<?php
declare(strict_types=1);

use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$basePath = dirname(__DIR__);
$config = Config::fromEnvironment($basePath);
$pdo = (new Database($config))->connection();
$pdo->exec($config->dbConnection === 'sqlite'
    ? 'CREATE TABLE IF NOT EXISTS schema_migrations (
         version TEXT NOT NULL PRIMARY KEY,
         applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
       )'
    : 'CREATE TABLE IF NOT EXISTS schema_migrations (
         version VARCHAR(100) NOT NULL PRIMARY KEY,
         applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
       ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
);

$migrationDirectory = $config->dbConnection === 'sqlite'
    ? $basePath . '/migrations/sqlite'
    : $basePath . '/migrations/mysql';
$files = glob($migrationDirectory . '/*.sql') ?: [];
sort($files, SORT_STRING);
foreach ($files as $file) {
    $version = basename($file);
    $check = $pdo->prepare('SELECT 1 FROM schema_migrations WHERE version = :version');
    $check->execute(['version' => $version]);
    if ($check->fetchColumn()) {
        // Migration 007 is deliberately reconciled element-by-element even
        // after its ledger row exists. Earlier deployments may have recorded
        // an older revision of this additive migration while the application
        // was still under QA; this repairs any missing column, table, or index
        // without replaying destructive data work.
        if ($version === '007_idempotent_mutations.sql') {
            applyIdempotentMutationMigration($pdo, $config->dbConnection);
            echo "skip {$version} (schema reconciled)\n";
        } else {
            echo "skip {$version}\n";
        }
        continue;
    }
    $sql = file_get_contents($file);
    if ($sql === false) {
        throw new RuntimeException("Cannot read {$file}");
    }
    // Migration 004 begins with an ALTER TABLE. MySQL commits DDL implicitly
    // and SQLite may have completed that statement before an interrupted
    // multi-statement exec. Resume after the already-present column.
    if ($version === '004_lifecycle.sql' && hasColumn($pdo, $config->dbConnection, 'comments', 'parent_comment_id')) {
        $sql = preg_replace('/\A\s*ALTER TABLE comments.*?;\s*/s', '', $sql, 1) ?? $sql;
    }
    // Migration 007 contains several ALTER statements. Apply every schema
    // element independently so an interrupted SQLite or implicitly committed
    // MySQL run can resume without a duplicate-column/index failure.
    if ($version === '007_idempotent_mutations.sql') {
        applyIdempotentMutationMigration($pdo, $config->dbConnection);
    } else {
        // DDL implicitly commits in MySQL, so record only after the complete
        // file succeeds.
        $pdo->exec($sql);
    }
    $insert = $pdo->prepare('INSERT INTO schema_migrations (version) VALUES (:version)');
    $insert->execute(['version' => $version]);
    echo "applied {$version}\n";
}

if (in_array('--seed', $argv, true)) {
    $seedFiles = glob($basePath . '/seeds/*.sql') ?: [];
    sort($seedFiles, SORT_STRING);
    foreach ($seedFiles as $file) {
        $count = (int) $pdo->query('SELECT COUNT(*) FROM questions')->fetchColumn();
        if ($count > 0) {
            echo 'skip ' . basename($file) . " (questions already exist)\n";
            continue;
        }
        $sql = file_get_contents($file);
        if ($sql === false) {
            throw new RuntimeException("Cannot read {$file}");
        }
        $pdo->exec($sql);
        echo 'seeded ' . basename($file) . "\n";
    }
}

function hasColumn(PDO $pdo, string $connection, string $table, string $column): bool
{
    if ($connection === 'sqlite') {
        foreach ($pdo->query('PRAGMA table_info(' . $table . ')')->fetchAll() as $row) {
            if ((string) $row['name'] === $column) {
                return true;
            }
        }
        return false;
    }
    $statement = $pdo->prepare(
        'SELECT 1 FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table AND COLUMN_NAME = :column
         LIMIT 1'
    );
    $statement->execute(['table' => $table, 'column' => $column]);
    return $statement->fetchColumn() !== false;
}

