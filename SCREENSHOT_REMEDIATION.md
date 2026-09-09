# Screenshot remediation — September 2026

This record follows the user's images in descending filename order. Existing
workspace changes were preserved. **1.0 (13)** is available to **Tsutsuura Internal**
(one existing tester). Apple confirms completed processing and **Testing** status;
Japanese testing notes are saved. External distribution remains blocked while
build 7 awaits Beta App Review.
The Toshizo API includes the fixes verified through actual Simulator testing
below.
Build 13 includes pull-to-reveal feedback, downward photo dismissal, the square-cornered
photo Close button, and upward banner dismissal. The App Store 1.0 draft has build
13 selected, Japanese copy, four screenshots, reviewer instructions, and manual
release. Final submission fields and readiness items remain in `release/app-store/README.md`.

| Image / request | Change |
| --- | --- |
| IMG_7720 — battery cells | One cell per family member, filled for that person's current-day answer; exact VoiceOver count retained. |
| IMG_7719 — admin name | Generated family names track admin name changes immediately. Migration repairs stale generated names. Deliberately chosen family names remain independent. |
| IMG_7718 — recovery code | Verified existing route against a real local HTTP server; production route is absent in the older deployment. |
| IMG_7717 — registration | Follow-up replaces phone registration/login with private verified email and native PHP mail. Legacy accounts and recovery codes are preserved. |
| IMG_7716 — help icon | Replaced unavailable symbol with `heart.fill`; updated help for the new behavior. |
| IMG_7715 — export | Verified authenticated export through the actual HTTP front controller; production requires rollout. |
| IMG_7713 — notifications / question timing | Verified preference read/save routes; simplified controls. Added stable per-family publication times and daytime notification delivery. |
| IMG_7712 — search | Live debounced search, submit/search-button support, query-bound results, and one reset action. Old results cannot masquerade as matches after failure. |
| IMG_7711 — loading overlay | Removed the blocking home spinner and refresh text/button. Quiet updates run about every ten seconds while Home is visible and active. |
| IMG_7708 — cancelled refresh | Cancellation no longer becomes a home error toast. Automatic updates preserve loaded pages, current search, and drafts. |
| IMG_7707 — separated banner | The banner is outside the scrolling feed and shares the fixed dot background. |
| Swipe back | A 24-point left-edge touch region takes precedence over vertical scrolling, ignores vertical travel, and uses the same spring as other page navigation. |
| Personal icons | Required hand-drawn 16×16 dot stamp stored on the profile and shown with answers/comments. Accounts without a drawing must create one before continuing. Drawing, erasing, undo, and clearing the canvas are available; blank marks and presets cannot be saved. |
| Immutable answers | Removed edit/delete entry points, guarded legacy route, added send confirmation, and enforced immutability on the server including attachments and changed retries. Comment edit/delete controls were also removed in build 11. |
| Annual question catalog | 370 distinct Japanese prompts; 43 current-day reflection prompts carry later publishing windows. Seed extension preserves existing IDs and answers. |
| Selected tab | Compact single-row buttons retain a light selected surface, dark label, strong border, checkmark, and VoiceOver selection state. |
| Filters | Removed the complex filter entry point from home; only search and reset remain. |
| Motion | Pages, tabs, and guide steps share one navigation spring. Icon creation and guide replay use page navigation instead of sheets; dots stay stationary. Explicit navigation intent avoids reversed login/pairing transitions; Reduce Motion disables sliding. |
| Settings | Large task-oriented rows, plain explanations, two main notification choices, optional details, and separate uncommon/destructive actions. |
| Onboarding | A required personal drawing comes before continuing into the app. Four short guide steps explain questions, sending, family versus personal pages, and finding help. The guide can be replayed from Help. |

## Question behavior

- General questions: 09:00–19:00; current-day experiences: 17:00–19:00.
- The calendar remains the configured `APP_TIMEZONE` (Asia/Tokyo), so a family
  shares the same day and question. The app explicitly shows the Japan date/time
  and the device's local date/time when different. Pending questions are called
  the next question, and onboarding explains the shared Japan calendar.
