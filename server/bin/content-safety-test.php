<?php
declare(strict_types=1);

// HTTP + persistent storage + deterministic worker tests for UGC safety.
$base = dirname(__DIR__);
$directory = sys_get_temp_dir() . '/tsutsuura-safety-' . bin2hex(random_bytes(8));
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

    require $base . '/src/Autoload.php';
    $config = Tsutsuura\Server\Config::fromEnvironment($base);
    $database = new Tsutsuura\Server\Database($config);
    $pdo = $database->connection();
    $crypto = new Tsutsuura\Server\Security\Crypto($config->appKey);
    $safety = new Tsutsuura\Server\App\ContentSafety($database);
    $app = new Tsutsuura\Server\App\AppService($database, $crypto, $config, null, new Tsutsuura\Server\Push\EventNotificationService());
    $moderation = new Tsutsuura\Server\App\ModerationService($database);
    $provider = new Tsutsuura\Server\Push\DeterministicPushProvider();
    $delivery = new Tsutsuura\Server\Push\PushDeliveryService($database, $crypto, $config, $provider);
    $worker = new Tsutsuura\Server\Push\EventNotificationWorker($database, $delivery);
    $health = request($origin, 'GET', '/v1/health', null, null, 200)['data'];
    check($health['apiRevision'] === '2026-09-07-safety' && $health['schemaVersion'] === '011_content_safety.sql', 'safety revision and schema');
    foreach (['userBlocking', 'answerReporting', 'commentReporting', 'reportedContentHiding', 'operatorModeration'] as $capability) {
        check($health['capabilities'][$capability] === true, 'health advertises ' . $capability);
    }
    $tokens = [];
    for ($user = 1; $user <= 4; $user++) {
        $auth = request($origin, 'POST', '/v1/setup/family', ['organizerName' => '家族' . $user, 'familyName' => '家' . $user], null, 201)['data'];
        check($auth['user']['id'] === (string) $user, 'fixture user identity');
        $tokens[$user] = $auth['token'];
        $app->registerPushToken($user, str_repeat((string) $user, 64), 'ios', 'sandbox');
    }
    $pdo->exec("UPDATE family_members SET family_id = 1, role = 'member' WHERE user_id IN (2,3)");
    // Explicit fixed history fixtures keep tests independent of today's publication time.
    $pdo->exec("INSERT INTO answers(id,family_id,question_id,user_id,answer_date,body) VALUES
        (1,1,1,1,'2026-09-01','一人目の回答'),(2,1,1,2,'2026-09-01','写真と音声の回答'),
        (3,1,1,3,'2026-09-01','三人目の回答'),(4,4,1,4,'2026-09-01','別の家族の回答');
        INSERT INTO comments(id,answer_id,user_id,body) VALUES
        (1,1,2,'二人目のコメント'),(2,1,3,'三人目のコメント'),(3,4,4,'別の家族のコメント');
        INSERT INTO answer_likes(answer_id,user_id) VALUES (1,2),(1,3)");
    foreach (['photo', 'audio'] as $index => $kind) {
        $key = bin2hex(random_bytes(32)); $key = substr($key,0,2) . '/' . substr($key,2);
        $path = $directory . '/media/' . $key;
        if (!is_dir(dirname($path))) { mkdir(dirname($path),0700,true); }
        file_put_contents($path, 'private-fixture-' . $kind);
        $insert = $pdo->prepare('INSERT INTO answer_media(answer_id,kind,sort_order,storage_key,file_name,mime_type,byte_count) VALUES(2,:kind,:sort,:key,:name,:mime,:bytes)');
        $insert->execute(['kind'=>$kind,'sort'=>$index,'key'=>$key,'name'=>$kind,'mime'=>$kind==='photo'?'image/png':'audio/mp4','bytes'=>filesize($path)]);
    }
    $answer = request($origin,'GET','/v1/answers/2',null,$tokens[1],200)['data']['answer'];
    $mediaPaths = array_map(static fn($media) => parse_url($media['url'],PHP_URL_PATH),$answer['media']);
    check(count($mediaPaths) === 2, 'photo and audio are available initially');
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[1],200); mediaStatus($origin,$path,$tokens[4],404); }
    foreach (['GET','PUT','DELETE'] as $method) {
        $path = $method==='GET'?'/v1/me/blocks':'/v1/me/blocks/2';
        request($origin,$method==='GET'?'GET':'POST',$path,null,null,401,'authentication_required',methodOverride:$method==='GET'?null:$method);
    }
    request($origin,'POST','/v1/answers/2/reports',['reason'=>'privacy'],null,401,'authentication_required');
    request($origin,'POST','/v1/comments/1/reports',['reason'=>'privacy'],null,401,'authentication_required');
    request($origin,'POST','/v1/me/blocks/1',null,$tokens[1],422,'self_block_not_allowed',methodOverride:'PUT');
    request($origin,'POST','/v1/me/blocks/4',null,$tokens[1],404,'user_not_found',methodOverride:'PUT');
    request($origin,'POST','/v1/me/blocks/9999999999999999999',null,$tokens[1],422,'invalid_id',methodOverride:'PUT');
    $replayKey='safety-comment-replay-0001';
    $replayComment=request($origin,'POST','/v1/answers/2/comments',['body'=>'保存したコメント'],$tokens[1],201,idempotencyKey:$replayKey)['data']['comment'];
    // Queue a real family event before blocking: the worker must recheck it.
    (new Tsutsuura\Server\Push\EventNotificationService())->enqueueAnswerSubmitted($pdo,2,2);
    request($origin,'POST','/v1/me/blocks/2',null,$tokens[1],200,methodOverride:'PUT');
    request($origin,'PUT','/v1/me/blocks/2',null,$tokens[1],200);
    $snapshot = request($origin,'GET','/v1/me/blocks',null,$tokens[1],200)['data'];
    check(array_column($snapshot['users'],'id') === ['2'] && $snapshot['hiddenUserIds'] === ['2'], 'persistent idempotent block list');
    $reverse = request($origin,'GET','/v1/me/blocks',null,$tokens[2],200)['data'];
    check($reverse['users'] === [] && $reverse['hiddenUserIds'] === ['1'], 'mutual visibility without granting unblock ownership');
    check(request($origin,'GET','/v1/family',null,$tokens[1],200)['data']['memberCount'] === 3,'blocking preserves family count');
    $feed = request($origin,'GET','/v1/history?scope=family&limit=1',null,$tokens[1],200)['data'];
    check(array_column($feed['items'],'id')===['3'] && $feed['nextCursor']==='3','visibility applied before page limit');
    $next=request($origin,'GET','/v1/history?limit=1&cursor=3',null,$tokens[1],200)['data'];
    check(array_column($next['items'],'id')===['1'] && $next['nextCursor']===null,'cursor skips hidden answer without losing visible answers');
    // Fetching a direct answer and an old signed media URL cannot bypass hiding.
    request($origin,'GET','/v1/answers/2',null,$tokens[1],404,'answer_not_found');
    request($origin,'GET','/v1/answers/1',null,$tokens[2],404,'answer_not_found');
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[1],404); }
    $comments=request($origin,'GET','/v1/answers/1/comments',null,$tokens[1],200)['data']['items'];
    check(array_column($comments,'id') === ['2'],'blocked comments omitted');
    $counts=request($origin,'GET','/v1/answers/1',null,$tokens[1],200)['data']['answer'];
    check($counts['commentsCount']===1 && $counts['likesCount']===1,'counts match visible comments and likes');
    request($origin,'POST','/v1/answers/2/comments',['body'=>'blocked contact'],$tokens[1],404,'answer_not_found');
    request($origin,'POST','/v1/answers/2/comments',['body'=>'保存したコメント'],$tokens[1],404,'answer_not_found',idempotencyKey:$replayKey);
    request($origin,'POST','/v1/comments/'.$replayComment['id'],['body'=>'blocked edit'],$tokens[1],404,'comment_not_found',methodOverride:'PATCH');
    request($origin,'POST','/v1/answers/2/like',null,$tokens[1],404,'answer_not_found',methodOverride:'PUT');
    request($origin,'POST','/v1/answers/1/comments',['body'=>'blocked reply','parentCommentId'=>'1'],$tokens[1],404,'parent_comment_not_found');
    $worker->run();
    check(count($provider->deliveries)===1 && $provider->deliveries[0]['token']===str_repeat('3',64),'queued notification suppressed for blocker but delivered to unaffected member');
    check($delivery->deliverToUser(1,'familyActivity','題','本文',['answer_id'=>'2'])['reason']==='content_hidden','direct delivery also enforces safety');
    $before=(int)$pdo->query('SELECT COUNT(*) FROM notification_event_outbox')->fetchColumn();
    (new Tsutsuura\Server\Push\EventNotificationService())->enqueueAnswerSubmitted($pdo,2,2);
    check((int)$pdo->query('SELECT COUNT(*) FROM notification_event_outbox')->fetchColumn()===$before+1,'new enqueue excludes blocker');
    request($origin,'POST','/v1/me/blocks/1',null,$tokens[2],200,methodOverride:'DELETE');
    request($origin,'GET','/v1/answers/1',null,$tokens[2],404,'answer_not_found');
    request($origin,'POST','/v1/me/blocks/2',null,$tokens[1],200,methodOverride:'DELETE');
    request($origin,'DELETE','/v1/me/blocks/2',null,$tokens[1],200);
    request($origin,'GET','/v1/answers/2',null,$tokens[1],200);
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[1],200); }
    check(count(request($origin,'GET','/v1/answers/1/comments',null,$tokens[1],200)['data']['items'])===2,'unblock restores comments');
    // Both directions can be owned separately: one unblock does not remove the other.
    $safety->block(1,'2'); $safety->block(2,'1'); $safety->unblock(1,'2');
    request($origin,'GET','/v1/answers/2',null,$tokens[1],404,'answer_not_found');
    $safety->unblock(2,'1');
    // A block immediately cancels an old event, even if unblocked before the worker runs.
    (new Tsutsuura\Server\Push\EventNotificationService())->enqueueAnswerSubmitted($pdo,2,2);
    $safety->block(1,'2'); $safety->unblock(1,'2');
    $beforeDeliveryCount=count($provider->deliveries);
    $worker->run();
    foreach(array_slice($provider->deliveries,$beforeDeliveryCount) as $sent) {
        check($sent['token']!==str_repeat('1',64),'unblock does not revive previously canceled notification');
    }
    foreach (['/v1/answers/4/reports','/v1/comments/3/reports'] as $path) {
        request($origin,'POST',$path,['reason'=>'privacy'],$tokens[1],404);
    }
    request($origin,'POST','/v1/answers/1/reports',['reason'=>'other'],$tokens[1],422,'self_report_not_allowed');
    request($origin,'POST','/v1/answers/2/reports',['reason'=>'made_up'],$tokens[1],422,'invalid_report_reason');
    request($origin,'POST','/v1/answers/2/reports',['reason'=>'privacy','details'=>str_repeat('字',501)],$tokens[1],422,'invalid_report_details');
    $report=request($origin,'POST','/v1/answers/2/reports',['reason'=>'privacy'],$tokens[1],201)['data']['report'];
    check(request($origin,'POST','/v1/answers/2/reports',['reason'=>'privacy'],$tokens[1],201)['data']['report']===$report,'answer reporting is retry-idempotent');
    request($origin,'GET','/v1/answers/2',null,$tokens[1],404);
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[1],404); mediaStatus($origin,$path,$tokens[3],200); }
    $safety->block(1,'2'); $safety->unblock(1,'2');
    request($origin,'GET','/v1/answers/2',null,$tokens[1],404);
    $commentReport=request($origin,'POST','/v1/comments/1/reports',['reason'=>'harassment'],$tokens[1],201)['data']['report'];
    check(request($origin,'POST','/v1/comments/1/reports',['reason'=>'harassment'],$tokens[1],201)['data']['report']===$commentReport,'comment report retry stable');
    check(array_column(request($origin,'GET','/v1/answers/1/comments',null,$tokens[1],200)['data']['items'],'id')===['2'],'reported comment hidden');
    request($origin,'POST','/v1/answers/1/comments',['body'=>'hidden reply','parentCommentId'=>'1'],$tokens[1],404,'parent_comment_not_found');
    check($delivery->deliverToUser(1,'comments','題','本文',['answer_id'=>'1','comment_id'=>'1'])['reason']==='content_hidden','reported comment suppresses notification');
    $snapshot=request($origin,'GET','/v1/me/blocks',null,$tokens[1],200)['data'];
    check(in_array('2',$snapshot['hiddenAnswerIds'],true) && in_array('1',$snapshot['hiddenCommentIds'],true),'snapshot persists reported ids');
    check(count($moderation->pending())===2,'operator pending queue includes both kinds');
    check(count(json_decode(runCLI($base.'/bin/moderate-content.php',['--list']),true,64,JSON_THROW_ON_ERROR))===2,'operator CLI lists actual pending reports');
    check(count($moderation->show('answer',(int)$report['id'])['media'])===2,'operator can inspect attached media metadata');
    $moderation->review('answer',(int)$report['id'],'remove','test-operator','Privacy violation verified in fixture');
    $moderation->review('answer',(int)$report['id'],'remove','test-operator','Retry');
    request($origin,'GET','/v1/answers/2',null,$tokens[3],404);
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[3],404); }
    $moderation->review('comment',(int)$commentReport['id'],'dismiss','test-operator','Fixture reviewed');
    check(count($moderation->pending())===0,'operator decisions leave pending queue');
    $createdComment=request($origin,'POST','/v1/answers/1/comments',['body'=>'moderation replay fixture'],$tokens[3],201,idempotencyKey:'safety-moderation-replay-0002')['data']['comment'];
    $createdReport=$safety->report(1,'comment',$createdComment['id'],'other');
    runCLI($base.'/bin/moderate-content.php',['--review','--type=comment','--id='.$createdReport['id'],'--decision=remove','--operator=test-operator','--note=Fixture removal']);
    request($origin,'POST','/v1/answers/1/comments',['body'=>'moderation replay fixture'],$tokens[3],404,'comment_not_found',idempotencyKey:'safety-moderation-replay-0002');
    check(count(request($origin,'GET','/v1/answers/1/comments',null,$tokens[3],200)['data']['items'])===2,'dismiss keeps comment for other members');
    check(count(request($origin,'GET','/v1/answers/1/comments',null,$tokens[1],200)['data']['items'])===1,'dismiss does not undo reporter hide choice');
    $pdo->exec("UPDATE comment_reports SET created_at='2020-01-01',updated_at='2020-01-01'");
    runCLI($base.'/bin/cleanup.php');
    check(count(request($origin,'GET','/v1/answers/1/comments',null,$tokens[1],200)['data']['items'])===1,'cleanup retains old reporter hide choice');
    check(request($origin,'POST','/v1/answers/2/reports',['reason'=>'privacy'],$tokens[1],201)['data']['report']['status']==='reviewed','retry cannot reopen moderator decision');
    // A removed TODAY answer remains answered; it must not reopen the composer.
    $today=request($origin,'GET','/v1/questions/today',null,$tokens[2],200)['data']['question'];
    $setToday=$pdo->prepare('UPDATE answers SET answer_date=:date,question_id=:question WHERE id=2');
    $setToday->execute(['date'=>$today['date'],'question'=>$today['id']]);
    $home=request($origin,'GET','/v1/home',null,$tokens[2],200)['data'];
    check($home['myAnswer']===null && $home['todayQuestion']['hasAnswered']===true && $home['todayQuestion']['answerHidden']===true,'removed today answer is still submitted on home');
    $today=request($origin,'GET','/v1/questions/today',null,$tokens[2],200)['data'];
    check($today['answer']===null && $today['question']['hasAnswered']===true && $today['question']['answerHidden']===true,'removed today answer cannot reopen composer');
    $safety->block(2,'3'); $safety->block(3,'2');
    $safety->report(2,'answer','1','other');
    request($origin,'POST','/v1/me',null,$tokens[2],200,methodOverride:'DELETE');
    check((int)$pdo->query('SELECT COUNT(*) FROM user_blocks WHERE blocker_user_id=2 OR blocked_user_id=2')->fetchColumn()===0,'account deletion clears both block directions');
    check((int)$pdo->query('SELECT COUNT(*) FROM answer_reports WHERE reported_by_user_id=2 OR answer_id=2')->fetchColumn()===0,'account deletion clears reports for deleted reporter/content');
    check((int)$pdo->query('SELECT COUNT(*) FROM moderation_actions WHERE answer_id=2')->fetchColumn()===0,'content deletion clears associated moderation metadata');
    foreach ($mediaPaths as $path) { mediaStatus($origin,$path,$tokens[3],404); }
    $pdo->exec("DELETE FROM schema_migrations WHERE version='011_content_safety.sql'");
    request($origin,'GET','/v1/health',null,null,503);
    $pdo->exec("INSERT INTO schema_migrations(version) VALUES('011_content_safety.sql')");
    request($origin,'GET','/v1/health',null,null,200);
    echo "Safety HTTP, visibility, media, notification, moderation, unblock, and account-deletion tests passed.\n";
} finally {
    $app = $safety = $moderation = $worker = $delivery = $database = null;
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

function runCLI(string $script,array $arguments=[]): string
{
    $process=proc_open([PHP_BINARY,$script,...$arguments],[0=>['file','/dev/null','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    check(is_resource($process),'CLI starts');
    $output=stream_get_contents($pipes[1]); $errors=stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    check(proc_close($process)===0,basename($script).' succeeds: '.$errors);
    return $output;
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

function mediaStatus(string $origin,string $path,string $token,int $expected): void {
    foreach (['GET','HEAD'] as $method) {
        $curl=curl_init($origin.$path);
        curl_setopt_array($curl,[CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_NOBODY=>$method==='HEAD',CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>['Authorization: Bearer '.$token],CURLOPT_TIMEOUT=>5]);
        curl_exec($curl);
        check(curl_getinfo($curl,CURLINFO_RESPONSE_CODE)===$expected,$method.' private media expected '.$expected);
    }
}
