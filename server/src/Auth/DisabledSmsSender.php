<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use RuntimeException;

final class DisabledSmsSender implements SmsSender
{
    public function sendOtp(string $phone, string $code): void
    {
        throw new RuntimeException('SMS authentication is disabled.');
    }
}

