# Prepared safety backend deployment — not executed

Target: `https://toshizo.link/tsutsuura-api/api`

Evidence for the existing layout is `server/deployment/portal-fresh-install.md`
and `release/app-store/build16/server-scheduler-deployment.json`,
`server-apns-configuration.json`, `event-worker-enabled.txt`, and
`question-worker-enabled.txt` in the root project. The 2026-09-05 fresh-install
document describes APNs as disabled at installation; the later build16 evidence
shows it was configured and workers were enabled. Preserve the current values.

The existing `server/bin/deploy.sh` uses private versioned releases, shared
configuration/storage, migration-before-activation and a quiescence acknowledgement.
It requires SSH/rsync. The prepared private `deploy-safety.php` implements the
equivalent local-host operations through ConoHa's File Manager and one-off cron,
without enabling SSH or exposing a web installer.

## Files to upload

Upload the prepared `tsutsuura-safety-20260907.zip` to `/home/c8629971/`, outside
`public_html`. Extract it there so the private script is exactly:

`/home/c8629971/tsutsuura-safety-20260907/deploy-safety.php`

The archive contains that script, a pinned payload manifest, and 79 reviewed
server files. It contains no `.env`, key, database, media, token or local test
fixture. The manifest pins each payload file and the expected existing runtime
hashes from the imported deployed baseline. A source mismatch stops preflight;
inspect it instead of changing the expected hashes blindly.

Check the ZIP SHA256 using the exact command in `PACKAGE-CHECKSUM.txt` before
running the helper. Inspect only the private output logs below. All commands use
the previously verified host CLI `/opt/alt/php84/usr/bin/php`.

## Preflight

Create a temporary once-per-minute job with this command; remove/disable it when
its log records `preflight_passed`:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-safety-20260907/deploy-safety.php --check-only > /home/c8629971/tsutsuura-safety-20260907/preflight.log 2>&1
```

The helper checks all payload hashes, actual production paths, current source
hashes, existing database integrity/foreign keys/migrations, PHP extensions and
PHP lint. It reads existing configuration but does not change it or invoke any
email/APNs/network provider. It reports an aggregate active-worker count; null
means Linux process visibility is unavailable and deployment is intentionally
blocked. Do not substitute a guessed zero.

## Pause and drain

In ConoHa, record the present ON/OFF state and command of each known job before
temporarily switching it OFF. Preserve each schedule and command exactly:

| Job | Existing command |
| --- | --- |
| Tsutsuura family activity push | `/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/send-event-notifications.php --limit=200 > /home/c8629971/apps/tsutsuura/storage/event-push.log 2>&1` |
| Tsutsuura daily question push | `/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/send-question-reminders.php > /home/c8629971/apps/tsutsuura/storage/question-push.log 2>&1` |
| Tsutsuura daily expired-data cleanup | `/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/cleanup.php > /home/c8629971/apps/tsutsuura/storage/cleanup.log 2>&1` |

Keep unrelated jobs unchanged. Disabling a schedule does not terminate a worker
already running; the helper refuses to proceed while a matching process remains.

Use a temporary job with:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-safety-20260907/deploy-safety.php --quiesce --workers-paused > /home/c8629971/tsutsuura-safety-20260907/quiesce.log 2>&1
```

It saves the prior public index and current target privately and atomically
serves an API-only HTTP503 maintenance response. It preserves `.htaccess`,
`.app-root`, `.user.ini`, the rest of toshizo.link and AASA. Disable this temporary
job after `quiesced`; an exact repeat is harmless. Wait at least five minutes
for existing HTTP requests/uploads to drain, and confirm any known longer
in-flight work has ended. The five-minute minimum is a guard, not proof that an
arbitrarily long host request has finished. Other visitors see a brief maintenance
response only on this app's API.

