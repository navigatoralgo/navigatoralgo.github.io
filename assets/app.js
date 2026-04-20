// ── NAVIGATOR ALGO · FIREBASE APP BOOTSTRAP ──
// Thin wrapper around Firebase SDK v10 for auth + realtime database access.
// Used by: /signin.html, /dashboard.html, /receiver-download.html

import { initializeApp }        from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signOut, updateProfile,
  sendSignInLinkToEmail, isSignInWithEmailLink, signInWithEmailLink,
  GoogleAuthProvider, signInWithPopup, signInWithRedirect, getRedirectResult
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";
import {
  getDatabase, ref, get, set, update, remove, onValue, runTransaction, serverTimestamp
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js";

import { firebaseConfig, DB_PATHS, LICENSE_PREFIXES, SUB_LICENSES_PER_PROVIDER } from "./firebase-config.js";

// ── CONFIG SANITY CHECK ──
// Fail loudly at boot if the user forgot to edit firebase-config.js.
// This prevents cryptic Firebase errors later.
if (firebaseConfig.apiKey.includes("__REPLACE_")) {
  console.error(
    "[Navigator Algo] Firebase config not set.\n" +
    "Edit /assets/firebase-config.js with your project's values before the dashboard will work."
  );
}

// ── INIT ──
const app  = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db   = getDatabase(app);

// Sign-in link settings — the magic-link redirect lands back on /signin.html
// which finishes the sign-in by calling `completeEmailLinkSignIn()`.
const emailLinkSettings = {
  url: window.location.origin + "/signin.html",
  handleCodeInApp: true
};

// ── AUTH HELPERS ──

export function watchAuth(onSignedIn, onSignedOut) {
  return onAuthStateChanged(auth, (user) => {
    if (user) onSignedIn(user);
    else onSignedOut();
  });
}

export async function sendMagicLink(email) {
  await sendSignInLinkToEmail(auth, email, emailLinkSettings);
  // Remember the email so we can finish sign-in on the return visit
  // without prompting for it again.
  window.localStorage.setItem("pendingSignInEmail", email);
}

export async function completeEmailLinkSignIn() {
  if (!isSignInWithEmailLink(auth, window.location.href)) return null;
  let email = window.localStorage.getItem("pendingSignInEmail");
  if (!email) {
    email = window.prompt("Please confirm the email address you used to sign in:");
  }
  if (!email) return null;
  const result = await signInWithEmailLink(auth, email, window.location.href);
  window.localStorage.removeItem("pendingSignInEmail");
  return result.user;
}

export async function signInWithGoogle() {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });
  try {
    const result = await signInWithPopup(auth, provider);
    return result.user;
  } catch (err) {
    // Popup blocked or closed → fall back to redirect flow (more reliable on
    // mobile + strict popup-blocker setups). Redirect navigates away from the
    // page; getRedirectResult() on return picks it up (handled in signin.html).
    if (err && (err.code === "auth/popup-blocked" || err.code === "auth/cancelled-popup-request")) {
      await signInWithRedirect(auth, provider);
      return null; // page will navigate; caller should not rely on a user being returned
    }
    throw err;
  }
}

// Called on /signin.html load to complete a redirect-based Google sign-in, if any.
export async function completeGoogleRedirect() {
  try {
    const result = await getRedirectResult(auth);
    return result ? result.user : null;
  } catch (err) {
    console.error("[Navigator Algo] getRedirectResult failed:", err);
    throw err;
  }
}

export async function signOutUser() {
  await signOut(auth);
}

// ── USER PROFILE HELPERS ──
// Stored at /users/{uid} per the Firebase security rules.
// Schema:
//   /users/{uid}/email        — mirror of auth email
//   /users/{uid}/display_name — optional friendly name (user-editable)
//   /users/{uid}/provider_id  — "NAV-XXXX" once EA is claimed
//   /users/{uid}/created_at   — server timestamp on first sign-in
//   /users/{uid}/last_seen_at — server timestamp refreshed each sign-in

export async function getUserProfile(uid) {
  const snap = await get(ref(db, `users/${uid}`));
  return snap.exists() ? snap.val() : null;
}

// Idempotent — creates /users/{uid} with basic info on first sign-in,
// refreshes last_seen_at on every subsequent load.
export async function touchUserProfile(user) {
  const updates = {
    [`users/${user.uid}/email`]:        user.email || null,
    [`users/${user.uid}/last_seen_at`]: serverTimestamp()
  };
  const existing = await get(ref(db, `users/${user.uid}`));
  if (!existing.exists()) {
    updates[`users/${user.uid}/created_at`] = serverTimestamp();
    if (user.displayName) updates[`users/${user.uid}/display_name`] = user.displayName;
  }
  await update(ref(db), updates);
}

