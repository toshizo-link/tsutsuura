<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use RuntimeException;

final class DisabledEmailSender implements EmailSender
{
    public function sendOtp(string $email, string $code): void
    {
        throw new RuntimeException('Email authentication is disabled.');
    }
}
