<?php
declare(strict_types=1);

use Tsutsuura\Server\App\ModerationService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;

require dirname(__DIR__) . '/src/Autoload.php';
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
$options = getopt('', ['list', 'show', 'review', 'type:', 'id:', 'decision:', 'operator:', 'note:', 'limit:']);
try {
    $modes = array_intersect(['list', 'show', 'review'], array_keys($options));
    if (count($modes) !== 1) {
        throw new RuntimeException("Choose --list [--limit=50], --show --type=answer|comment --id=N, or --review --type=answer|comment --id=N --decision=remove|dismiss --operator=NAME --note=REASON.\nThe show command includes private reported content/media storage keys for authorized operator review.");
    }
    $config = Config::fromEnvironment(dirname(__DIR__));
    $service = new ModerationService(new Database($config));
    if (isset($options['list'])) {
        $result = $service->pending((int) ($options['limit'] ?? 50));
    } else {
        $type = (string) ($options['type'] ?? '');
        $id = (string) ($options['id'] ?? '');
        if (preg_match('/^[1-9][0-9]{0,18}$/', $id) !== 1 || (string) (int) $id !== $id) { throw new RuntimeException('Invalid report id.'); }
        $result = isset($options['show']) ? $service->show($type, (int) $id)
            : $service->review($type, (int) $id, (string) ($options['decision'] ?? ''),
                (string) ($options['operator'] ?? ''), (string) ($options['note'] ?? ''));
    }
    echo json_encode($result, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT), PHP_EOL;
} catch (Throwable $error) {
    fwrite(STDERR, $error->getMessage() . PHP_EOL);
    exit(1);
}
