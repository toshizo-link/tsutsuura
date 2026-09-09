<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use PDO;
use RuntimeException;

/**
 * Adds immutable, per-recipient push jobs to the content transaction.
 *
 * Network delivery is intentionally absent from this service. The outbox row
 * commits atomically with the mutation and EventNotificationWorker delivers it
 * later, so APNs latency and transient failures cannot affect API responses.
 */
final class EventNotificationService
{
    public function enqueueAnswerSubmitted(PDO $pdo, int $actorUserId, int $answerId): void
    {
        $statement = $pdo->prepare(
            'SELECT a.family_id, u.display_name
             FROM answers a
             JOIN users u ON u.id = a.user_id
             WHERE a.id = :answer AND a.user_id = :actor'
        );
        $statement->execute(['answer' => $answerId, 'actor' => $actorUserId]);
        $context = $statement->fetch();
        if (!is_array($context)) {
            throw new RuntimeException('Answer notification context is unavailable.');
        }

        $familyId = (int) $context['family_id'];
        foreach ($this->familyRecipients($pdo, $familyId, $actorUserId) as $recipientUserId) {
            $this->enqueue(
                $pdo,
                'answer_submitted',
                'familyActivity',
                $familyId,
                $actorUserId,
                $recipientUserId,
                $answerId,
                null,
                '家族の新しい回答',
                sprintf('「%s」から今日の回答が届きました。', (string) $context['display_name']),
                [
                    'destination' => 'family_answer',
                    'event_type' => 'answer_submitted',
                    'answer_id' => (string) $answerId,
                ],
            );
        }
    }

    public function enqueueCommentAdded(PDO $pdo, int $actorUserId, int $commentId): void
    {
        $statement = $pdo->prepare(
            'SELECT c.answer_id, a.family_id, a.user_id AS answer_owner_id,
                    parent.user_id AS parent_owner_id, actor.display_name
             FROM comments c
             JOIN answers a ON a.id = c.answer_id
             JOIN users actor ON actor.id = c.user_id
             LEFT JOIN comments parent ON parent.id = c.parent_comment_id
             WHERE c.id = :comment AND c.user_id = :actor'
        );
        $statement->execute(['comment' => $commentId, 'actor' => $actorUserId]);
        $context = $statement->fetch();
        if (!is_array($context)) {
            throw new RuntimeException('Comment notification context is unavailable.');
        }

        $candidates = [(int) $context['answer_owner_id']];
        if ($context['parent_owner_id'] !== null) {
            $candidates[] = (int) $context['parent_owner_id'];
        }
        $familyId = (int) $context['family_id'];
        $answerId = (int) $context['answer_id'];
        foreach ($this->currentFamilyRecipients(
            $pdo,
            $familyId,
            $actorUserId,
            $candidates,
        ) as $recipientUserId) {
            $this->enqueue(
                $pdo,
                'comment_added',
                'comments',
                $familyId,
                $actorUserId,
                $recipientUserId,
                $answerId,
                $commentId,
                '新しいコメント',
                sprintf('「%s」からコメントが届きました。', (string) $context['display_name']),
                [
                    'destination' => 'comments',
                    'event_type' => 'comment_added',
                    'answer_id' => (string) $answerId,
                    'comment_id' => (string) $commentId,
                ],
            );
        }
    }

    public function enqueueAnswerLiked(PDO $pdo, int $actorUserId, int $answerId): void
    {
        $statement = $pdo->prepare(
            'SELECT a.family_id, a.user_id AS answer_owner_id, actor.display_name
             FROM answers a
             JOIN family_members actor_membership
               ON actor_membership.family_id = a.family_id
              AND actor_membership.user_id = :actor
             JOIN users actor ON actor.id = actor_membership.user_id
             WHERE a.id = :answer'
        );
        $statement->execute(['answer' => $answerId, 'actor' => $actorUserId]);
        $context = $statement->fetch();
        if (!is_array($context)) {
            throw new RuntimeException('Like notification context is unavailable.');
        }

        $familyId = (int) $context['family_id'];
        foreach ($this->currentFamilyRecipients(
            $pdo,
            $familyId,
            $actorUserId,
            [(int) $context['answer_owner_id']],
        ) as $recipientUserId) {
            $this->enqueue(
                $pdo,
                'answer_liked',
                'likes',
                $familyId,
                $actorUserId,
                $recipientUserId,
                $answerId,
                null,
                '回答にいいねがつきました',
                sprintf('「%s」があなたの回答にいいねしました。', (string) $context['display_name']),
                [
                    'destination' => 'family_answer',
                    'event_type' => 'answer_liked',
                    'answer_id' => (string) $answerId,
                ],
            );
        }
    }

