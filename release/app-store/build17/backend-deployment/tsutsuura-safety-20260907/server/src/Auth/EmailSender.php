<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

interface EmailSender
{
    public function sendOtp(string $email, string $code): void;
}
