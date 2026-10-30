# Public SPARQL refresh

The service builds a public projection from the private Virtuoso checkpoint. It preserves the private store, application code/schema, original RDF terms and existing submission files. It does not reparse ontologies or rebuild application indexes.

Run the installed `ecoportal-public-refresh.service` through systemd. Its `ExecStopPost` restores the configured private checkpoint interval even if the worker is killed. Do not run the Python entry point directly for unattended production work. The timer is installed only after DEV and PROD acceptance; its daily schedule is 02:15 UTC with up to five minutes of delay. Disable the old `clone_and_clean_virtuoso.sh` cron entry when enabling this timer.

## Publication gates

1. Require root, the approved DEV/PROD hostname, exact database paths, an unstriped private database and enough free space. A lock prevents overlapping refreshes.
2. Prove the staging configuration binds SQL and HTTP only to loopback using an empty database. Scheduled SQL events are disabled in staging.
3. Temporarily disable automatic checkpoints, checkpoint, copy the native file and verify its hash while the source process and file identity remain unchanged. Restore the configured interval immediately. An explicit checkpoint or source restart invalidates the copy.
4. Retain public ontology/submission subjects and their reachable approved auxiliary metadata. Drop every other business graph, including users, permissions, DOI history, projects, notes and subscriptions. Keep only known Virtuoso infrastructure graphs. Delete unwanted subjects rather than rewriting retained RDF terms.
5. Read the immutable metadata snapshot in native 1,000-row pages, avoiding Virtuoso's sorted-TOP limit. Reject partial states, short/overlapping pages and count drift; a unique statement count equal to the full graph count requires completeness regardless of scan order. Verify every retained statement, graph count and all nine sensitive graphs. Recheck source visibility before and after publication.
6. Stop only public Virtuoso, atomically exchange database directories, restart it and wait for HTTP readiness. Keep the previous public directory for rollback. Never restore a projection containing subjects that have since become private, or one whose sensitive graphs were nonempty.

## Evidence and recovery

Read `journalctl -u ecoportal-public-refresh.service` and `/srv/ontoportal/data/public-refresh-backups/last-success.json`. Progress contains phases and counts, never credentials or private graph contents. The previous public directory is named in the success record. At most three marker-owned successful backups are retained; migration/recovery archives are untouched.

If a worker fails during publication, inspect its journal before retrying. A failed privacy check can intentionally leave public Virtuoso stopped. The private application store continues running. The job can rebuild while the old public endpoint is stopped; it then treats the old projection as unavailable for rollback. Repair the cause and rerun the service; do not restore an older public database without checking current visibility and every sensitive graph. After an OS/power failure, inspect `public-refresh-stage-*` directories and the public service before removing anything; directory exchange preserves the live path, but a killed job may require service recovery.

## Validation on 30 October 2026

- Eleven offline tests cover public-only reachability, forbidden graph injection, interrupted copies/source restart with checkpoint restoration, truncated metadata/inventories, paging/overlap, the sorted-TOP limit, delayed HTTP startup and rebuilding with the old public endpoint stopped.
- Fresh review found and resolved partial-result and readiness blockers.
- DEV native snapshot: 1,386,217,472 bytes in 7.9 seconds, equal SHA-256, unchanged source PID/file signature, 60-minute checkpoint interval restored.
- Full DEV refresh: 26 seconds, 65 public ontology records, 62 content graphs, all nine sensitive graphs empty; the private acceptance resource is excluded.
- Controlled DEV failure after atomic publication exercised rollback and restored every prior public graph count and metadata statement set.
- Production acceptance is recorded separately in the migration handover; do not infer PROD installation from these DEV results.
- The first PROD rehearsal safely stopped before filtering/publication: OntologySubmission has 13,234 statements, while an unpaged response returned 10,000. Sorted pagination then hit SR353's 10,000-row sorted window. A read-only native-scan proof returned all 13,234 unique statements in 14 pages without configuration changes. Native paging addresses both limits. Tag .12 remains immutable; the corrected release uses a subsequent tag.
- One later staging statement comparison rejected a snapshot before publication; four strict PROD reruns subsequently passed (82 public ontologies/88 content graphs/nine sensitive graphs empty). The earlier mismatch remains unexplained. Equality is intentionally strict, with graph/count diagnostics and no automatic data normalization. A rejection never permits publication and a visibility revocation can stop the old public view; rerunning can recover from that stopped state.

The native-copy procedure follows [OpenLink's documented manual backup method](https://docs.openlinksw.com/virtuoso/ch-server/). The deprecated `backup_prepare` route is deliberately excluded: diagnostics triggered internal engine crashes on DEV, which automatically recovered. It was not used on PROD.