function hasTable(PDO $pdo, string $connection, string $table): bool
{
    if ($connection === 'sqlite') {
        $statement = $pdo->prepare(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = :table LIMIT 1"
        );
    } else {
        $statement = $pdo->prepare(
            'SELECT 1 FROM information_schema.TABLES
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table LIMIT 1'
        );
    }
    $statement->execute(['table' => $table]);
    return $statement->fetchColumn() !== false;
}

function hasIndex(PDO $pdo, string $connection, string $table, string $index): bool
{
    if ($connection === 'sqlite') {
        foreach ($pdo->query('PRAGMA index_list(' . $table . ')')->fetchAll() as $row) {
            if ((string) $row['name'] === $index) {
                return true;
            }
        }
        return false;
    }
    $statement = $pdo->prepare(
        'SELECT 1 FROM information_schema.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table
           AND INDEX_NAME = :index_name LIMIT 1'
    );
    $statement->execute(['table' => $table, 'index_name' => $index]);
    return $statement->fetchColumn() !== false;
}

function addColumnIfMissing(
    PDO $pdo,
    string $connection,
    string $table,
    string $column,
    string $definition,
): void {
    if (!hasColumn($pdo, $connection, $table, $column)) {
        $pdo->exec(sprintf(
            'ALTER TABLE %s ADD COLUMN %s %s',
            $table,
            $column,
            $definition,
        ));
    }
}

/** @param array<string, string> $definitions */
function addColumnsIfMissing(
    PDO $pdo,
    string $connection,
    string $table,
    array $definitions,
): void {
    foreach ($definitions as $column => $definition) {
        addColumnIfMissing(
            $pdo,
            $connection,
            $table,
            $column,
            $definition,
        );
    }
}

