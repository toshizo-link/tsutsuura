<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use Tsutsuura\Server\App\ContentSafety;

use DateTimeImmutable;
use DateTimeZone;
use JsonException;
use PDO;
use RuntimeException;
use Throwable;
use Tsutsuura\Server\Database;

final class EventNotificationWorker
{
    private const MAX_ATTEMPTS = 5;
    private const LEASE_SECONDS = 30 * 60;
    private const MAX_BATCH_SIZE = 1000;

    public function __construct(
        private readonly Database $database,
        private readonly PushDeliveryService $delivery,
    ) {
    }

    /**
     * Counts below are per destination-device attempt, not per recipient
     * outbox row. This distinction makes partial multi-device outcomes visible.
     *
     * @return array{
     *   claimed: int,
     *   delivered: int,
     *   skipped: int,
     *   retried: int,
     *   failed: int,
     *   providerDelivered: int,
     *   providerFailed: int
     * }
     */
    public function run(
        int $limit = 100,
        ?DateTimeImmutable $now = null,
    ): array {
        if ($limit < 1 || $limit > self::MAX_BATCH_SIZE) {
            throw new RuntimeException(sprintf(
                'Event notification batch size must be between 1 and %d.',
                self::MAX_BATCH_SIZE,
            ));
        }
        $fixedNow = $now?->setTimezone(new DateTimeZone('UTC'));
        $summary = [
            'claimed' => 0,
            'delivered' => 0,
            'skipped' => 0,
            'retried' => 0,
            'failed' => 0,
            'providerDelivered' => 0,
            'providerFailed' => 0,
        ];

        for ($index = 0; $index < $limit; $index++) {
            $iterationNow = $fixedNow
                ?? new DateTimeImmutable('now', new DateTimeZone('UTC'));
            $job = $this->claim($iterationNow);
            if ($job === null) {
                break;
            }
            $summary['claimed']++;
            $this->process($job, $iterationNow, $summary);
        }
        return $summary;
    }

    /** @param array<string, mixed> $job
     *  @param array<string, int> $summary
     */
    private function process(array $job, DateTimeImmutable $now, array &$summary): void
    {
        try {
            if (!$this->jobIsCurrent($job)) {
                $this->finish($job, 'skipped', $now, 0, 0, 'recipient_left_family');
                $summary['skipped']++;
                return;
            }
            $data = json_decode((string) $job['data_json'], true, 32, JSON_THROW_ON_ERROR);
            if (!is_array($data) || array_is_list($data)) {
                throw new JsonException('Event notification data is not an object.');
            }
            if (!ContentSafety::allowsNotification($this->database->connection(),
                (int) $job['recipient_user_id'], $data, (int) $job['actor_user_id'])) {
                $this->finish($job, 'skipped', $now, 0, 0, 'content_hidden');
                $summary['skipped']++;
                return;
            }
            if ($job['push_token_id'] === null) {
                $reason = (bool) $job['token_was_present']
                    ? 'token_unavailable'
                    : 'no_tokens';
                $this->finish($job, 'skipped', $now, 0, 0, $reason);
                $summary['skipped']++;
                return;
            }

            $result = $this->delivery->deliverToToken(
                (int) $job['recipient_user_id'],
                (int) $job['push_token_id'],
                (string) $job['category'],
                (string) $job['title'],
                (string) $job['body'],
                $data,
            );
            $providerDelivered = (int) $result['delivered'];
            $providerFailed = (int) $result['failed'];
            $summary['providerDelivered'] += $providerDelivered;
            $summary['providerFailed'] += $providerFailed;

            if ($providerDelivered > 0) {
                $this->finish(
                    $job,
                    'delivered',
                    $now,
                    $providerDelivered,
                    $providerFailed,
                    null,
                );
                $summary['delivered']++;
                return;
            }
            if ($result['skipped']) {
                $this->finish(
                    $job,
                    'skipped',
                    $now,
                    0,
                    $providerFailed,
                    (string) ($result['reason'] ?? 'delivery_skipped'),
                );
                $summary['skipped']++;
                return;
            }

            $this->retryOrFail(
                $job,
                $now,
                $providerDelivered,
                $providerFailed,
                'Push provider did not accept delivery.',
                $summary,
            );
        } catch (Throwable $exception) {
            $this->retryOrFail($job, $now, 0, 0, $exception->getMessage(), $summary);
        }
    }

