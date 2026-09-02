<?php
declare(strict_types=1);

use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Push\ApnsPushProvider;
use Tsutsuura\Server\Push\EventNotificationWorker;
use Tsutsuura\Server\Push\LogPushProvider;
use Tsutsuura\Server\Push\PushDeliveryService;
use Tsutsuura\Server\Security\Crypto;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$options = getopt('', ['limit::']);
$limitValue = $options['limit'] ?? '100';
if (!is_string($limitValue) || preg_match('/^[1-9][0-9]{0,3}$/', $limitValue) !== 1 ||
    (int) $limitValue > 1000) {
    fwrite(STDERR, "--limit must be between 1 and 1000.\n");
    exit(2);
}

$base = dirname(__DIR__);
try {
    $config = Config::fromEnvironment($base);
    $provider = match ($config->pushDriver) {
        'apns' => new ApnsPushProvider(
            (string) $config->apnsTeamId,
            (string) $config->apnsKeyId,
            (string) $config->apnsPrivateKeyPath,
            (string) $config->apnsTopic,
        ),
        'log' => $config->isProduction()
            ? throw new RuntimeException('Log push delivery is forbidden in production.')
            : new LogPushProvider(),
        'disabled' => null,
        default => throw new RuntimeException('Push delivery provider is invalid.'),
    };
} catch (RuntimeException $exception) {
    fwrite(STDERR, 'Push configuration error: ' . $exception->getMessage() . PHP_EOL);
    exit(3);
}
if ($provider === null) {
    fwrite(STDERR, "Push delivery is disabled. Configure PUSH_DRIVER=apns and APNs credentials.\n");
    exit(3);
}

$database = new Database($config);
$worker = new EventNotificationWorker(
    $database,
    new PushDeliveryService(
        $database,
        new Crypto($config->appKey),
        $config,
        $provider,
    ),
);
$summary = $worker->run((int) $limitValue);
fwrite(STDOUT, json_encode(
    $summary,
    JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
) . PHP_EOL);
