// ── NAVIGATOR ALGO · CLOUD FUNCTIONS ──
//
// HTTPS endpoints for MT5 EAs. MT5's MQL5 language can't easily do Firebase
// Auth, and hitting Realtime Database REST with the legacy database secret
// grants full-DB access — unacceptable. These functions validate a
// per-provider `ea_key` (or a per-receiver `license_code`) and then write
// to the DB using the admin SDK, bypassing client-side rules.
//
// Endpoints:
//   POST /eaWrite  — provider pushes signals/stats/heartbeats; receiver acks
//   POST /eaRead   — receiver polls for new signals since last_seq
//
// Contract shape (both endpoints):
//   Request:  application/json  { ...see handlers }
//   Response: application/json  { ok: true, ... } | { ok: false, error: "...", details?: "..." }
//   All error responses keep ok:false and a stable `error` code so the EA
//   can branch on it (bad_ea_key, provider_not_found, cap_exceeded, …).
//
// Deployed to: https://us-central1-signal-provider-pro.cloudfunctions.net/{eaWrite,eaRead}

const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase, ServerValue } = require("firebase-admin/database");

initializeApp();
const db = getDatabase();

// ── CONFIG ──

const REGION = "us-central1";
const FREE_LICENSE_CAP = 10;           // 10 active sub-licenses per provider for the free tier.
const AUTO_MINT_COUNT = 10;            // number of sub-license codes auto-generated on first heartbeat.
const SUB_LICENSE_PREFIX = "SUB-";     // matches LICENSE_PREFIXES.subLicense in firebase-config.js. Free Partner Receiver only.
const REC_LICENSE_PREFIX = "REC-";     // matches LICENSE_PREFIXES.receiverPaid. Paid Pro Receiver (MQL5 Market), stored at /rec_licenses/{code}.
const SUB_LICENSE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I/L — unambiguous when spoken.
const SIGNAL_READ_LIMIT = 50;          // max signals returned per eaRead call.
const MAX_BODY_BYTES = 16 * 1024;      // 16 KB cap on request body (EA payloads are ~1 KB).
const RATE_LIMIT_WINDOW_MS = 10_000;   // 10 s window …
const RATE_LIMIT_MAX = 50;             // … 50 writes per pid per window.

const VALID_KINDS_PROVIDER = new Set(["signal", "heartbeat", "stat"]);
const VALID_KINDS_RECEIVER = new Set(["receiver_ack"]);
const ALL_KINDS = new Set([...VALID_KINDS_PROVIDER, ...VALID_KINDS_RECEIVER]);

// ── IN-MEMORY RATE LIMIT ──
// Loose per-instance. Adequate for v1; upgrade to Firestore-backed token
// bucket if we ever see sustained abuse.
const rateBuckets = new Map();

function checkRate(key) {
  const now = Date.now();
  let bucket = rateBuckets.get(key);
  if (!bucket || now - bucket.windowStart > RATE_LIMIT_WINDOW_MS) {
    bucket = { windowStart: now, count: 0 };
    rateBuckets.set(key, bucket);
  }
  bucket.count += 1;
  if (rateBuckets.size > 10_000) {
    // crude eviction: drop the oldest ~half on overflow
    const cutoff = now - RATE_LIMIT_WINDOW_MS;
    for (const [k, v] of rateBuckets) {
      if (v.windowStart < cutoff) rateBuckets.delete(k);
    }
  }
  return bucket.count <= RATE_LIMIT_MAX;
}

// ── HELPERS ──

function err(res, httpStatus, code, details) {
  const body = { ok: false, error: code };
  if (details) body.details = String(details).slice(0, 500);
  return res.status(httpStatus).json(body);
}

function ok(res, extra = {}) {
  return res.status(200).json({ ok: true, server_ts: Date.now(), ...extra });
}

// Credential strings (pid, ea_key, license_code) are always generated in the
// client as uppercase ASCII with no internal whitespace. EAs or humans may
// paste them in with a stray trailing newline / space or in lower-case —
// normalize once at the edge so a rotated key never 401s for a cosmetic reason.
function normCred(v) {
  if (typeof v !== "string") return v;
  return v.trim().toUpperCase();
}

