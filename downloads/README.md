# Downloads

This folder serves the compiled MT5 Expert Advisors that are downloaded
directly from navigatoralgo.com.

## Files

- `NTS_Partner_Receiver.ex5` — Free Partner Receiver EA
  linked from [`/receiver-download.html`](../receiver-download.html).
  Replace this file whenever you ship a new version.

## Versioning

When you ship a new version:

1. Drop the new compiled `.ex5` into this folder (overwrite the existing file).
2. Update the version number displayed on `/receiver-download.html` (search for
   "Version 1.0.0" in the HTML).
3. Update the SHA-256 hash shown on the page (compute with `sha256sum NTS_Partner_Receiver.ex5`).
4. Commit + push. Cloudflare Pages will auto-deploy within ~30 seconds.

Do **not** store the MQ5 source here — that stays private in your
MQL5 source repo. Only the compiled `.ex5` binary goes here.
