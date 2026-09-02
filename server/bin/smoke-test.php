<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AppService;
use Tsutsuura\Server\App\AnswerMediaService;
use Tsutsuura\Server\App\FamilySetupService;
use Tsutsuura\Server\App\LifecycleService;
use Tsutsuura\Server\Auth\DisabledSmsSender;
use Tsutsuura\Server\Auth\OtpService;
use Tsutsuura\Server\Auth\PhoneNumber;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Auth\SmsSender;
use Tsutsuura\Server\Auth\UserService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Http\Request;
use Tsutsuura\Server\Http\UploadedFile;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;
use Tsutsuura\Server\Push\ApnsPushProvider;
use Tsutsuura\Server\Push\DeterministicPushProvider;
use Tsutsuura\Server\Push\PushDeliveryService;
use Tsutsuura\Server\Push\QuestionReminderScheduler;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$databasePath = sys_get_temp_dir() . '/tsutsuura-smoke-' . bin2hex(random_bytes(8)) . '.sqlite';
$mediaDirectory = sys_get_temp_dir() . '/tsutsuura-media-' . bin2hex(random_bytes(8));
$temporaryFiles = [];
$environment = [
    'APP_ENV' => 'testing',
    'APP_DEBUG' => 'false',
    'APP_KEY' => str_repeat('a1', 32),
    'APP_URL' => 'http://localhost',
    'APP_TIMEZONE' => 'Asia/Tokyo',
    'CORS_ALLOWED_ORIGINS' => 'http://localhost:3000',
    'DB_CONNECTION' => 'sqlite',
    'DB_DATABASE' => $databasePath,
    'MEDIA_STORAGE_PATH' => $mediaDirectory,
    'DB_HOST' => 'localhost',
    'DB_PORT' => '3306',
    'DB_USERNAME' => '',
    'DB_PASSWORD' => '',
    'OTP_DRIVER' => 'log',
    'OTP_DEV_EXPOSE' => 'false',
    'PUSH_DRIVER' => 'disabled',
];
foreach ($environment as $key => $value) {
    putenv($key . '=' . $value);
}