async function readJsonBody(req) {
  // onRequest auto-parses JSON when Content-Type is application/json, but we
  // defensively re-read raw and parse to enforce size cap.
  if (req.body && typeof req.body === "object" && !Array.isArray(req.body)) {
    return req.body;
  }
  if (typeof req.body === "string") {
    if (req.body.length > MAX_BODY_BYTES) throw new Error("body_too_large");
    try { return JSON.parse(req.body); } catch { throw new Error("bad_json"); }
  }
  throw new Error("bad_json");
}

// Resolve a license_code presented by a receiver EA to the signal provider it
// should follow + the license record used for state/expiry checks. Routes by
// prefix so the two receiver products stay properly separated:
//
//   SUB-XXXXXXXX — free Partner Receiver. Code is one of a provider's 10 free
//                  slots; provider owns it; lookup scans /providers/{pid}/sub_licenses.
//   REC-XXXXXXXX — paid Pro Receiver (MQL5 Market). Code is user-owned,
//                  time-limited, independent of any provider's cap. Looked up
//                  directly at /rec_licenses/{code}; the receiver picked which
//                  provider to follow at first activation (following_pid).
//
// Returns a normalized shape:
//   { kind: "sub" | "rec", pid, data?, license }
// or null if the code doesn't resolve.
async function findLicense(code) {
  if (typeof code !== "string") return null;
  if (code.startsWith(REC_LICENSE_PREFIX)) {
    const snap = await db.ref(`/rec_licenses/${code}`).get();
    if (!snap.exists()) return null;
    const license = snap.val();
    return { kind: "rec", pid: license.following_pid || null, license };
  }
  // Default path (includes SUB- and any legacy codes without prefix).
  const snap = await db.ref("/providers").get();
  if (!snap.exists()) return null;
  const all = snap.val();
  for (const pid of Object.keys(all)) {
    const subs = all[pid]?.sub_licenses;
    if (subs && Object.prototype.hasOwnProperty.call(subs, code)) {
      return { kind: "sub", pid, data: all[pid], license: subs[code] };
    }
  }
  return null;
}

async function validateProviderAuth(pid, eaKey) {
  if (!pid || typeof pid !== "string" || !/^NAV-[A-Z0-9]{3,10}$/.test(pid)) {
    return { err: "bad_pid" };
  }
  if (!eaKey || typeof eaKey !== "string" || eaKey.length < 8 || eaKey.length > 64) {
    return { err: "bad_ea_key" };
  }
  const snap = await db.ref(`/providers/${pid}`).get();
  if (!snap.exists()) return { err: "provider_not_found" };
  const data = snap.val();
  if (!data.ea_key) return { err: "provider_has_no_ea_key" };
  if (data.ea_key !== eaKey) return { err: "bad_ea_key" };
  return { ok: true, pid, data };
}

// ── WRITER HANDLERS ──

async function writeSignal(pid, payload) {
  // Append under /providers/{pid}/signals with auto-id. Also bump stats.
  const required = ["symbol", "side", "lots"];
  for (const k of required) {
    if (!(k in payload)) return { err: "bad_payload", details: `missing ${k}` };
  }
  if (!["buy", "sell"].includes(payload.side)) {
    return { err: "bad_payload", details: "side must be buy or sell" };
  }

  // Atomically allocate the next sequence number. Receivers filter signals
  // where seq > last_seq so they never re-pick an already-acted trade, even
  // if push-key ordering were to ever drift (clock skew etc).
  const seqRef = db.ref(`/providers/${pid}/stats/next_seq`);
  const txn = await seqRef.transaction((cur) => (typeof cur === "number" ? cur + 1 : 1));
  if (!txn.committed) return { err: "internal", details: "seq alloc failed" };
  const seq = txn.snapshot.val();

  const now = Date.now();
  const record = {
    ...payload,
    seq,
    server_ts: now
  };
  const ref = db.ref(`/providers/${pid}/signals`).push();
  await ref.set(record);

  // Bump total_signals and last_signal_at on the stats node.
  await db.ref(`/providers/${pid}/stats`).update({
    last_signal_at: now,
    total_signals: ServerValue.increment(1)
  });

  return { ok: true, auto_id: ref.key, seq };
}

