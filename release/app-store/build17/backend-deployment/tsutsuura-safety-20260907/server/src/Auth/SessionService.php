<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use DateTimeImmutable;
use PDO;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Http\Request;
use Tsutsuura\Server\Security\Crypto;

final class SessionService
{
    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly Config $config,
    ) {
    }

    /** @return array{token: string, expiresAt: string} */
    public function issue(int $userId): array
    {
        return $this->issueWithConnection($this->database->connection(), $userId);
    }

    /** @return array{token: string, expiresAt: string} */
    public function issueWithConnection(PDO $pdo, int $userId): array
    {
        $token = $this->crypto->randomToken(32);
        $now = new DateTimeImmutable('now');
        $expiresAt = $now->modify(sprintf('+%d days', $this->config->sessionTtlDays));
        $statement = $pdo->prepare(
            'INSERT INTO sessions (user_id, token_hash, expires_at, last_used_at)
             VALUES (:user, :hash, :expires, :now)'
        );
        $statement->execute([
            'user' => $userId,
            'hash' => $this->crypto->hashOpaque($token),
            'expires' => $expiresAt->format('Y-m-d H:i:s'),
            'now' => $now->format('Y-m-d H:i:s'),
        ]);
        return ['token' => $token, 'expiresAt' => $expiresAt->format(DATE_ATOM)];
    }

    /** @return array<string, mixed> */
    public function requireUser(Request $request): array
    {
        $token = $request->bearerToken();
        if ($token === null) {
            throw new ApiException(401, 'authentication_required', 'A valid bearer token is required.');
        }
        $statement = $this->database->connection()->prepare(
            'SELECT u.id, u.phone_e164, u.email_address, u.email_verified_at, u.display_name, u.avatar_url, u.avatar_mark, u.created_at,
                    s.id AS session_id,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM sessions s
             JOIN users u ON u.id = s.user_id
             LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE s.token_hash = :hash
               AND s.revoked_at IS NULL
               AND s.expires_at > CURRENT_TIMESTAMP
             LIMIT 1'
        );
        $statement->execute(['hash' => $this->crypto->hashOpaque($token)]);
        $user = $statement->fetch();
        if (!is_array($user)) {
            throw new ApiException(401, 'invalid_session', 'The session is invalid or expired.');
        }
        $touch = $this->database->connection()->prepare($this->database->isSqlite()
            ? "UPDATE sessions SET last_used_at = CURRENT_TIMESTAMP
               WHERE id = :id AND last_used_at < datetime(CURRENT_TIMESTAMP, '-5 minutes')"
            : 'UPDATE sessions SET last_used_at = CURRENT_TIMESTAMP
               WHERE id = :id AND last_used_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 5 MINUTE)'
        );
        $touch->execute(['id' => $user['session_id']]);
        return $user;
    }

    public function revoke(Request $request): void
    {
        $token = $request->bearerToken();
        if ($token === null) {
            throw new ApiException(401, 'authentication_required', 'A valid bearer token is required.');
        }
        $tokenHash = $this->crypto->hashOpaque($token);
        $this->database->transaction(function (PDO $pdo) use ($tokenHash): void {
            $sql =
                'SELECT id, user_id FROM sessions
                 WHERE token_hash = :hash
                   AND revoked_at IS NULL
                 LIMIT 1';
            if (!$this->database->isSqlite()) {
                $sql .= ' FOR UPDATE';
            }
            $lookup = $pdo->prepare($sql);
            $lookup->execute(['hash' => $tokenHash]);
            $session = $lookup->fetch();
            if (!is_array($session)) {
                return;
            }
            // Expiry remains an authorization boundary in requireUser().
            // Logout is deliberately narrower: possession of the exact,
            // still-stored bearer may only revoke that session and remove the
            // push registrations owned by its resolved user. Keeping expiry
            // out of this lookup prevents an expired device from continuing
            // to receive family content after its local bearer is cleared.
            // Push registrations represent devices rather than sessions. On
            // logout, removing every registration for this account is safer
            // than allowing a handed-over device to receive family content.
            $deletePush = $pdo->prepare('DELETE FROM push_tokens WHERE user_id = :user');
            $deletePush->execute(['user' => $session['user_id']]);
            $revoke = $pdo->prepare(
                'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP
                 WHERE id = :session AND revoked_at IS NULL'
            );
            $revoke->execute(['session' => $session['id']]);
        });
    }
}