// Writes the user's editable profile fields.
// Mirrors display_name onto the Firebase Auth user so other pages can read it
// straight from the auth object without a DB roundtrip.
export async function saveUserProfile(user, { display_name, phone, country, notes }) {
  const updates = {};
  if (display_name !== undefined) updates[`users/${user.uid}/display_name`] = display_name || null;
  if (phone        !== undefined) updates[`users/${user.uid}/phone`]        = phone || null;
  if (country      !== undefined) updates[`users/${user.uid}/country`]      = country || null;
  if (notes        !== undefined) updates[`users/${user.uid}/notes`]        = notes || null;
  updates[`users/${user.uid}/updated_at`] = serverTimestamp();
  await update(ref(db), updates);

  if (display_name !== undefined && user.displayName !== display_name) {
    try { await updateProfile(user, { displayName: display_name || null }); }
    catch (e) { console.warn("[Navigator Algo] updateProfile on auth user failed:", e); }
  }
}

// ── ADMIN HELPERS ──
// An admin is any user whose UID is set to `true` at /admins/{uid}.
// Set this manually in the Firebase console (Realtime Database → Data).
// Admins can mint new provider IDs + list all providers from /admin.html.

export async function isAdmin(uid) {
  try {
    const snap = await get(ref(db, `admins/${uid}`));
    return snap.exists() && snap.val() === true;
  } catch (err) {
    // Rules allow a user to read their own /admins/{uid}; any other outcome
    // (network error, rules not published) is treated as "not admin".
    console.warn("[Navigator Algo] isAdmin check failed:", err?.code || err?.message || err);
    return false;
  }
}

// Generate a short, human-friendly provider ID like "NAV-7K3Q9".
// Uses an alphabet without visually-confusing characters (0/O, 1/I/L).
const PROVIDER_ID_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
function randomProviderId() {
  const bytes = new Uint8Array(5);
  crypto.getRandomValues(bytes);
  let s = "";
  for (let i = 0; i < bytes.length; i++) {
    s += PROVIDER_ID_ALPHABET[bytes[i] % PROVIDER_ID_ALPHABET.length];
  }
  return `NAV-${s}`;
}

// Claim token: 12 hex chars in three groups of 4, e.g. "9F3A-1C77-B204".
// One-shot secret used by a human to bind their Firebase account to a provider
// node. Cleared after claim.
function randomClaimToken() {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0").toUpperCase()).join("");
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}`;
}

// EA key: 16 hex chars in four groups of 4, e.g. "4F72-91A0-BC33-8E12".
// Long-lived machine secret — pasted into the EA's inputs on the provider's
// MT5 terminal. Authenticates every eaWrite/eaRead Cloud Function call. Does
// NOT grant Firebase Auth session — the function validates this key server-
// side and uses admin SDK to write.
export function randomEaKey() {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0").toUpperCase()).join("");
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}`;
}

// Admin-only: mints a new (provider_id, claim_token, ea_key) triple and writes
// it to /providers/{pid} with no owner_uid. Retries up to 5 times on
// provider_id collision (astronomically unlikely with 31^5 ≈ 28M combinations).
// Returns { providerId, claimToken, eaKey }.
export async function mintProvider(adminUser, opts = {}) {
  const { display_name = null, license = "navigator-algo" } = opts;

  for (let attempt = 0; attempt < 5; attempt++) {
    const providerId  = randomProviderId();
    const claimToken  = randomClaimToken();
    const eaKey       = randomEaKey();
    const existing = await get(providerRef(providerId));
    if (existing.exists()) continue;

    await set(providerRef(providerId), {
      claim_token:    claimToken,
      ea_key:         eaKey,
      license:        license,
      display_name:   display_name,
      created_at:     Date.now(),
      created_by_uid: adminUser.uid
    });
    return { providerId, claimToken, eaKey };
  }
  throw new Error("Could not mint a unique provider ID after 5 attempts. Try again.");
}

// Provider-owner or admin: rotate ea_key on an existing provider. Old key
// stops working immediately; EA on the provider's MT5 must be reconfigured.
// Returns the new eaKey string.
export async function regenerateEaKey(user, providerId) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();
  const isOwner = data.owner_uid === user.uid;
  const admin = await isAdmin(user.uid);
  if (!isOwner && !admin) throw new Error("Only the provider's owner (or an admin) can rotate the EA key.");

  const eaKey = randomEaKey();
  await update(providerRef(providerId), { ea_key: eaKey, ea_key_rotated_at: Date.now() });
  return eaKey;
}

