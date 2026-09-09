<?php
declare(strict_types=1);

namespace Tsutsuura\Server;

use DateTimeZone;
use RuntimeException;

final readonly class Config
{
    /**
     * @param list<string> $corsAllowedOrigins
     * @param list<string> $trustedProxies
     */
    private function __construct(
        public string $environment,
        public bool $debug,
        public string $appKey,
        public string $appUrl,
        public DateTimeZone $timezone,
        public array $corsAllowedOrigins,
        public array $trustedProxies,
        public string $dbConnection,
        public string $dbHost,
        public int $dbPort,
        public string $dbName,
        public string $dbUser,
        public string $dbPassword,
        public ?string $dbSslCa,
        public string $mediaStoragePath,
        public int $answerAudioMaxBytes,
        public int $answerPhotoMaxBytes,
        public int $answerPhotoMaxCount,
        public int $answerMediaFamilyQuotaBytes,
        public int $answerMediaUserUploadsPerHour,
        public int $answerMediaIpUploadsPerHour,
        public int $sessionTtlDays,
        public int $otpTtlSeconds,
        public int $otpMaxAttempts,
        public int $otpPhoneRequestsPerHour,
        public int $otpEmailRequestsPerHour,
        public int $otpIpRequestsPerHour,
        public int $otpVerifyAttemptsPerHour,
        public int $setupFamilyIpRequestsPerHour,
        public int $pairingIpAttemptsPerHour,
        public int $pairingTtlSeconds,
        public string $otpDriver,
        public bool $otpDevExpose,
        public string $emailDriver,
        public bool $emailDevExpose,
        public ?string $emailFromAddress,
        public ?string $twilioAccountSid,
        public ?string $twilioAuthToken,
        public ?string $twilioFromNumber,
        public string $twilioApiBase,
        public string $pushDriver,
        public ?string $apnsTeamId,
        public ?string $apnsKeyId,
        public ?string $apnsPrivateKeyPath,
        public ?string $apnsTopic,
    ) {
    }

    public static function fromEnvironment(string $basePath): self
    {
        Env::load($basePath . '/.env');

        $environment = strtolower(Env::get('APP_ENV', 'production') ?? 'production');
        $debug = Env::bool('APP_DEBUG', false);
        $appKey = Env::require('APP_KEY');
        $appUrl = rtrim(Env::require('APP_URL'), '/');
        $timezoneName = Env::get('APP_TIMEZONE', 'Asia/Tokyo') ?? 'Asia/Tokyo';
        $otpDriver = strtolower(Env::get('OTP_DRIVER', 'disabled') ?? 'disabled');
        $cors = Env::csv('CORS_ALLOWED_ORIGINS');
        $dbConnection = strtolower(Env::get('DB_CONNECTION', 'mysql') ?? 'mysql');
        $dbName = Env::require('DB_DATABASE');
        if ($dbConnection === 'sqlite' && !str_starts_with($dbName, DIRECTORY_SEPARATOR)) {
            $dbName = $basePath . '/' . ltrim($dbName, '/');
        }
        if ($dbConnection === 'sqlite') {
            $databaseDirectory = realpath(dirname($dbName));
            $publicDirectory = realpath($basePath . '/public');
            if ($databaseDirectory !== false) {
                $dbName = $databaseDirectory . DIRECTORY_SEPARATOR . basename($dbName);
            }
            $normalizedDatabase = rtrim(str_replace('\\', '/', dirname($dbName)), '/') . '/';
            $normalizedPublic = $publicDirectory === false
                ? rtrim(str_replace('\\', '/', $basePath), '/') . '/public/'
                : rtrim(str_replace('\\', '/', $publicDirectory), '/') . '/';
            if (str_starts_with($normalizedDatabase, $normalizedPublic)) {
                throw new RuntimeException('The SQLite database must be stored outside the public document root.');
            }
        }
        $mediaStoragePath = Env::get('MEDIA_STORAGE_PATH', 'storage/answer-media') ?? 'storage/answer-media';
        if (!str_starts_with($mediaStoragePath, DIRECTORY_SEPARATOR)) {
            $mediaStoragePath = $basePath . '/' . ltrim($mediaStoragePath, '/');
        }
        $mediaStoragePath = self::normalizeAbsolutePath($mediaStoragePath);
        $mediaStoragePath = self::resolveProspectivePath($mediaStoragePath);
        $normalizedMedia = rtrim(str_replace('\\', '/', $mediaStoragePath), '/') . '/';
        $publicDirectory = realpath($basePath . '/public');
        $normalizedPublic = $publicDirectory === false
            ? rtrim(str_replace('\\', '/', $basePath), '/') . '/public/'
            : rtrim(str_replace('\\', '/', $publicDirectory), '/') . '/';
        if (str_starts_with($normalizedMedia, $normalizedPublic)) {
            throw new RuntimeException('Answer media must be stored outside the public document root.');
        }
        $apnsPrivateKeyPath = self::nullable(Env::get('APNS_PRIVATE_KEY_PATH'));
        if ($apnsPrivateKeyPath !== null) {
            if (preg_match('/[\x00-\x1F\x7F]/', $apnsPrivateKeyPath) === 1) {
                throw new RuntimeException('APNS_PRIVATE_KEY_PATH cannot contain control characters.');
            }
            if (!str_starts_with($apnsPrivateKeyPath, DIRECTORY_SEPARATOR)) {
                $apnsPrivateKeyPath = $basePath . '/' . ltrim($apnsPrivateKeyPath, '/');
            }
            $apnsPrivateKeyPath = self::normalizeAbsolutePath($apnsPrivateKeyPath);
            $normalizedConfiguredKey = rtrim(str_replace('\\', '/', $apnsPrivateKeyPath), '/');
            if (str_starts_with($normalizedConfiguredKey . '/', $normalizedPublic)) {
                throw new RuntimeException('The APNs private key must be stored outside the public document root.');
            }
            $apnsPrivateKeyPath = self::resolveProspectivePath($apnsPrivateKeyPath);
            $normalizedApnsKey = rtrim(str_replace('\\', '/', $apnsPrivateKeyPath), '/');
            if (str_starts_with($normalizedApnsKey . '/', $normalizedPublic)) {
                throw new RuntimeException('The APNs private key must be stored outside the public document root.');
            }
        }

        try {
            $timezone = new DateTimeZone($timezoneName);
        } catch (\Exception) {
            throw new RuntimeException('APP_TIMEZONE is invalid.');
        }

        $config = new self(
            environment: $environment,
            debug: $debug,
            appKey: $appKey,
            appUrl: $appUrl,
            timezone: $timezone,
            corsAllowedOrigins: $cors,
            trustedProxies: Env::csv('TRUSTED_PROXIES'),
            dbConnection: $dbConnection,
            dbHost: Env::get('DB_HOST', 'localhost') ?? 'localhost',
            dbPort: Env::int('DB_PORT', 3306, 1),
            dbName: $dbName,
            dbUser: Env::get('DB_USERNAME', '') ?? '',
            dbPassword: Env::get('DB_PASSWORD', '') ?? '',
            dbSslCa: self::nullable(Env::get('DB_SSL_CA')),
            mediaStoragePath: $mediaStoragePath,
            answerAudioMaxBytes: Env::int('ANSWER_AUDIO_MAX_BYTES', 20 * 1024 * 1024, 1),
            answerPhotoMaxBytes: Env::int('ANSWER_PHOTO_MAX_BYTES', 10 * 1024 * 1024, 1),
            answerPhotoMaxCount: Env::int('ANSWER_PHOTO_MAX_COUNT', 4, 1),
            answerMediaFamilyQuotaBytes: Env::int(
                'ANSWER_MEDIA_FAMILY_QUOTA_BYTES',
                2 * 1024 * 1024 * 1024,
                1,
            ),
            answerMediaUserUploadsPerHour: Env::int('ANSWER_MEDIA_USER_UPLOADS_PER_HOUR', 12, 1),
            answerMediaIpUploadsPerHour: Env::int('ANSWER_MEDIA_IP_UPLOADS_PER_HOUR', 120, 1),
            sessionTtlDays: Env::int('SESSION_TTL_DAYS', 30, 1),
            otpTtlSeconds: Env::int('OTP_TTL_SECONDS', 600, 60),
            otpMaxAttempts: Env::int('OTP_MAX_ATTEMPTS', 5, 1),
            otpPhoneRequestsPerHour: Env::int('OTP_PHONE_REQUESTS_PER_HOUR', 5, 1),
            otpEmailRequestsPerHour: Env::int('OTP_EMAIL_REQUESTS_PER_HOUR', 5, 1),
            otpIpRequestsPerHour: Env::int('OTP_IP_REQUESTS_PER_HOUR', 20, 1),
            otpVerifyAttemptsPerHour: Env::int('OTP_VERIFY_ATTEMPTS_PER_HOUR', 50, 1),
            setupFamilyIpRequestsPerHour: Env::int('SETUP_FAMILY_IP_REQUESTS_PER_HOUR', 5, 1),
            pairingIpAttemptsPerHour: Env::int('PAIRING_IP_ATTEMPTS_PER_HOUR', 60, 1),
            pairingTtlSeconds: Env::int('PAIRING_TTL_SECONDS', 600, 60),
            otpDriver: $otpDriver,
            otpDevExpose: Env::bool('OTP_DEV_EXPOSE', false),
            emailDriver: strtolower(Env::get('EMAIL_DRIVER', 'disabled') ?? 'disabled'),
            emailDevExpose: Env::bool('EMAIL_DEV_EXPOSE', false),
            emailFromAddress: self::nullable(Env::get('EMAIL_FROM_ADDRESS')),
            twilioAccountSid: self::nullable(Env::get('TWILIO_ACCOUNT_SID')),
            twilioAuthToken: self::nullable(Env::get('TWILIO_AUTH_TOKEN')),
            twilioFromNumber: self::nullable(Env::get('TWILIO_FROM_NUMBER')),
            twilioApiBase: rtrim(Env::get('TWILIO_API_BASE', 'https://api.twilio.com') ?? '', '/'),
            pushDriver: strtolower(Env::get('PUSH_DRIVER', 'disabled') ?? 'disabled'),
            apnsTeamId: self::nullable(Env::get('APNS_TEAM_ID')),
            apnsKeyId: self::nullable(Env::get('APNS_KEY_ID')),
            apnsPrivateKeyPath: $apnsPrivateKeyPath,
            apnsTopic: self::nullable(Env::get('APNS_TOPIC')),
        );
        $config->validate();
        return $config;
    }

    public function isProduction(): bool
    {
        return $this->environment === 'production';
    }

    private function validate(): void
    {
        foreach (array_merge(
            [$this->appUrl],
            $this->corsAllowedOrigins,
        ) as $url) {
            if (preg_match('/[\x00-\x1F\x7F]/', $url) === 1) {
                throw new RuntimeException('Configured URLs cannot contain control characters.');
            }
        }
        if (strlen($this->appKey) < 32 || str_starts_with($this->appKey, 'replace-')) {
            throw new RuntimeException('APP_KEY must contain at least 32 random characters.');
        }
        if (!in_array($this->otpDriver, ['twilio', 'log', 'disabled'], true)) {
            throw new RuntimeException('OTP_DRIVER must be twilio, log, or disabled.');
        }
        if (!in_array($this->emailDriver, ['mail', 'log', 'disabled'], true)) {
            throw new RuntimeException('EMAIL_DRIVER must be mail, log, or disabled.');
        }
        if ($this->emailFromAddress !== null) {
            try {
                \Tsutsuura\Server\Auth\EmailAddress::normalize($this->emailFromAddress);
            } catch (\Throwable) {
                throw new RuntimeException('EMAIL_FROM_ADDRESS must be one valid email address without header controls.');
            }
        }
        if ($this->emailDriver === 'mail' && ($this->emailFromAddress === null || !function_exists('mail'))) {
            throw new RuntimeException('EMAIL_DRIVER=mail requires EMAIL_FROM_ADDRESS and the PHP mail function.');
        }
        if (!in_array($this->pushDriver, ['apns', 'log', 'disabled'], true)) {
            throw new RuntimeException('PUSH_DRIVER must be apns, log, or disabled.');
        }
        if (!in_array($this->dbConnection, ['mysql', 'sqlite'], true)) {
            throw new RuntimeException('DB_CONNECTION must be mysql or sqlite.');
        }
        if ($this->dbConnection === 'mysql' && ($this->dbHost === '' || $this->dbUser === '')) {
            throw new RuntimeException('DB_HOST and DB_USERNAME are required for MySQL.');
        }
        if ($this->dbConnection === 'sqlite' && !str_starts_with($this->dbName, DIRECTORY_SEPARATOR)) {
            throw new RuntimeException('The resolved SQLite database path must be absolute.');
        }
        if (!str_starts_with($this->mediaStoragePath, DIRECTORY_SEPARATOR)) {
            throw new RuntimeException('The resolved answer media storage path must be absolute.');
        }
        if ($this->mediaStoragePath === DIRECTORY_SEPARATOR) {
            throw new RuntimeException('Answer media storage path cannot be the filesystem root.');
        }
        if ($this->answerAudioMaxBytes !== 20 * 1024 * 1024 ||
            $this->answerPhotoMaxBytes !== 10 * 1024 * 1024 ||
            $this->answerPhotoMaxCount !== 4) {
            throw new RuntimeException(
                'ANSWER_AUDIO_MAX_BYTES, ANSWER_PHOTO_MAX_BYTES, and ANSWER_PHOTO_MAX_COUNT ' .
                'must match the shipped iOS contract (20 MiB, 10 MiB, and 4).',
            );
        }
        if ($this->sessionTtlDays > 30) {
            throw new RuntimeException(
                'SESSION_TTL_DAYS cannot exceed the shipped iOS replay-retention contract of 30 days.',
            );
        }
        foreach ($this->corsAllowedOrigins as $origin) {
            if ($origin === '*' || filter_var($origin, FILTER_VALIDATE_URL) === false) {
                throw new RuntimeException('CORS_ALLOWED_ORIGINS must contain exact URL origins and cannot use *.');
            }
            $parts = parse_url($origin);
            if (!in_array(strtolower((string) ($parts['scheme'] ?? '')), ['http', 'https'], true) ||
                !isset($parts['host']) ||
                ($parts['path'] ?? '') !== '' || isset($parts['query']) || isset($parts['fragment'])) {
                throw new RuntimeException('CORS_ALLOWED_ORIGINS entries cannot contain paths, queries, or fragments.');
            }
            if ($this->isProduction() && strtolower((string) $parts['scheme']) !== 'https') {
                throw new RuntimeException('Production CORS origins must use HTTPS.');
            }
        }
        if (!str_starts_with($this->twilioApiBase, 'https://')) {
            throw new RuntimeException('TWILIO_API_BASE must use HTTPS.');
        }
        if ($this->pushDriver === 'apns') {
            $this->validateApns();
        }
        if ($this->isProduction()) {
            if ($this->debug || $this->otpDevExpose || $this->otpDriver === 'log' ||
                $this->emailDevExpose || $this->emailDriver === 'log') {
                throw new RuntimeException('Production forbids debug output, exposed OTPs, and log OTP delivery.');
            }
            if ($this->pushDriver === 'log') {
                throw new RuntimeException('Production forbids log push delivery.');
            }
            if (!str_starts_with($this->appUrl, 'https://')) {
                throw new RuntimeException('APP_URL must use HTTPS in production.');
            }
            if ($this->otpDriver === 'twilio') {
                foreach ([$this->twilioAccountSid, $this->twilioAuthToken, $this->twilioFromNumber] as $credential) {
                    if ($credential === null || str_starts_with($credential, 'replace-')) {
                        throw new RuntimeException('Twilio credentials must be configured when OTP_DRIVER=twilio.');
                    }
                }
            }
        }
    }

    private function validateApns(): void
    {
        if (!function_exists('curl_init') || !function_exists('openssl_sign')) {
            throw new RuntimeException('APNs delivery requires the cURL and OpenSSL PHP extensions.');
        }
        $curlVersion = curl_version();
        if (((int) ($curlVersion['features'] ?? 0) & CURL_VERSION_HTTP2) === 0) {
            throw new RuntimeException('APNs delivery requires a cURL build with HTTP/2 support.');
        }
        foreach (
            [
                'APNS_TEAM_ID' => $this->apnsTeamId,
                'APNS_KEY_ID' => $this->apnsKeyId,
                'APNS_PRIVATE_KEY_PATH' => $this->apnsPrivateKeyPath,
                'APNS_TOPIC' => $this->apnsTopic,
            ] as $name => $value
        ) {
            if ($value === null || str_starts_with(strtolower($value), 'replace-')) {
                throw new RuntimeException($name . ' must be configured when PUSH_DRIVER=apns.');
            }
        }
        if (preg_match('/^[A-Z0-9]{10}$/', (string) $this->apnsTeamId) !== 1) {
            throw new RuntimeException('APNS_TEAM_ID must be a 10-character Apple Team ID.');
        }
        if (preg_match('/^[A-Z0-9]{10}$/', (string) $this->apnsKeyId) !== 1) {
            throw new RuntimeException('APNS_KEY_ID must be a 10-character Apple key ID.');
        }
        if (strlen((string) $this->apnsTopic) > 255 ||
            preg_match('/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/', (string) $this->apnsTopic) !== 1) {
            throw new RuntimeException('APNS_TOPIC must be a valid application bundle identifier.');
        }
        $keyPath = (string) $this->apnsPrivateKeyPath;
        if (!is_file($keyPath) || !is_readable($keyPath)) {
            throw new RuntimeException('APNS_PRIVATE_KEY_PATH must reference a readable private-key file.');
        }
        $keySize = filesize($keyPath);
        if ($keySize === false || $keySize < 100 || $keySize > 32 * 1024) {
            throw new RuntimeException('The APNs private-key file has an invalid size.');
        }
        if ($this->isProduction()) {
            $permissions = fileperms($keyPath);
            if ($permissions === false || !in_array($permissions & 0777, [0400, 0440, 0600, 0640], true)) {
                throw new RuntimeException('The APNs private-key file permissions must be 0400, 0440, 0600, or 0640.');
            }
        }
    }

    private static function nullable(?string $value): ?string
    {
        $value = $value === null ? null : trim($value);
        return $value === '' ? null : $value;
    }

    private static function normalizeAbsolutePath(string $path): string
    {
        $parts = [];
        foreach (explode('/', str_replace('\\', '/', $path)) as $part) {
            if ($part === '' || $part === '.') {
                continue;
            }
            if ($part === '..') {
                array_pop($parts);
                continue;
            }
            $parts[] = $part;
        }
        return DIRECTORY_SEPARATOR . implode(DIRECTORY_SEPARATOR, $parts);
    }

    private static function resolveProspectivePath(string $path): string
    {
        $missing = [];
        $cursor = $path;
        while (!file_exists($cursor) && !is_link($cursor)) {
            $parent = dirname($cursor);
            if ($parent === $cursor) {
                return $path;
            }
            array_unshift($missing, basename($cursor));
            $cursor = $parent;
        }
        $resolved = realpath($cursor);
        if ($resolved === false) {
            return $path;
        }
        return self::normalizeAbsolutePath(
            rtrim($resolved, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR .
            implode(DIRECTORY_SEPARATOR, $missing),
        );
    }
}
