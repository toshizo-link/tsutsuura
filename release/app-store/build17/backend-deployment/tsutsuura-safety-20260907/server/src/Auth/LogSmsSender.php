<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

final class LogSmsSender implements SmsSender
{
    public function sendOtp(string $phone, string $code): void
    {
        error_log(sprintf('[development OTP] %s: %s', $phone, $code));
    }
}

