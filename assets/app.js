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
//   /users/{uid}/provider_id  — "NAV-XXXX" once a provider is bound to this user
//   /users/{uid}/created_at   — server timestamp on first sign-in
//   /users/{uid}/last_seen_at — server timestamp refreshed each sign-in
//
// Also mirrors email -> uid at /users_by_email/{encodeEmailKey(email)} so the
// admin console can resolve a user's UID from their email at provider-bind
// time without needing Admin SDK access from the browser.

// RTDB keys may not contain . $ # [ ] /. Only `.` occurs in real email
// addresses; map it to `,` so the key is deterministic and reversible enough
// for our purposes (we never read back out).
export function encodeEmailKey(email) {
  return String(email || "").trim().toLowerCase().replace(/\./g, ",");
}

export async function getUserProfile(uid) {
  const snap = await get(ref(db, `users/${uid}`));
  return snap.exists() ? snap.val() : null;
}

// Idempotent — creates /users/{uid} with basic info on first sign-in,
// refreshes last_seen_at on every subsequent load. Also refreshes the
// /users_by_email index so admins can find this user by email when binding a
// provider. Best-effort on the index write — failing to update the index
// must not block sign-in (e.g. a stale rule deploy would reject the write).
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
  if (user.email) {
    updates[`users_by_email/${encodeEmailKey(user.email)}`] = user.uid;
  }
  try {
    await update(ref(db), updates);
  } catch (err) {
    // If the email-index write is the failing one (e.g. stale rules not yet
    // published), fall back to writing only the /users/{uid} half so the
    // user can still sign in. Admin-bind will fail later with a clear error.
    console.warn("[Navigator Algo] touchUserProfile multi-path write failed; retrying without email index:", err?.code || err?.message || err);
    const fallback = { ...updates };
    delete fallback[`users_by_email/${encodeEmailKey(user.email || "")}`];
    await update(ref(db), fallback);
  }
}

// Admin-only: resolve a user's UID from their email by reading the
// /users_by_email/{encoded_email} index written at sign-in. Returns the UID
// string, or null if no user with that email has signed in yet.
export async function lookupUidByEmail(email) {
  const key = encodeEmailKey(email);
  if (!key) return null;
  const snap = await get(ref(db, `users_by_email/${key}`));
  return snap.exists() ? snap.val() : null;
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

// Admin-only: mints a new provider bound to an already-signed-up user's
// account. The admin supplies the user's email; we resolve it to a UID via
// /users_by_email and write the provider with `owner_uid` set from the start
// so the user sees their dashboard on next refresh without a separate
// claim-token step.
//
// Throws:
//   "user_not_found"   — no account with that email has signed in
//   "user_already_bound" — that user already has a provider bound
//
// Returns { providerId, eaKey, ownerUid, ownerEmail }.
export async function mintProviderBound(adminUser, opts = {}) {
  const { email, display_name = null, license = "navigator-algo" } = opts;
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) throw new Error("Email required.");

  const ownerUid = await lookupUidByEmail(normalizedEmail);
  if (!ownerUid) {
    const err = new Error("user_not_found");
    err.code = "user_not_found";
    err.userMessage = `No account found for ${normalizedEmail}. Ask them to sign up at /dashboard first, then try again.`;
    throw err;
  }

  const existingProfile = await get(ref(db, `users/${ownerUid}/provider_id`));
  if (existingProfile.exists() && existingProfile.val()) {
    const err = new Error("user_already_bound");
    err.code = "user_already_bound";
    err.userMessage = `${normalizedEmail} already has provider ${existingProfile.val()} bound. Unbind it first, or mint for a different user.`;
    throw err;
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const providerId = randomProviderId();
    const eaKey      = randomEaKey();
    const existing   = await get(providerRef(providerId));
    if (existing.exists()) continue;

    const updates = {};
    updates[`providers/${providerId}`] = {
      owner_uid:      ownerUid,
      owner_email:    normalizedEmail,
      ea_key:         eaKey,
      license:        license,
      display_name:   display_name,
      created_at:     Date.now(),
      claimed_at:     Date.now(),
      created_by_uid: adminUser.uid
    };
    updates[`users/${ownerUid}/provider_id`] = providerId;
    updates[`users/${ownerUid}/email`]       = normalizedEmail;
    await update(ref(db), updates);
    return { providerId, eaKey, ownerUid, ownerEmail: normalizedEmail };
  }
  throw new Error("Could not mint a unique provider ID after 5 attempts. Try again.");
}