## Apply migration 011 and activate

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-safety-20260907/deploy-safety.php --deploy --workers-paused > /home/c8629971/tsutsuura-safety-20260907/deploy.log 2>&1
```

This copies the verified source to:

`/home/c8629971/apps/tsutsuura/releases/20260907-safety-011`

It links the existing `.env` and `storage`, creates a consistent private SQLite
backup at `storage/safety-backups/20260907-safety-011/before.sqlite`, and applies
only the additive SQLite migration `011_content_safety.sql` plus its ledger row
in one transaction. It does not rerun the fresh installer, reseed questions,
change existing content, or restore a database. It checks prior table counts and
integrity, atomically switches `current`, then installs the tested public index.
An exact successful repeat verifies the installed identity and does nothing.
The workers remain paused until external checks pass. Remove/disable the
temporary job after its private log and state both show `installed`.

If the process stops mid-deploy, preserve the stage/state/backup and inspect it.
The helper refuses to overwrite a partial release. Do not delete that state and
rerun blindly. A failed migration rolls back its transaction; a completed 011 is
retained. No automatic database rollback is performed.

## Health and route verification

Run from the local worktree after activation:

```sh
php /tmp/tsutsuura-appstore-review-safety/server/bin/verify-release.php https://toshizo.link/tsutsuura-api/api
curl --fail --silent --show-error https://toshizo.link/tsutsuura-api/api/v1/health
```

Require revision `2026-09-07-safety`, schema `011_content_safety.sql`, all prior
capabilities and new `userBlocking`, `answerReporting`, `commentReporting`,
`reportedContentHiding`, `operatorModeration`. The verifier also probes the
authenticated routes without credentials, including POST method overrides;
expected authentication/method errors demonstrate route presence without
mutating anybody's account. It does not send email/APNs.

Confirm the main site and existing AASA remain reachable and API `.app-root`
remains inaccessible. Save the health output and private deployment state with
release evidence. Only then restore the three recurring jobs to their recorded
ON/OFF state; do not change schedules, APNs configuration, sender, keys or tokens.
Do not run a push-send command as part of this backend check.

Optional private status job:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-safety-20260907/deploy-safety.php --status > /home/c8629971/tsutsuura-safety-20260907/status.log 2>&1
```

## Rollback

Pause the same three jobs again if they were resumed. Invoke twice, with at
least five minutes between the first `rollback_quiesced` result and the second:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-safety-20260907/deploy-safety.php --rollback --workers-paused > /home/c8629971/tsutsuura-safety-20260907/rollback.log 2>&1
```

The first invocation checks ownership before touching the public index, starts
maintenance and records the drain time. The second checks safety rows after
drain. If **any** block, answer report, moderation action or comment report is
present, it refuses to activate old code and keeps maintenance. A forward fix
is required: the old backend would ignore those safety choices. Never delete
those rows just to force rollback. Disable the one-off job after a refusal.

When all safety tables are empty, rollback restores the recorded old symlink
and exact public index. Existing data, migration011 and the backup remain. It
never copies an old SQLite snapshot over live data. A successful exact repeat
is a no-op. Inspect old health/routes before resuming the recorded cron states;
the new release verifier will correctly reject the old revision. Do not publish
the new app while the old backend is active.

## Optional isolated authenticated smoke

See `AUTHENTICATED-SMOKE.md`. This creates only uniquely named disposable accounts
and uses no existing bearer session, device token, mailbox or family. It is a
separate post-deployment action; no account or authentication operation was
performed while preparing this package.

## Local evidence and remaining limitations

`deployment-fixture-results.json` and `deployment-fixture.log` test private source
copy, manifest tamper rejection, maintenance/drain gates, migration, SQLite
backup, preserved users/environment/media, repeated operations and both rollback
branches. The temporary macOS fixture substitutes a temporary home path and
zero-process Linux probe, and advances the fixture timestamps instead of waiting.
Actual ConoHa `/proc` visibility and the live source hashes remain preflight gates.

The backend's nine-suite source QA is in `/tmp/tsutsuura-review-safety-server-qa`.
No SSH, portal authentication, production write, email or APNs send occurred in
this preparation. Remaining semantic filtering/profile-report/manual moderation
gaps are still documented in `server/deployment/content-safety.md`; packaging
does not make those capabilities exist.