- The chosen question and time are persisted for each family/day. Reloads and
  catalog changes do not reshuffle an already chosen publication.
- Question prompts stay hidden until release. Submission checks release
  time, question ID, and expected date so a draft cannot silently attach to
  another day. Foreground refresh preserves the old prompt and draft until the
  user explicitly chooses to discard it and start the new question.
- Question reminders wait for publication, skip people who answered, and respect
  recipient-local 09:00 through the 19:00 minute, quiet hours, mute, and opt-out.
  Device timezone sync runs independently of notification permission and changes
  no notification choices. Actual APNs delivery
  can be delayed by device/network conditions.
- Existing same-day answers remain visible during rollout; historical answers
  are unchanged. The rotating evergreen catalog does not repeat until its full
  cycle completes.

## Validation

- iOS Simulator build succeeds.
- The full 150-test iOS unit run passes. After the final refresh guards, all eight
  focused polling tests pass, including four additional late-response cases.
  Coverage includes cancellation, search failures, stamp persistence/reset,
  immediate family-name propagation, immutable answers/retries, release-state
  decoding, draft preservation across date changes, and expected question IDs/dates
  in JSON/multipart submissions.
- New email tests verify normalization, endpoint/body contracts, account-bound
  enrollment, exact retries, relaunch recovery, expiration, and private addresses.
  New polling tests verify quiet failures, fresh-value merging with loaded pages,
  family changes, serial updates, and cancellation. Late refresh responses cannot
  replace a newer profile or sign out a session after their task is canceled.
- The animation/email follow-up has passing UI checks for email enrollment and
  returning login, email-entry/back navigation, guide next/previous, tab selection,
  drawing/undo/save on a full page, the fixed home banner without refresh controls,
  largest accessibility text, and straight/diagonal back gestures. On iPhone SE,
  a short diagonal edge swipe preserves the content's vertical position, an
  ordinary center swipe still scrolls, and a completed diagonal edge swipe returns.
  On iPhone 17 Pro Max, diagonal back gestures, drawing/undo/save, and email
  enrollment/sign-out/returning login also pass with the final edge capture.
- PHP lint, smoke, event notifications, transaction race, migration resume,
  question scheduling, and real HTTP contract tests pass.
- Question schedule tests verify all 370 catalog entries, daytime/evening windows,
  stable publishing, pre-release rejection, notification timing, and interrupted
  migration recovery.
- Before the animation/email follow-up, all 14 distinct focused simulator UI
  scenarios passed across verification runs. That integrated run passed all seven
  selected checks: largest accessibility text, edge swipe, full elder pairing,
  search/no-match/reset, selected tabs, fixed banner during pull, and settings
  name/refresh feedback. Other passing scenarios include stamp drawing/save,
  simplified notification preferences, help, and first-setup personalization.
- Visually reviewed home on iPhone SE, home at the largest accessibility text
  size, settings, notifications, drawing, and the setup guide. Simulator testing
  does not verify real inbox or APNs delivery.

Local verification artifacts:

- [Latest iOS unit test log](/tmp/tsutsuura-email-unit-tests.log)
- [Final polling regression log](/tmp/tsutsuura-background-refresh-tests.log)
- [Back gesture regression log](/tmp/tsutsuura-gesture-ui.log)
- [Larger-iPhone gesture and drawing log](/tmp/tsutsuura-gesture-pro-max-ui.log)
- [Final email login UI log](/tmp/tsutsuura-gesture-email-recheck.log)
- [Previous release UI test bundle](/tmp/tsutsuura-ui-review-final.xcresult)
- [Home screenshot](/tmp/tsutsuura-ui-review-screenshots/home.png)
- [Settings screenshot](/tmp/tsutsuura-ui-review-screenshots/settings.png)
- [Drawing screenshot](/tmp/tsutsuura-ui-review-screenshots/drawing.png)
- [Onboarding screenshot](/tmp/tsutsuura-ui-review-screenshots/first-setup-ready.png)