// Random SUB- sub-license code, 8 chars from an unambiguous alphabet
// (no 0/O/1/I/L). 32^8 ≈ 1.1T combinations so in-batch collisions are
// astronomically rare; we de-dup within the batch anyway. Same format the
// Cloud Function's auto-mint path produces on first heartbeat.
function randomSubLicenseCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  let out = LICENSE_PREFIXES.subLicense;
  for (let i = 0; i < 8; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

// Provider-owner: revoke a sub-license. Flips its state to "revoked" (so the
// Cloud Function's eaRead / eaWrite receiver paths both reject it on the next
// poll, within ~1 s) and clears the bound account/broker so the slot can be
// reused by a fresh unused code later. Also flips the /receivers/{acct} record
// to "inactive" so the Active Copiers KPI on the dashboard drops immediately.
export async function revokeSubLicense(user, providerId, code) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();
  const isOwner = data.owner_uid === user.uid;
  const admin = await isAdmin(user.uid);
  if (!isOwner && !admin) throw new Error("Only the provider's owner (or an admin) can revoke a sub-license.");

  const subs = data.sub_licenses || {};
  const license = subs[code];
  if (!license) throw new Error(`Sub-license ${code} not found.`);

  const boundAcct = license.bound_account || null;
  const updates = {
    [`${DB_PATHS.providers}/${providerId}/sub_licenses/${code}/state`]:         "revoked",
    [`${DB_PATHS.providers}/${providerId}/sub_licenses/${code}/bound_account`]: null,
    [`${DB_PATHS.providers}/${providerId}/sub_licenses/${code}/bound_broker`]:  null
  };
  if (boundAcct) {
    updates[`${DB_PATHS.providers}/${providerId}/receivers/${boundAcct}/state`] = "inactive";
  }
  await update(ref(db), updates);
}

// Provider-owner: rotate a sub-license. Deletes the old code entirely from the
// database (stronger than revoke — no trace remains, so even a stale cache on
// the Cloud Function can't resurrect it) and mints a fresh SUB-XXXXXXXX code in
// its place with state="unused". Atomic multi-path update: if one leg fails the
// other won't go through. Returns the new code string.
export async function rotateSubLicense(user, providerId, oldCode) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();
  const isOwner = data.owner_uid === user.uid;
  const admin = await isAdmin(user.uid);
  if (!isOwner && !admin) throw new Error("Only the provider's owner (or an admin) can rotate a sub-license.");

  const subs = data.sub_licenses || {};
  const oldLicense = subs[oldCode];
  if (!oldLicense) throw new Error(`Sub-license ${oldCode} not found.`);

  // Generate a new code and make sure it doesn't collide with an existing one
  // (astronomically unlikely but cheap to check).
  let newCode;
  for (let i = 0; i < 8; i++) {
    const candidate = randomSubLicenseCode();
    if (!subs[candidate]) { newCode = candidate; break; }
  }
  if (!newCode) throw new Error("Could not generate a unique new code. Try again.");

  const boundAcct = oldLicense.bound_account || null;
  const now = Date.now();
  const updates = {
    // Delete the old code entirely — Firebase treats `null` as "remove this node".
    [`${DB_PATHS.providers}/${providerId}/sub_licenses/${oldCode}`]: null,
    // Mint the replacement.
    [`${DB_PATHS.providers}/${providerId}/sub_licenses/${newCode}`]: {
      state: "unused",
      created_at: now
    }
  };
  if (boundAcct) {
    // Clean up the receiver record — old receiver EA loses access on next poll.
    updates[`${DB_PATHS.providers}/${providerId}/receivers/${boundAcct}/state`] = "inactive";
  }
  await update(ref(db), updates);
  return newCode;
}

// Provider-owner: generate the batch of free sub-license slots on demand
// (via the dashboard, before the EA first connects). Idempotent — aborts if
// sub_licenses already contains any codes. Returns the number of codes minted
// (0 if already populated).
export async function generateSubLicenseSlots(user, providerId) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();
  const isOwner = data.owner_uid === user.uid;
  const admin = await isAdmin(user.uid);
  if (!isOwner && !admin) throw new Error("Only the provider's owner (or an admin) can generate sub-license slots.");

  const slotsRef = ref(db, `${DB_PATHS.providers}/${providerId}/sub_licenses`);
  const result = await runTransaction(slotsRef, (current) => {
    if (current && typeof current === "object" && Object.keys(current).length > 0) {
      return; // abort — already populated
    }
    const now = Date.now();
    const out = {};
    const seen = new Set();
    while (Object.keys(out).length < SUB_LICENSES_PER_PROVIDER) {
      const code = randomSubLicenseCode();
      if (seen.has(code)) continue;
      seen.add(code);
      out[code] = { state: "unused", created_at: now };
    }
    return out;
  });

  if (!result.committed) return 0;
  const written = result.snapshot.val() || {};
  return Object.keys(written).length;
}

