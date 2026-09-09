<?php
declare(strict_types=1);

// Exercise the real front controller. Service-only tests cannot detect the
// missing-route deployment that produced the screenshot errors.
$base = dirname(__DIR__);
$directory = sys_get_temp_dir() . '/tsutsuura-http-' . bin2hex(random_bytes(8));
mkdir($directory, 0700);
$socket = stream_socket_server('tcp://127.0.0.1:0', $errno, $error);
if ($socket === false) {
    throw new RuntimeException('Could not allocate a local test port.');
}
$address = stream_socket_get_name($socket, false);
fclose($socket);
$origin = 'http://' . $address;
foreach ([
    'APP_ENV' => 'testing', 'APP_DEBUG' => 'false', 'APP_KEY' => str_repeat('c2', 32),
    'APP_URL' => $origin, 'APP_TIMEZONE' => 'Asia/Tokyo',
    'CORS_ALLOWED_ORIGINS' => 'http://localhost:3000',
    'DB_CONNECTION' => 'sqlite', 'DB_DATABASE' => $directory . '/test.sqlite',
    'MEDIA_STORAGE_PATH' => $directory . '/media', 'OTP_DRIVER' => 'disabled',
    'OTP_DEV_EXPOSE' => 'false', 'PUSH_DRIVER' => 'disabled',
    'EMAIL_DRIVER' => 'log', 'EMAIL_DEV_EXPOSE' => 'true', 'EMAIL_FROM_ADDRESS' => 'test@example.com',
] as $key => $value) {
    putenv($key . '=' . $value);
}
$server = null;
$pdo = null;
try {
    $migration = proc_open([PHP_BINARY, $base . '/bin/migrate.php', '--seed'], [
        0 => ['file', '/dev/null', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w'],
    ], $pipes);
    if (!is_resource($migration)) {
        throw new RuntimeException('Could not start the migration fixture.');
    }
    $migrationOutput = stream_get_contents($pipes[1]);
    $migrationErrors = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    if (proc_close($migration) !== 0) {
        throw new RuntimeException('Fixture migration failed: ' . $migrationOutput . $migrationErrors);
    }
    $server = proc_open([
        PHP_BINARY, '-d', 'upload_max_filesize=64M', '-d', 'post_max_size=128M',
        '-S', $address, '-t', $base . '/public', $base . '/public/index.php',
    ], [
        0 => ['file', '/dev/null', 'r'],
        1 => ['file', $directory . '/server.log', 'a'],
        2 => ['file', $directory . '/server.log', 'a'],
    ], $pipes);
    if (!is_resource($server)) {
        throw new RuntimeException('Could not start the local API.');
    }
    $ready = false;
    for ($attempt = 0; $attempt < 50; $attempt++) {
        $probe = @stream_socket_client('tcp://' . $address, $errno, $error, 0.1);
        if (is_resource($probe)) {
            fclose($probe);
            $ready = true;
            break;
        }
        usleep(100_000);
    }
    check($ready, 'local API starts');
    $preflight = curl_init($origin . '/v1/me');
    curl_setopt_array($preflight, [
        CURLOPT_CUSTOMREQUEST => 'OPTIONS', CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER => true, CURLOPT_HTTPHEADER => [
            'Origin: http://localhost:3000',
            'Access-Control-Request-Method: POST',
            'Access-Control-Request-Headers: authorization, x-http-method-override, idempotency-key',
        ],
    ]);
    $preflightResponse = curl_exec($preflight);
    check(curl_getinfo($preflight, CURLINFO_RESPONSE_CODE) === 204, 'POST transport CORS preflight succeeds');
    check(is_string($preflightResponse) && preg_match('/^Access-Control-Allow-Headers:.*X-HTTP-Method-Override/im', $preflightResponse) === 1 &&
        preg_match('/^Access-Control-Allow-Headers:.*Idempotency-Key/im', $preflightResponse) === 1, 'CORS permits mutation transport and retry headers');
    unset($preflight);
    $health = request($origin, 'GET', '/v1/health', null, null, 200)['data'];
    foreach (['accountRecovery', 'accountExport', 'notificationPreferences', 'profileMarks', 'immutableAnswers', 'scheduledQuestions', 'emailAuthentication'] as $capability) {
        check(($health['capabilities'][$capability] ?? false) === true, 'health advertises ' . $capability);
    }
    check($health['authProviders']['phone'] === false, 'phone provider availability is explicit');
    $auth = request($origin, 'POST', '/v1/setup/family', [
        'organizerName' => 'たかみ', 'familyName' => 'たかみさんの家族',
    ], null, 201)['data'];
    $token = $auth['token'];
    $userID = (int) $auth['user']['id'];
    request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => 'America/Toronto'], null, 401, 'authentication_required', methodOverride: 'PATCH');
    $deviceTimezone = request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => 'America/Toronto'], $token, 200, methodOverride: 'PATCH')['data'];
    check($deviceTimezone['timezone'] === 'America/Toronto' && $deviceTimezone['questionRemindersEnabled'] && $deviceTimezone['commentsEnabled'] && $deviceTimezone['likesEnabled'] && $deviceTimezone['familyActivityEnabled'], 'device timezone inserts defaults without a push token');
    foreach ([null, '', '+05:00', 'GMT+5', 'Invalid/Zone', ['Asia/Tokyo']] as $invalidZone) {
        request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => $invalidZone], $token, 422, 'invalid_timezone', methodOverride: 'PATCH');
    }
    request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => 'UTC', 'commentsEnabled' => false], $token, 422, 'invalid_timezone', methodOverride: 'PATCH');
    request($origin, 'POST', '/v1/me/timezone', null, $token, 422, 'invalid_timezone', methodOverride: 'PATCH');
    request($origin, 'POST', '/v1/me', ['avatarMark' => 'invalid'], null, 401, 'authentication_required', methodOverride: 'PATCH');
    request($origin, 'POST', '/v1/me', ['avatarMark' => 'invalid'], $token, 422, 'invalid_avatar_mark', methodOverride: 'PATCH');
    request($origin, 'POST', '/v1/me', ['displayName' => 'not applied'], $token, 405, 'method_not_allowed');
    foreach (['GET', 'POST', 'OPTIONS', 'TRACE', 'PATCH,DELETE', ''] as $invalidOverride) {
        request($origin, 'POST', '/v1/me', ['displayName' => 'not applied'], $token, 400, 'invalid_method_override', methodOverride: $invalidOverride);
    }
    request($origin, 'GET', '/v1/me', null, $token, 400, 'invalid_method_override', methodOverride: 'DELETE');
    request($origin, 'PATCH', '/v1/me', ['displayName' => 'not applied'], $token, 400, 'invalid_method_override', methodOverride: 'PATCH');
    check(request($origin, 'GET', '/v1/me', null, $token, 200)['data']['displayName'] === 'たかみ', 'rejected overrides never mutate profile');
    $mark = str_repeat('1000000000000001', 16);
    $profile = request($origin, 'POST', '/v1/me', ['avatarMark' => $mark], $token, 200, methodOverride: 'PATCH')['data'];
    check($profile['avatarMark'] === $mark && $profile['displayName'] === 'たかみ', 'mark-only profile patch');
    check(request($origin, 'GET', '/v1/me', null, $token, 200)['data']['avatarMark'] === $mark, 'mark survives authenticated reload');
    request($origin, 'PATCH', '/v1/me', ['avatarMark' => 'invalid'], $token, 422, 'invalid_avatar_mark');
    $renamedProfile = request($origin, 'PATCH', '/v1/me', ['displayName' => 'たかも'], $token, 200)['data'];
    check($renamedProfile['family']['name'] === 'たかもさんの家族', 'profile response refreshes displayed family name immediately');
    $family = request($origin, 'GET', '/v1/family', null, $token, 200)['data'];
    check($family['name'] === 'たかもさんの家族', 'generated family name follows owner');
    check($family['members'][0]['avatarMark'] === $mark, 'family member mark');
    $maximumNameProfile = request($origin, 'PATCH', '/v1/me', ['displayName' => str_repeat('名', 80)], $token, 200)['data'];
    check($maximumNameProfile['family']['name'] === str_repeat('名', 75) . 'さんの家族', 'maximum-length owner generates a schema-safe family name');
    request($origin, 'PATCH', '/v1/me', ['displayName' => 'たかも'], $token, 200);
    check(request($origin, 'GET', '/v1/family', null, $token, 200)['data']['name'] === 'たかもさんの家族', 'derived family tracking survives a maximum-length name');
    request($origin, 'PATCH', '/v1/family', ['name' => 'みんなの家'], $token, 200);
    request($origin, 'PATCH', '/v1/me', ['displayName' => 'たかみ'], $token, 200);
    check(request($origin, 'GET', '/v1/family', null, $token, 200)['data']['name'] === 'みんなの家', 'custom family name stays independent');

    request($origin, 'GET', '/v1/me/notification-preferences', null, null, 401, 'authentication_required');
    request($origin, 'GET', '/v1/me/notification-preferences', null, $token, 200);
    $preferences = request($origin, 'PATCH', '/v1/me/notification-preferences', [
        'commentsEnabled' => false, 'likesEnabled' => false, 'timezone' => 'Asia/Tokyo',
    ], $token, 200)['data'];
    check(!$preferences['commentsEnabled'] && !$preferences['likesEnabled'], 'notification preferences save');
    check(!request($origin, 'GET', '/v1/me/notification-preferences', null, $token, 200)['data']['commentsEnabled'], 'notification preferences persist');
    $beforeTimezoneSync = request($origin, 'PATCH', '/v1/me/notification-preferences', [
        'questionRemindersEnabled' => false, 'questionReminderTime' => '18:45',
        'familyActivityEnabled' => false, 'quietStart' => '21:30', 'quietEnd' => '08:15',
        'muteUntil' => '2099-01-01T00:00:00Z',
    ], $token, 200)['data'];
    $afterTimezoneSync = request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => 'Europe/Berlin'], $token, 200, methodOverride: 'PATCH')['data'];
    foreach ($beforeTimezoneSync as $field => $value) {
        if (!in_array($field, ['timezone', 'updatedAt'], true)) {
            check($afterTimezoneSync[$field] === $value, 'timezone sync preserves ' . $field);
        }
    }
    check($afterTimezoneSync['timezone'] === 'Europe/Berlin', 'timezone-only update is saved');
    $unrelatedAuth = request($origin, 'POST', '/v1/setup/family', ['organizerName' => '別の家族', 'familyName' => '別の家族の設定'], null, 201)['data'];
    request($origin, 'POST', '/v1/me/timezone', ['timeZoneIdentifier' => 'UTC', 'userId' => $unrelatedAuth['user']['id']], $token, 422, 'invalid_timezone', methodOverride: 'PATCH');
    request($origin, 'PATCH', '/v1/me/timezone', ['timeZoneIdentifier' => 'UTC'], $token, 200);
    check(request($origin, 'GET', '/v1/me/notification-preferences', null, $unrelatedAuth['token'], 200)['data']['timezone'] === null, 'device timezone cannot target another account');
    request($origin, 'POST', '/v1/me', null, $unrelatedAuth['token'], 200, methodOverride: 'DELETE');
    $recovery = request($origin, 'POST', '/v1/me/recovery-codes', [], $token, 201)['data'];
    check(is_string($recovery['code'] ?? null) && strlen($recovery['code']) > 10, 'recovery code route works');
    request($origin, 'POST', '/v1/me/phone/request', ['phone' => '09000000000'], $token, 503, 'auth_provider_unavailable');
    request($origin, 'POST', '/v1/me/phone/verify', ['requestId' => 'invalid', 'code' => '123456'], null, 401, 'authentication_required');

    check($health['authProviders']['email'] === true, 'email provider availability is explicit');
    request($origin, 'POST', '/v1/me/email/request', ['email' => 'mother@example.com'], null, 401, 'authentication_required');
    request($origin, 'POST', '/v1/auth/email/request', ['email' => "a@example.com\r\nBcc: other@example.com"], null, 422, 'invalid_email');
    $enrollment = request($origin, 'POST', '/v1/me/email/request', ['email' => 'Mother@Example.com'], $token, 202)['data'];
    $emailBody = ['requestId' => $enrollment['requestId'], 'code' => $enrollment['developmentCode']];
    $emailProfile = request($origin, 'POST', '/v1/me/email/verify', $emailBody, $token, 200, null, false, 'http-email-enrollment-0001')['data']['user'];
    check($emailProfile['email'] === 'mother@example.com' && $emailProfile['hasEmail'], 'email enrollment HTTP profile contract');
    check(request($origin, 'POST', '/v1/me/email/verify', $emailBody, $token, 200, null, false, 'http-email-enrollment-0001')['data']['user'] === $emailProfile, 'email enrollment HTTP retry');
    check(request($origin, 'GET', '/v1/me', null, $token, 200)['data']['email'] === 'mother@example.com', 'own profile reload includes email');
    $privateFamily = request($origin, 'GET', '/v1/family', null, $token, 200)['data'];
    check(!array_key_exists('email', $privateFamily['members'][0]), 'family response never exposes private email');
    $emailLogin = request($origin, 'POST', '/v1/auth/email/request', ['email' => 'mother@example.com'], null, 202)['data'];
    $loginBody = ['requestId' => $emailLogin['requestId'], 'code' => $emailLogin['developmentCode']];
    $emailSession = request($origin, 'POST', '/v1/auth/email/verify', $loginBody, null, 200, null, false, 'http-email-login-0000001')['data'];
    check($emailSession['user']['id'] === (string) $userID && $emailSession['user']['hasEmail'], 'email restores original account');
    check(request($origin, 'POST', '/v1/auth/email/verify', $loginBody, null, 200, null, false, 'http-email-login-0000001')['data'] === $emailSession, 'email HTTP login retry preserves token');
    request($origin, 'POST', '/v1/auth/email/verify', $loginBody, null, 422, 'invalid_otp');

    // Force only this isolated fixture's release into the past, making the
    // HTTP submit test independent of the time it runs. Scheduling has its
    // own clock-controlled before/after publication tests.
    $homeQuestion = request($origin, 'GET', '/v1/home', null, $token, 200)['data']['todayQuestion'];
    check($homeQuestion['timeZoneIdentifier'] === 'Asia/Tokyo', 'question publication uses explicit app timezone, independent of recipient timezone');
    $pdo = new PDO('sqlite:' . $directory . '/test.sqlite', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $pdo->exec("UPDATE daily_question_publications SET available_at = '2000-01-01 00:00:00'");
    request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '古い質問への回答', 'questionId' => '99999999'], $token, 409, 'question_changed');
    request($origin, 'POST', '/v1/questions/today/answer', ['body' => '古い質問への回答', 'questionId' => '99999999'], $token, 409, 'question_changed', true);
    check((int) $pdo->query('SELECT COUNT(*) FROM answers')->fetchColumn() === 0, 'stale question submission does not write an answer');
    $questionID = (string) $pdo->query('SELECT question_id FROM daily_question_publications LIMIT 1')->fetchColumn();
    $questionDate = (string) $pdo->query('SELECT local_date FROM daily_question_publications LIMIT 1')->fetchColumn();
    $staleQuestionDate = (new DateTimeImmutable($questionDate))->modify('-1 day')->format('Y-m-d');
    request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '日付が古い回答', 'questionId' => $questionID, 'questionDate' => $staleQuestionDate], $token, 409, 'question_changed');
    request($origin, 'POST', '/v1/questions/today/answer', ['body' => '日付が古い回答', 'questionId' => $questionID, 'questionDate' => $staleQuestionDate], $token, 409, 'question_changed', true);
    request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '日付が不正な回答', 'questionId' => $questionID, 'questionDate' => '2026-02-30'], $token, 422, 'invalid_question_date');
    check((int) $pdo->query('SELECT COUNT(*) FROM answers')->fetchColumn() === 0, 'same-question stale date does not write an answer');
    $answer = request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '家族にありがとう', 'questionId' => $questionID, 'questionDate' => $questionDate], $token, 200)['data']['answer'];
    check($answer['author']['avatarMark'] === $mark, 'answer author mark');
    $repeat = request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '家族にありがとう'], $token, 200)['data']['answer'];
    check($repeat['id'] === $answer['id'], 'answer retry returns original ID');
    $overrideRepeat = request($origin, 'POST', '/v1/questions/today/answer', ['body' => '家族にありがとう'], $token, 200, methodOverride: 'PUT')['data']['answer'];
    check($overrideRepeat['id'] === $answer['id'], 'POST transport preserves PUT answer retry');
    request($origin, 'PUT', '/v1/questions/today/answer', ['body' => '変更'], $token, 409, 'answer_immutable');
    request($origin, 'PATCH', '/v1/answers/' . $answer['id'], ['body' => '変更'], $token, 409, 'answer_immutable');
    request($origin, 'DELETE', '/v1/answers/' . $answer['id'], null, $token, 409, 'answer_immutable');
    $comment = request($origin, 'POST', '/v1/answers/' . $answer['id'] . '/comments', ['body' => 'ありがとう'], $token, 201)['data']['comment'];
    check($comment['author']['avatarMark'] === $mark, 'comment author mark');
    $found = request($origin, 'GET', '/v1/history?search=' . rawurlencode('ありがとう'), null, $token, 200)['data'];
    check(count($found['items']) === 1, 'history search returns matching answer');
    $missing = request($origin, 'GET', '/v1/history?search=' . rawurlencode('存在しない語'), null, $token, 200)['data'];
    check(count($missing['items']) === 0, 'history search omits unrelated answers');
    $export = request($origin, 'GET', '/v1/me/export', null, $token, 200)['data'];
    check($export['account']['avatarMark'] === $mark && count($export['answers']) === 1, 'export route includes own data');
    request($origin, 'PATCH', '/v1/me', ['avatarMark' => null], $token, 200);
    check(request($origin, 'GET', '/v1/me', null, $token, 200)['data']['avatarMark'] === null, 'mark can be reset');
    request($origin, 'POST', '/v1/me', null, null, 401, 'authentication_required', methodOverride: 'DELETE');
    request($origin, 'POST', '/v1/me', null, $token, 200, idempotencyKey: 'http-override-account-delete-0001', methodOverride: 'DELETE');
    request($origin, 'GET', '/v1/me', null, $token, 401, 'invalid_session');
    request($origin, 'POST', '/v1/me', null, $token, 200, idempotencyKey: 'http-override-account-delete-0001', methodOverride: 'DELETE');
    echo "HTTP contract tests passed.\n";
} finally {
    $pdo = null;
    if (is_resource($server)) {
        proc_terminate($server);
        proc_close($server);
    }
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST);
    foreach ($iterator as $file) {
        $file->isDir() ? rmdir($file->getPathname()) : unlink($file->getPathname());
    }
    rmdir($directory);
}

