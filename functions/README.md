# Navigator Algo · Cloud Functions

HTTPS proxy endpoints for MT5 EAs that can't do Firebase Auth. The functions
validate a per-provider `ea_key` or per-receiver `license_code`, then write
to Realtime Database using the admin SDK (bypassing client-side rules).

## Endpoints

Base URL (after deploy):
`https://us-central1-signal-provider-pro.cloudfunctions.net`

### `POST /eaWrite`

Provider writes (needs `pid` + `ea_key`):

```json
{
  "pid": "NAV-2K8KS",
  "ea_key": "4F72-91A0-BC33-8E12",
  "kind": "signal" | "heartbeat" | "stat",
  "payload": { ... }
}
```

Receiver writes (needs `license_code`):

```json
{
  "license_code": "ABC123XYZ",
  "kind": "receiver_ack",
  "payload": { "account": "12345678", "broker": "ICMarkets" }
}
```

Responses:
- `200 { ok: true, server_ts, ... }`
- `4xx { ok: false, error: "<code>", details?: "..." }`

Error codes the EA should handle: `bad_ea_key`, `provider_not_found`,
`bad_license_code`, `license_not_found`, `license_revoked`, `license_expired`,
`cap_exceeded` (free-tier 10-receiver limit), `rate_limited`, `bad_payload`,
`bad_kind`.

### `POST /eaRead`

Receiver polls (GET or POST both accepted):

```json
{ "license_code": "ABC123XYZ", "last_seq": 1487 }
```

Response:

```json
{
  "ok": true,
  "pid": "NAV-2K8KS",
  "signals": [ { "id": "-Nxyz...", "seq": 1488, "symbol": "EURUSD", ... }, ... ],
  "latest_seq": 1492
}
```

## Deploy

Requires Firebase CLI + Blaze plan (already enabled on `signal-provider-pro`).

```bash
cd /path/to/navigatoralgo.github.io
npm --prefix functions install
firebase deploy --only functions
```

First deploy creates the functions under
`us-central1-signal-provider-pro.cloudfunctions.net`. Subsequent deploys
redeploy in place (~30 s).

## Local emulator

```bash
firebase emulators:start --only functions,database
```

Hits `http://localhost:5001/signal-provider-pro/us-central1/eaWrite`.

## Rules dependency

The functions use `admin.initializeApp()` which bypasses client rules, but
the rules file at `firebase/database.rules.json` validates the shape of
written data. Any new field the functions write must have a matching
`.validate` entry or the write will fail.

## 10-follower cap

Enforced in `writeReceiverAck` — before activating a previously-unused
sub_license, the function counts `sub_licenses` with `state === 'active'`
for that provider and rejects (`cap_exceeded`) at >= 10. Existing active
licenses can continue to ack without triggering the cap check.

## Rate limiting

Loose in-memory token bucket per pid (50 writes / 10 s window). Resets per
function instance. Good enough for v1; upgrade to a Firestore-backed bucket
if we see sustained abuse.