// Admin-only: rebind an existing unbound provider to a signed-up user's
// email. Mirrors mintProviderBound but for providers that already exist
// (e.g. older claim-token-flow providers that were never linked). If the
// provider is already bound, the caller must unbindProvider first.
//
// Returns { providerId, ownerUid, ownerEmail }.
export async function bindProviderToEmail(adminUser, providerId, email) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) throw new Error("Email required.");

  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();
  if (data.owner_uid) {
    const err = new Error("provider_already_bound");
    err.code = "provider_already_bound";
    err.userMessage = `${providerId} is already bound to ${data.owner_email || data.owner_uid}. Unbind it first.`;
    throw err;
  }

  const ownerUid = await lookupUidByEmail(normalizedEmail);
  if (!ownerUid) {
    const err = new Error("user_not_found");
    err.code = "user_not_found";
    err.userMessage = `No account found for ${normalizedEmail}. Ask them to sign up at /dashboard first, then try again.`;
    throw err;
  }

  const existingProfile = await get(ref(db, `users/${ownerUid}/provider_id`));
  if (existingProfile.exists() && existingProfile.val()) {
    const err = new Error("user_already_bound");
    err.code = "user_already_bound";
    err.userMessage = `${normalizedEmail} already has provider ${existingProfile.val()} bound. Unbind that first.`;
    throw err;
  }

  const updates = {};
  updates[`providers/${providerId}/owner_uid`]   = ownerUid;
  updates[`providers/${providerId}/owner_email`] = normalizedEmail;
  updates[`providers/${providerId}/claim_token`] = null;
  updates[`providers/${providerId}/claimed_at`]  = Date.now();
  updates[`users/${ownerUid}/provider_id`]       = providerId;
  updates[`users/${ownerUid}/email`]             = normalizedEmail;
  await update(ref(db), updates);
  return { providerId, ownerUid, ownerEmail: normalizedEmail };
}

