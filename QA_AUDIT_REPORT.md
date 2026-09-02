# Tsutsuura whole-app manual QA audit

Date: 2026-08-30  
App: `toshizo.link.tsutsuura`  
Test OS: iOS/iPadOS 26.5 Simulator  
Method: end-to-end manual interaction through Computer Use, from the user-facing UI

## Executive summary

The central concept and the main happy path work: a caregiver can create a family, add a managed family member, issue a one-time setup code, pair the second user, answer a daily question with text/photos, and participate in comments and likes. I did not encounter an app crash in the exercised flows.

The app is not release-ready for its stated elder/family audience, however. The highest-risk findings are:

1. Accessibility Dynamic Type sizes make core actions disappear and cannot be recovered by scrolling.
2. Returning-user phone login and OTP screens exist but are unreachable from the signed-out UI, creating an account-recovery hole that is made worse by immediate logout.
3. The Back control on pairing confirmation repeatedly failed, trapping the user if the preview is wrong.
4. Several core color combinations are below even the 3:1 large-text contrast reference, and Increase Contrast does not provide an alternate presentation.

There are also serious responsive-layout, safe-area, voice-permission, family-management, social-action, and assistive-technology problems. The recommended first milestone is to replace the fixed 440×956 scaling model with an adaptive, scrollable layout and to repair authentication/recovery before adding more features.

## Scope and environments

### Devices and configurations

- iPhone 17 Pro Max, iOS 26.5
  - Authenticated and signed-out demo sessions
  - Default text size, largest standard Dynamic Type size, first Accessibility size, and largest Accessibility size
  - Light appearance, Dark appearance, Increase Contrast, and Reduce Motion
  - Foreground/background restoration and portrait orientation
- iPhone SE (3rd generation), iOS 26.5
  - Signed-out welcome and caregiver setup
  - Authenticated home and answer composer
  - Keyboard-present layouts
- iPad (A16), iPadOS 26.5
  - Authenticated family feed, profile, and settings
  - Portrait and landscape

The primary behavioral backend was the app's deterministic demo API. This avoided mutating real family data while still exercising the UI, state transitions, photo picker, permission prompt, and complete organizer/pairing flow. Source inspection and successful debug builds on all three simulators were used only to corroborate reachability and likely root causes; they did not replace manual UI testing.

### Severity

- **P0 — Critical:** crash, data loss, security/privacy exposure, or total outage.
- **P1 — High:** blocks a core journey, can lock out a user, or excludes an accessibility population.
- **P2 — Medium:** materially degrades a journey but has a workaround.
- **P3 — Low:** polish, clarity, consistency, or lower-risk feature completeness.

No P0 issue was found in this pass.

## Coverage matrix

| Area | Result | What was exercised |
|---|---|---|
| App launch/restoration | Partial | Launch, demo session restore, foreground/background. Live expired-token and server-outage retry were not forced. |
| Signed-out welcome | Tested | Both caregiver and this-iPhone branches. |
| Caregiver setup | Tested | Name entry, automatic/custom family name, long input, keyboard, continue, add/cancel member, finish. |
| Family management | Tested | Member list, add managed member, issue/reissue invite, refresh, return. |
| Invite sharing | Tested with follow-up | QR/code screen and completion. Share sheet failed to appear in Simulator and needs physical-device confirmation. |
| Pairing by code | Tested | Non-digit filtering, incomplete input, invalid code, valid code, confirmation, ready screen, managed-user home. |
| Pairing by link | Blocked | The share sheet did not present, so the user-originated universal-link path could not be completed reliably. |
| Phone login/OTP | Blocked by product | Screens are implemented but no signed-out control navigates to phone entry. |
| Family feed | Tested | Today prompt, progress, multiple cards, scrolling, empty feed, media, likes/comments availability. |
| Personal history | Tested | Profile tab, populated and empty history, settings entry. |
| Text answer | Tested | Empty/filled states, keyboard, draft persistence, submit, success state, feed update. |
| Photo answer | Tested | Picker, 1–4 photos, attempted fifth photo, removal, submission, rendered media. |
| Voice answer | Partial | Permission-denied path and retry behavior. Successful transcription/audio upload requires explicit microphone and Speech Recognition permission plus a live audio input. |
| Likes | Tested | Like/unlike another answer and own answer; count/state changes. |
| Comments | Tested | Empty thread, add comment, existing thread, keyboard, return. |
| Settings | Tested | Empty/valid display-name behavior, save, refresh, owner/managed variants, logout. |
| Accessibility | Tested | Dynamic Type, Dark appearance, Increase Contrast, Reduce Motion, accessibility tree/labels, keyboard layouts, compact phone and iPad. |
| Push notification | Environment-limited | Simulated delivery was attempted but no observable notification was produced in the current permission/simulator state. Requires signed-device validation. |

