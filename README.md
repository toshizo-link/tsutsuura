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
https://kttprojects.conohawing.com/tsutsuura-api/api
```

The client includes caregiver-led family creation, one-time elder-device
pairing, optional phone OTP authentication, Keychain sessions, family/profile
feeds, today’s question, Japanese speech transcription, likes/comments, APNs
registration, haptics, and Reduce Motion-aware animation. The bundled typeface
is `Kaisotai-Next-UP-B.otf`.

### Local simulator demo

Debug builds include an in-process demo API, so all primary screens and mutations
can be exercised without Twilio, APNs, or a network connection. Demo mode
also suppresses the notification permission request.

After installing the iOS 26.5 arm64 simulator runtime, build, install, and
launch the authenticated demo with:

```sh
scripts/run-demo.sh
```

To walk through the phone and OTP screens first, use:

```sh
TSUTSUURA_DEMO_MODE=signedOut scripts/run-demo.sh
```

The authenticated demo fixture uses `090-1234-5678`; any six-digit OTP works
for that enrolled number. Unknown numbers never create an account. You can also set
`TSUTSUURA_DEMO_MODE=authenticated` or `signedOut` in an Xcode scheme. These
variables have no effect unless explicitly set; normal production launches
continue to use the configured HTTPS API and Keychain. Release builds do not
include or activate the demo API.

## API

The deployed health check is:

```text
https://kttprojects.conohawing.com/tsutsuura-api/api/v1/health
```

The production deployment uses SQLite outside the public web root. The
caregiver-led family setup works without an SMS provider: a younger family
member creates the family and the elder profile, then sends a ten-minute setup
link by message. If the link is difficult to open, they can read the six-digit
code over a phone call; the QR code remains available when they are together.
Phone authentication stays disabled until real credentials are configured.
Phone routes intentionally return HTTP 503 in this state; they never expose a
development OTP.

To activate authentication:

- Add Twilio SID, token, and sender number, then set `OTP_DRIVER=twilio`.

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
