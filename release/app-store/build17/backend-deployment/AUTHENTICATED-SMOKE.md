# Proposed disposable-account safety smoke — not run

This is suitable after unauthenticated release verification passes. Keep all
tokens, pairing credentials and cleanup keys in a private local file; only log
statuses and fixture IDs. Use a new random suffix, for example
`安全確認-<UTC timestamp>-<random>`, so cleanup can verify exact identity. Do not
use existing users, enumerate family IDs, enroll email, register push tokens,
send notifications, or change server publication times.

Every URL is under `https://toshizo.link/tsutsuura-api/api`. Use JSON requests,
unique stable `Idempotency-Key` values for setup/activation/deletion, and POST
method overrides for mutations that ConoHa may otherwise reject.

1. `POST /v1/setup/family` with `organizerName` and `familyName` using the unique
   prefix. Save `data.token` and `data.user.id` as fixture A. With that bearer,
   `GET /v1/me` and `GET /v1/family`; confirm the exact name and one member.
2. A: `GET /v1/me/blocks` must return empty `users`, `hiddenUserIds`,
   `hiddenAnswerIds`, `hiddenCommentIds`.
3. A: `POST /v1/family/managed-members` with `displayName` using the same unique
   prefix plus B. Save `data.member.id`. A: create a pairing with
   `POST /v1/family/managed-members/{B}/pairings`; save `data.pairing.code`.
   `POST /v1/setup/pairings/activate` with that `code` and a stable activation
   idempotency key; save B's `data.token`, and confirm its user ID is exactly B.
   Both accounts must report the same fixture family and exactly members A/B.
4. A: `POST /v1/me/blocks/{B}` with `X-HTTP-Method-Override: PUT`, no body. Repeat
   once. A's block list must contain B once; B's list must have empty `users`
   and `hiddenUserIds` containing A. Both family member counts remain two.
5. B: POST override DELETE `/v1/me/blocks/{A}`; it must not undo A's block.
   A: POST override DELETE `/v1/me/blocks/{B}` twice; both return200 and both
   snapshots become empty. This checks real persistence/access control without
   creating a public-facing answer or triggering family-content notifications.

Optional report path checks, if a complete mutation check is desired:

6. B: `GET /v1/questions/today`. Continue only if `question.isAvailable` is true
   and `question.hasAnswered` false. B submits a uniquely identifiable harmless
   fixture answer via `POST /v1/questions/today/answer`, body fields `body`,
   `questionId`, `questionDate` from that response. No photo/audio is necessary
   for this light check. Save returned answer ID. These two accounts have no
   push tokens, so no device can receive their private fixture events.
7. A: fetch B's answer; POST `/v1/answers/{answerId}/reports` with
   `{"reason":"other","details":"Disposable release verification fixture"}`.
   Confirm201 and a stable repeated report ID; A's direct GET must now return404
   and its snapshot includes the answer ID. B still sees its own answer. No
   moderator action is needed: deleting B below cascades the fixture report.
8. If a comment mutation test is needed, create B's comment on B's answer,
   have A report the comment **before** A reports the answer, and check A's
   visible comments omit it. Do not report existing content or fabricate an
   operator review decision to test this.

Cleanup must run even after a failed check:

9. Using B's saved token, verify `GET /v1/me` returns exact fixture B and that
   `GET /v1/family` still identifies the recorded fixture family with no
   unexpected member. Delete B via `POST /v1/me` with
   `X-HTTP-Method-Override: DELETE` and its own stable cleanup idempotency key.
10. Using A's saved token, verify exact fixture A and the same family with only
    A remaining. Delete A with a different stable cleanup key. If those identity
    or membership checks fail, stop cleanup rather than guessing whom to delete.
11. Both tokens must then return401 from `GET /v1/me`; save only the fixture IDs,
    response statuses and cleanup result. Delete the private token file when
    cleanup is confirmed. If a network response is lost, retry the same scoped
    deletion with the same token/key rather than creating more fixtures.

If setup fails before B activation, A can delete only the exact managed B it
created via POST override DELETE `/v1/family/members/{B}`, after checking its
fixture family membership. Then verify A is the sole member before deleting A.

The recommended initial production smoke is steps1–5 plus9–11. Optional answer
reporting can wait until the existing question publishes naturally; the local
HTTP suite already covers reports and attached photo/audio access. Do not weaken
publication, authentication or moderation policies to make a smoke test run.
