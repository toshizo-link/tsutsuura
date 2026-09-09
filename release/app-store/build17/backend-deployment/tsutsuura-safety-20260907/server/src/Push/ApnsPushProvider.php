<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

use JsonException;
use OpenSSLAsymmetricKey;
use RuntimeException;

final class ApnsPushProvider implements PushProvider
{
    private const PRODUCTION_HOST = 'https://api.push.apple.com';
    private const SANDBOX_HOST = 'https://api.sandbox.push.apple.com';
    private const JWT_REFRESH_SECONDS = 50 * 60;
    private const MAX_PAYLOAD_BYTES = 4096;

    private readonly OpenSSLAsymmetricKey $privateKey;
    private ?string $providerToken = null;
    private int $providerTokenIssuedAt = 0;

    public function __construct(
        private readonly string $teamId,
        private readonly string $keyId,
        string $privateKeyPath,
        private readonly string $topic,
    ) {
        if (preg_match('/^[A-Z0-9]{10}$/', $this->teamId) !== 1 ||
            preg_match('/^[A-Z0-9]{10}$/', $this->keyId) !== 1 ||
            strlen($this->topic) > 255 ||
            preg_match('/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/', $this->topic) !== 1) {
            throw new RuntimeException('The APNs provider identifiers are invalid.');
        }
        $keySize = is_file($privateKeyPath) ? filesize($privateKeyPath) : false;
        if ($keySize === false || $keySize < 100 || $keySize > 32 * 1024) {
            throw new RuntimeException('Unable to load the APNs private key.');
        }
        $pem = @file_get_contents($privateKeyPath);
        if ($pem === false) {
            throw new RuntimeException('Unable to load the APNs private key.');
        }
        $privateKey = openssl_pkey_get_private($pem);
        unset($pem);
        if (!$privateKey instanceof OpenSSLAsymmetricKey) {
            throw new RuntimeException('The APNs private key is invalid.');
        }
        $details = openssl_pkey_get_details($privateKey);
        $curve = is_array($details) ? ($details['ec']['curve_name'] ?? null) : null;
        if (!is_array($details) || ($details['type'] ?? null) !== OPENSSL_KEYTYPE_EC ||
            ($details['bits'] ?? null) !== 256 || !in_array($curve, ['prime256v1', 'secp256r1'], true)) {
            throw new RuntimeException('The APNs private key must be an ES256 key.');
        }
        $this->privateKey = $privateKey;
    }

    public function send(string $deviceToken, string $environment, array $payload): array
    {
        if (preg_match('/^[A-Fa-f0-9]{32,256}$/', $deviceToken) !== 1 || strlen($deviceToken) % 2 !== 0) {
            return ['accepted' => false, 'providerId' => null, 'invalidToken' => true];
        }
        $host = match ($environment) {
            'production' => self::PRODUCTION_HOST,
            'sandbox' => self::SANDBOX_HOST,
            default => throw new RuntimeException('Stored push environment is invalid.'),
        };
        $body = json_encode(
            $payload,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        );
        if (strlen($body) > self::MAX_PAYLOAD_BYTES) {
            throw new RuntimeException('The APNs payload exceeds 4096 bytes.');
        }

        $responseHeaders = [];
        $handle = curl_init($host . '/3/device/' . rawurlencode($deviceToken));
        if ($handle === false) {
            throw new RuntimeException('Unable to initialize APNs delivery.');
        }
        curl_setopt_array($handle, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => [
                'authorization: bearer ' . $this->providerToken(),
                'apns-topic: ' . $this->topic,
                'apns-push-type: alert',
                'apns-priority: 10',
                'content-type: application/json',
            ],
            CURLOPT_HEADERFUNCTION => static function ($unused, string $line) use (&$responseHeaders): int {
                $separator = strpos($line, ':');
                if ($separator !== false) {
                    $name = strtolower(trim(substr($line, 0, $separator)));
                    $responseHeaders[$name] = trim(substr($line, $separator + 1));
                }
                return strlen($line);
            },
        ]);
        $response = curl_exec($handle);
        $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        $curlError = curl_errno($handle);
        curl_close($handle);
        if ($response === false) {
            throw new RuntimeException(sprintf('APNs transport failed (cURL error %d).', $curlError));
        }

