<?php
declare(strict_types=1);

namespace Tsutsuura\Server;

use PDO;
use PDOException;
use RuntimeException;
use Throwable;

final class Database
{
    // SQLite's SQLITE_DETERMINISTIC flag. The legacy PDO constant is
    // deprecated in PHP 8.5 and Pdo\Sqlite is unavailable before PHP 8.4.
    private const SQLITE_DETERMINISTIC = 2_048;

    private ?PDO $pdo = null;

    public function __construct(private readonly Config $config)
    {
    }

    public function connection(): PDO
    {
        if ($this->pdo instanceof PDO) {
            return $this->pdo;
        }

        if ($this->isSqlite()) {
            $directory = dirname($this->config->dbName);
            if (!is_dir($directory) || !is_writable($directory)) {
                throw new RuntimeException('SQLite database directory does not exist or is not writable.');
            }
            $dsn = 'sqlite:' . $this->config->dbName;
        } else {
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $this->config->dbHost,
                $this->config->dbPort,
                $this->config->dbName,
            );
        }
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_STRINGIFY_FETCHES => false,
        ];
        if (!$this->isSqlite() && $this->config->dbSslCa !== null && defined('PDO::MYSQL_ATTR_SSL_CA')) {
            $options[constant('PDO::MYSQL_ATTR_SSL_CA')] = $this->config->dbSslCa;
            if (defined('PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT')) {
                $options[constant('PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT')] = true;
            }
        }

        try {
            $this->pdo = $this->isSqlite() && class_exists(\Pdo\Sqlite::class)
                ? new \Pdo\Sqlite($dsn, null, null, $options)
                : new PDO(
                    $dsn,
                    $this->isSqlite() ? null : $this->config->dbUser,
                    $this->isSqlite() ? null : $this->config->dbPassword,
                    $options,
                );
            if ($this->isSqlite()) {
                $this->pdo->exec('PRAGMA foreign_keys = ON');
                $this->pdo->exec('PRAGMA journal_mode = WAL');
                $this->pdo->exec('PRAGMA synchronous = NORMAL');
                $this->pdo->exec('PRAGMA busy_timeout = 5000');
                $registered = method_exists($this->pdo, 'createFunction')
                    ? $this->pdo->createFunction(
                        'tsutsuura_search_fold',
                        self::sqliteSearchFold(...),
                        1,
                        self::SQLITE_DETERMINISTIC,
                    )
                    : $this->pdo->sqliteCreateFunction(
                        'tsutsuura_search_fold',
                        self::sqliteSearchFold(...),
                        1,
                        self::SQLITE_DETERMINISTIC,
                    );
                if (!$registered) {
                    throw new RuntimeException('SQLite search normalization could not be registered.');
                }
            } else {
                $this->pdo->exec("SET time_zone = '+00:00'");
                $this->pdo->exec("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'");
            }
        } catch (PDOException $exception) {
            throw new RuntimeException('Database connection failed.', previous: $exception);
        }
        return $this->pdo;
    }

    public function isSqlite(): bool
    {
        return $this->config->dbConnection === 'sqlite';
    }

    /** Match the app's case- and diacritic-insensitive history search. */
    private static function sqliteSearchFold(?string $value): string
    {
        $folded = mb_convert_case($value ?? '', MB_CASE_FOLD, 'UTF-8');
        $decomposed = \Normalizer::normalize($folded, \Normalizer::FORM_D);
        if (!is_string($decomposed)) {
            return $folded;
        }
        $withoutMarks = preg_replace('/\p{Mn}+/u', '', $decomposed);
        return is_string($withoutMarks) ? $withoutMarks : $folded;
    }

    /** @template T */
    public function transaction(callable $callback): mixed
    {
        $pdo = $this->connection();
        $attempts = 0;
        beginning:
        $attempts++;
        try {
            // BEGIN can itself lose a race with another SQLite writer or a
            // MySQL deadlock victim. Keep it inside the retry boundary rather
            // than retrying only statements after a transaction has started.
            if ($this->isSqlite()) {
                $pdo->exec('BEGIN IMMEDIATE');
            } else {
                $pdo->beginTransaction();
            }
            $result = $callback($pdo);
            $pdo->commit();
            return $result;
        } catch (Throwable $exception) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            if ($attempts < 3 && $exception instanceof PDOException &&
                (in_array((string) $exception->getCode(), ['40001', '1213'], true) ||
                    str_contains(strtolower($exception->getMessage()), 'database is locked'))) {
                usleep(random_int(10_000, 50_000));
                goto beginning;
            }
            throw $exception;
        }
    }
}
