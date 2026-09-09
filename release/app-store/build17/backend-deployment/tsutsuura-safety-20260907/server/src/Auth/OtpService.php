<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use DateTimeImmutable;
use PDO;
use PDOException;
use RuntimeException;
use Throwable;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;

final class OtpService
{
    use OtpMutationReceipts;

    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly RateLimiter $rateLimiter,
        private readonly SmsSender $smsSender,
        private readonly UserService $users,
        private readonly SessionService $sessions,
        private readonly Config $config,
    ) {
    }

    /** @return array<string, mixed> */
    public function request(mixed $phoneValue, string $clientIp): array
    {
        $this->ensureEnabled();
        $phone = PhoneNumber::normalize($phoneValue);
        $this->rateLimiter->consume('otp-phone:' . $phone, $this->config->otpPhoneRequestsPerHour, 3600);
        $this->rateLimiter->consume('otp-ip:' . $clientIp, $this->config->otpIpRequestsPerHour, 3600);

        $requestId = bin2hex(random_bytes(16));
        $code = (string) random_int(100000, 999999);
        $expires = (new DateTimeImmutable('now'))->modify(sprintf('+%d seconds', $this->config->otpTtlSeconds));
        $statement = $this->database->connection()->prepare(
            'INSERT INTO phone_otp_challenges
                (request_id, phone_e164, code_hash, max_attempts, expires_at)
             VALUES (:request, :phone, :hash, :max, :expires)'
        );
        $statement->execute([
            'request' => $requestId,
            'phone' => $phone,
            'hash' => $this->crypto->otpHash($requestId, $code),
            'max' => $this->config->otpMaxAttempts,
            'expires' => $expires->format('Y-m-d H:i:s'),
        ]);

        try {
            $this->smsSender->sendOtp($phone, $code);
        } catch (Throwable $exception) {
            $invalidate = $this->database->connection()->prepare(
                'UPDATE phone_otp_challenges SET consumed_at = CURRENT_TIMESTAMP WHERE request_id = :request'
            );
            $invalidate->execute(['request' => $requestId]);
            error_log('OTP delivery error: ' . $exception->getMessage());
            throw new ApiException(502, 'sms_delivery_failed', 'The verification code could not be sent. Please try again.');
        }

        $response = ['requestId' => $requestId, 'expiresIn' => $this->config->otpTtlSeconds];
        if (!$this->config->isProduction() && $this->config->otpDevExpose) {
            $response['developmentCode'] = $code;
        }
        return $response;
    }

    /** @return array<string, mixed> */
    public function verify(
        mixed $requestIdValue,
        mixed $codeValue,
        string $clientIp,
        mixed $idempotencyKeyValue = null,
    ): array
    {
        $this->ensureEnabled();
        if (!is_string($requestIdValue) || preg_match('/^[a-f0-9]{32}$/', $requestIdValue) !== 1 ||
            !is_string($codeValue) || preg_match('/^[0-9]{6}$/', $codeValue) !== 1) {
            throw new ApiException(422, 'invalid_otp', 'The verification code is invalid.');
        }
        $idempotencyKey = $this->optionalIdempotencyKey($idempotencyKeyValue);
        $operation = 'login_verification';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->crypto->hashOpaque('otp-verification:' . $idempotencyKey);
        $fingerprint = $this->crypto->hashOpaque(
            $operation . "\0" . $requestIdValue . "\0" . $codeValue,
        );
        if ($keyHash !== null) {
            $replay = $this->findOtpMutationOutcome(
                $operation,
                null,
                $keyHash,
                $fingerprint,
            );
            if ($replay !== null) {
                return $this->resolveOtpMutationOutcome($replay);
            }
        }
        $this->rateLimiter->consume('otp-verify-ip:' . $clientIp, $this->config->otpVerifyAttemptsPerHour, 3600);

        $outcome = $this->database->transaction(function (PDO $pdo) use (
            $requestIdValue,
            $codeValue,
            $operation,
            $keyHash,
            $fingerprint,
        ): array {
                $replay = $this->reserveOtpMutationReceipt(
                    $pdo,
                    $operation,
                    null,
                    $keyHash,
                    $fingerprint,
                );
                if ($replay !== null) {
                    return $replay;
                }
                $finish = function (array $result) use ($pdo, $keyHash): array {
                    $this->completeOtpMutationReceipt($pdo, $keyHash, $result);
                    return $result;
                };
                $statement = $pdo->prepare(
                    'SELECT phone_e164, code_hash, attempts, max_attempts,
                            expires_at, consumed_at
                     FROM phone_otp_challenges WHERE request_id = :request' .
                    ($this->database->isSqlite() ? '' : ' FOR UPDATE')
                );
                $statement->execute(['request' => $requestIdValue]);
                $challenge = $statement->fetch();
                if (!is_array($challenge)) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }
                if ($challenge['consumed_at'] !== null) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }
                if (strtotime((string) $challenge['expires_at']) <= time() ||
                    (int) $challenge['attempts'] >= (int) $challenge['max_attempts']) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }

                $matches = hash_equals(
                    (string) $challenge['code_hash'],
                    $this->crypto->otpHash($requestIdValue, $codeValue),
                );
                if (!$matches) {
                    $update = $pdo->prepare(
                        'UPDATE phone_otp_challenges
                         SET attempts = attempts + 1 WHERE request_id = :request'
                    );
                    $update->execute(['request' => $requestIdValue]);
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }

                $user = $this->users->findByPhone((string) $challenge['phone_e164']);
                if ($user === null) {
                    $consume = $pdo->prepare(
                        'UPDATE phone_otp_challenges
                         SET attempts = attempts + 1, consumed_at = CURRENT_TIMESTAMP
                         WHERE request_id = :request'
                    );
                    $consume->execute(['request' => $requestIdValue]);
                    return $finish($this->otpErrorOutcome(
                        404,
                        'account_not_found',
                        'No existing account is enrolled with this phone number.',
                    ));
                }

                $session = $this->sessions->issueWithConnection($pdo, (int) $user['id']);
                $result = [
                    'token' => $session['token'],
                    'tokenType' => 'Bearer',
                    'expiresAt' => $session['expiresAt'],
                    'user' => Presenter::user($user, true),
                ];
                $consume = $pdo->prepare(
                    'UPDATE phone_otp_challenges
                     SET attempts = attempts + 1,
                         consumed_at = CURRENT_TIMESTAMP
                     WHERE request_id = :request AND consumed_at IS NULL'
                );
                $consume->execute([
                    'request' => $requestIdValue,
                ]);
                if ($consume->rowCount() !== 1) {
                    throw new RuntimeException('OTP verification did not consume exactly once.');
                }
                return $finish(['kind' => 'success', 'result' => $result]);
        });
        return $this->resolveOtpMutationOutcome($outcome);
    }

    /** @return array<string, mixed> */
    public function requestEnrollment(int $userId, mixed $phoneValue, string $clientIp): array
    {
        $this->ensureEnabled();
        $phone = PhoneNumber::normalize($phoneValue);
        $user = $this->users->loadById($userId);
        $this->rateLimiter->consume(
            'phone-enrollment-user:' . $userId,
            $this->config->otpPhoneRequestsPerHour,
            3600,
        );
        $this->rateLimiter->consume(
            'phone-enrollment-phone:' . $phone,
            $this->config->otpPhoneRequestsPerHour,
            3600,
        );
        $this->rateLimiter->consume(
            'phone-enrollment-ip:' . $clientIp,
            $this->config->otpIpRequestsPerHour,
            3600,
        );
        if ((string) ($user['phone_e164'] ?? '') === $phone) {
            throw new ApiException(409, 'phone_already_enrolled', 'This phone number is already enrolled.');
        }
        $existing = $this->users->findByPhone($phone);
        if ($existing !== null && (int) $existing['id'] !== $userId) {
            throw new ApiException(409, 'phone_already_in_use', 'This phone number belongs to another account.');
        }

        $requestId = bin2hex(random_bytes(16));
        $code = (string) random_int(100000, 999999);
        $expires = (new DateTimeImmutable('now'))
            ->modify(sprintf('+%d seconds', $this->config->otpTtlSeconds));
        $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $requestId,
            $phone,
            $code,
            $expires,
        ): void {
            $invalidate = $pdo->prepare(
                'UPDATE phone_enrollment_challenges
                 SET consumed_at = CURRENT_TIMESTAMP
                 WHERE user_id = :user AND consumed_at IS NULL'
            );
            $invalidate->execute(['user' => $userId]);
            $insert = $pdo->prepare(
                'INSERT INTO phone_enrollment_challenges
                    (user_id, request_id, phone_e164, code_hash, max_attempts, expires_at)
                 VALUES (:user, :request, :phone, :hash, :max, :expires)'
            );
            $insert->execute([
                'user' => $userId,
                'request' => $requestId,
                'phone' => $phone,
                'hash' => $this->crypto->otpHash($requestId, $code),
                'max' => $this->config->otpMaxAttempts,
                'expires' => $expires->format('Y-m-d H:i:s'),
            ]);
        });

        try {
            $this->smsSender->sendOtp($phone, $code);
        } catch (Throwable $exception) {
            $invalidate = $this->database->connection()->prepare(
                'UPDATE phone_enrollment_challenges
                 SET consumed_at = CURRENT_TIMESTAMP WHERE request_id = :request'
            );
            $invalidate->execute(['request' => $requestId]);
            error_log('Phone enrollment delivery error: ' . $exception->getMessage());
            throw new ApiException(
                502,
                'sms_delivery_failed',
                'The verification code could not be sent. Please try again.',
            );
        }

        $response = ['requestId' => $requestId, 'expiresIn' => $this->config->otpTtlSeconds];
        if (!$this->config->isProduction() && $this->config->otpDevExpose) {
            $response['developmentCode'] = $code;
        }
        return $response;
    }

    /** @return array<string, mixed> */
    public function verifyEnrollment(
        int $userId,
        mixed $requestIdValue,
        mixed $codeValue,
        string $clientIp,
        mixed $idempotencyKeyValue = null,
    ): array {
        $this->ensureEnabled();
        if (!is_string($requestIdValue) ||
            preg_match('/^[a-f0-9]{32}$/', $requestIdValue) !== 1 ||
            !is_string($codeValue) || preg_match('/^[0-9]{6}$/', $codeValue) !== 1) {
            throw new ApiException(422, 'invalid_otp', 'The verification code is invalid.');
        }
        $idempotencyKey = $this->optionalIdempotencyKey($idempotencyKeyValue);
        $operation = 'phone_enrollment_verification';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->crypto->hashOpaque('phone-enrollment-verification:' . $idempotencyKey);
        $fingerprint = $this->crypto->hashOpaque(
            $operation . "\0" . $userId . "\0" . $requestIdValue . "\0" . $codeValue,
        );
        if ($keyHash !== null) {
            $replay = $this->findOtpMutationOutcome(
                $operation,
                $userId,
                $keyHash,
                $fingerprint,
            );
            if ($replay !== null) {
                return $this->resolveOtpMutationOutcome($replay);
            }
        }
        $this->rateLimiter->consume(
            'phone-enrollment-verify-ip:' . $clientIp,
            $this->config->otpVerifyAttemptsPerHour,
            3600,
        );

        $outcome = $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $requestIdValue,
            $codeValue,
            $operation,
            $keyHash,
            $fingerprint,
        ): array {
                $replay = $this->reserveOtpMutationReceipt(
                    $pdo,
                    $operation,
                    $userId,
                    $keyHash,
                    $fingerprint,
                );
                if ($replay !== null) {
                    return $replay;
                }
                $finish = function (array $result) use ($pdo, $keyHash): array {
                    $this->completeOtpMutationReceipt($pdo, $keyHash, $result);
                    return $result;
                };
                $sql =
                    'SELECT user_id, phone_e164, code_hash, attempts, max_attempts,
                            expires_at, consumed_at
                     FROM phone_enrollment_challenges
                     WHERE request_id = :request';
                if (!$this->database->isSqlite()) {
                    $sql .= ' FOR UPDATE';
                }
                $statement = $pdo->prepare($sql);
                $statement->execute(['request' => $requestIdValue]);
                $challenge = $statement->fetch();
                if (!is_array($challenge) || (int) $challenge['user_id'] !== $userId) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }
                if ($challenge['consumed_at'] !== null) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }
                if (
                    strtotime((string) $challenge['expires_at']) <= time() ||
                    (int) $challenge['attempts'] >= (int) $challenge['max_attempts']) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }

                $matches = hash_equals(
                    (string) $challenge['code_hash'],
                    $this->crypto->otpHash($requestIdValue, $codeValue),
                );
                $update = $pdo->prepare(
                    $matches
                        ? 'UPDATE phone_enrollment_challenges
                           SET attempts = attempts + 1, consumed_at = CURRENT_TIMESTAMP
                           WHERE request_id = :request'
                        : 'UPDATE phone_enrollment_challenges
                           SET attempts = attempts + 1 WHERE request_id = :request'
                );
                $update->execute(['request' => $requestIdValue]);
                if (!$matches) {
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }

                $claimed = $pdo->prepare(
                    'SELECT id FROM users WHERE phone_e164 = :phone AND id <> :user LIMIT 1'
                );
                $claimed->execute([
                    'phone' => $challenge['phone_e164'],
                    'user' => $userId,
                ]);
                if ($claimed->fetchColumn() !== false) {
                    return $finish($this->otpErrorOutcome(
                        409,
                        'phone_already_in_use',
                        'This phone number belongs to another account.',
                    ));
                }
                $attach = $pdo->prepare(
                    'UPDATE users SET phone_e164 = :phone, updated_at = CURRENT_TIMESTAMP
                     WHERE id = :user'
                );
                try {
                    $attach->execute([
                        'phone' => $challenge['phone_e164'],
                        'user' => $userId,
                    ]);
                } catch (PDOException $exception) {
                    if ((string) $exception->getCode() !== '23000') {
                        throw $exception;
                    }
                    return $finish($this->otpErrorOutcome(
                        409,
                        'phone_already_in_use',
                        'This phone number belongs to another account.',
                    ));
                }
                if ($attach->rowCount() !== 1) {
                    return $finish($this->otpErrorOutcome(
                        404,
                        'user_not_found',
                        'User not found.',
                    ));
                }
                $result = Presenter::user($this->users->loadById($userId), true);
                return $finish(['kind' => 'success', 'result' => $result]);
        });
        return $this->resolveOtpMutationOutcome($outcome);
    }

    private function ensureEnabled(): void
    {
        if ($this->config->otpDriver === 'disabled') {
            throw new ApiException(
                503,
                'auth_provider_unavailable',
                'Phone authentication is temporarily unavailable.',
            );
        }
    }
}
