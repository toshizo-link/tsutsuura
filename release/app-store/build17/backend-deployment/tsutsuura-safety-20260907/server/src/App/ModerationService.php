<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use PDO;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;

/** Operator-only service, exposed by the local CLI, never a public HTTP route. */
final class ModerationService
{
    public function __construct(private readonly Database $database) {}

    public function pending(int $limit = 50): array
    {
        if ($limit < 1 || $limit > 200) { throw new ApiException(422, 'invalid_limit', 'Limit must be 1–200.'); }
        $query = $this->database->connection()->prepare("SELECT * FROM (
            SELECT 'answer' AS type, id, answer_id AS content_id, reported_by_user_id, reason, details, status, created_at FROM answer_reports WHERE status = 'pending'
            UNION ALL
            SELECT 'comment' AS type, id, comment_id AS content_id, reported_by_user_id, reason, details, status, created_at FROM comment_reports WHERE status = 'pending'
            ) reports ORDER BY created_at, type, id LIMIT :limit");
        $query->bindValue(':limit', $limit, PDO::PARAM_INT);
        $query->execute();
        return $query->fetchAll();
    }

    public function show(string $type, int $reportId): array
    {
        self::validateType($type, $reportId);
        $pdo = $this->database->connection();
        $query = $pdo->prepare("SELECT r.*, c.body, c.user_id AS author_user_id FROM {$type}_reports r
            JOIN {$type}s c ON c.id = r.{$type}_id WHERE r.id = :id");
        $query->execute(['id' => $reportId]);
        $row = $query->fetch();
        if (!is_array($row)) { throw new ApiException(404, 'report_not_found', 'Report not found.'); }
        if ($type === 'answer') {
            $media = $pdo->prepare('SELECT id, kind, file_name, mime_type, storage_key, byte_count FROM answer_media WHERE answer_id = :answer ORDER BY id');
            $media->execute(['answer' => $row['answer_id']]);
            $row['media'] = $media->fetchAll();
        }
        return $row;
    }

    public function review(string $type, int $reportId, string $decision, string $reviewer, string $note): array
    {
        self::validateType($type, $reportId);
        if (!in_array($decision, ['remove', 'dismiss'], true)) { throw new ApiException(422, 'invalid_decision', 'Choose remove or dismiss.'); }
        foreach (['reviewer' => [$reviewer, 100], 'note' => [$note, 1000]] as $field => [$value, $maximum]) {
            if (!mb_check_encoding($value, 'UTF-8') || trim($value) === '' || str_contains($value, "\0") || mb_strlen($value, 'UTF-8') > $maximum) {
                throw new ApiException(422, 'invalid_review', "{$field} must contain 1–{$maximum} valid characters.");
            }
        }
        return $this->database->transaction(function (PDO $pdo) use ($type, $reportId, $decision, $reviewer, $note): array {
            $query = $pdo->prepare("SELECT id, {$type}_id AS content_id FROM {$type}_reports WHERE id = :id"
                . ($this->database->isSqlite() ? '' : ' FOR UPDATE'));
            $query->execute(['id' => $reportId]);
            $report = $query->fetch();
            if (!is_array($report)) { throw new ApiException(404, 'report_not_found', 'Report not found.'); }
            $existing = $pdo->prepare('SELECT decision FROM moderation_actions WHERE report_type = :type AND report_id = :id');
            $existing->execute(['type' => $type, 'id' => $reportId]);
            $old = $existing->fetchColumn();
            if ($old !== false && $old !== $decision) { throw new ApiException(409, 'report_already_reviewed', 'This report already has a different decision.'); }
            if ($old === false) {
                $insert = $pdo->prepare("INSERT INTO moderation_actions (report_type, report_id, {$type}_id, decision, reviewer, note)
                    VALUES (:type, :report, :content, :decision, :reviewer, :note)");
                $insert->execute(['type' => $type, 'report' => $reportId, 'content' => $report['content_id'],
                    'decision' => $decision, 'reviewer' => trim($reviewer), 'note' => trim($note)]);
            }
            $update = $pdo->prepare("UPDATE {$type}_reports SET status = :status, updated_at = CURRENT_TIMESTAMP WHERE id = :id");
            $update->execute(['status' => $decision === 'remove' ? 'reviewed' : 'dismissed', 'id' => $reportId]);
            if ($decision === 'remove') { ContentSafety::cancelHiddenNotifications($pdo); }
            return ['type' => $type, 'reportId' => (string) $reportId, 'decision' => $decision,
                'contentId' => (string) $report['content_id']];
        });
    }

    private static function validateType(string $type, int $id): void
    {
        if (!in_array($type, ['answer', 'comment'], true) || $id < 1) {
            throw new ApiException(422, 'invalid_report', 'Use answer/comment and a positive report id.');
        }
    }
}
