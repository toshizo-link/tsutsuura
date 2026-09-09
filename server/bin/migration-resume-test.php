<?php
declare(strict_types=1);

date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$suffix = bin2hex(random_bytes(8));
$databasePath = sys_get_temp_dir() . '/tsutsuura-migration-resume-' . $suffix . '.sqlite';
$mediaPath = sys_get_temp_dir() . '/tsutsuura-migration-resume-media-' . $suffix;
if (!mkdir($mediaPath, 0700) && !is_dir($mediaPath)) {
    throw new RuntimeException('Could not create migration test media directory.');
}

$environment = [
    'APP_ENV' => 'testing',
    'APP_DEBUG' => 'false',
    'APP_KEY' => str_repeat('a7', 32),
    'APP_URL' => 'http://localhost',
    'APP_TIMEZONE' => 'UTC',
    'CORS_ALLOWED_ORIGINS' => 'http://localhost:3000',
    'DB_CONNECTION' => 'sqlite',
    'DB_DATABASE' => $databasePath,
    'MEDIA_STORAGE_PATH' => $mediaPath,
    'DB_HOST' => 'localhost',
    'DB_PORT' => '3306',
    'DB_USERNAME' => '',
    'DB_PASSWORD' => '',
    'OTP_DRIVER' => 'disabled',
    'OTP_DEV_EXPOSE' => 'false',
    'PUSH_DRIVER' => 'disabled',
];
foreach ($environment as $key => $value) {
    putenv($key . '=' . $value);
}