## Confirmed findings

### QA-01 — P1 — Accessibility text sizes make essential controls unreachable

**Reproduction**

1. Open the signed-out welcome screen on iPhone 17 Pro Max.
2. In iOS Settings, set Larger Text to the first Accessibility size.
3. Return to the app.

**Observed**

- At the first Accessibility tier, `このiPhoneを設定` moves below the viewport.
- The welcome page is not scrollable, so there is no way to reach it.
- At the largest Accessibility tier, both `家族をつくる` and `このiPhoneを設定` disappear.
- Settings degrades further: Back/title placement breaks, family/name text truncates, and `保存` and tab labels collapse to `…`.
- The family home becomes functionally unusable at the largest tier.

**Expected**

All content should reflow, wrap, and scroll while keeping every primary action reachable at every supported Dynamic Type size.

**Impact**

Users who need larger text—including the app's likely elder audience—cannot start or operate the app.

**Recommendation**

Replace the fixed canvas with adaptive stacks and scroll containers; avoid fixed-height cards for text; test every route through all Accessibility sizes. Add UI tests that assert primary controls are both present and hittable. The fixed `.frame(width: 440, height: 956)` and scale-to-fit approach is visible in `ContentView.swift` and `TsutsuuraDesignSystem.swift`.

### QA-02 — P1 — Returning-user phone authentication is unreachable, and logout can create lockout

**Reproduction**

1. Open the signed-out app, or log out from Settings.
2. Inspect every action on the welcome screen.

**Observed**

- The only actions are `家族をつくる` and `このiPhoneを設定`.
- There is no login, phone-number, returning-user, or account-recovery action.
- `LoginScreen`, `SMSVerificationScreen`, `.phoneEntry`, and `.otpVerification` exist, but the signed-out route defaults to onboarding and no visible control enters `.phoneEntry`.
- Logout happens immediately without confirmation.
- A managed user's one-time pairing credential has already been consumed; after logout, that user needs another caregiver-issued invite. A family owner can be in an even worse recovery position.

**Expected**

Signed-out users should have a clear `電話番号でログイン`/`以前のアカウントに戻る` path. Logout should explain the recovery consequence and require confirmation, especially for managed devices.

**Impact**

Users can lose access to an existing account or require remote caregiver intervention. This is a core lifecycle failure, not only a missing convenience.

**Recommendation**

Add a returning-user route on the welcome screen, complete OTP recovery, and add a role-aware logout confirmation. For managed devices, consider caregiver authorization, a recovery code, or explicit wording that a new invite will be required.

### QA-03 — P1 — Pairing confirmation Back control does not navigate

**Reproduction**

1. Create a family and managed member in the same demo session.
2. Log out, choose `このiPhoneを設定`, enter the issued six-digit code, and continue.
3. On `内容を確認`, activate `戻る`.

**Observed**

Repeated accessibility activation and direct taps on the visible Back target produced no transition. The forward `このiPhoneを設定する` button worked immediately.

**Expected**

Back should return to code entry so a recipient can correct a wrong family/member preview.

**Impact**

The user is trapped at a consequential identity confirmation. Their only practical escape is terminating/restarting the app.