// Admin-only: list all providers (for the admin page table).
// Returns an array of { providerId, data } sorted by created_at desc.
export async function listAllProviders() {
  const snap = await get(ref(db, DB_PATHS.providers));
  if (!snap.exists()) return [];
  const all = snap.val();
  return Object.keys(all)
    .map((pid) => ({ providerId: pid, data: all[pid] || {} }))
    .sort((a, b) => (b.data.created_at || 0) - (a.data.created_at || 0));
}

// Admin-only: roll up per-provider metrics into a single object for the admin
// KPI strip. Everything here is computed from data already pulled in
// listAllProviders — no extra network round-trips.
//
// Receiver "tier" is written by the Cloud Function from the receiver_ack
// payload (field: `tier`, values: "free" | "paid"). Legacy receivers that
// pre-date tier-tracking default to "free".
export function rollupAdminStats(rows) {
  const out = {
    providers_total:    0,
    providers_claimed:  0,
    providers_unclaimed:0,
    signals_total:      0,
    subs_total:         0,
    subs_unused:        0,
    subs_active:        0,
    subs_revoked:       0,
    subs_expired:       0,
    receivers_free:     0,
    receivers_paid:     0,
    receivers_active:   0
  };
  for (const r of rows) {
    out.providers_total++;
    const d = r.data || {};
    if (d.owner_uid) out.providers_claimed++;
    else             out.providers_unclaimed++;

    out.signals_total += Number(d?.stats?.total_signals) || 0;

    const subs = d.sub_licenses || {};
    for (const code in subs) {
      out.subs_total++;
      const state = subs[code]?.state || "unused";
      if (state === "unused")  out.subs_unused++;
      if (state === "active")  out.subs_active++;
      if (state === "revoked") out.subs_revoked++;
      if (state === "expired") out.subs_expired++;
    }

    const rec = d.receivers || {};
    for (const acct in rec) {
      const row = rec[acct] || {};
      if (row.state === "active") {
        out.receivers_active++;
        if (row.tier === "paid") out.receivers_paid++;
        else                     out.receivers_free++; // default + explicit "free"
      }
    }
  }
  return out;
}

// Admin-only: per-provider counts used for the admin table row. Same data
// source as rollupAdminStats; just narrowed to a single provider.
export function perProviderCounts(data) {
  const d = data || {};
  const signals = Number(d?.stats?.total_signals) || 0;
  const subs = d.sub_licenses || {};
  let subs_active = 0, subs_unused = 0;
  for (const c in subs) {
    const s = subs[c]?.state;
    if (s === "active") subs_active++;
    if (s === "unused" || !s) subs_unused++;
  }
  const rec = d.receivers || {};
  let free = 0, paid = 0;
  for (const a in rec) {
    const row = rec[a] || {};
    if (row.state !== "active") continue;
    if (row.tier === "paid") paid++; else free++;
  }
  return {
    signals,
    subs_active, subs_unused,
    receivers_free: free, receivers_paid: paid,
    last_heartbeat: d.heartbeat || null
  };
}

// Admin-only: permanently remove a provider and everything under it. Before
// wiping, snapshots the full subtree to /deleted_providers/{pid} with a
// `deleted_at` timestamp + `deleted_by_uid` for audit + undo. Keep snapshots
// around for ~30 days (manual cleanup for now; automated trim is a later PR).
//
// Security: rules gate both paths to admin-only writes. This function will
// throw PERMISSION_DENIED if the caller isn't in /admins.
export async function deleteProvider(adminUser, providerId) {
  if (!adminUser || !providerId) throw new Error("adminUser + providerId required");
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error(`Provider ${providerId} not found.`);
  const data = snap.val();

  const now = Date.now();
  const snapshot = {
    ...data,
    deleted_at: now,
    deleted_by_uid: adminUser.uid,
    deleted_by_email: adminUser.email || null
  };
  // Write archive first. If this fails (permission etc) we abort before
  // deleting the live record — no orphaned deletions.
  await set(ref(db, `deleted_providers/${providerId}`), snapshot);

  // Also clear the /users/{owner_uid}/provider_id pointer so the owner's
  // dashboard stops showing a stale claim. Best-effort; don't fail the whole
  // op if the owner entry doesn't exist.
  const ownerUid = data.owner_uid;
  if (ownerUid) {
    try { await remove(ref(db, `users/${ownerUid}/provider_id`)); }
    catch (e) { console.warn("[Navigator Algo] deleteProvider: failed to clear owner pointer", e); }
  }

  await remove(providerRef(providerId));
  return { archived_at: now };
}