async function writeHeartbeat(pid, payload) {
  await db.ref(`/providers/${pid}/heartbeat`).set(Date.now());
  if (payload && typeof payload === "object") {
    const meta = {};
    if (typeof payload.ea_version === "string") meta.ea_version = payload.ea_version.slice(0, 32);
    if (typeof payload.mt5_build === "number")  meta.mt5_build  = payload.mt5_build | 0;
    if (Object.keys(meta).length) {
      await db.ref(`/providers/${pid}/heartbeat_meta`).update(meta);
    }
  }
  // First heartbeat auto-mints the 10 free sub-license slots. Idempotent via
  // transaction: if sub_licenses already exists (any state), we abort and noop.
  // Also safely racy across parallel heartbeats — transaction guarantees a
  // single writer.
  await ensureSubLicensesMinted(pid);
  return { ok: true };
}

// Generates a SUB-XXXXXXXX code from an unambiguous alphabet. Per-code collision
// probability within one 10-code batch is ~negligible (32^8 ≈ 1.1 trillion
// combinations). We de-dup within the batch regardless.
function generateSubLicenseCode() {
  const bytes = new Uint8Array(8);
  (globalThis.crypto || require("crypto").webcrypto).getRandomValues(bytes);
  let out = SUB_LICENSE_PREFIX;
  for (let i = 0; i < 8; i++) out += SUB_LICENSE_ALPHABET[bytes[i] % SUB_LICENSE_ALPHABET.length];
  return out;
}

async function ensureSubLicensesMinted(pid) {
  const ref = db.ref(`/providers/${pid}/sub_licenses`);
  const txn = await ref.transaction((current) => {
    if (current && typeof current === "object" && Object.keys(current).length > 0) {
      // Already minted (or partially populated by some other path). Abort.
      return;
    }
    const now = Date.now();
    const out = {};
    const seen = new Set();
    while (Object.keys(out).length < AUTO_MINT_COUNT) {
      const code = generateSubLicenseCode();
      if (seen.has(code)) continue;
      seen.add(code);
      out[code] = { state: "unused", created_at: now };
    }
    return out;
  });
  return txn.committed;
}

async function writeStat(pid, payload) {
  if (!payload || typeof payload !== "object") return { err: "bad_payload" };
  const allowed = ["active_copiers", "total_signals", "win_rate", "balance", "equity", "drawdown_pct"];
  const patch = {};
  for (const k of allowed) {
    if (k in payload && typeof payload[k] === "number" && Number.isFinite(payload[k])) {
      patch[k] = payload[k];
    }
  }
  if (!Object.keys(patch).length) return { err: "bad_payload", details: "no recognized stat fields" };
  patch.updated_at = Date.now();
  await db.ref(`/providers/${pid}/stats`).update(patch);
  return { ok: true };
}

// Free Partner Receiver (SUB- code) path. Enforces the provider's 10-slot cap
// on first activation, then writes the activation/heartbeat state under
// /providers/{pid}/sub_licenses/{code} + /providers/{pid}/receivers/{acct}.
async function writeReceiverAckSub(pid, licenseCode, license, payload) {
  const acct = payload?.account;
  if (!acct || typeof acct !== "string") return { err: "bad_payload", details: "account required" };
  const now = Date.now();

  // Enforce free-tier cap: if this license has never activated AND total
  // currently-active sub_licenses for this provider is already at the cap,
  // reject. Paid REC- receivers skip this check entirely — they don't consume
  // a provider slot.
  if (license.state === "unused" || !license.state) {
    const subsSnap = await db.ref(`/providers/${pid}/sub_licenses`).get();
    const subs = subsSnap.val() || {};
    const activeCount = Object.values(subs).filter((s) => s?.state === "active").length;
    if (activeCount >= FREE_LICENSE_CAP) {
      return { err: "cap_exceeded", details: `provider is at free-tier cap of ${FREE_LICENSE_CAP} active receivers` };
    }
  }

  // Activate the license node
  await db.ref(`/providers/${pid}/sub_licenses/${licenseCode}`).update({
    state: "active",
    bound_account: acct,
    bound_broker: typeof payload.broker === "string" ? payload.broker.slice(0, 64) : null,
    activated_at: license.activated_at || now,
    last_seen_at: now
  });

  // Write a receiver record keyed by account — useful for dashboard counts.
  // SUB- codes always resolve to tier:"free". The EA-reported `tier` field is
  // ignored now that the prefix itself encodes the product.
  const ea = (typeof payload.ea === "string") ? payload.ea.slice(0, 64) : null;
  const recUpdate = {
    state: "active",
    bound_broker: typeof payload.broker === "string" ? payload.broker.slice(0, 64) : null,
    license_code: licenseCode,
    tier: "free",
    activated_at: license.activated_at || now,
    last_seen_at: now
  };
  if (ea) recUpdate.ea = ea;
  await db.ref(`/providers/${pid}/receivers/${acct}`).update(recUpdate);

  return { ok: true };
}

