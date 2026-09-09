<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use DateTimeImmutable;
use PDO;
use RuntimeException;
use Tsutsuura\Server\Http\ApiException;

// Shared by legacy SMS and email verification. Persist both successful and
// failed outcomes so a transport retry cannot create sessions or spend attempts twice.
trait OtpMutationReceipts
{
    private function optionalIdempotencyKey(mixed $value): ?string
    {
        if ($value === null) {
            return null;
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

    /** @return array<string, mixed>|null */
    private function findOtpMutationOutcome(
        string $operation,
        ?int $actorUserId,
        string $keyHash,
        string $fingerprint,
    ): ?array {
        $statement = $this->database->connection()->prepare(
            'SELECT operation, actor_user_id, request_fingerprint, outcome_encrypted
             FROM otp_mutation_receipts
             WHERE key_hash = :key AND expires_at > CURRENT_TIMESTAMP
             LIMIT 1'
        );
        $statement->execute(['key' => $keyHash]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            return null;
        }
        $this->assertOtpReceiptBinding(
            $row,
            $operation,
            $actorUserId,
            $fingerprint,
        );
        $encrypted = $row['outcome_encrypted'] ?? null;
        if (!is_string($encrypted) || $encrypted === '') {
            throw new RuntimeException('OTP verification receipt is incomplete.');
        }
        return $this->decryptOtpOutcome($encrypted);
    }

    /** @return array<string, mixed>|null */
    private function reserveOtpMutationReceipt(
        PDO $pdo,
        string $operation,
        ?int $actorUserId,
        ?string $keyHash,
        string $fingerprint,
    ): ?array {
        if ($keyHash === null) {
            return null;
        }
        $delete = $pdo->prepare(
            'DELETE FROM otp_mutation_receipts
             WHERE key_hash = :key AND expires_at <= CURRENT_TIMESTAMP'
        );
        $delete->execute(['key' => $keyHash]);
        $insert = $pdo->prepare($this->database->isSqlite()
            ? 'INSERT OR IGNORE INTO otp_mutation_receipts
                (key_hash, operation, actor_user_id, request_fingerprint,
                 outcome_encrypted, expires_at)
               VALUES (:key, :operation, :actor, :fingerprint, NULL, :expires)'
            : 'INSERT IGNORE INTO otp_mutation_receipts
                (key_hash, operation, actor_user_id, request_fingerprint,
                 outcome_encrypted, expires_at)
               VALUES (:key, :operation, :actor, :fingerprint, NULL, :expires)'
        );
        $insert->execute([
            'key' => $keyHash,
            'operation' => $operation,
            'actor' => $actorUserId,
            'fingerprint' => $fingerprint,
            'expires' => (new DateTimeImmutable('now'))
                ->modify('+30 days')->format('Y-m-d H:i:s'),
        ]);
        $inserted = $insert->rowCount() === 1;
        $select = $pdo->prepare(
            'SELECT operation, actor_user_id, request_fingerprint, outcome_encrypted
             FROM otp_mutation_receipts WHERE key_hash = :key' .
            ($this->database->isSqlite() ? '' : ' FOR UPDATE')
        );
        $select->execute(['key' => $keyHash]);
        $row = $select->fetch();
        if (!is_array($row)) {
            throw new RuntimeException('OTP verification receipt reservation disappeared.');
        }
        $this->assertOtpReceiptBinding(
            $row,
            $operation,
            $actorUserId,
            $fingerprint,
        );
        if ($inserted) {
            return null;
        }
        $encrypted = $row['outcome_encrypted'] ?? null;
        if (!is_string($encrypted) || $encrypted === '') {
            throw new RuntimeException('OTP verification receipt is still incomplete.');
        }
        return $this->decryptOtpOutcome($encrypted);
    }

    /** @param array<string, mixed> $outcome */
    private function completeOtpMutationReceipt(
        PDO $pdo,
        ?string $keyHash,
        array $outcome,
    ): void {
        if ($keyHash === null) {
            return;
        }
        $statement = $pdo->prepare(
            'UPDATE otp_mutation_receipts
             SET outcome_encrypted = :outcome
             WHERE key_hash = :key AND outcome_encrypted IS NULL'
        );
        $statement->execute([
            'outcome' => $this->encryptOtpOutcome($outcome),
            'key' => $keyHash,
        ]);
        if ($statement->rowCount() !== 1) {
            throw new RuntimeException('OTP verification receipt did not complete exactly once.');
        }
    }

    /** @param array<string, mixed> $row */
    private function assertOtpReceiptBinding(
        array $row,
        string $operation,
        ?int $actorUserId,
        string $fingerprint,
    ): void {
        $storedActor = $row['actor_user_id'] === null
            ? null
            : (int) $row['actor_user_id'];
        if ((string) $row['operation'] !== $operation ||
            $storedActor !== $actorUserId ||
            !hash_equals((string) $row['request_fingerprint'], $fingerprint)) {
            throw new ApiException(
                409,
                'idempotency_key_reused',
                'The idempotency key was already used for a different verification.',
            );
        }
    }

    /** @return array{kind: string, status: int, code: string, message: string} */
    private function otpErrorOutcome(
        int $status,
        string $code,
        string $message,
    ): array {
        return [
            'kind' => 'error',
            'status' => $status,
            'code' => $code,
            'message' => $message,
        ];
    }

    /** @param array<string, mixed> $outcome @return array<string, mixed> */
    private function resolveOtpMutationOutcome(array $outcome): array
    {
        if (($outcome['kind'] ?? null) === 'success' &&
            is_array($outcome['result'] ?? null)) {
            return $outcome['result'];
        }
        if (($outcome['kind'] ?? null) === 'error' &&
            is_int($outcome['status'] ?? null) &&
            is_string($outcome['code'] ?? null) &&
            is_string($outcome['message'] ?? null)) {
            throw new ApiException(
                $outcome['status'],
                $outcome['code'],
                $outcome['message'],
            );
        }
        throw new RuntimeException('Stored OTP verification outcome is invalid.');
    }

    /** @param array<string, mixed> $outcome */
    private function encryptOtpOutcome(array $outcome): string
    {
        return $this->crypto->encrypt(json_encode(
            $outcome,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        ));
    }

    /** @return array<string, mixed> */
    private function decryptOtpOutcome(string $encrypted): array
    {
        $decoded = json_decode(
            $this->crypto->decrypt($encrypted),
            true,
            32,
            JSON_THROW_ON_ERROR,
        );
        if (!is_array($decoded) || $decoded === []) {
            throw new RuntimeException('Stored OTP verification outcome is invalid.');
        }
        return $decoded;
    }

}
