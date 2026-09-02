# Tsutsuura API

Dependency-free PHP 8.2+ HTTP API for the SwiftUI app. It supports SQLite (the
default ConoHa WING setup) and MySQL/MariaDB, phone OTP through Twilio, opaque
application sessions, authenticated phone enrollment, one-time device recovery,
caregiver-led family setup, managed profiles, family lifecycle controls, family
feeds, editable answers, threaded/reported comments, notification preferences,
and durable event/reminder push delivery. Answers can include an audio recording
and up to four photos stored privately outside the web document root.

## Local setup

Requirements: PHP 8.2+, cURL, Fileinfo, Intl, JSON, OpenSSL, mbstring, PDO, and
either `pdo_sqlite` or `pdo_mysql`.

```sh
cd server
cp .env.example .env
php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
# Put that value in APP_KEY and fill the remaining placeholders.
chmod 600 .env
php bin/migrate.php --seed
php -S 127.0.0.1:8080 -t public public/index.php
curl http://127.0.0.1:8080/v1/health
```

The document root is `server/public`, never `server/`. Keep `.env`, `src/`,
`migrations/`, and the SQLite file outside the public document root.

For local OTP work only, set `APP_ENV=development`, `OTP_DRIVER=log`, and
optionally `OTP_DEV_EXPOSE=true`. Production startup deliberately fails if
logging/debug OTP delivery is enabled. Twilio credentials are strictly required
whenever phone authentication is enabled.

### Safe production mode before provider credentials exist

The API and database can be deployed now without inventing credentials:

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=https://kttprojects.conohawing.com/tsutsuura-api/api
OTP_DRIVER=disabled
OTP_DEV_EXPOSE=false
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_FROM_NUMBER=
```

In this mode, `/v1/health` stays live and reports phone authentication as
disabled. Phone auth endpoints return HTTP `503` with
`auth_provider_unavailable`; no OTP is generated, logged, or exposed. Secure
device-based organizer setup and caregiver-managed elder pairing remain
available, so a family can start without an SMS provider. To activate optional
phone auth, add the three real Twilio values and set `OTP_DRIVER=twilio`.

## Database

For ConoHa without provisioned MySQL credentials:

```dotenv
DB_CONNECTION=sqlite
DB_DATABASE=storage/tsutsuura.sqlite
```

The resolved SQLite path is rejected if it is inside `public/`. SQLite runs
with foreign keys, WAL, a busy timeout, and immediate write transactions.
Back up the database file together with its `-wal` file, or use SQLite's
online backup command. For MySQL/MariaDB, set `DB_CONNECTION=mysql` plus the
`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, and `DB_PASSWORD` values.
The migration runner automatically selects the matching SQL.
Schemas `005_event_notifications.sql`,
`006_event_notification_deliveries.sql`, and
`007_idempotent_mutations.sql` are mandatory. They add the durable
per-recipient event outbox and independently retryable per-device delivery
states used by answer, like, and comment mutations. Schema 007 adds encrypted,
30-day exact-outcome receipts for phone-login verification, phone enrollment,
organizer/managed-member setup, and comment creation; response replay for
pairing and recovery credentials; and non-expiring family-leave/account-delete
tombstones. When upgrading a running deployment, pause
content mutations and the old event worker, apply 005, then 006 (which
backfills every active outbox row), and then 007; deploy this server version,
and only then resume HTTP traffic and the worker. This avoids creating a
schema-005-only row
after the backfill, overlapping old/new worker semantics, or serving a client
that sends idempotency keys before the matching columns exist.

Answer media defaults to `storage/answer-media`. `MEDIA_STORAGE_PATH` may be
absolute or relative to `server/`, but is rejected when it resolves inside
`public/`. The API uses random, non-user-controlled storage keys and keeps the
files private; do not map this directory into the web server. Back up this
directory together with the database so attachment metadata and files remain
in sync.

## Authentication contracts

All success responses use `{"data": ...}`. Errors use:

```json
{
  "error": {"code": "invalid_otp", "message": "The verification code is invalid or expired."},
  "requestId": "f2deae9ba82ae8818f0f9c8c"
}
```

Phone:

```text
POST /v1/auth/phone/request  {"phone":"090-1234-5678"}
202  {"data":{"requestId":"…","expiresIn":600}}

POST /v1/auth/phone/verify   {"requestId":"…","code":"123456"}
200  {"data":{"token":"…","tokenType":"Bearer","expiresAt":"…","user":{…}}}
```