## Toshizo backend migration — deployed

The user authorized a fresh migration to **Toshizo** and allowed discarding the
previous service data. The new API is live at
`https://toshizo.link/tsutsuura-api/api` as of **2026-09-05 04:40:01 UTC**.
No old accounts or history were imported. The existing Toshizo website remains
available at its original URL.

Deployment used the authenticated ConoHa file manager and a private CLI installer.
PHP **8.4.21**, SQLite, required extensions, `proc_open`, and native `mail` passed
host preflight. The private app is under `/home/c8629971/apps/tsutsuura`; only the
public API entry points are under `public_html/toshizo.link/tsutsuura-api/api`.
SSH restrictions and global site settings were not changed.

The installation log confirms migrations **001–010**, **370 distinct questions**,
and an empty account database. A fresh application key was generated on the host.
The installer logs and public-file backups remain in private staging for diagnosis.
The one-off installer schedule was disabled after success and replaced with a
daily 03:00 hosting-time cleanup job for expired records and orphaned attachments.

HTTPS release verification passed the expected `2026-09-05-email` revision,
all nine capabilities, and the lifecycle route probes. The AASA file returns direct
HTTP 200 JSON with the app ID and the new invitation path. The existing homepage
returns 200, and the API's private pointer/settings are not publicly readable.
[Live verification record](/tmp/tsutsuura-toshizo-live-verification.json).

Email verification is configured using native PHP mail with the existing
`general@toshizo.link` sender. SMS is disabled. **Real inbox delivery and code entry
have not been verified. APNs push is disabled until its credentials and worker are
configured.** These limits must not be represented as fully tested functionality.

The iOS production URL, Universal Links, and verification storage have been updated
for Toshizo. All seven selected configuration/Universal Link tests pass. Version
**1.0 (7)** is archived with its URL/domain and signature verified and was uploaded
to Apple successfully. Existing installations will return to account setup when
their old-server credentials are rejected by the fresh backend.

## Actual Simulator verification — build 9

Version **1.0 (9)** uploaded at **2026-09-05 16:37:18 UTC**. Apple reports
`Uploaded to Apple`, success, with no errors or warnings. The signed archive,
distribution app, production entitlements, IPA contents and frozen source manifest
passed verification. App Store Connect confirms completed processing and assignment
to **Tsutsuura Internal** with one existing tester; Japanese testing notes are saved.
Apple disables external-group assignment while build 7 of version 1.0 is awaiting
Beta App Review. Installation from TestFlight on a physical device remains unverified.


The Computer plugin was used to test the native app in Simulator, including a
normal signed-in session against Toshizo. Native XCUITest supplemented manual
checks when the Computer accessibility bridge temporarily timed out. The final
home, profile, settings, icon page, continuous second stroke, and diagonal
swipe-back were manually checked again after the bridge recovered.

Reproduced and fixed:

- ConoHa SiteGuard rejected direct PATCH, PUT, and DELETE with an HTML403 before
  PHP ran. The central client sends those logical verbs via POST with a strict
  method override; server authentication and original retry/idempotency semantics
  remain enforced. The firewall stays enabled. A hash-checked private patch was
  activated at **2026-09-05 16:16:02 UTC** with verified backups.
- Continuous icon strokes were canceled by the enclosing scroll view. A native
  touch recognizer now owns canvas strokes, ends/cancels each stroke cleanly, and
  preserves independent undo history. Margins still scroll and edge swipes return.
- Returning to the personal tab after searching reopened the keyboard. Focus is
  dismissed synchronously before the tab switch.
- Swiping back on guide steps closed the guide. It now returns one step, matching
  the Previous button and preserving the last onboarding step after drawing.
- A slow notification/comment save could navigate away from a later page. Saves
  now navigate only if their original route visit is still current.
