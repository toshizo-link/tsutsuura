# iOS push validation — build 16

Source frozen. The complete unit suite passed **217 tests, 0 failures**. The separate onboarding/push run passed **25 tests, 0 failures**, including four UI scenarios on iPhone SE (3rd generation), iOS 26.5. Both xcodebuild processes exited 0. Exact source hashes, result bundle paths, and coverage are in `evidence.json`; native result summaries and logs are included.

The changes repair overlapping/retained push navigation, stale account responses, and an explicit opt-in being lost behind a passive permission query. The final guide now offers an optional notification button, keeps finishing available, confirms permission, and sends denied users to iPhone Settings without prompting repeatedly.

The two PNGs are unchanged native XCTest screenshots. The guide scrolls on SE; the initial view shows the opt-in label and persistent finish button, with the opt-in lower bevel/footer available by scrolling. Permission choices are simulated only for DEBUG UI tests. Real APNs delivery requires a registered physical-device token and backend/Apple delivery evidence.

After successful UI tests, Xcode stalled collecting simulator diagnostics. Only its `simctl diagnose` child was stopped; Xcode then finalized the valid passing result bundle. The later notification-preference account-generation guard was validated by the final complete unit run; no onboarding UI source changed after the UI run.
