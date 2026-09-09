<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AppService;
use Tsutsuura\Server\App\DailyQuestionSchedule;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Push\DeterministicPushProvider;
use Tsutsuura\Server\Push\PushDeliveryService;
use Tsutsuura\Server\Push\PushProvider;
use Tsutsuura\Server\Push\QuestionReminderScheduler;
use Tsutsuura\Server\Security\Crypto;

require dirname(__DIR__) . '/src/Autoload.php';
date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$suffix = bin2hex(random_bytes(8));
$databasePath = sys_get_temp_dir() . '/tsutsuura-question-schedule-' . $suffix . '.sqlite';
$mediaPath = sys_get_temp_dir() . '/tsutsuura-question-media-' . $suffix;
foreach ([
    'APP_ENV' => 'testing', 'APP_DEBUG' => 'false', 'APP_KEY' => str_repeat('d3', 32),
    'APP_URL' => 'http://localhost', 'APP_TIMEZONE' => 'Asia/Tokyo',
    'CORS_ALLOWED_ORIGINS' => 'http://localhost:3000', 'DB_CONNECTION' => 'sqlite',
    'DB_DATABASE' => $databasePath, 'MEDIA_STORAGE_PATH' => $mediaPath,
    'DB_HOST' => 'localhost', 'DB_PORT' => '3306', 'DB_USERNAME' => '', 'DB_PASSWORD' => '',
    'OTP_DRIVER' => 'disabled', 'OTP_DEV_EXPOSE' => 'false', 'PUSH_DRIVER' => 'disabled',
] as $key => $value) {
    putenv($key . '=' . $value);
}