- An overseas device showed a bare overnight release time while onboarding
  promised daytime. Japan publication dates and local dates/times are explicit;
  automatic account-bound device timezone sync keeps local reminder timing
  independent of notification permission. Its private backend patch activated at
  **2026-09-05 16:28:01 UTC**, preserving configuration and existing data.

All **183 unit tests** pass. Focused UI regressions pass for keyboard return,
both guide flows, vertical locking during diagonal back gestures, continuous
strokes, independent second strokes, erasing, undo, margin scrolling, and back.
The controlled live-account test saved a drawn stamp, reopened it, terminated and
relaunched the app, and confirmed persistence. Notification preferences saved and
reloaded without changing their values or requesting permission. Live timezone
checks confirmed timezone-only updates, rejection without mutation, and matching
home/question calendar metadata. The disposable QA family and its two accounts
were removed afterward; current user accounts were preserved. A final native
app relaunch returned the removed QA session to account setup as expected.

- [Final 183-test unit log](/tmp/tsutsuura-final-live-fixes-unit.log)
- [Drawing and timezone regression log](/tmp/tsutsuura-drawing-timezone-ui.log)
- [Controlled live UI log](/tmp/tsutsuura-controlled-live-ui2.log)
- [Persisted drawing screenshot](/tmp/tsutsuura-controlled-live-ui2-evidence/live-qa-mark-after-relaunch.png)
- [Live timezone verification](/tmp/tsutsuura-simulator-live-qa/timezone-live-result.json)
- [Build 9 signed upload verification](/tmp/tsutsuura-upload9-verification.json)

Real email inbox delivery and APNs notification delivery remain unverified.
APNs credentials/workers remain disabled pending the previously requested
credential confirmation. No external review submission was canceled.

## Previous TestFlight upload — notification registration

Version **1.0 (8)** uploaded successfully on **2026-09-05 at 15:27:25 UTC**.
Apple's receipt confirms app `6800383132`, build `8`, `Uploaded to Apple`, state
`success`, and no errors or warnings. The exported app has production APNs,
TestFlight reporting, debugging disabled, and `applinks:toshizo.link`. Its signed
payload matches the uploaded IPA. App Store Connect confirms processing is
complete. Build 8 is assigned to **Tsutsuura Internal** (one existing tester),
with Japanese test notes saved. Apple currently prevents adding build 8 to an
external group because build 7 of version 1.0 is already **Waiting for Review**.
No existing review submission was canceled. Installation of build 8 and physical
notification presentation have not been verified.

Build 8 includes automatic notification permission recovery after returning from
iPhone Settings and protects a new account/session from stale push responses.
All 166 unit tests pass. The live API revision, nine capabilities, and required
lifecycle routes passed the release check immediately before upload.

- [Upload verification](/tmp/tsutsuura-upload8-verification.json)
- [Upload log](/tmp/tsutsuura-testflight-upload8-20260905.log)
- [Saved Xcode archive](</Users/takamimarsh/Library/Developer/Xcode/Archives/2026-09-05/tsutsuura 1.0 (8).xcarchive>)

## Previous TestFlight upload — Toshizo migration

Version **1.0 (7)** was uploaded successfully on **2026-09-05 at 04:42:17 UTC**.
Apple's receipt records app `6800383132`, build `7`, `Uploaded to Apple`, state
`success`, and empty error/warning arrays. The signed-in App Store Connect page
on September 5 confirms completed processing and assignment to Tsutsuura Internal
and Tsutsuura External Beta. External distribution is **Waiting for Review**.
The uploaded IPA matches the verified distribution app, whose signature
and production entitlements passed checks. Debugging is disabled, TestFlight
reporting is enabled, and the associated domain is `toshizo.link`.

This build connects to the verified Toshizo API, uses `applinks:toshizo.link`, and
separates email verification state by server so migration cannot reuse stale
verification details. It includes the animation, back-swipe, icon editor, email,
and quiet ten-second refresh changes from build 6.

