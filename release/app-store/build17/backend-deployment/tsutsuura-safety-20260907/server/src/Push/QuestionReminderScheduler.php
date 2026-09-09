<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use DateTimeImmutable;
use DateTimeZone;
use Tsutsuura\Server\App\DailyQuestionSchedule;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;

final class QuestionReminderScheduler
{
    private const RESERVATION_LEASE_SECONDS = 60 * 60;
    private const FAILED_RETRY_SECONDS = 5 * 60;

    public function __construct(
        private readonly Database $database,
        private readonly Config $config,
        private readonly PushDeliveryService $delivery,
    ) {
    }

    /**
     * Selects published questions during the recipient's daytime and reserves
     * one dispatch per user/app-calendar day before calling the provider. Accepted rows
     * are idempotent; stale in-progress rows become retryable after the lease.
     * A wholly failed delivery can retry after five minutes. Partial successes
     * stay completed so already-notified devices never receive a duplicate.
     *
     * @return array{eligible: int, due: int, reserved: int, delivered: int, failed: int, deferred: int}
     */
    public function run(?DateTimeImmutable $now = null): array
    {
        $now ??= new DateTimeImmutable('now', new DateTimeZone('UTC'));
        $now = $now->setTimezone(new DateTimeZone('UTC'));
        $statement = $this->database->connection()->prepare(
            'SELECT tokens.user_id, fm.family_id,
                    COALESCE(np.question_reminders_enabled, 1) AS enabled,
                    COALESCE(np.timezone, :default_timezone) AS timezone,
                    np.mute_until, np.quiet_start, np.quiet_end
             FROM (SELECT DISTINCT user_id FROM push_tokens) tokens
             JOIN family_members fm ON fm.user_id = tokens.user_id
             LEFT JOIN notification_preferences np ON np.user_id = tokens.user_id
             ORDER BY tokens.user_id ASC'
        );
        $statement->execute([
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
        $schedule = new DailyQuestionSchedule($this->database, $this->config);
        $familyQuestions = [];
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
            $localTime = $localNow->format('H:i');
            // Minute-granularity 09:00–19:00 inclusive matches publication's
            // latest 19:00 release and tolerates the worker's seconds of jitter.
            if ($localTime < '09:00' || $localTime > '19:00' || $this->isQuiet($row, $localTime)) {
                continue;
            }
            $familyId = (int) $row['family_id'];
            $question = $familyQuestions[$familyId] ??= $schedule->forFamily($familyId, $now);
            if (!$question['is_available']) {
                continue;
            }
            $userId = (int) $row['user_id'];
            $localDate = (string) $question['date'];
            $answered = $this->database->connection()->prepare(
                'SELECT 1 FROM answers WHERE user_id = :user AND answer_date = :date LIMIT 1'
            );
            $answered->execute(['user' => $userId, 'date' => $localDate]);
            if ($answered->fetchColumn() !== false) {
                continue;
            }
            $summary['due']++;
            $reminderTime = (new DateTimeImmutable((string) $question['available_at'], new DateTimeZone('UTC')))
                ->setTimezone($timezone)->format('H:i');
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
                    'question_id' => (string) $question['id'],
                ],
                $now,
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
            $this->complete($userId, $localDate, $delivered, $failed, $now);
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
                 (user_id, local_date, reminder_time, created_at, updated_at)
                 VALUES (:user, :date, :time, :created_at, :updated_at)'
            : 'INSERT IGNORE INTO notification_reminder_dispatches
                 (user_id, local_date, reminder_time, created_at, updated_at)
                 VALUES (:user, :date, :time, :created_at, :updated_at)'
        );
        $statement->execute([
            'user' => $userId,
            'date' => $localDate,
            'time' => $reminderTime,
            'created_at' => $now->format('Y-m-d H:i:s'),
            'updated_at' => $now->format('Y-m-d H:i:s'),
        ]);
        if ($statement->rowCount() === 1) {
            return true;
        }

        // A process may stop after reserving but before completing delivery.
        // Reclaim an old in-progress reservation or a wholly failed dispatch.
        // The hour lease is much longer than APNs timeouts. A successful
        // device must not be notified twice when another device failed.
        $reclaim = $this->database->connection()->prepare(
            "UPDATE notification_reminder_dispatches
             SET reminder_time = :time, status = 'reserved', updated_at = :lease_now
             WHERE user_id = :user AND local_date = :date
               AND ((status = 'reserved' AND updated_at < :lease_cutoff)
                 OR (status = 'failed' AND delivered_count = 0 AND failed_count > 0
                     AND updated_at <= :retry_cutoff))"
        );
        $reclaim->execute([
            'time' => $reminderTime,
            'lease_now' => $now->format('Y-m-d H:i:s'),
            'user' => $userId,
            'date' => $localDate,
            'lease_cutoff' => $now
                ->modify('-' . self::RESERVATION_LEASE_SECONDS . ' seconds')
                ->format('Y-m-d H:i:s'),
            'retry_cutoff' => $now
                ->modify('-' . self::FAILED_RETRY_SECONDS . ' seconds')
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

    /** @param array<string, mixed> $preferences */
    private function isQuiet(array $preferences, string $localTime): bool
    {
        if ($preferences['quiet_start'] === null || $preferences['quiet_end'] === null) {
            return false;
        }
        $start = substr((string) $preferences['quiet_start'], 0, 5);
        $end = substr((string) $preferences['quiet_end'], 0, 5);
        return $start <= $end
            ? ($start === $end || ($localTime >= $start && $localTime < $end))
            : ($localTime >= $start || $localTime < $end);
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
        DateTimeImmutable $now,
    ): void {
        $statement = $this->database->connection()->prepare(
            "UPDATE notification_reminder_dispatches
             SET status = :status, delivered_count = :delivered,
                 failed_count = :failed, updated_at = :updated_at
             WHERE user_id = :user AND local_date = :date AND status = 'reserved'"
        );
        $statement->execute([
            'status' => $delivered > 0 ? 'delivered' : 'failed',
            'delivered' => $delivered,
            'failed' => $failed,
            'updated_at' => $now->format('Y-m-d H:i:s'),
            'user' => $userId,
            'date' => $localDate,
        ]);
    }

}
