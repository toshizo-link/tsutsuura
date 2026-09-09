# Tsutsuura

SwiftUI family question-and-answer app backed by a dependency-free PHP API for
ConoHa WING.

The exhaustive remediation status for all 38 items in the whole-app QA audit is
tracked in [`QA_REMEDIATION_MATRIX.md`](QA_REMEDIATION_MATRIX.md), including the
physical-device, live-service, CDN, credential, and deployment gates that cannot
be certified by Simulator or deterministic local tests.

## iOS app

Open `tsutsuura/tsutsuura.xcodeproj` in Xcode. The app reads its HTTPS API root
from `API_BASE_URL` in `tsutsuura/Info.plist` and currently targets:

```text
https://toshizo.link/tsutsuura-api/api
```

The app's Associated Domains entitlement and Universal Link parser accept
`applinks:toshizo.link` and `/tsutsuura-api/api/invite/<token>`. The API fallback
uses the same production root. Verification challenges are stored per API root,
so an unfinished code from a previous server is never replayed on this server.
An old server session that receives HTTP 401 returns to account setup or login.
The Toshizo migration starts with fresh account and family data. Previous
accounts, invitations, and recovery codes are not transferred; create the
family again and send new setup invitations to its members.

The client includes caregiver-led family creation, one-time elder-device
pairing, optional email-code authentication, Keychain sessions, family/profile
feeds, today’s question, Japanese speech transcription, likes/comments, APNs
registration, haptics, and Reduce Motion-aware animation. The bundled typeface
is `Kaisotai-Next-UP-B.otf` (廻想体). The signature face appears in branding,
headings, family names and statuses, feed dates, questions, answers, comments,
and short controls. Form fields, codes, counters, and detailed guidance retain
system fonts. Both participate in Dynamic Type; screens fill the available width without an outer rounded mask, and
compact screens reflow instead of cropping a 440-point canvas.

The palette follows the [Figma reference](https://www.figma.com/design/lClmEifb1lrNbhkosKG3an/Tutuura?node-id=1-17): cyan `#2FADD7`, green `#4FC446`, paper `#D7F0F7`,
and charcoal `#2B2B2B`, with the original button shadows and square-dot pattern.
The cyan family battery has one cell per family member; each person's cell fills
when their answer arrives. 確認 opens the member status list and VoiceOver reads
the exact answered/total count. The question banner stays fixed while answers
scroll. Home refreshes quietly about every ten seconds while visible and active,
without a refresh button, spinner, or overlapping requests. Loaded pages, search
results, and drafts stay in place. Family and personal pages use the same spring
as other navigation over one stationary dotted backdrop. Selected tabs use a
light face, dark text, border, and 「表示中」 checkmark; edge swipes return from
detail pages. A narrow left-edge touch region takes priority over vertical scrolling,
including diagonal and canceled back swipes. Reduce Motion removes sliding.

Personal history offers a single live search field and 「すべての回答に戻る」.
Search changes discard mismatched old results. Settings use large task-based
rows for notifications, family, personal stamps, help, and account recovery;
less common and destructive actions are behind clearly labeled disclosures.
A four-step onboarding walkthrough explains daily questions, sending an answer,
family/personal pages, and help. Drawing a personal 16×16 dot stamp is optional;
a name initial or preset heart provides an accessible alternative. Stamp creation
and help replay are ordinary navigation pages, with the same spring and back behavior.

Published answers and attachments cannot be edited or deleted. The app asks the
user to confirm before sending; comments remain available for follow-up. The
backend rejects stale-question submissions and changed retries while preserving
exact retries. Automatically generated family names follow their admin's name;
custom family names stay independent.

The catalog contains 370 unique Japanese questions. Each family receives a
stable, varying publishing time from 09:00–19:00 in the app calendar timezone
(`APP_TIMEZONE`, currently Asia/Tokyo). The 43 questions about the current day's
experiences publish at 17:00–19:00. Before publication, home shows the arrival
time and hides the question; the app refreshes at that time and on reactivation.
Question notifications follow publication and additionally respect the
recipient's 09:00–20:00 daytime window, mute, and quiet-hour preferences.

See [the screenshot remediation record](SCREENSHOT_REMEDIATION.md) for the
reported issues, validation, and remaining production rollout requirements.

### Local simulator demo

Debug builds include an in-process demo API, so all primary screens and mutations
can be exercised without mail delivery, APNs, or a network connection. Demo mode
also suppresses the notification permission request.

After installing the iOS 26.5 arm64 simulator runtime, build, install, and
launch the authenticated demo with:

```sh
scripts/run-demo.sh
```

To start at setup or email login, use:

```sh
TSUTSUURA_DEMO_MODE=signedOut scripts/run-demo.sh
```

The demo account starts with `demo@example.com`. You can change it under account
settings before signing out to test email login; any six-digit demo code works. Unknown email
addresses never create an account. You can also set
`TSUTSUURA_DEMO_MODE=authenticated` or `signedOut` in an Xcode scheme. These
variables have no effect unless explicitly set; normal production launches
continue to use the configured HTTPS API and Keychain. Release builds do not
include or activate the demo API.

## API

The deployed health check is:

```text
https://toshizo.link/tsutsuura-api/api/v1/health
```

The production deployment uses SQLite outside the public web root. The
caregiver-led family setup works without an SMS provider: a younger family
member creates the family and the elder profile, then sends a ten-minute setup
link by message. If the link is difficult to open, they can read the six-digit
code over a phone call; the QR code remains available when they are together.
The app offers email verification for account recovery. Sessions, family
pairing, and recovery codes created on this deployment stay on this server.
Historical phone credentials
are retained for compatibility; keep `OTP_DRIVER=disabled` to avoid SMS.

To activate authentication:

- Apply migrations through `010`, set `EMAIL_DRIVER=mail`, and configure a real
  `EMAIL_FROM_ADDRESS` on the hosting account. PHP uses the host's outbound mail
  transport directly, with no third-party authentication SDK. Verify delivery to
  an actual inbox before relying on email recovery.

See `server/README.md` for the complete API, environment, migration, security,
test, and release-deployment documentation.

## Validation

```sh
bash -n server/bin/deploy.sh
bash server/bin/lint.sh
php server/bin/smoke-test.php
php server/bin/event-notification-test.php
php server/bin/transaction-race-test.php
php server/bin/migration-resume-test.php
php server/bin/http-contract-test.php
php server/bin/question-schedule-test.php

xcodebuild -project tsutsuura/tsutsuura.xcodeproj \
  -scheme tsutsuura \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project tsutsuura/tsutsuura.xcodeproj \
  -scheme tsutsuura \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=26.5' \
  -parallel-testing-enabled NO test
```

If `xcodebuild` reports that no runtime is compatible with the iOS 26.5 SDK,
install the matching runtime:

```sh
xcodebuild -downloadPlatform iOS \
  -architectureVariant arm64
```

Do not pin `-buildVersion 26.5` here: that can select an older 26.5 patch
runtime which `actool` rejects against Xcode's newer 26.5 simulator SDK.
