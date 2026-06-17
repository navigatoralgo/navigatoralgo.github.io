# navigatoralgo.com

Static marketing + provider dashboard for Navigator Algo MT5 tools.
Deployed on Cloudflare Workers using Wrangler Assets.

Important: this site does not auto-deploy from GitHub. Read
[`DEPLOYMENT_HANDOFF.md`](DEPLOYMENT_HANDOFF.md) before deploying.

## Pages

| Path | Purpose |
|---|---|
| `/` (`index.html`) | Home — hero, 9 EA product cards, flagship Trigger Pro demo, footer. |
| `/signal-copier.html` | Marketing page for the new bidirectional Signal Copier EA ($100/yr provider + $30/3mo receiver). |
| `/receiver-download.html` | Free Partner Receiver EA download + activation instructions (`SUB-` licence flow). |
| `/signin.html` | Firebase Auth sign-in (magic-link email + Google). |
| `/dashboard.html` | Provider dashboard — sub-license slots, active copiers, heartbeat, share link. |
| `/downloads/NTS_Partner_Receiver.ex5` | Compiled free receiver EA binary. |

## Firebase setup

Before the dashboard / sign-in will work, three Firebase things must be in place:

### 1. Fill in `assets/firebase-config.js`

Replace every `__REPLACE_*__` placeholder with the values from
Firebase console → Project settings → Your apps → Web app SDK config.

These values are safe to commit — they are *not* secrets, Firebase
is designed to expose them in client code.

### 2. Enable Authentication providers

Firebase console → Authentication → Sign-in method:

- Enable **Email/Password** (required so that Email link sign-in can be enabled)
- Enable **Email link (passwordless sign-in)**
- Enable **Google**

Then Firebase console → Authentication → Settings → Authorized domains:
add `navigatoralgo.com` and `www.navigatoralgo.com`.

### 3. Publish Realtime Database security rules

The starter rules live at [`firebase/database.rules.json`](firebase/database.rules.json).
Copy the `rules` object into Firebase console → Realtime Database → Rules → Publish.

**Do not skip this step.** Without these rules anyone with the Firebase URL can
read every provider's private data and mint fake licenses. The rules enforce:

- Each `/providers/{pid}` node is readable only by its claimed `owner_uid`.
- License codes under `/licenses/` are world-readable (so EAs can validate keys).
- Nothing else is accessible.

## Local development

No build step. To preview locally:

```bash
python3 -m http.server 8000
# open http://localhost:8000
```

For sign-in to work locally, add `localhost` to Firebase's authorized
domains list. Magic-link redirects come back to the origin they were
sent from, so local dev just works.

## Deployment

The live site is served by Cloudflare Worker `navigatoralgomain`, not GitHub
Pages or Cloudflare Pages. A `git push` does not update production.

Deploy manually with Wrangler from the Cloudflare account that owns the Worker
and the `navigatoralgo.com` route. See
[`DEPLOYMENT_HANDOFF.md`](DEPLOYMENT_HANDOFF.md) for the exact architecture,
the `.git` asset-size bug, the current manual workaround, and the recommended
permanent fix.