The returning-user endpoints only sign in an account that already owns the
verified number; verifying an unknown number returns `account_not_found` and
never provisions an accidental account. A device-created organizer can enroll
or replace its phone while authenticated by verifying the new number:

```text
POST /v1/me/phone/request  {"phone":"070-1234-5678"}
POST /v1/me/phone/verify   {"requestId":"…","code":"123456"}
```

The same number returns `phone_already_enrolled`, and a number owned by another
account returns `phone_already_in_use`. The verified update and uniqueness check
run atomically, so a concurrently claimed number cannot be attached.

`POST /v1/me/recovery-codes` returns one high-entropy recovery code once and
invalidates earlier unused codes. `POST /v1/auth/recovery/verify` consumes it,
revokes every older bearer session and push registration for the account, and
then issues one replacement session. Codes expire after 30 days and are stored
only as keyed hashes.

Phone-login verification, phone-enrollment verification, organizer bootstrap,
managed-member creation, recovery verification, pairing activation, comment
creation/reply, family leave, and account deletion accept a 16–128 character
`Idempotency-Key`. The iOS client creates one key per logical operation,
persists an opaque operation record across process relaunch, and reuses the
exact key across bounded transport/5xx retries and later manual retries. A
per-install 256-bit Keychain key HMACs the operation fingerprint and AES-GCM
encrypts the receipt UUID stored in preferences; neither a low-entropy
credential/name nor a replay key is recoverable from that file alone. A
definitive 4xx clears the record except for `429`, which retains it for a retry
after the rate-limit window. On launch and mutation-key use, the client sweeps
all expired 30-day records for OTP/enrollment, setup, recovery, pairing, and
comment operations, including abandoned records for unrelated payloads;
non-expiring leave/delete tombstones are excluded. Legacy headerless requests
remain accepted where documented, but they cannot recover an exact lost
response.

Login and enrollment verification reserve an encrypted outcome receipt before
changing attempts, consuming the challenge, attaching a phone, or issuing a
session. Successful and terminal error outcomes are replayable for 30 days;
exact replay does not consume another attempt or session, while reuse of the
key with a different request/code/actor returns `409`. The challenge itself
keeps its short SMS-entry lifetime. After an indeterminate verification, the
iOS app retains non-secret request metadata for restoring the screen and a
separately protected HMAC/encrypted retry association (never a plaintext SMS
code) for the receipt window. It allows the user to re-enter the same code and
clears stale login/enrollment UI when `/me` proves that the operation already
completed.

Organizer bootstrap and managed-member creation use encrypted setup receipts
with the same 30-day window. A transaction reserves the receipt before family
or member creation; concurrent same-key requests return the one exact response,
and a different payload or actor cannot reuse that key.

Recovery and pairing keep the encrypted exact response until the bearer
session issued by that operation expires. `SESSION_TTL_DAYS` is capped at 30
so the server receipt cannot outlive the client's 30-day association. Cleanup
retains the consumed credential row for that same period. A consumed pairing
can re-enter preview
with either valid credential representation (code or token) for that pairing
plus the original activation key, after which activation returns the original
token; exact replays do not consume a new pairing attempt. The client moves
the durable key association when the user switches representations if exactly
one live activation is awaiting recovery. If several live lost activations
exist at once, alternate code/token recovery is intentionally ambiguous and
safe-fails; re-enter the original representation or issue a new setup
credential. Expired client associations are pruned after 30 days, and a
different still-pending invite always starts its own key.

Comment creation reserves an immutable receipt before the insert and binds its
keyed request fingerprint to the authenticated actor, answer, parent, and body.
The encrypted exact response remains replayable for 30 days even if the source
comment is edited or deleted; a replay never recreates deleted content, and
different-content or different-actor key reuse returns `409`. Cleanup removes
the receipt at the end of that window, and the iOS client expires its matching
private retry record on the same schedule. Headerless comment requests create
no receipt.

Family-leave and account-deletion receipts are checked before authentication,
reserved inside the mutation transaction, and contain only the keyed hash,
operation, and small response JSON—never the raw key or actor identity. These
completed tombstones intentionally do not expire: deleting one could let a
very late retry leave a newer replacement family or rerun an account deletion.
Headerless legacy requests remain supported but do not create unreachable
tombstones. Monitor the table as ordinary database growth; introduce a
versioned client-key retirement policy before considering any pruning.