// REC- licenses pick which provider to follow at first activation and pin it
// server-side. Both eaRead and receiver_ack can do that activation: whichever
// call arrives first carrying a valid pid_to_follow wins. Subsequent calls
// must match or they get pid_mismatch.
//
// Returns { err?, details?, followingPid?, didPin? }:
//   didPin=true means this call just set following_pid on the license, and
//   the caller should persist the rest of the state (activated_at etc.) too.
async function resolveAndMaybePinPid(licenseCode, currentFollowingPid, requestedPidRaw, opts = {}) {
  const { requirePid = false } = opts;
  const requestedPid = typeof requestedPidRaw === "string"
    ? requestedPidRaw.trim().toUpperCase()
    : null;

  if (currentFollowingPid) {
    if (requestedPid && requestedPid !== currentFollowingPid) {
      return { err: "pid_mismatch", details: `license is already pinned to ${currentFollowingPid}; contact support to change providers` };
    }
    return { followingPid: currentFollowingPid, didPin: false };
  }

  // Not pinned yet.
  if (!requestedPid) {
    if (!requirePid) return { followingPid: null, didPin: false };
    return { err: "bad_payload", details: "pid_to_follow required on first activation (NAV-XXXX format)" };
  }
  if (!/^NAV-[A-Z0-9]{3,10}$/.test(requestedPid)) {
    return { err: "bad_payload", details: `pid_to_follow ${requestedPid} is not a valid NAV-XXXX id` };
  }
  // Verify the provider exists before pinning; a user typo shouldn't brick
  // the license until admin intervention.
  const provSnap = await db.ref(`/providers/${requestedPid}`).get();
  if (!provSnap.exists()) return { err: "provider_not_found", details: `pid_to_follow ${requestedPid} does not exist` };

  await db.ref(`/rec_licenses/${licenseCode}/following_pid`).set(requestedPid);
  return { followingPid: requestedPid, didPin: true };
}

// Paid Pro Receiver (REC- code) path. License lives at /rec_licenses/{code}
// and is independent of any provider's free-tier cap. On first activation the
// receiver must pick a provider to follow via payload.pid_to_follow OR have
// it already pinned by a previous eaRead call; that PID cannot be silently
// switched thereafter — an explicit admin rotation is required.
async function writeReceiverAckRec(licenseCode, license, payload) {
  const acct = payload?.account;
  if (!acct || typeof acct !== "string") return { err: "bad_payload", details: "account required" };
  const now = Date.now();

  // Enforce expiry. If the license has an expires_at in the past, flip state
  // to "expired" so future lookups can short-circuit without re-checking the
  // clock, and reject.
  if (typeof license.expires_at === "number" && license.expires_at > 0 && license.expires_at < now) {
    if (license.state !== "expired") {
      await db.ref(`/rec_licenses/${licenseCode}/state`).set("expired");
    }
    return { err: "license_expired" };
  }

  // Pin the provider if needed. receiver_ack requires a pid the first time
  // through; if eaRead already pinned one, requestedPid is optional (and just
  // verified for consistency).
  const pinResult = await resolveAndMaybePinPid(
    licenseCode,
    license.following_pid || null,
    payload.pid_to_follow,
    { requirePid: true }
  );
  if (pinResult.err) return pinResult;
  const followingPid = pinResult.followingPid;

  // Update the license node
  await db.ref(`/rec_licenses/${licenseCode}`).update({
    state: "active",
    bound_account: acct,
    bound_broker: typeof payload.broker === "string" ? payload.broker.slice(0, 64) : null,
    following_pid: followingPid,
    activated_at: license.activated_at || now,
    last_seen_at: now
  });

  // Mirror as a "paid" receiver under the followed provider so it shows up in
  // that provider's dashboard counts + admin analytics.
  const ea = (typeof payload.ea === "string") ? payload.ea.slice(0, 64) : null;
  const recUpdate = {
    state: "active",
    bound_broker: typeof payload.broker === "string" ? payload.broker.slice(0, 64) : null,
    license_code: licenseCode,
    tier: "paid",
    activated_at: license.activated_at || now,
    last_seen_at: now
  };
  if (ea) recUpdate.ea = ea;
  await db.ref(`/providers/${followingPid}/receivers/${acct}`).update(recUpdate);

  return { ok: true, pid: followingPid };
}

