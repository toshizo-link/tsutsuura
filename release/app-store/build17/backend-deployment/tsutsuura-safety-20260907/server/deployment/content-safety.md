# Content safety release

This isolated change starts from the deployed backend source copied from the
main workspace, including native PHP email, scheduled questions, profile marks,
and push retry fixes. `safety-baseline-manifest.json` records the imported source
hashes. The older server frozen with build 16 is not the deployment baseline.

## Upgrade and verification

Back up the private database and media together. Pause mutations and the old
event/reminder workers, apply migrations through `011_content_safety.sql`, deploy
the matching complete server release, then resume traffic and workers. Do not
overwrite `.env`, keys, or storage with source files. SQLite and MySQL migration
files are additive and retry-safe; no previous account or answer is deleted.

`GET /v1/health` must return revision `2026-09-07-safety`, schema version
`011_content_safety.sql`, and true `userBlocking`, `answerReporting`,
`commentReporting`, `reportedContentHiding`, and `operatorModeration` capabilities.
An absent migration/table makes health fail. Before an app release run:

```sh
php bin/verify-release.php https://YOUR_API_BASE
```

The verifier is read-only: it checks health, authenticated-route presence, and
the POST method-override transport used on ConoHa. It does not verify an actual
signed-in mutation or APNs delivery; use the app's family test accounts for those.

## Authenticated contracts

Every endpoint requires the current bearer session. IDs must be positive,
canonical decimal strings within the server integer range. Block/report targets
must be in the same current family; another family's content returns 404.

| Request | Result in `data` |
| --- | --- |
| `GET /v1/me/blocks` | `users`, `hiddenUserIds`, `hiddenAnswerIds`, `hiddenCommentIds` |
| `PUT /v1/me/blocks/{userId}` | Empty object; idempotently block |
| `DELETE /v1/me/blocks/{userId}` | Empty object; idempotently remove only your block |
| `POST /v1/answers/{answerId}/reports` | `report` with `id`, `answerId`, `reason`, `status`, `createdAt` |
| `POST /v1/comments/{commentId}/reports` | Same report shape with `commentId` |

PUT and DELETE also accept POST with `X-HTTP-Method-Override` set to the intended
method. Reports accept `reason`: `spam`, `harassment`, `privacy`, `inappropriate`,
or `other`, and optional UTF-8 `details` of at most 500 characters. Self-blocks
and self-reports return 422. A report is unique for reporter/content: retrying
returns the original report, without reopening an operator decision.

`users` lists only people explicitly blocked by the caller, with public profile
fields. `hiddenUserIds` includes both directions without identifying who blocked
whom. The answer/comment ID lists synchronize locally cached content with server
visibility, including operator removals. Clients must apply them to older pages,
open media, and stale responses. They are scoped to current-family content.

Blocking preserves membership and administrator authority. Both people lose
access to each other's answers, comments, private attachments and interactions.
Replies to hidden comments are rejected. An old private media URL cannot bypass
the checks. Unblocking restores otherwise-visible content; it does not undo an
individual report or the other person's independent block. Family-management
member names/marks remain available so the family can still be managed.

Reports hide the reported item for that reporter, including every attachment
and comment beneath a reported answer. Operator dismissal does not undo this
choice. Operator removal hides the item for everybody. Reporting a comment
does not hide separate replies by other visible members; a hidden parent's
body/author is never included in those reply payloads.

The enqueue, worker, direct delivery, and private-content paths enforce the
same policy. Mutations cancel active notification deliveries so subsequent
unblocking cannot revive them. APNs requests already in flight/accepted cannot
be recalled; a delivered device notification may remain in Notification Center.
Question reminders contain no other user's content and remain independent.

## Manual moderation

Only a trusted operator with shell access and the existing server configuration
can use this CLI. There is no public moderation endpoint or new administrator
privilege granted to family members. Run it from the deployed `server/` directory:

```sh
php bin/moderate-content.php --list --limit=50
php bin/moderate-content.php --show --type=answer --id=REPORT_ID
php bin/moderate-content.php --review --type=answer --id=REPORT_ID --decision=remove --operator=OPERATOR_NAME --note='Reason for decision'
php bin/moderate-content.php --review --type=comment --id=REPORT_ID --decision=dismiss --operator=OPERATOR_NAME --note='Reason for decision'
```

List shows oldest pending reports. Show includes the reported text and, for an
answer, attachment metadata/private storage keys. Review original media using
authorized access to `MEDIA_STORAGE_PATH`; do not expose or copy it to public
URLs. Output contains private reports and must be handled accordingly.

Review requires a named operator and nonempty decision note. Repeating the same
decision is safe; changing the decision on a completed report is rejected.
Remove makes content inaccessible through app routes without deleting the
underlying daily-answer record or allowing another answer that day. The current
CLI cannot reverse a removal. Dismiss leaves content available to other users.

Report rows are retained with the content/account because they also represent
the reporter's persistent hiding choice. Cleanup no longer expires reviewed
comment reports after 365 days. Account deletion removes owned block edges and
its reports; deleting content cascades reports/actions. A global removal record
remains if only the reporter deletes their account, so the content cannot
reappear for everybody. No deleted reporter identity is stored in that record.

## Remaining review and operational gaps

These controls alone are **not** evidence that every App Store UGC requirement
is satisfied:

- Text validation covers format, UTF-8 and length; media validation covers
  accepted types, size and decoding. There is no semantic pre-publication
  objectionable-content screening for text, photos, audio or profile marks.
- There is no dedicated report or operator removal for profile names/marks.
  Blocking hides authored content but intentionally leaves the membership list.
- Reports enter a persistent queue. No email/push alert for a new report, human
  staffing schedule, response deadline, or actual monitoring commitment is
  configured by this change. A real operator must accept and carry out those
  responsibilities before they can be represented to App Review.
- A local remove/dismiss action does not suspend an abusive account. Existing
  family removal/account lifecycle controls remain separate.
- Local regressions use SQLite and deterministic push delivery. They do not
  establish production deployment, real APNs delivery, or runtime validation
  against a provisioned MySQL/MariaDB instance.

Do not claim an exemption or a moderation response SLA based only on this code.
