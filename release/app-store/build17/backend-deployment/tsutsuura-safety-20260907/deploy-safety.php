<?php
declare(strict_types=1);

// Private CLI upgrade. Never upload under public_html. No network/mail/APNs calls.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
umask(0077);
date_default_timezone_set('UTC');
const EXPECTED_HOME = '/home/c8629971';
const MANIFEST_SHA256 = 'ed619005df1cae06d5ac530719b0aaac382da66e78f312ae521b94b17631f5f4';
const RELEASE = '20260907-safety-011';
const MAINTENANCE = "<?php\nhttp_response_code(503);\nheader('Content-Type: application/json; charset=utf-8');\nheader('Retry-After: 300');\necho '{\"error\":{\"code\":\"maintenance\",\"message\":\"更新しています。少しお待ちください。\"}}';\n";

$stage = realpath(__DIR__);
$app = EXPECTED_HOME . '/apps/tsutsuura';
$public = EXPECTED_HOME . '/public_html/toshizo.link/tsutsuura-api/api';
$target = $app . '/releases/' . RELEASE;
$statePath = $stage . '/deployment-state.json';
$lock = null;
try {
    $mode = $argv[1] ?? '';
    $ack = array_slice($argv, 2);
    if (!in_array($mode, ['--check-only','--quiesce','--deploy','--rollback','--status'], true)
        || ($mode !== '--check-only' && $mode !== '--status' && $ack !== ['--workers-paused'])
        || (in_array($mode, ['--check-only','--status'], true) && $ack !== [])) {
        throw new RuntimeException('Use --check-only, --status, or --quiesce/--deploy/--rollback --workers-paused.');
    }
    must($stage === EXPECTED_HOME . '/tsutsuura-safety-20260907', 'Unexpected private staging path.');
    foreach ([$app,$app.'/storage',$app.'/releases',$public] as $dir) {
        must(is_dir($dir) && !is_link($dir) && realpath($dir) === $dir, 'Unexpected installation directory.');
    }
    must(is_file($app.'/.env') && !is_link($app.'/.env'), 'Shared environment is missing or linked unexpectedly.');
    must(is_link($app.'/current'), 'Current release must be a symlink.');
    $current = realpath($app.'/current');
    must(is_string($current) && str_starts_with($current,$app.'/releases/'), 'Current release is outside the private release directory.');
    must(trim((string)file_get_contents($public.'/.app-root')) === $app.'/current', 'Public release pointer differs.');
    must(hash_file('sha256',$stage.'/payload-manifest.json') === MANIFEST_SHA256, 'Payload manifest hash differs.');
    $manifest = json_decode((string)file_get_contents($stage.'/payload-manifest.json'),true,64,JSON_THROW_ON_ERROR);
    foreach ($manifest['files'] as $path=>$hash) {
        must(is_file($stage.'/'.$path) && !is_link($stage.'/'.$path) && realpath($stage.'/'.$path) === $stage.'/'.$path
            && hash_file('sha256',$stage.'/'.$path) === $hash, 'Payload file missing or altered: '.$path);
    }
    $actual=[];
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($stage.'/server',FilesystemIterator::SKIP_DOTS)) as $file) {
        must(!$file->isLink(), 'Payload contains a symlink.');
        if ($file->isFile()) { $actual[]=substr($file->getPathname(),strlen($stage)+1); }
    }
    $expected=array_keys($manifest['files']); sort($actual); sort($expected);
    must($actual===$expected, 'Payload contains unexpected files.');
    must(PHP_VERSION_ID>=80200 && function_exists('proc_open'), 'PHP 8.2+ and proc_open required.');
    foreach (['curl','fileinfo','intl','json','mbstring','openssl','PDO','pdo_sqlite'] as $extension) {
        must(extension_loaded($extension), 'Missing PHP extension: '.$extension);
    }
    require $stage.'/server/src/Autoload.php';
    // Load existing configuration only; do not alter .env or instantiate any sender/provider.
    $config=\Tsutsuura\Server\Config::fromEnvironment($current);
    must($config->environment==='production' && $config->dbConnection==='sqlite'
        && $config->dbName===$app.'/storage/tsutsuura.sqlite'
        && $config->mediaStoragePath===$app.'/storage/answer-media'
        && $config->appUrl==='https://toshizo.link/tsutsuura-api/api', 'Configured production target differs.');
    $pdo=new PDO('sqlite:'.$config->dbName,null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    $pdo->exec('PRAGMA busy_timeout=15000; PRAGMA foreign_keys=ON');
    must($pdo->query('PRAGMA integrity_check')->fetchColumn()==='ok' && $pdo->query('PRAGMA foreign_key_check')->fetch()===false,'SQLite integrity check failed.');
    $versions=$pdo->query('SELECT version FROM schema_migrations ORDER BY version')->fetchAll(PDO::FETCH_COLUMN);
    $expectedVersions=array_map('basename',glob($stage.'/server/migrations/sqlite/*.sql')); sort($expectedVersions);
    $oldVersions=array_values(array_filter($expectedVersions,fn($v)=>$v!=='011_content_safety.sql'));
    must($versions===$oldVersions || $versions===$expectedVersions,'Unexpected migration ledger; inspect before upgrading.');
    $workers=activeWorkers($app);
    $state=is_file($statePath)?json_decode((string)file_get_contents($statePath),true,64,JSON_THROW_ON_ERROR):null;
    if ($mode==='--status') {
        output(['state'=>$state['status']??'not_started','current'=>$current,'migration011'=>in_array('011_content_safety.sql',$versions,true),'activeWorkerCount'=>$workers,'maintenance'=>hash_file('sha256',$public.'/index.php')===hash('sha256',MAINTENANCE)]); exit;
    }
    if ($mode==='--check-only') {
        if ($current!==$target) { baseline($current,$public,$manifest); }
        foreach ($manifest['files'] as $path=>$hash) {
            if (str_ends_with($path,'.php')) { run([PHP_BINARY,'-l',$stage.'/'.$path]); }
        }
        output(['status'=>'preflight_passed','php'=>PHP_VERSION,'current'=>$current,'payloadFiles'=>count($manifest['files']),'manifestSHA256'=>MANIFEST_SHA256,'migration011'=>in_array('011_content_safety.sql',$versions,true),'activeWorkerCount'=>$workers,'productionDataChanged'=>false,'networkEmailPushCalled'=>false]); exit;
    }
    must($workers===0, 'A known worker/cleanup CLI process is still active, or process visibility is unavailable.');
    $lock=fopen($stage.'/deployment.lock','c');
    must(is_resource($lock) && flock($lock,LOCK_EX|LOCK_NB),'Another deployment operation is active.');
    if ($mode==='--quiesce') {
        if (is_array($state)) {
            must($state['status']==='quiesced' && hash_file('sha256',$public.'/index.php')===hash('sha256',MAINTENANCE),'Existing deployment state requires inspection.');
            output(['status'=>'already_quiesced']); exit;
        }
        baseline($current,$public,$manifest);
        must(!file_exists($target) && !is_link($target),'Release target already exists without matching deployment state.');
        must(!file_exists($stage.'/index.before.php') && !is_link($stage.'/index.before.php'),'Public-index backup already exists without matching deployment state.');
        must(copy($public.'/index.php',$stage.'/index.before.php'),'Cannot back up current public index.');
        $state=['release'=>RELEASE,'manifestSHA256'=>MANIFEST_SHA256,'status'=>'prepared','oldCurrent'=>$current,'oldPublicIndexSHA256'=>hash_file('sha256',$public.'/index.php'),
            'envSHA256'=>hash_file('sha256',$app.'/.env'),'publicPreserved'=>preservedPublic($public),'quiescedAt'=>time()];
        saveState($statePath,$state);
        atomic($public.'/index.php',MAINTENANCE,0644);
        $state['status']='quiesced'; saveState($statePath,$state);
        output(['status'=>'quiesced','waitSeconds'=>300,'workersRemainPaused'=>true]); exit;
    }
    must(is_array($state) && $state['release']===RELEASE && $state['manifestSHA256']===MANIFEST_SHA256,'Matching deployment state is missing.');
    must(hash_file('sha256',$app.'/.env')===$state['envSHA256'] && preservedPublic($public)===$state['publicPreserved'],'Shared config/public ancillary files changed; inspect before continuing.');
    if ($mode==='--deploy') {
        if ($state['status']==='installed') {
            must($current===$target && hash_file('sha256',$public.'/index.php')===$manifest['files']['server/public/index.php'],'Installed state does not match active code.');
            output(['status'=>'already_installed','verifyHTTPS'=>true]); exit;
        }
        must($state['status']==='quiesced' && $current===$state['oldCurrent'] && time()-$state['quiescedAt']>=300,'Require unchanged quiesced state, paused/drained workers and at least 300 seconds for HTTP requests to drain.');
        must(hash_file('sha256',$public.'/index.php')===hash('sha256',MAINTENANCE),'Maintenance index changed.');
        must(!file_exists($target) && !is_link($target),'A partial target exists; inspect rather than overwriting it.');
        baseline($current,null,$manifest);
        $state['status']='deploying'; saveState($statePath,$state);
        must(mkdir($target,0700),'Cannot create the private release directory.');
        foreach ($manifest['files'] as $path=>$hash) {
            $relative=substr($path,7); $destination=$target.'/'.$relative;
            if (!is_dir(dirname($destination))) { must(mkdir(dirname($destination),0700,true),'Cannot create a release subdirectory.'); }
            must(copy($stage.'/'.$path,$destination) && hash_file('sha256',$destination)===$hash,'Release copy failed.'); chmod($destination,0600);
        }
        must(symlink($app.'/.env',$target.'/.env') && symlink($app.'/storage',$target.'/storage'),'Shared config/storage links failed.');
        // A consistent private database backup. Never replace/rewind the live DB on code rollback.
        $backup=$app.'/storage/safety-backups/'.RELEASE;
        must(!file_exists($backup) && !is_link($backup),'Backup directory already exists; inspect partial deployment.');
        must(mkdir($backup,0700,true),'Cannot create private backup directory.');
        $pdo->exec('VACUUM INTO '.$pdo->quote($backup.'/before.sqlite'));
        chmod($backup.'/before.sqlite',0600);
        $counts=tableCounts($pdo);
        $pdo->beginTransaction();
        if (!in_array('011_content_safety.sql',$versions,true)) {
            $pdo->exec((string)file_get_contents($target.'/migrations/sqlite/011_content_safety.sql'));
            $pdo->exec("INSERT INTO schema_migrations(version) VALUES('011_content_safety.sql')");
        }
        foreach ($counts as $table=>$count) {
            if ($table!=='schema_migrations') { must((int)$pdo->query('SELECT COUNT(*) FROM "'.$table.'"')->fetchColumn()===$count,'Existing table count changed during migration.'); }
        }
        must($pdo->query('PRAGMA integrity_check')->fetchColumn()==='ok' && $pdo->query('PRAGMA foreign_key_check')->fetch()===false,'Post-migration integrity failed.');
        $pdo->commit();
        $state['backupDirectory']=$backup;
        $state['migration011Applied']=true; saveState($statePath,$state);
        switchCurrent($app,$target);
        atomic($public.'/index.php',(string)file_get_contents($target.'/public/index.php'),0644);
        $state['status']='installed'; $state['installedAt']=gmdate(DATE_ATOM); saveState($statePath,$state);
        output(['status'=>'installed','release'=>$target,'backupDirectory'=>$backup,'configKeysMediaPreserved'=>true,'onlyMigration011Applied'=>true,'networkEmailPushCalled'=>false,'workersRemainPaused'=>true,'verifyHTTPS'=>true]); exit;
    }
    // Check ownership before any rollback write, including maintenance.
    must(is_dir($state['oldCurrent']) && hash_file('sha256',$stage.'/index.before.php')===$state['oldPublicIndexSHA256'],'Previous release backup is invalid.');
    must(in_array($current,[$target,$state['oldCurrent']],true),'Another release is active.');
    $currentIndex=hash_file('sha256',$public.'/index.php');
    if ($state['status']==='rolled_back') {
        must($current===$state['oldCurrent'] && $currentIndex===$state['oldPublicIndexSHA256'],'Rolled-back state differs from active code.');
        output(['status'=>'already_rolled_back','workersRemainPaused'=>true]); exit;
    }
    must(in_array($state['status'],['quiesced','deploying','installed','rollback_quiesced'],true),'State cannot be rolled back by this helper.');
    must(in_array($currentIndex,[hash('sha256',MAINTENANCE),$manifest['files']['server/public/index.php']],true),'Public index was changed by another operator.');
    if ($state['status']!=='rollback_quiesced') {
        atomic($public.'/index.php',MAINTENANCE,0644);
        $state['status']='rollback_quiesced'; $state['rollbackQuiescedAt']=time(); saveState($statePath,$state);
        output(['status'=>'rollback_quiesced','waitSeconds'=>300,'repeatRollbackAfterDrain'=>true,'workersRemainPaused'=>true]); exit;
    }
    must($currentIndex===hash('sha256',MAINTENANCE) && time()-$state['rollbackQuiescedAt']>=300,'Rollback requires unchanged maintenance and 300 seconds for HTTP requests to drain.');
    // Old code ignores blocks/reports. Check only after traffic is drained.
    foreach (['user_blocks','answer_reports','moderation_actions','comment_reports'] as $table) {
        $exists=$pdo->prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=:name"); $exists->execute(['name'=>$table]);
        if ($exists->fetchColumn()!==false && (int)$pdo->query('SELECT COUNT(*) FROM '.$table)->fetchColumn()>0) {
            throw new RuntimeException('Rollback would disable stored content safety choices. Maintenance retained; deploy a forward fix.');
        }
    }
    switchCurrent($app,$state['oldCurrent']);
    atomic($public.'/index.php',(string)file_get_contents($stage.'/index.before.php'),0644);
    $state['status']='rolled_back'; $state['rolledBackAt']=gmdate(DATE_ATOM); saveState($statePath,$state);
    output(['status'=>'rolled_back','databaseSchemaRetained'=>true,'databaseRestored'=>false,'workersRemainPaused'=>true]);
} catch (Throwable $error) {
    if (isset($pdo) && $pdo->inTransaction()) { $pdo->rollBack(); }
    // If activation reached the exact code owned by this operation but the
    // completion write failed, close that code again. Never clobber a newer
    // operator's index or current target on a failed preflight/rollback.
    if ($mode==='--deploy' && isset($state,$manifest) && ($state['status']??null)==='deploying'
        && realpath($app.'/current')===$target && is_file($public.'/index.php')
        && hash_file('sha256',$public.'/index.php')===$manifest['files']['server/public/index.php']) {
        try { atomic($public.'/index.php',MAINTENANCE,0644); } catch (Throwable) {}
    }
    fwrite(STDERR,'FAILED: '.$error->getMessage().PHP_EOL); exit(1);
} finally { if (is_resource($lock)) { flock($lock,LOCK_UN); fclose($lock); } }

