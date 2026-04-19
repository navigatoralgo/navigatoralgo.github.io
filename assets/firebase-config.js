// ── FIREBASE CONFIG ──
// Replace all placeholder values with your Firebase project's web app config.
// You can find this at: Firebase console → Project settings → "Your apps" → Web app SDK config.
//
// NOTE: These values are *safe* to expose in client-side code. They are not secrets —
// security is enforced by Firebase security rules, not by hiding this config.
//
// Before launch, you MUST:
//   1. Replace every __PLACEHOLDER__ below with the real value.
//   2. Enable Firebase Authentication → Email link (passwordless) + Google provider
//      in the Firebase console.
//   3. Write and publish Firebase Realtime Database security rules (see
//      `firebase/database.rules.json` in this repo for a starting point).
//   4. Add https://navigatoralgo.com to the authorized domains list in
//      Firebase Auth → Settings → Authorized domains.

export const firebaseConfig = {
  apiKey:            "__REPLACE_API_KEY__",
  authDomain:        "__REPLACE_PROJECT_ID__.firebaseapp.com",
  databaseURL:       "https://__REPLACE_PROJECT_ID__-default-rtdb.firebaseio.com",
  projectId:         "__REPLACE_PROJECT_ID__",
  storageBucket:     "__REPLACE_PROJECT_ID__.appspot.com",
  messagingSenderId: "__REPLACE_SENDER_ID__",
  appId:             "__REPLACE_APP_ID__"
};

// Root paths used by the EA + dashboard. Keep in sync with
// what the MQL5 EA writes to Firebase.
export const DB_PATHS = {
  providers:  "providers",   // /providers/{provider_id}
  licenses:   "licenses",    // /licenses/{license_code}
  signals:    "signals",     // /signals/{provider_id}/{seq}
  heartbeats: "heartbeats"   // /heartbeats/{provider_id}
};

// How the dashboard knows what to show. Must match the
// license prefixes used by the EA's license generator.
export const LICENSE_PREFIXES = {
  providerPaid: "PRO-",   // paid provider license (sold on MQL5 Market)
  receiverPaid: "REC-",   // paid receiver license (sold on MQL5 Market)
  subLicense:   "SUB-"    // free sub-license bundled with provider purchase
};

// Number of free sub-licenses issued with each provider purchase.
export const SUB_LICENSES_PER_PROVIDER = 10;