Device-based family setup:

```text
POST /v1/setup/family
{"organizerName":"ゆうた","familyName":"田中家"}
201 {"data":{"token":"…","tokenType":"Bearer","expiresAt":"…","user":{…}}}

POST /v1/family/managed-members
Authorization: Bearer <organizer token>
{"displayName":"まさこ"}
201 {"data":{"member":{"id":"…","displayName":"まさこ","managed":true,…}}}

POST /v1/family/managed-members/{memberId}/pairings
201 {"data":{"pairing":{"id":"…","code":"123456","token":"…",
     "pairingUrl":"https://…/invite/…","expiresAt":"…",…}}}

POST /v1/setup/pairings/preview
{"code":"123456"}
200 {"data":{"pairing":{"member":{"id":"…","displayName":"まさこ"},
     "family":{"id":"…","name":"田中家"},"expiresAt":"…",…}}}

POST /v1/setup/pairings/activate
{"token":"high-entropy-token-from-the-pairing-url"}
200 {"data":{"token":"…","tokenType":"Bearer","expiresAt":"…","user":{…}}}
```

Pairing preview and activation accept exactly one of `code` or `token`. Codes
are six numeric digits for manual fallback; QR codes and links should always
use the high-entropy token. Pairings expire after ten minutes, are single-use,
are stored only as keyed hashes, and are rate-limited by client IP. Creating a
new pairing revokes any earlier pending pairing for that managed member.
When an activation response is lost, the client sends its existing activation
key on preview; the server permits the already-consumed credential to be shown
only for that exact replay and then returns the original bearer on activation.
Families do not need to be in the same place: the organizer can send the
Universal Link by message, or read the six-digit fallback code over a phone
call. The QR code is an optional in-person shortcut.

`GET /invite/{token}` is a no-store, no-referrer HTML fallback for browsers. It
does not render the token into the page body. The token remains present in the
requested URL, so access-log retention should be kept short.

Authenticated routes require `Authorization: Bearer <token>`. Only a keyed
hash of each bearer token is stored. OTPs are keyed hashes, capped by
per-phone/per-IP windows and per-challenge attempts.

## API routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/v1/health` | Database-aware health check |
| POST | `/v1/setup/family` | Create a device organizer and family without SMS |
| POST | `/v1/setup/pairings/preview` | Preview a pending pairing by code or token |
| POST | `/v1/setup/pairings/activate` | Consume a pairing and issue the managed profile session |
| POST | `/v1/auth/logout` | Revoke the presented session and all resolved-account push registrations; an exact stored expired bearer is accepted only for this cleanup and returns HTTP 200 |
| GET / PATCH | `/v1/me` | Read/update `displayName` |
| POST | `/v1/me/phone/request`, `/v1/me/phone/verify` | Authenticated phone enrollment or replacement |
| POST | `/v1/me/recovery-codes` | Rotate and return a one-time device recovery code |
| POST | `/v1/auth/recovery/verify` | Consume a recovery code and issue a session |
| GET / DELETE | `/v1/me/export`, `/v1/me` | Export JSON / delete account with owner guards |
| GET / PATCH | `/v1/me/notification-preferences` | Read/update categories, reminder time, quiet hours, timezone, and `muteUntil` |
| GET | `/v1/family` | Family and member list |
| PATCH | `/v1/family` | Owner renames the family |
| PATCH / DELETE | `/v1/family/members/{id}` | Rename a managed member / remove a member |
| POST | `/v1/family/ownership` | Transfer ownership to a recoverable member; an activated managed target is promoted to independent |
| POST | `/v1/family/leave` | Leave after ownership has been transferred |
| POST | `/v1/family/managed-members` | Owner creates an elderly managed profile |
| POST | `/v1/family/managed-members/{id}/pairings` | Owner/manager creates a ten-minute pairing |
| GET | `/v1/family/pairings` | Owner/manager lists recent pairings |
| DELETE | `/v1/family/pairings/{id}` | Revoke a pending pairing |
| GET | `/v1/home` | Family, today question, own answer, recent feed |
| GET | `/v1/questions/today` | Today question and own answer |
| PUT or POST | `/v1/questions/today/answer` | JSON text; POST also accepts multipart media |
| GET | `/v1/history?cursor=&limit=&search=&date=&from=&to=&authorId=&scope=` | Validated cursor-paginated/filterable history |
| GET / HEAD | `/v1/answer-media/{id}/{token}` | Authenticated media bytes (supports ranges) |
| GET | `/v1/answers/{id}` | Fetch one family-visible answer for a notification deep link |
| PATCH / DELETE | `/v1/answers/{id}` | Edit/delete one’s own answer |
| DELETE | `/v1/answers/{id}/media/{mediaId}` | Delete one attachment without emptying the answer |
| PUT/POST/DELETE | `/v1/answers/{id}/like` | Set/remove a like |
| GET/POST | `/v1/answers/{id}/comments` | List/create `{body,parentCommentId?}` comments/replies |
| PATCH / DELETE | `/v1/comments/{id}` | Edit/delete one's own comment |
| POST | `/v1/comments/{id}/reports` | Report another family member’s comment with `{reason,details?}` |
| PUT or POST | `/v1/push-tokens` | Register `{token,platform,environment}` |
| DELETE | `/v1/push-tokens/{tokenHash}` | Remove a registered token |