function applyIdempotentMutationMigration(PDO $pdo, string $connection): void
{
    if ($connection === 'sqlite') {
        addColumnIfMissing($pdo, $connection, 'device_pairings', 'activation_key_hash', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'device_pairings', 'activation_response_encrypted', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'device_pairings', 'activation_replay_expires_at', 'TEXT NULL');
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS device_pairings_activation_key_unique
             ON device_pairings (activation_key_hash)
             WHERE activation_key_hash IS NOT NULL'
        );

        addColumnIfMissing($pdo, $connection, 'device_recovery_codes', 'redemption_key_hash', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'device_recovery_codes', 'redemption_response_encrypted', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'device_recovery_codes', 'redemption_replay_expires_at', 'TEXT NULL');
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS device_recovery_redemption_key_unique
             ON device_recovery_codes (redemption_key_hash)
             WHERE redemption_key_hash IS NOT NULL'
        );

        addColumnIfMissing($pdo, $connection, 'phone_otp_challenges', 'verification_key_hash', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'phone_otp_challenges', 'verification_response_encrypted', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'phone_otp_challenges', 'verification_replay_expires_at', 'TEXT NULL');
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS phone_otp_verification_key_unique
             ON phone_otp_challenges (verification_key_hash)
             WHERE verification_key_hash IS NOT NULL'
        );

        addColumnIfMissing($pdo, $connection, 'phone_enrollment_challenges', 'verification_key_hash', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'phone_enrollment_challenges', 'verification_response_encrypted', 'TEXT NULL');
        addColumnIfMissing($pdo, $connection, 'phone_enrollment_challenges', 'verification_replay_expires_at', 'TEXT NULL');
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS phone_enrollment_verification_key_unique
             ON phone_enrollment_challenges (verification_key_hash)
             WHERE verification_key_hash IS NOT NULL'
        );

        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS comment_mutation_receipts (
                key_hash TEXT NOT NULL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                request_fingerprint TEXT NOT NULL,
                response_encrypted TEXT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
             )'
        );
        addColumnsIfMissing($pdo, $connection, 'comment_mutation_receipts', [
            'key_hash' => 'TEXT NULL',
            'user_id' => 'INTEGER NULL',
            'request_fingerprint' => 'TEXT NULL',
            'response_encrypted' => 'TEXT NULL',
            'expires_at' => 'TEXT NULL',
            'created_at' => 'TEXT NULL',
        ]);
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS comment_mutation_receipts_key_unique
             ON comment_mutation_receipts (key_hash)'
        );
        $pdo->exec(
            'CREATE INDEX IF NOT EXISTS comment_mutation_receipts_expiry_index
             ON comment_mutation_receipts (expires_at)'
        );
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS setup_mutation_receipts (
                key_hash TEXT NOT NULL PRIMARY KEY,
                operation TEXT NOT NULL,
                actor_user_id INTEGER NULL,
                request_fingerprint TEXT NOT NULL,
                response_encrypted TEXT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
             )'
        );
        addColumnsIfMissing($pdo, $connection, 'setup_mutation_receipts', [
            'key_hash' => 'TEXT NULL',
            'operation' => 'TEXT NULL',
            'actor_user_id' => 'INTEGER NULL',
            'request_fingerprint' => 'TEXT NULL',
            'response_encrypted' => 'TEXT NULL',
            'expires_at' => 'TEXT NULL',
            'created_at' => 'TEXT NULL',
        ]);
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS setup_mutation_receipts_key_unique
             ON setup_mutation_receipts (key_hash)'
        );
        $pdo->exec(
            'CREATE INDEX IF NOT EXISTS setup_mutation_receipts_expiry_index
             ON setup_mutation_receipts (expires_at)'
        );
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS otp_mutation_receipts (
                key_hash TEXT NOT NULL PRIMARY KEY,
                operation TEXT NOT NULL,
                actor_user_id INTEGER NULL,
                request_fingerprint TEXT NOT NULL,
                outcome_encrypted TEXT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
             )'
        );
        addColumnsIfMissing($pdo, $connection, 'otp_mutation_receipts', [
            'key_hash' => 'TEXT NULL',
            'operation' => 'TEXT NULL',
            'actor_user_id' => 'INTEGER NULL',
            'request_fingerprint' => 'TEXT NULL',
            'outcome_encrypted' => 'TEXT NULL',
            'expires_at' => 'TEXT NULL',
            'created_at' => 'TEXT NULL',
        ]);
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS otp_mutation_receipts_key_unique
             ON otp_mutation_receipts (key_hash)'
        );
        $pdo->exec(
            'CREATE INDEX IF NOT EXISTS otp_mutation_receipts_expiry_index
             ON otp_mutation_receipts (expires_at)'
        );
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS lifecycle_mutation_receipts (
                key_hash TEXT NOT NULL PRIMARY KEY,
                operation TEXT NOT NULL,
                result_json TEXT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
             )'
        );
        addColumnsIfMissing($pdo, $connection, 'lifecycle_mutation_receipts', [
            'key_hash' => 'TEXT NULL',
            'operation' => 'TEXT NULL',
            'result_json' => 'TEXT NULL',
            'created_at' => 'TEXT NULL',
        ]);
        $pdo->exec(
            'CREATE UNIQUE INDEX IF NOT EXISTS lifecycle_mutation_receipts_key_unique
             ON lifecycle_mutation_receipts (key_hash)'
        );
        return;
    }

    addColumnIfMissing(
        $pdo,
        $connection,
        'device_pairings',
        'activation_key_hash',
        'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
    );
    addColumnIfMissing($pdo, $connection, 'device_pairings', 'activation_response_encrypted', 'TEXT NULL');
    addColumnIfMissing($pdo, $connection, 'device_pairings', 'activation_replay_expires_at', 'DATETIME NULL');
    if (!hasIndex($pdo, $connection, 'device_pairings', 'device_pairings_activation_key_unique')) {
        $pdo->exec(
            'ALTER TABLE device_pairings
             ADD UNIQUE KEY device_pairings_activation_key_unique (activation_key_hash)'
        );
    }

    addColumnIfMissing(
        $pdo,
        $connection,
        'device_recovery_codes',
        'redemption_key_hash',
        'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
    );
    addColumnIfMissing($pdo, $connection, 'device_recovery_codes', 'redemption_response_encrypted', 'TEXT NULL');
    addColumnIfMissing($pdo, $connection, 'device_recovery_codes', 'redemption_replay_expires_at', 'DATETIME NULL');
    if (!hasIndex($pdo, $connection, 'device_recovery_codes', 'device_recovery_redemption_key_unique')) {
        $pdo->exec(
            'ALTER TABLE device_recovery_codes
             ADD UNIQUE KEY device_recovery_redemption_key_unique (redemption_key_hash)'
        );
    }

    addColumnIfMissing(
        $pdo,
        $connection,
        'phone_otp_challenges',
        'verification_key_hash',
        'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
    );
    addColumnIfMissing($pdo, $connection, 'phone_otp_challenges', 'verification_response_encrypted', 'TEXT NULL');
    addColumnIfMissing($pdo, $connection, 'phone_otp_challenges', 'verification_replay_expires_at', 'DATETIME NULL');
    if (!hasIndex($pdo, $connection, 'phone_otp_challenges', 'phone_otp_verification_key_unique')) {
        $pdo->exec(
            'ALTER TABLE phone_otp_challenges
             ADD UNIQUE KEY phone_otp_verification_key_unique (verification_key_hash)'
        );
    }

    addColumnIfMissing(
        $pdo,
        $connection,
        'phone_enrollment_challenges',
        'verification_key_hash',
        'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
    );
    addColumnIfMissing($pdo, $connection, 'phone_enrollment_challenges', 'verification_response_encrypted', 'TEXT NULL');
    addColumnIfMissing($pdo, $connection, 'phone_enrollment_challenges', 'verification_replay_expires_at', 'DATETIME NULL');
    if (!hasIndex($pdo, $connection, 'phone_enrollment_challenges', 'phone_enrollment_verification_key_unique')) {
        $pdo->exec(
            'ALTER TABLE phone_enrollment_challenges
             ADD UNIQUE KEY phone_enrollment_verification_key_unique (verification_key_hash)'
        );
    }

    if (!hasTable($pdo, $connection, 'comment_mutation_receipts')) {
        $pdo->exec(
            'CREATE TABLE comment_mutation_receipts (
                key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                response_encrypted TEXT NULL,
                expires_at DATETIME NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY comment_mutation_receipts_expiry_index (expires_at),
                CONSTRAINT comment_mutation_receipts_user_fk
                    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
             ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
        );
    }
    addColumnsIfMissing($pdo, $connection, 'comment_mutation_receipts', [
        'key_hash' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'user_id' => 'BIGINT UNSIGNED NULL',
        'request_fingerprint' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'response_encrypted' => 'TEXT NULL',
        'expires_at' => 'DATETIME NULL',
        'created_at' => 'DATETIME NULL',
    ]);
    if (!hasIndex(
        $pdo,
        $connection,
        'comment_mutation_receipts',
        'comment_mutation_receipts_expiry_index',
    )) {
        $pdo->exec(
            'ALTER TABLE comment_mutation_receipts
             ADD KEY comment_mutation_receipts_expiry_index (expires_at)'
        );
    }
    if (!hasIndex(
        $pdo,
        $connection,
        'comment_mutation_receipts',
        'comment_mutation_receipts_key_unique',
    )) {
        $pdo->exec(
            'ALTER TABLE comment_mutation_receipts
             ADD UNIQUE KEY comment_mutation_receipts_key_unique (key_hash)'
        );
    }

    if (!hasTable($pdo, $connection, 'setup_mutation_receipts')) {
        $pdo->exec(
            'CREATE TABLE setup_mutation_receipts (
                key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
                operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                actor_user_id BIGINT UNSIGNED NULL,
                request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                response_encrypted TEXT NULL,
                expires_at DATETIME NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY setup_mutation_receipts_expiry_index (expires_at),
                CONSTRAINT setup_mutation_receipts_actor_fk
                    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
             ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
        );
    }
    addColumnsIfMissing($pdo, $connection, 'setup_mutation_receipts', [
        'key_hash' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'operation' => 'VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'actor_user_id' => 'BIGINT UNSIGNED NULL',
        'request_fingerprint' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'response_encrypted' => 'TEXT NULL',
        'expires_at' => 'DATETIME NULL',
        'created_at' => 'DATETIME NULL',
    ]);
    if (!hasIndex(
        $pdo,
        $connection,
        'setup_mutation_receipts',
        'setup_mutation_receipts_expiry_index',
    )) {
        $pdo->exec(
            'ALTER TABLE setup_mutation_receipts
             ADD KEY setup_mutation_receipts_expiry_index (expires_at)'
        );
    }
    if (!hasIndex(
        $pdo,
        $connection,
        'setup_mutation_receipts',
        'setup_mutation_receipts_key_unique',
    )) {
        $pdo->exec(
            'ALTER TABLE setup_mutation_receipts
             ADD UNIQUE KEY setup_mutation_receipts_key_unique (key_hash)'
        );
    }

    if (!hasTable($pdo, $connection, 'lifecycle_mutation_receipts')) {
        $pdo->exec(
            'CREATE TABLE lifecycle_mutation_receipts (
                key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
                operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                result_json TEXT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
             ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
        );
    }
    addColumnsIfMissing($pdo, $connection, 'lifecycle_mutation_receipts', [
        'key_hash' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'operation' => 'VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'result_json' => 'TEXT NULL',
        'created_at' => 'DATETIME NULL',
    ]);
    if (!hasIndex(
        $pdo,
        $connection,
        'lifecycle_mutation_receipts',
        'lifecycle_mutation_receipts_key_unique',
    )) {
        $pdo->exec(
            'ALTER TABLE lifecycle_mutation_receipts
             ADD UNIQUE KEY lifecycle_mutation_receipts_key_unique (key_hash)'
        );
    }

    if (!hasTable($pdo, $connection, 'otp_mutation_receipts')) {
        $pdo->exec(
            'CREATE TABLE otp_mutation_receipts (
                key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
                operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                actor_user_id BIGINT UNSIGNED NULL,
                request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                outcome_encrypted TEXT NULL,
                expires_at DATETIME NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY otp_mutation_receipts_expiry_index (expires_at),
                CONSTRAINT otp_mutation_receipts_actor_fk
                    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
             ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
        );
    }
    addColumnsIfMissing($pdo, $connection, 'otp_mutation_receipts', [
        'key_hash' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'operation' => 'VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'actor_user_id' => 'BIGINT UNSIGNED NULL',
        'request_fingerprint' => 'CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL',
        'outcome_encrypted' => 'TEXT NULL',
        'expires_at' => 'DATETIME NULL',
        'created_at' => 'DATETIME NULL',
    ]);
    if (!hasIndex(
        $pdo,
        $connection,
        'otp_mutation_receipts',
        'otp_mutation_receipts_expiry_index',
    )) {
        $pdo->exec(
            'ALTER TABLE otp_mutation_receipts
             ADD KEY otp_mutation_receipts_expiry_index (expires_at)'
        );
    }
    if (!hasIndex(
        $pdo,
        $connection,
        'otp_mutation_receipts',
        'otp_mutation_receipts_key_unique',
    )) {
        $pdo->exec(
            'ALTER TABLE otp_mutation_receipts
             ADD UNIQUE KEY otp_mutation_receipts_key_unique (key_hash)'
        );
    }
}