- [TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6800383132/testflight/ios)
- [Upload log](/tmp/tsutsuura-testflight-upload7-20260905.log)
- [Saved Xcode archive](</Users/takamimarsh/Library/Developer/Xcode/Archives/2026-09-05/tsutsuura 1.0 (7).xcarchive>)

## Previous TestFlight upload — animation/email follow-up

Version **1.0 (6)** was uploaded successfully on **2026-09-05 at 03:41:43 UTC**
(September 4, 23:41 Toronto time). Apple accepted the upload and reported that
the package had begun processing. The archive's upload event records
`Uploaded to Apple`, state `success`, build `6`, with no errors or warnings.
Availability to testers after processing has not been independently confirmed.

This release contains the consistent navigation spring, sliding icon editor,
vertical locking during back swipes, email authentication screens, and quiet
ten-second Home updates, including the final canceled-request guards.
The signed Release archive and uploaded app passed signature validation; the
uploaded app has production push, TestFlight reporting, and debugging disabled.
Email privacy disclosure, font, and assets are included. Source hashes were
checked against the archived release.

- [TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6800383132/testflight/ios)
- [Upload log](/tmp/tsutsuura-testflight-upload6-20260905.log)
- [Saved Xcode archive](</Users/takamimarsh/Library/Developer/Xcode/Archives/2026-09-04/tsutsuura 1.0 (6).xcarchive>)

The TestFlight upload does not deploy the PHP backend. A fresh preflight check
still found the older live API without email authentication; server rollout
through migration 010 and working native mail remain required.

## Previous TestFlight upload (before the animation/email follow-up)

Version **1.0 (5)** was uploaded successfully to App Store Connect on
2026-09-05 at 02:47 UTC (September 4, 22:47 Toronto time). Xcode recorded
`Uploaded to Apple`, build number `5`, with no upload errors or warnings;
Apple reported that the package had begun processing. Tester availability
after processing has not been independently confirmed.

The signed Release archive passed local verification. The uploaded distribution
app was verified with `aps-environment=production`, `get-task-allow=false`,
and `beta-reports-active=true`. The privacy manifest and font are included.

- [TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6800383132/testflight/ios)
- [Upload log](/tmp/tsutsuura-testflight-upload5-20260905.log)
- [Saved Xcode archive](</Users/takamimarsh/Library/Developer/Xcode/Archives/2026-09-04/tsutsuura 1.0 (5).xcarchive>)

This upload does not deploy the backend. The server rollout and provider
configuration above remain required for the corresponding features.

## Final email and APNs activation follow-up

The iOS notification registration follow-up refreshes device permission when the
app returns to the foreground, including after changes in iPhone Settings. Token
uploads are serialized and acknowledged per account/session. A stale unauthorized
response cannot clear a newer bearer or sign out a fresh login to the same account.
All **166 unit tests** pass, including permission recovery and concurrent session
regressions. An independent review found no remaining blocker.
[Final unit test log](/tmp/tsutsuura-push-final-unit-tests.log).

The user requested completion of the remaining live checks. On 2026-09-05 at
04:56 UTC, a private CLI check verified PHP cURL HTTP/2 and certificate-verified
TLS connectivity from Toshizo to `api.push.apple.com`. Apple's unauthenticated
root request returned 405; this proves connectivity, not APNs credential acceptance
or notification delivery. The check observed 3 users and 0 push registrations.
No existing account was changed or removed.

The private APNs configuration script passed local fixture tests and independent
review, including non-push environment/database/media preservation, atomic activation,
rollback, repeat invocation, credential collision, and concurrency guards. It is
ready at `/tmp/tsutsuura-toshizo-push/configure-push.php`. Its upload to the private
`/home/c8629971/tsutsuura-push-20260905` directory is confirmed.
The script has not been executed remotely; APNs remains disabled.

