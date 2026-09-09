<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Security;

use DateTimeImmutable;
use PDO;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;

final class RateLimiter
{
    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
    ) {
    }

    public function consume(string $bucket, int $limit, int $windowSeconds): void
    {
        $key = $this->crypto->hashOpaque('rate:' . $bucket);
        $now = new DateTimeImmutable('now');
        $cutoff = $now->modify(sprintf('-%d seconds', $windowSeconds))->format('Y-m-d H:i:s');
        $nowString = $now->format('Y-m-d H:i:s');

        $count = $this->database->transaction(function (PDO $pdo) use ($key, $cutoff, $nowString): int {
            $sql = $this->database->isSqlite()
                ? 'INSERT INTO rate_limits (bucket_hash, window_started_at, hits, updated_at)
                   VALUES (:bucket, :now_started, 1, :now_updated)
                   ON CONFLICT(bucket_hash) DO UPDATE SET
                     hits = CASE WHEN window_started_at <= :cutoff_hits THEN 1 ELSE hits + 1 END,
                     window_started_at = CASE WHEN window_started_at <= :cutoff_window THEN excluded.window_started_at ELSE window_started_at END,
                     updated_at = excluded.updated_at'
                : 'INSERT INTO rate_limits (bucket_hash, window_started_at, hits, updated_at)
                   VALUES (:bucket, :now_started, 1, :now_updated)
                   ON DUPLICATE KEY UPDATE
                     hits = IF(window_started_at <= :cutoff_hits, 1, hits + 1),
                     window_started_at = IF(window_started_at <= :cutoff_window, VALUES(window_started_at), window_started_at),
                     updated_at = VALUES(updated_at)';
            $statement = $pdo->prepare($sql);
            $statement->execute([
                'bucket' => $key,
                'now_started' => $nowString,
                'now_updated' => $nowString,
                'cutoff_hits' => $cutoff,
                'cutoff_window' => $cutoff,
            ]);
            $select = $pdo->prepare('SELECT hits FROM rate_limits WHERE bucket_hash = :bucket');
            $select->execute(['bucket' => $key]);
            return (int) $select->fetchColumn();
        });

        if ($count > $limit) {
            throw new ApiException(
                429,
                'rate_limited',
                'Too many requests. Please try again later.',
                ['retryAfter' => $windowSeconds],
            );
        }
    }
}
