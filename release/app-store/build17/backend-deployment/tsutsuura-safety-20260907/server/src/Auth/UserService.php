<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use PDO;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;

final class UserService
{
    public function __construct(private readonly Database $database)
    {
    }

    /** @return array<string, mixed> */
    public function findOrCreateByPhone(string $phone): array
    {
        return $this->database->transaction(function (PDO $pdo) use ($phone): array {
            $insert = $pdo->prepare($this->database->isSqlite()
                ? "INSERT INTO users (phone_e164, display_name) VALUES (:phone, 'ユーザー')
                   ON CONFLICT(phone_e164) DO NOTHING"
                : "INSERT INTO users (phone_e164, display_name) VALUES (:phone, 'ユーザー')
                   ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)"
            );
            $insert->execute(['phone' => $phone]);
            $userId = (int) $pdo->lastInsertId();
            if ($this->database->isSqlite() || $userId === 0) {
                $selectId = $pdo->prepare('SELECT id FROM users WHERE phone_e164 = :phone');
                $selectId->execute(['phone' => $phone]);
                $userId = (int) $selectId->fetchColumn();
            }
            $this->ensureFamilyWithConnection($pdo, $userId);
            return $this->loadByIdWithConnection($pdo, $userId);
        });
    }

    /**
     * Looks up an existing phone-authenticated account without provisioning a
     * new user or family. Returning-user authentication must use this method so
     * that entering an unknown number can never create an accidental account.
     *
     * @return array<string, mixed>|null
     */
    public function findByPhone(string $phone): ?array
    {
        $statement = $this->database->connection()->prepare(
            'SELECT id FROM users WHERE phone_e164 = :phone LIMIT 1'
        );
        $statement->execute(['phone' => $phone]);
        $userId = $statement->fetchColumn();
        if ($userId === false) {
            return null;
        }
        return $this->loadById((int) $userId);
    }

    /** @return array<string, mixed>|null */
    public function findByEmail(string $email): ?array
    {
        $statement = $this->database->connection()->prepare(
            'SELECT id FROM users WHERE email_address = :email AND email_verified_at IS NOT NULL LIMIT 1'
        );
        $statement->execute(['email' => $email]);
        $id = $statement->fetchColumn();
        return $id === false ? null : $this->loadById((int) $id);
    }

    /** @return array<string, mixed> */
    public function loadById(int $userId): array
    {
        return $this->loadByIdWithConnection($this->database->connection(), $userId);
    }

    /** @return array<string, mixed> */
    public function updateProfile(
        int $userId,
        mixed $displayName = null,
        mixed $avatarMark = null,
        bool $updateAvatarMark = false,
    ): array
    {
        if ($displayName !== null && !is_string($displayName)) {
            throw new ApiException(422, 'invalid_display_name', 'displayName must be a string.');
        }
        if ($displayName === null && !$updateAvatarMark) {
            throw new ApiException(422, 'invalid_profile', 'Specify displayName or avatarMark.');
        }
        $displayName = $displayName === null ? null : self::cleanDisplayName($displayName);
        if ($updateAvatarMark && $avatarMark !== null && (
            !is_string($avatarMark) || preg_match('/\A[01]{256}\z/D', $avatarMark) !== 1
        )) {
            throw new ApiException(422, 'invalid_avatar_mark', 'avatarMark must contain 256 binary pixels or be null.');
        }
        return $this->database->transaction(function (PDO $pdo) use (
            $userId, $displayName, $avatarMark, $updateAvatarMark,
        ): array {
            $fields = ['updated_at = CURRENT_TIMESTAMP'];
            $parameters = ['id' => $userId];
            if ($displayName !== null) {
                $fields[] = 'display_name = :name';
                $parameters['name'] = $displayName;
            }
            if ($updateAvatarMark) {
                $fields[] = 'avatar_mark = :mark';
                $parameters['mark'] = $avatarMark;
            }
            $statement = $pdo->prepare('UPDATE users SET ' . implode(', ', $fields) . ' WHERE id = :id');
            $statement->execute($parameters);
            if ($displayName !== null) {
                self::syncOwnerFamilyName($pdo, $userId, $displayName);
            }
            return $this->loadByIdWithConnection($pdo, $userId);
        });
    }

    public static function defaultFamilyName(string $displayName): string
    {
        return mb_substr($displayName, 0, 75, 'UTF-8') . 'さんの家族';
    }

    public static function syncOwnerFamilyName(PDO $pdo, int $userId, string $displayName): void
    {
        $statement = $pdo->prepare(
            "UPDATE families SET name = :name, updated_at = CURRENT_TIMESTAMP
             WHERE name_tracks_owner = 1 AND id IN (
                 SELECT family_id FROM family_members WHERE user_id = :user AND role = 'owner'
             )"
        );
        $statement->execute(['name' => self::defaultFamilyName($displayName), 'user' => $userId]);
    }

    /** @return array<string, mixed> */
    private function loadByIdWithConnection(PDO $pdo, int $userId): array
    {
        $statement = $pdo->prepare(
            'SELECT u.id, u.phone_e164, u.email_address, u.email_verified_at, u.display_name, u.avatar_url, u.avatar_mark, u.created_at,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM users u
             LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE u.id = :id'
        );
        $statement->execute(['id' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'user_not_found', 'User not found.');
        }
        return $row;
    }

    private function ensureFamilyWithConnection(PDO $pdo, int $userId): void
    {
        $check = $pdo->prepare('SELECT family_id FROM family_members WHERE user_id = :user');
        $check->execute(['user' => $userId]);
        if ($check->fetchColumn() !== false) {
            return;
        }

        for ($attempt = 0; $attempt < 3; $attempt++) {
            $inviteCode = strtoupper(substr(bin2hex(random_bytes(8)), 0, 12));
            try {
                $family = $pdo->prepare("INSERT INTO families (name, invite_code) VALUES ('わたしの家族', :code)");
                $family->execute(['code' => $inviteCode]);
                $familyId = (int) $pdo->lastInsertId();
                $member = $pdo->prepare(
                    "INSERT INTO family_members (family_id, user_id, role) VALUES (:family, :user, 'owner')"
                );
                $member->execute(['family' => $familyId, 'user' => $userId]);
                return;
            } catch (\PDOException $exception) {
                if ((string) $exception->getCode() !== '23000') {
                    throw $exception;
                }
            }
        }
        throw new \RuntimeException('Unable to provision a family.');
    }

    private static function cleanDisplayName(string $value): string
    {
        $value = trim(preg_replace('/\s+/u', ' ', $value) ?? '');
        if ($value === '' || mb_strlen($value, 'UTF-8') > 80) {
            throw new ApiException(422, 'invalid_display_name', 'displayName must be between 1 and 80 characters.');
        }
        return $value;
    }
}