// ── ENDPOINT: eaWrite ──

exports.eaWrite = onRequest(
  { region: REGION, cors: false, timeoutSeconds: 20, memory: "256MiB", maxInstances: 20 },
  async (req, res) => {
    try {
      if (req.method !== "POST") return err(res, 405, "method_not_allowed");

      let body;
      try { body = await readJsonBody(req); }
      catch (e) { return err(res, 400, e.message || "bad_json"); }

      const pid          = normCred(body?.pid);
      const ea_key       = normCred(body?.ea_key);
      const license_code = normCred(body?.license_code);
      const { kind, payload } = body || {};

      if (!kind || !ALL_KINDS.has(kind)) return err(res, 400, "bad_kind", `kind must be one of ${[...ALL_KINDS].join(", ")}`);
      if (!payload || typeof payload !== "object") return err(res, 400, "bad_payload", "payload object required");

      if (VALID_KINDS_PROVIDER.has(kind)) {
        // Provider path: needs {pid, ea_key}
        const auth = await validateProviderAuth(pid, ea_key);
        if (auth.err) return err(res, auth.err === "provider_not_found" ? 404 : 401, auth.err);

        if (!checkRate(`pid:${pid}`)) return err(res, 429, "rate_limited");

        let result;
        if (kind === "signal")    result = await writeSignal(pid, payload);
        if (kind === "heartbeat") result = await writeHeartbeat(pid, payload);
        if (kind === "stat")      result = await writeStat(pid, payload);
        if (result?.err) return err(res, 400, result.err, result.details);
        return ok(res, result.auto_id ? { auto_id: result.auto_id } : {});
      }

      if (VALID_KINDS_RECEIVER.has(kind)) {
        // Receiver path: needs {license_code}. Routed by prefix — SUB- goes to
        // the free Partner Receiver flow (provider-owned slot), REC- to the
        // paid Pro Receiver flow (user-owned, time-limited, picks which
        // provider to follow at first activation).
        if (!license_code || typeof license_code !== "string" || license_code.length < 4 || license_code.length > 64) {
          return err(res, 400, "bad_license_code");
        }
        const found = await findLicense(license_code);
        if (!found) return err(res, 404, "license_not_found");
        if (found.license.state === "revoked") return err(res, 403, "license_revoked");
        if (found.license.state === "expired") return err(res, 403, "license_expired");

        if (!checkRate(`lic:${license_code}`)) return err(res, 429, "rate_limited");

        if (kind === "receiver_ack") {
          const result = found.kind === "rec"
            ? await writeReceiverAckRec(license_code, found.license, payload)
            : await writeReceiverAckSub(found.pid, license_code, found.license, payload);
          if (result?.err) {
            const status = result.err === "cap_exceeded" ? 403
                         : result.err === "license_expired" ? 403
                         : result.err === "provider_not_found" ? 404
                         : 400;
            return err(res, status, result.err, result.details);
          }
          return ok(res, { pid: result.pid || found.pid });
        }
      }

      return err(res, 400, "bad_kind");
    } catch (e) {
      console.error("[eaWrite] uncaught:", e);
      return err(res, 500, "internal", e?.message);
    }
  }
);

// ── ENDPOINT: eaRead ──
//
// Receiver polls with: { license_code, last_seq }
// Returns signals where seq > last_seq, ordered ascending, limited to
// SIGNAL_READ_LIMIT. Receiver stores the max seq it's seen to filter idempotently.

