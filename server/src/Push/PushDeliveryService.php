<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use DateTimeImmutable;
use DateTimeZone;
use Throwable;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Security\Crypto;

final class PushDeliveryService
{
    /** @var array<string, string> */
    private const PREFERENCE_COLUMNS = [
        'questionReminders' => 'question_reminders_enabled',
        'comments' => 'comments_enabled',
        'likes' => 'likes_enabled',
        'familyActivity' => 'family_activity_enabled',
    ];

    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly Config $config,
        private readonly PushProvider $provider,
    ) {
    }

    /** @param array<string, mixed> $data
     *  @return array{registered: int, delivered: int, failed: int, skipped: bool, reason: ?string}
     */
    public function deliverToUser(
        int $userId,
        string $category,
        mixed $titleValue,
        mixed $bodyValue,
        array $data = [],
    ): array {
        [$preferenceColumn, $payload] = $this->notification(
            $category,
            $titleValue,
            $bodyValue,
            $data,
        );
        return $this->deliverTokens(
            $this->tokens($userId, $preferenceColumn),
            $payload,
            'no_tokens',
        );
    }

    /** @param array<string, mixed> $data
     *  @return array{registered: int, delivered: int, failed: int, skipped: bool, reason: ?string}
     */
    public function deliverToToken(
        int $userId,
        int $pushTokenId,
        string $category,
        mixed $titleValue,
        mixed $bodyValue,
        array $data = [],
    ): array {
        if ($pushTokenId < 1) {
            throw new ApiException(422, 'invalid_push_token', 'Push token id is invalid.');
        }
        [$preferenceColumn, $payload] = $this->notification(
            $category,
            $titleValue,
            $bodyValue,
            $data,
        );
        return $this->deliverTokens(
            $this->tokens($userId, $preferenceColumn, $pushTokenId),
            $payload,
            'token_unavailable',
        );
    }

    /**
     * @param array<string, mixed> $data
     * @return array{0: string, 1: array<string, mixed>}
     */
    private function notification(
        string $category,
        mixed $titleValue,
        mixed $bodyValue,
        array $data,
    ): array {
        $preferenceColumn = self::PREFERENCE_COLUMNS[$category] ?? null;
        if ($preferenceColumn === null) {
            throw new ApiException(422, 'invalid_notification_category', 'Notification category is invalid.');
        }
        $title = self::text($titleValue, 120, 'title');
        $body = self::text($bodyValue, 500, 'body');
        if ($data !== [] && array_is_list($data)) {
            throw new ApiException(422, 'invalid_notification_data', 'Notification data must be an object.');
        }
        foreach (array_keys($data) as $key) {
            if (!is_string($key) || in_array($key, ['aps', 'category'], true)) {
                throw new ApiException(
                    422,
                    'invalid_notification_data',
                    'Notification data cannot override reserved APNs keys.',
                );
            }
        }
        json_encode($data, JSON_THROW_ON_ERROR);

        return [$preferenceColumn, array_merge([
            'aps' => [
                'alert' => ['title' => $title, 'body' => $body],
                'sound' => 'default',
            ],
            'category' => $category,
        ], $data)];
    }

    /** @return list<array<string, mixed>> */
    private function tokens(int $userId, string $preferenceColumn, ?int $pushTokenId = null): array
    {
        $tokenFilter = $pushTokenId === null ? '' : ' AND pt.id = :token';
        $statement = $this->database->connection()->prepare(
            'SELECT pt.id, pt.token_encrypted, pt.environment,
                    COALESCE(np.' . $preferenceColumn . ', 1) AS preference_enabled,
                    np.quiet_start, np.quiet_end, np.timezone, np.mute_until
             FROM push_tokens pt
             LEFT JOIN notification_preferences np ON np.user_id = pt.user_id
             WHERE pt.user_id = :user' . $tokenFilter . ' ORDER BY pt.id ASC'
        );
        $values = ['user' => $userId];
        if ($pushTokenId !== null) {
            $values['token'] = $pushTokenId;
        }
        $statement->execute($values);
        return $statement->fetchAll();
    }

    /**
     * @param list<array<string, mixed>> $tokens
     * @param array<string, mixed> $payload
     * @return array{registered: int, delivered: int, failed: int, skipped: bool, reason: ?string}
     */
    private function deliverTokens(array $tokens, array $payload, string $missingReason): array
    {
        if ($tokens === []) {
            return [
                'registered' => 0,
                'delivered' => 0,
                'failed' => 0,
                'skipped' => true,
                'reason' => $missingReason,
            ];
        }
        $first = $tokens[0];
        if (!(bool) $first['preference_enabled']) {
            return [
                'registered' => count($tokens),
                'delivered' => 0,
                'failed' => 0,
                'skipped' => true,
                'reason' => 'preference_disabled',
            ];
        }
        if ($this->isMuted($first)) {
            return [
                'registered' => count($tokens),
                'delivered' => 0,
                'failed' => 0,
                'skipped' => true,
                'reason' => 'muted',
            ];
        }
        if ($this->isQuietTime($first)) {
            return [
                'registered' => count($tokens),
                'delivered' => 0,
                'failed' => 0,
                'skipped' => true,
                'reason' => 'quiet_hours',
            ];
        }

        $delivered = 0;
        $failed = 0;
        foreach ($tokens as $token) {
            try {
                $result = $this->provider->send(
                    $this->crypto->decrypt((string) $token['token_encrypted']),
                    (string) $token['environment'],
                    $payload,
                );
                if ($result['accepted']) {
                    $delivered++;
                } else {
                    $failed++;
                }
                if ($result['invalidToken']) {
                    $delete = $this->database->connection()->prepare(
                        'DELETE FROM push_tokens WHERE id = :id'
                    );
                    $delete->execute(['id' => $token['id']]);
                }
            } catch (Throwable $exception) {
                $failed++;
                error_log('Push delivery failed: ' . $exception->getMessage());
            }
        }
        return [
            'registered' => count($tokens),
            'delivered' => $delivered,
            'failed' => $failed,
            'skipped' => false,
            'reason' => null,
        ];
    }

    /** @param array<string, mixed> $preferences */
    private function isMuted(array $preferences): bool
    {
        if ($preferences['mute_until'] === null) {
            return false;
        }
        try {
            $muteUntil = new DateTimeImmutable(
                (string) $preferences['mute_until'],
                new DateTimeZone('UTC'),
            );
        } catch (\Exception) {
            return true;
        }
        return $muteUntil > new DateTimeImmutable('now', new DateTimeZone('UTC'));
    }

    /** @param array<string, mixed> $preferences */
    private function isQuietTime(array $preferences): bool
    {
        if ($preferences['quiet_start'] === null || $preferences['quiet_end'] === null) {
            return false;
        }
        $timezoneName = $preferences['timezone'] === null
            ? $this->config->timezone->getName()
            : (string) $preferences['timezone'];
        try {
            $timezone = new DateTimeZone($timezoneName);
        } catch (\Exception) {
            $timezone = $this->config->timezone;
        }
        $now = (new DateTimeImmutable('now', $timezone))->format('H:i');
        $start = substr((string) $preferences['quiet_start'], 0, 5);
        $end = substr((string) $preferences['quiet_end'], 0, 5);
        if ($start === $end) {
            return true;
        }
        if ($start < $end) {
            return $now >= $start && $now < $end;
        }
        return $now >= $start || $now < $end;
    }

    private static function text(mixed $value, int $maximum, string $field): string
    {
        if (!is_string($value)) {
            throw new ApiException(422, 'invalid_notification', $field . ' must be a string.');
        }
        $value = trim(str_replace("\0", '', $value));
        if ($value === '' || mb_strlen($value, 'UTF-8') > $maximum) {
            throw new ApiException(
                422,
                'invalid_notification',
                sprintf('%s must be between 1 and %d characters.', $field, $maximum),
            );
        }
        return $value;
    }
}
