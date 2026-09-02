<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AppService;
use Tsutsuura\Server\App\AnswerMediaService;
use Tsutsuura\Server\App\FamilySetupService;
use Tsutsuura\Server\App\LifecycleService;
use Tsutsuura\Server\Auth\LogSmsSender;
use Tsutsuura\Server\Auth\OtpService;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Auth\DisabledSmsSender;
use Tsutsuura\Server\Auth\TwilioSmsSender;
use Tsutsuura\Server\Auth\UserService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Http\Request;
use Tsutsuura\Server\Http\Response;
use Tsutsuura\Server\Http\Router;
use Tsutsuura\Server\Push\EventNotificationService;
use Tsutsuura\Server\Security\ClientIp;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;

ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

$appRootPointer = __DIR__ . '/.app-root';
$appRoot = is_file($appRootPointer)
    ? trim((string) file_get_contents($appRootPointer))
    : dirname(__DIR__);
if ($appRoot === '' || !is_file($appRoot . '/src/Autoload.php')) {
    http_response_code(500);
    exit('Server bootstrap is unavailable.');
}
require $appRoot . '/src/Autoload.php';

date_default_timezone_set('UTC');
$request = null;
$config = null;

try {
    $config = Config::fromEnvironment($appRoot);
    $request = Request::fromGlobals();
    applySecurityHeaders($config);
    applyCors($request, $config);
    if ($request->method === 'OPTIONS') {
        Response::empty();
    }

    $database = new Database($config);
    $crypto = new Crypto($config->appKey);
    $rateLimiter = new RateLimiter($database, $crypto);
    $users = new UserService($database);
    $sessions = new SessionService($database, $crypto, $config);
    $sms = match ($config->otpDriver) {
        'twilio' => new TwilioSmsSender($config),
        'log' => new LogSmsSender(),
        default => new DisabledSmsSender(),
    };
    $otp = new OtpService($database, $crypto, $rateLimiter, $sms, $users, $sessions, $config);
    $answerMedia = new AnswerMediaService($database, $crypto, $config);
    $eventNotifications = $config->pushDriver === 'disabled'
        ? null
        : new EventNotificationService();
    $app = new AppService(
        $database,
        $crypto,
        $config,
        $answerMedia,
        $eventNotifications,
    );
    $lifecycle = new LifecycleService(
        $database,
        $crypto,
        $config,
        $sessions,
        $answerMedia,
    );
    $familySetup = new FamilySetupService(
        $database,
        $crypto,
        $rateLimiter,
        $sessions,
        $config,
    );
    $router = new Router();

    $health = static function () use ($database, $config, $answerMedia): never {
        $databaseReady = false;
        $familySetupReady = false;
        $answerMediaReady = false;
        try {
            $pdo = $database->connection();
            $pdo->query('SELECT 1')->fetchColumn();
            $migration = $pdo->prepare(
                'SELECT 1 FROM schema_migrations WHERE version = :version'
            );
            foreach ([
                '004_lifecycle.sql',
                '005_event_notifications.sql',
                '006_event_notification_deliveries.sql',
                '007_idempotent_mutations.sql',
            ] as $version) {
                $migration->execute(['version' => $version]);
                if ($migration->fetchColumn() === false) {
                    throw new RuntimeException('Required server migration is missing.');
                }
            }
            $pdo->query('SELECT 1 FROM managed_profiles WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM device_pairings WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM answer_media WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM notification_preferences WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM notification_reminder_dispatches WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM notification_event_outbox WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM notification_event_deliveries WHERE 1 = 0');
            $pdo->query('SELECT 1 FROM device_recovery_codes WHERE 1 = 0');
            $pdo->query(
                'SELECT key_hash, user_id, request_fingerprint,
                        response_encrypted, expires_at
                 FROM comment_mutation_receipts WHERE 1 = 0'
            );
            $pdo->query(
                'SELECT key_hash, operation, actor_user_id, request_fingerprint,
                        response_encrypted, expires_at
                 FROM setup_mutation_receipts WHERE 1 = 0'
            );
            $pdo->query(
                'SELECT key_hash, operation, actor_user_id, request_fingerprint,
                        outcome_encrypted, expires_at
                 FROM otp_mutation_receipts WHERE 1 = 0'
            );
            $pdo->query(
                'SELECT key_hash, operation, result_json
                 FROM lifecycle_mutation_receipts WHERE 1 = 0'
            );
            $pdo->query('SELECT 1 FROM comment_reports WHERE 1 = 0');
            if ($database->isSqlite()
                && (!is_file($config->dbName) || !is_writable($config->dbName))) {
                throw new RuntimeException('SQLite database is not writable.');
            }
            $databaseReady = true;
            $familySetupReady = true;
            $answerMedia->ensureStorageReady();
            $answerMedia->assertUploadRuntimeReady();
            $answerMediaReady = true;
        } catch (Throwable $exception) {
            error_log('Health check unavailable: ' . $exception->getMessage());
            Response::json(['data' => [
                'status' => $databaseReady ? 'degraded' : 'unavailable',
                'database' => $databaseReady ? 'ok' : 'unavailable',
                'authProviders' => [
                    'phone' => $config->otpDriver !== 'disabled',
                ],
                'capabilities' => [
                    'familySetup' => $familySetupReady,
                    'answerMedia' => $answerMediaReady,
                ],
                'time' => gmdate(DATE_ATOM),
            ]], 503);
        }
        Response::json(['data' => [
            'status' => 'ok',
            'database' => 'ok',
            'authProviders' => [
                'phone' => $config->otpDriver !== 'disabled',
            ],
            'capabilities' => [
                'familySetup' => true,
                'answerMedia' => true,
            ],
            'time' => gmdate(DATE_ATOM),
        ]]);
    };
    $router->add('GET', '/health', $health);
    $router->add('GET', '/v1/health', $health);

    $router->add('POST', '/v1/auth/phone/request', static function (Request $request) use ($otp, $config): never {
        $body = $request->json();
        $result = $otp->request($body['phone'] ?? null, ClientIp::resolve($request, $config));
        Response::json(['data' => $result], 202);
    });
    $router->add('POST', '/v1/auth/phone/verify', static function (Request $request) use ($otp, $config): never {
        $body = $request->json();
        $result = $otp->verify(
            $body['requestId'] ?? null,
            $body['code'] ?? null,
            ClientIp::resolve($request, $config),
            $request->header('idempotency-key'),
        );
        Response::json(['data' => $result]);
    });
    $router->add('POST', '/v1/auth/recovery/verify', static function (
        Request $request,
    ) use ($lifecycle): never {
        $body = $request->json();
        Response::json(['data' => $lifecycle->recoverSession(
            $body['code'] ?? null,
            $request->header('idempotency-key'),
        )]);
    });
    $router->add('POST', '/v1/auth/logout', static function (Request $request) use ($sessions): never {
        $sessions->revoke($request);
        Response::json(['data' => (object) []], 200);
    });

    $router->add('POST', '/v1/setup/family', static function (
        Request $request,
    ) use ($familySetup, $config): never {
        $body = $request->json();
        Response::json(['data' => $familySetup->createOrganizerFamily(
            $body['organizerName'] ?? null,
            $body['familyName'] ?? null,
            ClientIp::resolve($request, $config),
            $request->header('idempotency-key'),
        )], 201);
    });
    $router->add('POST', '/v1/setup/pairings/preview', static function (
        Request $request,
    ) use ($familySetup, $config): never {
        $body = $request->json();
        Response::json(['data' => ['pairing' => $familySetup->previewPairing(
            $body['code'] ?? null,
            $body['token'] ?? null,
            ClientIp::resolve($request, $config),
            $request->header('idempotency-key'),
        )]]);
    });
    $router->add('POST', '/v1/setup/pairings/activate', static function (
        Request $request,
    ) use ($familySetup, $config): never {
        $body = $request->json();
        Response::json(['data' => $familySetup->activatePairing(
            $body['code'] ?? null,
            $body['token'] ?? null,
            ClientIp::resolve($request, $config),
            $request->header('idempotency-key'),
        )]);
    });
    $router->add('GET', '/invite/{token}', static function (
        Request $request,
        array $parameters,
    ) use ($familySetup, $config): never {
        try {
            $pairing = $familySetup->previewPairing(
                null,
                $parameters['token'],
                ClientIp::resolve($request, $config),
            );
            $memberName = htmlspecialchars(
                (string) $pairing['member']['displayName'],
                ENT_QUOTES | ENT_SUBSTITUTE,
                'UTF-8',
            );
            $familyName = htmlspecialchars(
                (string) $pairing['family']['name'],
                ENT_QUOTES | ENT_SUBSTITUTE,
                'UTF-8',
            );
            Response::html(
                '<!doctype html><html lang="ja"><head><meta charset="utf-8">' .
                '<meta name="viewport" content="width=device-width,initial-scale=1">' .
                '<meta name="referrer" content="no-referrer"><title>つつうら 家族設定</title></head>' .
                '<body><main><h1>家族設定の準備ができています</h1><p>' .
                $familyName . 'の「' . $memberName .
                '」として設定します。</p><p>つつうらアプリでこのリンクを開いてください。</p>' .
                '</main></body></html>',
            );
        } catch (ApiException $exception) {
            Response::html(
                '<!doctype html><html lang="ja"><head><meta charset="utf-8">' .
                '<meta name="viewport" content="width=device-width,initial-scale=1">' .
                '<meta name="referrer" content="no-referrer"><title>つつうら 家族設定</title></head>' .
                '<body><main><h1>この家族設定リンクは利用できません</h1>' .
                '<p>家族の方に新しいリンクを作ってもらってください。</p></main></body></html>',
                $exception->status,
            );
        }
    });

    $router->add('GET', '/v1/me', static function (Request $request) use ($sessions): never {
        Response::json(['data' => Presenter::user($sessions->requireUser($request))]);
    });
    $router->add('PATCH', '/v1/me', static function (Request $request) use ($sessions, $users): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => Presenter::user($users->updateProfile(
            (int) $user['id'],
            $body['displayName'] ?? null,
        ))]);
    });
    $router->add('POST', '/v1/me/phone/request', static function (
        Request $request,
    ) use ($sessions, $otp, $config): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => $otp->requestEnrollment(
            (int) $user['id'],
            $body['phone'] ?? null,
            ClientIp::resolve($request, $config),
        )], 202);
    });
    $router->add('POST', '/v1/me/phone/verify', static function (
        Request $request,
    ) use ($sessions, $otp, $config): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['user' => $otp->verifyEnrollment(
            (int) $user['id'],
            $body['requestId'] ?? null,
            $body['code'] ?? null,
            ClientIp::resolve($request, $config),
            $request->header('idempotency-key'),
        )]]);
    });
    $router->add('POST', '/v1/me/recovery-codes', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $lifecycle->createRecoveryCode((int) $user['id'])], 201);
    });
    $router->add('GET', '/v1/me/export', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $lifecycle->exportAccount((int) $user['id'])]);
    });
    $router->add('DELETE', '/v1/me', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $idempotencyKey = $request->header('idempotency-key');
        if ($lifecycle->replayMutation('account.delete', $idempotencyKey) !== null) {
            Response::json(['data' => (object) []]);
        }
        try {
            $user = $sessions->requireUser($request);
        } catch (ApiException $exception) {
            if ($exception->status === 401 &&
                $lifecycle->replayMutation('account.delete', $idempotencyKey) !== null) {
                Response::json(['data' => (object) []]);
            }
            throw $exception;
        }
        $lifecycle->deleteAccount((int) $user['id'], $idempotencyKey);
        Response::json(['data' => (object) []]);
    });
    $router->add('GET', '/v1/me/notification-preferences', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $lifecycle->notificationPreferences((int) $user['id'])]);
    });
    $router->add('PATCH', '/v1/me/notification-preferences', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $lifecycle->updateNotificationPreferences(
            (int) $user['id'],
            $request->json(),
        )]);
    });
    $router->add('GET', '/v1/family', static function (Request $request) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->family((int) $user['id'])]);
    });
    $router->add('PATCH', '/v1/family', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => $lifecycle->renameFamily(
            (int) $user['id'],
            $body['name'] ?? null,
        )]);
    });
    $router->add('PATCH', '/v1/family/members/{memberId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['member' => $lifecycle->renameMember(
            (int) $user['id'],
            $parameters['memberId'],
            $body['displayName'] ?? null,
        )]]);
    });
    $router->add('DELETE', '/v1/family/members/{memberId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        $lifecycle->removeMember((int) $user['id'], $parameters['memberId']);
        Response::json(['data' => (object) []]);
    });
    $router->add('POST', '/v1/family/ownership', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => $lifecycle->transferOwnership(
            (int) $user['id'],
            is_string($body['memberId'] ?? null) ? $body['memberId'] : '',
        )]);
    });
    $router->add('POST', '/v1/family/leave', static function (
        Request $request,
    ) use ($sessions, $lifecycle): never {
        $idempotencyKey = $request->header('idempotency-key');
        $replayed = $lifecycle->replayMutation('family.leave', $idempotencyKey);
        if ($replayed !== null) {
            Response::json(['data' => $replayed]);
        }
        try {
            $user = $sessions->requireUser($request);
        } catch (ApiException $exception) {
            if ($exception->status === 401) {
                $replayed = $lifecycle->replayMutation(
                    'family.leave',
                    $idempotencyKey,
                );
                if ($replayed !== null) {
                    Response::json(['data' => $replayed]);
                }
            }
            throw $exception;
        }
        Response::json(['data' => $lifecycle->leaveFamily(
            (int) $user['id'],
            $idempotencyKey,
        )]);
    });
    $router->add('POST', '/v1/family/managed-members', static function (
        Request $request,
    ) use ($sessions, $familySetup): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['member' => $familySetup->createManagedMember(
            (int) $user['id'],
            $body['displayName'] ?? null,
            $request->header('idempotency-key'),
        )]], 201);
    });
    $router->add('POST', '/v1/family/managed-members/{memberId}/pairings', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $familySetup): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => ['pairing' => $familySetup->createPairing(
            (int) $user['id'],
            $parameters['memberId'],
        )]], 201);
    });
    $router->add('GET', '/v1/family/pairings', static function (
        Request $request,
    ) use ($sessions, $familySetup): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $familySetup->pairings((int) $user['id'])]);
    });
    $router->add('DELETE', '/v1/family/pairings/{pairingId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $familySetup): never {
        $user = $sessions->requireUser($request);
        $familySetup->revokePairing((int) $user['id'], $parameters['pairingId']);
        Response::json(['data' => (object) []]);
    });
    $router->add('GET', '/v1/home', static function (Request $request) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->home(
            (int) $user['id'],
            $request->query['cursor'] ?? null,
        )]);
    });
    $router->add('GET', '/v1/questions/today', static function (Request $request) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->todayQuestion((int) $user['id'])]);
    });
    $router->add('GET', '/v1/answers/{answerId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => ['answer' => $app->answerById(
            (int) $user['id'],
            $parameters['answerId'],
        )]]);
    });
    $submitAnswer = static function (
        Request $request,
    ) use ($sessions, $app, $rateLimiter, $config): never {
        $user = $sessions->requireUser($request);
        if ($request->isMultipart()) {
            if ($request->method !== 'POST') {
                throw new ApiException(
                    415,
                    'multipart_requires_post',
                    'Multipart answer uploads must use POST.',
                );
            }
            $rateLimiter->consume(
                'answer-media-user:' . (string) $user['id'],
                $config->answerMediaUserUploadsPerHour,
                3600,
            );
            $rateLimiter->consume(
                'answer-media-ip:' . ClientIp::resolve($request, $config),
                $config->answerMediaIpUploadsPerHour,
                3600,
            );
            $body = $request->form();
            $unexpectedFields = array_diff(
                array_keys($body),
                ['body', 'audioDurationMilliseconds'],
            );
            $unexpectedFiles = array_diff(
                $request->uploadedFileFieldNames(),
                ['audio', 'photos'],
            );
            if ($unexpectedFields !== [] || $unexpectedFiles !== []) {
                throw new ApiException(
                    422,
                    'invalid_multipart_field',
                    'Multipart answer contains an unsupported field.',
                );
            }
            $answer = $app->submitTodayAnswer(
                (int) $user['id'],
                $body['body'] ?? '',
                $request->uploadedFile('audio'),
                $request->uploadedFiles('photos'),
                $body['audioDurationMilliseconds'] ?? null,
                true,
            );
        } else {
            $body = $request->json();
            $answer = $app->submitTodayAnswer(
                (int) $user['id'],
                $body['body'] ?? null,
            );
        }
        Response::json(['data' => ['answer' => $answer]]);
    };
    $router->add('PUT', '/v1/questions/today/answer', $submitAnswer);
    $router->add('POST', '/v1/questions/today/answer', $submitAnswer);
    $history = static function (Request $request) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->history(
            (int) $user['id'],
            $request->query['cursor'] ?? null,
            $request->query['limit'] ?? null,
            $request->query,
        )]);
    };
    $router->add('GET', '/v1/history', $history);
    $router->add('GET', '/v1/family/feed', $history);

    $serveAnswerMedia = static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $answerMedia): never {
        $user = $sessions->requireUser($request);
        $file = $answerMedia->download(
            (int) $user['id'],
            $parameters['mediaId'],
            $parameters['token'],
        );
        Response::file(
            $file['path'],
            $file['mimeType'],
            $file['byteCount'],
            $file['fileName'],
            $request->header('range'),
            $request->method === 'HEAD',
        );
    };
    $router->add('GET', '/v1/answer-media/{mediaId}/{token}', $serveAnswerMedia);
    $router->add('HEAD', '/v1/answer-media/{mediaId}/{token}', $serveAnswerMedia);

    $router->add('PATCH', '/v1/answers/{answerId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['answer' => $app->updateAnswer(
            (int) $user['id'],
            $parameters['answerId'],
            $body['body'] ?? null,
        )]]);
    });
    $router->add('DELETE', '/v1/answers/{answerId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $app->deleteAnswer((int) $user['id'], $parameters['answerId']);
        Response::json(['data' => (object) []]);
    });
    $router->add('DELETE', '/v1/answers/{answerId}/media/{mediaId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => ['answer' => $app->deleteAnswerMedia(
            (int) $user['id'],
            $parameters['answerId'],
            $parameters['mediaId'],
        )]]);
    });

    $like = static function (Request $request, array $parameters) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->setLike((int) $user['id'], $parameters['answerId'], true)]);
    };
    $router->add('PUT', '/v1/answers/{answerId}/like', $like);
    $router->add('POST', '/v1/answers/{answerId}/like', $like);
    $router->add('DELETE', '/v1/answers/{answerId}/like', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->setLike((int) $user['id'], $parameters['answerId'], false)]);
    });
    $router->add('GET', '/v1/answers/{answerId}/comments', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        Response::json(['data' => $app->comments(
            (int) $user['id'],
            $parameters['answerId'],
            $request->query['cursor'] ?? null,
            $request->query['limit'] ?? null,
        )]);
    });
    $router->add('POST', '/v1/answers/{answerId}/comments', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['comment' => $app->addComment(
            (int) $user['id'],
            $parameters['answerId'],
            $body['body'] ?? null,
            $body['parentCommentId'] ?? null,
            $request->header('idempotency-key'),
        )]], 201);
    });
    $router->add('PATCH', '/v1/comments/{commentId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['comment' => $app->updateComment(
            (int) $user['id'],
            $parameters['commentId'],
            $body['body'] ?? null,
        )]]);
    });
    $router->add('POST', '/v1/comments/{commentId}/reports', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => ['report' => $app->reportComment(
            (int) $user['id'],
            $parameters['commentId'],
            $body['reason'] ?? null,
            $body['details'] ?? null,
        )]], 201);
    });
    $router->add('DELETE', '/v1/comments/{commentId}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $app->deleteComment((int) $user['id'], $parameters['commentId']);
        Response::json(['data' => (object) []]);
    });

    $push = static function (Request $request) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $body = $request->json();
        Response::json(['data' => $app->registerPushToken(
            (int) $user['id'],
            $body['token'] ?? null,
            $body['platform'] ?? null,
            $body['environment'] ?? null,
        )]);
    };
    $router->add('PUT', '/v1/push-tokens', $push);
    $router->add('POST', '/v1/push-tokens', $push);
    $router->add('DELETE', '/v1/push-tokens/{tokenHash}', static function (
        Request $request,
        array $parameters,
    ) use ($sessions, $app): never {
        $user = $sessions->requireUser($request);
        $app->deletePushToken((int) $user['id'], $parameters['tokenHash']);
        Response::json(['data' => (object) []]);
    });

    $router->dispatch($request);
} catch (ApiException $exception) {
    $requestId = $request?->requestId ?? bin2hex(random_bytes(12));
    if ($exception->status === 401) {
        header('WWW-Authenticate: Bearer realm="tsutsuura"');
    }
    if ($exception->status === 429 && isset($exception->details['retryAfter'])) {
        header('Retry-After: ' . (string) $exception->details['retryAfter']);
    }
    $error = ['code' => $exception->errorCode, 'message' => $exception->getMessage()];
    if ($exception->details !== []) {
        $error['details'] = $exception->details;
    }
    Response::json(['error' => $error, 'requestId' => $requestId], $exception->status);
} catch (Throwable $exception) {
    $requestId = $request?->requestId ?? bin2hex(random_bytes(12));
    error_log(sprintf('[%s] %s: %s', $requestId, $exception::class, $exception->getMessage()));
    $error = ['code' => 'internal_error', 'message' => 'An unexpected server error occurred.'];
    if ($config?->debug === true) {
        $error['details'] = ['exception' => $exception::class, 'message' => $exception->getMessage()];
    }
    Response::json(['error' => $error, 'requestId' => $requestId], 500);
}

function applySecurityHeaders(Config $config): void
{
    header_remove('X-Powered-By');
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
    header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    header('Cache-Control: no-store, max-age=0');
    header('Pragma: no-cache');
    if ($config->isProduction()) {
        header('Strict-Transport-Security: max-age=31536000');
    }
}

function applyCors(Request $request, Config $config): void
{
    $origin = $request->header('origin');
    if ($origin === null || $origin === '') {
        return;
    }
    if (!in_array($origin, $config->corsAllowedOrigins, true)) {
        throw new ApiException(403, 'origin_not_allowed', 'The request origin is not allowed.');
    }
    header('Access-Control-Allow-Origin: ' . $origin);
    header('Vary: Origin');
    header('Access-Control-Allow-Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Authorization, Content-Type, Range, X-Request-ID');
    header('Access-Control-Expose-Headers: Accept-Ranges, Content-Length, Content-Range');
    header('Access-Control-Max-Age: 600');
}