IDs are JSON strings. Times are UTC ISO-8601 strings; question/answer dates use
`APP_TIMEZONE` (normally `Asia/Tokyo`). History cursors are the last returned
answer ID.

Family/account deletion and removal first commit database cascades, then remove
the collected private-media storage keys. Owners cannot leave or delete their
account while other members remain; ownership must be transferred first.
Independent removed/leaving members receive a private replacement family and
keep their authenticated sessions, recovery credentials, and push registration,
so the app can immediately load that replacement family without exposing the old
one. Managed-member removal deletes the managed account and all sessions.

Ownership transfer requires every successor to have a durable recovery path:
either an enrolled phone number or an unexpired device recovery code. A managed
successor must also have completed pairing and hold an active device session.
On a successful transfer, that managed profile is atomically promoted to an
independent account; its existing bearer session and recovery credentials stay
valid. This prevents a caregiver-created profile from becoming owner before it
can authenticate and recover itself.

`bin/send-push.php` honors stored category preferences, quiet hours, and the
optional ISO-8601 `muteUntil`, decrypts registered tokens only at dispatch, and
sends through the configured provider.
Production delivery uses Apple's token-based HTTP/2 APNs API; each registered
token selects the sandbox or production APNs host recorded at registration. The
smoke suite uses a deterministic in-memory provider.

Create an Apple Push Notifications Auth Key, keep the downloaded `.p8` file
outside `public/`, and set restrictive permissions before enabling delivery:

```sh
install -m 600 AuthKey_ABC123DEFG.p8 /secure/path/AuthKey_ABC123DEFG.p8
```

```dotenv
PUSH_DRIVER=apns
APNS_TEAM_ID=AB12CD34EF
APNS_KEY_ID=ABC123DEFG
APNS_PRIVATE_KEY_PATH=/secure/path/AuthKey_ABC123DEFG.p8
APNS_TOPIC=com.example.tsutsuura
```

`APNS_TEAM_ID` is the Apple Developer Team ID, `APNS_KEY_ID` is the identifier
shown for the `.p8` key, and `APNS_TOPIC` is the iOS app bundle identifier. The
server verifies that the key is an ES256 key and refreshes its signed provider
JWT before Apple's one-hour limit. Production rejects `PUSH_DRIVER=log`; use
`PUSH_DRIVER=disabled` until credentials are installed. The API still starts in
disabled mode, while the send CLI exits clearly without delivering anything.

For local-only payload inspection, `APP_ENV=development` and `PUSH_DRIVER=log`
write a token hash (never the raw device token) and payload to the server log.
Send a notification with:

```sh
php bin/send-push.php --user=123 --category=comments \
  --title='新しいコメント' --body='家族からコメントが届きました。' \
  --data='{"answerId":"456"}'
```

APNs `BadDeviceToken`, `DeviceTokenNotForTopic`, and `Unregistered` responses
remove the invalid registration. Other APNs or transport failures remain
registered for a later retry and never expose the device token or provider key
in application logs.

When push delivery is enabled, answer publication, first-like insertion, and
new-comment/reply mutations do not contact APNs in the HTTP request. They write one
`notification_event_outbox` row per recipient in the same transaction as the
content change. Each row snapshots its currently registered tokens into
`notification_event_deliveries`; a no-token sentinel preserves an inspectable
terminal outcome. The actor is excluded; answer activity targets current
family members, likes target the answer owner, and comments target the answer
owner plus the parent-comment author for replies. The composite membership
foreign key removes pending rows and their device deliveries if the recipient
leaves that family.