    /** @return array<string, mixed>|null */
    private function claim(DateTimeImmutable $now): ?array
    {
        return $this->database->transaction(function (PDO $pdo) use ($now): ?array {
            $sql =
                "SELECT delivery.id AS delivery_id, delivery.outbox_id,
                        delivery.push_token_id, delivery.token_was_present,
                        delivery.status AS delivery_status, delivery.attempts,
                        outbox.event_type, outbox.category, outbox.family_id,
                        outbox.actor_user_id, outbox.recipient_user_id,
                        outbox.answer_id, outbox.comment_id, outbox.title,
                        outbox.body, outbox.data_json
                 FROM notification_event_deliveries delivery
                 JOIN notification_event_outbox outbox ON outbox.id = delivery.outbox_id
                 WHERE ((delivery.status IN ('pending', 'retry')
                          AND delivery.available_at <= :available_now)
                    OR (delivery.status = 'processing'
                          AND delivery.claimed_at < :lease_cutoff))
                 ORDER BY delivery.id ASC
                 LIMIT 1";
            if (!$this->database->isSqlite()) {
                $sql .= ' FOR UPDATE';
            }
            $statement = $pdo->prepare($sql);
            $statement->execute([
                'available_now' => $now->format('Y-m-d H:i:s'),
                'lease_cutoff' => $now
                    ->modify('-' . self::LEASE_SECONDS . ' seconds')
                    ->format('Y-m-d H:i:s'),
            ]);
            $job = $statement->fetch();
            if (!is_array($job)) {
                return null;
            }

            $claimToken = bin2hex(random_bytes(16));
            $claim = $pdo->prepare(
                "UPDATE notification_event_deliveries
                 SET status = 'processing', attempts = attempts + 1,
                     claimed_at = :claimed_at, claim_token = :claim_token,
                     completed_at = NULL, last_error = NULL,
                     updated_at = :updated_at
                 WHERE id = :id"
            );
            $claim->execute([
                'claimed_at' => $now->format('Y-m-d H:i:s'),
                'claim_token' => $claimToken,
                'updated_at' => $now->format('Y-m-d H:i:s'),
                'id' => $job['delivery_id'],
            ]);
            if ($claim->rowCount() !== 1) {
                return null;
            }
            $job['attempts'] = (int) $job['attempts'] + 1;
            $job['claim_token'] = $claimToken;

            // Parent columns remain a convenient recipient-level aggregate;
            // leases and claims are authoritative on the child delivery row.
            $parent = $pdo->prepare(
                "UPDATE notification_event_outbox
                 SET status = 'processing',
                     attempts = CASE WHEN attempts < :attempts THEN :attempt_value ELSE attempts END,
                     claimed_at = :claimed_at, claim_token = NULL,
                     completed_at = NULL, last_error = NULL,
                     updated_at = :updated_at
                 WHERE id = :id"
            );
            $parent->execute([
                'attempts' => $job['attempts'],
                'attempt_value' => $job['attempts'],
                'claimed_at' => $now->format('Y-m-d H:i:s'),
                'updated_at' => $now->format('Y-m-d H:i:s'),
                'id' => $job['outbox_id'],
            ]);
            return $job;
        });
    }

    /** @param array<string, mixed> $job */
    private function jobIsCurrent(array $job): bool
    {
        $statement = $this->database->connection()->prepare(
            "SELECT 1
             FROM notification_event_deliveries delivery
             JOIN notification_event_outbox outbox ON outbox.id = delivery.outbox_id
             JOIN family_members membership
               ON membership.family_id = outbox.family_id
              AND membership.user_id = outbox.recipient_user_id
             WHERE delivery.id = :delivery AND delivery.outbox_id = :outbox
               AND delivery.status = 'processing'
               AND delivery.claim_token = :claim_token"
        );
        $statement->execute([
            'delivery' => $job['delivery_id'],
            'outbox' => $job['outbox_id'],
            'claim_token' => $job['claim_token'],
        ]);
        return $statement->fetchColumn() !== false;
    }

    /** @param array<string, mixed> $job
     *  @param array<string, int> $summary
     */
    private function retryOrFail(
        array $job,
        DateTimeImmutable $now,
        int $providerDelivered,
        int $providerFailed,
        string $error,
        array &$summary,
    ): void {
        if ((int) $job['attempts'] >= self::MAX_ATTEMPTS) {
            $this->finish(
                $job,
                'failed',
                $now,
                $providerDelivered,
                $providerFailed,
                $error,
            );
            $summary['failed']++;
            return;
        }

        $backoffSeconds = min(
            60 * 60,
            30 * (2 ** max(0, (int) $job['attempts'] - 1)),
        );
        $this->finish(
            $job,
            'retry',
            $now,
            $providerDelivered,
            $providerFailed,
            $error,
            $now->modify('+' . $backoffSeconds . ' seconds'),
        );
        $summary['retried']++;
    }

