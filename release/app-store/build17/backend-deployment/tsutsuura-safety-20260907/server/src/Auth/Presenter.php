<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

final class Presenter
{
    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    public static function user(array $row, bool $includePrivateEmail = false): array
    {
        return [
            'id' => (string) $row['id'],
            'displayName' => (string) $row['display_name'],
            'avatarUrl' => $row['avatar_url'] === null ? null : (string) $row['avatar_url'],
            'avatarMark' => $row['avatar_mark'] ?? null,
            'hasPhone' => $row['phone_e164'] !== null,
            'hasEmail' => ($row['email_address'] ?? null) !== null && ($row['email_verified_at'] ?? null) !== null,
            ...($includePrivateEmail ? ['email' => $row['email_address'] ?? null] : []),
            'managed' => (bool) ($row['managed'] ?? false),
            'createdAt' => self::utcTimestamp((string) $row['created_at']),
        ];
    }

    public static function utcTimestamp(string $databaseValue): string
    {
        return str_replace(' ', 'T', $databaseValue) . 'Z';
    }
}
