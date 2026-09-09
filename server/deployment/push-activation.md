# Toshizo push configuration and delivery verification

This is a configuration update to the existing app. Do not run the fresh
installer or migrations, replace APP_KEY, reset SQLite, or copy media.

## Host and Apple prerequisites

- Private app: `/home/c8629971/apps/tsutsuura`; current source in `current/`.
- CLI: `/opt/alt/php84/usr/bin/php`; cURL must advertise HTTP/2 and OpenSSL must
  load a 256-bit prime256v1/secp256r1 EC private key.
- Outbound TLS443 and HTTP/2 to `https://api.push.apple.com` and, for development
  devices, `https://api.sandbox.push.apple.com`. A no-auth request can establish
  TLS/HTTP2 reachability without posting a device notification.
- Correct host UTC clock for the provider JWT's issued-at timestamp.
- Apple developer team `34NS8XN5F9`, topic `toshizo.link.tsutsuura`, and an APNs
  authentication key enabled for that app/environment. An App Store Connect API
  key is not interchangeable with an APNs key.
- No key contents, provider JWTs, device tokens or existing APP_KEY should be
  printed into command output, screenshots or logs.

## Private setup

Upload `configure-push.php` and the selected `.p8` only to
`/home/c8629971/tsutsuura-push-20260905/`, outside public_html. Use the actual
Apple Key ID in these commands:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/tsutsuura-push-20260905/configure-push.php \
  --team-id=34NS8XN5F9 --key-id=KEYID12345 --key-file=AuthKey_KEYID12345.p8 --check-only \
  > /home/c8629971/tsutsuura-push-20260905/cron-check.log 2>&1
```

`--check-only` validates the existing app and staged key without changing live
configuration. It tightens the staged key's permissions to0600. On success,
run the same command without `--check-only`; use a separate `cron-configure.log`
for cron output, leaving the script's private `configure-push.log` intact.

The script:

- locks configuration, verifies the exact existing Toshizo app/database paths;
- validates the selected P-256 key and full production config;
- installs a0600 key under `~/apps/tsutsuura/keys/AuthKey_<KEYID>.p8`;
- backs up the previous `.env` under `storage/push-config-backups/<run>/`;
- atomically changes only PUSH_DRIVER/APNS_TEAM_ID/APNS_KEY_ID/
  APNS_PRIVATE_KEY_PATH/APNS_TOPIC;
- preserves all other environment bytes, APP_KEY, SQLite and media;
- refuses a different key with an already-used Key ID or a concurrent env edit;
- becomes a no-op for the same installed key/settings; sends no push.

A private `storage/push-configured.json` records configuration completion and
explicitly marks provider/device delivery as untested. Remove the one-off
configuration cron entry once this is confirmed. Keep the03:00 daily cleanup
job unchanged. No public installer or migration endpoint is introduced.

## Verification and recurring delivery

1. Run the existing HTTPS `verify-release.php`; validate public web health after
   enabling push, since CLI and web PHP can differ. Health does not prove Apple
   accepted the key. Check the private log for configuration errors.
2. Read aggregate counts only from push_tokens grouped by environment. Do not
   dump/decrypt tokens for inspection. If no production token exists, open the
   current TestFlight build on the controlled test device, sign in to the intended
   test account and allow notifications. Confirm its account/token registration.
3. Send one explicit test to that controlled account using the existing command:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/send-push.php \
  --user=CONFIRMED_TEST_ACCOUNT_ID --category=familyActivity \
  --title='津々浦々の通知テスト' --body='通知を受け取れたことを確認してください。'
```

The command respects notification preferences, mute and quiet hours. Inspect
its count-only summary and sanitized APNs error reasons. Do not bypass user
preferences or send a broadcast. APNs `delivered` means provider acceptance;
confirm the notification on the physical device separately.

4. Add separate once-per-minute portal cron jobs:

```sh
/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/send-event-notifications.php --limit=200 \
  > /home/c8629971/apps/tsutsuura/storage/event-push.log 2>&1
/opt/alt/php84/usr/bin/php /home/c8629971/apps/tsutsuura/current/bin/send-question-reminders.php \
  > /home/c8629971/apps/tsutsuura/storage/question-push.log 2>&1
```

The event worker has durable per-device leases/retries. The question scheduler
uses publication time and recipient quiet/mute settings. Existing events made
while push was disabled are not retroactively announced. Avoid forced test
answers in a real family: answers are immutable.

## Email end-to-end check

Use a uniquely named temporary QA organizer/family, never an existing family.
Keep fixture token and user/family IDs privately to guarantee cleanup.

1. POST `/v1/setup/family` with unique organizerName/familyName and an
   Idempotency-Key. Save the returned token and user/family IDs.
2. Using that bearer, POST `/v1/me/email/request` with the controlled mailbox.
   HTTP202 means host acceptance only. A409 email_already_in_use means choose
   another controlled mailbox; do not replace the real owner.
3. Read the delivered code from the mailbox and POST `/v1/me/email/verify` with
   requestId/code and a unique Idempotency-Key. Confirm hasEmail and fixture ID.
4. POST `/v1/auth/email/request`; receive a second email; POST
   `/v1/auth/email/verify` with its requestId/code and a new Idempotency-Key.
   Confirm the returned user ID is the same fixture user.
5. With the login token, GET `/v1/me` and `/v1/family`; verify the exact fixture
   IDs/name and one-member family. DELETE `/v1/me` with this token and a unique
   cleanup Idempotency-Key. This deletes only the sole-member QA family and
   fixture account; the mailbox is released and fixture sessions cascade away.
6. Verify GET `/v1/me` with both fixture tokens returns401. If any prior test
   step fails, use the original fixture token for the same scoped cleanup.

Do not replace missing inbox evidence with a server-side OTP lookup or expose
development codes in production. Avoid consuming recovery codes for this test.

## Failure handling

The configuration script restores its exact env backup if activation fails
before completion and removes only a newly staged live key. A failure after
another operator edits the env requires manual review; it refuses to clobber
that edit. For a later provider failure, stop the minute workers and restore the
previous push configuration from the private backup without changing APP_KEY,
email configuration or application data. Keep Apple keys intact until a correct
replacement has been verified; no existing key revocation is part of this plan.