// ── REC- (paid Pro Receiver) LICENSE HELPERS ──
//
// REC-XXXXXXXX codes are user-owned, time-limited licenses for the paid Pro
// Receiver EA sold on MQL5 Market. Unlike SUB- codes (which live under a
// provider's free 10-slot cap), REC- codes are independent: the buyer picks
// which provider to follow at first activation (that PID is pinned to the
// license server-side). Admins mint / revoke / expire / rotate these from
// /admin.html. Cloud Functions read /rec_licenses/{code} when an EA presents
// a REC- prefixed license.
//
// Schema at /rec_licenses/{code}:
//   state           "unused" | "active" | "revoked" | "expired"
//   created_at      number   (ms)
//   created_by_uid  string   (admin uid)
//   owner_email     string?  (buyer email from MQL5)
//   mql5_order_id   string?  (optional buyer-side receipt ref)
//   note            string?  (free-form admin note)
//   expires_at      number?  (ms; null = no expiry)
//   activated_at    number?  (ms; set on first receiver_ack)
//   last_seen_at    number?  (ms; bumped on each receiver_ack)
//   bound_account   string?  (MT5 account number from receiver_ack)
//   bound_broker    string?  (broker name from receiver_ack)
//   following_pid   string?  (pinned on first activation)

function recLicenseRef(code) {
  return ref(db, `rec_licenses/${code}`);
}

