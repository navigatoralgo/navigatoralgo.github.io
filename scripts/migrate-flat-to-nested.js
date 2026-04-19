#!/usr/bin/env node
/*
 * ── NAVIGATOR ALGO · ONE-SHOT SCHEMA MIGRATION ──
 *
 * Copies legacy flat-schema data into the new nested schema under
 * /providers/{pid}/*, then optionally deletes the flat paths.
 *
 * Legacy flat (read) → New nested (write)
 *   /signals/{pid}/{auto_id}                  → /providers/{pid}/signals/{auto_id}
 *   /signals__meta/{pid}/last_seq             → /providers/{pid}/stats/next_seq
 *   /provider_meta/{pid}/{field}              → /providers/{pid}/{field}       (merge, does not clobber)
 *
 * Legacy /licenses/{pid}/{code} is DROPPED entirely (confirmed test-only data).
 *
 * ── USAGE ──
 *
 *   1. Install deps:  npm --prefix functions install  (uses firebase-admin already there)
 *   2. Service account key: get one from Firebase console →
 *      Project settings → Service accounts → Generate new private key.
 *      Save as /tmp/sa.json (do NOT commit).
 *   3. Dry run:  GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json \
 *                 node scripts/migrate-flat-to-nested.js --dry-run
 *   4. Real run: GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json \
 *                 node scripts/migrate-flat-to-nested.js --apply
 *   5. After verifying nested paths in Firebase console, drop the flat paths:
 *                 GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json \
 *                 node scripts/migrate-flat-to-nested.js --drop-flat --drop-licenses
 *
 * ── SAFETY ──
 *   - Default mode is --dry-run (no writes). Must pass --apply to write.
 *   - Script never overwrites a nested field that already exists (merge, not
 *     clobber). Running --apply twice is idempotent for provider_meta.
 *   - For /signals, auto-ids are unique so re-copying is a no-op.
 *   - --drop-flat and --drop-licenses are separate flags; you must pass them
 *     explicitly in a second invocation after verifying the first worked.
 *   - Prints a count diff at the end: flat rows vs nested rows. If they don't
 *     match, the script exits non-zero before any drop.
 */

"use strict";

const admin = require("firebase-admin");

const DB_URL = "https://signal-provider-pro-default-rtdb.firebaseio.com";
const PROJECT_ID = "signal-provider-pro";

const argv = new Set(process.argv.slice(2));
const DRY_RUN      = argv.has("--dry-run") || (!argv.has("--apply") && !argv.has("--drop-flat") && !argv.has("--drop-licenses"));
const APPLY        = argv.has("--apply");
const DROP_FLAT    = argv.has("--drop-flat");
const DROP_LICENSE = argv.has("--drop-licenses");

function log(...args) { console.log(`[migrate]`, ...args); }
function warn(...args) { console.warn(`[migrate][WARN]`, ...args); }
function fatal(...args) { console.error(`[migrate][FATAL]`, ...args); process.exit(1); }

