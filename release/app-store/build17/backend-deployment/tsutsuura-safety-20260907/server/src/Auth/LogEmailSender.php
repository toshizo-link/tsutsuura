<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use RuntimeException;
use Tsutsuura\Server\Config;

final class LogEmailSender implements EmailSender
{
    public function __construct(private readonly Config $config)
    {
        if ($config->isProduction()) {
            throw new RuntimeException('Production forbids logging email verification codes.');
        }
    }

    public function sendOtp(string $email, string $code): void
    {
        error_log(sprintf('[development email OTP] %s: %s', EmailAddress::normalize($email), $code));
    }
}