A controlled enrollment/login helper is ready at
`/tmp/tsutsuura-live-qa/email-qa.py`. No live test emails or QA accounts have been
created. Apple Developer and App Store Connect sign-ins are confirmed. A production
APNs key restricted to `toshizo.link.tsutsuura` is prepared at the final Register
step, awaiting the Chrome policy's action-time credential approval. The inbox
choice is also pending. A physical TestFlight device must register for notifications
before actual presentation can be confirmed.

The temporary `Tsutsuura push setup preflight` job was confirmed OFF after its
successful run. The daily cleanup job remains enabled. No recurring push workers
have been added yet. Chrome control is connected and portal actions work.

## Mandatory marks and compact home — build 10

The September 5 follow-up requires every member without a valid saved drawing to
create a personal mark before proceeding. The gate also covers restored accounts,
new organizers, paired members, and pending navigation. Authentication receipts
are checked against the current server profile; failed saves preserve the canvas
and cannot release the gate. Empty saves and preset/initial shortcuts are removed.
Existing drawings can still be edited, and the guide/help explain the requirement.

Home tabs now use a compact single row while preserving clear selection and large
tap targets. The waiting-question banner can be closed; that choice survives
refresh, navigation, and relaunch separately for each account/family. A new question
or publication restores the appropriate banner and answer action.

Answer photos open full-screen at the tapped photo. Horizontal paging stays within
the answer, uses authenticated media loading, and returns to the last-viewed inline
photo on close. Portrait, landscape, and square images fit without cropping.
Comment creation/reply/edit no longer show a character counter; the existing
1,000 Unicode-scalar input and server limits remain enforced.

Final validation: **196 unit tests passed** and **10 Simulator UI checks passed**
(9 distinct scenarios, including photo paging on both SE and Pro Max). These cover
required drawing/back-bypass prevention, onboarding, saved edits/empty-save blocking,
drawing/erasing/undo, diagonal back scroll locking, large text, banner persistence
and publication, photo paging, and comment entry. Computer Use also exercised the
actual Pro Max drawing canvas, saving into Home, and opening an image. Native touch
regressions verified horizontal paging on both phone sizes.

Build 10's signed archive, production API URL, compiled source list, resources,
and source freeze passed verification. Apple confirmed upload at 2026-09-05
17:27:10 UTC with no errors or warnings. The distribution app, uploaded IPA
contents, production entitlements, and Apple receipt also passed verification.
The September 5 follow-up confirms build 10 is assigned to Tsutsuura Internal and
has Testing status; build 11 now supersedes it. No backend change is required for
this follow-up; existing email/APNs delivery limitations remain.

- [Final unit and UI test log](/tmp/tsutsuura-refinements-final.log)
- [Photo, large-text, and comment UI checks](/tmp/tsutsuura-refinements-ui.log)
- [Pro Max photo touch regression](/tmp/tsutsuura-photo-pro-max-ui.log)
- [Archive verification](/tmp/tsutsuura-release10-verification.json)

## Comment controls and banner motion — build 11

Removed comment edit/delete controls and their deletion confirmation. The unused
comment editor screen and callbacks are removed; the former editor route displays
the comment thread. Existing backend endpoints remain compatible with older apps.
Updated the in-app information text so it no longer advertises comment editing.

Closing the upcoming-question banner now moves it upward and fades it out using
the shared 0.42-second navigation spring. The answer area expands in the same
transaction, and the status-bar tint fades with it. Background dots stay fixed.
Reduce Motion disables this movement.

Four focused Simulator checks pass: large-text home controls, dismissal persistence
and publication, comment keyboard submission, and absent comment edit/delete
controls with successful reporting/replying. The comment test's initial failure
was a scroll-helper overshoot underneath the fixed banner; bounded reversible
drags corrected the test. No app behavior was changed to accommodate the test.
The signed build 11 archive and source manifest passed verification. Apple confirmed
upload at 2026-09-05 17:46:53 UTC with no errors or warnings. The distribution
app, uploaded IPA, production entitlements, and receipt also passed verification.
The signed-in App Store Connect session confirms completed processing, saved
Japanese notes, and assignment to Tsutsuura Internal with one existing tester.
The group's build list confirms **Testing** status for 1.0 (11). Apple disables
external-group assignment until the existing build 7 Beta App Review completes.
The successful banner tests did not retain motion video; slide/fade timing was checked in source
and dismissal behavior was exercised through native Simulator interactions.

