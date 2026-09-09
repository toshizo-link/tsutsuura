<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

interface SmsSender
{
    public function sendOtp(string $phone, string $code): void;
}

