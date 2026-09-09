<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AnswerMediaService;
use Tsutsuura\Server\App\AppService;
use Tsutsuura\Server\App\FamilySetupService;
use Tsutsuura\Server\App\LifecycleService;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Push\EventNotificationService;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$mode = $argv[1] ?? null;
if ($mode === '--timezone-child') {
    childResult(static function () use ($base, $argv): array {
        return lifecycle($base)->updateDeviceTimezone(positiveId($argv[2] ?? null), [
            'timeZoneIdentifier' => 'America/Toronto',
        ]);
    });
}
if ($mode === '--preferences-child') {
    childResult(static function () use ($base, $argv): array {
        return lifecycle($base)->updateNotificationPreferences(positiveId($argv[2] ?? null), [
            'commentsEnabled' => true,
        ]);
    });
}
if ($mode === '--transfer-child') {
    childResult(static function () use ($base, $argv): array {
        $ownerId = positiveId($argv[2] ?? null);
        $targetId = positiveId($argv[3] ?? null);
        return lifecycle($base)->transferOwnership($ownerId, (string) $targetId);
    });
}
if ($mode === '--report-child') {
    childResult(static function () use ($base, $argv): array {
        $reporterId = positiveId($argv[2] ?? null);
        $commentId = positiveId($argv[3] ?? null);
        [$database, $crypto, $config] = dependencies($base);
        return (new AppService($database, $crypto, $config))->reportComment(
            $reporterId,
            (string) $commentId,
            'privacy',
            'concurrent membership transition',
        );
    });
}
if ($mode === '--leave-child') {
    childResult(static function () use ($base, $argv): array {
        $userId = positiveId($argv[2] ?? null);
        $key = requiredRaceKey($argv[3] ?? null);
        return lifecycle($base)->leaveFamily($userId, $key);
    });
}
if ($mode === '--delete-child') {
    childResult(static function () use ($base, $argv): array {
        $userId = positiveId($argv[2] ?? null);
        $key = requiredRaceKey($argv[3] ?? null);
        lifecycle($base)->deleteAccount($userId, $key);
        return [];
    });
}
if ($mode === '--comment-child') {
    childResult(static function () use ($base, $argv): array {
        $userId = positiveId($argv[2] ?? null);
        $answerId = positiveId($argv[3] ?? null);
        $key = requiredRaceKey($argv[4] ?? null);
        [$database, $crypto, $config] = dependencies($base);
        return (new AppService(
            $database,
            $crypto,
            $config,
            null,
            new EventNotificationService(),
        ))->addComment(
            $userId,
            (string) $answerId,
            'concurrent exact comment',
            null,
            $key,
        );
    });
}
if ($mode === '--organizer-child') {
    childResult(static function () use ($base, $argv): array {
        $key = requiredRaceKey($argv[2] ?? null);
        return familySetup($base)->createOrganizerFamily(
            'concurrent organizer',
            'concurrent setup family',
            '127.0.0.80',
            $key,
        );
    });
}
if ($mode === '--managed-child') {
    childResult(static function () use ($base, $argv): array {
        $ownerId = positiveId($argv[2] ?? null);
        $key = requiredRaceKey($argv[3] ?? null);
        return familySetup($base)->createManagedMember(
            $ownerId,
            'concurrent managed member',
            $key,
        );
    });
}

$suffix = bin2hex(random_bytes(8));
$databasePath = sys_get_temp_dir() . '/tsutsuura-transaction-race-' . $suffix . '.sqlite';
$mediaPath = sys_get_temp_dir() . '/tsutsuura-transaction-media-' . $suffix;
configureTestEnvironment($databasePath, $mediaPath);

