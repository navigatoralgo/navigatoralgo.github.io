# navigatoralgo.com Deployment Handoff

This document is the source of truth for deploying `navigatoralgo.com`.

## Hosting Architecture

The site is not hosted on GitHub Pages or Cloudflare Pages.

The live site is hosted on the Cloudflare Worker project named
`navigatoralgomain`. The Worker uses Wrangler Assets to serve the static HTML,
CSS, JavaScript, and image files from the repository root:

```json
"assets": {
  "directory": "."
}
```

Because this is a Worker deployment, pushing to GitHub does not automatically
update the live site. After committing changes, the live Worker must be deployed
manually with Wrangler from the Cloudflare account that owns `navigatoralgomain`
and the `navigatoralgo.com` route.

## Deployment Bug

Wrangler deploys were failing because the assets directory is the repository
root (`.`). That made Wrangler try to upload hidden and non-public files,
including the `.git/` folder.

Cloudflare Workers Assets has a strict 25 MiB size limit per asset. The local
`.git/` folder was larger than that, so deployment failed when Wrangler tried to
include it.

Do not assume `.wranglerignore` or `.workerignore` will solve this in every
Wrangler version. The observed failure happened even after ignore-file attempts.

## Current Manual Deployment

The manual fix used successfully was:

```powershell
# From C:\navigatoralgo.com

# 1. Move the large .git folder outside the deploy directory.
Move-Item -Path ".git" -Destination "C:\temp_git"

# 2. Deploy the Worker assets.
cmd /c npx wrangler deploy

# 3. Restore version control.
Move-Item -Path "C:\temp_git" -Destination ".git"
```

Use this only when you are confident the current directory is
`C:\navigatoralgo.com`. After deploying, always confirm `.git` was moved back
and `git status` works.

## Safer Temporary Deployment Option

Instead of moving `.git`, a safer deploy path is to deploy from a clean temporary
copy made from the committed tree. This excludes `.git`, untracked temp files,
and local debug files.

High-level workflow:

1. Commit the intended changes.
2. Create a clean temporary folder from `git archive HEAD`.
3. Copy or generate a Wrangler config whose `assets.directory` points at that
   clean folder.
4. Run `npx wrangler deploy --config <temp-config>`.
5. Verify the live URL.

This avoids touching the real `.git` folder.

## Permanent Fix

Move all public website files into a dedicated public directory, for example
`public/`, then update `wrangler.jsonc`:

```json
"assets": {
  "directory": "./public"
}
```

That prevents Wrangler from uploading `.git`, `node_modules`, Firebase function
source, temporary HTML files, and other files that should never be deployed as
static assets.

## Verification Checklist

After deployment, verify both canonical guide URLs:

```powershell
Invoke-WebRequest "https://navigatoralgo.com/tcu-guide" -UseBasicParsing
Invoke-WebRequest "https://navigatoralgo.com/tcu-guide.html" -UseBasicParsing
```

For the TCU guide, confirm the response includes current page markers such as:

- `Trade Copier Ultimate Guide`
- `@uwuxr3`
- `@tcusupport`

Also test the page in a browser after deployment because Cloudflare may return a
cached `HIT` response while still serving the newest Worker asset.