// Admin-only: detach a provider from its current owner without deleting it.
// Clears owner_uid + owner_email on the provider and clears the user's
// /users/{uid}/provider_id pointer. The ea_key is NOT rotated — the admin
// can rotate it separately if they want to revoke the old owner's MT5
// access. Useful when a mint goes to the wrong email, or when transferring
// a provider between accounts.
export async function unbindProvider(adminUser, providerId) {
  const snap = await get(providerRef(providerId));
  if (!snap.exists()) throw new Error("Provider not found.");
  const data = snap.val();

  const updates = {};
  updates[`providers/${providerId}/owner_uid`]   = null;
  updates[`providers/${providerId}/owner_email`] = null;
  updates[`providers/${providerId}/claimed_at`]  = null;
  if (data.owner_uid) {
    updates[`users/${data.owner_uid}/provider_id`] = null;
  }
  await update(ref(db), updates);
  return { providerId, previousOwnerUid: data.owner_uid || null };
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

// Provider-owner: reactivate a previously-revoked REC- code owned by this
// provider. Flips state revoked → active on the SAME code (no new mint) and
// restores the receiver row to "active" if it was bound before revoke. Use
// when a subscriber was revoked in error or resumed paying. Refuses to act
// on "expired" codes — those need expiry extension via admin first.
export async function providerReactivateRecLicense(user, providerId, code) {
  if (!user)        throw new Error("user required");
  if (!providerId)  throw new Error("providerId required");
  if (!code)        throw new Error("code required");

  const snap = await get(recLicenseRef(code));
  if (!snap.exists()) throw new Error(`REC license ${code} not found.`);
  const prev = snap.val() || {};
  if (prev.created_by_pid !== providerId) {
    throw new Error("This REC- code was not minted by this provider.");
  }
  if (prev.state !== "revoked") {
    throw new Error(`Cannot reactivate a code in state "${prev.state || "unused"}". Only revoked codes can be reactivated here.`);
  }
  if (typeof prev.expires_at === "number" && prev.expires_at < Date.now()) {
    throw new Error("Cannot reactivate an expired code. Rotate to mint a replacement with a fresh expiry, or ask an admin to extend the expiry.");
  }

  // If it was previously bound, resume "active"; otherwise drop back to
  // "unused" so the first eaRead / receiver_ack drives the normal activation
  // path (matches the semantics of rotateRecLicense).
  const newState = prev.bound_account ? "active" : "unused";
  const updates = {
    [`rec_licenses/${code}/state`]: newState
  };
  if (prev.following_pid && prev.bound_account) {
    updates[`${DB_PATHS.providers}/${prev.following_pid}/receivers/${prev.bound_account}/state`] = "active";
  }
  await update(ref(db), updates);
}

// Provider-owner: rotate a REC- code this provider minted. Mints a new code
// carrying over the subscriber metadata, bound account, expiry, and
// following_pid, then deletes the old record + its index entry atomically.
// Use when a subscriber reports the code leaked or they want a fresh code.
// Works on any state (unused, active, revoked, expired). Returns the new code.
export async function providerRotateRecLicense(user, providerId, oldCode) {
  if (!user)        throw new Error("user required");
  if (!providerId)  throw new Error("providerId required");
  if (!oldCode)     throw new Error("oldCode required");

  const snap = await get(recLicenseRef(oldCode));
  if (!snap.exists()) throw new Error(`REC license ${oldCode} not found.`);
  const prev = snap.val() || {};
  if (prev.created_by_pid !== providerId) {
    throw new Error("This REC- code was not minted by this provider.");
  }

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
    created_by_uid: user.uid,
    created_by_pid: providerId,
    following_pid:  providerId,
    rotated_from:   oldCode
  };
  if (prev.owner_email)    newRecord.owner_email   = prev.owner_email;
  if (prev.note)           newRecord.note          = prev.note;
  if (prev.expires_at)     newRecord.expires_at    = prev.expires_at;
  if (prev.bound_account)  newRecord.bound_account = prev.bound_account;
  if (prev.bound_broker)   newRecord.bound_broker  = prev.bound_broker;
  if (prev.activated_at)   newRecord.activated_at  = prev.activated_at;

  const updates = {
    // Delete the old record + drop it from the per-provider index. The new
    // code replaces it in both places atomically so the dashboard stays
    // consistent even if the write is mid-flight.
    [`rec_licenses/${oldCode}`]: null,
    [`${DB_PATHS.providers}/${providerId}/issued_rec_licenses/${oldCode}`]: null,
    [`rec_licenses/${newCode}`]: newRecord,
    [`${DB_PATHS.providers}/${providerId}/issued_rec_licenses/${newCode}`]: true
  };
  // Re-point the receiver row at the new code so the dashboard's
  // Active Copiers list doesn't drift.
  if (prev.bound_account) {
    updates[`${DB_PATHS.providers}/${providerId}/receivers/${prev.bound_account}/license_code`] = newCode;
    updates[`${DB_PATHS.providers}/${providerId}/receivers/${prev.bound_account}/state`] = "active";
  }
  await update(ref(db), updates);
  return newCode;
}