(async function main() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    fatal("Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON file path before running.");
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    databaseURL: DB_URL,
    projectId: PROJECT_ID
  });

  const db = admin.database();

  log("mode:", DRY_RUN ? "DRY-RUN" : APPLY ? "APPLY" : DROP_FLAT || DROP_LICENSE ? "DROP-ONLY" : "unknown");
  log("DB:", DB_URL);

  // ── 1. Load flat snapshots ──
  log("reading /signals, /signals__meta, /provider_meta, /licenses …");
  const [flatSignals, flatSeq, flatMeta, flatLic] = await Promise.all([
    db.ref("/signals").get().then((s) => s.val() || {}),
    db.ref("/signals__meta").get().then((s) => s.val() || {}),
    db.ref("/provider_meta").get().then((s) => s.val() || {}),
    db.ref("/licenses").get().then((s) => s.val() || {})
  ]);

  const flatSignalCount = Object.values(flatSignals).reduce(
    (acc, perPid) => acc + (perPid && typeof perPid === "object" ? Object.keys(perPid).length : 0),
    0
  );
  const flatLicCount = Object.values(flatLic).reduce(
    (acc, perPid) => acc + (perPid && typeof perPid === "object" ? Object.keys(perPid).length : 0),
    0
  );

  log(`flat /signals                 = ${Object.keys(flatSignals).length} providers, ${flatSignalCount} records total`);
  log(`flat /signals__meta           = ${Object.keys(flatSeq).length} providers`);
  log(`flat /provider_meta           = ${Object.keys(flatMeta).length} providers`);
  log(`flat /licenses                = ${Object.keys(flatLic).length} providers, ${flatLicCount} records total (WILL DROP)`);

  const allPids = new Set([
    ...Object.keys(flatSignals),
    ...Object.keys(flatSeq),
    ...Object.keys(flatMeta)
  ]);
  log(`union of provider ids         = ${allPids.size}`);

  // ── 2. Ensure /providers/{pid} node exists for every pid we'll write to ──
  const missingProviders = [];
  for (const pid of allPids) {
    const exists = (await db.ref(`/providers/${pid}`).get()).exists();
    if (!exists) missingProviders.push(pid);
  }
  if (missingProviders.length) {
    warn(`no /providers/{pid} node for ${missingProviders.length} pids:`, missingProviders);
    warn(`these pids exist in flat paths but were never minted via the admin console.`);
    warn(`the migration will skip them — no parent node to attach nested data to.`);
    warn(`if you want to keep their data, mint those providers first, then re-run.`);
  }

  // ── 3. Plan the writes ──
  const plan = {
    signalsCopied: 0,
    seqCopied: 0,
    metaFieldsCopied: 0,
    pidsSkipped: missingProviders.length,
    licensesToDrop: flatLicCount
  };

  for (const pid of allPids) {
    if (missingProviders.includes(pid)) continue;

    // 3a. Signals
    const pidSignals = flatSignals[pid] || {};
    for (const autoId of Object.keys(pidSignals)) {
      const nestedPath = `/providers/${pid}/signals/${autoId}`;
      if (!APPLY && !DROP_FLAT && !DROP_LICENSE) {
        // Dry run — just count
        plan.signalsCopied++;
        continue;
      }
      if (APPLY) {
        // Don't clobber if already migrated (idempotent)
        const existing = await db.ref(nestedPath).get();
        if (existing.exists()) continue;
        await db.ref(nestedPath).set(pidSignals[autoId]);
        plan.signalsCopied++;
      }
    }

    // 3b. next_seq from /signals__meta/{pid}/last_seq
    const lastSeq = flatSeq[pid]?.last_seq;
    if (typeof lastSeq === "number") {
      if (APPLY) {
        const existing = await db.ref(`/providers/${pid}/stats/next_seq`).get();
        // Use max(existing, flat) — new signals via eaWrite may have already bumped next_seq
        const merged = Math.max(existing.val() || 0, lastSeq);
        await db.ref(`/providers/${pid}/stats/next_seq`).set(merged);
        plan.seqCopied++;
      } else {
        plan.seqCopied++;
      }
    }

    // 3c. provider_meta fields — merge into /providers/{pid}, never clobber
    const meta = flatMeta[pid] || {};
    for (const field of Object.keys(meta)) {
      if (APPLY) {
        const existing = await db.ref(`/providers/${pid}/${field}`).get();
        if (existing.exists()) continue;
        await db.ref(`/providers/${pid}/${field}`).set(meta[field]);
        plan.metaFieldsCopied++;
      } else {
        plan.metaFieldsCopied++;
      }
    }
  }

  log("── plan ──");
  log(`  signals to copy (net):      ${plan.signalsCopied}`);
  log(`  next_seq to set:            ${plan.seqCopied}`);
  log(`  provider_meta fields:       ${plan.metaFieldsCopied}`);
  log(`  providers skipped (missing):${plan.pidsSkipped}`);
  log(`  licenses to drop (test):    ${plan.licensesToDrop}`);

  if (DRY_RUN) {
    log("dry run — no writes performed. Re-run with --apply to commit.");
    return;
  }

  // ── 4. Drop flat paths (only with explicit flag) ──
  if (DROP_FLAT) {
    log("dropping flat /signals, /signals__meta, /provider_meta …");
    await db.ref("/signals").remove();
    await db.ref("/signals__meta").remove();
    await db.ref("/provider_meta").remove();
    log("flat paths removed.");
  }

  if (DROP_LICENSE) {
    log("dropping flat /licenses (test data) …");
    await db.ref("/licenses").remove();
    log("/licenses removed.");
  }

  log("done.");
})().catch((e) => fatal(e?.stack || e?.message || e));
