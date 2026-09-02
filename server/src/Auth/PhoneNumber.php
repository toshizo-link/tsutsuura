<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use Tsutsuura\Server\Http\ApiException;

final class PhoneNumber
{
    public static function normalize(mixed $value, string $defaultCountryCode = '81'): string
    {
        if (!is_string($value)) {
            throw new ApiException(422, 'invalid_phone', 'phone must be a string.');
        }
        $phone = preg_replace('/[\s\-().]/u', '', trim($value));
        if ($phone === null || $phone === '') {
            throw new ApiException(422, 'invalid_phone', 'Enter a valid phone number.');
        }
        if (str_starts_with($phone, '00')) {
            $phone = '+' . substr($phone, 2);
        } elseif (str_starts_with($phone, '0')) {
            $phone = '+' . $defaultCountryCode . substr($phone, 1);
        }
        if (preg_match('/^\+[1-9][0-9]{7,14}$/', $phone) !== 1) {
            throw new ApiException(422, 'invalid_phone', 'Enter a valid phone number in international format.');
        }
        return $phone;
    }
}