try {
    $config = Config::fromEnvironment($base);
    $database = new Database($config);
    $pdo = $database->connection();
    $seed = file_get_contents($base . '/seeds/001_questions.sql');
    if ($seed === false) {
        throw new RuntimeException('Test fixtures could not be read.');
    }
    $migrationFiles = glob($base . '/migrations/sqlite/*.sql') ?: [];
    sort($migrationFiles, SORT_STRING);
    foreach ($migrationFiles as $migrationFile) {
        $migration = file_get_contents($migrationFile);
        if ($migration === false) {
            throw new RuntimeException('Test migration could not be read.');
        }
        $pdo->exec($migration);
    }
    $pdo->exec($seed);

    $crypto = new Crypto($config->appKey);
    same('secret payload', $crypto->decrypt($crypto->encrypt('secret payload')), 'encryption round trip');
    same('+819012345678', PhoneNumber::normalize('090-1234-5678'), 'Japanese phone normalization');

    $sms = new class implements SmsSender {
        public string $code = '';
        public function sendOtp(string $phone, string $code): void
        {
            $this->code = $code;
        }
    };
    $users = new UserService($database);
    $sessions = new SessionService($database, $crypto, $config);
    $rateLimiter = new RateLimiter($database, $crypto);
    $otp = new OtpService(
        $database,
        $crypto,
        $rateLimiter,
        $sms,
        $users,
        $sessions,
        $config,
    );
    $users->findOrCreateByPhone('+819012345678');
    $challenge = $otp->request('090-1234-5678', '127.0.0.1');
    truthy(isset($challenge['requestId']) && $sms->code !== '', 'OTP request');
    $loginCode = $sms->code;
    $invalidLoginKey = 'smoke-phone-login-invalid-0001';
    apiError(
        static fn () => $otp->verify(
            $challenge['requestId'],
            '000000',
            '127.0.0.1',
            $invalidLoginKey,
        ),
        422,
        'invalid_otp',
        'OTP invalid code',
    );
    apiError(
        static fn () => $otp->verify(
            $challenge['requestId'],
            '000000',
            '127.0.0.1',
            $invalidLoginKey,
        ),
        422,
        'invalid_otp',
        'OTP invalid outcome exact replay',
    );
    $otpAttempts = $pdo->prepare(
        'SELECT attempts FROM phone_otp_challenges WHERE request_id = :request'
    );
    $otpAttempts->execute(['request' => $challenge['requestId']]);
    same(1, (int) $otpAttempts->fetchColumn(), 'OTP invalid replay increments only once');
    $otpAttempts->closeCursor();
    $loginVerificationKey = 'smoke-phone-login-verify-0001';
    $auth = $otp->verify(
        $challenge['requestId'],
        $loginCode,
        '127.0.0.1',
        $loginVerificationKey,
    );
    truthy(isset($auth['token'], $auth['user']['id']), 'OTP verify and session issuance');
    same(
        $auth,
        $otp->verify(
            $challenge['requestId'],
            $loginCode,
            '127.0.0.1',
            $loginVerificationKey,
        ),
        'OTP verification exact response replay',
    );
    apiError(
        static fn () => $otp->verify(
            $challenge['requestId'],
            '000000',
            '127.0.0.1',
            $loginVerificationKey,
        ),
        409,
        'idempotency_key_reused',
        'OTP verification idempotency content binding',
    );
    same(false, array_key_exists('hasLine', $auth['user']), 'auth response omits removed provider metadata');
    $userId = (int) $auth['user']['id'];
    $maximumName = str_repeat('名', 80);
    $maximumComposedName = str_repeat("e\u{0301}", 40);
    $oversizedComposedName = $maximumComposedName . 'e';
    same(
        $maximumName,
        $users->updateProfile($userId, $maximumName)['display_name'],
        'profile name accepts the documented 80-character boundary',
    );
    apiError(
        static fn () => $users->updateProfile($userId, str_repeat('名', 81)),
        422,
        'invalid_display_name',
        'profile name rejects 81 characters',
    );
    same(
        $maximumComposedName,
        $users->updateProfile($userId, $maximumComposedName)['display_name'],
        'profile name accepts 80 Unicode code points across 40 composed glyphs',
    );
    apiError(
        static fn () => $users->updateProfile($userId, $oversizedComposedName),
        422,
        'invalid_display_name',
        'profile name rejects 81 Unicode code points across composed glyphs',
    );
    $users->updateProfile($userId, 'つつうら');

    $unknownChallenge = $otp->request('080-1111-2222', '127.0.0.11');
    $unknownCode = $sms->code;
    $unknownVerificationKey = 'smoke-phone-login-unknown-0001';
    apiError(
        static fn () => $otp->verify(
            $unknownChallenge['requestId'],
            $unknownCode,
            '127.0.0.11',
            $unknownVerificationKey,
        ),
        404,
        'account_not_found',
        'unknown phone does not provision an accidental account',
    );
    apiError(
        static fn () => $otp->verify(
            $unknownChallenge['requestId'],
            $unknownCode,
            '127.0.0.11',
            $unknownVerificationKey,
        ),
        404,
        'account_not_found',
        'unknown phone terminal outcome exact replay',
    );
    $unknownPhoneCount = $pdo->prepare('SELECT COUNT(*) FROM users WHERE phone_e164 = :phone');
    $unknownPhoneCount->execute(['phone' => '+818011112222']);
    same(0, (int) $unknownPhoneCount->fetchColumn(), 'unknown OTP phone remains unprovisioned');
    $unknownPhoneCount->closeCursor();

    $exhaustedChallenge = $otp->request('090-1234-5678', '127.0.0.12');
    $exhaustedCode = $sms->code;
    for ($attempt = 0; $attempt < $config->otpMaxAttempts; $attempt++) {
        apiError(
            static fn () => $otp->verify(
                $exhaustedChallenge['requestId'],
                '000000',
                '127.0.0.12',
            ),
            422,
            'invalid_otp',
            'OTP max-attempt increment ' . $attempt,
        );
    }
    $otpAttempts->execute(['request' => $exhaustedChallenge['requestId']]);
    same($config->otpMaxAttempts, (int) $otpAttempts->fetchColumn(), 'OTP attempt cap persists');
    apiError(
        static fn () => $otp->verify(
            $exhaustedChallenge['requestId'],
            $exhaustedCode,
            '127.0.0.12',
        ),
        422,
        'invalid_otp',
        'OTP correct code rejected after attempt cap',
    );

    $answerMedia = new AnswerMediaService($database, $crypto, $config);
    $app = new AppService($database, $crypto, $config, $answerMedia);
    $lifecycle = new LifecycleService(
        $database,
        $crypto,
        $config,
        $sessions,
        $answerMedia,
    );
    $family = $app->family($userId);
    same(1, count($family['members']), 'default family provisioning');
    $today = $app->todayQuestion($userId);
    truthy(isset($today['question']['prompt']), 'today question');
    $answer = $app->submitTodayAnswer($userId, '今日はいい日でした。');
    same('今日はいい日でした。', $answer['body'], 'answer submission');
    same([], $answer['media'], 'text answer has empty media array');
    same(
        $answer['id'],
        $app->answerById($userId, (string) $answer['id'])['id'],
        'answer detail lookup for current family',
    );

    $audioPath = sys_get_temp_dir() . '/tsutsuura-audio-' . bin2hex(random_bytes(8)) . '.m4a';
    $photoPath = sys_get_temp_dir() . '/tsutsuura-photo-' . bin2hex(random_bytes(8)) . '.png';
    $invalidPhotoPath = sys_get_temp_dir() . '/tsutsuura-invalid-photo-' . bin2hex(random_bytes(8)) . '.txt';
    $temporaryFiles = [$audioPath, $photoPath, $invalidPhotoPath];
    file_put_contents(
        $audioPath,
        pack('N', 24) . 'ftypM4A ' . pack('N', 0) . 'M4A isom' . str_repeat("\0", 100),
    );
    file_put_contents(
        $photoPath,
        base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            true,
        ),
    );
    file_put_contents($invalidPhotoPath, 'not an image');
    $answer = $app->submitTodayAnswer(
        $userId,
        '',
        UploadedFile::fromLocalFile($audioPath, "../voice\r\n.m4a"),
        [UploadedFile::fromLocalFile($photoPath, '../../思い出.png')],
        '12345',
        true,
    );
    same('', $answer['body'], 'media-only answer body');
    same(2, count($answer['media']), 'audio and photo presentation');
    same('audio', $answer['media'][0]['kind'], 'audio media ordering');
    same('audio/mp4', $answer['media'][0]['mimeType'], 'audio MIME normalization');
    same(12345, $answer['media'][0]['durationMilliseconds'], 'audio duration metadata');
    same('photo', $answer['media'][1]['kind'], 'photo media ordering');
    same('image/png', $answer['media'][1]['mimeType'], 'photo MIME validation');
    same('思い出.png', $answer['media'][1]['fileName'], 'media filename sanitization');
    truthy($answer['media'][0]['byteCount'] > 0, 'media byte metadata');
    $mediaUrlPath = (string) parse_url($answer['media'][0]['url'], PHP_URL_PATH);
    truthy(
        preg_match('#/v1/answer-media/([1-9][0-9]*)/([a-f0-9]{64})$#', $mediaUrlPath, $mediaUrl) === 1,
        'authenticated media URL shape',
    );
    $download = $answerMedia->download($userId, $mediaUrl[1], $mediaUrl[2]);
    same(hash_file('sha256', $audioPath), hash_file('sha256', $download['path']), 'stored media bytes');
    apiError(
        static fn () => $answerMedia->download($userId, $mediaUrl[1], str_repeat('0', 64)),
        404,
        'media_not_found',
        'invalid media capability token',
    );
    $answer = $app->submitTodayAnswer($userId, '文字を更新しました。');
    same(2, count($answer['media']), 'JSON update preserves answer media');
    $answer = $app->updateAnswer($userId, $answer['id'], '所有者が本文を編集しました。');
    same('所有者が本文を編集しました。', $answer['body'], 'answer owner edit');
    $answer = $app->deleteAnswerMedia(
        $userId,
        $answer['id'],
        $answer['media'][0]['id'],
    );
    same(1, count($answer['media']), 'individual answer media deletion');
    same(false, is_file($download['path']), 'individual media physical cleanup');
    $remainingMediaPath = (string) parse_url($answer['media'][0]['url'], PHP_URL_PATH);
    truthy(
        preg_match('#/v1/answer-media/([1-9][0-9]*)/([a-f0-9]{64})$#', $remainingMediaPath, $remainingMediaUrl) === 1,
        'remaining media URL shape',
    );
    $remainingDownload = $answerMedia->download(
        $userId,
        $remainingMediaUrl[1],
        $remainingMediaUrl[2],
    );
    $answer = $app->updateAnswer($userId, $answer['id'], '');
    apiError(
        static fn () => $app->deleteAnswerMedia(
            $userId,
            $answer['id'],
            $answer['media'][0]['id'],
        ),
        409,
        'answer_would_be_empty',
        'last media cannot leave an empty answer',
    );
    $answer = $app->updateAnswer($userId, $answer['id'], '本文を戻しました。');
    $maximumComposedAnswer = str_repeat("e\u{0301}", 1_000);
    $oversizedComposedAnswer = $maximumComposedAnswer . 'e';
    same(
        $maximumComposedAnswer,
        $app->updateAnswer(
            $userId,
            $answer['id'],
            $maximumComposedAnswer,
        )['body'],
        'answer accepts 2000 Unicode code points across composed glyphs',
    );
    apiError(
        static fn () => $app->updateAnswer(
            $userId,
            $answer['id'],
            $oversizedComposedAnswer,
        ),
        422,
        'invalid_answer',
        'answer rejects 2001 Unicode code points across composed glyphs',
    );
    $answer = $app->updateAnswer($userId, $answer['id'], '本文を戻しました。');
    putenv('ANSWER_MEDIA_FAMILY_QUOTA_BYTES=200');
    $quotaConfig = Config::fromEnvironment($base);
    $quotaMedia = new AnswerMediaService($database, $crypto, $quotaConfig);
    $quotaApp = new AppService($database, $crypto, $quotaConfig, $quotaMedia);
    apiError(
        static fn () => $quotaApp->submitTodayAnswer(
            $userId,
            'quota test',
            UploadedFile::fromLocalFile($audioPath, 'voice.m4a'),
            [
                UploadedFile::fromLocalFile($photoPath, 'one.png'),
                UploadedFile::fromLocalFile($photoPath, 'two.png'),
            ],
            null,
            true,
        ),
        422,
        'media_quota_exceeded',
        'family media quota',
    );
    same(1, count($app->todayQuestion($userId)['answer']['media']), 'quota rejection preserves media');
    putenv('ANSWER_MEDIA_FAMILY_QUOTA_BYTES=2147483648');
    apiError(
        static fn () => $app->submitTodayAnswer($userId, '', null, [], null, true),
        422,
        'invalid_answer',
        'empty multipart answer',
    );
    apiError(
        static fn () => $app->submitTodayAnswer(
            $userId,
            "\xc3\x28",
            null,
            [UploadedFile::fromLocalFile($photoPath, 'photo.png')],
            null,
            true,
        ),
        422,
        'invalid_answer',
        'multipart answer UTF-8 validation',
    );
    apiError(
        static fn () => $app->submitTodayAnswer(
            $userId,
            'invalid photo',
            null,
            [UploadedFile::fromLocalFile($invalidPhotoPath, 'bad.png')],
            null,
            true,
        ),
        422,
        'invalid_photo_type',
        'photo content validation',
    );
    apiError(
        static fn () => $app->submitTodayAnswer(
            $userId,
            'too many photos',
            null,
            array_fill(0, 5, UploadedFile::fromLocalFile($photoPath, 'photo.png')),
            null,
            true,
        ),
        422,
        'too_many_photos',
        'photo count validation',
    );
    $history = $app->history($userId, null, 20);
    same(1, count($history['items']), 'history feed');
    $filterUserInsert = $pdo->prepare('INSERT INTO users (display_name) VALUES (:name)');
    $filterUserInsert->execute(['name' => 'Élodie']);
    $filterUserId = (int) $pdo->lastInsertId();
    $filterMembership = $pdo->prepare(
        "INSERT INTO family_members (family_id, user_id, role) VALUES (:family, :user, 'member')"
    );
    $filterMembership->execute(['family' => $family['id'], 'user' => $filterUserId]);
    $filterAnswerInsert = $pdo->prepare(
        'INSERT INTO answers (family_id, question_id, user_id, answer_date, body)
         VALUES (:family, :question, :user, :date, :body)'
    );
    $filterAnswerInsert->execute([
        'family' => $family['id'],
        'question' => $today['question']['id'],
        'user' => $filterUserId,
        'date' => '2024-01-02',
        'body' => '検索語を含む古い回答',
    ]);
    $firstFilterAnswerId = (int) $pdo->lastInsertId();
    $filterAnswerInsert->execute([
        'family' => $family['id'],
        'question' => $today['question']['id'],
        'user' => $filterUserId,
        'date' => '2024-02-03',
        'body' => '別の日の回答',
    ]);
    $secondFilterAnswerId = (int) $pdo->lastInsertId();

    $firstPage = $app->history($userId, null, 1);
    same(1, count($firstPage['items']), 'history first page size');
    truthy($firstPage['nextCursor'] !== null, 'history first page cursor');
    $secondPage = $app->history($userId, $firstPage['nextCursor'], 1);
    same(1, count($secondPage['items']), 'history second page size');
    truthy($firstPage['items'][0]['id'] !== $secondPage['items'][0]['id'], 'history cursor advances');
    same(
        1,
        count($app->history($userId, null, 20, ['search' => '検索語'])['items']),
        'history literal search filter',
    );
    same(
        2,
        count($app->history($userId, null, 20, ['search' => 'eLoDiE'])['items']),
        'history search folds author-name case and diacritics',
    );
    same(
        2,
        count($app->history($userId, null, 20, ['search' => "E\u{0301}LODIE"])['items']),
        'history search treats composed and decomposed author names equivalently',
    );
    $maximumComposedSearch = str_repeat("e\u{0301}", 50);
    same(
        0,
        count($app->history(
            $userId,
            null,
            20,
            ['search' => $maximumComposedSearch],
        )['items']),
        'history search accepts 100 Unicode code points',
    );
    apiError(
        static fn () => $app->history(
            $userId,
            null,
            20,
            ['search' => $maximumComposedSearch . 'e'],
        ),
        422,
        'invalid_search',
        'history search rejects 101 Unicode code points',
    );
    same(
        1,
        count($app->history($userId, null, 20, [
            'from' => '2024-02-01',
            'to' => '2024-02-29',
        ])['items']),
        'history date range filter',
    );
    same(
        1,
        count($app->history($userId, null, 20, ['date' => '2024-01-02'])['items']),
        'history exact date filter',
    );
    same(
        2,
        count($app->history($userId, null, 20, ['authorId' => (string) $filterUserId])['items']),
        'history author filter',
    );
    same(
        1,
        count($app->history($userId, null, 20, ['scope' => 'mine'])['items']),
        'history mine scope',
    );
    apiError(
        static fn () => $app->history($userId, null, 20, ['from' => '2024-02-30']),
        422,
        'invalid_date_filter',
        'history date validation',
    );
    apiError(
        static fn () => $app->history($userId, null, 20, ['scope' => 'everyone']),
        422,
        'invalid_scope',
        'history scope validation',
    );
    apiError(
        static fn () => $app->history($userId, null, 20, ['authorId' => '999999']),
        422,
        'invalid_author_filter',
        'history family-author validation',
    );
    apiError(
        static fn () => $app->updateAnswer($filterUserId, $answer['id'], '不正な編集'),
        404,
        'answer_not_found',
        'answer edit ownership',
    );
    apiError(
        static fn () => $app->deleteAnswerMedia(
            $filterUserId,
            $answer['id'],
            $answer['media'][0]['id'],
        ),
        404,
        'answer_not_found',
        'answer media deletion ownership',
    );
    $app->deleteAnswer($filterUserId, (string) $firstFilterAnswerId);
    same(
        1,
        count($app->history($userId, null, 20, ['authorId' => (string) $filterUserId])['items']),
        'answer owner deletion',
    );
    apiError(
        static fn () => $app->setLike($userId, $answer['id'], true),
        422,
        'self_like_not_allowed',
        'self-like rejection',
    );
    $commentRequestKey = 'smoke-comment-create-key-0001';
    $comment = $app->addComment(
        $userId,
        $answer['id'],
        'すてき！',
        null,
        $commentRequestKey,
    );
    same('すてき！', $comment['body'], 'comment');
    $originalComment = $comment;
    $maximumComposedComment = str_repeat("e\u{0301}", 500);
    same(
        $maximumComposedComment,
        $app->updateComment(
            $userId,
            $comment['id'],
            $maximumComposedComment,
        )['body'],
        'comment accepts 1000 Unicode code points',
    );
    apiError(
        static fn () => $app->updateComment(
            $userId,
            $comment['id'],
            $maximumComposedComment . 'e',
        ),
        422,
        'invalid_comment',
        'comment rejects 1001 Unicode code points',
    );
    $comment = $app->updateComment($userId, $comment['id'], 'すてき！');
    $replayedComment = $app->addComment(
        $userId,
        $answer['id'],
        'すてき！',
        null,
        $commentRequestKey,
    );
    same($comment['id'], $replayedComment['id'], 'comment idempotency replay');
    apiError(
        static fn () => $app->addComment(
            $userId,
            $answer['id'],
            '違う本文',
            null,
            $commentRequestKey,
        ),
        409,
        'idempotency_key_reused',
        'comment idempotency key content binding',
    );
    $comment = $app->updateComment($userId, $comment['id'], '編集したコメント');
    same('編集したコメント', $comment['body'], 'comment owner edit');
    same(
        $originalComment,
        $app->addComment(
            $userId,
            $answer['id'],
            'すてき！',
            null,
            $commentRequestKey,
        ),
        'comment replay remains the exact original response after edit',
    );
    $reply = $app->addComment(
        $filterUserId,
        $answer['id'],
        '返信です',
        $comment['id'],
    );
    same($comment['id'], $reply['parentCommentId'], 'comment reply parent');
    $maximumComposedReportDetails = str_repeat("e\u{0301}", 250);
    $report = $app->reportComment(
        $filterUserId,
        $comment['id'],
        'privacy',
        $maximumComposedReportDetails,
    );
    same('pending', $report['status'], 'comment report');
    same('privacy', $report['reason'], 'comment report reason contract');
    same($comment['id'], $report['commentId'], 'comment report response context');
    apiError(
        static fn () => $app->reportComment(
            $filterUserId,
            $comment['id'],
            'privacy',
            $maximumComposedReportDetails . 'e',
        ),
        422,
        'invalid_report_details',
        'comment report details reject 501 Unicode code points',
    );
    apiError(
        static fn () => $app->reportComment($userId, $comment['id'], 'other', '自分のコメント'),
        422,
        'self_report_not_allowed',
        'comment self-report rejection',
    );
    $comments = $app->comments($userId, $answer['id'], null, 20);
    same(2, count($comments['items']), 'comment list with reply');
    $app->deleteComment($filterUserId, $reply['id']);
    $app->deleteComment($userId, $comment['id']);
    same(0, count($app->comments($userId, $answer['id'], null, 20)['items']), 'comment deletion');
    same(
        $originalComment,
        $app->addComment(
            $userId,
            $answer['id'],
            'すてき！',
            null,
            $commentRequestKey,
        ),
        'comment replay remains exact after source deletion',
    );
    same(
        0,
        count($app->comments($userId, $answer['id'], null, 20)['items']),
        'comment replay after deletion does not recreate content',
    );
    same(
        1,
        (int) $pdo->query('SELECT COUNT(*) FROM comment_mutation_receipts')->fetchColumn(),
        'headerless comment and reply requests do not retain unreachable receipts',
    );
    $storedCommentReceiptStatement = $pdo->query(
        'SELECT request_fingerprint, response_encrypted
         FROM comment_mutation_receipts LIMIT 1'
    );
    $storedCommentReceipt = $storedCommentReceiptStatement->fetch();
    $storedCommentReceiptStatement->closeCursor();
    truthy(
        is_array($storedCommentReceipt) &&
        !str_contains((string) $storedCommentReceipt['request_fingerprint'], 'すてき！') &&
        !str_contains((string) $storedCommentReceipt['response_encrypted'], 'すてき！'),
        'comment receipt stores only a keyed fingerprint and encrypted response',
    );
    $push = $app->registerPushToken($userId, str_repeat('a', 64), 'ios', 'sandbox');
    truthy(strlen($push['tokenHash']) === 64, 'push token registration');
    apiError(
        static fn () => $app->registerPushToken($userId, str_repeat('g', 64), 'ios', 'sandbox'),
        422,
        'invalid_push_token',
        'push token registration rejects non-hexadecimal input',
    );
    apiError(
        static fn () => $app->registerPushToken($userId, str_repeat('a', 33), 'ios', 'sandbox'),
        422,
        'invalid_push_token',
        'push token registration rejects odd-length input',
    );
    same(
        true,
        $lifecycle->notificationPreferences($userId)['commentsEnabled'],
        'notification preference defaults',
    );
    same(
        '09:00',
        $lifecycle->notificationPreferences($userId)['questionReminderTime'],
        'question reminder default time',
    );
    $preferences = $lifecycle->updateNotificationPreferences($userId, [
        'commentsEnabled' => false,
        'questionReminderTime' => '23:58',
        'timezone' => 'UTC',
    ]);
    same(false, $preferences['commentsEnabled'], 'notification preference update');
    same('23:58', $preferences['questionReminderTime'], 'question reminder time update');
    $preferences = $lifecycle->updateNotificationPreferences($userId, ['likesEnabled' => false]);
    same(false, $preferences['commentsEnabled'], 'partial preference patch preserves another field');
    $pushProvider = new DeterministicPushProvider();
    $pushDelivery = new PushDeliveryService($database, $crypto, $config, $pushProvider);
    $delivery = $pushDelivery->deliverToUser(
        $userId,
        'comments',
        '新しいコメント',
        '家族からコメントが届きました。',
        ['answerId' => $answer['id']],
    );
    same('preference_disabled', $delivery['reason'], 'push honors disabled preference');
    $lifecycle->updateNotificationPreferences($userId, [
        'commentsEnabled' => true,
        'quietStart' => '00:00',
        'quietEnd' => '00:00',
    ]);
    $delivery = $pushDelivery->deliverToUser(
        $userId,
        'comments',
        '新しいコメント',
        '家族からコメントが届きました。',
    );
    same('quiet_hours', $delivery['reason'], 'push honors quiet hours');
    $lifecycle->updateNotificationPreferences($userId, [
        'quietStart' => null,
        'quietEnd' => null,
    ]);
    $delivery = $pushDelivery->deliverToUser(
        $userId,
        'comments',
        '新しいコメント',
        '家族からコメントが届きました。',
    );
    same(1, $delivery['delivered'], 'deterministic push delivery');
    same(1, count($pushProvider->deliveries), 'deterministic provider captured payload');
    apiError(
        static fn () => $pushDelivery->deliverToUser(
            $userId,
            'comments',
            '不正な通知',
            '予約済みAPNsキーは上書きできません。',
            ['aps' => []],
        ),
        422,
        'invalid_notification_data',
        'push custom data cannot override aps',
    );
    $preferences = $lifecycle->updateNotificationPreferences($userId, [
        'muteUntil' => '2999-01-01T09:30:00+09:00',
    ]);
    same('2999-01-01T00:30:00Z', $preferences['muteUntil'], 'notification mute normalization');
    $mutedDelivery = $pushDelivery->deliverToUser(
        $userId,
        'comments',
        'ミュート中のコメント',
        'この通知は配信されません。',
    );
    same('muted', $mutedDelivery['reason'], 'push honors future mute');
    same(1, count($pushProvider->deliveries), 'muted push does not invoke provider');
    $scheduledAt = new DateTimeImmutable('2026-09-01T23:59:00+00:00');
    $mutedReminderProvider = new DeterministicPushProvider();
    $mutedReminderScheduler = new QuestionReminderScheduler(
        $database,
        $config,
        new PushDeliveryService($database, $crypto, $config, $mutedReminderProvider),
    );
    $mutedSchedule = $mutedReminderScheduler->run($scheduledAt);
    same(0, $mutedSchedule['reserved'], 'muted reminder does not reserve a dispatch');
    same(0, count($mutedReminderProvider->deliveries), 'muted reminder does not invoke provider');
    $preferences = $lifecycle->updateNotificationPreferences($userId, ['muteUntil' => null]);
    same(null, $preferences['muteUntil'], 'notification mute clearing');
    $reminderProvider = new DeterministicPushProvider();
    $reminderScheduler = new QuestionReminderScheduler(
        $database,
        $config,
        new PushDeliveryService($database, $crypto, $config, $reminderProvider),
    );
    $scheduled = $reminderScheduler->run($scheduledAt);
    same(1, $scheduled['delivered'], 'due question reminder delivery');
    same(1, count($reminderProvider->deliveries), 'question reminder provider invocation');
    same(
        'today_question',
        $reminderProvider->deliveries[0]['payload']['destination'] ?? null,
        'push destination is at APNs payload root',
    );
    truthy(
        isset($reminderProvider->deliveries[0]['payload']['question_id']),
        'push question id is at APNs payload root',
    );
    same(
        false,
        array_key_exists('data', $reminderProvider->deliveries[0]['payload']),
        'push navigation is not nested under data',
    );
    $scheduledAgain = $reminderScheduler->run($scheduledAt);
    same(0, $scheduledAgain['reserved'], 'question reminder daily idempotency');
    same(1, count($reminderProvider->deliveries), 'repeated scheduler does not redeliver');
    $leaseUser = $users->findOrCreateByPhone('+819066667777');
    $leaseUserId = (int) $leaseUser['id'];
    $leasePush = $app->registerPushToken(
        $leaseUserId,
        str_repeat('c', 64),
        'ios',
        'sandbox',
    );
    $lifecycle->updateNotificationPreferences($leaseUserId, [
        'questionReminderTime' => '23:58',
        'timezone' => 'UTC',
    ]);
    $staleReservation = $pdo->prepare(
        "INSERT INTO notification_reminder_dispatches
            (user_id, local_date, reminder_time, status, created_at, updated_at)
         VALUES (:user, :date, :time, 'reserved', :created, :updated)"
    );
    $staleReservation->execute([
        'user' => $leaseUserId,
        'date' => '2026-09-01',
        'time' => '23:58',
        'created' => '2026-09-01 20:00:00',
        'updated' => '2026-09-01 20:00:00',
    ]);
    $leaseProvider = new DeterministicPushProvider();
    $leaseScheduler = new QuestionReminderScheduler(
        $database,
        $config,
        new PushDeliveryService($database, $crypto, $config, $leaseProvider),
    );
    $leaseRecovered = $leaseScheduler->run($scheduledAt);
    same(1, $leaseRecovered['reserved'], 'stale reminder reservation is reclaimed');
    same(1, $leaseRecovered['delivered'], 'reclaimed reminder reservation delivers');
    same(1, count($leaseProvider->deliveries), 'reclaimed reminder invokes provider once');
    $leaseRepeated = $leaseScheduler->run($scheduledAt);
    same(0, $leaseRepeated['reserved'], 'completed reclaimed reservation is idempotent');
    same(1, count($leaseProvider->deliveries), 'completed reclaimed reservation does not redeliver');
    $app->deletePushToken($leaseUserId, $leasePush['tokenHash']);
    $lifecycle->deleteAccount($leaseUserId);
    $invalidPushDelivery = new PushDeliveryService(
        $database,
        $crypto,
        $config,
        new DeterministicPushProvider(false, true),
    );
    $invalidDelivery = $invalidPushDelivery->deliverToUser(
        $userId,
        'comments',
        '新しいコメント',
        '無効な端末トークンを削除します。',
    );
    same(1, $invalidDelivery['failed'], 'invalid provider token records failed delivery');
    $invalidPushCount = $pdo->prepare('SELECT COUNT(*) FROM push_tokens WHERE user_id = :user');
    $invalidPushCount->execute(['user' => $userId]);
    same(0, (int) $invalidPushCount->fetchColumn(), 'invalid provider token is removed');
    apiError(
        static fn () => $lifecycle->updateNotificationPreferences($userId, [
            'likesEnabled' => 'yes',
        ]),
        422,
        'invalid_notification_preferences',
        'notification boolean validation',
    );
    apiError(
        static fn () => $lifecycle->updateNotificationPreferences($userId, [
            'quietStart' => '25:00',
        ]),
        422,
        'invalid_notification_preferences',
        'notification quiet-time validation',
    );
    apiError(
        static fn () => $lifecycle->updateNotificationPreferences($userId, [
            'questionReminderTime' => null,
        ]),
        422,
        'invalid_notification_preferences',
        'question reminder time validation',
    );
    apiError(
        static fn () => $lifecycle->updateNotificationPreferences($userId, [
            'muteUntil' => '2026-02-30T12:00:00Z',
        ]),
        422,
        'invalid_notification_preferences',
        'notification mute timestamp validation',
    );
    $app->deletePushToken($userId, $push['tokenHash']);

    $familySetup = new FamilySetupService(
        $database,
        $crypto,
        $rateLimiter,
        $sessions,
        $config,
    );
    $organizerSetupKey = 'smoke-organizer-family-create-0001';
    $organizerAuth = $familySetup->createOrganizerFamily(
        'ゆうた',
        '田中家',
        '127.0.0.3',
        $organizerSetupKey,
    );
    truthy(isset($organizerAuth['token'], $organizerAuth['user']['id']), 'organizer bootstrap session');
    same(false, $organizerAuth['user']['hasPhone'], 'device organizer does not require phone');
    same(
        $organizerAuth,
        $familySetup->createOrganizerFamily(
            'ゆうた',
            '田中家',
            '127.0.0.3',
            $organizerSetupKey,
        ),
        'organizer bootstrap exact response replay',
    );
    apiError(
        static fn () => $familySetup->createOrganizerFamily(
            '別の名前',
            '田中家',
            '127.0.0.3',
            $organizerSetupKey,
        ),
        409,
        'idempotency_key_reused',
        'organizer bootstrap idempotency content binding',
    );
    $organizerId = (int) $organizerAuth['user']['id'];
    same(
        $maximumName,
        $lifecycle->renameFamily($organizerId, $maximumName)['name'],
        'family name accepts the documented 80-character boundary',
    );
    apiError(
        static fn () => $lifecycle->renameFamily($organizerId, str_repeat('名', 81)),
        422,
        'invalid_family_name',
        'family name rejects 81 characters',
    );
    $lifecycle->renameFamily($organizerId, '田中家');
    apiError(
        static fn () => $otp->requestEnrollment(
            $organizerId,
            '090-1234-5678',
            '127.0.0.30',
        ),
        409,
        'phone_already_in_use',
        'phone enrollment uniqueness',
    );
    $enrollment = $otp->requestEnrollment($organizerId, '070-3333-4444', '127.0.0.31');
    $invalidEnrollmentKey = 'smoke-phone-enrollment-invalid-0001';
    apiError(
        static fn () => $otp->verifyEnrollment(
            $organizerId,
            $enrollment['requestId'],
            '000000',
            '127.0.0.31',
            $invalidEnrollmentKey,
        ),
        422,
        'invalid_otp',
        'phone enrollment invalid code',
    );
    apiError(
        static fn () => $otp->verifyEnrollment(
            $organizerId,
            $enrollment['requestId'],
            '000000',
            '127.0.0.31',
            $invalidEnrollmentKey,
        ),
        422,
        'invalid_otp',
        'phone enrollment invalid outcome exact replay',
    );
    $enrollmentAttempts = $pdo->prepare(
        'SELECT attempts FROM phone_enrollment_challenges WHERE request_id = :request'
    );
    $enrollmentAttempts->execute(['request' => $enrollment['requestId']]);
    same(1, (int) $enrollmentAttempts->fetchColumn(), 'phone enrollment invalid replay increments only once');
    $enrollmentAttempts->closeCursor();
    $enrollmentVerificationKey = 'smoke-phone-enrollment-verify-0001';
    $enrollmentCode = $sms->code;
    $enrolledUser = $otp->verifyEnrollment(
        $organizerId,
        $enrollment['requestId'],
        $enrollmentCode,
        '127.0.0.31',
        $enrollmentVerificationKey,
    );
    same(true, $enrolledUser['hasPhone'], 'authenticated phone enrollment');
    same(
        $enrolledUser,
        $otp->verifyEnrollment(
            $organizerId,
            $enrollment['requestId'],
            $enrollmentCode,
            '127.0.0.31',
            $enrollmentVerificationKey,
        ),
        'phone enrollment verification exact response replay',
    );
    apiError(
        static fn () => $otp->verifyEnrollment(
            $organizerId,
            $enrollment['requestId'],
            '999999',
            '127.0.0.31',
            $enrollmentVerificationKey,
        ),
        409,
        'idempotency_key_reused',
        'phone enrollment verification idempotency content binding',
    );

    $conflictEnrollment = ['requestId' => str_repeat('c', 32)];
    $conflictEnrollmentCode = '333333';
    $insertConflictChallenge = $pdo->prepare(
        "INSERT INTO phone_enrollment_challenges
            (user_id, request_id, phone_e164, code_hash, max_attempts, expires_at)
         VALUES (:user, :request, '+817055556666', :hash, :max,
                 '2099-01-01 00:00:00')"
    );
    $insertConflictChallenge->execute([
        'user' => $organizerId,
        'request' => $conflictEnrollment['requestId'],
        'hash' => $crypto->otpHash(
            $conflictEnrollment['requestId'],
            $conflictEnrollmentCode,
        ),
        'max' => $config->otpMaxAttempts,
    ]);
    $insertConflictChallenge->closeCursor();
    $pdo->exec(
        "INSERT INTO users (phone_e164, display_name)
         VALUES ('+817055556666', '競合ユーザー')"
    );
    $conflictingUserId = (int) $pdo->lastInsertId();
    $conflictEnrollmentKey = 'smoke-phone-enrollment-conflict-0001';
    foreach (['first', 'replay'] as $phase) {
        apiError(
            static fn () => $otp->verifyEnrollment(
                $organizerId,
                $conflictEnrollment['requestId'],
                $conflictEnrollmentCode,
                '127.0.0.37',
                $conflictEnrollmentKey,
            ),
            409,
            'phone_already_in_use',
            'phone enrollment conflict terminal outcome ' . $phase,
        );
    }
    $conflictAttempts = $pdo->prepare(
        'SELECT attempts FROM phone_enrollment_challenges WHERE request_id = :request'
    );
    $conflictAttempts->execute(['request' => $conflictEnrollment['requestId']]);
    same(1, (int) $conflictAttempts->fetchColumn(), 'phone conflict replay consumes once');
    $conflictAttempts->closeCursor();
    $deleteConflict = $pdo->prepare('DELETE FROM users WHERE id = :user');
    $deleteConflict->execute(['user' => $conflictingUserId]);
    $deleteConflict->closeCursor();

    apiError(
        static fn () => $otp->requestEnrollment(
            $organizerId,
            '070-3333-4444',
            '127.0.0.31',
        ),
        409,
        'phone_already_enrolled',
        'duplicate phone enrollment',
    );
    $returningChallenge = $otp->request('070-3333-4444', '127.0.0.33');
    $returningAuth = $otp->verify(
        $returningChallenge['requestId'],
        $sms->code,
        '127.0.0.33',
    );
    same((string) $organizerId, $returningAuth['user']['id'], 'enrolled phone recovery login');
    $replacement = $otp->requestEnrollment(
        $organizerId,
        '080-9999-0000',
        '127.0.0.32',
    );
    $replacedUser = $otp->verifyEnrollment(
        $organizerId,
        $replacement['requestId'],
        $sms->code,
        '127.0.0.32',
    );
    same(true, $replacedUser['hasPhone'], 'authenticated phone replacement');
    apiError(
        static fn () => $otp->requestEnrollment(
            $organizerId,
            '090-1234-5678',
            '127.0.0.34',
        ),
        409,
        'phone_already_in_use',
        'phone replacement uniqueness',
    );
    $formerPhoneChallenge = $otp->request('070-3333-4444', '127.0.0.35');
    $formerPhoneCode = $sms->code;
    apiError(
        static fn () => $otp->verify(
            $formerPhoneChallenge['requestId'],
            $formerPhoneCode,
            '127.0.0.35',
        ),
        404,
        'account_not_found',
        'replaced phone no longer recovers the account',
    );
    same(null, $users->findByPhone('+817033334444'), 'former phone is unclaimed after replacement');
    $replacementLogin = $otp->request('080-9999-0000', '127.0.0.36');
    $replacementAuth = $otp->verify(
        $replacementLogin['requestId'],
        $sms->code,
        '127.0.0.36',
    );
    same((string) $organizerId, $replacementAuth['user']['id'], 'replacement phone recovery login');
    $sessions->issue($organizerId);
    $app->registerPushToken($organizerId, str_repeat('e', 64), 'ios', 'sandbox');
    $recovery = $lifecycle->createRecoveryCode($organizerId);
    $recoveryRequestKey = 'smoke-recovery-redemption-key-0001';
    $recoveredAuth = $lifecycle->recoverSession(
        $recovery['code'],
        $recoveryRequestKey,
    );
    same((string) $organizerId, $recoveredAuth['user']['id'], 'device recovery session');
    $replayedRecoveryAuth = $lifecycle->recoverSession(
        $recovery['code'],
        $recoveryRequestKey,
    );
    same(
        $recoveredAuth['token'],
        $replayedRecoveryAuth['token'],
        'recovery lost-response replay returns the original session',
    );
    $recoveryReplayState = $pdo->prepare(
        'SELECT redemption_replay_expires_at FROM device_recovery_codes
         WHERE redemption_key_hash = :key'
    );
    $recoveryReplayState->execute([
        'key' => $crypto->hashOpaque(
            'recovery-redemption:' . $recoveryRequestKey
        ),
    ]);
    same(
        (new DateTimeImmutable((string) $recoveredAuth['expiresAt']))
            ->format('Y-m-d H:i:s'),
        (string) $recoveryReplayState->fetchColumn(),
        'recovery replay remains available for the issued session lifetime',
    );
    $recoveredSessionCount = $pdo->prepare(
        'SELECT COUNT(*) FROM sessions WHERE user_id = :user AND revoked_at IS NULL'
    );
    $recoveredSessionCount->execute(['user' => $organizerId]);
    same(1, (int) $recoveredSessionCount->fetchColumn(), 'recovery rotates all prior sessions');
    $recoveredPushCount = $pdo->prepare('SELECT COUNT(*) FROM push_tokens WHERE user_id = :user');
    $recoveredPushCount->execute(['user' => $organizerId]);
    same(0, (int) $recoveredPushCount->fetchColumn(), 'recovery removes prior push registrations');
    apiError(
        static fn () => $lifecycle->recoverSession($recovery['code']),
        422,
        'invalid_recovery_code',
        'one-time device recovery code',
    );
    apiError(
        static fn () => $answerMedia->download($organizerId, $mediaUrl[1], $mediaUrl[2]),
        404,
        'media_not_found',
        'cross-family media authorization',
    );
    $managedMemberRequestKey = 'smoke-managed-member-create-0001';
    $managedMember = $familySetup->createManagedMember(
        $organizerId,
        'まさこ',
        $managedMemberRequestKey,
    );
    same(true, $managedMember['managed'], 'managed elder creation');
    same(
        $managedMember,
        $familySetup->createManagedMember(
            $organizerId,
            'まさこ',
            $managedMemberRequestKey,
        ),
        'managed member exact response replay',
    );
    apiError(
        static fn () => $familySetup->createManagedMember(
            $organizerId,
            '別の家族',
            $managedMemberRequestKey,
        ),
        409,
        'idempotency_key_reused',
        'managed member idempotency content binding',
    );
    $managedMemberId = (int) $managedMember['id'];
    same(
        $maximumName,
        $lifecycle->renameMember(
            $organizerId,
            (string) $managedMemberId,
            $maximumName,
        )['displayName'],
        'managed member name accepts the documented 80-character boundary',
    );
    apiError(
        static fn () => $lifecycle->renameMember(
            $organizerId,
            (string) $managedMemberId,
            str_repeat('名', 81),
        ),
        422,
        'invalid_display_name',
        'managed member name rejects 81 characters',
    );
    $lifecycle->renameMember($organizerId, (string) $managedMemberId, 'まさこ');
    same(
        $managedMember,
        $familySetup->createManagedMember(
            $organizerId,
            'まさこ',
            $managedMemberRequestKey,
        ),
        'managed member replay remains the original response after rename',
    );

    $pairing = $familySetup->createPairing($organizerId, (string) $managedMemberId);
    truthy(
        preg_match('/^[0-9]{6}$/', (string) $pairing['code']) === 1,
        'six-digit pairing fallback',
    );
    truthy(strlen((string) $pairing['token']) >= 40, 'high-entropy pairing token');
    truthy(
        str_contains((string) $pairing['pairingUrl'], '/invite/' . $pairing['token']),
        'pairing URL',
    );
    $unknownPairingCode = $pairing['code'] === '999999' ? '999998' : '999999';
    apiError(
        static fn () => $familySetup->previewPairing(
            $unknownPairingCode,
            null,
            '127.0.0.41',
        ),
        404,
        'pairing_not_found',
        'well-formed unknown pairing code',
    );
    $preview = $familySetup->previewPairing(
        $pairing['code'],
        null,
        '127.0.0.4',
    );
    same((string) $managedMemberId, $preview['member']['id'], 'pairing preview member');
    same('田中家', $preview['family']['name'], 'pairing preview family');

    $pairingActivationKey = 'smoke-pairing-activation-key-0001';
    $managedAuth = $familySetup->activatePairing(
        null,
        $pairing['token'],
        '127.0.0.4',
        $pairingActivationKey,
    );
    same((string) $managedMemberId, $managedAuth['user']['id'], 'managed device activation');
    same(true, $managedAuth['user']['managed'], 'managed device session profile');
    $replayedManagedAuth = $familySetup->activatePairing(
        null,
        $pairing['token'],
        '127.0.0.43',
        $pairingActivationKey,
    );
    same(
        $managedAuth['token'],
        $replayedManagedAuth['token'],
        'pairing lost-response replay returns the original session',
    );
    $replayedPairingPreview = $familySetup->previewPairing(
        null,
        $pairing['token'],
        '127.0.0.44',
        $pairingActivationKey,
    );
    same(
        (string) $managedMemberId,
        $replayedPairingPreview['member']['id'],
        'consumed pairing re-enters preview with its exact activation key',
    );
    apiError(
        static fn () => $familySetup->previewPairing(
            null,
            $pairing['token'],
            '127.0.0.45',
            'wrong-pairing-activation-key-0001',
        ),
        409,
        'pairing_already_used',
        'consumed pairing preview rejects a different activation key',
    );
    $pairingReplayState = $pdo->prepare(
        'SELECT activation_replay_expires_at FROM device_pairings
         WHERE activation_key_hash = :key'
    );
    $pairingReplayState->execute([
        'key' => $crypto->hashOpaque(
            'pairing-activation:' . $pairingActivationKey
        ),
    ]);
    same(
        (new DateTimeImmutable((string) $managedAuth['expiresAt']))
            ->format('Y-m-d H:i:s'),
        (string) $pairingReplayState->fetchColumn(),
        'pairing replay remains available for the issued session lifetime',
    );

    $exhaustedReplayIp = '127.0.0.46';
    $exhaustedBucket = $crypto->hashOpaque(
        'rate:pairing-activate-ip:' . $exhaustedReplayIp
    );
    $exhaustRateLimit = $pdo->prepare(
        'INSERT INTO rate_limits (bucket_hash, window_started_at, hits, updated_at)
         VALUES (:bucket, CURRENT_TIMESTAMP, :hits, CURRENT_TIMESTAMP)'
    );
    $exhaustRateLimit->execute([
        'bucket' => $exhaustedBucket,
        'hits' => $config->pairingIpAttemptsPerHour,
    ]);
    $rateExemptReplay = $familySetup->activatePairing(
        null,
        $pairing['token'],
        $exhaustedReplayIp,
        $pairingActivationKey,
    );
    same(
        $managedAuth['token'],
        $rateExemptReplay['token'],
        'exact activation replay bypasses an exhausted attempt bucket',
    );
    $exhaustedHits = $pdo->prepare(
        'SELECT hits FROM rate_limits WHERE bucket_hash = :bucket'
    );
    $exhaustedHits->execute(['bucket' => $exhaustedBucket]);
    same(
        $config->pairingIpAttemptsPerHour,
        (int) $exhaustedHits->fetchColumn(),
        'exact activation replay does not consume another attempt',
    );
    $exhaustedHits->closeCursor();

    $agePairingReplay = $pdo->prepare(
        "UPDATE device_pairings
         SET consumed_at = '2000-01-01 00:00:00',
             expires_at = '2000-01-01 00:00:00'
         WHERE activation_key_hash = :key"
    );
    $agePairingReplay->execute([
        'key' => $crypto->hashOpaque(
            'pairing-activation:' . $pairingActivationKey
        ),
    ]);
    $agePairingReplay->closeCursor();
    $ageRecoveryReplay = $pdo->prepare(
        "UPDATE device_recovery_codes
         SET consumed_at = '2000-01-01 00:00:00',
             expires_at = '2000-01-01 00:00:00'
         WHERE redemption_key_hash = :key"
    );
    $ageRecoveryReplay->execute([
        'key' => $crypto->hashOpaque(
            'recovery-redemption:' . $recoveryRequestKey
        ),
    ]);
    $ageRecoveryReplay->closeCursor();
    $ageLoginChallenge = $pdo->prepare(
        "UPDATE phone_otp_challenges
         SET expires_at = '2000-01-01 00:00:00',
             consumed_at = '2000-01-01 00:00:00'
         WHERE request_id = :request"
    );
    $ageLoginChallenge->execute(['request' => $challenge['requestId']]);
    $ageLoginChallenge->closeCursor();
    $ageEnrollmentChallenge = $pdo->prepare(
        "UPDATE phone_enrollment_challenges
         SET expires_at = '2000-01-01 00:00:00',
             consumed_at = '2000-01-01 00:00:00'
         WHERE request_id = :request"
    );
    $ageEnrollmentChallenge->execute(['request' => $enrollment['requestId']]);
    $ageEnrollmentChallenge->closeCursor();
    // Apply the retention predicates in-process here; the complete cleanup
    // executable is exercised later after all intentionally open fixture
    // cursors have been released.
    $pdo->exec(
        "DELETE FROM phone_otp_challenges
         WHERE expires_at < datetime(CURRENT_TIMESTAMP, '-1 day')
           AND verification_replay_expires_at IS NULL;
         DELETE FROM phone_enrollment_challenges
         WHERE expires_at < datetime(CURRENT_TIMESTAMP, '-1 day')
           AND verification_replay_expires_at IS NULL;"
    );
    same(
        0,
        (int) $pdo->query(
            "SELECT COUNT(*) FROM phone_otp_challenges
             WHERE request_id = '" . $challenge['requestId'] . "'"
        )->fetchColumn(),
        'expired OTP challenge is removable independently of its receipt',
    );
    same(
        $managedAuth['token'],
        $familySetup->activatePairing(
            null,
            $pairing['token'],
            '127.0.0.47',
            $pairingActivationKey,
        )['token'],
        'cleanup retains consumed pairing until its issued session expires',
    );
    same(
        $recoveredAuth['token'],
        $lifecycle->recoverSession(
            $recovery['code'],
            $recoveryRequestKey,
        )['token'],
        'cleanup retains consumed recovery until its issued session expires',
    );
    same(
        $auth,
        $otp->verify(
            $challenge['requestId'],
            $loginCode,
            '127.0.0.1',
            $loginVerificationKey,
        ),
        'cleanup retains consumed OTP exact replay for its bounded window',
    );
    same(
        $enrolledUser,
        $otp->verifyEnrollment(
            $organizerId,
            $enrollment['requestId'],
            $enrollmentCode,
            '127.0.0.31',
            $enrollmentVerificationKey,
        ),
        'cleanup retains enrollment exact replay for its bounded window',
    );
    $organizerFamily = $app->family($organizerId);
    $managedFamily = $app->family($managedMemberId);
    same($organizerFamily['id'], $managedFamily['id'], 'paired devices share family');
    same(2, count($managedFamily['members']), 'shared family member count');
    $renamedFamily = $lifecycle->renameFamily($organizerId, '田中さんの家族');
    same('田中さんの家族', $renamedFamily['name'], 'family owner rename');
    apiError(
        static fn () => $lifecycle->renameFamily($managedMemberId, '不正な変更'),
        403,
        'family_owner_required',
        'family rename owner authorization',
    );
    $renamedMember = $lifecycle->renameMember(
        $organizerId,
        (string) $managedMemberId,
        'おばあちゃん',
    );
    same('おばあちゃん', $renamedMember['displayName'], 'managed member rename');
    $managedRecovery = $lifecycle->createRecoveryCode($managedMemberId);
    $managedRecoveredAuth = $lifecycle->recoverSession($managedRecovery['code']);
    same(true, $managedRecoveredAuth['user']['managed'], 'managed-device recovery session');
    $organizerAnswer = $app->submitTodayAnswer(
        $organizerId,
        '家族への回答',
        null,
        [UploadedFile::fromLocalFile($photoPath, 'leave-family.png')],
        null,
        true,
    );
    same(
        $organizerAnswer['id'],
        $app->answerById($managedMemberId, (string) $organizerAnswer['id'])['id'],
        'answer detail lookup for another current family member',
    );
    apiError(
        static fn () => $app->answerById($userId, (string) $organizerAnswer['id']),
        404,
        'answer_not_found',
        'answer detail cross-family authorization',
    );
    $organizerMediaPath = (string) parse_url($organizerAnswer['media'][0]['url'], PHP_URL_PATH);
    truthy(
        preg_match(
            '#/v1/answer-media/([1-9][0-9]*)/([a-f0-9]{64})$#',
            $organizerMediaPath,
            $organizerMediaUrl,
        ) === 1,
        'family leave media URL',
    );
    $organizerMediaDownload = $answerMedia->download(
        $organizerId,
        $organizerMediaUrl[1],
        $organizerMediaUrl[2],
    );
    $familyLike = $app->setLike($managedMemberId, $organizerAnswer['id'], true);
    same(1, $familyLike['likesCount'], 'family member like');
    same(
        0,
        $app->setLike($managedMemberId, $organizerAnswer['id'], false)['likesCount'],
        'family member unlike',
    );
    same(
        true,
        array_values(array_filter(
            $organizerFamily['members'],
            static fn (array $member): bool => $member['id'] === (string) $managedMemberId,
        ))[0]['managed'],
        'family identifies managed member',
    );
    apiError(
        static fn () => $familySetup->activatePairing(
            null,
            $pairing['token'],
            '127.0.0.5',
        ),
        409,
        'pairing_already_used',
        'pairing replay',
    );
    $listedPairings = $familySetup->pairings($organizerId);
    same('consumed', $listedPairings['items'][0]['status'], 'pairing status after activation');
    $revocablePairing = $familySetup->createPairing(
        $organizerId,
        (string) $managedMemberId,
    );
    $familySetup->revokePairing($organizerId, $revocablePairing['id']);
    apiError(
        static fn () => $familySetup->previewPairing(
            null,
            $revocablePairing['token'],
            '127.0.0.6',
        ),
        410,
        'pairing_revoked',
        'revoked pairing preview',
    );
    $expiredPairing = $familySetup->createPairing(
        $organizerId,
        (string) $managedMemberId,
    );
    $expirePairing = $pdo->prepare(
        "UPDATE device_pairings SET expires_at = '2000-01-01 00:00:00' WHERE id = :id"
    );
    $expirePairing->execute(['id' => $expiredPairing['id']]);
    apiError(
        static fn () => $familySetup->previewPairing(
            null,
            $expiredPairing['token'],
            '127.0.0.42',
        ),
        410,
        'pairing_expired',
        'expired pairing preview',
    );
    apiError(
        static fn () => $familySetup->createManagedMember($managedMemberId, '追加'),
        403,
        'family_owner_required',
        'managed member owner authorization',
    );

    apiError(
        static fn () => $lifecycle->leaveFamily($organizerId),
        409,
        'ownership_transfer_required',
        'owner must transfer before leaving',
    );
    apiError(
        static fn () => $lifecycle->deleteAccount($organizerId),
        409,
        'ownership_transfer_required',
        'owner account deletion guard',
    );
    $promotionCandidate = $familySetup->createManagedMember($organizerId, '引き継ぎ候補');
    $promotionCandidateId = (int) $promotionCandidate['id'];
    apiError(
        static fn () => $lifecycle->transferOwnership(
            $organizerId,
            (string) $promotionCandidateId,
        ),
        409,
        'owner_device_setup_required',
        'unconfigured managed profile cannot receive ownership',
    );
    $promotionPairing = $familySetup->createPairing(
        $organizerId,
        (string) $promotionCandidateId,
    );
    $promotionAuth = $familySetup->activatePairing(
        null,
        $promotionPairing['token'],
        '127.0.0.41',
    );
    apiError(
        static fn () => $lifecycle->transferOwnership(
            $organizerId,
            (string) $promotionCandidateId,
        ),
        409,
        'owner_recovery_required',
        'configured successor must prepare durable recovery',
    );
    $consumedPromotionRecovery = $lifecycle->createRecoveryCode($promotionCandidateId);
    $promotionRecoveredAuth = $lifecycle->recoverSession($consumedPromotionRecovery['code']);
    apiError(
        static fn () => $lifecycle->transferOwnership(
            $organizerId,
            (string) $promotionCandidateId,
        ),
        409,
        'owner_recovery_required',
        'ownership rechecks recovery eligibility after credential consumption',
    );
    $lifecycle->createRecoveryCode($promotionCandidateId);
    $promotedOwnership = $lifecycle->transferOwnership(
        $organizerId,
        (string) $promotionCandidateId,
    );
    same(
        (string) $promotionCandidateId,
        $promotedOwnership['ownerUserId'],
        'activated managed profile receives ownership',
    );
    $promotedManagedProfileCount = $pdo->prepare(
        'SELECT COUNT(*) FROM managed_profiles WHERE user_id = :user'
    );
    $promotedManagedProfileCount->execute(['user' => $promotionCandidateId]);
    same(
        0,
        (int) $promotedManagedProfileCount->fetchColumn(),
        'ownership promotion makes managed profile independent',
    );
    $promotionSessionUser = $sessions->requireUser(
        authenticatedRequest($promotionRecoveredAuth['token'])
    );
    same(false, (bool) $promotionSessionUser['managed'], 'promoted device session remains usable');
    $restoredOwnership = $lifecycle->transferOwnership(
        $promotionCandidateId,
        (string) $organizerId,
    );
    same((string) $organizerId, $restoredOwnership['ownerUserId'], 'ownership can be handed back');
    $lifecycle->removeMember($organizerId, (string) $promotionCandidateId);
    $accountExport = $lifecycle->exportAccount($organizerId);
    same(1, $accountExport['schemaVersion'], 'account export schema version');
    same('+818099990000', $accountExport['account']['phoneNumber'], 'account export phone');
    same('田中さんの家族', $accountExport['family']['name'], 'account export family');
    truthy(count($accountExport['auditLog']) >= 3, 'account export audit log');

    $successor = $users->findOrCreateByPhone('+819055556666');
    $successorId = (int) $successor['id'];
    $successorOldFamily = $pdo->prepare(
        'SELECT family_id FROM family_members WHERE user_id = :user'
    );
    $successorOldFamily->execute(['user' => $successorId]);
    $successorOldFamilyId = (int) $successorOldFamily->fetchColumn();
    $removeSuccessorMembership = $pdo->prepare(
        'DELETE FROM family_members WHERE user_id = :user'
    );
    $removeSuccessorMembership->execute(['user' => $successorId]);
    $removeSuccessorFamily = $pdo->prepare('DELETE FROM families WHERE id = :family');
    $removeSuccessorFamily->execute(['family' => $successorOldFamilyId]);
    $joinSuccessor = $pdo->prepare(
        "INSERT INTO family_members (family_id, user_id, role) VALUES (:family, :user, 'member')"
    );
    $joinSuccessor->execute([
        'family' => $organizerFamily['id'],
        'user' => $successorId,
    ]);
    $sessions->issue($successorId);

    $removedRegular = $users->findOrCreateByPhone('+819077778888');
    $removedRegularId = (int) $removedRegular['id'];
    $removedOldFamily = $pdo->prepare('SELECT family_id FROM family_members WHERE user_id = :user');
    $removedOldFamily->execute(['user' => $removedRegularId]);
    $removedOldFamilyId = (int) $removedOldFamily->fetchColumn();
    $removeSuccessorMembership->execute(['user' => $removedRegularId]);
    $removeSuccessorFamily->execute(['family' => $removedOldFamilyId]);
    $joinSuccessor->execute([
        'family' => $organizerFamily['id'],
        'user' => $removedRegularId,
    ]);
    $removedRegularSession = $sessions->issue($removedRegularId);
    $reportAfterRemovalComment = $app->addComment(
        $managedMemberId,
        $organizerAnswer['id'],
        '退会競合の通報テスト',
    );
    apiError(
        static fn () => $lifecycle->renameMember(
            $organizerId,
            (string) $removedRegularId,
            '大人の名前',
        ),
        403,
        'managed_member_required',
        'owner cannot rename an independent adult account',
    );
    apiError(
        static fn () => $lifecycle->removeMember(
            $managedMemberId,
            (string) $organizerId,
        ),
        403,
        'family_owner_required',
        'member removal owner authorization',
    );
    $lifecycle->removeMember($organizerId, (string) $removedRegularId);
    apiError(
        static fn () => $app->reportComment(
            $removedRegularId,
            $reportAfterRemovalComment['id'],
            'privacy',
            '古い家族のコメント',
        ),
        404,
        'comment_not_found',
        'comment report rechecks membership after concurrent-removal ordering',
    );
    $postRemovalReports = $pdo->prepare(
        'SELECT COUNT(*) FROM comment_reports
         WHERE comment_id = :comment AND reported_by_user_id = :reporter'
    );
    $postRemovalReports->execute([
        'comment' => $reportAfterRemovalComment['id'],
        'reporter' => $removedRegularId,
    ]);
    same(0, (int) $postRemovalReports->fetchColumn(), 'unauthorized report is not inserted');
    same(1, $app->family($removedRegularId)['memberCount'], 'removed adult receives replacement family');
    $removedRegularSessions = $pdo->prepare(
        'SELECT COUNT(*) FROM sessions WHERE user_id = :user AND revoked_at IS NULL'
    );
    $removedRegularSessions->execute(['user' => $removedRegularId]);
    same(1, (int) $removedRegularSessions->fetchColumn(), 'adult removal preserves authentication');
    $removedRegularUser = $sessions->requireUser(authenticatedRequest($removedRegularSession['token']));
    same((string) $removedRegularId, (string) $removedRegularUser['id'], 'removed adult token remains valid');
    $removedRegularFamily = $app->family($removedRegularId);
    truthy(
        $removedRegularFamily['id'] !== $organizerFamily['id'],
        'removed adult cannot access the old family',
    );

    $filterUserInsert->execute(['name' => '未認証の家族']);
    $unauthenticatedMemberId = (int) $pdo->lastInsertId();
    $joinSuccessor->execute([
        'family' => $organizerFamily['id'],
        'user' => $unauthenticatedMemberId,
    ]);
    apiError(
        static fn () => $lifecycle->transferOwnership(
            $organizerId,
            (string) $unauthenticatedMemberId,
        ),
        409,
        'owner_recovery_required',
        'ownership target must have a durable recovery method',
    );
    $deleteUnauthenticatedMember = $pdo->prepare('DELETE FROM users WHERE id = :user');
    $deleteUnauthenticatedMember->execute(['user' => $unauthenticatedMemberId]);

    $ownership = $lifecycle->transferOwnership($organizerId, (string) $successorId);
    same((string) $successorId, $ownership['ownerUserId'], 'family ownership transfer');
    $ownershipRetry = $lifecycle->transferOwnership($organizerId, (string) $successorId);
    same(
        (string) $successorId,
        $ownershipRetry['ownerUserId'],
        'ownership transfer retry returns committed outcome',
    );
    $ownerCount = $pdo->prepare(
        "SELECT COUNT(*) FROM family_members WHERE family_id = :family AND role = 'owner'"
    );
    $ownerCount->execute(['family' => $organizerFamily['id']]);
    same(1, (int) $ownerCount->fetchColumn(), 'family has exactly one owner');
    $managedCreator = $pdo->prepare(
        'SELECT created_by_user_id FROM managed_profiles WHERE user_id = :managed'
    );
    $managedCreator->execute(['managed' => $managedMemberId]);
    same($successorId, (int) $managedCreator->fetchColumn(), 'managed profile follows new owner');
    $stalePairingCreators = $pdo->prepare(
        'SELECT COUNT(*) FROM device_pairings
         WHERE family_id = :family AND created_by_user_id <> :owner'
    );
    $stalePairingCreators->execute([
        'family' => $organizerFamily['id'],
        'owner' => $successorId,
    ]);
    same(0, (int) $stalePairingCreators->fetchColumn(), 'pairing ownership follows new owner');
    apiError(
        static fn () => $familySetup->createManagedMember($organizerId, '権限外の追加'),
        403,
        'family_owner_required',
        'former owner cannot add managed members',
    );
    apiError(
        static fn () => $familySetup->createPairing(
            $organizerId,
            (string) $managedMemberId,
        ),
        403,
        'family_manager_required',
        'former owner cannot create managed-member pairings',
    );

    $regularLeaveKey = 'smoke-regular-family-leave-key-0001';
    same(
        false,
        $lifecycle->updateNotificationPreferences(
            $organizerId,
            ['commentsEnabled' => false],
        )['commentsEnabled'],
        'old-family notification preference is stored before leave',
    );
    $leave = $lifecycle->leaveFamily($organizerId, $regularLeaveKey);
    same(false, $leave['accountDeleted'], 'regular member leave preserves account');
    same(
        ['accountDeleted' => false],
        $lifecycle->replayMutation('family.leave', $regularLeaveKey),
        'regular leave receipt returns the exact committed response',
    );
    same(
        false,
        $lifecycle->leaveFamily($organizerId, $regularLeaveKey)['accountDeleted'],
        'same-key regular leave service retry does not leave replacement family',
    );
    same(
        null,
        $lifecycle->replayMutation(
            'family.leave',
            'smoke-regular-family-leave-wrong-0001',
        ),
        'wrong leave key cannot read a receipt',
    );
    same(
        null,
        $lifecycle->replayMutation('family.leave', null),
        'missing leave key cannot read a receipt',
    );
    $activeOrganizerSessions = $pdo->prepare(
        'SELECT COUNT(*) FROM sessions WHERE user_id = :user AND revoked_at IS NULL'
    );
    $activeOrganizerSessions->execute(['user' => $organizerId]);
    same(1, (int) $activeOrganizerSessions->fetchColumn(), 'leave preserves active authentication');
    $preservedOrganizer = $sessions->requireUser(authenticatedRequest($recoveredAuth['token']));
    same((string) $organizerId, (string) $preservedOrganizer['id'], 'leaver token remains valid');
    $organizerReplacementFamily = $app->family($organizerId);
    same(1, $organizerReplacementFamily['memberCount'], 'leaver receives private replacement family');
    same(
        true,
        $lifecycle->notificationPreferences($organizerId)['commentsEnabled'],
        'replacement family starts with default notification preferences',
    );
    truthy(
        $organizerReplacementFamily['id'] !== $organizerFamily['id'],
        'leaver token cannot access the old family',
    );
    same(0, count($app->history($organizerId, null, 20)['items']), 'leaver content does not cross families');
    $oldFamilyHistory = $app->history($successorId, null, 20)['items'];
    same(
        false,
        in_array($organizerAnswer['id'], array_column($oldFamilyHistory, 'id'), true),
        'old family no longer exposes leaver content',
    );
    same(false, is_file($organizerMediaDownload['path']), 'leave removes physical answer media');

    $managedLeaveFixture = $familySetup->createManagedMember(
        $successorId,
        '退出レシート確認',
    );
    $managedLeaveKey = 'smoke-managed-family-leave-key-0001';
    $managedLeave = $lifecycle->leaveFamily(
        (int) $managedLeaveFixture['id'],
        $managedLeaveKey,
    );
    same(true, $managedLeave['accountDeleted'], 'managed leave deletes account');
    same(
        ['accountDeleted' => true],
        $lifecycle->replayMutation('family.leave', $managedLeaveKey),
        'managed leave receipt survives deletion of its user and sessions',
    );
    same(
        true,
        $lifecycle->leaveFamily(
            (int) $managedLeaveFixture['id'],
            $managedLeaveKey,
        )['accountDeleted'],
        'same-key managed leave service retry replays without a user',
    );

    $lifecycle->removeMember($successorId, (string) $managedMemberId);
    $managedExists = $pdo->prepare('SELECT COUNT(*) FROM users WHERE id = :user');
    $managedExists->execute(['user' => $managedMemberId]);
    same(0, (int) $managedExists->fetchColumn(), 'managed member removal deletes managed account');
    $activeManagedSessions = $pdo->prepare('SELECT COUNT(*) FROM sessions WHERE user_id = :user');
    $activeManagedSessions->execute(['user' => $managedMemberId]);
    same(0, (int) $activeManagedSessions->fetchColumn(), 'managed member removal cleans sessions');

    $successorDeleteKey = 'smoke-account-delete-key-0001';
    $lifecycle->deleteAccount($successorId, $successorDeleteKey);
    $successorExists = $pdo->prepare('SELECT COUNT(*) FROM users WHERE id = :user');
    $successorExists->execute(['user' => $successorId]);
    same(0, (int) $successorExists->fetchColumn(), 'sole-owner account deletion');
    same(
        [],
        $lifecycle->replayMutation('account.delete', $successorDeleteKey),
        'account deletion receipt survives deletion of its user and sessions',
    );
    $lifecycle->deleteAccount($successorId, $successorDeleteKey);
    same(
        null,
        $lifecycle->replayMutation(
            'account.delete',
            'smoke-account-delete-wrong-key-0001',
        ),
        'wrong account deletion key cannot read a receipt',
    );
    same(
        null,
        $lifecycle->replayMutation('account.delete', null),
        'missing account deletion key cannot read a receipt',
    );

    $deletionAuth = $familySetup->createOrganizerFamily(
        '削除テスト',
        '削除テスト家族',
        '127.0.0.41',
    );
    $deletionUserId = (int) $deletionAuth['user']['id'];
    $deletionAnswer = $app->submitTodayAnswer(
        $deletionUserId,
        '回答削除テスト',
        null,
        [UploadedFile::fromLocalFile($photoPath, 'delete-answer.png')],
        null,
        true,
    );
    $deletionMediaPath = (string) parse_url($deletionAnswer['media'][0]['url'], PHP_URL_PATH);
    truthy(
        preg_match('#/v1/answer-media/([1-9][0-9]*)/([a-f0-9]{64})$#', $deletionMediaPath, $deletionMediaUrl) === 1,
        'answer deletion media URL',
    );
    $deletionDownload = $answerMedia->download(
        $deletionUserId,
        $deletionMediaUrl[1],
        $deletionMediaUrl[2],
    );
    $app->deleteAnswer($deletionUserId, $deletionAnswer['id']);
    same(false, is_file($deletionDownload['path']), 'answer deletion physical media cleanup');

    $accountDeletionAnswer = $app->submitTodayAnswer(
        $deletionUserId,
        'アカウント削除テスト',
        null,
        [UploadedFile::fromLocalFile($photoPath, 'delete-account.png')],
        null,
        true,
    );
    $accountMediaPath = (string) parse_url($accountDeletionAnswer['media'][0]['url'], PHP_URL_PATH);
    truthy(
        preg_match('#/v1/answer-media/([1-9][0-9]*)/([a-f0-9]{64})$#', $accountMediaPath, $accountMediaUrl) === 1,
        'account deletion media URL',
    );
    $accountDeletionDownload = $answerMedia->download(
        $deletionUserId,
        $accountMediaUrl[1],
        $accountMediaUrl[2],
    );
    $lifecycle->deleteAccount($deletionUserId);
    same(false, is_file($accountDeletionDownload['path']), 'account deletion physical media cleanup');
    $deletedAccount = $pdo->prepare('SELECT COUNT(*) FROM users WHERE id = :user');
    $deletedAccount->execute(['user' => $deletionUserId]);
    same(0, (int) $deletedAccount->fetchColumn(), 'account deletion cascade');

    $logoutAuth = $familySetup->createOrganizerFamily(
        'ログアウトテスト',
        'ログアウト家族',
        '127.0.0.42',
    );
    $logoutUserId = (int) $logoutAuth['user']['id'];
    $app->registerPushToken($logoutUserId, str_repeat('f', 64), 'ios', 'sandbox');
    $app->registerPushToken($logoutUserId, str_repeat('c', 64), 'ios', 'sandbox');
    $unrelatedLogoutAuth = $familySetup->createOrganizerFamily(
        '他家族ログアウト境界',
        '他家族',
        '127.0.0.43',
    );
    $unrelatedLogoutUserId = (int) $unrelatedLogoutAuth['user']['id'];
    $app->registerPushToken(
        $unrelatedLogoutUserId,
        str_repeat('e', 64),
        'ios',
        'sandbox',
    );
    $expiredLogoutSession = $sessions->issue($logoutUserId);
    $expireLogoutSession = $pdo->prepare(
        'UPDATE sessions SET expires_at = :expired WHERE token_hash = :hash'
    );
    $expireLogoutSession->execute([
        'expired' => '2000-01-01 00:00:00',
        'hash' => $crypto->hashOpaque($expiredLogoutSession['token']),
    ]);
    same(1, $expireLogoutSession->rowCount(), 'expired logout session fixture');
    $expiredLogoutRequest = authenticatedRequest($expiredLogoutSession['token']);
    apiError(
        static fn () => $sessions->requireUser($expiredLogoutRequest),
        401,
        'invalid_session',
        'expired bearer remains unauthorized before logout',
    );
    $sessions->revoke($expiredLogoutRequest);
    $logoutPushCount = $pdo->prepare('SELECT COUNT(*) FROM push_tokens WHERE user_id = :user');
    $logoutPushCount->execute(['user' => $logoutUserId]);
    same(0, (int) $logoutPushCount->fetchColumn(), 'expired bearer logout removes account push registrations');
    $expiredLogoutRevocation = $pdo->prepare(
        'SELECT revoked_at FROM sessions WHERE token_hash = :hash'
    );
    $expiredLogoutRevocation->execute([
        'hash' => $crypto->hashOpaque($expiredLogoutSession['token']),
    ]);
    $expiredLogoutRevokedAt = $expiredLogoutRevocation->fetchColumn();
    truthy(
        is_string($expiredLogoutRevokedAt) && $expiredLogoutRevokedAt !== '',
        'expired bearer logout revokes the resolved session',
    );
    same(
        (string) $logoutUserId,
        (string) $sessions->requireUser(authenticatedRequest($logoutAuth['token']))['id'],
        'expired bearer logout preserves another session for its resolved user',
    );
    $unrelatedPushCount = $pdo->prepare('SELECT COUNT(*) FROM push_tokens WHERE user_id = :user');
    $unrelatedPushCount->execute(['user' => $unrelatedLogoutUserId]);
    same(1, (int) $unrelatedPushCount->fetchColumn(), 'expired bearer logout preserves another user push registration');
    same(
        (string) $unrelatedLogoutUserId,
        (string) $sessions->requireUser(authenticatedRequest($unrelatedLogoutAuth['token']))['id'],
        'expired bearer logout preserves another user session',
    );
    $sessions->revoke($expiredLogoutRequest);
    $sessions->revoke(authenticatedRequest(str_repeat('z', 64)));
    $unrelatedPushCount->execute(['user' => $unrelatedLogoutUserId]);
    same(1, (int) $unrelatedPushCount->fetchColumn(), 'logout retries and unknown bearers have no cross-user effects');
    apiError(
        static fn () => $sessions->requireUser($expiredLogoutRequest),
        401,
        'invalid_session',
        'expired bearer remains unauthorized after logout',
    );
    $app->registerPushToken($logoutUserId, str_repeat('d', 64), 'ios', 'sandbox');
    $logoutRequest = authenticatedRequest($logoutAuth['token']);
    $sessions->revoke($logoutRequest);
    $logoutPushCount->execute(['user' => $logoutUserId]);
    same(0, (int) $logoutPushCount->fetchColumn(), 'logout removes account push registrations');
    $unrelatedPushCount->execute(['user' => $unrelatedLogoutUserId]);
    same(1, (int) $unrelatedPushCount->fetchColumn(), 'active logout preserves another user push registration');
    apiError(
        static fn () => $sessions->requireUser($logoutRequest),
        401,
        'invalid_session',
        'logout revokes bearer session',
    );

    foreach ([
        'ANSWER_AUDIO_MAX_BYTES' => ['20971519', '20971520'],
        'ANSWER_PHOTO_MAX_BYTES' => ['10485759', '10485760'],
        'ANSWER_PHOTO_MAX_COUNT' => ['5', '4'],
    ] as $name => [$invalidValue, $contractValue]) {
        putenv($name . '=' . $invalidValue);
        runtimeError(
            static fn () => Config::fromEnvironment($base),
            $name . ' iOS contract drift rejection',
        );
        putenv($name . '=' . $contractValue);
    }

    putenv('SESSION_TTL_DAYS=31');
    runtimeError(
        static fn () => Config::fromEnvironment($base),
        'session TTL beyond iOS replay-retention contract rejection',
    );
    putenv('SESSION_TTL_DAYS=30');

    putenv('APP_ENV=production');
    putenv('APP_URL=https://api.example.jp');
    putenv('CORS_ALLOWED_ORIGINS=https://app.example.jp');
    putenv('OTP_DRIVER=disabled');
    putenv('OTP_DEV_EXPOSE=false');
    $disabledConfig = Config::fromEnvironment($base);
    same('disabled', $disabledConfig->otpDriver, 'production-disabled phone provider');
    same('disabled', $disabledConfig->pushDriver, 'production-disabled push provider');
    $disabledOtp = new OtpService(
        $database,
        $crypto,
        new RateLimiter($database, $crypto),
        new DisabledSmsSender(),
        $users,
        $sessions,
        $disabledConfig,
    );
    unavailable(
        static fn () => $disabledOtp->request('090-1234-5678', '127.0.0.2'),
        'disabled phone provider',
    );
    putenv('PUSH_DRIVER=log');
    runtimeError(
        static fn () => Config::fromEnvironment($base),
        'production log push provider rejection',
    );

    $apnsKeyPath = sys_get_temp_dir() . '/tsutsuura-apns-' . bin2hex(random_bytes(8)) . '.p8';
    $temporaryFiles[] = $apnsKeyPath;
    $apnsKey = openssl_pkey_new([
        'private_key_type' => OPENSSL_KEYTYPE_EC,
        'curve_name' => 'prime256v1',
    ]);
    if ($apnsKey === false || !openssl_pkey_export($apnsKey, $apnsPem)) {
        throw new RuntimeException('APNs test key could not be generated.');
    }
    file_put_contents($apnsKeyPath, $apnsPem);
    chmod($apnsKeyPath, 0600);
    putenv('PUSH_DRIVER=apns');
    putenv('APNS_TEAM_ID=AB12CD34EF');
    putenv('APNS_KEY_ID=ABC123DEFG');
    putenv('APNS_PRIVATE_KEY_PATH=' . $apnsKeyPath);
    putenv('APNS_TOPIC=com.example.tsutsuura');
    $apnsConfig = Config::fromEnvironment($base);
    $apnsProvider = new ApnsPushProvider(
        (string) $apnsConfig->apnsTeamId,
        (string) $apnsConfig->apnsKeyId,
        (string) $apnsConfig->apnsPrivateKeyPath,
        (string) $apnsConfig->apnsTopic,
    );
    $providerTokenMethod = new ReflectionMethod($apnsProvider, 'providerToken');
    $providerToken = $providerTokenMethod->invoke($apnsProvider);
    $providerTokenParts = explode('.', $providerToken);
    same(3, count($providerTokenParts), 'APNs ES256 provider JWT shape');
    $signaturePart = $providerTokenParts[2];
    $signaturePart .= str_repeat('=', (4 - strlen($signaturePart) % 4) % 4);
    $joseSignature = base64_decode(strtr($signaturePart, '-_', '+/'), true);
    same(64, is_string($joseSignature) ? strlen($joseSignature) : 0, 'APNs JOSE signature size');
    same(
        true,
        $apnsProvider->send('malformed-token', 'sandbox', [])['invalidToken'],
        'APNs malformed token classification without a live request',
    );
    putenv('PUSH_DRIVER=disabled');

    $orphanBucket = $mediaDirectory . '/ff';
    if (!is_dir($orphanBucket) && !mkdir($orphanBucket, 0700, true) && !is_dir($orphanBucket)) {
        throw new RuntimeException('Orphan media fixture directory could not be created.');
    }
    $orphanPath = $orphanBucket . '/' . str_repeat('f', 62);
    file_put_contents($orphanPath, 'orphan');
    touch($orphanPath, time() - 7200);
    same(1, $answerMedia->cleanupOrphanedFiles(), 'orphan media cleanup');

    $answer = $app->submitTodayAnswer($userId, '添付を削除しました。', null, [], null, true);
    same([], $answer['media'], 'multipart replacement clears media');
    same(false, is_file($remainingDownload['path']), 'replaced media file cleanup');

    // Make the child cleanup process perform its write only after all service
    // mutations are complete. A fresh read connection then verifies the
    // deletion without reusing the parent's intentionally long-lived SQLite
    // cursors/snapshot.
    $ageCommentReceipt = $pdo->prepare(
        "UPDATE comment_mutation_receipts
         SET expires_at = '2000-01-01 00:00:00'
         WHERE key_hash = :key"
    );
    $ageCommentReceipt->execute([
        'key' => $crypto->hashOpaque('comment-create:' . $commentRequestKey),
    ]);
    $ageCommentReceipt->closeCursor();
    $setupReceiptCountStatement = $pdo->query(
        'SELECT COUNT(*) FROM setup_mutation_receipts'
    );
    $setupReceiptCount = (int) $setupReceiptCountStatement->fetchColumn();
    $setupReceiptCountStatement->closeCursor();
    truthy($setupReceiptCount > 0, 'setup receipt cleanup fixture exists');
    $pdo->exec(
        "UPDATE setup_mutation_receipts
         SET expires_at = '2000-01-01 00:00:00'"
    );
    $pdo->exec(
        "UPDATE otp_mutation_receipts
         SET expires_at = '2000-01-01 00:00:00'"
    );
    $finalCleanupOutput = [];
    $finalCleanupStatus = 0;
    exec(
        escapeshellarg(PHP_BINARY) . ' ' .
        escapeshellarg($base . '/bin/cleanup.php') . ' 2>&1',
        $finalCleanupOutput,
        $finalCleanupStatus,
    );
    same(0, $finalCleanupStatus, 'cleanup command removes expired comment receipt');
    $verificationPdo = new PDO('sqlite:' . $databasePath);
    same(
        0,
        (int) $verificationPdo->query(
            'SELECT COUNT(*) FROM comment_mutation_receipts'
        )->fetchColumn(),
        'cleanup removes expired encrypted comment receipts',
    );
    same(
        0,
        (int) $verificationPdo->query(
            'SELECT COUNT(*) FROM setup_mutation_receipts'
        )->fetchColumn(),
        'cleanup removes expired encrypted setup receipts',
    );
    same(
        0,
        (int) $verificationPdo->query(
            'SELECT COUNT(*) FROM otp_mutation_receipts'
        )->fetchColumn(),
        'cleanup removes expired encrypted OTP and enrollment outcome receipts',
    );
    $verificationPdo = null;

    echo "smoke test passed\n";
} finally {
    foreach ($temporaryFiles as $file) {
        if (is_file($file)) {
            unlink($file);
        }
    }
    removeTestDirectory($mediaDirectory);
    foreach ([$databasePath, $databasePath . '-wal', $databasePath . '-shm'] as $file) {
        if (is_file($file)) {
            unlink($file);
        }
    }
}

