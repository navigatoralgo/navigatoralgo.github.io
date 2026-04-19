# navigatoralgo.com

Static marketing + provider dashboard for Navigator Algo MT5 tools.
Deployed on Cloudflare Pages (was GitHub Pages until the Signal Copier launch).

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

## Deploying to Cloudflare Pages

1. [dash.cloudflare.com](https://dash.cloudflare.com) → Workers & Pages → Create → Pages → Connect to Git.
2. Authorise the `navigatoralgo` GitHub organisation, pick this repo.
3. Build settings:
   - **Framework preset**: None
   - **Build command**: *(leave empty)*
   - **Build output directory**: `/`
   - **Root directory**: *(leave empty)*
4. Click Deploy. First deploy takes ~30 seconds.
5. You get a URL like `navigatoralgo.pages.dev`. Open it — it should match the live site.
6. In the Pages project → Custom domains → add `navigatoralgo.com` and `www.navigatoralgo.com`.
   Cloudflare adds the DNS records automatically (only works if the domain's
   nameservers point to Cloudflare — see next step).

## Migrating DNS from GitHub Pages to Cloudflare

1. Cloudflare dashboard → Add a site → `navigatoralgo.com` → Free plan.
2. Cloudflare imports existing DNS records. Verify the GitHub Pages A records
   (`185.199.108.153` etc) are present. They stay while we migrate, no downtime.
3. Cloudflare shows 2 nameservers like `abby.ns.cloudflare.com` / `kai.ns.cloudflare.com`.
   Change the nameservers at your domain registrar to those 2.
4. Wait ~5 min — a few hours for full propagation. The GitHub Pages site keeps
   serving until Cloudflare takes over.
5. Once propagated, attach the Pages project's custom domain (step 6 above).
6. After 24h of verifying Cloudflare is serving correctly, disable GitHub Pages:
   GitHub repo → Settings → Pages → Source: None.

## Auto-deploy

Every `git push` to `main` triggers a new Cloudflare Pages deploy.
PRs get preview deploys at a per-PR URL — linked in the PR checks.