// Random REC- code, 8 chars from an unambiguous alphabet (no 0/O/1/I/L).
// 32^8 ≈ 1.1T combinations; in-batch collisions are astronomically rare,
// and the mint path re-tries on duplicates anyway.
function randomRecLicenseCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  let out = LICENSE_PREFIXES.receiverPaid;
  for (let i = 0; i < 8; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

// Admin-only: mint a new REC- license. Returns the license code + the full
// record that was written. Retries up to 5 times on collision. The minted
// code has state="unused" until a receiver_ack activates it.
//
// opts: { owner_email?, mql5_order_id?, note?, expires_at?, expires_in_days? }
//   Pass either expires_at (absolute ms) or expires_in_days (e.g. 90 for
//   3 months). If both are absent the license has no expiry.
export async function mintRecLicense(adminUser, opts = {}) {
  if (!adminUser) throw new Error("adminUser required");
  const now = Date.now();
  let expiresAt = null;
  if (typeof opts.expires_at === "number" && opts.expires_at > now) {
    expiresAt = opts.expires_at;
  } else if (typeof opts.expires_in_days === "number" && opts.expires_in_days > 0) {
    expiresAt = now + Math.floor(opts.expires_in_days * 24 * 60 * 60 * 1000);
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomRecLicenseCode();
    const existing = await get(recLicenseRef(code));
    if (existing.exists()) continue;

    const record = {
      state:          "unused",
      created_at:     now,
      created_by_uid: adminUser.uid
    };
    if (opts.owner_email)    record.owner_email   = String(opts.owner_email).slice(0, 256);
    if (opts.mql5_order_id)  record.mql5_order_id = String(opts.mql5_order_id).slice(0, 64);
    if (opts.note)           record.note          = String(opts.note).slice(0, 500);
    if (expiresAt)           record.expires_at    = expiresAt;

    await set(recLicenseRef(code), record);
    return { code, record };
  }
  throw new Error("Could not mint a unique REC- code after 5 attempts. Try again.");
}

// Admin-only: list every REC- license, newest first. Returns an array of
// { code, data } records. Use for the admin console table.
export async function listAllRecLicenses() {
  const snap = await get(ref(db, "rec_licenses"));
  if (!snap.exists()) return [];
  const all = snap.val();
  return Object.keys(all)
    .map((code) => ({ code, data: all[code] || {} }))
    .sort((a, b) => (b.data.created_at || 0) - (a.data.created_at || 0));
}

// Admin-only: flip a REC- license to "revoked". Next receiver poll returns
// 403 license_revoked within ~1 s. Does not delete the record so you can see
// the history in the admin console.
export async function revokeRecLicense(adminUser, code) {
  if (!adminUser || !code) throw new Error("adminUser + code required");
  const snap = await get(recLicenseRef(code));
  if (!snap.exists()) throw new Error(`REC license ${code} not found.`);
  const prev = snap.val() || {};
  const boundAcct = prev.bound_account;
  const followingPid = prev.following_pid;

  const updates = {
    [`rec_licenses/${code}/state`]: "revoked"
  };
  // Also mark the paid receiver row inactive on the provider's dashboard so
  // their Active Copiers count drops immediately.
  if (followingPid && boundAcct) {
    updates[`${DB_PATHS.providers}/${followingPid}/receivers/${boundAcct}/state`] = "inactive";
  }
  await update(ref(db), updates);
}

// Admin-only: extend (or set) a REC- license's expiry. Pass either
// new_expires_at (absolute ms) or extend_days (relative to the current
// expires_at, or to now if none was set). Useful for "buyer renewed" flows.
export async function updateRecLicenseExpiry(adminUser, code, opts = {}) {
  if (!adminUser || !code) throw new Error("adminUser + code required");
  const snap = await get(recLicenseRef(code));
  if (!snap.exists()) throw new Error(`REC license ${code} not found.`);
  const prev = snap.val() || {};

  let newExpiresAt = null;
  if (typeof opts.new_expires_at === "number" && opts.new_expires_at > 0) {
    newExpiresAt = opts.new_expires_at;
  } else if (typeof opts.extend_days === "number" && opts.extend_days > 0) {
    const base = typeof prev.expires_at === "number" && prev.expires_at > Date.now()
      ? prev.expires_at
      : Date.now();
    newExpiresAt = base + Math.floor(opts.extend_days * 24 * 60 * 60 * 1000);
  } else if (opts.clear === true) {
    newExpiresAt = null;
  } else {
    throw new Error("Pass new_expires_at (ms), extend_days (number), or clear:true.");
  }

  const updates = { [`rec_licenses/${code}/expires_at`]: newExpiresAt };
  // If it was expired and we're pushing the date forward, also un-expire the
  // state so the receiver starts working again on next poll.
  if (prev.state === "expired" && (newExpiresAt == null || newExpiresAt > Date.now())) {
    updates[`rec_licenses/${code}/state`] = prev.bound_account ? "active" : "unused";
  }
  await update(ref(db), updates);
  return { new_expires_at: newExpiresAt };
}

// Admin-only: rotate a REC- license code. Deletes the old record entirely
// (so a stale Cloud Function cache can't resurrect it) and mints a new code
// that carries over the expiry / following_pid / buyer metadata. Use when
// a buyer reports the code was leaked. Returns the new code.
export async function rotateRecLicense(adminUser, oldCode) {
  if (!adminUser || !oldCode) throw new Error("adminUser + oldCode required");
  const snap = await get(recLicenseRef(oldCode));
  if (!snap.exists()) throw new Error(`REC license ${oldCode} not found.`);
  const prev = snap.val() || {};

  let newCode;
  for (let i = 0; i < 8; i++) {
    const candidate = randomRecLicenseCode();
    const collision = await get(recLicenseRef(candidate));
    if (!collision.exists()) { newCode = candidate; break; }
  }
  if (!newCode) throw new Error("Could not generate a unique new REC- code. Try again.");

  const now = Date.now();
  const newRecord = {
    state:          prev.bound_account ? "active" : "unused",
    created_at:     now,
    created_by_uid: adminUser.uid,
    rotated_from:   oldCode
  };
  if (prev.owner_email)    newRecord.owner_email   = prev.owner_email;
  if (prev.mql5_order_id)  newRecord.mql5_order_id = prev.mql5_order_id;
  if (prev.note)           newRecord.note          = prev.note;
  if (prev.expires_at)     newRecord.expires_at    = prev.expires_at;
  if (prev.bound_account)  newRecord.bound_account = prev.bound_account;
  if (prev.bound_broker)   newRecord.bound_broker  = prev.bound_broker;
  if (prev.following_pid)  newRecord.following_pid = prev.following_pid;
  if (prev.activated_at)   newRecord.activated_at  = prev.activated_at;

  const updates = {
    [`rec_licenses/${oldCode}`]: null,   // delete old
    [`rec_licenses/${newCode}`]: newRecord
  };
  // Repoint the provider's receiver row at the new code so the dashboard
  // stays consistent.
  if (prev.following_pid && prev.bound_account) {
    updates[`${DB_PATHS.providers}/${prev.following_pid}/receivers/${prev.bound_account}/license_code`] = newCode;
  }
  await update(ref(db), updates);
  return newCode;
}

// Admin-only: permanently delete a REC- license record. Use for test/mistake
// cleanup; for revocation prefer revokeRecLicense (keeps the audit trail).
export async function deleteRecLicense(adminUser, code) {
  if (!adminUser || !code) throw new Error("adminUser + code required");
  await remove(recLicenseRef(code));
}

// ── PROVIDER-MINTED REC- LICENSES ──
//
// In the Navigator Algo business model, the platform sells the Pro Receiver
// EA on MQL5 Market ($30 / 3 months) but the EA is useless by itself — the
// buyer needs a REC- code from a signal provider to point the EA at. Providers
// collect their own subscription fees (Telegram, Discord, their own site)
// and mint a REC- code for each paying subscriber here. The code is born
// with following_pid already pinned to the minting provider, so the buyer
// can't use it to follow anyone else.
//
// Auth model: database.rules.json gates writes to /rec_licenses/{code} and
// /providers/{pid}/issued_rec_licenses/{code} to Firebase users whose UID
// matches /providers/{pid}/owner_uid — same pattern as SUB- mint / revoke.
// No Cloud Function required.

// Provider-owner: mint a new REC- code pre-pinned to this provider. The code
// carries an expiry (defaults to 3 months to match the Pro Receiver's MQL5
// listing) and an optional subscriber note / email to help the provider
// track who each code was issued to. Returns { code, record }.
//
// opts: { expires_in_days?, expires_at?, owner_email?, note? }
//   expires_in_days defaults to 90. Pass 0 or null for no expiry (not
//   recommended — the code never auto-expires if the subscriber stops paying).
export async function providerMintRecLicense(user, providerId, opts = {}) {
  if (!user)       throw new Error("user required");
  if (!providerId) throw new Error("providerId required");

  // Client-side owner check so we can throw a friendly error before the
  // Firebase rules reject the write.
  const provSnap = await get(providerRef(providerId));
  if (!provSnap.exists()) throw new Error(`Provider ${providerId} not found.`);
  const prov = provSnap.val() || {};
  if (prov.owner_uid !== user.uid) {
    throw new Error("Only the provider's owner can mint REC- codes for it.");
  }

  const now = Date.now();
  let expiresAt = null;
  if (typeof opts.expires_at === "number" && opts.expires_at > now) {
    expiresAt = opts.expires_at;
  } else if (opts.expires_in_days === null || opts.expires_in_days === 0) {
    expiresAt = null;
  } else {
    const days = (typeof opts.expires_in_days === "number" && opts.expires_in_days > 0)
      ? opts.expires_in_days
      : 90;
    expiresAt = now + Math.floor(days * 24 * 60 * 60 * 1000);
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomRecLicenseCode();
    const existing = await get(recLicenseRef(code));
    if (existing.exists()) continue;

    const record = {
      state:          "unused",
      created_at:     now,
      created_by_uid: user.uid,
      created_by_pid: providerId,
      following_pid:  providerId
    };
    if (opts.owner_email) record.owner_email = String(opts.owner_email).slice(0, 256);
    if (opts.note)        record.note        = String(opts.note).slice(0, 500);
    if (expiresAt)        record.expires_at  = expiresAt;

    const updates = {
      [`rec_licenses/${code}`]: record,
      [`${DB_PATHS.providers}/${providerId}/issued_rec_licenses/${code}`]: true
    };
    await update(ref(db), updates);
    return { code, record };
  }
  throw new Error("Could not mint a unique REC- code after 5 attempts. Try again.");
}

// Provider-owner: list every REC- code this provider has minted, newest first.
// Reads the per-provider index at /providers/{pid}/issued_rec_licenses and
// fetches each /rec_licenses/{code} record in parallel.
export async function listProviderRecLicenses(user, providerId) {
  if (!user)       throw new Error("user required");
  if (!providerId) throw new Error("providerId required");

  const indexSnap = await get(ref(db, `${DB_PATHS.providers}/${providerId}/issued_rec_licenses`));
  if (!indexSnap.exists()) return [];
  const codes = Object.keys(indexSnap.val() || {});
  if (!codes.length) return [];

  const records = await Promise.all(codes.map(async (code) => {
    const snap = await get(recLicenseRef(code));
    return { code, data: snap.exists() ? snap.val() : null };
  }));
  // Drop any stale index entries whose /rec_licenses/{code} was deleted.
  return records
    .filter((r) => r.data)
    .sort((a, b) => (b.data.created_at || 0) - (a.data.created_at || 0));
}

// Provider-owner: revoke a REC- code they own. Flips state to "revoked"; the
// Cloud Function's eaRead / eaWrite paths reject the code on the next poll
// within ~1 s. Does not delete the record so the provider can see the
// history in their dashboard and re-enable by extending expiry later.
export async function providerRevokeRecLicense(user, providerId, code) {
  if (!user)        throw new Error("user required");
  if (!providerId)  throw new Error("providerId required");
  if (!code)        throw new Error("code required");

  const snap = await get(recLicenseRef(code));
  if (!snap.exists()) throw new Error(`REC license ${code} not found.`);
  const prev = snap.val() || {};
  if (prev.created_by_pid !== providerId) {
    throw new Error("This REC- code was not minted by this provider.");
  }

  const updates = {
    [`rec_licenses/${code}/state`]: "revoked"
  };
  // Also flip the receiver row on the provider's dashboard so the Active
  // Copiers KPI drops immediately (same pattern as admin-side revoke).
  if (prev.following_pid && prev.bound_account) {
    updates[`${DB_PATHS.providers}/${prev.following_pid}/receivers/${prev.bound_account}/state`] = "inactive";
  }
  await update(ref(db), updates);
}

// Roll up a list of REC license records into counts for the admin KPI strip.
// Cheap pure function — no network.
export function rollupRecLicenseStats(rows) {
  const out = {
    rec_total: 0, rec_unused: 0, rec_active: 0, rec_revoked: 0, rec_expired: 0,
    rec_expiring_soon_7d: 0
  };
  const now = Date.now();
  const soonWindow = 7 * 24 * 60 * 60 * 1000;
  for (const r of rows) {
    out.rec_total++;
    const s = r.data?.state || "unused";
    if (s === "unused")  out.rec_unused++;
    if (s === "active")  out.rec_active++;
    if (s === "revoked") out.rec_revoked++;
    if (s === "expired") out.rec_expired++;
    if (s === "active" && typeof r.data?.expires_at === "number"
        && r.data.expires_at > now && r.data.expires_at - now < soonWindow) {
      out.rec_expiring_soon_7d++;
    }
  }
  return out;
}

// ── DATABASE HELPERS ──

export function providerRef(providerId) {
  return ref(db, `${DB_PATHS.providers}/${providerId}`);
}

export function licenseRef(code) {
  return ref(db, `${DB_PATHS.licenses}/${code}`);
}

export async function getProvider(providerId) {
  const snap = await get(providerRef(providerId));
  return snap.exists() ? snap.val() : null;
}

// Returns the provider_id owned by the given auth user, or null if none claimed yet.
// Schema assumption:
//   /users/{uid}/provider_id = "NAV-XXXX"
export async function getUserProviderId(uid) {
  const snap = await get(ref(db, `users/${uid}/provider_id`));
  return snap.exists() ? snap.val() : null;
}

// Live-subscribe to the provider node so the dashboard updates in realtime.
export function subscribeProvider(providerId, callback, onError) {
  const r = providerRef(providerId);
  return onValue(
    r,
    (snap) => callback(snap.exists() ? snap.val() : null),
    (err) => {
      console.error("[Navigator Algo] subscribeProvider error:", err);
      if (onError) onError(err);
    }
  );
}

// Claim a provider_id for the signed-in user.
// Validates the activation token (generated by the EA and shown in the EA's panel)
// before writing /users/{uid}/provider_id.
//
// The EA writes:
//   /providers/{providerId}/claim_token = "<random 16-char token>"
//   /providers/{providerId}/owner_uid   = null   (initially)
//
// Claim logic:
//   1. Check the claim_token matches.
//   2. Check the provider is unclaimed (owner_uid == null).
//   3. Write owner_uid = user.uid and clear claim_token.
//   4. Write /users/{uid}/provider_id.
//
// All of this needs to be enforced by Firebase security rules too — client-side
// checks are just for UX.
export async function claimProvider(user, providerId, claimToken) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider ID not found. Make sure the EA has connected to Firebase at least once.");
  const data = snap.val();
  if (data.owner_uid && data.owner_uid !== user.uid) throw new Error("This provider is already linked to another account.");
  if (data.claim_token !== claimToken) throw new Error("Activation token doesn't match. Copy the exact token from your EA's panel.");

  const updates = {};
  updates[`${DB_PATHS.providers}/${providerId}/owner_uid`]   = user.uid;
  updates[`${DB_PATHS.providers}/${providerId}/owner_email`] = user.email || null;
  updates[`${DB_PATHS.providers}/${providerId}/claim_token`] = null;
  updates[`${DB_PATHS.providers}/${providerId}/claimed_at`]  = serverTimestamp();
  updates[`users/${user.uid}/provider_id`] = providerId;
  updates[`users/${user.uid}/email`]       = user.email || null;

  await update(ref(db), updates);
  return providerId;
}

// Count active copiers = number of sub_licenses with state == "active".
// Also counts any /providers/{providerId}/receivers/{acctNum} entries
// (paid receivers that picked this provider).
export function countActiveCopiers(providerData) {
  if (!providerData) return { sub: 0, paid: 0, total: 0 };
  let sub = 0, paid = 0;
  const subs = providerData.sub_licenses || {};
  for (const code in subs) {
    if (subs[code] && subs[code].state === "active") sub++;
  }
  const receivers = providerData.receivers || {};
  for (const acct in receivers) {
    if (receivers[acct] && receivers[acct].state === "active") paid++;
  }
  return { sub, paid, total: sub + paid };
}

// Expose a minimal, namespaced API for page scripts.
export { LICENSE_PREFIXES, SUB_LICENSES_PER_PROVIDER, DB_PATHS };
