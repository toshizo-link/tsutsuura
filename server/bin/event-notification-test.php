<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AppService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Push\DeterministicPushProvider;
use Tsutsuura\Server\Push\EventNotificationService;
use Tsutsuura\Server\Push\EventNotificationWorker;
use Tsutsuura\Server\Push\PushDeliveryService;
use Tsutsuura\Server\Push\PushProvider;
use Tsutsuura\Server\Security\Crypto;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$suffix = bin2hex(random_bytes(8));
$databasePath = sys_get_temp_dir() . '/tsutsuura-event-notifications-' . $suffix . '.sqlite';
$mediaPath = sys_get_temp_dir() . '/tsutsuura-event-media-' . $suffix;
$environment = [
    'APP_ENV' => 'testing',
    'APP_DEBUG' => 'false',
    'APP_KEY' => str_repeat('e7', 32),
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
];
foreach ($environment as $key => $value) {
    putenv($key . '=' . $value);
}

$database = null;
$pdo = null;
try {
    $config = Config::fromEnvironment($base);
    $database = new Database($config);
    $pdo = $database->connection();
    $migrationFiles = glob($base . '/migrations/sqlite/*.sql') ?: [];
    sort($migrationFiles, SORT_STRING);
    foreach ($migrationFiles as $migrationFile) {
        $migration = file_get_contents($migrationFile);
        if ($migration === false) {
            throw new RuntimeException('Test migration could not be read.');
        }
        $pdo->exec($migration);
    }
    $seed = file_get_contents($base . '/seeds/001_questions.sql');
    if ($seed === false) {
        throw new RuntimeException('Question fixtures could not be read.');
    }
    $pdo->exec($seed);

    $pdo->exec(
        "INSERT INTO users (display_name) VALUES
            ('お母さん'), ('おばあちゃん'), ('空'), ('森'), ('星');
         INSERT INTO families (name, invite_code) VALUES
            ('つつうら家', 'EVENT001'), ('別の家族', 'EVENT002');
         INSERT INTO family_members (family_id, user_id, role) VALUES
            (1, 1, 'owner'), (1, 2, 'member'), (1, 3, 'member'),
            (2, 4, 'owner'), (1, 5, 'member');"
    );

    $crypto = new Crypto($config->appKey);
    $provider = new DeterministicPushProvider();
    $worker = eventWorker($database, $crypto, $config, $provider);
    $app = new AppService(
        $database,
        $crypto,
        $config,
        null,
        new EventNotificationService(),
        static fn (): DateTimeImmutable => (new DateTimeImmutable('now', $config->timezone))->setTime(19, 30),
    );
    $tokens = [
        1 => str_repeat('a', 64),
        2 => str_repeat('b', 64),
        3 => str_repeat('c', 64),
        4 => str_repeat('d', 64),
    ];
    foreach ($tokens as $userId => $token) {
        $app->registerPushToken($userId, $token, 'ios', 'sandbox');
    }

    ensurePreferences($pdo, 3);
    $pdo->exec('UPDATE notification_preferences SET family_activity_enabled = 0 WHERE user_id = 3');

    $answer = $app->submitTodayAnswer(1, '家族への最初の回答');
    same(0, count($provider->deliveries), 'request path never calls provider');
    $answerJobs = jobs($pdo, 'answer_submitted');
    same(3, count($answerJobs), 'new answer enqueues one row per in-family recipient');
    same([2, 3, 5], recipients($answerJobs), 'answer excludes actor and cross-family user');
    same(
        3,
        deliveryCountForJobs($pdo, $answerJobs),
        'answer atomically snapshots one delivery per token or no-token recipient',
    );
    same('family_answer', jobData($answerJobs[0], 'destination'), 'answer destination contract');
    same('answer_submitted', jobData($answerJobs[0], 'event_type'), 'answer event contract');
    same($answer['id'], jobData($answerJobs[0], 'answer_id'), 'answer id is a string payload value');

    $updatedAnswer = $app->submitTodayAnswer(1, '家族への最初の回答');
    same($answer['id'], $updatedAnswer['id'], 'daily answer retry keeps public response shape');
    same(3, count(jobs($pdo, 'answer_submitted')), 'daily answer retry does not enqueue again');

    $answerSummary = $worker->run();
    same(3, $answerSummary['claimed'], 'answer worker claims all recipient jobs');
    same(1, $answerSummary['delivered'], 'answer worker delivers enabled token');
    same(2, $answerSummary['skipped'], 'answer worker skips disabled and no-token recipients');
    same(1, count($provider->deliveries), 'answer provider delivery count');
    same($tokens[2], $provider->deliveries[0]['token'], 'answer targets enabled family member');
    same('familyActivity', category($provider, 0), 'answer notification category');
    same('family_answer', payloadValue($provider, 0, 'destination'), 'delivered answer destination');
    same(
        '「お母さん」から今日の回答が届きました。',
        alertBody($provider, 0),
        'answer copy does not double a kinship honorific',
    );

    ensurePreferences($pdo, 1);
    $pdo->exec('UPDATE notification_preferences SET likes_enabled = 0 WHERE user_id = 1');
    $like = $app->setLike(2, $answer['id'], true);
    same(['likesCount' => 1, 'isLiked' => true], $like, 'like mutation succeeds before worker');
    same(1, pendingCount($pdo), 'like enqueues one owner job');
    $disabledLikeSummary = $worker->run();
    same(1, $disabledLikeSummary['skipped'], 'disabled likes preference skips delivery');
    same(1, count($provider->deliveries), 'disabled likes preference does not call provider');

    $app->setLike(2, $answer['id'], false);
    same(0, pendingCount($pdo), 'unlike does not enqueue');
    $pdo->exec('UPDATE notification_preferences SET likes_enabled = 1 WHERE user_id = 1');
    $like = $app->setLike(2, $answer['id'], true);
    same(['likesCount' => 1, 'isLiked' => true], $like, 'like response shape remains unchanged');
    $worker->run();
    same(2, count($provider->deliveries), 'enabled like delivers once');
    same($tokens[1], $provider->deliveries[1]['token'], 'like targets answer owner');
    same('likes', category($provider, 1), 'like category');
    same('family_answer', payloadValue($provider, 1, 'destination'), 'like destination contract');
    same(
        '「おばあちゃん」があなたの回答にいいねしました。',
        alertBody($provider, 1),
        'like copy does not double a kinship honorific',
    );
    $app->setLike(2, $answer['id'], true);
    same(0, pendingCount($pdo), 'idempotent like does not enqueue again');

    $pdo->exec('UPDATE notification_preferences SET comments_enabled = 0 WHERE user_id = 1');
    $disabledComment = $app->addComment(2, $answer['id'], '通知オフでも保存される');
    truthy(isset($disabledComment['id']), 'comment persists with preference disabled');
    $worker->run();
    same(2, count($provider->deliveries), 'disabled comments preference suppresses provider');

    $pdo->exec(
        "UPDATE notification_preferences
         SET comments_enabled = 1, mute_until = '2999-01-01 00:00:00'
         WHERE user_id = 1"
    );
    $mutedComment = $app->addComment(2, $answer['id'], 'ミュート中でも保存される');
    truthy(isset($mutedComment['id']), 'comment persists while recipient is muted');
    $mutedSummary = $worker->run();
    same(1, $mutedSummary['skipped'], 'mute skips comment job');

    $pdo->exec(
        "UPDATE notification_preferences
         SET mute_until = NULL, quiet_start = '00:00', quiet_end = '00:00', timezone = 'UTC'
         WHERE user_id = 1"
    );
    $quietComment = $app->addComment(2, $answer['id'], '静穏時間中でも保存される');
    truthy(isset($quietComment['id']), 'comment persists during quiet hours');
    $quietSummary = $worker->run();
    same(1, $quietSummary['skipped'], 'quiet hours skip comment job');

    $pdo->exec(
        'UPDATE notification_preferences
         SET quiet_start = NULL, quiet_end = NULL, timezone = NULL
         WHERE user_id = 1'
    );
    $comment = $app->addComment(2, $answer['id'], '通知されるコメント');
    $commentJobs = jobs($pdo, 'comment_added', (int) $comment['id']);
    same(1, count($commentJobs), 'comment enqueues answer-owner recipient');
    same('comments', jobData($commentJobs[0], 'destination'), 'comment destination contract');
    same($comment['id'], jobData($commentJobs[0], 'comment_id'), 'comment id is a string payload value');
    $worker->run();
    same(3, count($provider->deliveries), 'comment delivers to answer owner');
    same('comments', category($provider, 2), 'comment category');
    same(
        '「おばあちゃん」からコメントが届きました。',
        alertBody($provider, 2),
        'comment copy does not double a kinship honorific',
    );

    $reply = $app->addComment(3, $answer['id'], '返信です', $comment['id']);
    $replyJobs = jobs($pdo, 'comment_added', (int) $reply['id']);
    same(2, count($replyJobs), 'reply enqueues answer owner and parent author');
    same([1, 2], recipients($replyJobs), 'reply deduplicates recipients and excludes actor');
    $worker->run();
    same(5, count($provider->deliveries), 'reply delivers exactly twice');
    $replyTokens = [
        $provider->deliveries[3]['token'],
        $provider->deliveries[4]['token'],
    ];
    sort($replyTokens, SORT_STRING);
    same([$tokens[1], $tokens[2]], $replyTokens, 'reply provider recipient set');

    $ownerComment = $app->addComment(1, $answer['id'], '回答者自身のコメント');
    same(
        0,
        count(jobs($pdo, 'comment_added', (int) $ownerComment['id'])),
        'answer owner is not notified about their own comment',
    );
    $deduplicatedReply = $app->addComment(
        3,
        $answer['id'],
        '回答者のコメントへの返信',
        $ownerComment['id'],
    );
    $deduplicatedJobs = jobs($pdo, 'comment_added', (int) $deduplicatedReply['id']);
    same(1, count($deduplicatedJobs), 'same answer and parent owner is deduplicated');
    same([1], recipients($deduplicatedJobs), 'deduplicated reply recipient');
    $worker->run();
    same(6, count($provider->deliveries), 'deduplicated reply delivers once');

    $failingProvider = new class implements PushProvider {
        public int $calls = 0;

        public function send(string $deviceToken, string $environment, array $payload): array
        {
            $this->calls++;
            throw new RuntimeException('simulated transient APNs failure');
        }
    };
    $failedDeliveryLike = $app->setLike(3, $answer['id'], true);
    same(
        ['likesCount' => 2, 'isLiked' => true],
        $failedDeliveryLike,
        'mutation commits without invoking failing provider',
    );
    same(0, $failingProvider->calls, 'provider is not called by mutation request');
    $persistedLike = $pdo->query(
        'SELECT COUNT(*) FROM answer_likes WHERE answer_id = ' . (int) $answer['id'] . ' AND user_id = 3'
    )->fetchColumn();
    same(1, (int) $persistedLike, 'like is committed before delivery');

    $failingWorker = eventWorker($database, $crypto, $config, $failingProvider);
    $failureSummary = $failingWorker->run();
    same(1, $failureSummary['retried'], 'transient provider failure schedules retry');
    same(1, $failureSummary['providerFailed'], 'worker records provider failure');
    same(1, $failingProvider->calls, 'worker exercises provider once');
    $retryJob = latestJob($pdo, 'answer_liked');
    same('retry', $retryJob['status'], 'failed outbox job remains durable');
    same(1, (int) $retryJob['attempts'], 'failed outbox attempt is counted');

    $retrySummary = $worker->run(
        100,
        new DateTimeImmutable((string) $retryJob['available_at'] . ' UTC'),
    );
    same(1, $retrySummary['delivered'], 'retry worker eventually delivers durable job');
    $retriedJob = latestJob($pdo, 'answer_liked');
    same('delivered', $retriedJob['status'], 'retried job reaches terminal delivered state');
    same(2, (int) $retriedJob['attempts'], 'retry increments attempt count');

    $leasedComment = $app->addComment(2, $answer['id'], 'リース回復テスト');
    $leaseJob = latestJob($pdo, 'comment_added');
    $lease = $pdo->prepare(
        "UPDATE notification_event_deliveries
         SET status = 'processing', claimed_at = '2000-01-01 00:00:00', claim_token = :token
         WHERE outbox_id = :id"
    );
    $lease->execute(['token' => str_repeat('0', 32), 'id' => $leaseJob['id']]);
    $leaseSummary = $worker->run();
    same(1, $leaseSummary['delivered'], 'stale per-device processing lease is reclaimed');
    same(
        $leasedComment['id'],
        payloadValue($provider, count($provider->deliveries) - 1, 'comment_id'),
        'reclaimed job keeps payload context',
    );

    // One recipient can have several devices. A success on one token must not
    // turn the parent row terminal while another token still needs a retry.
    $secondOwnerToken = str_repeat('e', 64);
    $app->registerPushToken(1, $secondOwnerToken, 'ios', 'sandbox');
    $app->setLike(2, $answer['id'], false);
    $partialLike = $app->setLike(2, $answer['id'], true);
    same(
        ['likesCount' => 2, 'isLiked' => true],
        $partialLike,
        'multi-device like mutation remains independent from provider delivery',
    );
    $partialJob = latestJob($pdo, 'answer_liked');
    same(2, count(deliveries($pdo, (int) $partialJob['id'])), 'recipient tokens are separate jobs');

    $partialProvider = new class ($secondOwnerToken) implements PushProvider {
        /** @var list<string> */
        public array $calls = [];
        public bool $failSecond = true;

        public function __construct(private readonly string $secondToken)
        {
        }

        public function send(string $deviceToken, string $environment, array $payload): array
        {
            $this->calls[] = $deviceToken;
            if ($this->failSecond && $deviceToken === $this->secondToken) {
                throw new RuntimeException('simulated second-device APNs failure');
            }
            return [
                'accepted' => true,
                'providerId' => 'partial-' . count($this->calls),
                'invalidToken' => false,
            ];
        }
    };
    $partialWorker = eventWorker($database, $crypto, $config, $partialProvider);
    $partialSummary = $partialWorker->run();
    same(2, $partialSummary['claimed'], 'both snapshotted devices are attempted');
    same(1, $partialSummary['delivered'], 'first device delivery is retained');
    same(1, $partialSummary['retried'], 'second device independently schedules retry');
    $partialJob = latestJob($pdo, 'answer_liked');
    same('retry', $partialJob['status'], 'parent remains nonterminal after partial success');
    same(1, (int) $partialJob['provider_delivered'], 'parent aggregates successful device');
    same(1, (int) $partialJob['provider_failed'], 'parent aggregates transient device failure');
    same(
        ['delivered', 'retry'],
        deliveryStatuses($pdo, (int) $partialJob['id']),
        'per-device success and retry states remain distinct',
    );
    same(1, tokenCallCount($partialProvider->calls, $tokens[1]), 'successful token called once');
    same(1, tokenCallCount($partialProvider->calls, $secondOwnerToken), 'failed token called once');

    $retryDelivery = retryDelivery($pdo, (int) $partialJob['id']);
    $partialProvider->failSecond = false;
    $partialRetry = $partialWorker->run(
        100,
        new DateTimeImmutable((string) $retryDelivery['available_at'] . ' UTC'),
    );
    same(1, $partialRetry['claimed'], 'retry claims only the failed device');
    same(1, $partialRetry['delivered'], 'failed device eventually delivers');
    same(1, tokenCallCount($partialProvider->calls, $tokens[1]), 'successful token is never redelivered');
    same(2, tokenCallCount($partialProvider->calls, $secondOwnerToken), 'only failed token is retried');
    $partialJob = latestJob($pdo, 'answer_liked');
    same('delivered', $partialJob['status'], 'parent becomes terminal after every device resolves');
    same(2, (int) $partialJob['provider_delivered'], 'parent records both delivered devices');
    same(1, (int) $partialJob['provider_failed'], 'transient failure history remains inspectable');
    same(
        ['delivered', 'delivered'],
        deliveryStatuses($pdo, (int) $partialJob['id']),
        'both device states finish delivered',
    );

    same(0, pendingCount($pdo), 'all due outbox jobs reach terminal state');
    same([], $pdo->query('PRAGMA foreign_key_check')->fetchAll(), 'outbox foreign keys remain valid');
    fwrite(STDOUT, "Event notification tests passed.\n");
} catch (Throwable $exception) {
    fwrite(STDERR, 'Event notification tests failed: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
} finally {
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

function eventWorker(
    Database $database,
    Crypto $crypto,
    Config $config,
    PushProvider $provider,
): EventNotificationWorker {
    return new EventNotificationWorker(
        $database,
        new PushDeliveryService($database, $crypto, $config, $provider),
    );
}

function ensurePreferences(PDO $pdo, int $userId): void
{
    $statement = $pdo->prepare(
        'INSERT OR IGNORE INTO notification_preferences (user_id) VALUES (:user)'
    );
    $statement->execute(['user' => $userId]);
}

/** @return list<array<string, mixed>> */
function jobs(PDO $pdo, string $eventType, ?int $commentId = null): array
{
    $sql = 'SELECT * FROM notification_event_outbox WHERE event_type = :event_type';
    $values = ['event_type' => $eventType];
    if ($commentId !== null) {
        $sql .= ' AND comment_id = :comment';
        $values['comment'] = $commentId;
    }
    $sql .= ' ORDER BY id ASC';
    $statement = $pdo->prepare($sql);
    $statement->execute($values);
    return $statement->fetchAll();
}

/** @return array<string, mixed> */
function latestJob(PDO $pdo, string $eventType): array
{
    $statement = $pdo->prepare(
        'SELECT * FROM notification_event_outbox
         WHERE event_type = :event_type ORDER BY id DESC LIMIT 1'
    );
    $statement->execute(['event_type' => $eventType]);
    $job = $statement->fetch();
    if (!is_array($job)) {
        throw new RuntimeException('Expected outbox job is missing.');
    }
    return $job;
}

/** @param list<array<string, mixed>> $jobs
 *  @return list<int>
 */
function recipients(array $jobs): array
{
    $recipients = array_map(static fn (array $job): int => (int) $job['recipient_user_id'], $jobs);
    sort($recipients, SORT_NUMERIC);
    return $recipients;
}

/** @param array<string, mixed> $job */
function jobData(array $job, string $key): mixed
{
    $data = json_decode((string) $job['data_json'], true, 32, JSON_THROW_ON_ERROR);
    return is_array($data) ? ($data[$key] ?? null) : null;
}

function pendingCount(PDO $pdo): int
{
    return (int) $pdo->query(
        "SELECT COUNT(*) FROM notification_event_outbox
         WHERE status IN ('pending', 'processing', 'retry')"
    )->fetchColumn();
}

/** @param list<array<string, mixed>> $jobs */
function deliveryCountForJobs(PDO $pdo, array $jobs): int
{
    if ($jobs === []) {
        return 0;
    }
    $ids = array_map(static fn (array $job): int => (int) $job['id'], $jobs);
    $statement = $pdo->query(
        'SELECT COUNT(*) FROM notification_event_deliveries WHERE outbox_id IN (' .
        implode(',', $ids) . ')'
    );
    return (int) $statement->fetchColumn();
}

/** @return list<array<string, mixed>> */
function deliveries(PDO $pdo, int $outboxId): array
{
    $statement = $pdo->prepare(
        'SELECT * FROM notification_event_deliveries WHERE outbox_id = :outbox ORDER BY id ASC'
    );
    $statement->execute(['outbox' => $outboxId]);
    return $statement->fetchAll();
}

/** @return list<string> */
function deliveryStatuses(PDO $pdo, int $outboxId): array
{
    $statuses = array_map(
        static fn (array $delivery): string => (string) $delivery['status'],
        deliveries($pdo, $outboxId),
    );
    sort($statuses, SORT_STRING);
    return $statuses;
}

/** @return array<string, mixed> */
function retryDelivery(PDO $pdo, int $outboxId): array
{
    $statement = $pdo->prepare(
        "SELECT * FROM notification_event_deliveries
         WHERE outbox_id = :outbox AND status = 'retry' LIMIT 1"
    );
    $statement->execute(['outbox' => $outboxId]);
    $delivery = $statement->fetch();
    if (!is_array($delivery)) {
        throw new RuntimeException('Expected retry delivery is missing.');
    }
    return $delivery;
}

/** @param list<string> $calls */
function tokenCallCount(array $calls, string $token): int
{
    return count(array_filter($calls, static fn (string $call): bool => $call === $token));
}

function category(DeterministicPushProvider $provider, int $index): mixed
{
    return $provider->deliveries[$index]['payload']['category'] ?? null;
}

function payloadValue(DeterministicPushProvider $provider, int $index, string $key): mixed
{
    return $provider->deliveries[$index]['payload'][$key] ?? null;
}

function alertBody(DeterministicPushProvider $provider, int $index): mixed
{
    return $provider->deliveries[$index]['payload']['aps']['alert']['body'] ?? null;
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

function truthy(bool $value, string $label): void
{
    if (!$value) {
        throw new RuntimeException($label . ': expected a truthy value.');
    }
}