$database = null;
$pdo = null;
$blocker = null;
try {
    if (!mkdir($mediaPath, 0700) && !is_dir($mediaPath)) {
        throw new RuntimeException('Could not create transaction-test media directory.');
    }
    [$database, $crypto, $config] = dependencies($base);
    $pdo = $database->connection();
    $migrationFiles = glob($base . '/migrations/sqlite/*.sql') ?: [];
    sort($migrationFiles, SORT_STRING);
    foreach ($migrationFiles as $migrationFile) {
        $sql = file_get_contents($migrationFile);
        if ($sql === false) {
            throw new RuntimeException('Transaction-test migration could not be read.');
        }
        $pdo->exec($sql);
    }
    $seed = file_get_contents($base . '/seeds/001_questions.sql');
    if ($seed === false) {
        throw new RuntimeException('Transaction-test seed could not be read.');
    }
    $pdo->exec($seed);
    $pdo->exec(
        "INSERT INTO users (display_name) VALUES
            ('owner'), ('successor'), ('reporter'), ('commenter');
         INSERT INTO families (name, invite_code) VALUES ('race family', 'RACE00000001');
         INSERT INTO family_members (family_id, user_id, role) VALUES
            (1, 1, 'owner'), (1, 2, 'member'), (1, 3, 'member'), (1, 4, 'member');
         INSERT INTO sessions (user_id, token_hash, expires_at, last_used_at) VALUES
            (2, '" . str_repeat('1', 64) . "', '2999-01-01 00:00:00', CURRENT_TIMESTAMP);
         INSERT INTO answers (family_id, question_id, user_id, answer_date, body) VALUES
            (1, 1, 1, '2026-01-01', 'race answer');
         INSERT INTO comments (answer_id, user_id, body) VALUES
            (1, 4, 'reportable comment');"
    );

    $lifecycle = lifecycle($base);
    $blocker = sqliteConnection($databasePath);
    $blocker->exec("BEGIN IMMEDIATE;
        INSERT INTO notification_preferences
            (user_id, comments_enabled, likes_enabled, family_activity_enabled, question_reminders_enabled,
             question_reminder_time, timezone, quiet_start, quiet_end, mute_until)
        VALUES (4, 0, 0, 0, 0, '18:45', 'Asia/Tokyo', '21:00', '08:00', '2099-01-01 00:00:00')");
    $timezoneChild = startChild(['--timezone-child', '4']);
    assertBlocked($timezoneChild, 'device timezone waits for preference transaction');
    $blocker->commit();
    $timezoneResult = finishChild($timezoneChild);
    same('success', $timezoneResult['kind'] ?? null, 'timezone preference race outcome');
    $savedPreferences = $lifecycle->notificationPreferences(4);
    same('America/Toronto', $savedPreferences['timezone'], 'timezone sync applies after concurrent preference insertion');
    foreach (['commentsEnabled', 'likesEnabled', 'familyActivityEnabled', 'questionRemindersEnabled'] as $field) {
        same(false, $savedPreferences[$field], 'timezone sync preserves concurrently saved ' . $field);
    }
    same('18:45', $savedPreferences['questionReminderTime'], 'timezone sync preserves custom reminder time');
    same('21:00', $savedPreferences['quietStart'], 'timezone sync preserves quiet hours');
    same('2099-01-01T00:00:00Z', $savedPreferences['muteUntil'], 'timezone sync preserves mute deadline');
    $blocker->exec("BEGIN IMMEDIATE; UPDATE notification_preferences SET timezone = 'Europe/Berlin' WHERE user_id = 4");
    $preferencesChild = startChild(['--preferences-child', '4']);
    assertBlocked($preferencesChild, 'preference edit waits for device timezone transaction');
    $blocker->commit();
    $blocker = null;
    same('success', finishChild($preferencesChild)['kind'] ?? null, 'reverse timezone preference race outcome');
    $savedPreferences = $lifecycle->notificationPreferences(4);
    same('Europe/Berlin', $savedPreferences['timezone'], 'later partial preference edit preserves synced timezone');
    same(true, $savedPreferences['commentsEnabled'], 'later preference edit applies its intended toggle');
    $recovery = $lifecycle->createRecoveryCode(2);

    // Hold the SQLite writer lock while applying the state transition that a
    // recovery transaction makes. The transfer process starts while that
    // transaction is uncommitted, then must re-read eligibility after it wins
    // the lock and reject the consumed last recovery credential.
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $consume = $blocker->prepare(
        'UPDATE device_recovery_codes SET consumed_at = CURRENT_TIMESTAMP
         WHERE code_hash = :hash AND consumed_at IS NULL'
    );
    $consume->execute([
        'hash' => $crypto->hashOpaque('device-recovery:' . $recovery['code']),
    ]);
    same(1, $consume->rowCount(), 'recovery-race credential transition');
    $blocker->exec(
        "UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP
         WHERE user_id = 2 AND revoked_at IS NULL;
         INSERT INTO sessions (user_id, token_hash, expires_at, last_used_at) VALUES
            (2, '" . str_repeat('2', 64) . "', '2999-01-01 00:00:00', CURRENT_TIMESTAMP);"
    );
    $transfer = startChild(['--transfer-child', '1', '2']);
    assertBlocked($transfer, 'ownership transfer waits for recovery state lock');
    $blocker->commit();
    $blocker = null;
    $transferResult = finishChild($transfer);
    same('error', $transferResult['kind'] ?? null, 'recovery-first transfer outcome kind');
    same(409, $transferResult['status'] ?? null, 'recovery-first transfer status');
    same(
        'owner_recovery_required',
        $transferResult['code'] ?? null,
        'transfer rechecks consumed recovery credential',
    );
    same(1, familyOwner($pdo, 1), 'failed raced transfer preserves original owner');

    $lifecycle->createRecoveryCode(2);
    $transferResult = $lifecycle->transferOwnership(1, '2');
    same('2', $transferResult['ownerUserId'], 'replacement recovery permits later transfer');

    // Reproduce the report/leave window with two real connections. A writer
    // moves the reporter to a replacement family while the report request is
    // already running. Authorization and insertion must wait together, see the
    // new membership, and leave no stale report behind.
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $blocker->exec(
        "DELETE FROM family_members WHERE user_id = 3;
         INSERT INTO families (name, invite_code) VALUES ('replacement family', 'RACE00000002');"
    );
    $replacementFamilyId = (int) $blocker->lastInsertId();
    $replacement = $blocker->prepare(
        "INSERT INTO family_members (family_id, user_id, role)
         VALUES (:family, 3, 'owner')"
    );
    $replacement->execute(['family' => $replacementFamilyId]);
    $report = startChild(['--report-child', '3', '1']);
    assertBlocked($report, 'comment report waits for membership transition lock');
    $blocker->commit();
    $blocker = null;
    $reportResult = finishChild($report);
    same('error', $reportResult['kind'] ?? null, 'post-leave report outcome kind');
    same(404, $reportResult['status'] ?? null, 'post-leave report status');
    same('comment_not_found', $reportResult['code'] ?? null, 'post-leave report authorization');
    same(
        0,
        (int) $pdo->query('SELECT COUNT(*) FROM comment_reports')->fetchColumn(),
        'raced membership change cannot leave an unauthorized report',
    );

    // Two identical comment requests contend for the same immutable receipt.
    // Only one comment and its one answer-owner outbox event may be created;
    // both callers receive the byte-equivalent presented response.
    $commentKey = 'transaction-race-comment-key-0001';
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $commentA = startChild(['--comment-child', '4', '1', $commentKey]);
    $commentB = startChild(['--comment-child', '4', '1', $commentKey]);
    assertBlocked($commentA, 'first duplicate comment waits for writer lock');
    assertBlocked($commentB, 'second duplicate comment waits for writer lock');
    $blocker->commit();
    $blocker = null;
    $commentResultA = finishChild($commentA);
    $commentResultB = finishChild($commentB);
    same('success', $commentResultA['kind'] ?? null, 'first duplicate comment outcome');
    same('success', $commentResultB['kind'] ?? null, 'second duplicate comment outcome');
    same(
        $commentResultA['value'] ?? null,
        $commentResultB['value'] ?? null,
        'duplicate comment exact receipt response',
    );
    same(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM comments WHERE body = 'concurrent exact comment'"
        )->fetchColumn(),
        'duplicate comment inserts once',
    );
    same(
        1,
        (int) $pdo->query(
            'SELECT COUNT(*) FROM comment_mutation_receipts
             WHERE response_encrypted IS NOT NULL'
        )->fetchColumn(),
        'duplicate comment completes one receipt',
    );
    same(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM notification_event_outbox
             WHERE event_type = 'comment_added'"
        )->fetchColumn(),
        'duplicate comment enqueues one notification effect',
    );

    // Anonymous organizer bootstrap and authenticated managed-member creation
    // use the same reserve/complete receipt protocol. Exercise both with real
    // processes so a same-key race cannot create duplicate accounts/families.
    $organizerKey = 'transaction-race-organizer-key-0001';
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $organizerA = startChild(['--organizer-child', $organizerKey]);
    $organizerB = startChild(['--organizer-child', $organizerKey]);
    assertBlocked($organizerA, 'first organizer bootstrap waits for writer lock');
    assertBlocked($organizerB, 'second organizer bootstrap waits for writer lock');
    $blocker->commit();
    $blocker = null;
    $organizerResultA = finishChild($organizerA);
    $organizerResultB = finishChild($organizerB);
    same('success', $organizerResultA['kind'] ?? null, 'first organizer race outcome');
    same('success', $organizerResultB['kind'] ?? null, 'second organizer race outcome');
    same(
        $organizerResultA['value'] ?? null,
        $organizerResultB['value'] ?? null,
        'organizer race exact receipt response',
    );
    same(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM families WHERE name = 'concurrent setup family'"
        )->fetchColumn(),
        'organizer race creates one family',
    );
    same(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM users WHERE display_name = 'concurrent organizer'"
        )->fetchColumn(),
        'organizer race creates one user',
    );
    $setupOwnerId = (int) ($organizerResultA['value']['user']['id'] ?? 0);
    same(1, $setupOwnerId > 0 ? 1 : 0, 'organizer race returns an owner id');

    $managedKey = 'transaction-race-managed-key-0001';
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $managedA = startChild(['--managed-child', (string) $setupOwnerId, $managedKey]);
    $managedB = startChild(['--managed-child', (string) $setupOwnerId, $managedKey]);
    assertBlocked($managedA, 'first managed-member create waits for writer lock');
    assertBlocked($managedB, 'second managed-member create waits for writer lock');
    $blocker->commit();
    $blocker = null;
    $managedResultA = finishChild($managedA);
    $managedResultB = finishChild($managedB);
    same('success', $managedResultA['kind'] ?? null, 'first managed-member race outcome');
    same('success', $managedResultB['kind'] ?? null, 'second managed-member race outcome');
    same(
        $managedResultA['value'] ?? null,
        $managedResultB['value'] ?? null,
        'managed-member race exact receipt response',
    );
    same(
        1,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM users WHERE display_name = 'concurrent managed member'"
        )->fetchColumn(),
        'managed-member race creates one account',
    );
    same(
        2,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM setup_mutation_receipts
             WHERE response_encrypted IS NOT NULL"
        )->fetchColumn(),
        'setup races complete one receipt per operation',
    );

    // Two identical leave requests start while another writer owns the lock.
    // Once released, one performs the move and the other must return the
    // completed receipt instead of operating on the replacement family.
    $leaveKey = 'transaction-race-leave-key-0001';
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $leaveA = startChild(['--leave-child', '4', $leaveKey]);
    $leaveB = startChild(['--leave-child', '4', $leaveKey]);
    assertBlocked($leaveA, 'first duplicate leave waits for writer lock');
    assertBlocked($leaveB, 'second duplicate leave waits for writer lock');
    $blocker->commit();
    $blocker = null;
    foreach ([finishChild($leaveA), finishChild($leaveB)] as $leaveResult) {
        same('success', $leaveResult['kind'] ?? null, 'duplicate leave outcome');
        same(
            ['accountDeleted' => false],
            $leaveResult['value'] ?? null,
            'duplicate leave exact receipt',
        );
    }
    same(
        1,
        receiptCount($pdo, 'family.leave'),
        'duplicate leave stores one durable receipt',
    );

    $pdo->exec(
        "INSERT INTO users (display_name) VALUES ('delete owner');
         INSERT INTO families (name, invite_code) VALUES ('delete family', 'RACE00000003');"
    );
    $deleteUserId = (int) $pdo->query('SELECT MAX(id) FROM users')->fetchColumn();
    $deleteFamilyId = (int) $pdo->query('SELECT MAX(id) FROM families')->fetchColumn();
    $deleteMembership = $pdo->prepare(
        "INSERT INTO family_members (family_id, user_id, role)
         VALUES (:family, :user, 'owner')"
    );
    $deleteMembership->execute([
        'family' => $deleteFamilyId,
        'user' => $deleteUserId,
    ]);
    $deleteKey = 'transaction-race-delete-key-0001';
    $blocker = sqliteConnection($databasePath);
    $blocker->exec('BEGIN IMMEDIATE');
    $deleteA = startChild(['--delete-child', (string) $deleteUserId, $deleteKey]);
    $deleteB = startChild(['--delete-child', (string) $deleteUserId, $deleteKey]);
    assertBlocked($deleteA, 'first duplicate delete waits for writer lock');
    assertBlocked($deleteB, 'second duplicate delete waits for writer lock');
    $blocker->commit();
    $blocker = null;
    foreach ([finishChild($deleteA), finishChild($deleteB)] as $deleteResult) {
        same('success', $deleteResult['kind'] ?? null, 'duplicate delete outcome');
        same([], $deleteResult['value'] ?? null, 'duplicate delete exact receipt');
    }
    same(
        1,
        receiptCount($pdo, 'account.delete'),
        'duplicate delete stores one durable receipt',
    );
    same(
        0,
        (int) $pdo->query(
            'SELECT COUNT(*) FROM users WHERE id = ' . $deleteUserId
        )->fetchColumn(),
        'duplicate account delete removes the user once',
    );
    same([], $pdo->query('PRAGMA foreign_key_check')->fetchAll(), 'transaction-race foreign keys');

    fwrite(STDOUT, "Transaction race tests passed.\n");
} catch (Throwable $exception) {
    if ($blocker instanceof PDO && $blocker->inTransaction()) {
        $blocker->rollBack();
    }
    fwrite(STDERR, 'Transaction race tests failed: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
} finally {
    $blocker = null;
    $pdo = null;
    $database = null;
    foreach ([$databasePath, $databasePath . '-shm', $databasePath . '-wal'] as $path) {
        if (is_file($path)) {
            @unlink($path);
        }
    }
    if (is_dir($mediaPath)) {
        @rmdir($mediaPath);
    }
}

/** @return array{0: Database, 1: Crypto, 2: Config} */
function dependencies(string $base): array
{
    $config = Config::fromEnvironment($base);
    $database = new Database($config);
    return [$database, new Crypto($config->appKey), $config];
}

function lifecycle(string $base): LifecycleService
{
    [$database, $crypto, $config] = dependencies($base);
    $sessions = new SessionService($database, $crypto, $config);
    return new LifecycleService(
        $database,
        $crypto,
        $config,
        $sessions,
        new AnswerMediaService($database, $crypto, $config),
    );
}

function familySetup(string $base): FamilySetupService
{
    [$database, $crypto, $config] = dependencies($base);
    return new FamilySetupService(
        $database,
        $crypto,
        new RateLimiter($database, $crypto),
        new SessionService($database, $crypto, $config),
        $config,
    );
}

function configureTestEnvironment(string $databasePath, string $mediaPath): void
{
    foreach ([
        'APP_ENV' => 'testing',
        'APP_DEBUG' => 'false',
        'APP_KEY' => str_repeat('9b', 32),
        'APP_URL' => 'http://localhost',
        'APP_TIMEZONE' => 'Asia/Tokyo',
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
    ] as $key => $value) {
        putenv($key . '=' . $value);
    }
}

function sqliteConnection(string $databasePath): PDO
{
    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON');
    $pdo->exec('PRAGMA journal_mode = WAL');
    $pdo->exec('PRAGMA busy_timeout = 5000');
    return $pdo;
}

/** @return array{process: resource, pipes: array<int, resource>} */
function startChild(array $arguments): array
{
    $command = [PHP_BINARY, __FILE__, ...$arguments];
    $process = proc_open($command, [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ], $pipes, dirname(__DIR__));
    if (!is_resource($process)) {
        throw new RuntimeException('Could not start transaction-race child process.');
    }
    fclose($pipes[0]);
    $ready = fgets($pipes[1]);
    if ($ready === false || trim($ready) !== 'READY') {
        $stderr = stream_get_contents($pipes[2]);
        proc_terminate($process);
        throw new RuntimeException('Transaction-race child did not become ready: ' . trim($stderr));
    }
    return ['process' => $process, 'pipes' => $pipes];
}

/** @param array{process: resource, pipes: array<int, resource>} $child */
function assertBlocked(array $child, string $label): void
{
    usleep(150_000);
    $status = proc_get_status($child['process']);
    if (!is_array($status) || !$status['running']) {
        $output = stream_get_contents($child['pipes'][1]);
        $stderr = stream_get_contents($child['pipes'][2]);
        throw new RuntimeException($label . ': child completed before the writer lock released; ' .
            trim($output . ' ' . $stderr));
    }
}

/** @param array{process: resource, pipes: array<int, resource>} $child
 *  @return array<string, mixed>
 */
function finishChild(array $child): array
{
    $output = trim((string) stream_get_contents($child['pipes'][1]));
    $stderr = trim((string) stream_get_contents($child['pipes'][2]));
    fclose($child['pipes'][1]);
    fclose($child['pipes'][2]);
    $exit = proc_close($child['process']);
    if ($exit !== 0) {
        throw new RuntimeException('Transaction-race child failed: ' . $stderr);
    }
    $decoded = json_decode($output, true, 32, JSON_THROW_ON_ERROR);
    if (!is_array($decoded)) {
        throw new RuntimeException('Transaction-race child returned an invalid result.');
    }
    return $decoded;
}

function childResult(callable $operation): never
{
    fwrite(STDOUT, "READY\n");
    fflush(STDOUT);
    try {
        $value = $operation();
        fwrite(STDOUT, json_encode(['kind' => 'success', 'value' => $value], JSON_THROW_ON_ERROR));
    } catch (ApiException $exception) {
        fwrite(STDOUT, json_encode([
            'kind' => 'error',
            'status' => $exception->status,
            'code' => $exception->errorCode,
        ], JSON_THROW_ON_ERROR));
    } catch (Throwable $exception) {
        fwrite(STDOUT, json_encode([
            'kind' => 'unexpected',
            'type' => $exception::class,
            'message' => $exception->getMessage(),
        ], JSON_THROW_ON_ERROR));
    }
    exit(0);
}

function positiveId(mixed $value): int
{
    if (!is_string($value) || preg_match('/^[1-9][0-9]*$/', $value) !== 1) {
        throw new RuntimeException('Child id argument is invalid.');
    }
    return (int) $value;
}

function requiredRaceKey(mixed $value): string
{
    if (!is_string($value) || preg_match('/^[A-Za-z0-9._-]{16,128}$/', $value) !== 1) {
        throw new RuntimeException('Child idempotency key argument is invalid.');
    }
    return $value;
}

function receiptCount(PDO $pdo, string $operation): int
{
    $statement = $pdo->prepare(
        'SELECT COUNT(*) FROM lifecycle_mutation_receipts
         WHERE operation = :operation AND result_json IS NOT NULL'
    );
    $statement->execute(['operation' => $operation]);
    return (int) $statement->fetchColumn();
}

function familyOwner(PDO $pdo, int $familyId): int
{
    $statement = $pdo->prepare(
        "SELECT user_id FROM family_members WHERE family_id = :family AND role = 'owner'"
    );
    $statement->execute(['family' => $familyId]);
    return (int) $statement->fetchColumn();
}

function same(mixed $expected, mixed $actual, string $label): void
{
    if ($expected !== $actual) {
        throw new RuntimeException(sprintf(
            '%s: expected %s, received %s',
            $label,
            var_export($expected, true),
            var_export($actual, true),
        ));
    }
}
