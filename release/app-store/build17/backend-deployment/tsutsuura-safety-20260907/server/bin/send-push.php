<?php
declare(strict_types=1);

use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Push\ApnsPushProvider;
use Tsutsuura\Server\Push\LogPushProvider;
use Tsutsuura\Server\Push\PushProvider;
use Tsutsuura\Server\Push\PushDeliveryService;
use Tsutsuura\Server\Security\Crypto;

require dirname(__DIR__) . '/src/Autoload.php';

$options = getopt('', ['user:', 'category:', 'title:', 'body:', 'data::']);
$userValue = $options['user'] ?? null;
if (!is_string($userValue) || preg_match('/^[1-9][0-9]{0,18}$/', $userValue) !== 1) {
    fwrite(STDERR, "--user must be a positive user id.\n");
    exit(2);
}
foreach (['category', 'title', 'body'] as $required) {
    if (!isset($options[$required]) || !is_string($options[$required]) || $options[$required] === '') {
        fwrite(STDERR, '--' . $required . " is required.\n");
        exit(2);
    }
}

$data = [];
if (isset($options['data'])) {
    try {
        $decoded = json_decode((string) $options['data'], true, 32, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fwrite(STDERR, "--data must be a JSON object.\n");
        exit(2);
    }
    if (!is_array($decoded) || array_is_list($decoded)) {
        fwrite(STDERR, "--data must be a JSON object.\n");
        exit(2);
    }
    $data = $decoded;
}

$base = dirname(__DIR__);
try {
    $config = Config::fromEnvironment($base);
    $provider = match ($config->pushDriver) {
        'apns' => apnsProvider($config),
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
$delivery = new PushDeliveryService(
    $database,
    new Crypto($config->appKey),
    $config,
    $provider,
);
$result = $delivery->deliverToUser(
    (int) $userValue,
    (string) $options['category'],
    $options['title'],
    $options['body'],
    $data,
);
fwrite(STDOUT, json_encode($result, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES) . PHP_EOL);

function apnsProvider(Config $config): PushProvider
{
    if ($config->apnsTeamId === null || $config->apnsKeyId === null ||
        $config->apnsPrivateKeyPath === null || $config->apnsTopic === null) {
        throw new RuntimeException('APNs push delivery is not fully configured.');
    }
    return new ApnsPushProvider(
        $config->apnsTeamId,
        $config->apnsKeyId,
        $config->apnsPrivateKeyPath,
        $config->apnsTopic,
    );
}