**Recommendation**

Inspect hit testing and overlays around `FamilySetupHeader`, enlarge/verify the full button shape, and add a UI test that specifically enters confirmation and returns to code entry.

### QA-04 — P1 — Core text and button palettes have insufficient contrast

The following source-defined combinations were measured with the standard relative-luminance formula:

| Combination | Measured ratio |
|---|---:|
| White on cyan `#31ADD6` | 2.60:1 |
| White on green `#4FC446` | 2.25:1 |
| White on orange `#EFA56F` | 2.04:1 |
| White on coral `#FF858C` | 2.34:1 |
| Muted text `#91A8AC` on sky `#D7F0F7` | 2.11:1 |

All are below the commonly used 3:1 large-text reference, as well as the 4.5:1 normal-text reference. These combinations are used for primary buttons, phone text, placeholders, dates, and secondary instructions. Turning on iOS Increase Contrast produced no meaningful visual adaptation.

**Impact**

Important actions and metadata are difficult to read for users with low vision or reduced contrast sensitivity.

**Recommendation**

Darken colored button fills or switch to dark text, replace `skyMuted` with a substantially darker semantic color, and provide an Increased Contrast variant through the environment. Validate rendered states, including disabled controls. Reference: [W3C WCAG 2.2 contrast technique G18](https://www.w3.org/WAI/WCAG22/Techniques/general/G18.html).

### QA-05 — P2 — Fixed 440×956 scaling produces poor compact-phone and iPad experiences

**Observed on iPhone SE**

- The whole 440×956 canvas scales to approximately 69.8% because height is the limiting dimension.
- A nominal 19-point secondary label becomes roughly 13 points.
- Some authored targets under roughly 63 points become smaller than a 44-point touch target.
- The keyboard covers the caregiver setup primary action; the user must discover `閉じる` before continuing.

**Observed on iPad (A16)**

- The target explicitly supports iPad and all iPad orientations.
- Portrait is a centered phone canvas with large unused side regions.
- Landscape is a narrow column only about 378 points wide on an approximately 1180-point-wide screen—roughly one-third of the available width.
- Feed and Settings do not rearrange for tablet use.

**Recommendation**

Build adaptive layouts using size classes and safe-area-aware containers. If that work is not in scope for launch, remove iPad from `TARGETED_DEVICE_FAMILY` rather than shipping a nominally supported but poor experience.

### QA-06 — P2 — Scrolled feed content renders beneath the status area/Dynamic Island

**Reproduction**

1. Open a populated family feed on iPhone 17 Pro Max.
2. Scroll until a card reaches the top.

**Observed**

Author, date, question text, and media can move behind the status bar/Dynamic Island and become obscured. The root layout ignores all container safe areas.

**Expected**

Scrollable content should stop below the top safe-area inset, while decorative background may extend edge-to-edge.

**Recommendation**

Apply `ignoresSafeArea` only to the backdrop, not the complete content canvas, and add a safe-area top inset to scrolling content.

### QA-07 — P2 — Like and comment actions are hidden until today's question is answered

**Reproduction**

1. Launch the authenticated demo before answering today's question.
2. Inspect existing historical cards in both Family and Profile.
3. Submit today's answer and inspect the same cards again.

**Observed**

Before answering, historical cards have no like/comment controls. After answering, those controls appear. This is not explained in the UI. The behavior is explicitly tied to `feed.todayQuestion?.answer == nil`.

**Expected**

Reading and participating in existing family conversation should not be conditional on answering today's prompt, unless this is a deliberate rule with clear rationale and disclosure.

**Impact**

Users may conclude that social features do not exist, and a user who cannot answer today is prevented from supporting family members.

**Recommendation**

Always show the controls. If participation gating is a firm product decision, show disabled controls with an explanation rather than removing them.

### QA-08 — P2 — Add-member forms and completion actions clip or disappear

**Observed**

- In family management, expanding `つつうらを使う方を追加` pushes `やめる` to the bottom where it is clipped and difficult to discover.
- With the keyboard shown, the managed-member input/action region is partly hidden.
- During first-time family setup, the green Finish action can collapse to a thin visible strip or move offscreen while the add-member form is expanded.

**Expected**

The active field, submit action, cancel action, and page completion action should remain reachable through scrolling and keyboard avoidance.

**Recommendation**

Use one scroll view with focused-field scrolling, keyboard safe-area padding, and a sticky footer only when it does not overlap content. Do not render the Finish action behind an expanded sub-form.

### QA-09 — P2 — Voice permission denial leaves a false listening state with no recovery

**Reproduction**

1. Open today's question and choose `声で回答`.
2. Deny Speech Recognition permission.

**Observed**

- The screen continues to say `声を聞いています…` and presents a listening waveform.
- A red permission error appears, but the record control remains tappable.
- Repeated retry taps cause no visible state change.
- `この回答` remains disabled.
- There is no `設定を開く`, explanation of which permissions are needed, or text-answer escape other than canceling the entire voice screen.

**Expected**

A denied state should stop the listening animation, clearly state that recording did not begin, and offer `設定を開く` and `テキストで回答する`.

**Recommendation**

Model permission states separately from recording states, stop audio UI on denial, and provide a direct Settings recovery action.

### QA-10 — P2 — Family response progress is unclear visually and inaccessible semantically

**Observed**

- Progress is shown as anonymous colored rectangles plus a vertical `確認` label.
- Individual segments do not identify which member answered or is still pending.
- Assistive output exposes decorative `xmark.circle.fill` items as `Close` and only a total such as `1人/3人 回答済`.

**Expected**

Each member/state should be understandable without interpreting color or decoration, for example `あおい：回答済み`, `おばあちゃん：未回答`.

**Recommendation**

Use named rows/avatars or a labeled summary with a detail view. Hide decorative icons from accessibility and provide a combined, descriptive label.

### QA-11 — P2 — Accessibility labels expose misleading decorative names and raw symbols

Examples observed in the accessibility tree:

- The answer-card envelope avatar is announced as `Mark Read`.
- Progress `xmark.circle.fill` symbols are announced as actionable `Close` items.
- Empty-state art is announced as raw symbol names such as `person.3.fill` and `text.book.closed.fill`.
- The tap-to-dismiss error toast is exposed as text, not as a dismissible alert/action.

**Impact**

VoiceOver users hear unrelated actions and implementation names, creating a substantially different and confusing interface.

**Recommendation**

Mark decorative images `.accessibilityHidden(true)`, give meaningful labels to semantic images, group card headers appropriately, and expose errors as announcements with a labeled Dismiss action.

### QA-12 — P2 — Honorific handling produces awkward/doubled names

**Reproduction**

1. Use the provided example and add a member named `おばあちゃん`.
2. Continue to the share and ready screens.

**Observed**

Copy becomes `「おばあちゃん」さん` and accessibility text becomes `おばあちゃんさんへ`.

**Expected**

Kinship names and names already containing an honorific should not receive another suffix.

**Recommendation**

Do not mechanically append `さん` to free-form display names. Either phrase copy without a suffix or store a separate preferred form of address.

### QA-13 — P2 — Invalid-invite guidance tells the recipient to do something they cannot do

**Reproduction**

Enter an invalid six-digit pairing code.

**Observed**

The toast says `この招待は利用できません。新しい招待を作ってください。` The recipient/elder cannot create an invite.

**Expected**

The message should say to ask the caregiver/family organizer to issue and send a new invite, and should preserve the user's context.

**Recommendation**

Use role-appropriate wording such as `ご家族に新しい設定番号を送ってもらってください` and add a direct retry affordance.

### QA-14 — P2 — Users can like their own answer

**Reproduction**

Submit today's answer, then tap Like on that same answer.

**Observed**

The own-answer count becomes 1 and the state changes to liked; it can then be unliked.

**Expected**

For a family-support signal, self-liking is likely meaningless and can distort counts. If it is intentional, the product should explicitly define why.

**Recommendation**

Hide/disable Like for the current user's answers or enforce this server-side and return a clear state.

### QA-15 — P2 — Photo gallery hides later images with weak interaction affordance

**Observed**

An answer containing three photos showed two full photos and only a thin slice of the third. There is no page count, scroll indicator, chevron, or instruction. Repeated horizontal gestures in the Simulator did not visibly move the strip.

**Expected**

Users should be able to discover and reliably view every image.

**Recommendation**

Use a paged gallery with `1/3`, a visible partial next card plus chevron, or a tappable full-screen viewer. Confirm actual swipe handling on hardware.

### QA-16 — P2 — Free-form names have no visible limit or counter

**Reproduction**

Enter an approximately 80-character organizer name.

**Observed**

The value is accepted and Continue remains enabled. No maximum, counter, truncation warning, or server-compatible validation is communicated.

**Impact**

Long values can break cards, share copy, notification text, and backend validation later in the journey.

**Recommendation**

Define consistent server/client limits, enforce them inline, and show a character count near the limit. Apply the same policy to organizer, family, member, and display names.

### QA-17 — P2 — The decorative font reduces readability, especially after scaling

The custom display font is applied to nearly all body, form, metadata, and button text. At iPhone SE scale, thin/stylized glyphs become visibly hard to distinguish; for example, kana such as `の` can resemble boxed/katakana forms. This is especially risky in an elder-focused app.

**Recommendation**

Keep the brand font for large headings only. Use the system Japanese font for body copy, form fields, dates, validation, and buttons, with standard weights and Dynamic Type metrics.

### QA-18 — P3 — Answer call-to-action uses inconsistent/incorrect copy

The home call-to-action says `解答`, while the composer and the rest of the product use `回答`. For a personal response rather than a quiz solution, `回答` is the consistent term.

**Recommendation**

Change the home CTA to `回答する`.

### QA-19 — P3 — Settings actions lack completion/state feedback

**Observed**

- Saving a valid display name updates the data but shows no success message.
- Save remains enabled even when the value has not changed.
- `データを更新` gives no visible completion timestamp or confirmation in the fast demo path.

**Recommendation**

Disable Save when unchanged, show `保存しました`, and show a lightweight refreshed timestamp or success state for manual refresh.

### QA-20 — P3 — Comment presentation truncates identity and lacks context

**Observed**

- The four-character author `つつうら` is visually truncated to `つつ…` in the fixed author column, while `あおい` fits.
- Comments have no timestamp.
- There is no edit/delete control for one's own comment, even though delete support exists in the API/store layer.

**Recommendation**

Allow the author label to wrap or size flexibly, add relative/absolute timestamps, and expose delete (and optionally edit) for the comment owner with confirmation.

### QA-21 — P3 — Repeated photo controls lack unique assistive context

Every selected-photo remove control is announced as `写真を削除`, and rendered answer photos are all announced as `回答の写真`.

**Recommendation**

Use labels such as `写真2/4を削除` and `回答の写真2/3`; group a gallery with a count.

### QA-22 — P3 — Demo data shows a phone number that was never collected

A newly created organizer account displayed `090-1234-5678` in Settings even though no phone-number flow had occurred. This appears demo-specific, but it undermines reliable UX testing and can hide production data-contract problems.

**Recommendation**

Set the demo profile's phone to `nil` unless the OTP path was actually completed, and include separate fixtures for phone-authenticated and caregiver-created users.

## Missing or incomplete product capabilities

These are not necessarily defects if deliberately out of scope, but they are important lifecycle gaps for a production family app.

| Priority | Capability | Why it matters |
|---|---|---|
| High | Returning-user login and recovery | Required after logout, device replacement, keychain loss, or token expiry. |
| High | Safe managed-device recovery | A paired elder should not depend on an unannounced new one-time invite after accidental logout. |
| High | Family lifecycle controls | Owners cannot rename the family, rename/remove a managed member, transfer ownership, or leave a family. |
| High | Account/privacy controls | No account deletion, data export, privacy information, terms, support, or contact path is visible. |
| Medium | Answer ownership controls | No edit/delete for a submitted answer or its media. |
| Medium | Comment ownership controls | Delete exists in lower layers but is absent from the UI; no edit/reply/report. |
| Medium | Notification preferences | No reminder schedule, mute, per-family preference, permission status, or explanation. |
| Medium | Invite resilience | Add Copy Link, Copy Code, countdown, explicit expired state, and a clear reissue flow in addition to the share sheet. |
| Medium | History navigation | No date picker, search, filter, jump-to-today, or clear pagination affordance as history grows. |
| Low | Help/onboarding replay | Elder users need a simple way to replay setup help and understand voice/photo/social controls. |

## Features to remove or simplify if they cannot be completed before launch

- Remove iPad targeting until the layouts are truly responsive.
- Remove the hidden social-participation gate; it creates complexity without a visible rule.
- Stop using the decorative font for all text; reserve it for branding/headings.
- Hide the phone row when no phone was collected instead of displaying fixture/placeholder data.
- Do not surface Share Link as the primary remote setup action until its physical-device behavior and universal-link path are verified end to end.

## Physical-device and live-service follow-ups

These could not be classified as confirmed production bugs from the current safe Simulator pass:

1. **Share sheet:** `設定リンクを送る` did not present a share sheet after repeated accessibility and direct taps. `ShareLink` is present in the implementation, so retest on at least two physical iPhones. Treat as P1 if reproduced.
2. **Universal link/QR:** Verify the HTTPS invite opens the installed app, previews the correct family/member, handles an already signed-in user, and gives a useful web fallback when the app is not installed.
3. **Successful voice path:** With explicit consent, test Speech Recognition + microphone allow, live partial transcript, stop/re-record, audio upload, interruption, silence, and offline behavior.
4. **Push notifications:** Test authorization rationale, denied/allowed states, foreground presentation, background delivery, tap-to-open today's question, stale payloads, and token refresh on a signed physical build.
5. **Live OTP:** Once reachable, test valid/invalid/expired code, resend cooldown, international/Japanese number formatting, rate limiting, delayed SMS, and returning-account restoration.
6. **Network resilience:** Exercise offline launch, timeouts, 401 refresh/expiry, 4xx/5xx submissions, interrupted media upload, retry idempotency, and partial refresh failures.

## What worked well

- No crash occurred during the tested journeys.
- The caregiver-to-managed-member setup can be completed end to end with a six-digit code.
- Pairing code input filters non-digits and invalid codes produce a visible error.
- Text-answer drafts survive backing out and reopening within the session.
- Photo selection enforces the four-photo maximum, supports removal, and submitted photos render in the feed.
- Text submission produces a success state and updates feed/progress.
- Like/unlike and comment posting update counts/state once social controls are available.
- Empty family/history/comment states render without crashing.
- Owner and managed Settings variants correctly differ: managed users do not see family administration.
- Dark appearance, foreground/background return, and basic Reduce Motion behavior did not break navigation.

## Recommended delivery order

### Milestone 1 — Release blockers

1. Replace the fixed canvas with adaptive, scrollable, safe-area-aware layout.
2. Make all routes usable through the complete Dynamic Type range.
3. Add returning-user login/recovery and role-aware logout confirmation.
4. Fix and regression-test pairing confirmation Back.
5. Correct contrast tokens and assistive labels.

### Milestone 2 — Core journey quality

1. Repair keyboard/add-member layout.
2. Make social controls consistently available.
3. Model voice permission/error states correctly.
4. Improve progress semantics, photo gallery discoverability, copy, validation, and feedback.
5. Verify sharing, universal links, push, OTP, and voice on physical devices/live services.

### Milestone 3 — Production lifecycle completeness

1. Add family/member/account management and recovery.
2. Add answer/comment ownership controls.
3. Add notification preferences, privacy/support, and scalable history navigation.