$pdo = null;
try {
    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON');
    $pdo->exec(
        'CREATE TABLE schema_migrations (
            version TEXT NOT NULL PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
         )'
    );

    foreach (range(1, 5) as $number) {
        $pattern = sprintf('%s/migrations/sqlite/%03d_*.sql', $base, $number);
        $file = singleMigrationFile($pattern);
        $sql = file_get_contents($file);
        if ($sql === false) {
            throw new RuntimeException('Could not read ' . $file);
        }
        $pdo->exec($sql);
        recordMigration($pdo, basename($file));
    }

    // An active schema-005 outbox row must survive the schema-006 rollout as
    // exactly one per-device delivery with its retry state and attempt count.
    $pdo->exec(
        "INSERT INTO users (display_name) VALUES ('送信者'), ('受信者');
         INSERT INTO families (name, invite_code) VALUES ('移行家族', 'MIGRATE1');
         INSERT INTO family_members (family_id, user_id, role) VALUES
            (1, 1, 'owner'), (1, 2, 'member');
         INSERT INTO questions (prompt, available_on) VALUES ('質問', '2026-09-01');
         INSERT INTO answers (family_id, question_id, user_id, answer_date, body)
            VALUES (1, 1, 1, '2026-09-01', '回答');
         INSERT INTO push_tokens
            (user_id, token_hash, token_encrypted, environment)
            VALUES (2, 'token-hash', 'encrypted-token', 'sandbox');
         INSERT INTO notification_event_outbox
            (event_type, category, family_id, actor_user_id,
             recipient_user_id, answer_id, title, body, data_json,
             status, attempts, available_at)
            VALUES ('answer_submitted', 'familyActivity', 1, 1, 2, 1,
                    '通知', '本文', '{}', 'processing', 2,
                    '2026-09-01 00:00:00');"
    );

    $migration006 = singleMigrationFile($base . '/migrations/sqlite/006_*.sql');
    $sql006 = file_get_contents($migration006);
    if ($sql006 === false) {
        throw new RuntimeException('Could not read migration 006.');
    }
    $pdo->exec($sql006);
    recordMigration($pdo, basename($migration006));
    $delivery = $pdo->query(
        'SELECT outbox_id, push_token_id, token_was_present, status, attempts
         FROM notification_event_deliveries'
    )->fetchAll();
    sameMigrationValue(1, count($delivery), '005 active row backfills exactly once');
    sameMigrationValue(1, (int) $delivery[0]['outbox_id'], 'delivery keeps outbox');
    sameMigrationValue(1, (int) $delivery[0]['push_token_id'], 'delivery snapshots token');
    sameMigrationValue(1, (int) $delivery[0]['token_was_present'], 'token presence is recorded');
    sameMigrationValue('retry', (string) $delivery[0]['status'], 'processing becomes retry');
    sameMigrationValue(2, (int) $delivery[0]['attempts'], 'attempt count survives');

    // Simulate termination after unrelated 007 statements committed but
    // before schema_migrations was written.
    $pdo->exec(
        'ALTER TABLE device_pairings ADD COLUMN activation_key_hash TEXT NULL;
         CREATE UNIQUE INDEX device_pairings_activation_key_unique
            ON device_pairings (activation_key_hash)
            WHERE activation_key_hash IS NOT NULL;
         ALTER TABLE device_recovery_codes ADD COLUMN redemption_key_hash TEXT NULL;
         ALTER TABLE phone_otp_challenges ADD COLUMN verification_key_hash TEXT NULL;
         ALTER TABLE phone_enrollment_challenges ADD COLUMN verification_key_hash TEXT NULL;
         CREATE TABLE comment_mutation_receipts (
            key_hash TEXT NOT NULL PRIMARY KEY,
            user_id INTEGER NOT NULL,
            request_fingerprint TEXT NOT NULL,
            response_encrypted TEXT NULL,
            expires_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
         );
         CREATE TABLE setup_mutation_receipts (
            key_hash TEXT NOT NULL PRIMARY KEY,
            operation TEXT NOT NULL,
            actor_user_id INTEGER NULL,
            request_fingerprint TEXT NOT NULL,
            response_encrypted TEXT NULL,
            expires_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
         );'
    );
    // Question scheduling can stop between its two additive columns.
    $pdo->exec("ALTER TABLE questions ADD COLUMN publish_start_minute INTEGER NOT NULL DEFAULT 540;
        INSERT INTO questions (prompt) VALUES ('今日、心に残った景色は？');");
    // Migration 009 can also stop after its first ALTER has committed.
    $pdo->exec("ALTER TABLE users ADD COLUMN avatar_mark TEXT NULL;
        INSERT INTO users (id, display_name) VALUES (3, 'たかも');
        INSERT INTO families (id, name, invite_code) VALUES (2, 'たかみさんの家族', 'MIGRATE2');
        INSERT INTO family_members (family_id, user_id, role) VALUES (2, 3, 'owner');");
    $pdo = null;

    $firstOutput = runMigrator($base);
    if (!str_contains($firstOutput, 'applied 007_idempotent_mutations.sql')) {
        throw new RuntimeException('Interrupted 007 did not resume: ' . $firstOutput);
    }

    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    foreach ([
        ['device_pairings', 'activation_key_hash'],
        ['device_pairings', 'activation_response_encrypted'],
        ['device_pairings', 'activation_replay_expires_at'],
        ['device_recovery_codes', 'redemption_key_hash'],
        ['device_recovery_codes', 'redemption_response_encrypted'],
        ['device_recovery_codes', 'redemption_replay_expires_at'],
        ['phone_otp_challenges', 'verification_key_hash'],
        ['phone_otp_challenges', 'verification_response_encrypted'],
        ['phone_otp_challenges', 'verification_replay_expires_at'],
        ['phone_enrollment_challenges', 'verification_key_hash'],
        ['phone_enrollment_challenges', 'verification_response_encrypted'],
        ['phone_enrollment_challenges', 'verification_replay_expires_at'],
    ] as [$table, $column]) {
        migrationTruthy(
            migrationHasColumn($pdo, $table, $column),
            'resumed 007 column ' . $table . '.' . $column,
        );
    }
    foreach ([
        ['device_pairings', 'device_pairings_activation_key_unique'],
        ['device_recovery_codes', 'device_recovery_redemption_key_unique'],
        ['phone_otp_challenges', 'phone_otp_verification_key_unique'],
        ['phone_enrollment_challenges', 'phone_enrollment_verification_key_unique'],
        ['comment_mutation_receipts', 'comment_mutation_receipts_expiry_index'],
        ['comment_mutation_receipts', 'comment_mutation_receipts_key_unique'],
        ['setup_mutation_receipts', 'setup_mutation_receipts_expiry_index'],
        ['setup_mutation_receipts', 'setup_mutation_receipts_key_unique'],
        ['otp_mutation_receipts', 'otp_mutation_receipts_expiry_index'],
        ['otp_mutation_receipts', 'otp_mutation_receipts_key_unique'],
        ['lifecycle_mutation_receipts', 'lifecycle_mutation_receipts_key_unique'],
    ] as [$table, $index]) {
        migrationTruthy(
            migrationHasIndex($pdo, $table, $index),
            'resumed 007 index ' . $index,
        );
    }
    migrationTruthy(
        migrationHasTable($pdo, 'comment_mutation_receipts'),
        'resumed 007 comment receipt table',
    );
    migrationTruthy(
        migrationHasTable($pdo, 'setup_mutation_receipts'),
        'resumed 007 setup receipt table',
    );
    migrationTruthy(
        migrationHasTable($pdo, 'otp_mutation_receipts'),
        'resumed 007 OTP receipt table',
    );
    migrationTruthy(
        migrationHasTable($pdo, 'lifecycle_mutation_receipts'),
        'resumed 007 lifecycle receipt table',
    );
    sameMigrationValue(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM schema_migrations
             WHERE version = '007_idempotent_mutations.sql'"
        )->fetchColumn(),
        '007 ledger is written exactly once',
    );
    sameMigrationValue(
        1,
        (int) $pdo->query('SELECT COUNT(*) FROM notification_event_deliveries')->fetchColumn(),
        '007 resume does not duplicate the 006 backfill',
    );
    migrationTruthy(migrationHasColumn($pdo, 'questions', 'publish_start_minute'), '008 resumes existing start column');
    migrationTruthy(migrationHasColumn($pdo, 'questions', 'publish_end_minute'), '008 adds ending minute');
    migrationTruthy(migrationHasTable($pdo, 'daily_question_publications'), '008 creates durable publication table');
    migrationTruthy(migrationHasIndex($pdo, 'daily_question_publications', 'daily_question_publications_date_index'), '008 creates publication date index');
    sameMigrationValue(1020, (int) $pdo->query("SELECT publish_start_minute FROM questions WHERE prompt LIKE '今日%'")->fetchColumn(), '008 moves legacy day-experience question to evening');
    sameMigrationValue(1, (int) $pdo->query('SELECT COUNT(*) FROM answers WHERE question_id = 1')->fetchColumn(), '008 preserves existing answer question reference');
    $pdo->exec('UPDATE questions SET publish_start_minute = 1080 WHERE id = 2');
    migrationTruthy(migrationHasColumn($pdo, 'users', 'avatar_mark'), '009 resumes existing mark column');
    migrationTruthy(migrationHasColumn($pdo, 'families', 'name_tracks_owner'), '009 adds family name mode');
    sameMigrationValue('たかもさんの家族', $pdo->query('SELECT name FROM families WHERE id = 2')->fetchColumn(), '009 repairs stale generated family name');
    sameMigrationValue('移行家族', $pdo->query('SELECT name FROM families WHERE id = 1')->fetchColumn(), '009 preserves custom family name');
    $pdo->exec("UPDATE families SET name = '大切な家族', name_tracks_owner = 0 WHERE id = 2");
    // A ledger row alone must not hide an incomplete additive schema. Damage
    // one safe-to-recreate index after the first successful run and prove that
    // the recorded migration reconciles it on the next invocation.
    $pdo->exec(
        'DROP INDEX phone_otp_verification_key_unique;
         ALTER TABLE otp_mutation_receipts DROP COLUMN outcome_encrypted;'
    );
    migrationTruthy(
        !migrationHasIndex($pdo, 'phone_otp_challenges', 'phone_otp_verification_key_unique'),
        'test setup removed recorded-007 index',
    );
    migrationTruthy(
        !migrationHasColumn($pdo, 'otp_mutation_receipts', 'outcome_encrypted'),
        'test setup removed recorded-007 receipt column',
    );
    $pdo = null;

    $secondOutput = runMigrator($base);
    if (!str_contains($secondOutput, 'skip 007_idempotent_mutations.sql')) {
        throw new RuntimeException('Completed 007 was not a no-op: ' . $secondOutput);
    }
    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    migrationTruthy(
        migrationHasIndex($pdo, 'phone_otp_challenges', 'phone_otp_verification_key_unique'),
        'recorded 007 reconciles a missing index',
    );
    migrationTruthy(
        migrationHasColumn($pdo, 'otp_mutation_receipts', 'outcome_encrypted'),
        'recorded 007 reconciles a missing receipt column',
    );
    sameMigrationValue('大切な家族', $pdo->query('SELECT name FROM families WHERE id = 2')->fetchColumn(), '009 ledger prevents repeated name backfill');
    sameMigrationValue(1080, (int) $pdo->query('SELECT publish_start_minute FROM questions WHERE id = 2')->fetchColumn(), '008 ledger preserves subsequent publishing customizations');
    // Simulate an interrupted 010 after the first user column and unique index
    // had committed. Previously verified profile data remains in the column.
    $pdo->exec("DELETE FROM schema_migrations WHERE version = '010_email_auth.sql'");
    $pdo->exec("UPDATE users SET email_address = 'retained@example.com' WHERE id = 1");
    $pdo->exec('ALTER TABLE users DROP COLUMN email_verified_at');
    $pdo->exec('DROP TABLE email_enrollment_challenges');
    $pdo->exec('DROP INDEX email_otp_expiry_index');
    $resumeEmail = runMigrator($base);
    migrationTruthy(str_contains($resumeEmail, 'applied 010_email_auth.sql'), '010 interrupted migration resumes');
    migrationTruthy(migrationHasColumn($pdo, 'users', 'email_verified_at'), '010 missing verification column restored');
    migrationTruthy(migrationHasTable($pdo, 'email_enrollment_challenges'), '010 missing enrollment table restored');
    migrationTruthy(migrationHasIndex($pdo, 'email_otp_challenges', 'email_otp_expiry_index'), '010 missing index restored');
    sameMigrationValue('retained@example.com', $pdo->query('SELECT email_address FROM users WHERE id = 1')->fetchColumn(), '010 preserves existing address');
    migrationTruthy(str_contains(runMigrator($base), 'skip 010_email_auth.sql'), '010 repeat is idempotent');
    // Resume additive safety tables after a partial DDL commit. Existing block
    // choices must survive; no rewrite of deployed questions or auth occurs.
    $pdo->exec("INSERT INTO user_blocks (blocker_user_id,blocked_user_id) VALUES (1,2)");
    $pdo->exec("DELETE FROM schema_migrations WHERE version = '011_content_safety.sql'");
    $pdo->exec('DROP TABLE moderation_actions; DROP TABLE answer_reports');
    $resumeSafety = runMigrator($base);
    migrationTruthy(str_contains($resumeSafety, 'applied 011_content_safety.sql'), '011 interrupted migration resumes');
    migrationTruthy(migrationHasTable($pdo, 'answer_reports') && migrationHasTable($pdo, 'moderation_actions'), '011 missing safety tables restored');
    sameMigrationValue(1, (int) $pdo->query('SELECT COUNT(*) FROM user_blocks WHERE blocker_user_id=1 AND blocked_user_id=2')->fetchColumn(), '011 preserves block choices');
    migrationTruthy(str_contains(runMigrator($base), 'skip 011_content_safety.sql'), '011 repeat is idempotent');
    echo "migration resume test passed\n";
} finally {
    $pdo = null;
    foreach ([$databasePath, $databasePath . '-wal', $databasePath . '-shm'] as $path) {
        if (is_file($path)) {
            unlink($path);
        }
    }
    if (is_dir($mediaPath)) {
        rmdir($mediaPath);
    }
}

