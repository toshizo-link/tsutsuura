<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use DateTimeImmutable;
use PDO;
use RuntimeException;
use Throwable;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Http\UploadedFile;
use Tsutsuura\Server\Push\EventNotificationService;
use Tsutsuura\Server\Security\Crypto;

final class AppService
{
    private readonly AnswerMediaService $answerMedia;

    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly Config $config,
        ?AnswerMediaService $answerMedia = null,
        private readonly ?EventNotificationService $eventNotifications = null,
        private readonly ?\Closure $clock = null,
    ) {
        $this->answerMedia = $answerMedia ?? new AnswerMediaService($database, $crypto, $config);
    }

    /** @return array<string, mixed> */
    public function family(int $userId): array
    {
        $family = $this->familyRow($userId);
        $statement = $this->database->connection()->prepare(
            'SELECT u.id, u.phone_e164, u.email_address, u.email_verified_at, u.display_name, u.avatar_url, u.avatar_mark, u.created_at,
                    fm.role, fm.joined_at,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM family_members fm
             JOIN users u ON u.id = fm.user_id
             LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE fm.family_id = :family
             ORDER BY fm.joined_at ASC, u.id ASC'
        );
        $statement->execute(['family' => $family['id']]);
        $members = [];
        foreach ($statement->fetchAll() as $row) {
            $member = Presenter::user($row);
            $member['role'] = (string) $row['role'];
            $member['joinedAt'] = Presenter::utcTimestamp((string) $row['joined_at']);
            $members[] = $member;
        }
        return [
            'id' => (string) $family['id'],
            'name' => (string) $family['name'],
            'inviteCode' => (string) $family['invite_code'],
            'memberCount' => count($members),
            'members' => $members,
        ];
    }

    /** @return array<string, mixed> */
    public function home(int $userId, mixed $cursorValue = null): array
    {
        $family = $this->family($userId);
        $question = $this->todayQuestionRow($userId);
        $today = (string) $question['date'];
        $page = $this->history($userId, $cursorValue, 20);
        // Family progress must include every current member who answered,
        // even when their answer is beyond the current feed page.
        $answeredUsersStatement = $this->database->connection()->prepare(
            'SELECT DISTINCT a.user_id
             FROM answers a
             JOIN family_members fm ON fm.family_id = a.family_id AND fm.user_id = a.user_id
             WHERE a.family_id = :family AND a.answer_date = :date AND a.question_id = :question
             ORDER BY a.user_id ASC'
        );
        $answeredUsersStatement->execute([
            'family' => $family['id'],
            'date' => $today,
            'question' => $question['id'],
        ]);
        $todayAnsweredUserIds = array_map('strval', $answeredUsersStatement->fetchAll(PDO::FETCH_COLUMN));
        $myAnswerStatement = $this->database->connection()->prepare(
            'SELECT id FROM answers WHERE user_id = :user AND answer_date = :date LIMIT 1'
        );
        $myAnswerStatement->execute(['user' => $userId, 'date' => $today]);
        $myAnswerId = $myAnswerStatement->fetchColumn();
        return [
            'family' => $family,
            'todayQuestion' => $this->question($question, $today),
            'todayAnsweredUserIDs' => $todayAnsweredUserIds,
            'myAnswer' => $myAnswerId === false ? null : $this->answer((int) $myAnswerId, $userId),
            'feed' => $page['items'],
            'nextCursor' => $page['nextCursor'],
        ];
    }

    /** @return array<string, mixed> */
    public function todayQuestion(int $userId): array
    {
        $question = $this->todayQuestionRow($userId);
        $today = (string) $question['date'];
        $statement = $this->database->connection()->prepare(
            'SELECT id FROM answers WHERE user_id = :user AND answer_date = :date LIMIT 1'
        );
        $statement->execute(['user' => $userId, 'date' => $today]);
        $answerId = $statement->fetchColumn();
        return [
            'question' => $this->question($question, $today),
            'answer' => $answerId === false ? null : $this->answer((int) $answerId, $userId),
        ];
    }

    /** @return array<string, mixed> */
    public function answerById(int $userId, string $answerIdValue): array
    {
        return $this->answer(self::id($answerIdValue, 'answer'), $userId);
    }

    /** @return array<string, mixed> */
    public function submitTodayAnswer(
        int $userId,
        mixed $bodyValue,
        ?UploadedFile $audio = null,
        array $photos = [],
        mixed $audioDurationMilliseconds = null,
        bool $replaceMedia = false,
        mixed $expectedQuestionId = null,
        mixed $expectedQuestionDate = null,
    ): array {
        $hasMediaUpload = $audio !== null || $photos !== [];
        $body = self::body(
            $bodyValue ?? ($replaceMedia ? '' : null),
            2000,
            'answer',
            $replaceMedia && $hasMediaUpload,
        );
        $question = $this->todayQuestionRow($userId);
        $today = $question['date'];
        if ($expectedQuestionId !== null) {
            if (!is_string($expectedQuestionId) || preg_match('/\A[1-9][0-9]{0,18}\z/D', $expectedQuestionId) !== 1) {
                throw new ApiException(422, 'invalid_question_id', 'questionId must be a question ID string.');
            }
            if ($expectedQuestionId !== (string) $question['id']) {
                throw new ApiException(409, 'question_changed', '今日の質問が変わりました。ホームに戻って新しい質問をご確認ください。');
            }
        }
        if ($expectedQuestionDate !== null) {
            $parsedDate = is_string($expectedQuestionDate)
                && preg_match('/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/D', $expectedQuestionDate) === 1
                ? DateTimeImmutable::createFromFormat('!Y-m-d', $expectedQuestionDate)
                : false;
            if ($parsedDate === false || $parsedDate->format('Y-m-d') !== $expectedQuestionDate) {
                throw new ApiException(422, 'invalid_question_date', 'questionDate must be a valid YYYY-MM-DD date.');
            }
            if ($expectedQuestionDate !== $today) {
                throw new ApiException(409, 'question_changed', '今日の質問が変わりました。ホームに戻って新しい質問をご確認ください。');
            }
        }
        if (!$question['is_available']) {
            throw new ApiException(409, 'question_not_published', '今日の質問は、表示された時刻になると届きます。');
        }
        if (!$replaceMedia && ($hasMediaUpload || $audioDurationMilliseconds !== null)) {
            throw new ApiException(400, 'invalid_upload', 'Media uploads require multipart form submission.');
        }
        $prepared = $replaceMedia
            ? $this->answerMedia->prepareUploads($audio, $photos, $audioDurationMilliseconds)
            : [];
        try {
            $result = $this->database->transaction(function (PDO $pdo) use (
                $question,
                $userId,
                $today,
                $body,
                $replaceMedia,
                $prepared,
            ): array {
                // Serialize content creation with family leave/removal. A
                // membership resolved before the transaction could otherwise
                // be deleted and purged before this insert commits.
                $family = $this->lockedFamilyRow($pdo, $userId);
                if ((int) $family['id'] !== (int) $question['family_id']) {
                    throw new ApiException(409, 'family_changed', '家族の情報が変わりました。ホームに戻ってもう一度お試しください。');
                }

                $existing = $pdo->prepare(
                    'SELECT id, body FROM answers WHERE user_id = :user AND answer_date = :date'
                );
                $existing->execute(['user' => $userId, 'date' => $today]);
                $existingAnswer = $existing->fetch();
                if (is_array($existingAnswer)) {
                    $answerId = (int) $existingAnswer['id'];
                    // Lost-response retries return the original immutable answer.
                    // Compare the uploaded bytes as well as their presentation
                    // metadata; a same-size replacement must never be accepted.
                    if ((string) $existingAnswer['body'] !== $body ||
                        ($replaceMedia && !$this->answerMedia->matchesPreparedForAnswer($pdo, $answerId, $prepared))) {
                        throw self::immutableAnswerError();
                    }
                    return [
                        'answer' => $this->answer($answerId, $userId),
                        'oldStorageKeys' => [],
                        'replayed' => true,
                    ];
                }
                $statement = $pdo->prepare(
                    'INSERT INTO answers (family_id, question_id, user_id, answer_date, body)
                     VALUES (:family, :question, :user, :date, :body)'
                );
                $statement->execute([
                    'family' => $family['id'],
                    'question' => $question['id'],
                    'user' => $userId,
                    'date' => $today,
                    'body' => $body,
                ]);
                $answerId = (int) $pdo->lastInsertId();
                if ($this->database->isSqlite() || $answerId === 0) {
                    $lookup = $pdo->prepare(
                        'SELECT id FROM answers WHERE user_id = :user AND answer_date = :date'
                    );
                    $lookup->execute(['user' => $userId, 'date' => $today]);
                    $answerId = (int) $lookup->fetchColumn();
                }
                $oldStorageKeys = $replaceMedia
                    ? $this->answerMedia->replaceForAnswer($pdo, $answerId, $prepared)
                    : [];
                $this->eventNotifications?->enqueueAnswerSubmitted($pdo, $userId, $answerId);
                return [
                    'answer' => $this->answer($answerId, $userId),
                    'oldStorageKeys' => $oldStorageKeys,
                    'replayed' => false,
                ];
            });
        } catch (Throwable $exception) {
            $this->answerMedia->discardPrepared($prepared);
            throw $exception;
        }
        if ($result['replayed']) {
            $this->answerMedia->discardPrepared($prepared);
        }
        $this->answerMedia->deleteStorageKeys($result['oldStorageKeys']);
        return $result['answer'];
    }

    /** @return array<string, mixed> */
    public function updateAnswer(int $userId, string $answerIdValue, mixed $bodyValue): array
    {
        $this->assertOwnedImmutableAnswer($userId, $answerIdValue);
    }

    public function deleteAnswer(int $userId, string $answerIdValue): void
    {
        $this->assertOwnedImmutableAnswer($userId, $answerIdValue);
    }

    /** @return array<string, mixed> */
    public function deleteAnswerMedia(
        int $userId,
        string $answerIdValue,
        string $mediaIdValue,
    ): array {
        self::id($mediaIdValue, 'media');
        $this->assertOwnedImmutableAnswer($userId, $answerIdValue);
    }

    private function assertOwnedImmutableAnswer(int $userId, string $answerIdValue): never
    {
        $answerId = self::id($answerIdValue, 'answer');
        $this->ownedAnswer($this->database->connection(), $answerId, $userId, false);
        throw self::immutableAnswerError();
    }

    private static function immutableAnswerError(): ApiException
    {
        return new ApiException(409, 'answer_immutable', '送った回答は変更・削除できません。');
    }

    /** @return array{items: list<array<string, mixed>>, nextCursor: ?string} */
    public function history(
        int $userId,
        mixed $cursorValue,
        mixed $limitValue,
        array $filterValues = [],
    ): array
    {
        $cursor = null;
        if ($cursorValue !== null && $cursorValue !== '') {
            if (!is_string($cursorValue) || preg_match('/^[1-9][0-9]{0,18}$/', $cursorValue) !== 1) {
                throw new ApiException(422, 'invalid_cursor', 'cursor is invalid.');
            }
            $cursor = (int) $cursorValue;
        }
        $limit = 20;
        if ($limitValue !== null && $limitValue !== '') {
            $limit = filter_var($limitValue, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 50]]);
            if ($limit === false) {
                throw new ApiException(422, 'invalid_limit', 'limit must be between 1 and 50.');
            }
        }
        $family = $this->familyRow($userId);
        $filters = $this->historyFilters($filterValues);
        if ($filters['authorId'] !== null) {
            $member = $this->database->connection()->prepare(
                'SELECT 1 FROM family_members WHERE family_id = :family AND user_id = :user'
            );
            $member->execute([
                'family' => $family['id'],
                'user' => $filters['authorId'],
            ]);
            if ($member->fetchColumn() === false) {
                throw new ApiException(422, 'invalid_author_filter', 'authorId is not a family member.');
            }
        }
        $items = $this->answerRows(
            (int) $family['id'],
            $userId,
            $cursor,
            null,
            $limit + 1,
            $filters,
        );
        $hasMore = count($items) > $limit;
        if ($hasMore) {
            array_pop($items);
        }
        $next = $hasMore && $items !== [] ? (string) end($items)['id'] : null;
        return ['items' => array_values($items), 'nextCursor' => $next];
    }

    /** @return array{likesCount: int, isLiked: bool} */
    public function setLike(int $userId, string $answerIdValue, bool $liked): array
    {
        $answerId = self::id($answerIdValue, 'answer');
        $result = $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $answerId,
            $liked,
        ): array {
            $family = $this->lockedFamilyRow($pdo, $userId);
            $owner = $pdo->prepare(
                'SELECT user_id FROM answers WHERE id = :answer AND family_id = :family'
            );
            $owner->execute(['answer' => $answerId, 'family' => $family['id']]);
            $answerOwnerId = $owner->fetchColumn();
            if ($answerOwnerId === false) {
                throw new ApiException(404, 'answer_not_found', 'Answer not found.');
            }
            if ($liked && (int) $answerOwnerId === $userId) {
                throw new ApiException(
                    422,
                    'self_like_not_allowed',
                    'Users cannot like their own answers.',
                );
            }
            $statement = $liked
                ? $pdo->prepare($this->database->isSqlite()
                    ? 'INSERT OR IGNORE INTO answer_likes (answer_id, user_id) VALUES (:answer, :user)'
                    : 'INSERT IGNORE INTO answer_likes (answer_id, user_id) VALUES (:answer, :user)')
                : $pdo->prepare(
                    'DELETE FROM answer_likes WHERE answer_id = :answer AND user_id = :user'
            );
            $statement->execute(['answer' => $answerId, 'user' => $userId]);
            $created = $liked && $statement->rowCount() === 1;
            if ($created) {
                $this->eventNotifications?->enqueueAnswerLiked($pdo, $userId, $answerId);
            }
            $count = $pdo->prepare(
                'SELECT COUNT(*) FROM answer_likes WHERE answer_id = :answer'
            );
            $count->execute(['answer' => $answerId]);
            return [
                'likesCount' => (int) $count->fetchColumn(),
                'isLiked' => $liked,
            ];
        });
        return $result;
    }

    /** @return array{items: list<array<string, mixed>>, nextCursor: ?string} */
    public function comments(int $userId, string $answerIdValue, mixed $cursorValue, mixed $limitValue): array
    {
        $answerId = self::id($answerIdValue, 'answer');
        $this->assertAnswerVisible($answerId, $userId);
        $cursor = 0;
        if ($cursorValue !== null && $cursorValue !== '') {
            if (!is_string($cursorValue) || preg_match('/^[1-9][0-9]{0,18}$/', $cursorValue) !== 1) {
                throw new ApiException(422, 'invalid_cursor', 'cursor is invalid.');
            }
            $cursor = (int) $cursorValue;
        }
        $limit = 30;
        if ($limitValue !== null && $limitValue !== '') {
            $limit = filter_var($limitValue, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 50]]);
            if ($limit === false) {
                throw new ApiException(422, 'invalid_limit', 'limit must be between 1 and 50.');
            }
        }
        $statement = $this->database->connection()->prepare(
            'SELECT c.id, c.answer_id, c.user_id, c.parent_comment_id,
                    c.body, c.created_at, c.updated_at,
                    u.phone_e164, u.display_name, u.avatar_url, u.avatar_mark, u.created_at AS user_created_at
             FROM comments c
             JOIN users u ON u.id = c.user_id
             WHERE c.answer_id = :answer AND c.id > :cursor
             ORDER BY c.id ASC
             LIMIT :limit'
        );
        $statement->bindValue(':answer', $answerId, PDO::PARAM_INT);
        $statement->bindValue(':cursor', $cursor, PDO::PARAM_INT);
        $statement->bindValue(':limit', $limit + 1, PDO::PARAM_INT);
        $statement->execute();
        $rows = $statement->fetchAll();
        $hasMore = count($rows) > $limit;
        if ($hasMore) {
            array_pop($rows);
        }
        $items = array_map(fn (array $row): array => $this->presentComment($row), $rows);
        return [
            'items' => $items,
            'nextCursor' => $hasMore && $items !== [] ? (string) end($items)['id'] : null,
        ];
    }

    /** @return array<string, mixed> */
    public function addComment(
        int $userId,
        string $answerIdValue,
        mixed $bodyValue,
        mixed $parentCommentIdValue = null,
        mixed $idempotencyKeyValue = null,
    ): array
    {
        $answerId = self::id($answerIdValue, 'answer');
        $body = self::body($bodyValue, 1000, 'comment');
        $parentCommentId = null;
        if ($parentCommentIdValue !== null && $parentCommentIdValue !== '') {
            if (!is_string($parentCommentIdValue)) {
                throw new ApiException(422, 'invalid_id', 'parent comment id is invalid.');
            }
            $parentCommentId = self::id($parentCommentIdValue, 'parent comment');
        }
        $idempotencyKey = $this->optionalIdempotencyKey($idempotencyKeyValue);
        $requestKeyHash = $idempotencyKey === null
            ? null
            : $this->crypto->hashOpaque('comment-create:' . $idempotencyKey);
        $requestFingerprint = $requestKeyHash === null
            ? null
            : $this->crypto->hashOpaque(
                'comment-request:' . json_encode(
                    [$answerId, $parentCommentId, $body],
                    JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE,
                )
            );
        $comment = $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $answerId,
            $parentCommentId,
            $body,
            $requestKeyHash,
            $requestFingerprint,
        ): array {
            if ($requestKeyHash !== null && $requestFingerprint !== null) {
                $replay = $this->reserveCommentMutationReceipt(
                    $pdo,
                    $requestKeyHash,
                    $userId,
                    $requestFingerprint,
                );
                if ($replay !== null) {
                    return $replay;
                }
            }

            $family = $this->lockedFamilyRow($pdo, $userId);
            $visible = $pdo->prepare(
                'SELECT 1 FROM answers WHERE id = :answer AND family_id = :family'
            );
            $visible->execute(['answer' => $answerId, 'family' => $family['id']]);
            if ($visible->fetchColumn() === false) {
                throw new ApiException(404, 'answer_not_found', 'Answer not found.');
            }

            if ($parentCommentId !== null) {
                $parent = $pdo->prepare(
                    'SELECT 1 FROM comments WHERE id = :comment AND answer_id = :answer'
                );
                $parent->execute(['comment' => $parentCommentId, 'answer' => $answerId]);
                if ($parent->fetchColumn() === false) {
                    throw new ApiException(404, 'parent_comment_not_found', 'Parent comment not found.');
                }
            }
            $statement = $pdo->prepare(
                'INSERT INTO comments
                    (answer_id, user_id, parent_comment_id, body)
                 VALUES (:answer, :user, :parent, :body)'
            );
            $statement->execute([
                'answer' => $answerId,
                'user' => $userId,
                'parent' => $parentCommentId,
                'body' => $body,
            ]);
            $commentId = (int) $pdo->lastInsertId();
            $this->eventNotifications?->enqueueCommentAdded($pdo, $userId, $commentId);
            $created = $this->commentById($commentId);
            if ($requestKeyHash !== null && $requestFingerprint !== null) {
                $this->completeCommentMutationReceipt(
                    $pdo,
                    $requestKeyHash,
                    $userId,
                    $requestFingerprint,
                    $created,
                );
            }
            return $created;
        });
        return $comment;
    }

    private function optionalIdempotencyKey(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value) ||
            preg_match('/^[A-Za-z0-9._-]{16,128}$/', trim($value)) !== 1) {
            throw new ApiException(
                422,
                'invalid_idempotency_key',
                'Idempotency-Key must be 16 to 128 safe ASCII characters.',
            );
        }
        return trim($value);
    }

    /**
     * Reserve a 30-day, user/content-bound comment mutation receipt. The
     * response is encrypted because it contains the original comment body.
     * Reservation and completion happen in the same transaction, so a
     * concurrent duplicate can only observe the completed response.
     *
     * @return array<string, mixed>|null Exact replay, or null for the newly
     * reserved request.
     */
    private function reserveCommentMutationReceipt(
        PDO $pdo,
        string $keyHash,
        int $userId,
        string $requestFingerprint,
    ): ?array {
        $now = new DateTimeImmutable('now');
        $deleteExpired = $pdo->prepare(
            'DELETE FROM comment_mutation_receipts
             WHERE key_hash = :key AND expires_at < :now'
        );
        $deleteExpired->execute([
            'key' => $keyHash,
            'now' => $now->format('Y-m-d H:i:s'),
        ]);

        $reserve = $pdo->prepare($this->database->isSqlite()
            ? 'INSERT OR IGNORE INTO comment_mutation_receipts
                 (key_hash, user_id, request_fingerprint,
                  response_encrypted, expires_at)
               VALUES (:key, :user, :fingerprint, NULL, :expires)'
            : 'INSERT IGNORE INTO comment_mutation_receipts
                 (key_hash, user_id, request_fingerprint,
                  response_encrypted, expires_at)
               VALUES (:key, :user, :fingerprint, NULL, :expires)'
        );
        $reserve->execute([
            'key' => $keyHash,
            'user' => $userId,
            'fingerprint' => $requestFingerprint,
            'expires' => $now->modify('+30 days')->format('Y-m-d H:i:s'),
        ]);
        $newlyReserved = $reserve->rowCount() === 1;

        $sql =
            'SELECT user_id, request_fingerprint, response_encrypted
             FROM comment_mutation_receipts
             WHERE key_hash = :key LIMIT 1';
        if (!$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $lookup = $pdo->prepare($sql);
        $lookup->execute(['key' => $keyHash]);
        $row = $lookup->fetch();
        if (!is_array($row)) {
            throw new RuntimeException('Comment mutation receipt reservation is invalid.');
        }
        if ((int) $row['user_id'] !== $userId ||
            !hash_equals((string) $row['request_fingerprint'], $requestFingerprint)) {
            throw new ApiException(
                409,
                'idempotency_key_reused',
                'The idempotency key was already used for different comment content.',
            );
        }
        if (is_string($row['response_encrypted'])) {
            return $this->decryptCommentMutationResponse($row['response_encrypted']);
        }
        if (!$newlyReserved) {
            throw new RuntimeException('Stored comment mutation receipt is incomplete.');
        }
        return null;
    }

    /** @param array<string, mixed> $result */
    private function completeCommentMutationReceipt(
        PDO $pdo,
        string $keyHash,
        int $userId,
        string $requestFingerprint,
        array $result,
    ): void {
        $encoded = json_encode(
            $result,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        );
        $update = $pdo->prepare(
            'UPDATE comment_mutation_receipts
             SET response_encrypted = :response
             WHERE key_hash = :key AND user_id = :user
               AND request_fingerprint = :fingerprint
               AND response_encrypted IS NULL'
        );
        $update->execute([
            'response' => $this->crypto->encrypt($encoded),
            'key' => $keyHash,
            'user' => $userId,
            'fingerprint' => $requestFingerprint,
        ]);
        if ($update->rowCount() !== 1) {
            throw new RuntimeException('Comment mutation receipt did not complete exactly once.');
        }
    }

    /** @return array<string, mixed> */
    private function decryptCommentMutationResponse(string $encrypted): array
    {
        $decoded = json_decode(
            $this->crypto->decrypt($encrypted),
            true,
            32,
            JSON_THROW_ON_ERROR,
        );
        if (!is_array($decoded) ||
            !is_string($decoded['id'] ?? null) ||
            !is_string($decoded['body'] ?? null)) {
            throw new RuntimeException('Stored comment replay response is invalid.');
        }
        return $decoded;
    }

    /** @return array<string, mixed> */
    public function updateComment(int $userId, string $commentIdValue, mixed $bodyValue): array
    {
        $commentId = self::id($commentIdValue, 'comment');
        $body = self::body($bodyValue, 1000, 'comment');
        $statement = $this->database->connection()->prepare(
            'UPDATE comments SET body = :body, updated_at = CURRENT_TIMESTAMP
             WHERE id = :comment AND user_id = :owner_user
               AND EXISTS (
                 SELECT 1 FROM answers a
                 JOIN family_members fm ON fm.family_id = a.family_id
                 WHERE a.id = comments.answer_id AND fm.user_id = :member_user
               )'
        );
        $statement->execute([
            'body' => $body,
            'comment' => $commentId,
            'owner_user' => $userId,
            'member_user' => $userId,
        ]);
        if ($statement->rowCount() === 0) {
            $owned = $this->database->connection()->prepare(
                'SELECT 1 FROM comments c
                 JOIN answers a ON a.id = c.answer_id
                 JOIN family_members fm ON fm.family_id = a.family_id AND fm.user_id = :member
                 WHERE c.id = :comment AND c.user_id = :owner'
            );
            $owned->execute(['member' => $userId, 'comment' => $commentId, 'owner' => $userId]);
            if ($owned->fetchColumn() === false) {
                throw new ApiException(404, 'comment_not_found', 'Comment not found.');
            }
        }
        return $this->commentById($commentId);
    }

    /** @return array<string, mixed> */
    public function reportComment(
        int $userId,
        string $commentIdValue,
        mixed $reasonValue,
        mixed $detailsValue = null,
    ): array {
        $commentId = self::id($commentIdValue, 'comment');
        if (!is_string($reasonValue) || !in_array(
            $reasonValue,
            ['spam', 'harassment', 'privacy', 'inappropriate', 'other'],
            true,
        )) {
            throw new ApiException(
                422,
                'invalid_report_reason',
                'reason must be spam, harassment, privacy, inappropriate, or other.',
            );
        }
        $details = null;
        if ($detailsValue !== null) {
            if (!is_string($detailsValue) || !mb_check_encoding($detailsValue, 'UTF-8')) {
                throw new ApiException(422, 'invalid_report_details', 'details must be valid text.');
            }
            $details = trim(str_replace("\0", '', $detailsValue));
            if (mb_strlen($details, 'UTF-8') > 500) {
                throw new ApiException(
                    422,
                    'invalid_report_details',
                    'details must be no longer than 500 characters.',
                );
            }
            $details = $details === '' ? null : $details;
        }
        $reason = $reasonValue;
        return $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $commentId,
            $reason,
            $details,
        ): array {
            // Use the same membership/family lock as answer, like, and comment
            // mutations. A concurrent leave/removal therefore commits either
            // before this authorization check or after the report insert.
            $family = $this->lockedFamilyRow($pdo, $userId);
            $commentSql =
                'SELECT c.user_id FROM comments c
                 JOIN answers a ON a.id = c.answer_id
                 WHERE c.id = :comment AND a.family_id = :family';
            if (!$this->database->isSqlite()) {
                $commentSql .= ' FOR UPDATE';
            }
            $comment = $pdo->prepare($commentSql);
            $comment->execute(['comment' => $commentId, 'family' => $family['id']]);
            $ownerId = $comment->fetchColumn();
            if ($ownerId === false) {
                throw new ApiException(404, 'comment_not_found', 'Comment not found.');
            }
            if ((int) $ownerId === $userId) {
                throw new ApiException(422, 'self_report_not_allowed', 'Users cannot report their own comments.');
            }
            $statement = $pdo->prepare($this->database->isSqlite()
                ? 'INSERT INTO comment_reports (comment_id, reported_by_user_id, reason, details)
                   VALUES (:comment, :reporter, :reason, :details)
                   ON CONFLICT(comment_id, reported_by_user_id) DO UPDATE SET
                     reason = excluded.reason, details = excluded.details,
                     status = \'pending\', updated_at = CURRENT_TIMESTAMP'
                : 'INSERT INTO comment_reports (comment_id, reported_by_user_id, reason, details)
                   VALUES (:comment, :reporter, :reason, :details)
                   ON DUPLICATE KEY UPDATE
                     reason = VALUES(reason), details = VALUES(details),
                     status = \'pending\', updated_at = CURRENT_TIMESTAMP'
            );
            $statement->execute([
                'comment' => $commentId,
                'reporter' => $userId,
                'reason' => $reason,
                'details' => $details,
            ]);
            $lookup = $pdo->prepare(
                'SELECT id, comment_id, reason, status, created_at FROM comment_reports
                 WHERE comment_id = :comment AND reported_by_user_id = :reporter'
            );
            $lookup->execute(['comment' => $commentId, 'reporter' => $userId]);
            $row = $lookup->fetch();
            if (!is_array($row)) {
                throw new RuntimeException('Comment report could not be loaded.');
            }
            return [
                'id' => (string) $row['id'],
                'commentId' => (string) $row['comment_id'],
                'reason' => (string) $row['reason'],
                'status' => (string) $row['status'],
                'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
            ];
        });
    }

    public function deleteComment(int $userId, string $commentIdValue): void
    {
        $commentId = self::id($commentIdValue, 'comment');
        $statement = $this->database->connection()->prepare(
            'DELETE FROM comments
             WHERE id = :comment AND user_id = :owner_user
               AND EXISTS (
                 SELECT 1 FROM answers a
                 JOIN family_members fm ON fm.family_id = a.family_id
                 WHERE a.id = comments.answer_id AND fm.user_id = :member_user
               )'
        );
        $statement->execute([
            'owner_user' => $userId,
            'member_user' => $userId,
            'comment' => $commentId,
        ]);
        if ($statement->rowCount() === 0) {
            throw new ApiException(404, 'comment_not_found', 'Comment not found.');
        }
    }

    /** @return array{tokenHash: string, platform: string, environment: string} */
    public function registerPushToken(int $userId, mixed $tokenValue, mixed $platformValue, mixed $environmentValue): array
    {
        if (!is_string($tokenValue) || preg_match('/^(?:[A-Fa-f0-9]{2}){16,128}$/', $tokenValue) !== 1) {
            throw new ApiException(422, 'invalid_push_token', 'token is invalid.');
        }
        $platform = $platformValue ?? 'ios';
        $environment = $environmentValue ?? 'production';
        if ($platform !== 'ios' || !in_array($environment, ['sandbox', 'production'], true)) {
            throw new ApiException(422, 'invalid_push_token', 'platform or environment is invalid.');
        }
        $tokenHash = $this->crypto->hashOpaque('push:' . $tokenValue);
        $statement = $this->database->connection()->prepare($this->database->isSqlite()
            ? 'INSERT INTO push_tokens (user_id, token_hash, token_encrypted, platform, environment)
               VALUES (:user, :hash, :encrypted, :platform, :environment)
               ON CONFLICT(token_hash) DO UPDATE SET
                  user_id = excluded.user_id,
                  token_encrypted = excluded.token_encrypted,
                  platform = excluded.platform,
                  environment = excluded.environment,
                  updated_at = CURRENT_TIMESTAMP'
            : 'INSERT INTO push_tokens (user_id, token_hash, token_encrypted, platform, environment)
               VALUES (:user, :hash, :encrypted, :platform, :environment)
               ON DUPLICATE KEY UPDATE
                  user_id = VALUES(user_id),
                  token_encrypted = VALUES(token_encrypted),
                  platform = VALUES(platform),
                  environment = VALUES(environment),
                  updated_at = CURRENT_TIMESTAMP'
        );
        $statement->execute([
            'user' => $userId,
            'hash' => $tokenHash,
            'encrypted' => $this->crypto->encrypt($tokenValue),
            'platform' => $platform,
            'environment' => $environment,
        ]);
        return ['tokenHash' => $tokenHash, 'platform' => $platform, 'environment' => $environment];
    }

    public function deletePushToken(int $userId, string $tokenHash): void
    {
        if (preg_match('/^[a-f0-9]{64}$/', $tokenHash) !== 1) {
            throw new ApiException(422, 'invalid_push_token', 'tokenHash is invalid.');
        }
        $statement = $this->database->connection()->prepare(
            'DELETE FROM push_tokens WHERE user_id = :user AND token_hash = :hash'
        );
        $statement->execute(['user' => $userId, 'hash' => $tokenHash]);
    }

    /** @return array<string, mixed> */
    private function familyRow(int $userId): array
    {
        $statement = $this->database->connection()->prepare(
            'SELECT f.id, f.name, f.invite_code
             FROM families f
             JOIN family_members fm ON fm.family_id = f.id
             WHERE fm.user_id = :user LIMIT 1'
        );
        $statement->execute(['user' => $userId]);
        $family = $statement->fetch();
        if (!is_array($family)) {
            throw new ApiException(409, 'family_required', 'The user does not belong to a family.');
        }
        return $family;
    }

    /** @return array<string, mixed> */
    private function lockedFamilyRow(PDO $pdo, int $userId): array
    {
        $sql =
            'SELECT f.id, f.name, f.invite_code
             FROM families f
             JOIN family_members fm ON fm.family_id = f.id
             WHERE fm.user_id = :user LIMIT 1';
        if (!$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['user' => $userId]);
        $family = $statement->fetch();
        if (!is_array($family)) {
            throw new ApiException(409, 'family_required', 'The user does not belong to a family.');
        }
        return $family;
    }

    /** @return array<string, mixed> */
    private function todayQuestionRow(int $userId): array
    {
        $family = $this->familyRow($userId);
        $now = $this->clock === null ? null : ($this->clock)();
        return (new DailyQuestionSchedule($this->database, $this->config))
            ->forFamily((int) $family['id'], $now);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function answerRows(
        int $familyId,
        int $viewerId,
        ?int $beforeId,
        ?string $date,
        int $limit,
        array $filters = [],
    ): array {
        $sql =
            'SELECT a.id, a.user_id, a.answer_date, a.body, a.created_at, a.updated_at,
                    q.id AS question_id, q.prompt,
                    u.phone_e164, u.display_name, u.avatar_url, u.avatar_mark, u.created_at AS user_created_at,
                    (SELECT COUNT(*) FROM answer_likes al WHERE al.answer_id = a.id) AS likes_count,
                    EXISTS(SELECT 1 FROM answer_likes al2 WHERE al2.answer_id = a.id AND al2.user_id = :viewer) AS is_liked,
                    (SELECT COUNT(*) FROM comments c WHERE c.answer_id = a.id) AS comments_count
             FROM answers a
             JOIN questions q ON q.id = a.question_id
             JOIN users u ON u.id = a.user_id
             WHERE a.family_id = :family';
        if ($beforeId !== null) {
            $sql .= ' AND a.id < :before_id';
        }
        if ($date !== null) {
            $sql .= ' AND a.answer_date = :answer_date';
        }
        if (($filters['scope'] ?? 'family') === 'mine') {
            $sql .= ' AND a.user_id = :scope_user';
        }
        if (($filters['authorId'] ?? null) !== null) {
            $sql .= ' AND a.user_id = :author_user';
        }
        if (($filters['from'] ?? null) !== null) {
            $sql .= ' AND a.answer_date >= :date_from';
        }
        if (($filters['to'] ?? null) !== null) {
            $sql .= ' AND a.answer_date <= :date_to';
        }
        if (($filters['search'] ?? null) !== null) {
            if ($this->database->isSqlite()) {
                $sql .= ' AND (
                    instr(tsutsuura_search_fold(a.body), tsutsuura_search_fold(:search_body)) > 0 OR
                    instr(tsutsuura_search_fold(q.prompt), tsutsuura_search_fold(:search_prompt)) > 0 OR
                    instr(tsutsuura_search_fold(u.display_name), tsutsuura_search_fold(:search_author)) > 0
                )';
            } else {
                $sql .= ' AND (
                    LOCATE(:search_body, a.body) > 0 OR
                    LOCATE(:search_prompt, q.prompt) > 0 OR
                    LOCATE(:search_author, u.display_name) > 0
                )';
            }
        }
        $sql .= ' ORDER BY a.id DESC LIMIT :limit';
        $statement = $this->database->connection()->prepare($sql);
        $statement->bindValue(':viewer', $viewerId, PDO::PARAM_INT);
        $statement->bindValue(':family', $familyId, PDO::PARAM_INT);
        if ($beforeId !== null) {
            $statement->bindValue(':before_id', $beforeId, PDO::PARAM_INT);
        }
        if ($date !== null) {
            $statement->bindValue(':answer_date', $date);
        }
        if (($filters['scope'] ?? 'family') === 'mine') {
            $statement->bindValue(':scope_user', $viewerId, PDO::PARAM_INT);
        }
        if (($filters['authorId'] ?? null) !== null) {
            $statement->bindValue(':author_user', $filters['authorId'], PDO::PARAM_INT);
        }
        if (($filters['from'] ?? null) !== null) {
            $statement->bindValue(':date_from', $filters['from']);
        }
        if (($filters['to'] ?? null) !== null) {
            $statement->bindValue(':date_to', $filters['to']);
        }
        if (($filters['search'] ?? null) !== null) {
            $statement->bindValue(':search_body', $filters['search']);
            $statement->bindValue(':search_prompt', $filters['search']);
            $statement->bindValue(':search_author', $filters['search']);
        }
        $statement->bindValue(':limit', $limit, PDO::PARAM_INT);
        $statement->execute();
        $rows = $statement->fetchAll();
        $media = $this->answerMedia->forAnswers(array_map(
            static fn (array $row): int => (int) $row['id'],
            $rows,
        ));
        return array_map(
            fn (array $row): array => $this->presentAnswer($row, $media[(int) $row['id']] ?? []),
            $rows,
        );
    }

    /** @return array<string, mixed> */
    private function answer(int $answerId, int $viewerId): array
    {
        $family = $this->familyRow($viewerId);
        $rows = $this->answerRows((int) $family['id'], $viewerId, null, null, 100);
        foreach ($rows as $answer) {
            if ((int) $answer['id'] === $answerId) {
                return $answer;
            }
        }
        // A direct query avoids a false 404 in unusually large feeds.
        $statement = $this->database->connection()->prepare(
            'SELECT a.id, a.user_id, a.answer_date, a.body, a.created_at, a.updated_at,
                    q.id AS question_id, q.prompt,
                    u.phone_e164, u.display_name, u.avatar_url, u.avatar_mark, u.created_at AS user_created_at,
                    (SELECT COUNT(*) FROM answer_likes al WHERE al.answer_id = a.id) AS likes_count,
                    EXISTS(SELECT 1 FROM answer_likes al2 WHERE al2.answer_id = a.id AND al2.user_id = :viewer) AS is_liked,
                    (SELECT COUNT(*) FROM comments c WHERE c.answer_id = a.id) AS comments_count
             FROM answers a
             JOIN questions q ON q.id = a.question_id
             JOIN users u ON u.id = a.user_id
             WHERE a.id = :answer AND a.family_id = :family'
        );
        $statement->execute(['viewer' => $viewerId, 'answer' => $answerId, 'family' => $family['id']]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'answer_not_found', 'Answer not found.');
        }
        $media = $this->answerMedia->forAnswers([(int) $row['id']]);
        return $this->presentAnswer($row, $media[(int) $row['id']] ?? []);
    }

    private function assertAnswerVisible(int $answerId, int $userId): void
    {
        $statement = $this->database->connection()->prepare(
            'SELECT 1 FROM answers a
             JOIN family_members fm ON fm.family_id = a.family_id
             WHERE a.id = :answer AND fm.user_id = :user'
        );
        $statement->execute(['answer' => $answerId, 'user' => $userId]);
        if ($statement->fetchColumn() === false) {
            throw new ApiException(404, 'answer_not_found', 'Answer not found.');
        }
    }

    /** @return array<string, mixed> */
    private function ownedAnswer(
        PDO $pdo,
        int $answerId,
        int $userId,
        bool $forUpdate,
    ): array {
        $sql =
            'SELECT a.id, a.body,
                    (SELECT COUNT(*) FROM answer_media am WHERE am.answer_id = a.id) AS media_count
             FROM answers a
             JOIN family_members fm ON fm.family_id = a.family_id AND fm.user_id = :member_user
             WHERE a.id = :answer AND a.user_id = :owner_user';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute([
            'member_user' => $userId,
            'answer' => $answerId,
            'owner_user' => $userId,
        ]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'answer_not_found', 'Answer not found.');
        }
        return $row;
    }

    /** @param array<string, mixed> $values
     *  @return array{search: ?string, from: ?string, to: ?string, authorId: ?int, scope: string}
     */
    private function historyFilters(array $values): array
    {
        $searchValue = $values['search'] ?? $values['q'] ?? null;
        $search = null;
        if ($searchValue !== null && $searchValue !== '') {
            if (!is_string($searchValue)) {
                throw new ApiException(422, 'invalid_search', 'search must be a string.');
            }
            $search = trim(str_replace("\0", '', $searchValue));
            if ($search === '' || mb_strlen($search, 'UTF-8') > 100) {
                throw new ApiException(422, 'invalid_search', 'search must be between 1 and 100 characters.');
            }
        }
        $date = self::optionalDate($values['date'] ?? null, 'date');
        $from = self::optionalDate($values['from'] ?? null, 'from');
        $to = self::optionalDate($values['to'] ?? null, 'to');
        if ($date !== null) {
            if ($from !== null || $to !== null) {
                throw new ApiException(
                    422,
                    'invalid_date_range',
                    'date cannot be combined with from or to.',
                );
            }
            $from = $date;
            $to = $date;
        }
        if ($from !== null && $to !== null && $from > $to) {
            throw new ApiException(422, 'invalid_date_range', 'from must not be after to.');
        }
        $authorId = null;
        $authorValue = $values['authorId'] ?? null;
        if ($authorValue !== null && $authorValue !== '') {
            if (!is_string($authorValue) || preg_match('/^[1-9][0-9]{0,18}$/', $authorValue) !== 1) {
                throw new ApiException(422, 'invalid_author_filter', 'authorId is invalid.');
            }
            $authorId = (int) $authorValue;
        }
        $scope = $values['scope'] ?? 'family';
        if (!is_string($scope) || !in_array($scope, ['family', 'mine'], true)) {
            throw new ApiException(422, 'invalid_scope', 'scope must be family or mine.');
        }
        return [
            'search' => $search,
            'from' => $from,
            'to' => $to,
            'authorId' => $authorId,
            'scope' => $scope,
        ];
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function presentAnswer(array $row, array $media = []): array
    {
        $author = [
            'id' => $row['user_id'],
            'phone_e164' => $row['phone_e164'],
            'display_name' => $row['display_name'],
            'avatar_url' => $row['avatar_url'],
            'avatar_mark' => $row['avatar_mark'],
            'created_at' => $row['user_created_at'],
        ];
        return [
            'id' => (string) $row['id'],
            'answerDate' => (string) $row['answer_date'],
            'body' => (string) $row['body'],
            'media' => array_values($media),
            'question' => [
                'id' => (string) $row['question_id'],
                'prompt' => (string) $row['prompt'],
                'date' => (string) $row['answer_date'],
                'timeZoneIdentifier' => $this->config->timezone->getName(),
            ],
            'author' => Presenter::user($author),
            'likesCount' => (int) $row['likes_count'],
            'isLiked' => (bool) $row['is_liked'],
            'commentsCount' => (int) $row['comments_count'],
            'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
            'updatedAt' => Presenter::utcTimestamp((string) $row['updated_at']),
        ];
    }

    /** @return array<string, mixed> */
    private function commentById(int $commentId): array
    {
        $statement = $this->database->connection()->prepare(
            'SELECT c.id, c.answer_id, c.user_id, c.parent_comment_id,
                    c.body, c.created_at, c.updated_at,
                    u.phone_e164, u.display_name, u.avatar_url, u.avatar_mark, u.created_at AS user_created_at
             FROM comments c JOIN users u ON u.id = c.user_id WHERE c.id = :id'
        );
        $statement->execute(['id' => $commentId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'comment_not_found', 'Comment not found.');
        }
        return $this->presentComment($row);
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function presentComment(array $row): array
    {
        $author = [
            'id' => $row['user_id'],
            'phone_e164' => $row['phone_e164'],
            'display_name' => $row['display_name'],
            'avatar_url' => $row['avatar_url'],
            'avatar_mark' => $row['avatar_mark'],
            'created_at' => $row['user_created_at'],
        ];
        return [
            'id' => (string) $row['id'],
            'answerId' => (string) $row['answer_id'],
            'parentCommentId' => $row['parent_comment_id'] === null
                ? null
                : (string) $row['parent_comment_id'],
            'body' => (string) $row['body'],
            'author' => Presenter::user($author),
            'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
            'updatedAt' => Presenter::utcTimestamp((string) $row['updated_at']),
        ];
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function question(array $row, string $date): array
    {
        return [
            'id' => (string) $row['id'],
            'prompt' => $row['is_available'] ? (string) $row['prompt'] : '',
            'date' => $date,
            'availableAt' => Presenter::utcTimestamp((string) $row['available_at']),
            'timeZoneIdentifier' => $this->config->timezone->getName(),
            'isAvailable' => (bool) $row['is_available'],
        ];
    }

    private static function id(string $value, string $resource): int
    {
        if (preg_match('/^[1-9][0-9]{0,18}$/', $value) !== 1) {
            throw new ApiException(422, 'invalid_id', sprintf('%s id is invalid.', $resource));
        }
        return (int) $value;
    }

    private static function optionalDate(mixed $value, string $field): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_string($value) || preg_match('/^\d{4}-\d{2}-\d{2}$/', $value) !== 1) {
            throw new ApiException(422, 'invalid_date_filter', $field . ' must use YYYY-MM-DD.');
        }
        $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
        if (!$date instanceof DateTimeImmutable || $date->format('Y-m-d') !== $value) {
            throw new ApiException(422, 'invalid_date_filter', $field . ' is not a valid date.');
        }
        return $value;
    }

    private static function body(mixed $value, int $max, string $field, bool $allowEmpty = false): string
    {
        if (!is_string($value)) {
            throw new ApiException(422, 'invalid_' . $field, $field . ' body must be a string.');
        }
        if (!mb_check_encoding($value, 'UTF-8')) {
            throw new ApiException(422, 'invalid_' . $field, $field . ' body must be valid UTF-8.');
        }
        $value = trim(str_replace("\0", '', $value));
        $length = mb_strlen($value, 'UTF-8');
        if ((!$allowEmpty && $length < 1) || $length > $max) {
            throw new ApiException(
                422,
                'invalid_' . $field,
                sprintf('%s body must be between 1 and %d characters.', ucfirst($field), $max),
            );
        }
        return $value;
    }
}
