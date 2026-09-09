<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Push;

final class DeterministicPushProvider implements PushProvider
{
    /** @var list<array<string, mixed>> */
    public array $deliveries = [];

    public function __construct(
        private readonly bool $accept = true,
        private readonly bool $invalidToken = false,
    ) {
    }

    public function send(string $deviceToken, string $environment, array $payload): array
    {
        $providerId = 'deterministic-' . (count($this->deliveries) + 1);
        $this->deliveries[] = [
            'token' => $deviceToken,
            'environment' => $environment,
            'payload' => $payload,
            'providerId' => $providerId,
        ];
        return [
            'accepted' => $this->accept && !$this->invalidToken,
            'providerId' => $this->accept && !$this->invalidToken ? $providerId : null,
            'invalidToken' => $this->invalidToken,
        ];
    }
}