$database = null;
$pdo = null;
try {
    $config = Config::fromEnvironment($base);
    $database = new Database($config);
    $pdo = $database->connection();
    $migrations = glob($base . '/migrations/sqlite/*.sql') ?: [];
    sort($migrations, SORT_STRING);
    foreach ($migrations as $file) {
        $pdo->exec((string) file_get_contents($file));
    }
    // Match an existing installation: a legacy seed row and a custom question
    // keep their IDs, active flags and metadata when the catalog is extended.
    $pdo->exec("INSERT INTO questions (prompt, is_active, publish_start_minute, publish_end_minute)
                VALUES ('最近「ありがとう」と思ったことは？', 1, 600, 660)");
    $legacyId = (int) $pdo->lastInsertId();
    $seed = (string) file_get_contents($base . '/seeds/001_questions.sql');
    $pdo->exec($seed);
    same(370, (int) $pdo->query('SELECT COUNT(*) FROM questions')->fetchColumn(), 'yearly catalog count');
    same(370, (int) $pdo->query('SELECT COUNT(DISTINCT prompt) FROM questions')->fetchColumn(), 'all prompts unique');
    $pdo->exec($seed);
    same(370, (int) $pdo->query('SELECT COUNT(*) FROM questions')->fetchColumn(), 'reseed is idempotent');
    same('最近「ありがとう」と思ったことは？', (string) $pdo->query('SELECT prompt FROM questions WHERE id = ' . $legacyId)->fetchColumn(), 'legacy ID preserved');
    same(600, (int) $pdo->query('SELECT publish_start_minute FROM questions WHERE id = ' . $legacyId)->fetchColumn(), 'custom existing publishing time preserved');
    same(0, (int) $pdo->query("SELECT COUNT(*) FROM questions WHERE prompt LIKE '今日%' AND publish_start_minute < 1020")->fetchColumn(), 'experience questions arrive in evening');
    foreach ($pdo->query('SELECT prompt FROM questions')->fetchAll(PDO::FETCH_COLUMN) as $prompt) {
        check(mb_strlen((string) $prompt, 'UTF-8') < 100, 'prompts are short enough to read on phone');
    }
    $pdo->exec("INSERT INTO users (display_name) VALUES ('花'), ('空'), ('森'), ('海');
                INSERT INTO families (name, invite_code) VALUES ('花の家族', 'SCHEDULE1'), ('森の家族', 'SCHEDULE2');
                INSERT INTO family_members (family_id, user_id, role) VALUES
                    (1, 1, 'owner'), (1, 2, 'member'), (2, 3, 'owner')");
    $schedule = new DailyQuestionSchedule($database, $config);
    $timezone = new DateTimeZone('Asia/Tokyo');
    $start = new DateTimeImmutable('2028-01-01 08:00:00', $timezone);
    $seenQuestions = [];
    $seenTimes = [];
    $familyTimeDifferences = 0;
    foreach (range(0, 369) as $day) {
        $now = $start->modify('+' . $day . ' days');
        $row = $schedule->forFamily(1, $now);
        $otherFamily = $schedule->forFamily(2, $now);
        same(false, $row['is_available'], 'not published at eight');
        $at = (new DateTimeImmutable($row['available_at'], new DateTimeZone('UTC')))->setTimezone($timezone);
        same($now->format('Y-m-d'), $at->format('Y-m-d'), 'publication stays on app calendar date');
        check($at->format('H:i') >= '09:00' && $at->format('H:i') <= '19:00', 'safe publication window');
        if (str_starts_with($row['prompt'], '今日')) {
            check($at->format('H:i') >= '17:00', 'same-day experiences publish after seventeen');
        }
        $seenQuestions[(string) $row['id']] = true;
        $seenTimes[$at->format('H:i')] = true;
        $familyTimeDifferences += $row['available_at'] !== $otherFamily['available_at'] ? 1 : 0;
        $reloaded = (new DailyQuestionSchedule(new Database($config), $config))->forFamily(1, $now);
        same($row, $reloaded, 'reload uses the durable question and time');
    }
    same(370, count($seenQuestions), 'full catalog rotation has no repeated question');
    check(count($seenTimes) > 100, 'publishing times vary across days');
    check($familyTimeDifferences > 350, 'families have independent publishing times');

    $date = '2030-06-15';
    $pdo->exec("INSERT INTO questions
                (prompt, available_on, publish_start_minute, publish_end_minute)
                VALUES ('今日、試して楽しかったことは？', '$date', 1020, 1020)");
    $specialId = (string) $pdo->lastInsertId();
    $now = new DateTimeImmutable($date . ' 16:59:59', $timezone);
    $crypto = new Crypto($config->appKey);
    $app = new AppService($database, $crypto, $config, clock: static function () use (&$now): DateTimeImmutable { return $now; });
    $today = $app->todayQuestion(1);
    same($specialId, $today['question']['id'], 'date-specific question overrides rotation');
    same('', $today['question']['prompt'], 'unpublished prompt is not leaked');
    same(false, $today['question']['isAvailable'], 'today availability contract');
    same('2030-06-15T08:00:00Z', $today['question']['availableAt'], 'UTC publishing contract');
    same('Asia/Tokyo', $today['question']['timeZoneIdentifier'], 'publication timezone is explicit');
    $home = $app->home(1);
    same($today['question'], $home['todayQuestion'], 'home and today agree before release');
    rejected('question_not_published', static fn() => $app->submitTodayAnswer(1, 'まだ投稿できない'));
    same(0, (int) $pdo->query('SELECT COUNT(*) FROM answers')->fetchColumn(), 'pre-release request saves nothing');

    $provider = new DeterministicPushProvider();
    foreach ([1 => 'a', 2 => 'b', 3 => 'c', 4 => 'd'] as $id => $token) {
        $app->registerPushToken($id, str_repeat($token, 64), 'ios', 'sandbox');
    }
    $pdo->exec("INSERT INTO notification_preferences (user_id, timezone, question_reminder_time)
                VALUES (1, 'Asia/Tokyo', '00:01'), (2, 'Asia/Tokyo', '23:59'),
                       (3, 'America/Toronto', '09:00'), (4, 'Asia/Tokyo', '09:00')");
    $scheduler = new QuestionReminderScheduler($database, $config, new PushDeliveryService($database, $crypto, $config, $provider));
    same(0, $scheduler->run($now)['delivered'], 'no reminder before publication despite old preference');
    $now = new DateTimeImmutable($date . ' 17:00:00', $timezone);
    $released = $app->todayQuestion(1);
    same(true, $released['question']['isAvailable'], 'available at exact publishing minute');
    same('今日、試して楽しかったことは？', $released['question']['prompt'], 'prompt appears at publishing time');
    $pdo->exec("UPDATE notification_preferences SET quiet_start = '16:00', quiet_end = '18:00' WHERE user_id = 2");
    $sent = $scheduler->run($now);
    same(1, $sent['delivered'], 'quiet user, sleeping overseas user and familyless user excluded');
    same($specialId, $provider->deliveries[0]['payload']['question_id'], 'reminder uses same scheduled question');
    same(0, $scheduler->run($now)['reserved'], 'reminder once per question day');
    same(1, (int) $pdo->query('SELECT COUNT(*) FROM notification_reminder_dispatches')->fetchColumn(), 'quiet hours reserve nothing');
    $now = new DateTimeImmutable($date . ' 18:00:00', $timezone);
    same(1, $scheduler->run($now)['delivered'], 'quiet-hour reminder sends after quiet period');
    $answer = $app->submitTodayAnswer(1, '新しいお茶を飲みました。');
    same($specialId, $answer['question']['id'], 'answer matches published question');
    // Changing tomorrow's catalog cannot move an already assigned release.
    $pdo->exec("UPDATE questions SET publish_start_minute = 1140, publish_end_minute = 1140 WHERE id = $specialId");
    same($released['question']['availableAt'], $app->todayQuestion(1)['question']['availableAt'], 'metadata edit cannot reschedule existing publication');
    $pdo->exec("UPDATE notification_preferences SET quiet_start = NULL, quiet_end = NULL, timezone = 'Asia/Tokyo' WHERE user_id = 3");
    $now = new DateTimeImmutable($date . ' 20:00:00', $timezone);
    same(0, $scheduler->run($now)['delivered'], 'no question reminders at twenty or later');
    $now = new DateTimeImmutable('2030-06-16 08:59:59', $timezone);
    same(0, $scheduler->run($now)['delivered'], 'no question reminders in early morning');
    $now = new DateTimeImmutable('2030-06-16 19:30:00', $timezone);
    $app->submitTodayAnswer(1, 'もう答えました。');
    $pdo->exec("UPDATE notification_preferences SET question_reminders_enabled = 0 WHERE user_id IN (2, 3)");
    $now = new DateTimeImmutable('2030-06-16 19:00:00', $timezone);
    same(0, $scheduler->run($now)['delivered'], 'already answered users do not get reminders');

    // A release at the maximum 19:00 minute still gets its reminder. Seconds
    // of cron jitter are allowed, but 19:01 must not reserve or send anything.
    $pdo->exec("UPDATE notification_preferences SET question_reminders_enabled = 0 WHERE user_id IN (1, 2);
                UPDATE notification_preferences SET question_reminders_enabled = 1, timezone = 'Asia/Tokyo' WHERE user_id = 3;
                INSERT INTO questions (prompt, available_on, publish_start_minute, publish_end_minute)
                VALUES ('今日の最後に伝えたいことは？', '2030-06-17', 1140, 1140)");
    $now = new DateTimeImmutable('2030-06-17 18:59:59', $timezone);
    same(0, $scheduler->run($now)['reserved'], 'latest release stays unavailable before nineteen');
    $now = new DateTimeImmutable('2030-06-17 19:01:00', $timezone);
    same(0, $scheduler->run($now)['reserved'], 'cutoff excludes nineteen-oh-one before any dispatch exists');
    $now = new DateTimeImmutable('2030-06-17 19:00:59', $timezone);
    same(1, $scheduler->run($now)['delivered'], 'latest publication sends during its final allowed minute');

    // Toronto's daylight-saving transition changes its UTC offset. Recipient
    // daytime still opens at local 09:00 while publication uses Tokyo's day.
    $pdo->exec("UPDATE notification_preferences SET timezone = 'America/Toronto' WHERE user_id = 3");
    $toronto = new DateTimeZone('America/Toronto');
    foreach (['2030-03-09', '2030-03-10'] as $localDay) {
        $now = new DateTimeImmutable($localDay . ' 08:59:59', $toronto);
        same(0, $scheduler->run($now)['reserved'], 'recipient reminder waits until nine around DST');
        $now = new DateTimeImmutable($localDay . ' 09:00:00', $toronto);
        same(1, $scheduler->run($now)['delivered'], 'recipient local nine follows DST offset');
    }

    // A short APNs outage must not consume the only reminder for the day.
    // Retry only after backoff, and recheck quiet hours before claiming it.
    $pdo->exec("UPDATE notification_preferences SET timezone = 'Asia/Tokyo' WHERE user_id = 3;
                INSERT INTO questions (prompt, available_on, publish_start_minute, publish_end_minute)
                VALUES ('少し前にうれしかったことは？', '2030-07-01', 540, 540)");
    $retryProvider = new class implements PushProvider {
        public int $attempts = 0;
        public function send(string $deviceToken, string $environment, array $payload): array
        {
            $this->attempts++;
            return ['accepted' => $this->attempts > 1, 'providerId' => null, 'invalidToken' => false];
        }
    };
    $retryScheduler = new QuestionReminderScheduler(
        $database, $config, new PushDeliveryService($database, $crypto, $config, $retryProvider),
    );
    $retryAt = new DateTimeImmutable('2030-07-01 12:00:00', $timezone);
    same(1, $retryScheduler->run($retryAt)['failed'], 'provider failure is recorded');
    same(0, $retryScheduler->run($retryAt)['reserved'], 'immediate rerun cannot hammer APNs');
    same(0, $retryScheduler->run($retryAt->modify('+4 minutes 59 seconds'))['reserved'], 'retry waits five full minutes');
    same(1, $retryProvider->attempts, 'backoff suppresses provider calls');
    $pdo->exec("UPDATE notification_preferences SET quiet_start = '12:00', quiet_end = '13:00' WHERE user_id = 3");
    same(0, $retryScheduler->run($retryAt->modify('+5 minutes'))['reserved'], 'retry still respects new quiet hours');
    $pdo->exec("UPDATE notification_preferences SET quiet_start = NULL, quiet_end = NULL WHERE user_id = 3");
    same(1, $retryScheduler->run($retryAt->modify('+5 minutes'))['delivered'], 'failed reminder recovers after backoff');
    same(2, $retryProvider->attempts, 'only failed delivery is retried');
    same(0, $retryScheduler->run($retryAt->modify('+10 minutes'))['reserved'], 'successful retry is not repeated');

    // Daily reservations are per account. If one of its devices succeeds,
    // retain completion rather than redelivering to the successful device.
    $app->registerPushToken(3, str_repeat('e', 64), 'ios', 'sandbox');
    $pdo->exec("INSERT INTO questions (prompt, available_on, publish_start_minute, publish_end_minute)
                VALUES ('最近見つけた小さな楽しみは？', '2030-07-02', 540, 540)");
    $partialProvider = new class implements PushProvider {
        public int $attempts = 0;
        public function send(string $deviceToken, string $environment, array $payload): array
        {
            $this->attempts++;
            return ['accepted' => $deviceToken === str_repeat('c', 64), 'providerId' => null, 'invalidToken' => false];
        }
    };
    $partialScheduler = new QuestionReminderScheduler(
        $database, $config, new PushDeliveryService($database, $crypto, $config, $partialProvider),
    );
    $partialAt = new DateTimeImmutable('2030-07-02 12:00:00', $timezone);
    $partialResult = $partialScheduler->run($partialAt);
    same(1, $partialResult['delivered'], 'one device accepts the reminder');
    same(1, $partialResult['failed'], 'other device failure remains visible');
    same(0, $partialScheduler->run($partialAt->modify('+5 minutes'))['reserved'], 'partial delivery does not duplicate successful device');
    same(2, $partialProvider->attempts, 'partially completed dispatch does not call provider again');

    $pdo->exec("INSERT INTO questions (prompt, available_on, publish_start_minute, publish_end_minute)
                VALUES ('今日、誰かに伝えたい思い出は？', '2030-07-03', 1140, 1140)");
    $lateFailureProvider = new DeterministicPushProvider(accept: false);
    $lateFailureScheduler = new QuestionReminderScheduler(
        $database, $config, new PushDeliveryService($database, $crypto, $config, $lateFailureProvider),
    );
    $lateAt = new DateTimeImmutable('2030-07-03 19:00:59', $timezone);
    same(2, $lateFailureScheduler->run($lateAt)['failed'], 'latest-minute provider failures are recorded');
    same(0, $lateFailureScheduler->run($lateAt->modify('+5 minutes'))['reserved'], 'retry cannot send after daytime cutoff');

    // A family with an answer created before the schedule rollout must keep
    // that question available, even before the new normal daytime window.
    $pdo->exec("INSERT INTO answers (family_id, question_id, user_id, answer_date, body)
                VALUES (2, $legacyId, 3, '2031-01-02', '以前のアプリで回答済み')");
    $legacyDay = $schedule->forFamily(2, new DateTimeImmutable('2031-01-02 06:00:00', $timezone));
    same($legacyId, (int) $legacyDay['id'], 'rollout preserves already answered question');
    same(true, $legacyDay['is_available'], 'rollout does not hide existing answer');
    echo "question schedule test passed: 370 unique questions, release gating, stable rotation, quiet hours, notification retries and no duplicate successes\n";
} finally {
    $pdo = null;
    $database = null;
    foreach ([$databasePath, $databasePath . '-wal', $databasePath . '-shm'] as $path) {
        if (is_file($path)) {
            unlink($path);
        }
    }
    if (is_dir($mediaPath)) {
        rmdir($mediaPath);
    }
}

function same(mixed $expected, mixed $actual, string $message): void
{
    if ($expected !== $actual) {
        throw new RuntimeException($message . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}
function check(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}
function rejected(string $code, callable $operation): void
{
    try {
        $operation();
    } catch (ApiException $error) {
        same($code, $error->errorCode, 'rejection code');
        same(409, $error->status, 'rejection status');
        return;
    }
    throw new RuntimeException('Expected rejection ' . $code);
}