Run the event worker at least once per minute. `--limit` bounds destination
device attempts; a higher value drains a backlog faster while keeping one
invocation bounded:

```cron
* * * * * php /home/c0443939/apps/tsutsuura/current/bin/send-event-notifications.php --limit=200
```

The worker evaluates the recipient's current category preference, global mute,
quiet hours, and each snapshotted token before delivery. Preference, mute,
quiet-hour, no-token, and removed-token outcomes are recorded as terminal
`skipped` device rows. A success on one device never suppresses retry on
another: transient provider failures retry per token up to five attempts with
exponential backoff from 30 seconds to one hour. A stopped device delivery's
`processing` state is reclaimable after a 30-minute lease; per-device claim
tokens prevent an expired worker from overwriting the replacement worker's
result. The recipient outbox row aggregates its device outcomes. Terminal
outbox rows (and their cascading device rows) are retained for 90 days and then
removed by `bin/cleanup.php`.

Custom APNs data stays at the payload root. Answer and like events use
`destination: "family_answer"`; comment/reply events use
`destination: "comments"`. Every payload includes `event_type` and a string
`answer_id`, with string `comment_id` added for comments. The authenticated
`GET /v1/answers/{id}` route lets the client resolve an answer that is not yet
in its local feed.

Run the question-reminder scheduler at least once per minute:

```cron
* * * * * php /home/c0443939/apps/tsutsuura/current/bin/send-question-reminders.php
```

It evaluates each registered user's `questionReminderTime` in their stored
timezone, respects category, quiet-hour, and mute preferences, and records one
dispatch reservation per user/local calendar day before delivery. Completed
dispatches are never repeated; an in-progress reservation left by a stopped
process can be reclaimed after its one-hour lease. Quiet-hour and mute deferrals
are released so a later run can deliver after the preference window ends.

## Answer media contract

The existing PUT/POST JSON request remains unchanged and continues to require a
non-empty body. A JSON update changes only the text and preserves existing
attachments:

```http
PUT /v1/questions/today/answer
Authorization: Bearer <token>
Content-Type: application/json

{"body":"今日は散歩をしました。"}
```

Send binary attachments with `POST` as `multipart/form-data` (PHP's native,
security-hardened upload parser only handles multipart files for POST). `body` is UTF-8 text;
`audio` is an optional single recording; `photos[]` is an ordered repeated
field with at most four images. `audioDurationMilliseconds` is an optional
integer from 1 through 86,400,000 (24 hours) associated with `audio`. A
multipart request is the complete attachment set and replaces previous media
transactionally. Its body may be blank only when at least one valid attachment
is present.

```text
POST /v1/questions/today/answer
body: "庭の花です"
audio: recording.m4a (optional)
audioDurationMilliseconds: 18320 (optional)
photos[]: flower-1.jpg
photos[]: flower-2.png
```

Audio accepts validated M4A, AAC, MP3, WAV, or CAF content up to 20 MiB.
Photos accept decoded JPEG, PNG, or WebP content up to 10 MiB each, with at
most four photos per answer. These three limits are the shipped iOS protocol
contract: `ANSWER_AUDIO_MAX_BYTES`, `ANSWER_PHOTO_MAX_BYTES`, and
`ANSWER_PHOTO_MAX_COUNT` must remain `20971520`, `10485760`, and `4`.
Configuration startup fails when they drift. The web/PHP configuration must
set `upload_max_filesize` and `post_max_size` high enough for the complete
request, and `max_file_uploads` must be at least
`ANSWER_PHOTO_MAX_COUNT + 1` (currently five: one audio plus four photos).
Configure the web SAPI (not only PHP CLI) with
`file_uploads=On`, `upload_max_filesize=20M`, `post_max_size=64M`, and
`max_file_uploads>=5`. `/v1/health` reports `answerMedia: false` and returns a
degraded response if the actual web runtime cannot honor those limits.

Stored attachments are bounded by `ANSWER_MEDIA_FAMILY_QUOTA_BYTES` (2 GiB by
default). A replacement that reduces an already-over-quota family remains
allowed. Multipart attempts are also limited by
`ANSWER_MEDIA_USER_UPLOADS_PER_HOUR` and
`ANSWER_MEDIA_IP_UPLOADS_PER_HOUR`; rejected upload attempts count toward the
window to prevent repeated validation/storage abuse.