exports.eaRead = onRequest(
  { region: REGION, cors: false, timeoutSeconds: 15, memory: "256MiB", maxInstances: 20 },
  async (req, res) => {
    try {
      if (req.method !== "POST" && req.method !== "GET") return err(res, 405, "method_not_allowed");

      let params = {};
      if (req.method === "POST") {
        try { params = await readJsonBody(req); }
        catch (e) { return err(res, 400, e.message || "bad_json"); }
      } else {
        params = req.query || {};
      }

      const license_code = normCred(params.license_code);
      const last_seq = Number(params.last_seq) || 0;
      // pid_to_follow is REC--only. The Pro Receiver sends its configured
      // provider on every read so activation happens on whichever of
      // eaRead/receiver_ack lands first (receiver_ack is only emitted after a
      // signal execution, so a fresh receiver with no copied trades would
      // otherwise deadlock waiting for activation).
      const pid_to_follow = typeof params.pid_to_follow === "string" ? params.pid_to_follow : null;

      if (!license_code || typeof license_code !== "string") return err(res, 400, "bad_license_code");

      const found = await findLicense(license_code);
      if (!found) return err(res, 404, "license_not_found");
      if (found.license.state === "revoked") return err(res, 403, "license_revoked");
      if (found.license.state === "expired") return err(res, 403, "license_expired");

      // REC- licenses enforce expiry on every read too, not just on activation,
      // so a paid receiver whose subscription lapses stops polling within
      // a single round-trip even if the background "expire" sweep hasn't run.
      if (found.kind === "rec" && typeof found.license.expires_at === "number"
          && found.license.expires_at > 0 && found.license.expires_at < Date.now()) {
        await db.ref(`/rec_licenses/${license_code}/state`).set("expired");
        return err(res, 403, "license_expired");
      }

      // A REC- code that hasn't activated yet has no following_pid. Try to
      // pin it now using the pid_to_follow from this request; if the Pro EA
      // sends one, we activate transparently without needing receiver_ack.
      let readPid = found.pid;
      if (found.kind === "rec" && !readPid) {
        const pinResult = await resolveAndMaybePinPid(
          license_code, null, pid_to_follow,
          { requirePid: true }
        );
        if (pinResult.err) {
          const status = pinResult.err === "provider_not_found" ? 404
                       : pinResult.err === "bad_payload"        ? 400
                       : 409;
          return err(res, status, pinResult.err, pinResult.details);
        }
        readPid = pinResult.followingPid;
        if (pinResult.didPin) {
          // Mark license as active + stamp activated_at. receiver_ack will
          // fill in bound_account/broker later when the first trade copies.
          await db.ref(`/rec_licenses/${license_code}`).update({
            state: "active",
            activated_at: found.license.activated_at || Date.now(),
            last_seen_at: Date.now()
          });
        }
      } else if (found.kind === "rec" && pid_to_follow) {
        // Already pinned — verify the Pro EA's configured pid still matches.
        const check = await resolveAndMaybePinPid(license_code, readPid, pid_to_follow);
        if (check.err) {
          const status = check.err === "pid_mismatch" ? 400 : 409;
          return err(res, status, check.err, check.details);
        }
        // Pre-pinned codes (typically provider-minted, where following_pid is
        // set at mint time) are born state="unused" and would otherwise stay
        // that way on the dashboard until the first receiver_ack fires after
        // a trade copy. Flip to "active" on first successful read so the
        // admin + provider dashboards reflect reality earlier.
        if (found.license.state === "unused") {
          db.ref(`/rec_licenses/${license_code}`).update({
            state: "active",
            activated_at: found.license.activated_at || Date.now(),
            last_seen_at: Date.now()
          }).catch(() => {});
        } else {
          // Refresh last_seen_at so an idle-but-connected Pro Receiver is
          // still visible on the dashboard.
          db.ref(`/rec_licenses/${license_code}/last_seen_at`).set(Date.now()).catch(() => {});
        }
      }

      // Any non-REC path without a pid is a data-integrity bug, not a user
      // error; shouldn't happen because SUB- licenses inherit pid from the
      // enclosing provider.
      if (!readPid) return err(res, 500, "internal", "no pid resolved");

      if (!checkRate(`read:${license_code}`)) return err(res, 429, "rate_limited");

      // Pull signals with seq > last_seq
      const snap = await db.ref(`/providers/${readPid}/signals`)
        .orderByChild("seq")
        .startAfter(last_seq)
        .limitToFirst(SIGNAL_READ_LIMIT)
        .get();

      const signals = [];
      snap.forEach((child) => {
        const v = child.val() || {};
        signals.push({ id: child.key, ...v });
      });

      let latest_seq = last_seq;
      for (const s of signals) if (typeof s.seq === "number" && s.seq > latest_seq) latest_seq = s.seq;

      return ok(res, { pid: readPid, signals, latest_seq });
    } catch (e) {
      console.error("[eaRead] uncaught:", e);
      return err(res, 500, "internal", e?.message);
    }
  }
);
