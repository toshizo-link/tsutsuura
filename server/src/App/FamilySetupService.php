<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use DateTimeImmutable;
use PDO;
use PDOException;
use RuntimeException;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;

final class FamilySetupService
{
    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly RateLimiter $rateLimiter,
        private readonly SessionService $sessions,
        private readonly Config $config,
    ) {
    }

    /** @return array<string, mixed> */
    public function createOrganizerFamily(
        mixed $organizerNameValue,
        mixed $familyNameValue,
        string $clientIp,
        mixed $idempotencyKeyValue = null,
    ): array {
        $organizerName = self::name($organizerNameValue, 'organizer_name', 'organizerName');
        $familyName = self::name($familyNameValue, 'family_name', 'familyName');
        $idempotencyKey = $this->optionalIdempotencyKey($idempotencyKeyValue);
        $operation = 'organizer-family-create';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->setupMutationKeyHash($operation, $idempotencyKey);
        $requestFingerprint = $keyHash === null
            ? null
            : $this->setupRequestFingerprint([$organizerName, $familyName]);

        if ($keyHash !== null && $requestFingerprint !== null) {
            $replay = $this->completedSetupMutationReplay(
                $keyHash,
                $operation,
                null,
                $requestFingerprint,
            );
            if ($replay !== null) {
                return $replay;
            }
        }

        $this->rateLimiter->consume(
            'setup-family-ip:' . $clientIp,
            $this->config->setupFamilyIpRequestsPerHour,
            3600,
        );

        return $this->database->transaction(function (PDO $pdo) use (
            $organizerName,
            $familyName,
            $keyHash,
            $operation,
            $requestFingerprint,
        ): array {
            if ($keyHash !== null && $requestFingerprint !== null) {
                $replay = $this->reserveSetupMutationReceipt(
                    $pdo,
                    $keyHash,
                    $operation,
                    null,
                    $requestFingerprint,
                    (new DateTimeImmutable('now'))->modify('+30 days'),
                );
                if ($replay !== null) {
                    return $replay;
                }
            }

            $user = $pdo->prepare('INSERT INTO users (display_name) VALUES (:name)');
            $user->execute(['name' => $organizerName]);
            $userId = (int) $pdo->lastInsertId();

            $familyId = $this->insertFamily($pdo, $familyName);
            $member = $pdo->prepare(
                "INSERT INTO family_members (family_id, user_id, role)
                 VALUES (:family, :user, 'owner')"
            );
            $member->execute(['family' => $familyId, 'user' => $userId]);

            $result = $this->issueAuthSession($this->userById($pdo, $userId));
            if ($keyHash !== null && $requestFingerprint !== null) {
                $this->completeSetupMutationReceipt(
                    $pdo,
                    $keyHash,
                    $operation,
                    null,
                    $requestFingerprint,
                    $result,
                    (new DateTimeImmutable('now'))->modify('+30 days'),
                );
            }
            return $result;
        });
    }

    /** @return array<string, mixed> */
    public function createManagedMember(
        int $actorUserId,
        mixed $displayNameValue,
        mixed $idempotencyKeyValue = null,
    ): array
    {
        $displayName = self::name($displayNameValue, 'display_name', 'displayName');
        $idempotencyKey = $this->optionalIdempotencyKey($idempotencyKeyValue);
        $operation = 'managed-member-create';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->setupMutationKeyHash($operation, $idempotencyKey);
        $requestFingerprint = $keyHash === null
            ? null
            : $this->setupRequestFingerprint([$displayName]);

        return $this->database->transaction(function (PDO $pdo) use (
            $actorUserId,
            $displayName,
            $keyHash,
            $operation,
            $requestFingerprint,
        ): array {
            if ($keyHash !== null && $requestFingerprint !== null) {
                $replay = $this->reserveSetupMutationReceipt(
                    $pdo,
                    $keyHash,
                    $operation,
                    $actorUserId,
                    $requestFingerprint,
                    (new DateTimeImmutable('now'))->modify('+30 days'),
                );
                if ($replay !== null) {
                    return $replay;
                }
            }

            $membership = $this->requireFamilyMembership($pdo, $actorUserId, true);
            $this->requireOwner($membership);

            $insert = $pdo->prepare('INSERT INTO users (display_name) VALUES (:name)');
            $insert->execute(['name' => $displayName]);
            $managedUserId = (int) $pdo->lastInsertId();

            $member = $pdo->prepare(
                "INSERT INTO family_members (family_id, user_id, role)
                 VALUES (:family, :user, 'member')"
            );
            $member->execute([
                'family' => $membership['family_id'],
                'user' => $managedUserId,
            ]);
            $managed = $pdo->prepare(
                'INSERT INTO managed_profiles (user_id, family_id, created_by_user_id)
                 VALUES (:user, :family, :creator)'
            );
            $managed->execute([
                'user' => $managedUserId,
                'family' => $membership['family_id'],
                'creator' => $actorUserId,
            ]);

            $presented = Presenter::user($this->userById($pdo, $managedUserId));
            $presented['managed'] = true;
            if ($keyHash !== null && $requestFingerprint !== null) {
                $this->completeSetupMutationReceipt(
                    $pdo,
                    $keyHash,
                    $operation,
                    $actorUserId,
                    $requestFingerprint,
                    $presented,
                    (new DateTimeImmutable('now'))->modify('+30 days'),
                );
            }
            return $presented;
        });
    }

    /** @return array<string, mixed> */
    public function createPairing(int $actorUserId, string $memberIdValue): array
    {
        $managedUserId = self::id($memberIdValue, 'member');

        return $this->database->transaction(function (PDO $pdo) use ($actorUserId, $managedUserId): array {
            $managed = $this->requireManagedMember($pdo, $actorUserId, $managedUserId, true);
            $this->revokePendingPairings($pdo, $managedUserId);

            $expiresAt = (new DateTimeImmutable('now'))
                ->modify(sprintf('+%d seconds', $this->config->pairingTtlSeconds))
                ->format('Y-m-d H:i:s');
            [$pairingId, $code, $token] = $this->insertPairing(
                $pdo,
                (int) $managed['family_id'],
                $managedUserId,
                $actorUserId,
                $expiresAt,
            );
            $row = $this->pairingById($pdo, $pairingId);
            return $this->presentPairing($row, $code, $token);
        });
    }

    /** @return array<string, mixed> */
    public function previewPairing(
        mixed $codeValue,
        mixed $tokenValue,
        string $clientIp,
        mixed $idempotencyKeyValue = null,
    ): array {
        try {
            [$column, $hash] = $this->pairingCredential($codeValue, $tokenValue);
        } catch (ApiException $exception) {
            $this->consumePairingRateLimit('preview', $clientIp);
            throw $exception;
        }
        if ($idempotencyKeyValue !== null) {
            $keyHash = $this->crypto->hashOpaque(
                'pairing-activation:' . $this->idempotencyKey($idempotencyKeyValue)
            );
            $replayed = $this->pairingReplayByKey(
                $this->database->connection(),
                $keyHash,
                $column,
                $hash,
            );
            if ($replayed !== null) {
                // Exact lost-response re-entry is not a new credential attempt
                // and therefore must not be rejected by an exhausted IP bucket.
                return $this->presentPairing($replayed);
            }
        }
        $this->consumePairingRateLimit('preview', $clientIp);
        $row = $this->pairingByCredential(
            $this->database->connection(),
            $column,
            $hash,
            false,
        );
        $this->requirePendingPairing($row);
        return $this->presentPairing($row);
    }

    /** @return array<string, mixed> */
    public function activatePairing(
        mixed $codeValue,
        mixed $tokenValue,
        string $clientIp,
        mixed $idempotencyKeyValue = null,
    ): array {
        try {
            [$column, $hash] = $this->pairingCredential($codeValue, $tokenValue);
        } catch (ApiException $exception) {
            $this->consumePairingRateLimit('activate', $clientIp);
            throw $exception;
        }
        $idempotencyKey = $this->idempotencyKey($idempotencyKeyValue);
        $keyHash = $this->crypto->hashOpaque('pairing-activation:' . $idempotencyKey);
        $replayed = $this->pairingReplayByKey(
            $this->database->connection(),
            $keyHash,
            $column,
            $hash,
        );
        if ($replayed !== null) {
            return $this->decryptAuthResponse(
                (string) $replayed['activation_response_encrypted']
            );
        }
        $this->consumePairingRateLimit('activate', $clientIp);

        return $this->database->transaction(function (PDO $pdo) use (
            $column,
            $hash,
            $keyHash,
        ): array {
            $row = $this->pairingByCredential($pdo, $column, $hash, true);
            if ($row['consumed_at'] !== null &&
                is_string($row['activation_key_hash']) &&
                hash_equals($row['activation_key_hash'], $keyHash) &&
                is_string($row['activation_response_encrypted']) &&
                is_string($row['activation_replay_expires_at']) &&
                strtotime($row['activation_replay_expires_at']) > time()) {
                return $this->decryptAuthResponse($row['activation_response_encrypted']);
            }
            $this->requirePendingPairing($row);

            $reused = $pdo->prepare(
                'SELECT 1 FROM device_pairings
                 WHERE activation_key_hash = :key AND id <> :id LIMIT 1'
            );
            $reused->execute(['key' => $keyHash, 'id' => $row['id']]);
            if ($reused->fetchColumn() !== false) {
                throw new ApiException(
                    409,
                    'idempotency_key_reused',
                    'The idempotency key was already used for another pairing.',
                );
            }

            $auth = $this->issueAuthSession(
                $this->userById($pdo, (int) $row['managed_user_id'])
            );
            $encoded = json_encode($auth, JSON_THROW_ON_ERROR);
            // The stored response contains the only copy of the bearer after
            // this one-time credential is consumed. Keep it replayable for
            // the entire lifetime of that exact issued session.
            $replayExpiresAt = (new DateTimeImmutable((string) $auth['expiresAt']))
                ->format('Y-m-d H:i:s');

            $consume = $pdo->prepare(
                'UPDATE device_pairings
                 SET consumed_at = CURRENT_TIMESTAMP,
                     activation_key_hash = :key,
                     activation_response_encrypted = :response,
                     activation_replay_expires_at = :replay_expires
                 WHERE id = :id
                   AND consumed_at IS NULL
                   AND revoked_at IS NULL
                   AND expires_at > CURRENT_TIMESTAMP'
            );
            $consume->execute([
                'key' => $keyHash,
                'response' => $this->crypto->encrypt($encoded),
                'replay_expires' => $replayExpiresAt,
                'id' => $row['id'],
            ]);
            if ($consume->rowCount() !== 1) {
                throw new ApiException(
                    409,
                    'pairing_state_changed',
                    'The pairing was already used or is no longer available.',
                );
            }

            return $auth;
        });
    }

    /** @return array{items: list<array<string, mixed>>} */
    public function pairings(int $actorUserId): array
    {
        $pdo = $this->database->connection();
        $membership = $this->requireFamilyMembership($pdo, $actorUserId);
        $sql =
            'SELECT dp.id, dp.family_id, dp.managed_user_id, dp.created_by_user_id,
                    dp.expires_at, dp.consumed_at, dp.revoked_at, dp.created_at,
                    dp.activation_key_hash, dp.activation_response_encrypted,
                    dp.activation_replay_expires_at,
                    u.display_name AS member_name, f.name AS family_name
             FROM device_pairings dp
             JOIN users u ON u.id = dp.managed_user_id
             JOIN families f ON f.id = dp.family_id
             WHERE dp.family_id = :family';
        if ((string) $membership['role'] !== 'owner') {
            $sql .= ' AND dp.created_by_user_id = :actor';
        }
        $sql .= ' ORDER BY dp.id DESC LIMIT 100';
        $statement = $pdo->prepare($sql);
        $statement->bindValue(':family', (int) $membership['family_id'], PDO::PARAM_INT);
        if ((string) $membership['role'] !== 'owner') {
            $statement->bindValue(':actor', $actorUserId, PDO::PARAM_INT);
        }
        $statement->execute();

        return [
            'items' => array_map(
                fn (array $row): array => $this->presentPairing($row),
                $statement->fetchAll(),
            ),
        ];
    }

    public function revokePairing(int $actorUserId, string $pairingIdValue): void
    {
        $pairingId = self::id($pairingIdValue, 'pairing');
        $this->database->transaction(function (PDO $pdo) use ($actorUserId, $pairingId): void {
            $sql =
                'SELECT dp.id, dp.created_by_user_id, dp.consumed_at, dp.revoked_at,
                        fm.role
                 FROM device_pairings dp
                 JOIN family_members fm
                   ON fm.family_id = dp.family_id AND fm.user_id = :actor
                 WHERE dp.id = :pairing';
            if (!$this->database->isSqlite()) {
                $sql .= ' FOR UPDATE';
            }
            $statement = $pdo->prepare($sql);
            $statement->execute(['actor' => $actorUserId, 'pairing' => $pairingId]);
            $row = $statement->fetch();
            if (!is_array($row)) {
                throw new ApiException(404, 'pairing_not_found', 'Pairing not found.');
            }
            if ((string) $row['role'] !== 'owner' &&
                (int) $row['created_by_user_id'] !== $actorUserId) {
                throw new ApiException(
                    403,
                    'family_manager_required',
                    'Only a family owner or this member’s manager can revoke the pairing.',
                );
            }
            if ($row['consumed_at'] !== null) {
                throw new ApiException(409, 'pairing_already_used', 'The pairing has already been used.');
            }
            if ($row['revoked_at'] !== null) {
                return;
            }
            $revoke = $pdo->prepare(
                'UPDATE device_pairings
                 SET revoked_at = CURRENT_TIMESTAMP
                 WHERE id = :id AND consumed_at IS NULL AND revoked_at IS NULL'
            );
            $revoke->execute(['id' => $pairingId]);
            if ($revoke->rowCount() !== 1) {
                throw new ApiException(
                    409,
                    'pairing_state_changed',
                    'The pairing state changed before it could be revoked.',
                );
            }
        });
    }

    private function consumePairingRateLimit(string $action, string $clientIp): void
    {
        $this->rateLimiter->consume(
            'pairing-' . $action . '-ip:' . $clientIp,
            $this->config->pairingIpAttemptsPerHour,
            3600,
        );
    }

    /** @return array{0: string, 1: string} */
    private function pairingCredential(mixed $codeValue, mixed $tokenValue): array
    {
        $hasCode = $codeValue !== null;
        $hasToken = $tokenValue !== null;
        if ($hasCode === $hasToken) {
            throw new ApiException(
                422,
                'invalid_pairing_credential',
                'Provide exactly one of code or token.',
            );
        }

        if ($hasCode) {
            if (!is_string($codeValue)) {
                throw new ApiException(422, 'invalid_pairing_code', 'code must be a six-digit string.');
            }
            $code = preg_replace('/[\s-]+/u', '', trim($codeValue));
            if (!is_string($code) || preg_match('/^[0-9]{6}$/', $code) !== 1) {
                throw new ApiException(422, 'invalid_pairing_code', 'code must be a six-digit string.');
            }
            return ['code_hash', $this->crypto->hashOpaque('pairing-code:' . $code)];
        }

        if (!is_string($tokenValue) ||
            preg_match('/^[A-Za-z0-9_-]{40,128}$/', trim($tokenValue)) !== 1) {
            throw new ApiException(422, 'invalid_pairing_token', 'token is invalid.');
        }
        $token = trim($tokenValue);
        return ['token_hash', $this->crypto->hashOpaque('pairing-token:' . $token)];
    }

    /** @return array<string, mixed> */
    private function pairingByCredential(
        PDO $pdo,
        string $column,
        string $hash,
        bool $forUpdate,
    ): array {
        $sql =
            'SELECT dp.id, dp.family_id, dp.managed_user_id, dp.created_by_user_id,
                    dp.expires_at, dp.consumed_at, dp.revoked_at, dp.created_at,
                    dp.activation_key_hash, dp.activation_response_encrypted,
                    dp.activation_replay_expires_at,
                    u.display_name AS member_name, f.name AS family_name
             FROM device_pairings dp
             JOIN users u ON u.id = dp.managed_user_id
             JOIN families f ON f.id = dp.family_id
             WHERE dp.' . $column . ' = :hash
             LIMIT 1';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['hash' => $hash]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'pairing_not_found', 'Pairing not found.');
        }
        return $row;
    }

    /** @return array<string, mixed>|null */
    private function pairingReplayByKey(
        PDO $pdo,
        string $keyHash,
        string $credentialColumn,
        string $credentialHash,
    ): ?array {
        $statement = $pdo->prepare(
            'SELECT dp.id, dp.family_id, dp.managed_user_id, dp.created_by_user_id,
                    dp.expires_at, dp.consumed_at, dp.revoked_at, dp.created_at,
                    dp.activation_key_hash, dp.activation_response_encrypted,
                    dp.activation_replay_expires_at,
                    u.display_name AS member_name, f.name AS family_name
             FROM device_pairings dp
             JOIN users u ON u.id = dp.managed_user_id
             JOIN families f ON f.id = dp.family_id
             WHERE dp.activation_key_hash = :key
               AND dp.' . $credentialColumn . ' = :credential
               AND dp.consumed_at IS NOT NULL
               AND dp.activation_response_encrypted IS NOT NULL
               AND dp.activation_replay_expires_at > CURRENT_TIMESTAMP
             LIMIT 1'
        );
        $statement->execute([
            'key' => $keyHash,
            'credential' => $credentialHash,
        ]);
        $row = $statement->fetch();
        return is_array($row) ? $row : null;
    }

    /** @return array<string, mixed> */
    private function pairingById(PDO $pdo, int $pairingId): array
    {
        $statement = $pdo->prepare(
            'SELECT dp.id, dp.family_id, dp.managed_user_id, dp.created_by_user_id,
                    dp.expires_at, dp.consumed_at, dp.revoked_at, dp.created_at,
                    u.display_name AS member_name, f.name AS family_name
             FROM device_pairings dp
             JOIN users u ON u.id = dp.managed_user_id
             JOIN families f ON f.id = dp.family_id
             WHERE dp.id = :id'
        );
        $statement->execute(['id' => $pairingId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new RuntimeException('The created pairing could not be loaded.');
        }
        return $row;
    }

    /** @return array<string, mixed> */
    private function presentPairing(
        array $row,
        ?string $code = null,
        ?string $token = null,
    ): array {
        $pairing = [
            'id' => (string) $row['id'],
            'expiresAt' => Presenter::utcTimestamp((string) $row['expires_at']),
            'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
            'status' => $this->pairingStatus($row),
            'member' => [
                'id' => (string) $row['managed_user_id'],
                'displayName' => (string) $row['member_name'],
            ],
            'family' => [
                'id' => (string) $row['family_id'],
                'name' => (string) $row['family_name'],
            ],
        ];
        if ($code !== null && $token !== null) {
            $pairing['code'] = $code;
            $pairing['token'] = $token;
            $pairing['pairingUrl'] = $this->config->appUrl . '/invite/' . rawurlencode($token);
        }
        return $pairing;
    }

    private function pairingStatus(array $row): string
    {
        if ($row['revoked_at'] !== null) {
            return 'revoked';
        }
        if ($row['consumed_at'] !== null) {
            return 'consumed';
        }
        if (strtotime((string) $row['expires_at']) <= time()) {
            return 'expired';
        }
        return 'pending';
    }

    private function requirePendingPairing(array $row): void
    {
        $status = $this->pairingStatus($row);
        match ($status) {
            'pending' => null,
            'consumed' => throw new ApiException(
                409,
                'pairing_already_used',
                'The pairing has already been used.',
            ),
            'revoked' => throw new ApiException(
                410,
                'pairing_revoked',
                'The pairing was revoked.',
            ),
            default => throw new ApiException(
                410,
                'pairing_expired',
                'The pairing has expired.',
            ),
        };
    }

    /** @return array<string, mixed> */
    private function requireManagedMember(
        PDO $pdo,
        int $actorUserId,
        int $managedUserId,
        bool $forUpdate = false,
    ): array
    {
        $sql =
            'SELECT mp.family_id, mp.created_by_user_id, fm.role
             FROM managed_profiles mp
             JOIN family_members fm
               ON fm.family_id = mp.family_id AND fm.user_id = :actor
             WHERE mp.user_id = :managed_user';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute([
            'actor' => $actorUserId,
            'managed_user' => $managedUserId,
        ]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'managed_member_not_found', 'Managed family member not found.');
        }
        if ((string) $row['role'] !== 'owner' &&
            (int) $row['created_by_user_id'] !== $actorUserId) {
            throw new ApiException(
                403,
                'family_manager_required',
                'Only a family owner or this member’s manager can create a pairing.',
            );
        }
        return $row;
    }

    /** @return array<string, mixed> */
    private function requireFamilyMembership(
        PDO $pdo,
        int $userId,
        bool $forUpdate = false,
    ): array
    {
        $sql =
            'SELECT fm.family_id, fm.role, f.name AS family_name
             FROM family_members fm
             JOIN families f ON f.id = fm.family_id
             WHERE fm.user_id = :user';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['user' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(409, 'family_required', 'The user does not belong to a family.');
        }
        return $row;
    }

    private function requireOwner(array $membership): void
    {
        if ((string) $membership['role'] !== 'owner') {
            throw new ApiException(
                403,
                'family_owner_required',
                'Only the family owner can add a managed family member.',
            );
        }
    }

    private function revokePendingPairings(PDO $pdo, int $managedUserId): void
    {
        $statement = $pdo->prepare(
            'UPDATE device_pairings
             SET revoked_at = CURRENT_TIMESTAMP
             WHERE managed_user_id = :user
               AND consumed_at IS NULL
               AND revoked_at IS NULL
               AND expires_at > CURRENT_TIMESTAMP'
        );
        $statement->execute(['user' => $managedUserId]);
    }

    /** @return array{0: int, 1: string, 2: string} */
    private function insertPairing(
        PDO $pdo,
        int $familyId,
        int $managedUserId,
        int $actorUserId,
        string $expiresAt,
    ): array {
        for ($attempt = 0; $attempt < 5; $attempt++) {
            $code = str_pad((string) random_int(0, 999_999), 6, '0', STR_PAD_LEFT);
            $token = $this->crypto->randomToken(32);
            try {
                $statement = $pdo->prepare(
                    'INSERT INTO device_pairings
                        (family_id, managed_user_id, created_by_user_id,
                         code_hash, token_hash, expires_at)
                     VALUES
                        (:family, :managed_user, :creator, :code_hash, :token_hash, :expires)'
                );
                $statement->execute([
                    'family' => $familyId,
                    'managed_user' => $managedUserId,
                    'creator' => $actorUserId,
                    'code_hash' => $this->crypto->hashOpaque('pairing-code:' . $code),
                    'token_hash' => $this->crypto->hashOpaque('pairing-token:' . $token),
                    'expires' => $expiresAt,
                ]);
                return [(int) $pdo->lastInsertId(), $code, $token];
            } catch (PDOException $exception) {
                if ((string) $exception->getCode() !== '23000') {
                    throw $exception;
                }
            }
        }
        throw new RuntimeException('Unable to create a unique device pairing.');
    }

    private function insertFamily(PDO $pdo, string $familyName): int
    {
        for ($attempt = 0; $attempt < 5; $attempt++) {
            $inviteCode = strtoupper(substr(bin2hex(random_bytes(8)), 0, 12));
            try {
                $family = $pdo->prepare(
                    'INSERT INTO families (name, invite_code) VALUES (:name, :code)'
                );
                $family->execute(['name' => $familyName, 'code' => $inviteCode]);
                return (int) $pdo->lastInsertId();
            } catch (PDOException $exception) {
                if ((string) $exception->getCode() !== '23000') {
                    throw $exception;
                }
            }
        }
        throw new RuntimeException('Unable to create a unique family.');
    }

    /** @return array<string, mixed> */
    private function userById(PDO $pdo, int $userId): array
    {
        $statement = $pdo->prepare(
            'SELECT u.id, u.phone_e164, u.display_name, u.avatar_url, u.created_at,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM users u
             LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE u.id = :id'
        );
        $statement->execute(['id' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new RuntimeException('User could not be loaded.');
        }
        return $row;
    }

    /** @return array<string, mixed> */
    private function issueAuthSession(array $user): array
    {
        $session = $this->sessions->issue((int) $user['id']);
        return [
            'token' => $session['token'],
            'tokenType' => 'Bearer',
            'expiresAt' => $session['expiresAt'],
            'user' => Presenter::user($user),
        ];
    }

    /** @return array<string, mixed> */
    private function decryptAuthResponse(string $encrypted): array
    {
        $decoded = json_decode(
            $this->crypto->decrypt($encrypted),
            true,
            32,
            JSON_THROW_ON_ERROR,
        );
        if (!is_array($decoded) || !is_string($decoded['token'] ?? null)) {
            throw new RuntimeException('Stored pairing replay response is invalid.');
        }
        return $decoded;
    }

    private function optionalIdempotencyKey(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        return $this->idempotencyKey($value);
    }

    private function setupMutationKeyHash(string $operation, string $key): string
    {
        return $this->crypto->hashOpaque(
            'setup-mutation:' . $operation . ':' . $key
        );
    }

    /** @param array<int, string> $values */
    private function setupRequestFingerprint(array $values): string
    {
        return $this->crypto->hashOpaque(
            'setup-request:' . json_encode(
                $values,
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE,
            )
        );
    }

    /** @return array<string, mixed>|null */
    private function completedSetupMutationReplay(
        string $keyHash,
        string $operation,
        ?int $actorUserId,
        string $requestFingerprint,
    ): ?array {
        $statement = $this->database->connection()->prepare(
            'SELECT operation, actor_user_id, request_fingerprint,
                    response_encrypted, expires_at
             FROM setup_mutation_receipts
             WHERE key_hash = :key LIMIT 1'
        );
        $statement->execute(['key' => $keyHash]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            return null;
        }
        $this->assertSetupMutationBinding(
            $row,
            $operation,
            $actorUserId,
            $requestFingerprint,
        );
        if (new DateTimeImmutable((string) $row['expires_at'])
            <= new DateTimeImmutable('now')) {
            return null;
        }
        if (!is_string($row['response_encrypted'])) {
            return null;
        }
        return $this->decryptSetupMutationResponse($row['response_encrypted']);
    }

    /**
     * @return array<string, mixed>|null Exact completed replay, or null for
     * the newly reserved request.
     */
    private function reserveSetupMutationReceipt(
        PDO $pdo,
        string $keyHash,
        string $operation,
        ?int $actorUserId,
        string $requestFingerprint,
        DateTimeImmutable $expiresAt,
    ): ?array {
        $deleteExpired = $pdo->prepare(
            'DELETE FROM setup_mutation_receipts
             WHERE key_hash = :key AND expires_at <= :now'
        );
        $deleteExpired->execute([
            'key' => $keyHash,
            'now' => (new DateTimeImmutable('now'))->format('Y-m-d H:i:s'),
        ]);

        $reserve = $pdo->prepare($this->database->isSqlite()
            ? 'INSERT OR IGNORE INTO setup_mutation_receipts
                 (key_hash, operation, actor_user_id, request_fingerprint,
                  response_encrypted, expires_at)
               VALUES (:key, :operation, :actor, :fingerprint, NULL, :expires)'
            : 'INSERT IGNORE INTO setup_mutation_receipts
                 (key_hash, operation, actor_user_id, request_fingerprint,
                  response_encrypted, expires_at)
               VALUES (:key, :operation, :actor, :fingerprint, NULL, :expires)'
        );
        $reserve->execute([
            'key' => $keyHash,
            'operation' => $operation,
            'actor' => $actorUserId,
            'fingerprint' => $requestFingerprint,
            'expires' => $expiresAt->format('Y-m-d H:i:s'),
        ]);
        $newlyReserved = $reserve->rowCount() === 1;

        $sql =
            'SELECT operation, actor_user_id, request_fingerprint,
                    response_encrypted, expires_at
             FROM setup_mutation_receipts
             WHERE key_hash = :key LIMIT 1';
        if (!$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $lookup = $pdo->prepare($sql);
        $lookup->execute(['key' => $keyHash]);
        $row = $lookup->fetch();
        if (!is_array($row)) {
            throw new RuntimeException('Setup mutation receipt reservation is invalid.');
        }
        $this->assertSetupMutationBinding(
            $row,
            $operation,
            $actorUserId,
            $requestFingerprint,
        );
        if (is_string($row['response_encrypted'])) {
            return $this->decryptSetupMutationResponse($row['response_encrypted']);
        }
        if (!$newlyReserved) {
            throw new RuntimeException('Stored setup mutation receipt is incomplete.');
        }
        return null;
    }

    /** @param array<string, mixed> $result */
    private function completeSetupMutationReceipt(
        PDO $pdo,
        string $keyHash,
        string $operation,
        ?int $actorUserId,
        string $requestFingerprint,
        array $result,
        DateTimeImmutable $expiresAt,
    ): void {
        $encoded = json_encode(
            $result,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        );
        $update = $pdo->prepare(
            'UPDATE setup_mutation_receipts
             SET response_encrypted = :response, expires_at = :expires
             WHERE key_hash = :key AND operation = :operation
               AND request_fingerprint = :fingerprint
               AND response_encrypted IS NULL'
        );
        $update->execute([
            'response' => $this->crypto->encrypt($encoded),
            'expires' => $expiresAt->format('Y-m-d H:i:s'),
            'key' => $keyHash,
            'operation' => $operation,
            'fingerprint' => $requestFingerprint,
        ]);
        if ($update->rowCount() !== 1) {
            throw new RuntimeException('Setup mutation receipt did not complete exactly once.');
        }
    }

    /** @param array<string, mixed> $row */
    private function assertSetupMutationBinding(
        array $row,
        string $operation,
        ?int $actorUserId,
        string $requestFingerprint,
    ): void {
        $storedActor = $row['actor_user_id'] === null
            ? null
            : (int) $row['actor_user_id'];
        if ((string) $row['operation'] !== $operation ||
            $storedActor !== $actorUserId ||
            !hash_equals((string) $row['request_fingerprint'], $requestFingerprint)) {
            throw new ApiException(
                409,
                'idempotency_key_reused',
                'The idempotency key was already used for a different setup request.',
            );
        }
    }

    /** @return array<string, mixed> */
    private function decryptSetupMutationResponse(string $encrypted): array
    {
        $decoded = json_decode(
            $this->crypto->decrypt($encrypted),
            true,
            32,
            JSON_THROW_ON_ERROR,
        );
        if (!is_array($decoded) || $decoded === []) {
            throw new RuntimeException('Stored setup replay response is invalid.');
        }
        return $decoded;
    }

    private function idempotencyKey(mixed $value): string
    {
        if ($value === null) {
            // Backward-compatible service callers remain one-shot. Current
            // HTTP clients always supply a stable key and can safely retry.
            return $this->crypto->randomToken(24);
        }
        if (!is_string($value) ||
            preg_match('/^[A-Za-z0-9._-]{16,128}$/', trim($value)) !== 1) {
            throw new ApiException(
                422,
                'invalid_idempotency_key',
                'Idempotency-Key must be 16 to 128 safe ASCII characters.',
            );
        }
        return trim($value);
    }

    private static function id(string $value, string $resource): int
    {
        if (preg_match('/^[1-9][0-9]{0,18}$/', $value) !== 1) {
            throw new ApiException(422, 'invalid_' . $resource . '_id', $resource . ' id is invalid.');
        }
        return (int) $value;
    }

    private static function name(mixed $value, string $errorSuffix, string $field): string
    {
        if (!is_string($value)) {
            throw new ApiException(
                422,
                'invalid_' . $errorSuffix,
                $field . ' must be a string.',
            );
        }
        $value = trim(str_replace("\0", '', preg_replace('/\s+/u', ' ', $value) ?? ''));
        if ($value === '' || mb_strlen($value, 'UTF-8') > 80) {
            throw new ApiException(
                422,
                'invalid_' . $errorSuffix,
                $field . ' must be between 1 and 80 characters.',
            );
        }
        return $value;
    }
}