Every presented answer includes `media`, including an empty array for old or
text-only answers:

```json
{
  "media": [
    {
      "id": "12",
      "kind": "audio",
      "url": "https://api.example.jp/v1/answer-media/12/<opaque-token>",
      "mimeType": "audio/mp4",
      "fileName": "recording.m4a",
      "byteCount": 482193,
      "durationMilliseconds": 18320
    },
    {
      "id": "13",
      "kind": "photo",
      "url": "https://api.example.jp/v1/answer-media/13/<opaque-token>",
      "mimeType": "image/jpeg",
      "fileName": "flower-1.jpg",
      "byteCount": 1948201
    }
  ]
}
```

Media URLs are scoped to the stored row with an application-keyed opaque
token, but they are not public capability URLs: the same bearer session is
required, and the requester must still belong to the answer's family. Clients
must therefore attach `Authorization` when loading images or audio. Responses
are private/no-store, use the persisted MIME and byte length, retain `nosniff`,
and support single HTTP byte ranges for audio playback.

## ConoHa WING layout and deployment

For the requested base URL:

```text
https://kttprojects.conohawing.com/tsutsuura-api/api
```

the contents of `server/public/` are the public document root corresponding to
the `/tsutsuura-api/api` directory. Store the rest of `server/` in a private
directory outside `public_html`. The deployment template writes a protected
`.app-root` pointer so `index.php` can load that private directory.

`bin/deploy.sh` performs no deployment until every destination and the SSH
identity are explicitly supplied. It contains no account, hostname, or key
default and never searches for a key. Migrations are mandatory for this release
because lifecycle/comment-reply queries require schema `004`, event push
delivery requires schemas `005` and `006`, and replay-safe verification,
setup, comment, credential, and lifecycle mutations require schema `007`.

Before invoking it, externally pause all API traffic and every
old reminder/event worker. Write a fresh, single-use 16–128 character token to
`$DEPLOY_APP_PATH/storage/deploy-quiesced` only after both are stopped, then
pass that same token below within 15 minutes. The script atomically renames the
marker to claim it, so concurrent deployments cannot reuse it, and refuses a
missing, older, or mismatched marker. A failed deployment intentionally leaves
its `.claimed` marker for diagnosis; while the deployment remains quiesced,
remove that claim and create a new token before retrying. It uploads private
code into a new immutable `releases/` directory,
runs migrations there against shared `.env` and `storage`, and atomically moves
the `current` symlink only after migrations succeed. The public bootstrap is
then pointed at `current`; the one-time marker is removed only after both health
checks pass. Keep traffic and workers paused until the command completes.

```sh
DEPLOY_HOST=www315.conoha.ne.jp \
DEPLOY_PORT=8022 \
DEPLOY_USER=c0443939 \
DEPLOY_APP_PATH=/home/c0443939/apps/tsutsuura \
DEPLOY_DOMAIN_ROOT=/home/c0443939/public_html/kttprojects.conohawing.com \
DEPLOY_PUBLIC_PATH=/home/c0443939/public_html/kttprojects.conohawing.com/tsutsuura-api/api \
DEPLOY_PUBLIC_URL=https://kttprojects.conohawing.com/tsutsuura-api/api \
SSH_IDENTITY_FILE=/absolute/path/to/selected-key \
REMOTE_PHP=/opt/alt/php84/usr/bin/php \
RUN_MIGRATIONS=1 \
QUIESCENCE_ACKNOWLEDGED=1 \
DEPLOY_QUIESCENCE_TOKEN=replace-with-the-one-time-marker-value \
bin/deploy.sh
```

Create the production `.env` at `$DEPLOY_APP_PATH/.env` before migrations and
restrict it to the account user. The script intentionally never uploads or
overwrites `.env`, shared storage, or a SQLite database. It checks the PHP CLI
and required extensions, applies all migrations from the staged release,
uploads the API bootstrap and Associated Domains files, switches `current`,
then checks the public health and association URLs. Point scheduled commands at
`$DEPLOY_APP_PATH/current/bin/...` so they follow the same release cutover.
Migrations
`004`, `005`, `006`, and `007`, plus a writable private answer-media directory, are
required for a healthy release. TLS must be active before enabling the
production configuration.