function check(bool $condition, string $label): void
{
    if (!$condition) {
        throw new RuntimeException('Failed: ' . $label);
    }
}

/** @return array<string, mixed> */
function request(string $origin, string $method, string $path, ?array $body, ?string $token, int $status, ?string $errorCode = null, bool $multipart = false, ?string $idempotencyKey = null, ?string $methodOverride = null): array
{
    $curl = curl_init($origin . $path);
    $headers = ['Accept: application/json'];
    if ($methodOverride !== null) { $headers[] = $methodOverride === '' ? 'X-HTTP-Method-Override;' : 'X-HTTP-Method-Override: ' . $methodOverride; }
    if ($idempotencyKey !== null) { $headers[] = 'Idempotency-Key: ' . $idempotencyKey; }
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    if ($body !== null) {
        if ($multipart) {
            curl_setopt($curl, CURLOPT_POSTFIELDS, $body);
        } else {
            $headers[] = 'Content-Type: application/json';
            curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode((object) $body, JSON_THROW_ON_ERROR));
        }
    }
    curl_setopt_array($curl, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_TIMEOUT => 10]);
    $raw = curl_exec($curl);
    $actualStatus = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    check(is_string($raw), $method . ' ' . $path . ' responds');
    $response = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
    check($actualStatus === $status, $method . ' ' . $path . ' expected ' . $status . ', got ' . $actualStatus . ' (' . ($response['error']['code'] ?? 'success') . ')');
    if ($errorCode !== null) {
        check(($response['error']['code'] ?? null) === $errorCode, $method . ' ' . $path . ' error code');
    }
    return $response;
}
