# Fresh Toshizo installation through the hosting portal

Target API: `https://toshizo.link/tsutsuura-api/api`.

## Completed installation

The private installer completed on **2026-09-05 at 04:40:01 UTC**. The actual
home directory is `/home/c8629971`; PHP 8.4.21, all required extensions,
`proc_open` and `mail()` were verified. Migrations 001–010, the 370-question seed,
and SQLite integrity/foreign-key checks completed before public activation.

The live app is `/home/c8629971/apps/tsutsuura/current`; its shared `.env`,
SQLite database and private media remain under `/home/c8629971/apps/tsutsuura`.
The public API is
`/home/c8629971/public_html/toshizo.link/tsutsuura-api/api`. Private completion
records are `/home/c8629971/tsutsuura-stage-20260905/install.log` and
`/home/c8629971/apps/tsutsuura/storage/install-complete.json`.

Release verification passed for revision **2026-09-05-email**, all nine required
capabilities, lifecycle routes and enabled email provider. AASA returned direct
HTTP 200 with `34NS8XN5F9.toshizo.link.tsutsuura` and
`/tsutsuura-api/api/invite/*`. The existing homepage remained HTTP 200; public
`.app-root` returned 403 and `.user.ini` returned 404.

Email uses native PHP mail with `general@toshizo.link` as the configured sender.
**Actual inbox delivery and code entry remain unverified.** Both SMS
(`OTP_DRIVER=disabled`) and APNs (`PUSH_DRIVER=disabled`) are disabled. Do not
rerun the fresh installer to update the live app or replace its database/key.

## Reference procedure for a new empty target

Use a private staging directory outside `public_html`, such as
`~/tsutsuura-stage-20260905/server`, containing the source bundle. Exclude `.env`,
`storage/`, local databases and secrets from the uploaded ZIP. Inspect the
actual ConoHa home directory, PHP CLI executable and domain root before running
commands. This procedure creates a fresh app; it does not migrate the old host.

The installation layout is:

```text
~/apps/tsutsuura/
  .env                         private, generated on the new host
  storage/tsutsuura.sqlite      new database
  storage/answer-media/         private attachments
  releases/<release>/          server source
  current -> releases/<release>
~/public_html/toshizo.link/
  tsutsuura-api/api/            contents of server/public only
    .app-root                  points to ~/apps/tsutsuura/current
    .user.ini                  API-local upload limits
  .well-known/
    apple-app-site-association  merge with existing app associations
```

Create a new `APP_KEY` on the host and store it only in the private `.env`.
Set `APP_URL=https://toshizo.link/tsutsuura-api/api`, `DB_CONNECTION=sqlite`, and
absolute private database/media paths. Do not copy the old host's credentials
or overwrite existing Toshizo application directories. Keep
`OTP_DRIVER=disabled`, `OTP_DEV_EXPOSE=false`, and `EMAIL_DEV_EXPOSE=false`.

For native email, choose a real mailbox from this hosting account and configure
`EMAIL_DRIVER=mail` plus `EMAIL_FROM_ADDRESS`. Omitting mail setup can leave
`EMAIL_DRIVER=disabled` while the app's family/device setup remains usable.
Configuring native mail does not send a test email or prove inbox delivery.

Run migrations with the host's verified PHP8.2+ CLI executable from the private
release, never through a public PHP URL:

```sh
/path/to/php /home/c8629971/apps/tsutsuura/releases/RELEASE/bin/migrate.php --seed \
  > /home/c8629971/apps/tsutsuura/storage/install.log 2>&1
```

A portal cron entry can run a reviewed private one-off installer instead when
SSH access is unavailable. That installer should lock concurrent executions,
refuse an existing app/database/public API, generate the key on the host,
record a private success marker, and become a no-op on an exact repeat. Remove
the one-off cron entry once its completion marker has been verified. Never add
a web-accessible migration or installation endpoint, and do not weaken SSH
access restrictions to deploy.

Before activation, verify all migrations `001` through `010` are recorded,
SQLite `PRAGMA integrity_check` returns `ok`, `PRAGMA foreign_key_check` returns
no rows, the catalog contains at least 370 distinct active prompts, and the new
users/families/sessions/answers/media tables are empty.

Publish only the API's public directory. Keep existing Toshizo website files
and global PHP settings unchanged. The API-local `.user.ini` should set:

```ini
file_uploads=On
upload_max_filesize=20M
post_max_size=64M
max_file_uploads=5
```

Copying PHP configuration may be subject to the host's `.user.ini` refresh
interval; HTTPS health is the authoritative check for the web runtime. Merge
AASA app entries and preserve unrelated apps, webcredentials and activity
continuation entries. Back up any existing AASA and `.well-known/.htaccess`
files before changing them. The required app ID is
`34NS8XN5F9.toshizo.link.tsutsuura` and invite path is
`/tsutsuura-api/api/invite/*`.

After activation run, from the local workspace:

```sh
php server/bin/verify-release.php https://toshizo.link/tsutsuura-api/api
```

Verify the AASA URL returns direct HTTP 200 JSON and the new iOS build uses the
same API base URL and `applinks:toshizo.link` entitlement. Complete one controlled
mailbox delivery/code-entry check before declaring email recovery ready.

For a failed fresh installation, restore the exact backed-up public association
files and remove only public paths created by that installer. Keep the failed
private installation quarantined for diagnosis. If a process was interrupted
before recording its success marker, inspect it manually before retrying; never
blindly reset an existing database. Once real accounts use the new endpoint,
subsequent releases must preserve the shared environment, database and media.

The temporary installer job was replaced with an enabled daily 03:00 hosting-time
`cleanup.php` job. It runs `/opt/alt/php84/usr/bin/php` against
`/home/c8629971/apps/tsutsuura/current/bin/cleanup.php` and writes its latest output
to the private `storage/cleanup.log`. No recurring installer remains.