`DEPLOY_APP_PATH` is the release root, not the `current` directory. For a
one-time conversion from an older flat deployment where `current` is a real
directory, remain quiesced while moving that directory under `releases/`,
moving its `.env` and `storage` to the release root, adding back release-local
symlinks to those shared paths, and replacing `current` with a symlink to the
old release. Confirm the old release still answers through that symlink before
running this deployer. Never let the deployer overwrite a real `current`
directory.

The app’s QR links use Universal Links. The deployment publishes:

```text
https://kttprojects.conohawing.com/.well-known/apple-app-site-association
```

The file must return HTTP 200 directly, without a redirect, and with
`Content-Type: application/json`. Verify it after deployment:

```sh
curl --fail --silent --show-error --dump-header - \
  https://kttprojects.conohawing.com/.well-known/apple-app-site-association

curl --fail --silent --show-error \
  https://kttprojects.conohawing.com/tsutsuura-api/api/v1/health
```

The Apple App ID and the distribution provisioning profile must also have
Associated Domains enabled. The Xcode entitlement is
`applinks:kttprojects.conohawing.com`.

Run this once per day from ConoHa’s cron panel to remove expired OTP/enrollment,
recovery, OAuth, pairing, rate-limit, session, and 30-day OTP/setup/comment
receipt rows; resolved reports/old audit records; terminal event outbox rows;
plus unreferenced attachment files older than one hour. Non-expiring
leave/account-deletion tombstones are deliberately retained:

```sh
cd /home/c0443939/apps/tsutsuura/current && \
  /opt/alt/php84/usr/bin/php bin/cleanup.php
```

Use SQLite’s online backup command (or ConoHa snapshots) while the app is live;
do not copy only the main SQLite file while WAL writes may be pending. Keep a
synchronized backup of `storage/answer-media` as well. Keep a separate
protected backup of `$DEPLOY_APP_PATH/.env` and its `APP_KEY`: losing that key
invalidates sessions and makes encrypted push tokens unreadable. Leave
`TRUSTED_PROXIES` empty unless ConoHa support supplies the exact proxy
addresses; accepting forwarded client IPs from arbitrary hosts would weaken
rate limiting.

## Validation

```sh
bash -n bin/deploy.sh
bin/lint.sh
php bin/smoke-test.php
php bin/event-notification-test.php
php bin/transaction-race-test.php
php bin/migration-resume-test.php
```

The smoke test creates a temporary SQLite database, applies every migration,
and exercises OTP issuance/enrollment/replacement and unknown-account rejection;
exact success/error OTP replay without a second attempt/session; recovery codes;
idempotent organizer/managed-member setup; pairing activation replay; family
rename/removal/ownership/leave invariants; export/delete cascades; answer/media
ownership and physical cleanup; filtered pagination; immutable threaded-comment
receipts across edit/delete; notification preferences/reminders; deterministic
and crash-recovered push dispatch; APNs configuration/JWT construction;
MIME/count/UTF-8/quota validation; composed-Unicode 80/81 name,
2,000/2,001 answer, 1,000/1,001 comment, 500/501 report-detail, and 100/101
history-search boundaries; encryption; logout boundaries; receipt expiry;
and orphan cleanup. It performs no network calls.

The event-notification test separately exercises transactional enqueue,
cross-family and actor exclusion, category preferences, mute/quiet/no-token
skips, answer/like deduplication, reply fan-out, payload destinations, leased
device-job recovery, durable retry after simulated provider failure, and a
partial multi-device delivery where only the failed token is retried. It also
performs no network calls.

The transaction-race test uses independent SQLite processes and held writer
locks to verify recovery/ownership serialization, membership/report
authorization, concurrent organizer/managed-member setup, immutable comment
creation, and same-key leave/account-deletion receipts. The migration-resume
test starts at schema 005 with an active outbox row, verifies the 006 per-device
backfill, simulates a partially committed 007, and proves that rerunning the
migrator completes it exactly once without duplicating the backfill. It also
removes required 007 columns/indexes after the ledger says the migration ran and
verifies that the migrator self-reconciles them.

These deterministic database gates execute SQLite. The MySQL/MariaDB 006/007
DDL and reconciler are source-audited but must still be run on a disposable
staging schema before a MySQL-backed release; local SQLite success is not proof
of MySQL constraint or DDL behavior. The 007 reconciler repairs missing known
tables, columns, and indexes after an interrupted/incorrectly recorded
migration; it is not a general drift engine and does not rebuild an existing
column whose default/nullability or foreign-key definition was manually
altered. Validate constraint shape in staging and restore unexpected drift from
a known-good migration/backup.