    /** @return list<int> */
    private function familyRecipients(PDO $pdo, int $familyId, int $actorUserId): array
    {
        $statement = $pdo->prepare(
            'SELECT user_id
             FROM family_members
             WHERE family_id = :family AND user_id <> :actor
             ORDER BY user_id ASC'
        );
        $statement->execute(['family' => $familyId, 'actor' => $actorUserId]);
        return array_values(array_map('intval', $statement->fetchAll(PDO::FETCH_COLUMN)));
    }

    /**
     * @param list<int> $candidateUserIds
     * @return list<int>
     */
    private function currentFamilyRecipients(
        PDO $pdo,
        int $familyId,
        int $actorUserId,
        array $candidateUserIds,
    ): array {
        $candidateUserIds = array_values(array_unique(array_filter(
            $candidateUserIds,
            static fn (int $userId): bool => $userId > 0 && $userId !== $actorUserId,
        )));
        if ($candidateUserIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($candidateUserIds), '?'));
        $statement = $pdo->prepare(
            'SELECT user_id
             FROM family_members
             WHERE family_id = ? AND user_id IN (' . $placeholders . ')
             ORDER BY user_id ASC'
        );
        $statement->execute([$familyId, ...$candidateUserIds]);
        return array_values(array_map('intval', $statement->fetchAll(PDO::FETCH_COLUMN)));
    }

    /** @param array<string, mixed> $data */
    private function enqueue(
        PDO $pdo,
        string $eventType,
        string $category,
        int $familyId,
        int $actorUserId,
        int $recipientUserId,
        int $answerId,
        ?int $commentId,
        string $title,
        string $body,
        array $data,
    ): void {
        $statement = $pdo->prepare(
            'INSERT INTO notification_event_outbox
                (event_type, category, family_id, actor_user_id, recipient_user_id,
                 answer_id, comment_id, title, body, data_json)
             VALUES
                (:event_type, :category, :family, :actor, :recipient,
                 :answer, :comment, :title, :body, :data)'
        );
        $statement->execute([
            'event_type' => $eventType,
            'category' => $category,
            'family' => $familyId,
            'actor' => $actorUserId,
            'recipient' => $recipientUserId,
            'answer' => $answerId,
            'comment' => $commentId,
            'title' => $title,
            'body' => $body,
            'data' => json_encode(
                $data,
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
            ),
        ]);
        $outboxId = (int) $pdo->lastInsertId();
        if ($outboxId < 1) {
            throw new RuntimeException('Event notification outbox id is unavailable.');
        }

        // Snapshot destinations while still inside the content transaction.
        // A later registration must not receive historical family content, and
        // each device needs its own lease/retry state so one accepted token
        // cannot hide a transient failure on another token.
        $tokenSql =
            'SELECT id FROM push_tokens WHERE user_id = :user ORDER BY id ASC';
        if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'sqlite') {
            $tokenSql .= ' FOR UPDATE';
        }
        $tokens = $pdo->prepare($tokenSql);
        $tokens->execute(['user' => $recipientUserId]);
        $tokenIds = array_values(array_map('intval', $tokens->fetchAll(PDO::FETCH_COLUMN)));
        $delivery = $pdo->prepare(
            'INSERT INTO notification_event_deliveries
                (outbox_id, push_token_id, token_was_present)
             VALUES (:outbox, :token, :token_was_present)'
        );
        if ($tokenIds === []) {
            $delivery->bindValue(':outbox', $outboxId, PDO::PARAM_INT);
            $delivery->bindValue(':token', null, PDO::PARAM_NULL);
            $delivery->bindValue(':token_was_present', 0, PDO::PARAM_INT);
            $delivery->execute();
            return;
        }
        foreach ($tokenIds as $tokenId) {
            $delivery->execute([
                'outbox' => $outboxId,
                'token' => $tokenId,
                'token_was_present' => 1,
            ]);
        }
    }
}
