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

// Walk /providers and find the pid whose sub_licenses contains the given code.
// Used for receiver-side auth where the EA only knows its license_code.
async function findProviderByLicenseCode(code) {
  const snap = await db.ref("/providers").get();
  if (!snap.exists()) return null;
  const all = snap.val();
  for (const pid of Object.keys(all)) {
    const subs = all[pid]?.sub_licenses;
    if (subs && Object.prototype.hasOwnProperty.call(subs, code)) {
      return { pid, data: all[pid], license: subs[code] };
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
  return { ok: true };
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

async function writeReceiverAck(pid, licenseCode, license, payload) {
  // The receiver's EA is acknowledging it picked up a signal / is live.
  // payload: { account: "123456", broker: "ICMarkets", last_seq_received: 1487 }
  const acct = payload?.account;
  if (!acct || typeof acct !== "string") return { err: "bad_payload", details: "account required" };
  const now = Date.now();

  // Enforce free-tier cap: if this license has never activated AND total
  // currently-active sub_licenses for this provider is already at the cap,
  // reject.
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
  await db.ref(`/providers/${pid}/receivers/${acct}`).update({
    state: "active",
    bound_broker: typeof payload.broker === "string" ? payload.broker.slice(0, 64) : null,
    license_code: licenseCode,
    activated_at: license.activated_at || now,
    last_seen_at: now
  });

  return { ok: true };
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

      const { pid, ea_key, license_code, kind, payload } = body || {};

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
        // Receiver path: needs {license_code}
        if (!license_code || typeof license_code !== "string" || license_code.length < 4 || license_code.length > 64) {
          return err(res, 400, "bad_license_code");
        }
        const found = await findProviderByLicenseCode(license_code);
        if (!found) return err(res, 404, "license_not_found");
        if (found.license.state === "revoked") return err(res, 403, "license_revoked");
        if (found.license.state === "expired") return err(res, 403, "license_expired");

        if (!checkRate(`lic:${license_code}`)) return err(res, 429, "rate_limited");

        if (kind === "receiver_ack") {
          const result = await writeReceiverAck(found.pid, license_code, found.license, payload);
          if (result?.err) return err(res, result.err === "cap_exceeded" ? 403 : 400, result.err, result.details);
          return ok(res, { pid: found.pid });
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

      const { license_code } = params;
      const last_seq = Number(params.last_seq) || 0;

      if (!license_code || typeof license_code !== "string") return err(res, 400, "bad_license_code");

      const found = await findProviderByLicenseCode(license_code);
      if (!found) return err(res, 404, "license_not_found");
      if (found.license.state === "revoked") return err(res, 403, "license_revoked");
      if (found.license.state === "expired") return err(res, 403, "license_expired");

      if (!checkRate(`read:${license_code}`)) return err(res, 429, "rate_limited");

      // Pull signals with seq > last_seq
      const snap = await db.ref(`/providers/${found.pid}/signals`)
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

      return ok(res, { pid: found.pid, signals, latest_seq });
    } catch (e) {
      console.error("[eaRead] uncaught:", e);
      return err(res, 500, "internal", e?.message);
    }
  }
);