function must(bool $value,string $message): void { if (!$value) { throw new RuntimeException($message); } }
function output(array $value): void { echo json_encode($value,JSON_THROW_ON_ERROR|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES).PHP_EOL; }
function atomic(string $path,string $bytes,int $mode): void {
    must(!is_link($path),'Refusing a linked output file.'); $temp=$path.'.safety-'.bin2hex(random_bytes(4));
    must(file_put_contents($temp,$bytes,LOCK_EX)===strlen($bytes),'Atomic file write failed.'); chmod($temp,$mode);
    must(rename($temp,$path),'Atomic file replacement failed.');
}
function saveState(string $path,array $state): void { atomic($path,json_encode($state,JSON_THROW_ON_ERROR|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES)."\n",0600); }
function switchCurrent(string $app,string $target): void {
    $temp=$app.'/.current-safety-'.bin2hex(random_bytes(4));
    must(symlink($target,$temp) && rename($temp,$app.'/current'),'Atomic current-release switch failed.');
}
function baseline(string $current,?string $public,array $manifest): void {
    foreach ($manifest['expectedOldRuntime'] as $relative=>$hash) {
        $path=$current.'/'.substr($relative,7);
        must(is_file($path) && !is_link($path) && hash_file('sha256',$path)===$hash,'Live runtime differs from recorded deployed baseline: '.$relative);
    }
    if ($public!==null) { must(hash_file('sha256',$public.'/index.php')===$manifest['expectedOldPublicIndex'],'Live public index differs from recorded baseline.'); }
}
function preservedPublic(string $public): array {
    $result=[];
    foreach (['.app-root','.htaccess','.user.ini'] as $name) {
        must(is_file($public.'/'.$name) && !is_link($public.'/'.$name),'Expected public ancillary file missing.');
        $result[$name]=hash_file('sha256',$public.'/'.$name);
    }
    return $result;
}
function tableCounts(PDO $pdo): array {
    $result=[];
    foreach ($pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")->fetchAll(PDO::FETCH_COLUMN) as $table) {
        must(preg_match('/^[a-z_]+$/',$table)===1,'Unexpected table identifier.');
        $result[$table]=(int)$pdo->query('SELECT COUNT(*) FROM "'.$table.'"')->fetchColumn();
    }
    return $result;
}
function run(array $command): void {
    $proc=proc_open($command,[0=>['file','/dev/null','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    must(is_resource($proc),'Cannot start private lint.');
    stream_get_contents($pipes[1]); stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    must(proc_close($proc)===0,'Staged PHP syntax check failed.');
}
function activeWorkers(string $app): ?int {
    if (!is_readable('/proc/self/cmdline') || !is_dir('/proc')) { return null; }
    $count=0;
    foreach (glob('/proc/[0-9]*/cmdline')?:[] as $file) {
        $value=@file_get_contents($file); if (!is_string($value)) { continue; }
        if (str_contains($value,$app.'/') && preg_match('~/(?:send-event-notifications|send-question-reminders|cleanup)\.php(?:\x00|\s|$)~',$value)) { $count++; }
    }
    return $count;
}