function singleMigrationFile(string $pattern): string
{
    $files = glob($pattern) ?: [];
    if (count($files) !== 1) {
        throw new RuntimeException('Expected one migration for ' . $pattern);
    }
    return $files[0];
}

function recordMigration(PDO $pdo, string $version): void
{
    $statement = $pdo->prepare(
        'INSERT INTO schema_migrations (version) VALUES (:version)'
    );
    $statement->execute(['version' => $version]);
}

function runMigrator(string $base): string
{
    $lines = [];
    $status = 0;
    exec(
        escapeshellarg(PHP_BINARY) . ' ' .
        escapeshellarg($base . '/bin/migrate.php') . ' 2>&1',
        $lines,
        $status,
    );
    $output = implode("\n", $lines);
    if ($status !== 0) {
        throw new RuntimeException('Migrator failed: ' . $output);
    }
    return $output;
}

function migrationHasColumn(PDO $pdo, string $table, string $column): bool
{
    foreach ($pdo->query('PRAGMA table_info(' . $table . ')')->fetchAll() as $row) {
        if ((string) $row['name'] === $column) {
            return true;
        }
    }
    return false;
}

function migrationHasIndex(PDO $pdo, string $table, string $index): bool
{
    foreach ($pdo->query('PRAGMA index_list(' . $table . ')')->fetchAll() as $row) {
        if ((string) $row['name'] === $index) {
            return true;
        }
    }
    return false;
}

function migrationHasTable(PDO $pdo, string $table): bool
{
    $statement = $pdo->prepare(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = :table"
    );
    $statement->execute(['table' => $table]);
    return $statement->fetchColumn() !== false;
}

function sameMigrationValue(mixed $expected, mixed $actual, string $message): void
{
    if ($expected !== $actual) {
        throw new RuntimeException(sprintf(
            '%s: expected %s, got %s',
            $message,
            var_export($expected, true),
            var_export($actual, true),
        ));
    }
}

function migrationTruthy(bool $value, string $message): void
{
    if (!$value) {
        throw new RuntimeException($message);
    }
}