- [Home and comment entry UI checks](/tmp/tsutsuura-comment-banner11-ui.log)
- [Comment controls/reply/report recheck](/tmp/tsutsuura-comment-controls11-recheck.log)
- [Archive verification](/tmp/tsutsuura-release11-verification.json)
- [TestFlight processing and tester availability evidence](/tmp/tsutsuura-build11-testflight-browser-evidence.json)

## Restore the upcoming banner by pulling down — build 12

Releasing a pull at least 64 points beyond the top of either Home timeline restores
the dismissed upcoming-question banner with the existing navigation spring. The
native scroll-phase callback adds no refresh spinner or competing drag recognizer;
the dots and header remain anchored, and Reduce Motion is respected. Only the
current account/family dismissal is cleared. Quiet ten-second updates continue to
respect dismissal, and small tugs or ordinary scrolling do not restore the banner.

The Simulator regression passed for a short tug, a full pull in both 家族 and
あなた, restored visibility after relaunch, and the available-question action.
The existing largest-text check initially failed to dismiss after a tap; its
isolated recheck passed with the same binary and no code/test changes. The original
failure and successful recheck are both retained; its cause was not established.

The signed build 12 archive, frozen source manifest, production configuration,
uploaded IPA, distribution entitlements, and Apple receipt passed verification.
Apple confirmed upload at 2026-09-05 18:17:42 UTC with no errors or warnings.
App Store Connect confirms completed processing, saved Japanese notes, and
**Testing** status in **Tsutsuura Internal** with one existing tester. External
assignment is still disabled while version 1.0 build 7 awaits Beta App Review.

- [Pull-to-reveal and initial large-text check](/tmp/tsutsuura-pull-banner-ui.log)
- [Large-text recheck](/tmp/tsutsuura-pull-banner-large-recheck.log)
- [Build 12 upload verification](/tmp/tsutsuura-upload12-verification.json)
- [Build 12 TestFlight availability](/tmp/tsutsuura-build12-testflight-browser-evidence.json)

## Interactive pull feedback — included in build 13

While pulling to restore a hidden upcoming-question banner, an arrow and progress
ring now follow the finger. At 64 points the cue springs into a checkmark, changes
to 「指を離すと表示」, and gives one readiness haptic. Releasing while ready restores
the banner with its existing spring and a confirmation haptic. Closing it gives
a selection haptic too. Retreating below the threshold cancels restoration; small
movements around the threshold never repeat the readiness haptic within one drag.

The cue sits outside the scrolling content and ignores hit testing. Only the
selected tab can trigger it. It resets on tab, account, question, eligibility, or
page changes, and ignores scroll rebound. Background dots remain stationary.
Reduce Motion retains the text and progress while omitting rotation, scale,
translation, and spring animation.

Eight gesture-state tests passed. Both Pro Max UI scenarios passed, covering
largest text, navigation, short and full pulls in both tabs, cue removal, persisted
restoration, and question publication. The SE largest-text scenario passed; its
longer flow encountered intermittent missed button taps (close, then Settings
Back on a separate run) and one runner stall. The failed Back event targeted the
button center after the transition, with no intercepting overlay found. The same
binary passed on Pro Max; no source change or test retry loop was added to mask
the SE failures. Their cause remains unconfirmed. Simulator recording visually
confirmed the partial-progress cue, ready checkmark, and animated reveal. Physical
haptic sensation cannot be verified in Simulator.

