<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use Tsutsuura\Server\Http\ApiException;

final class EmailAddress
{
    public static function normalize(mixed $value): string
    {
        // Deliberately accept one ordinary ASCII mailbox, never display names,
        // address lists or header controls. Full-width keyboard input is folded.
        if (!is_string($value) || preg_match('/[\x00-\x1F\x7F]/', $value) === 1) {
            throw new ApiException(422, 'invalid_email', 'Enter one valid email address.');
        }
        $email = strtolower(trim(mb_convert_kana($value, 'as', 'UTF-8')));
        if (strlen($email) > 254 || filter_var($email, FILTER_VALIDATE_EMAIL) === false ||
            preg_match('/\A[A-Za-z0-9.!#$%&\x27*+\/=?^_`{|}~-]+@[A-Za-z0-9.-]+\z/D', $email) !== 1) {
            throw new ApiException(422, 'invalid_email', 'Enter one valid email address.');
        }
        $domain = substr($email, (int) strrpos($email, '@') + 1);
        $labels = explode('.', $domain);
        if (count($labels) < 2 || preg_match('/[a-z]/', $labels[count($labels) - 1]) !== 1) {
            throw new ApiException(422, 'invalid_email', 'Enter one valid email address.');
        }
        return $email;
    }
}