function removeTestDirectory(string $directory): void
{
    if (!is_dir($directory)) {
        return;
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST,
    );
    foreach ($iterator as $item) {
        if ($item->isDir()) {
            rmdir($item->getPathname());
        } else {
            unlink($item->getPathname());
        }
    }
    rmdir($directory);
}

function authenticatedRequest(string $token): Request
{
    $server = $_SERVER;
    $get = $_GET;
    $post = $_POST;
    $files = $_FILES;
    try {
        $_SERVER = [
            'REQUEST_METHOD' => 'GET',
            'REQUEST_URI' => '/v1/me',
            'SCRIPT_NAME' => '/index.php',
            'HTTP_AUTHORIZATION' => 'Bearer ' . $token,
            'REMOTE_ADDR' => '127.0.0.1',
        ];
        $_GET = [];
        $_POST = [];
        $_FILES = [];
        return Request::fromGlobals();
    } finally {
        $_SERVER = $server;
        $_GET = $get;
        $_POST = $post;
        $_FILES = $files;
    }
}

function same(mixed $expected, mixed $actual, string $label): void
{
    if ($expected !== $actual) {
        throw new RuntimeException(sprintf(
            '%s failed: expected %s, got %s',
            $label,
            var_export($expected, true),
            var_export($actual, true),
        ));
    }
}

function truthy(bool $condition, string $label): void
{
    if (!$condition) {
        throw new RuntimeException($label . ' failed.');
    }
}

function unavailable(callable $operation, string $label): void
{
    try {
        $operation();
    } catch (ApiException $exception) {
        if ($exception->status === 503 && $exception->errorCode === 'auth_provider_unavailable') {
            return;
        }
        throw $exception;
    }
    throw new RuntimeException($label . ' did not return provider unavailable.');
}

function runtimeError(callable $operation, string $label): void
{
    try {
        $operation();
    } catch (RuntimeException) {
        return;
    }
    throw new RuntimeException($label . ' did not reject invalid runtime configuration.');
}

function apiError(
    callable $operation,
    int $expectedStatus,
    string $expectedCode,
    string $label,
): void {
    try {
        $operation();
    } catch (ApiException $exception) {
        if ($exception->status === $expectedStatus &&
            $exception->errorCode === $expectedCode) {
            return;
        }
        throw $exception;
    }
    throw new RuntimeException($label . ' did not return the expected API error.');
}
