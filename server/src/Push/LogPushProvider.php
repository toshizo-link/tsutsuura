<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

final class LogPushProvider implements PushProvider
{
    public function send(string $deviceToken, string $environment, array $payload): array
    {
        $providerId = 'log-' . bin2hex(random_bytes(8));
        error_log(json_encode([
            'type' => 'push_stub',
            'providerId' => $providerId,
            'tokenSha256' => hash('sha256', $deviceToken),
            'environment' => $environment,
            'payload' => $payload,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        return ['accepted' => true, 'providerId' => $providerId, 'invalidToken' => false];
    }
}
