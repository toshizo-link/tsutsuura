# Privacy disclosure preparation

**Factual inventory, 2026-09-05. The nine-category App Store privacy label is published; the full policy page is finalized locally with operator AlexanderTakami Marsh and is awaiting hosting sign-in for deployment.** Do not invent facts about operations outside this repository.

## Implemented collection

`tsutsuura/tsutsuura/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking=false`; every listed collected type is linked to the user, not used for tracking, and used for App Functionality:

| Apple data category | Repository evidence / purpose |
| --- | --- |
| Email address | Optional verified email enrollment and login/recovery (`EmailOtpService`, `EmailAuthenticationScreens`). Email is returned in the user's own profile, not the family summary. |
| Name | Display names and family-member identification (`UserProfile`, `UserService`). |

| User ID | Accounts, family membership, answers/comments, authentication and authorization. |
| Device ID | Push device tokens and device/session association. |
| Photos or videos | User-selected answer photos; video upload is not a current feature. Apple's category combines these media types. |
| Audio data | Optional uploaded voice recordings associated with answers. |
| Emails or text messages | Private family communication in answers/comments; this declaration does not mean the app reads the user's mailbox or SMS inbox. |
| Other user content | Personal 16×16 drawings and other submitted family content. |
| Other data types | Family relationships, preferences/timezone, authentication/recovery and security records. Confirm the final categorization against actual server logging. |

Build 14 removes the phone declaration: current SMS endpoints reject before parsing/storing numbers with SMS disabled, the migrated service is fresh, and the visible client uses email. Dormant schema support does not represent current collection. Nine corresponding App Store Connect categories were saved and published, with App Functionality, linked identity, and no tracking. Apple requires privacy answers separately in App Store Connect, including linked-data status and partner practices. IP addresses should be categorized according to their actual use; do not claim location collection merely because an IP exists. [Apple App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/).

The only declared required-reason API is UserDefaults with reason `CA92.1`. Local settings include onboarding/banner state and verification bookkeeping. No advertising/tracking SDK, StoreKit purchasing flow, or analytics SDK was found in the shipping Swift source. This source inspection does not establish the hosting provider's logging or any off-repository analytics practices.

## Sharing and processing to describe accurately

- Answers, selected photos/audio, comments, and marks are shared with the current family, subject to server membership checks. Published answers and comments cannot be individually changed/deleted through the current visible app controls; account deletion remains available.
- Own-account email and login secrets are not presented in family member summaries. Do not describe data as anonymous or unlinked: it is associated with account and family IDs.
- The PHP backend and private SQLite/media storage are hosted on ConoHa. The configured sender is `general@toshizo.link` using native PHP mail and host mail transport. “No third-party authentication SDK” is accurate; “no outside service receives data” is not supported.
- The app uses Apple's Speech framework for Japanese transcription and does not set `requiresOnDeviceRecognition=true`. Do not promise that speech processing always stays on the device. Explain the actual permission and processing behavior before finalizing the policy.
- Push registration uses Apple's APNs infrastructure. Current local operational records say the production push provider/workers are disabled. If activated, disclose device-token use and avoid sensitive answer/comment content in notification claims.
- Confirm controller/operator identity, contact address, hosting/mail processing locations, subprocessors, and the protections applied to outside processing. None should be invented from the bundle ID or developer-team name.

## Retention and deletion facts

- `LifecycleService::deleteAccount` deletes the user and associated content through database relations and schedules physical media removal. A sole owner's family is deleted; an owner with other members is required to transfer ownership first. Test that process with an owner whose members are not yet eligible for ownership.
- Family-owner removal of a managed member can delete that managed account and content. The policy and onboarding should explain caregiver management rather than implying only the elder can affect their data.
- `server/bin/cleanup.php` has distinct expiry rules: revoked/expired sessions are retained for thirty days after that event; completed notification records for ninety days; resolved comment reports for 365 days; account audit records for 730 days. Pending reports do not have that resolved-report expiry.
- Mutation/recovery receipts have their own replay retention; account-deletion retry tombstones intentionally do not expire. Confirm the precise retained identifiers and document necessary technical records without promising instantaneous erasure of every backup/log/hash.
- Backup schedules, backup expiry, hosting access-log retention, support-email retention, and real-world deletion-response time are not established by the repository. They are required operator decisions before policy publication.
- Explain how to export data, delete an account, withdraw microphone/speech/photo/notification permission, and contact support. Do not label permission revocation as deletion of previously uploaded content.

## Public-page completion requirements

Build 14 adds a public-policy link to the in-app summary and corrects the help address to general@toshizo.link; the target page still requires deployment. The draft HTML under `public-pages/` is a starting point only. Complete the marked factual gaps, publish real HTTPS pages, verify anonymous access, then put the policy URL in App Store Connect and within the app. The support URL must be a contact website; the existing `mailto:` link is not the App Store's required support website. [Apple privacy-policy rule](https://developer.apple.com/app-store/review/guidelines/#privacy), [support metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

Do not publish until the policy, in-app text, manifest, and App Store privacy answers agree. This file records engineering evidence and unresolved facts; it does not certify legal compliance.
