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

final class EmailOtpService
{
    use OtpMutationReceipts;

    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly RateLimiter $rateLimiter,
        private readonly EmailSender $emailSender,
        private readonly UserService $users,
        private readonly SessionService $sessions,
        private readonly Config $config,
    ) {
    }

    /** @return array<string, mixed> */
    public function request(mixed $emailValue, string $clientIp): array
    {
        $this->ensureEnabled();
        $email = EmailAddress::normalize($emailValue);
        $this->rateLimiter->consume('email-address:' . $email, $this->config->otpEmailRequestsPerHour, 3600);
        $this->rateLimiter->consume('email-request-ip:' . $clientIp, $this->config->otpIpRequestsPerHour, 3600);

        $requestedUser = $this->users->findByEmail($email);
        $requestId = bin2hex(random_bytes(16));
        $code = (string) random_int(100000, 999999);
        $expires = (new DateTimeImmutable('now'))->modify(sprintf('+%d seconds', $this->config->otpTtlSeconds));
        $statement = $this->database->connection()->prepare(
            'INSERT INTO email_otp_challenges
                (request_id, user_id, email_address, code_hash, max_attempts, expires_at)
             VALUES (:request, :user, :email, :hash, :max, :expires)'
        );
        $statement->execute([
            'request' => $requestId,
            'user' => $requestedUser['id'] ?? null,
            'email' => $email,
            'hash' => $this->crypto->otpHash($requestId, $code),
            'max' => $this->config->otpMaxAttempts,
            'expires' => $expires->format('Y-m-d H:i:s'),
        ]);

        try {
            $this->emailSender->sendOtp($email, $code);
        } catch (Throwable $exception) {
            $invalidate = $this->database->connection()->prepare(
                'UPDATE email_otp_challenges SET consumed_at = CURRENT_TIMESTAMP WHERE request_id = :request'
            );
            $invalidate->execute(['request' => $requestId]);
            error_log('Email OTP delivery failed (' . get_class($exception) . ').');
            throw new ApiException(502, 'email_delivery_failed', 'The verification code could not be sent. Please try again.');
        }

        $response = ['requestId' => $requestId, 'expiresIn' => $this->config->otpTtlSeconds];
        if (!$this->config->isProduction() && $this->config->emailDevExpose) {
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
        $operation = 'email_login_verification';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->crypto->hashOpaque('email-otp-verification:' . $idempotencyKey);
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
        $this->rateLimiter->consume('email-otp-verify-ip:' . $clientIp, $this->config->otpVerifyAttemptsPerHour, 3600);

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
                    'SELECT user_id, email_address, code_hash, attempts, max_attempts,
                            expires_at, consumed_at
                     FROM email_otp_challenges WHERE request_id = :request' .
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
                        'UPDATE email_otp_challenges
                         SET attempts = attempts + 1 WHERE request_id = :request'
                    );
                    $update->execute(['request' => $requestIdValue]);
                    return $finish($this->otpErrorOutcome(
                        422,
                        'invalid_otp',
                        'The verification code is invalid or expired.',
                    ));
                }

                // Lock the bound account while checking its current address.
                // A code sent before an address change must never sign into an
                // account that later claims that address, even under concurrency.
                $bound = $pdo->prepare(
                    'SELECT id, email_address, email_verified_at FROM users WHERE id = :user' .
                    ($this->database->isSqlite() ? '' : ' FOR UPDATE')
                );
                $bound->execute(['user' => $challenge['user_id']]);
                $boundUser = $bound->fetch();
                if (!is_array($boundUser) || $boundUser['email_verified_at'] === null ||
                    (string) $boundUser['email_address'] !== (string) $challenge['email_address']) {
                    $consume = $pdo->prepare(
                        'UPDATE email_otp_challenges
                         SET attempts = attempts + 1, consumed_at = CURRENT_TIMESTAMP
                         WHERE request_id = :request'
                    );
                    $consume->execute(['request' => $requestIdValue]);
                    return $finish($this->otpErrorOutcome(
                        404,
                        'account_not_found',
                        'No existing account is enrolled with this email address.',
                    ));
                }

                $user = $this->users->loadById((int) $boundUser['id']);
                $session = $this->sessions->issueWithConnection($pdo, (int) $user['id']);
                $result = [
                    'token' => $session['token'],
                    'tokenType' => 'Bearer',
                    'expiresAt' => $session['expiresAt'],
                    'user' => Presenter::user($user, true),
                ];
                $consume = $pdo->prepare(
                    'UPDATE email_otp_challenges
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
    public function requestEnrollment(int $userId, mixed $emailValue, string $clientIp): array
    {
        $this->ensureEnabled();
        $email = EmailAddress::normalize($emailValue);
        $user = $this->users->loadById($userId);
        $this->rateLimiter->consume(
            'email-enrollment-user:' . $userId,
            $this->config->otpEmailRequestsPerHour,
            3600,
        );
        $this->rateLimiter->consume(
            'email-address:' . $email,
            $this->config->otpEmailRequestsPerHour,
            3600,
        );
        $this->rateLimiter->consume(
            'email-request-ip:' . $clientIp,
            $this->config->otpIpRequestsPerHour,
            3600,
        );
        if ((string) ($user['email_address'] ?? '') === $email) {
            throw new ApiException(409, 'email_already_enrolled', 'This email address is already enrolled.');
        }
        $existing = $this->users->findByEmail($email);
        if ($existing !== null && (int) $existing['id'] !== $userId) {
            throw new ApiException(409, 'email_already_in_use', 'This email address belongs to another account.');
        }

        $requestId = bin2hex(random_bytes(16));
        $code = (string) random_int(100000, 999999);
        $expires = (new DateTimeImmutable('now'))
            ->modify(sprintf('+%d seconds', $this->config->otpTtlSeconds));
        $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $requestId,
            $email,
            $code,
            $expires,
        ): void {
            $invalidate = $pdo->prepare(
                'UPDATE email_enrollment_challenges
                 SET consumed_at = CURRENT_TIMESTAMP
                 WHERE user_id = :user AND consumed_at IS NULL'
            );
            $invalidate->execute(['user' => $userId]);
            $insert = $pdo->prepare(
                'INSERT INTO email_enrollment_challenges
                    (user_id, request_id, email_address, code_hash, max_attempts, expires_at)
                 VALUES (:user, :request, :email, :hash, :max, :expires)'
            );
            $insert->execute([
                'user' => $userId,
                'request' => $requestId,
                'email' => $email,
                'hash' => $this->crypto->otpHash($requestId, $code),
                'max' => $this->config->otpMaxAttempts,
                'expires' => $expires->format('Y-m-d H:i:s'),
            ]);
        });

        try {
            $this->emailSender->sendOtp($email, $code);
        } catch (Throwable $exception) {
            $invalidate = $this->database->connection()->prepare(
                'UPDATE email_enrollment_challenges
                 SET consumed_at = CURRENT_TIMESTAMP WHERE request_id = :request'
            );
            $invalidate->execute(['request' => $requestId]);
            error_log('Email enrollment delivery failed (' . get_class($exception) . ').');
            throw new ApiException(
                502,
                'email_delivery_failed',
                'The verification code could not be sent. Please try again.',
            );
        }

        $response = ['requestId' => $requestId, 'expiresIn' => $this->config->otpTtlSeconds];
        if (!$this->config->isProduction() && $this->config->emailDevExpose) {
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
        $operation = 'email_enrollment_verification';
        $keyHash = $idempotencyKey === null
            ? null
            : $this->crypto->hashOpaque('email-enrollment-verification:' . $idempotencyKey);
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
            'email-enrollment-verify-ip:' . $clientIp,
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
                    'SELECT user_id, email_address, code_hash, attempts, max_attempts,
                            expires_at, consumed_at
                     FROM email_enrollment_challenges
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
                        ? 'UPDATE email_enrollment_challenges
                           SET attempts = attempts + 1, consumed_at = CURRENT_TIMESTAMP
                           WHERE request_id = :request'
                        : 'UPDATE email_enrollment_challenges
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
                    'SELECT id FROM users WHERE email_address = :email AND id <> :user LIMIT 1'
                );
                $claimed->execute([
                    'email' => $challenge['email_address'],
                    'user' => $userId,
                ]);
                if ($claimed->fetchColumn() !== false) {
                    return $finish($this->otpErrorOutcome(
                        409,
                        'email_already_in_use',
                        'This email address belongs to another account.',
                    ));
                }
                $attach = $pdo->prepare(
                    'UPDATE users SET email_address = :email, email_verified_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                     WHERE id = :user'
                );
                try {
                    $attach->execute([
                        'email' => $challenge['email_address'],
                        'user' => $userId,
                    ]);
                } catch (PDOException $exception) {
                    if ((string) $exception->getCode() !== '23000') {
                        throw $exception;
                    }
                    return $finish($this->otpErrorOutcome(
                        409,
                        'email_already_in_use',
                        'This email address belongs to another account.',
                    ));
                }
                if ($attach->rowCount() !== 1) {
                    return $finish($this->otpErrorOutcome(
                        404,
                        'user_not_found',
                        'User not found.',
                    ));
                }
                $invalidateLogin = $pdo->prepare(
                    'UPDATE email_otp_challenges SET consumed_at = CURRENT_TIMESTAMP
                     WHERE user_id = :user AND consumed_at IS NULL'
                );
                $invalidateLogin->execute(['user' => $userId]);
                $result = Presenter::user($this->users->loadById($userId), true);
                return $finish(['kind' => 'success', 'result' => $result]);
        });
        return $this->resolveOtpMutationOutcome($outcome);
    }

    private function ensureEnabled(): void
    {
        if ($this->config->emailDriver === 'disabled') {
            throw new ApiException(
                503,
                'auth_provider_unavailable',
                'Email authentication is temporarily unavailable.',
            );
        }
    }
}
