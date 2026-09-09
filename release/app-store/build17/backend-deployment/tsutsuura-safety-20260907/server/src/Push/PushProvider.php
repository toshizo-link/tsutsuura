<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

interface PushProvider
{
    /**
     * @param array<string, mixed> $payload
     * @return array{accepted: bool, providerId: ?string, invalidToken: bool}
     */
    public function send(string $deviceToken, string $environment, array $payload): array;
}
