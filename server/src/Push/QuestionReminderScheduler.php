<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use DateTimeImmutable;
use DateTimeZone;
use PDO;
use RuntimeException;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;

final class QuestionReminderScheduler
{
    private const RESERVATION_LEASE_SECONDS = 60 * 60;

    public function __construct(
        private readonly Database $database,
        private readonly Config $config,
        private readonly PushDeliveryService $delivery,
    ) {
    }

    /**
     * Selects reminders whose configured local time has arrived and reserves one
     * dispatch per user/local day before calling the provider. Completed rows
     * are idempotent; stale in-progress rows become retryable after the lease.
     *
     * @return array{eligible: int, due: int, reserved: int, delivered: int, failed: int, deferred: int}
     */
    public function run(?DateTimeImmutable $now = null): array
    {
        $now ??= new DateTimeImmutable('now', new DateTimeZone('UTC'));
        $now = $now->setTimezone(new DateTimeZone('UTC'));
        $statement = $this->database->connection()->prepare(
            'SELECT tokens.user_id,
                    COALESCE(np.question_reminders_enabled, 1) AS enabled,
                    COALESCE(np.question_reminder_time, :default_time) AS reminder_time,
                    COALESCE(np.timezone, :default_timezone) AS timezone,
                    np.mute_until
             FROM (SELECT DISTINCT user_id FROM push_tokens) tokens
             LEFT JOIN notification_preferences np ON np.user_id = tokens.user_id
             ORDER BY tokens.user_id ASC'
        );
        $statement->execute([
            'default_time' => '09:00',
            'default_timezone' => $this->config->timezone->getName(),
        ]);
        $rows = $statement->fetchAll();
        $summary = [
            'eligible' => 0,
            'due' => 0,
            'reserved' => 0,
            'delivered' => 0,
            'failed' => 0,
            'deferred' => 0,
        ];
        $questionId = $this->questionId($now);
        foreach ($rows as $row) {
            if (!(bool) $row['enabled']) {
                continue;
            }
            if ($this->isMuted($row['mute_until'], $now)) {
                continue;
            }
            $summary['eligible']++;
            try {
                $timezone = new DateTimeZone((string) $row['timezone']);
            } catch (\Exception) {
                $timezone = $this->config->timezone;
            }
            $localNow = $now->setTimezone($timezone);
            $reminderTime = substr((string) $row['reminder_time'], 0, 5);
            if ($localNow->format('H:i') < $reminderTime) {
                continue;
            }
            $summary['due']++;
            $userId = (int) $row['user_id'];
            $localDate = $localNow->format('Y-m-d');
            if (!$this->reserve($userId, $localDate, $reminderTime, $now)) {
                continue;
            }
            $summary['reserved']++;
            $result = $this->delivery->deliverToUser(
                $userId,
                'questionReminders',
                '今日の質問が届きました',
                '今日のつつうらを残しましょう。',
                [
                    'destination' => 'today_question',
                    'question_id' => $questionId,
                ],
            );
            if ($result['skipped'] && in_array(
                $result['reason'],
                ['quiet_hours', 'muted', 'no_tokens'],
                true,
            )) {
                $this->release($userId, $localDate);
                $summary['deferred']++;
                continue;
            }
            $delivered = (int) $result['delivered'];
            $failed = (int) $result['failed'];
            $this->complete($userId, $localDate, $delivered, $failed);
            $summary['delivered'] += $delivered;
            $summary['failed'] += $failed;
        }
        return $summary;
    }

    private function reserve(
        int $userId,
        string $localDate,
        string $reminderTime,
        DateTimeImmutable $now,
    ): bool
    {
        $statement = $this->database->connection()->prepare($this->database->isSqlite()
            ? 'INSERT OR IGNORE INTO notification_reminder_dispatches
                 (user_id, local_date, reminder_time) VALUES (:user, :date, :time)'
            : 'INSERT IGNORE INTO notification_reminder_dispatches
                 (user_id, local_date, reminder_time) VALUES (:user, :date, :time)'
        );
        $statement->execute(['user' => $userId, 'date' => $localDate, 'time' => $reminderTime]);
        if ($statement->rowCount() === 1) {
            return true;
        }

        // A process may stop after reserving but before completing delivery.
        // Reclaim only an old in-progress reservation; completed rows remain
        // immutable, and the hour lease is much longer than APNs timeouts for
        // the handful of devices normally registered to one account.
        $reclaim = $this->database->connection()->prepare(
            "UPDATE notification_reminder_dispatches
             SET reminder_time = :time, updated_at = :lease_now
             WHERE user_id = :user AND local_date = :date
               AND status = 'reserved' AND updated_at < :lease_cutoff"
        );
        $reclaim->execute([
            'time' => $reminderTime,
            'lease_now' => $now->format('Y-m-d H:i:s'),
            'user' => $userId,
            'date' => $localDate,
            'lease_cutoff' => $now
                ->modify('-' . self::RESERVATION_LEASE_SECONDS . ' seconds')
                ->format('Y-m-d H:i:s'),
        ]);
        return $reclaim->rowCount() === 1;
    }

    private function isMuted(mixed $value, DateTimeImmutable $now): bool
    {
        if ($value === null) {
            return false;
        }
        try {
            $muteUntil = new DateTimeImmutable((string) $value, new DateTimeZone('UTC'));
        } catch (\Exception) {
            return true;
        }
        return $muteUntil > $now;
    }

    private function release(int $userId, string $localDate): void
    {
        $statement = $this->database->connection()->prepare(
            "DELETE FROM notification_reminder_dispatches
             WHERE user_id = :user AND local_date = :date AND status = 'reserved'"
        );
        $statement->execute(['user' => $userId, 'date' => $localDate]);
    }

    private function complete(
        int $userId,
        string $localDate,
        int $delivered,
        int $failed,
    ): void {
        $statement = $this->database->connection()->prepare(
            "UPDATE notification_reminder_dispatches
             SET status = :status, delivered_count = :delivered,
                 failed_count = :failed, updated_at = CURRENT_TIMESTAMP
             WHERE user_id = :user AND local_date = :date AND status = 'reserved'"
        );
        $statement->execute([
            'status' => $delivered > 0 ? 'delivered' : 'failed',
            'delivered' => $delivered,
            'failed' => $failed,
            'user' => $userId,
            'date' => $localDate,
        ]);
    }

    private function questionId(DateTimeImmutable $now): string
    {
        $date = $now->setTimezone($this->config->timezone)->format('Y-m-d');
        $specific = $this->database->connection()->prepare(
            'SELECT id FROM questions WHERE available_on = :date AND is_active = 1 LIMIT 1'
        );
        $specific->execute(['date' => $date]);
        $id = $specific->fetchColumn();
        if ($id !== false) {
            return (string) $id;
        }
        $ids = $this->database->connection()->query(
            'SELECT id FROM questions WHERE available_on IS NULL AND is_active = 1 ORDER BY id ASC'
        )->fetchAll(PDO::FETCH_COLUMN);
        if ($ids === []) {
            throw new RuntimeException('No active question is available for reminder delivery.');
        }
        $offset = (int) (sprintf('%u', crc32($date)) % count($ids));
        return (string) $ids[$offset];
    }
}
