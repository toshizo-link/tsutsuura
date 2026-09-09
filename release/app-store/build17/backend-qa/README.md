# Backend safety QA

All nine commands in `results.json` passed against the final source hashes in
`source-manifest.json`. Commands run from `/tmp/tsutsuura-appstore-review-safety`.
The import manifest preserves the deployed 89-file backend baseline; the safety
change modifies 10 baseline files and adds 8 files, including documentation/tests.
No root workspace, production data, private configuration or browser was changed.

Coverage includes actual authenticated HTTP routes, native and POST-overridden
methods, foreign-family/self/invalid targets, persistent mutual blocking,
pagination, old photo/audio URLs (GET/HEAD), interaction and receipt guards,
queued/direct notification suppression, unblock semantics, report retries,
operator CLI decisions, retention, removed TODAY answer state and account cleanup.
The existing suites cover email, scheduling, push device retries, migration
resumption, concurrent transactions, media, and the wider API contracts.

One regression during implementation caught the prior exact receipt-after-own-
comment-deletion contract. The final guard preserves it without recreating the
comment, while still rejecting existing moderator-hidden comment replays. Both
legacy smoke and dedicated safety regressions pass. Event test warnings are
intentional simulated provider failures, followed by successful retry assertions.

Read `server/deployment/content-safety.md` for deployment and moderation commands
and explicit remaining App Review gaps. This QA does not claim full UGC compliance,
production deployment, real email/APNs delivery, or MySQL runtime coverage.
