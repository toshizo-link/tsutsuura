<?php
declare(strict_types=1);

use Tsutsuura\Server\Auth\EmailAddress;
use Tsutsuura\Server\Auth\EmailOtpService;
use Tsutsuura\Server\Auth\EmailSender;
use Tsutsuura\Server\Auth\NativeEmailSender;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Auth\UserService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Security\Crypto;
use Tsutsuura\Server\Security\RateLimiter;

require dirname(__DIR__) . '/src/Autoload.php';
date_default_timezone_set('UTC');
$base = dirname(__DIR__);
$path = sys_get_temp_dir() . '/tsutsuura-email-' . bin2hex(random_bytes(8)) . '.sqlite';
foreach ([
    'APP_ENV' => 'testing', 'APP_DEBUG' => 'false', 'APP_KEY' => str_repeat('e1', 32),
    'APP_URL' => 'http://localhost', 'DB_CONNECTION' => 'sqlite', 'DB_DATABASE' => $path,
    'MEDIA_STORAGE_PATH' => $path . '-media', 'OTP_DRIVER' => 'disabled', 'OTP_DEV_EXPOSE' => 'false',
    'EMAIL_DRIVER' => 'mail', 'EMAIL_FROM_ADDRESS' => 'no-reply@example.com', 'EMAIL_DEV_EXPOSE' => 'false',
    'OTP_EMAIL_REQUESTS_PER_HOUR' => '100', 'OTP_IP_REQUESTS_PER_HOUR' => '200',
    'OTP_VERIFY_ATTEMPTS_PER_HOUR' => '200', 'OTP_MAX_ATTEMPTS' => '3', 'PUSH_DRIVER' => 'disabled',
] as $key => $value) { putenv($key . '=' . $value); }
$pdo = null;
try {
    $config = Config::fromEnvironment($base);
    $database = new Database($config);
    $pdo = $database->connection();
    foreach (glob($base . '/migrations/sqlite/*.sql') ?: [] as $migration) { $pdo->exec(file_get_contents($migration)); }
    $pdo->exec("INSERT INTO users (display_name) VALUES ('お母さん'), ('家族'), ('祖父')");
    $crypto = new Crypto($config->appKey);
    $users = new UserService($database);
    $sessions = new SessionService($database, $crypto, $config);
    $limiter = new RateLimiter($database, $crypto);
    $sender = new class implements EmailSender {
        public array $sent = [];
        public bool $fail = false;
        public function sendOtp(string $email, string $code): void {
            $this->sent[] = [$email, $code];
            if ($this->fail) { throw new RuntimeException('Deliberate local delivery failure.'); }
        }
        public function code(): string { return $this->sent[array_key_last($this->sent)][1]; }
    };
    $otp = new EmailOtpService($database, $crypto, $limiter, $sender, $users, $sessions, $config);
    eq('name+tag@example.com', EmailAddress::normalize(' ＮＡＭＥ+ｔａｇ＠ＥＸＡＭＰＬＥ.ＣＯＭ '), 'full-width normalization');
    foreach (["a@example.com\r\nBcc: victim@example.com", 'a@example.com,b@example.com', '.a@example.com', 'a..b@example.com', 'a@localhost', 'a@123.456', '名前@example.com', ['a@example.com']] as $invalid) {
        fails(fn () => EmailAddress::normalize($invalid), 'invalid_email');
    }
    $enroll = $otp->requestEnrollment(1, ' Mother+App@Example.com ', '127.0.0.1');
    $code = $sender->code();
    eq(false, array_key_exists('developmentCode', $enroll), 'production-style response omits code');
    eq(null, $users->loadById(1)['email_address'], 'unverified email never attaches');
    $stored = $pdo->query('SELECT code_hash FROM email_enrollment_challenges')->fetchColumn();
    eq($crypto->otpHash($enroll['requestId'], $code), $stored, 'challenge stores only keyed hash');
    fails(fn () => $otp->verifyEnrollment(2, $enroll['requestId'], $code, '127.0.0.1'), 'invalid_otp');
    $wrong = $code === '999999' ? '999998' : '999999';
    fails(fn () => $otp->verifyEnrollment(1, $enroll['requestId'], $wrong, '127.0.0.1', 'wrong-enrollment-key-0001'), 'invalid_otp');
    fails(fn () => $otp->verifyEnrollment(1, $enroll['requestId'], $wrong, '127.0.0.1', 'wrong-enrollment-key-0001'), 'invalid_otp');
    eq(1, (int) $pdo->query('SELECT attempts FROM email_enrollment_challenges')->fetchColumn(), 'failed retry spends one attempt');
    $profile = $otp->verifyEnrollment(1, $enroll['requestId'], $code, '127.0.0.1', 'email-enrollment-key-0001');
    eq('mother+app@example.com', $profile['email'], 'enrollment normalizes mailbox');
    eq(true, $profile['hasEmail'], 'verified profile flag');
    eq($profile, $otp->verifyEnrollment(1, $enroll['requestId'], $code, '127.0.0.1', 'email-enrollment-key-0001'), 'enrollment response replay');
    fails(fn () => $otp->verifyEnrollment(1, $enroll['requestId'], $code, '127.0.0.1'), 'invalid_otp');
    fails(fn () => $otp->verifyEnrollment(2, $enroll['requestId'], $code, '127.0.0.1', 'email-enrollment-key-0001'), 'idempotency_key_reused');
    fails(fn () => $otp->requestEnrollment(1, 'mother+app@example.com', '127.0.0.1'), 'email_already_enrolled');
    fails(fn () => $otp->requestEnrollment(2, 'mother+app@example.com', '127.0.0.1'), 'email_already_in_use');
    eq(false, array_key_exists('email', Presenter::user($users->loadById(1))), 'family presenter omits private address');

    $login = $otp->request('mother+app@example.com', '127.0.0.1');
    $loginCode = $sender->code();
    $auth = $otp->verify($login['requestId'], $loginCode, '127.0.0.1', 'email-login-key-0000001');
    eq('1', $auth['user']['id'], 'email login restores original user');
    eq($auth, $otp->verify($login['requestId'], $loginCode, '127.0.0.1', 'email-login-key-0000001'), 'login exact replay retains token');
    eq(1, (int) $pdo->query('SELECT COUNT(*) FROM sessions')->fetchColumn(), 'replay never creates another session');
    fails(fn () => $otp->verify($login['requestId'], $loginCode, '127.0.0.1'), 'invalid_otp');
    fails(fn () => $otp->verify($login['requestId'], '000000', '127.0.0.1', 'email-login-key-0000001'), 'idempotency_key_reused');

    $unknown = $otp->request('unknown@example.com', '127.0.0.1');
    fails(fn () => $otp->verify($unknown['requestId'], $sender->code(), '127.0.0.1'), 'account_not_found');
    eq(3, (int) $pdo->query('SELECT COUNT(*) FROM users')->fetchColumn(), 'unknown email never provisions an accidental account');
    $preclaim = $otp->request('later@example.com', '127.0.0.1');
    $preclaimCode = $sender->code();
    $later = $otp->requestEnrollment(2, 'later@example.com', '127.0.0.1');
    $otp->verifyEnrollment(2, $later['requestId'], $sender->code(), '127.0.0.1');
    fails(fn () => $otp->verify($preclaim['requestId'], $preclaimCode, '127.0.0.1'), 'account_not_found');

    $oldLogin = $otp->request('mother+app@example.com', '127.0.0.1');
    $oldCode = $sender->code();
    $change = $otp->requestEnrollment(1, 'new@example.com', '127.0.0.1');
    $otp->verifyEnrollment(1, $change['requestId'], $sender->code(), '127.0.0.1');
    fails(fn () => $otp->verify($oldLogin['requestId'], $oldCode, '127.0.0.1'), 'invalid_otp');
    eq(null, $users->findByEmail('mother+app@example.com'), 'old mailbox loses account access');
    eq(1, (int) $pdo->query('SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL')->fetchColumn(), 'email changes preserve existing session');
    $first = $otp->requestEnrollment(3, 'first@example.com', '127.0.0.1');
    $firstCode = $sender->code();
    $second = $otp->requestEnrollment(3, 'second@example.com', '127.0.0.1');
    fails(fn () => $otp->verifyEnrollment(3, $first['requestId'], $firstCode, '127.0.0.1'), 'invalid_otp');
    $secondCode = $sender->code();
    for ($i = 0; $i < 3; $i++) { fails(fn () => $otp->verifyEnrollment(3, $second['requestId'], '000000', '127.0.0.1'), 'invalid_otp'); }
    fails(fn () => $otp->verifyEnrollment(3, $second['requestId'], $secondCode, '127.0.0.1'), 'invalid_otp');
    $expired = $otp->request('new@example.com', '127.0.0.1');
    $pdo->exec("UPDATE email_otp_challenges SET expires_at = '2000-01-01 00:00:00' WHERE request_id = " . $pdo->quote($expired['requestId']));
    fails(fn () => $otp->verify($expired['requestId'], $sender->code(), '127.0.0.1'), 'invalid_otp');

    // Both accounts can request an unclaimed address, but only the first
    // verified claim may win; the second transaction must preserve its owner.
    $claimOne = $otp->requestEnrollment(1, 'shared@example.com', '127.0.0.1');
    $claimOneCode = $sender->code();
    $claimThree = $otp->requestEnrollment(3, 'shared@example.com', '127.0.0.1');
    $claimThreeCode = $sender->code();
    $otp->verifyEnrollment(1, $claimOne['requestId'], $claimOneCode, '127.0.0.1');
    fails(fn () => $otp->verifyEnrollment(3, $claimThree['requestId'], $claimThreeCode, '127.0.0.1'), 'email_already_in_use');
    eq(null, $users->loadById(3)['email_address'], 'losing a mailbox claim never attaches the address');
    eq(1, (int) $users->findByEmail('shared@example.com')['id'], 'winning account retains its email');

    // Native mail is injected here: these checks never contact any mailbox.
    $mail = null;
    $native = new NativeEmailSender($config, static function (...$arguments) use (&$mail): bool { $mail = $arguments; return true; });
    $native->sendOtp('test@example.com', '123456');
    eq(4, count($mail), 'native transport has no shell envelope arguments');
    eq(true, str_contains(base64_decode($mail[2]), '123456'), 'Japanese MIME message includes code');
    eq('text/plain; charset=UTF-8', $mail[3]['Content-Type'], 'native UTF-8 MIME type');
    foreach ([static fn (): bool => false, static function (): bool { throw new RuntimeException('test'); }] as $failure) {
        $failedOtp = new EmailOtpService($database, $crypto, $limiter, new NativeEmailSender($config, $failure), $users, $sessions, $config);
        fails(fn () => $failedOtp->request('failed@example.com', '127.0.0.1'), 'email_delivery_failed');
        fails(fn () => $failedOtp->requestEnrollment(3, 'failed@example.com', '127.0.0.1'), 'email_delivery_failed');
    }
    eq(0, (int) $pdo->query("SELECT COUNT(*) FROM email_otp_challenges WHERE email_address='failed@example.com' AND consumed_at IS NULL")->fetchColumn(), 'failed mail invalidates login challenges');
    eq(0, (int) $pdo->query("SELECT COUNT(*) FROM email_enrollment_challenges WHERE email_address='failed@example.com' AND consumed_at IS NULL")->fetchColumn(), 'failed mail invalidates enrollment challenges');
    putenv('OTP_EMAIL_REQUESTS_PER_HOUR=1');
    $limitedConfig = Config::fromEnvironment($base);
    $limited = new EmailOtpService($database, $crypto, $limiter, $sender, $users, $sessions, $limitedConfig);
    $pdo->exec("INSERT INTO users (id, display_name) VALUES (4, '制限の確認')");
    $limited->request('limit@example.com', '127.0.0.2');
    fails(fn () => $limited->request('LIMIT@example.com', '127.0.0.3'), 'rate_limited');
    fails(fn () => $limited->requestEnrollment(4, 'limit@example.com', '127.0.0.4'), 'rate_limited');

    putenv('APP_ENV=production'); putenv('APP_URL=https://example.com');
    foreach (['EMAIL_DRIVER=log', 'EMAIL_DEV_EXPOSE=true', "EMAIL_FROM_ADDRESS=bad@example.com\r\nBcc: victim@example.com"] as $invalidConfig) {
        putenv('EMAIL_DRIVER=mail'); putenv('EMAIL_DEV_EXPOSE=false'); putenv('EMAIL_FROM_ADDRESS=no-reply@example.com');
        putenv($invalidConfig);
        try { Config::fromEnvironment($base); throw new LogicException('Unsafe mail config was accepted.'); }
        catch (RuntimeException $expected) {}
    }
    echo "Email authentication tests passed (no email sent).\n";
} finally {
    $pdo = null;
    foreach ([$path, $path . '-wal', $path . '-shm'] as $file) { if (is_file($file)) { unlink($file); } }
}

function eq(mixed $expected, mixed $actual, string $label): void {
    if ($expected !== $actual) { throw new RuntimeException('Failed: ' . $label); }
}
function fails(callable $operation, string $code): void {
    try { $operation(); } catch (ApiException $error) { eq($code, $error->errorCode, 'error ' . $code); return; }
    throw new RuntimeException('Expected API error: ' . $code);
}
