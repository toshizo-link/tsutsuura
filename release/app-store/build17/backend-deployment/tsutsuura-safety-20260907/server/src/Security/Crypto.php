<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Security;

use RuntimeException;

final class Crypto
{
    private readonly string $encryptionKey;

    public function __construct(private readonly string $appKey)
    {
        $this->encryptionKey = hash('sha256', $appKey, true);
    }

    public function randomToken(int $bytes = 32): string
    {
        return self::base64UrlEncode(random_bytes($bytes));
    }

    public function hashOpaque(string $value): string
    {
        return hash_hmac('sha256', $value, $this->appKey);
    }

    public function otpHash(string $requestId, string $code): string
    {
        return hash_hmac('sha256', "otp\0" . $requestId . "\0" . $code, $this->appKey);
    }

    public function encrypt(string $plaintext): string
    {
        $iv = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt(
            $plaintext,
            'aes-256-gcm',
            $this->encryptionKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            '',
            16,
        );
        if ($ciphertext === false) {
            throw new RuntimeException('Encryption failed.');
        }
        return self::base64UrlEncode($iv . $tag . $ciphertext);
    }

    public function decrypt(string $payload): string
    {
        $raw = self::base64UrlDecode($payload);
        if (strlen($raw) < 29) {
            throw new RuntimeException('Encrypted payload is invalid.');
        }
        $plaintext = openssl_decrypt(
            substr($raw, 28),
            'aes-256-gcm',
            $this->encryptionKey,
            OPENSSL_RAW_DATA,
            substr($raw, 0, 12),
            substr($raw, 12, 16),
        );
        if ($plaintext === false) {
            throw new RuntimeException('Encrypted payload authentication failed.');
        }
        return $plaintext;
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $value): string
    {
        $decoded = base64_decode(strtr($value, '-_', '+/'), true);
        if ($decoded === false) {
            throw new RuntimeException('Base64url value is invalid.');
        }
        return $decoded;
    }
}