// Provider-owner: permanently delete a REC- code this provider minted, plus
// its entry in the per-provider index. Refuses on "active" codes — callers
// must Revoke first (two-step guard so a stray click on a paying
// subscriber's row can't kill them silently). Rotate is the path for "kill
// the old and mint a new one in one click".
export async function providerDeleteRecLicense(user, providerId, code) {
  if (!user)        throw new Error("user required");
  if (!providerId)  throw new Error("providerId required");
  if (!code)        throw new Error("code required");

  const snap = await get(recLicenseRef(code));
  if (!snap.exists()) throw new Error(`REC license ${code} not found.`);
  const prev = snap.val() || {};
  if (prev.created_by_pid !== providerId) {
    throw new Error("This REC- code was not minted by this provider.");
  }
  if (prev.state === "active") {
    throw new Error('Cannot delete an "active" code. Revoke it first, then delete.');
  }

  const updates = {
    [`rec_licenses/${code}`]: null,
    [`${DB_PATHS.providers}/${providerId}/issued_rec_licenses/${code}`]: null
  };
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

// ── SYSTEM NOTICE (maintenance banner) ──
// /system/notice is a single node rendered as a dismissable banner at the
// top of admin + provider dashboard pages. Readable by any authed user,
// writable by admins. Schema:
//   { level: 'info'|'warning'|'critical',
//     title: string (<=140),
//     body: string (<=1000),
//     starts_at?: number (ms epoch, banner hidden before this),
//     ends_at?: number (ms epoch, banner hidden after this),
//     show_to: 'providers'|'receivers'|'all',
//     updated_at: number, updated_by: uid }

const NOTICE_DISMISS_KEY_PREFIX = "nav_notice_dismissed_";

export async function readSystemNotice() {
  try {
    const snap = await get(ref(db, "system/notice"));
    if (!snap.exists()) return null;
    return snap.val();
  } catch (err) {
    console.warn("[Navigator Algo] readSystemNotice failed:", err);
    return null;
  }
}

export async function setSystemNotice(adminUser, { level, title, body, starts_at, ends_at, show_to }) {
  if (!adminUser || !adminUser.uid) throw new Error("not signed in");
  if (!["info", "warning", "critical"].includes(level)) throw new Error("bad level");
  if (!title || title.length > 140) throw new Error("bad title");
  if (body && body.length > 1000) throw new Error("bad body");
  const target = ["providers", "receivers", "all"].includes(show_to) ? show_to : "providers";
  const payload = {
    level,
    title,
    body: body || "",
    show_to: target,
    updated_at: Date.now(),
    updated_by: adminUser.uid
  };
  if (typeof starts_at === "number" && starts_at > 0) payload.starts_at = starts_at;
  if (typeof ends_at === "number" && ends_at > 0) payload.ends_at = ends_at;
  await set(ref(db, "system/notice"), payload);
}

export async function clearSystemNotice(adminUser) {
  if (!adminUser || !adminUser.uid) throw new Error("not signed in");
  await remove(ref(db, "system/notice"));
}

// Decide whether a notice should render on a given audience page right now.
// audience is 'providers' (dashboard) or 'admin' (admin console); admins
// always see every notice regardless of show_to so they can preview what
// was posted.
export function noticeApplies(notice, audience) {
  if (!notice || !notice.title) return false;
  const now = Date.now();
  if (typeof notice.starts_at === "number" && now < notice.starts_at) return false;
  if (typeof notice.ends_at === "number" && now > notice.ends_at) return false;
  if (audience === "admin") return true;
  const target = notice.show_to || "providers";
  if (target === "all") return true;
  return target === audience;
}

// Mounts the banner at the top of the current page body. Caller specifies
// the audience (providers, receivers, admin). The banner is dismissable —
// dismiss is keyed by updated_at so a fresh notice re-appears. Safe to call
// multiple times; replaces any existing banner.
export async function mountSystemNoticeBanner(audience) {
  const notice = await readSystemNotice();
  const existing = document.getElementById("nav-system-notice");
  if (existing) existing.remove();
  if (!noticeApplies(notice, audience)) return;

  const dismissKey = NOTICE_DISMISS_KEY_PREFIX + (notice.updated_at || 0);
  if (window.localStorage.getItem(dismissKey) === "1") return;

  const level = notice.level || "info";
  const bg = level === "critical" ? "#3a0f14"
           : level === "warning"  ? "#3a2a0f"
           : "#0f2a3a";
  const accent = level === "critical" ? "#ff5a5a"
              : level === "warning"  ? "#ffb63d"
              : "#5ac8ff";

  const bar = document.createElement("div");
  bar.id = "nav-system-notice";
  bar.setAttribute("role", "status");
  bar.style.cssText = [
    "position:sticky", "top:0", "z-index:9999",
    "padding:10px 48px 10px 16px",
    `background:${bg}`,
    `border-bottom:2px solid ${accent}`,
    "color:#fff", "font-family:inherit", "font-size:13px", "line-height:1.45"
  ].join(";");
  const titleText = String(notice.title).replace(/</g, "&lt;");
  const bodyText = String(notice.body || "").replace(/</g, "&lt;");
  bar.innerHTML =
    `<strong style="color:${accent};text-transform:uppercase;letter-spacing:0.05em;font-size:11px;">[${level}]</strong> ` +
    `<strong>${titleText}</strong>` +
    (bodyText ? `<div style="margin-top:4px;opacity:0.85;">${bodyText}</div>` : "") +
    `<button type="button" aria-label="Dismiss" ` +
      `style="position:absolute;top:6px;right:10px;background:transparent;border:0;color:#fff;font-size:18px;line-height:1;cursor:pointer;padding:4px 8px;">×</button>`;
  const btn = bar.querySelector("button");
  btn.addEventListener("click", () => {
    window.localStorage.setItem(dismissKey, "1");
    bar.remove();
  });
  document.body.insertBefore(bar, document.body.firstChild);
}

// Expose a minimal, namespaced API for page scripts.
export { LICENSE_PREFIXES, SUB_LICENSES_PER_PROVIDER, DB_PATHS };
