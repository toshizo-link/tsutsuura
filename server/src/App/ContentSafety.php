<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use PDO;
use RuntimeException;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;

/** Shared visibility policy for feeds, direct access, media and push delivery. */
final class ContentSafety
{
    public function __construct(private readonly Database $database) {}

    // Expressions and aliases passed here are application constants. User IDs
    // are typed integers, avoiding duplicate PDO placeholders on native MySQL.
    public static function contactSQL(string $authorExpression, int $viewerId): string
    {
        return "NOT EXISTS (SELECT 1 FROM user_blocks safety_block WHERE
            (safety_block.blocker_user_id = {$viewerId} AND safety_block.blocked_user_id = {$authorExpression}) OR
            (safety_block.blocked_user_id = {$viewerId} AND safety_block.blocker_user_id = {$authorExpression}))";
    }

    public static function answerSQL(string $alias, int $viewerId): string
    {
        return self::contactSQL("{$alias}.user_id", $viewerId) . "
            AND NOT EXISTS (SELECT 1 FROM answer_reports safety_report
                WHERE safety_report.answer_id = {$alias}.id AND safety_report.reported_by_user_id = {$viewerId})
            AND NOT EXISTS (SELECT 1 FROM moderation_actions safety_action
                WHERE safety_action.answer_id = {$alias}.id AND safety_action.decision = 'remove')";
    }

    public static function commentSQL(string $alias, int $viewerId): string
    {
        return self::contactSQL("{$alias}.user_id", $viewerId) . "
            AND NOT EXISTS (SELECT 1 FROM comment_reports safety_report
                WHERE safety_report.comment_id = {$alias}.id AND safety_report.reported_by_user_id = {$viewerId})
            AND NOT EXISTS (SELECT 1 FROM moderation_actions safety_action
                WHERE safety_action.comment_id = {$alias}.id AND safety_action.decision = 'remove')";
    }

    public static function canContact(PDO $pdo, int $viewerId, int $authorId): bool
    {
        return (bool) $pdo->query('SELECT ' . self::contactSQL((string) $authorId, $viewerId))->fetchColumn();
    }

    public static function canSeeAnswer(PDO $pdo, int $viewerId, int $answerId): bool
    {
        $query = $pdo->prepare('SELECT 1 FROM answers a JOIN family_members fm ON fm.family_id = a.family_id
            WHERE a.id = :answer AND fm.user_id = :viewer AND ' . self::answerSQL('a', $viewerId));
        $query->execute(['answer' => $answerId, 'viewer' => $viewerId]);
        return $query->fetchColumn() !== false;
    }

    public static function canSeeComment(PDO $pdo, int $viewerId, int $commentId): bool
    {
        $query = $pdo->prepare('SELECT 1 FROM comments c JOIN answers a ON a.id = c.answer_id
            JOIN family_members fm ON fm.family_id = a.family_id
            WHERE c.id = :comment AND fm.user_id = :viewer AND ' . self::answerSQL('a', $viewerId)
            . ' AND ' . self::commentSQL('c', $viewerId));
        $query->execute(['comment' => $commentId, 'viewer' => $viewerId]);
        return $query->fetchColumn() !== false;
    }

    public static function allowsNotification(PDO $pdo, int $viewerId, array $data, ?int $actorId = null): bool
    {
        $actorId ??= isset($data['actor_user_id']) ? (int) $data['actor_user_id'] : null;
        if ($actorId !== null && !self::canContact($pdo, $viewerId, $actorId)) { return false; }
        $answerId = $data['answer_id'] ?? $data['answerId'] ?? null;
        if ($answerId !== null && !self::canSeeAnswer($pdo, $viewerId, (int) $answerId)) { return false; }
        $commentId = $data['comment_id'] ?? $data['commentId'] ?? null;
        return $commentId === null || self::canSeeComment($pdo, $viewerId, (int) $commentId);
    }

    /** Cancel queued work while the hide choice is committed, so unblocking
     * cannot revive an old notification. APNs requests already in flight
     * cannot be recalled. Call inside the caller's transaction.
     * @param list<int>|null $recipients null checks all active recipients
     */
    public static function cancelHiddenNotifications(PDO $pdo, ?array $recipients = null): void
    {
        $sql = "SELECT id, recipient_user_id, actor_user_id, data_json FROM notification_event_outbox
            WHERE status IN ('pending', 'retry', 'processing')";
        if ($recipients !== null) {
            if ($recipients === []) { return; }
            $sql .= ' AND recipient_user_id IN (' . implode(',', array_map('intval', $recipients)) . ')';
        }
        $sql .= ' ORDER BY id';
        if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'sqlite') { $sql .= ' FOR UPDATE'; }
        foreach ($pdo->query($sql)->fetchAll() as $row) {
            $data = json_decode((string) $row['data_json'], true);
            if (!is_array($data) || self::allowsNotification($pdo, (int) $row['recipient_user_id'], $data, (int) $row['actor_user_id'])) { continue; }
            $cancel = $pdo->prepare("UPDATE notification_event_deliveries SET status = 'skipped',
                claimed_at = NULL, claim_token = NULL, completed_at = CURRENT_TIMESTAMP,
                last_error = 'content_hidden', updated_at = CURRENT_TIMESTAMP
                WHERE outbox_id = :outbox AND status IN ('pending', 'retry', 'processing')");
            $cancel->execute(['outbox' => $row['id']]);
            // Every child shares the same recipient/content. Keep completed
            // device outcomes and provider totals, while ending active work.
            $outcomes = $pdo->prepare("SELECT SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
                SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered
                FROM notification_event_deliveries WHERE outbox_id = :outbox");
            $outcomes->execute(['outbox' => $row['id']]);
            $totals = $outcomes->fetch();
            $update = $pdo->prepare("UPDATE notification_event_outbox SET status = :status,
                claimed_at = NULL, claim_token = NULL, completed_at = CURRENT_TIMESTAMP,
                last_error = 'content_hidden', updated_at = CURRENT_TIMESTAMP WHERE id = :id");
            $update->execute(['status' => (int) $totals['failed'] > 0 ? 'failed'
                : ((int) $totals['delivered'] > 0 ? 'delivered' : 'skipped'), 'id' => $row['id']]);
        }
    }

    /** @return array<string, mixed> */
    public function snapshot(int $userId): array
    {
        $pdo = $this->database->connection();
        $query = $pdo->prepare('SELECT u.id, u.display_name, u.avatar_url, u.avatar_mark, u.phone_e164, u.created_at
            FROM user_blocks b JOIN users u ON u.id = b.blocked_user_id
            WHERE b.blocker_user_id = :viewer ORDER BY b.created_at, u.id');
        $query->execute(['viewer' => $userId]);
        $users = array_map(Presenter::user(...), $query->fetchAll());
        $hidden = $pdo->prepare('SELECT blocked_user_id AS id FROM user_blocks WHERE blocker_user_id = :viewer1
            UNION SELECT blocker_user_id AS id FROM user_blocks WHERE blocked_user_id = :viewer2');
        $hidden->execute(['viewer1' => $userId, 'viewer2' => $userId]);
        $answerIds = $pdo->prepare('SELECT a.id FROM answers a JOIN family_members fm ON fm.family_id = a.family_id
            WHERE fm.user_id = :viewer AND NOT (' . self::answerSQL('a', $userId) . ')');
        $answerIds->execute(['viewer' => $userId]);
        $commentIds = $pdo->prepare('SELECT c.id FROM comments c JOIN answers a ON a.id = c.answer_id
            JOIN family_members fm ON fm.family_id = a.family_id WHERE fm.user_id = :viewer
            AND (NOT (' . self::answerSQL('a', $userId) . ') OR NOT (' . self::commentSQL('c', $userId) . '))');
        $commentIds->execute(['viewer' => $userId]);
        return ['users' => $users,
            'hiddenUserIds' => array_map('strval', $hidden->fetchAll(PDO::FETCH_COLUMN)),
            'hiddenAnswerIds' => array_map('strval', $answerIds->fetchAll(PDO::FETCH_COLUMN)),
            'hiddenCommentIds' => array_map('strval', $commentIds->fetchAll(PDO::FETCH_COLUMN))];
    }

    public function block(int $userId, string $targetValue): void
    {
        $targetId = self::id($targetValue);
        if ($targetId === $userId) { throw new ApiException(422, 'self_block_not_allowed', '自分をブロックすることはできません。'); }
        $this->database->transaction(function (PDO $pdo) use ($userId, $targetId): void {
            $familyId = $this->lockFamily($pdo, $userId);
            $member = $pdo->prepare('SELECT 1 FROM family_members WHERE family_id = :family AND user_id = :target');
            $member->execute(['family' => $familyId, 'target' => $targetId]);
            if ($member->fetchColumn() === false) { throw new ApiException(404, 'user_not_found', '家族が見つかりません。'); }
            $insert = $pdo->prepare($this->database->isSqlite()
                ? 'INSERT OR IGNORE INTO user_blocks (blocker_user_id, blocked_user_id) VALUES (:viewer, :target)'
                : 'INSERT IGNORE INTO user_blocks (blocker_user_id, blocked_user_id) VALUES (:viewer, :target)');
            $insert->execute(['viewer' => $userId, 'target' => $targetId]);
            self::cancelHiddenNotifications($pdo, [$userId, $targetId]);
        });
    }

    public function unblock(int $userId, string $targetValue): void
    {
        $targetId = self::id($targetValue);
        if ($targetId === $userId) { throw new ApiException(422, 'self_block_not_allowed', '自分をブロックすることはできません。'); }
        // It remains possible to unblock someone after either person leaves
        // the family. This never changes a block owned by the other person.
        $this->database->transaction(function (PDO $pdo) use ($userId, $targetId): void {
            $this->lockFamily($pdo, $userId);
            $delete = $pdo->prepare('DELETE FROM user_blocks WHERE blocker_user_id = :viewer AND blocked_user_id = :target');
            $delete->execute(['viewer' => $userId, 'target' => $targetId]);
        });
    }

    /** Reports are unique per reporter/content; a lost-response retry returns
     * the original report rather than reopening a resolved moderation action.
     * @return array<string, mixed>
     */
    public function report(int $userId, string $type, string $idValue, mixed $reason, mixed $details = null): array
    {
        if (!in_array($type, ['answer', 'comment'], true)) { throw new RuntimeException('Invalid report resource.'); }
        $id = self::id($idValue);
        if (!is_string($reason) || !in_array($reason, ['spam', 'harassment', 'privacy', 'inappropriate', 'other'], true)) {
            throw new ApiException(422, 'invalid_report_reason', '報告の理由を選んでください。');
        }
        if ($details !== null) {
            if (!is_string($details) || !mb_check_encoding($details, 'UTF-8') || str_contains($details, "\0") || mb_strlen(trim($details), 'UTF-8') > 500) {
                throw new ApiException(422, 'invalid_report_details', '報告の詳細は500文字以内で入力してください。');
            }
            $details = trim($details) ?: null;
        }
        return $this->database->transaction(function (PDO $pdo) use ($userId, $type, $id, $reason, $details): array {
            $familyId = $this->lockFamily($pdo, $userId);
            $sql = $type === 'answer'
                ? 'SELECT user_id FROM answers WHERE id = :id AND family_id = :family'
                : 'SELECT c.user_id FROM comments c JOIN answers a ON a.id = c.answer_id WHERE c.id = :id AND a.family_id = :family';
            $query = $pdo->prepare($sql);
            $query->execute(['id' => $id, 'family' => $familyId]);
            $author = $query->fetchColumn();
            if ($author === false) { throw new ApiException(404, $type . '_not_found', '内容が見つかりません。'); }
            if ((int) $author === $userId) { throw new ApiException(422, 'self_report_not_allowed', '自分の投稿は報告できません。'); }
            $insert = $pdo->prepare(($this->database->isSqlite() ? 'INSERT OR IGNORE' : 'INSERT IGNORE')
                . " INTO {$type}_reports ({$type}_id, reported_by_user_id, reason, details) VALUES (:id, :viewer, :reason, :details)");
            $insert->execute(['id' => $id, 'viewer' => $userId, 'reason' => $reason, 'details' => $details]);
            self::cancelHiddenNotifications($pdo, [$userId]);
            $lookup = $pdo->prepare("SELECT id, {$type}_id AS content_id, reason, status, created_at FROM {$type}_reports
                WHERE {$type}_id = :id AND reported_by_user_id = :viewer");
            $lookup->execute(['id' => $id, 'viewer' => $userId]);
            $row = $lookup->fetch();
            if (!is_array($row)) { throw new RuntimeException('Report was not saved.'); }
            return ['id' => (string) $row['id'], $type . 'Id' => (string) $row['content_id'],
                'reason' => (string) $row['reason'], 'status' => (string) $row['status'],
                'createdAt' => Presenter::utcTimestamp((string) $row['created_at'])];
        });
    }

    private function lockFamily(PDO $pdo, int $userId): int
    {
        $sql = 'SELECT f.id FROM families f JOIN family_members fm ON fm.family_id = f.id WHERE fm.user_id = :user LIMIT 1';
        if (!$this->database->isSqlite()) { $sql .= ' FOR UPDATE'; }
        $query = $pdo->prepare($sql);
        $query->execute(['user' => $userId]);
        $familyId = $query->fetchColumn();
        if ($familyId === false) { throw new ApiException(409, 'family_required', '家族の登録が必要です。'); }
        return (int) $familyId;
    }

    private static function id(string $value): int
    {
        if (preg_match('/^[1-9][0-9]{0,18}$/', $value) !== 1 || (string) (int) $value !== $value) {
            throw new ApiException(422, 'invalid_id', '対象が正しくありません。');
        }
        return (int) $value;
    }
}
