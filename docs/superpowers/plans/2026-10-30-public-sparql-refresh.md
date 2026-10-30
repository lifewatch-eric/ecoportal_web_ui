# Safe public SPARQL refresh implementation plan

> Execute with superpowers:executing-plans, in this existing checkout, without subagents.

**Goal:** Replace the paused unsafe clone script with a consistent, filtered public projection.

**Architecture:** Use the vendor-documented checkpoint-disabled native copy, verified by source PID, file identity and SHA-256. Start the copy on loopback only, apply the previously accepted public-subject/reachable-metadata policy, verify every retained statement set and all graph counts, then replace only the public database directory. Keep the previous public directory for guarded rollback.

**Tech stack:** Python 3 standard library, existing Virtuoso/isql, systemd.

**Spec:** Existing public-prepare policy in the migration evidence and the authorized acceptance/release work.

## Constraints and failure handling

- Only ecoportal-2026-dev and ecoportal-2026-prod; root and exact source/public paths required.
- No source data, users, SQL schema, application configuration or SMTP changes.
- Never call backup_prepare: DEV diagnostics triggered an internal Virtuoso crash; DEV recovered automatically. Never use that diagnostic in PROD.
- Disable automatic checkpoints only during the native copy; always restore the configured interval. Service ExecStopPost must restore it even after a killed job.
- Verify both staging listeners are loopback before reading/filtering any cloned data; disable staging scheduled events.
- Preserve original RDF terms by deleting disallowed subjects instead of serializing retained statements.
- Reject source file/process drift, missing disk space, unknown graphs, changed privacy policy and failed validation before publication.
- Roll back only if the old projection is still public under current source visibility and its sensitive graphs were empty.
- Keep at most three marker-protected job backups; never delete migration/recovery archives.

## Tasks

- [x] Add focused policy/snapshot tests under test/maintenance; observe failure before implementation.
- [x] Add script/refresh_public_sparql.py and run policy, injection and failure-restoration tests: seven passing tests after review fixes.
- [x] Rehearse on DEV: completed in 26 seconds; 65 public ontology subjects, 62 content graphs, nine sensitive graphs empty. Controlled failure after atomic publication restored all prior public graph counts and metadata statement sets; source stayed running.
- [ ] Rehearse on PROD only after DEV passes; preserve rollback directory and evidence.
- [ ] Commit/push/tag the reviewed utility with the DOI compatibility change; deploy and install pinned utility.
- [ ] Enable a bounded systemd service/timer only after successful refresh acceptance.
- [ ] Update canonical migration/release handovers and mirror them to both servers.

## Separate acceptance findings

PROD mailbox delivery succeeded and was confirmed in the recipient inbox. DEV write-flow acceptance reproduced the deferred #235 partial-save failure: the private ontology persisted, no submission did; notification preparation passed with delivery suppressed, while smtp.lirmm.fr:25 timed out. The exact partial test ontology ECOACCEPT1030 was deleted through the authenticated application endpoint and its absence was verified. The user then explicitly approved production SMTP settings in DEV. Three encrypted configuration backups preceded the guarded UI/API/Cron transport copy; TLS authentication and runtime equality checks passed, and existing delivery flags were preserved. A fresh private ECOACCEPT1030 upload succeeded and completed RDF/index/metrics/annotation processing; owner class browsing and anonymous content denial passed. Its removal is pending final acceptance. Missing-token CAPTCHA rejection passed; positive CAPTCHA requires the human. PROD write acceptance and release/tag/deploy remain pending. The API #235 patch remains local and undeployed.