        $providerId = isset($responseHeaders['apns-id']) && $responseHeaders['apns-id'] !== ''
            ? substr($responseHeaders['apns-id'], 0, 128)
            : null;
        if ($status === 200) {
            return ['accepted' => true, 'providerId' => $providerId, 'invalidToken' => false];
        }
        $reason = null;
        if ($response !== '') {
            try {
                $decoded = json_decode($response, true, 8, JSON_THROW_ON_ERROR);
                $reason = is_array($decoded) && is_string($decoded['reason'] ?? null)
                    ? $decoded['reason']
                    : null;
            } catch (JsonException) {
                // APNs failures normally contain JSON; status still determines rejection.
            }
        }
        $invalidToken = $status === 410 || in_array(
            $reason,
            ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'],
            true,
        );
        error_log(sprintf(
            'APNs rejected push (HTTP %d%s).',
            $status,
            $reason === null ? '' : ', reason ' . preg_replace('/[^A-Za-z0-9_-]/', '', $reason),
        ));
        return ['accepted' => false, 'providerId' => $providerId, 'invalidToken' => $invalidToken];
    }

    private function providerToken(): string
    {
        $now = time();
        if ($this->providerToken !== null && $now - $this->providerTokenIssuedAt < self::JWT_REFRESH_SECONDS) {
            return $this->providerToken;
        }
        $header = self::base64Url(json_encode(
            ['alg' => 'ES256', 'kid' => $this->keyId],
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES,
        ));
        $claims = self::base64Url(json_encode(
            ['iss' => $this->teamId, 'iat' => $now],
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES,
        ));
        $signingInput = $header . '.' . $claims;
        if (!openssl_sign($signingInput, $derSignature, $this->privateKey, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('Unable to sign the APNs provider token.');
        }
        $this->providerToken = $signingInput . '.' . self::base64Url(self::derToJose($derSignature));
        $this->providerTokenIssuedAt = $now;
        return $this->providerToken;
    }

    private static function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private static function derToJose(string $der): string
    {
        $offset = 0;
        if (self::readByte($der, $offset) !== 0x30) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        $sequenceLength = self::readLength($der, $offset);
        $sequenceEnd = $offset + $sequenceLength;
        if ($sequenceEnd !== strlen($der)) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        $r = self::readInteger($der, $offset);
        $s = self::readInteger($der, $offset);
        if ($offset !== $sequenceEnd) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        return self::normalizeInteger($r) . self::normalizeInteger($s);
    }

    private static function readInteger(string $der, int &$offset): string
    {
        if (self::readByte($der, $offset) !== 0x02) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        $length = self::readLength($der, $offset);
        if ($length < 1 || $offset + $length > strlen($der)) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        $value = substr($der, $offset, $length);
        $offset += $length;
        return $value;
    }

    private static function normalizeInteger(string $value): string
    {
        $value = ltrim($value, "\0");
        if ($value === '' || strlen($value) > 32) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        return str_pad($value, 32, "\0", STR_PAD_LEFT);
    }

    private static function readLength(string $der, int &$offset): int
    {
        $length = self::readByte($der, $offset);
        if (($length & 0x80) === 0) {
            return $length;
        }
        $bytes = $length & 0x7f;
        if ($bytes < 1 || $bytes > 2 || $offset + $bytes > strlen($der)) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        $length = 0;
        for ($index = 0; $index < $bytes; $index++) {
            $length = ($length << 8) | self::readByte($der, $offset);
        }
        return $length;
    }

    private static function readByte(string $der, int &$offset): int
    {
        if ($offset >= strlen($der)) {
            throw new RuntimeException('APNs signing returned an invalid signature.');
        }
        return ord($der[$offset++]);
    }
}