    /** @param array<string, mixed> $job */
    private function finish(
        array $job,
        string $status,
        DateTimeImmutable $now,
        int $providerDelivered,
        int $providerFailed,
        ?string $lastError,
        ?DateTimeImmutable $availableAt = null,
    ): void {
        $this->database->transaction(function (PDO $pdo) use (
            $job,
            $status,
            $now,
            $providerDelivered,
            $providerFailed,
            $lastError,
            $availableAt,
        ): void {
            // Serialize aggregate refreshes for sibling device deliveries.
            $parentSql = 'SELECT id FROM notification_event_outbox WHERE id = :id';
            if (!$this->database->isSqlite()) {
                $parentSql .= ' FOR UPDATE';
            }
            $parent = $pdo->prepare($parentSql);
            $parent->execute(['id' => $job['outbox_id']]);
            if ($parent->fetchColumn() === false) {
                return;
            }

            $terminal = in_array($status, ['delivered', 'skipped', 'failed'], true);
            $statement = $pdo->prepare(
                'UPDATE notification_event_deliveries
                 SET status = :status, available_at = :available_at,
                     claimed_at = NULL, claim_token = NULL,
                     completed_at = :completed_at,
                     provider_delivered = :provider_delivered,
                     provider_failed = provider_failed + :provider_failed,
                     last_error = :last_error, updated_at = :updated_at
                 WHERE id = :id AND status = :processing
                   AND claim_token = :claim_token'
            );
            $statement->execute([
                'status' => $status,
                'available_at' => ($availableAt ?? $now)->format('Y-m-d H:i:s'),
                'completed_at' => $terminal ? $now->format('Y-m-d H:i:s') : null,
                'provider_delivered' => $providerDelivered > 0 ? 1 : 0,
                'provider_failed' => $providerFailed,
                'last_error' => $lastError === null ? null : $this->safeError($lastError),
                'updated_at' => $now->format('Y-m-d H:i:s'),
                'id' => $job['delivery_id'],
                'processing' => 'processing',
                'claim_token' => $job['claim_token'],
            ]);
            if ($statement->rowCount() !== 1) {
                return;
            }
            $this->refreshParent($pdo, (int) $job['outbox_id'], $now);
        });
    }

    private function refreshParent(PDO $pdo, int $outboxId, DateTimeImmutable $now): void
    {
        $aggregate = $pdo->prepare(
            "SELECT COUNT(*) AS total,
                    SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) AS processing_count,
                    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
                    SUM(CASE WHEN status = 'retry' THEN 1 ELSE 0 END) AS retry_count,
                    SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered_count,
                    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
                    SUM(provider_delivered) AS provider_delivered,
                    SUM(provider_failed) AS provider_failed,
                    MAX(attempts) AS attempts,
                    MIN(CASE WHEN status IN ('pending', 'retry') THEN available_at END)
                        AS next_available_at,
                    MAX(CASE WHEN status = 'processing' THEN claimed_at END) AS claimed_at,
                    MAX(CASE WHEN last_error IS NOT NULL THEN last_error END) AS last_error
             FROM notification_event_deliveries WHERE outbox_id = :outbox"
        );
        $aggregate->execute(['outbox' => $outboxId]);
        $row = $aggregate->fetch();
        if (!is_array($row) || (int) $row['total'] === 0) {
            return;
        }

        $terminal = false;
        if ((int) $row['processing_count'] > 0) {
            $status = 'processing';
        } elseif ((int) $row['pending_count'] > 0) {
            $status = 'pending';
        } elseif ((int) $row['retry_count'] > 0) {
            $status = 'retry';
        } elseif ((int) $row['failed_count'] > 0) {
            $status = 'failed';
            $terminal = true;
        } elseif ((int) $row['delivered_count'] > 0) {
            $status = 'delivered';
            $terminal = true;
        } else {
            $status = 'skipped';
            $terminal = true;
        }

        $update = $pdo->prepare(
            'UPDATE notification_event_outbox
             SET status = :status, attempts = :attempts,
                 available_at = :available_at, claimed_at = :claimed_at,
                 claim_token = NULL, completed_at = :completed_at,
                 provider_delivered = :provider_delivered,
                 provider_failed = :provider_failed,
                 last_error = :last_error, updated_at = :updated_at
             WHERE id = :id'
        );
        $update->execute([
            'status' => $status,
            'attempts' => (int) $row['attempts'],
            'available_at' => $row['next_available_at'] === null
                ? $now->format('Y-m-d H:i:s')
                : (string) $row['next_available_at'],
            'claimed_at' => $status === 'processing' ? $row['claimed_at'] : null,
            'completed_at' => $terminal ? $now->format('Y-m-d H:i:s') : null,
            'provider_delivered' => (int) $row['provider_delivered'],
            'provider_failed' => (int) $row['provider_failed'],
            'last_error' => $row['last_error'],
            'updated_at' => $now->format('Y-m-d H:i:s'),
            'id' => $outboxId,
        ]);
    }

    private function safeError(string $value): string
    {
        $value = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $value) ?? 'Push delivery failed.';
        $value = trim($value);
        return mb_substr($value === '' ? 'Push delivery failed.' : $value, 0, 500);
    }
}
