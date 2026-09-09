<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use DateTimeImmutable;
use DateTimeZone;
use PDO;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;

/** One durable question and release time per family and app-calendar day. */
final class DailyQuestionSchedule
{
    public function __construct(
        private readonly Database $database,
        private readonly Config $config,
    ) {
    }

    /** @return array<string, mixed> */
    public function forFamily(int $familyId, ?DateTimeImmutable $now = null): array
    {
        $now ??= new DateTimeImmutable('now', new DateTimeZone('UTC'));
        $date = $now->setTimezone($this->config->timezone)->format('Y-m-d');
        $row = $this->existing($familyId, $date);
        if ($row === null) {
            // During rollout, retain the question a family already answered
            // today and keep it published. Historical answers are untouched.
            $answered = $this->database->connection()->prepare(
                'SELECT question_id FROM answers
                 WHERE family_id = :family AND answer_date = :date ORDER BY id ASC LIMIT 1'
            );
            $answered->execute(['family' => $familyId, 'date' => $date]);
            $answeredQuestionId = $answered->fetchColumn();
            if ($answeredQuestionId !== false) {
                $question = ['id' => $answeredQuestionId];
                $availableAt = new DateTimeImmutable($date . ' 00:00:00', $this->config->timezone);
            } else {
                $question = $this->selectQuestion($date);
                $availableAt = $this->releaseTime($familyId, $date, $question);
            }

            // A simultaneous home refresh and reminder worker converge on
            // the same row. Future catalog changes never move today's choice.
            $insert = $this->database->connection()->prepare($this->database->isSqlite()
                ? 'INSERT INTO daily_question_publications
                     (family_id, local_date, question_id, available_at)
                   VALUES (:family, :date, :question, :available)
                   ON CONFLICT(family_id, local_date) DO NOTHING'
                : 'INSERT INTO daily_question_publications
                     (family_id, local_date, question_id, available_at)
                   VALUES (:family, :date, :question, :available)
                   ON DUPLICATE KEY UPDATE family_id = VALUES(family_id)'
            );
            $insert->execute([
                'family' => $familyId,
                'date' => $date,
                'question' => $question['id'],
                'available' => $availableAt->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s'),
            ]);
            $row = $this->existing($familyId, $date);
        }
        if ($row === null) {
            throw new ApiException(503, 'question_unavailable', '今日の質問を準備しています。少し後でもう一度お試しください。');
        }
        $availableAt = new DateTimeImmutable((string) $row['available_at'], new DateTimeZone('UTC'));
        $row['family_id'] = $familyId;
        $row['date'] = $date;
        $row['is_available'] = $now >= $availableAt;
        return $row;
    }

    /** @return array<string, mixed>|null */
    private function existing(int $familyId, string $date): ?array
    {
        $statement = $this->database->connection()->prepare(
            'SELECT q.id, q.prompt, p.available_at
             FROM daily_question_publications p JOIN questions q ON q.id = p.question_id
             WHERE p.family_id = :family AND p.local_date = :date'
        );
        $statement->execute(['family' => $familyId, 'date' => $date]);
        $row = $statement->fetch();
        return is_array($row) ? $row : null;
    }

    /** @return array<string, mixed> */
    private function selectQuestion(string $date): array
    {
        $specific = $this->database->connection()->prepare(
            'SELECT id, prompt, publish_start_minute, publish_end_minute
             FROM questions WHERE available_on = :date AND is_active = 1 LIMIT 1'
        );
        $specific->execute(['date' => $date]);
        $row = $specific->fetch();
        if (is_array($row)) {
            return $row;
        }
        $count = (int) $this->database->connection()->query(
            'SELECT COUNT(*) FROM questions WHERE available_on IS NULL AND is_active = 1'
        )->fetchColumn();
        if ($count === 0) {
            throw new ApiException(503, 'question_unavailable', '今日の質問を準備しています。少し後でもう一度お試しください。');
        }
        // A full rotation avoids the frequent repeats of a daily hash modulo
        // the catalog size. Calendar arithmetic is independent of DST.
        $day = (int) floor((new DateTimeImmutable($date, new DateTimeZone('UTC')))->getTimestamp() / 86400);
        $offset = (($day % $count) + $count) % $count;
        $statement = $this->database->connection()->prepare(
            'SELECT id, prompt, publish_start_minute, publish_end_minute
             FROM questions WHERE available_on IS NULL AND is_active = 1
             ORDER BY id ASC LIMIT 1 OFFSET :offset'
        );
        $statement->bindValue(':offset', $offset, PDO::PARAM_INT);
        $statement->execute();
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(503, 'question_unavailable', '今日の質問を準備しています。少し後でもう一度お試しください。');
        }
        return $row;
    }

    /** @param array<string, mixed> $question */
    private function releaseTime(int $familyId, string $date, array $question): DateTimeImmutable
    {
        // Catalog entries may narrow the safe window, never extend it into
        // early mornings or nights, even if an operator enters invalid data.
        $start = max(540, min(1140, (int) $question['publish_start_minute']));
        $end = max($start, min(1140, (int) $question['publish_end_minute']));
        $hash = hash('sha256', $familyId . ':' . $date . ':' . $question['id']);
        $minute = $start + ((int) hexdec(substr($hash, 0, 8)) % ($end - $start + 1));
        return (new DateTimeImmutable($date, $this->config->timezone))
            ->setTime(intdiv($minute, 60), $minute % 60);
    }
}