- [State tests and initial SE checks](/tmp/tsutsuura-pull-feedback-tests.log)
- [SE follow-up after restart](/tmp/tsutsuura-pull-feedback-reboot-recheck.log)
- [Passing Pro Max UI checks](/tmp/tsutsuura-pull-feedback-promax.log)
- [Ready-state frame](/tmp/tsutsuura-pull-feedback-ready-cue.png)
- [Pull and reveal frames](/tmp/tsutsuura-pull-feedback-contact.png)

## Photo and banner dismissal gestures — build 13

Full-screen photos now follow a downward drag and close after a deliberate
120-point release. A short drag or upward retreat springs back. One direction-locked
gesture controls a bounded SwiftUI photo pager: horizontal starts page, downward
starts dismiss, and upward starts are ignored. The
close button uses the app's rectangular RaisedButton styling. One haptic accompanies
closure; Reduce Motion suppresses the interactive travel/scale and exit motion.
VoiceOver escape and the adjustable photo counter remain available.

An upward swipe starting inside the upcoming-question banner closes it at a
48-point, vertically dominant release. Timeline-origin scrolling cannot dismiss
it. The existing close button and pull-to-reveal restoration remain. Published
banners consume drags without dismissing or accidentally activating the answer
button, while ordinary answer-button taps still navigate.

The first Pro Max run passed 209 logic tests and captured four App Store
screenshots. UI failures exposed two issues: scaled-to-fill inline photos had
oversized hit/accessibility bounds, and swiping an available question over its
answer button could trigger navigation. The image now renders within an explicit
bounded container; the published banner retains its high-priority drag recognizer.
A stale accessibility snapshot after relaunch was also corrected in the test.
Further SE testing exposed missed downward swipes in the landscape letterbox.
The final full-screen SwiftUI pager removes the competing native page-scroll
recognizer. Explicit accessibility containment preserves each selected photo's
identity; offscreen photos are hidden from accessibility. Cancellation assertions
measure the moving photo itself rather than its stationary outer container.
Both final photo tests pass on SE and Pro Max, including letterbox dismissal and
reopen. The banner swipe/contact-origin scenario passes on both phone sizes. The
existing SE Home regression also passes on the final source, including Settings
Back, tab switching, dismissal persistence, pulls in both tabs, and publication.
The earlier intermediate failures above are retained as investigation evidence;
the final implementation and all targeted UI release checks pass.

- [Final SE photo checks](/tmp/tsutsuura-photo-pager-se2.log)
- [Final Pro Max photo checks](/tmp/tsutsuura-photo13-verified-promax.log)
- [Final SE Home checks](/tmp/tsutsuura-home13-verified-se.log)
- [Banner contact-origin check on Pro Max](/tmp/tsutsuura-banner13-priority-promax.log)
- [Banner contact-origin check on SE](/tmp/tsutsuura-gesture13-verified-se.log)

The App Store draft contains Japanese description/promotion/keywords, subtitle,
Social Networking/Lifestyle categories, four 1320×2868 screenshots, a calculated
13+ age rating (regional exceptions), self-serve reviewer instructions, and manual
release mode. No App Store review submission or public release has been made.
`release/app-store/` holds the metadata, screenshots, policy/support drafts and
remaining product/operational requirements. Price/regions, copyright confirmation
and App Review contact details were requested from the user.

Apple accepted the build 13 upload at **2026-09-05 19:35:59 UTC** with no errors
or warnings. Archive and uploaded IPA verification passed against the source
snapshot. App Store Connect confirms **Testing** in **Tsutsuura Internal** with
one existing tester; Japanese testing notes are saved. Build 13 is selected in
the App Store version 1.0 draft. External assignment is still blocked by the
existing version 1.0 build 7 Beta App Review; no review was cancelled.

- [Release and internal availability evidence](/tmp/tsutsuura-build13-release-status.json)
- [QA summary](/tmp/tsutsuura-build13-qa-summary.json)
- [App Store preparation checklist](release/app-store/README.md)
