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
  getDatabase, ref, get, set, update, onValue, runTransaction, serverTimestamp
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
