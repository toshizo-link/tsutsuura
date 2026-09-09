<?php
declare(strict_types=1);

namespace Tsutsuura\Server;

use RuntimeException;

final class Env
{
    /** @var array<string, string> */
    private static array $fileValues = [];

    public static function load(string $path): void
    {
        if (!is_file($path)) {
            return;
        }

        $lines = file($path, FILE_IGNORE_NEW_LINES);
        if ($lines === false) {
            throw new RuntimeException('Unable to read environment file.');
        }

        foreach ($lines as $lineNumber => $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            if (str_starts_with($line, 'export ')) {
                $line = trim(substr($line, 7));
            }

            $separator = strpos($line, '=');
            if ($separator === false) {
                throw new RuntimeException(sprintf('Invalid .env syntax on line %d.', $lineNumber + 1));
            }

            $key = trim(substr($line, 0, $separator));
            $value = trim(substr($line, $separator + 1));
            if (preg_match('/^[A-Z][A-Z0-9_]*$/', $key) !== 1) {
                throw new RuntimeException(sprintf('Invalid .env key on line %d.', $lineNumber + 1));
            }

            if (strlen($value) >= 2 && (($value[0] === '"' && str_ends_with($value, '"')) ||
                    ($value[0] === "'" && str_ends_with($value, "'")))) {
                $quote = $value[0];
                $value = substr($value, 1, -1);
                if ($quote === '"') {
                    $value = strtr($value, ['\\n' => "\n", '\\r' => "\r", '\\t' => "\t", '\\"' => '"', '\\\\' => '\\']);
                }
            } else {
                $comment = preg_split('/\s+#/', $value, 2);
                $value = $comment === false ? $value : $comment[0];
            }

            if (getenv($key) === false && !array_key_exists($key, $_ENV)) {
                self::$fileValues[$key] = $value;
            }
        }
    }

    public static function get(string $key, ?string $default = null): ?string
    {
        $value = getenv($key);
        if ($value !== false) {
            return $value;
        }
        if (array_key_exists($key, $_ENV)) {
            return (string) $_ENV[$key];
        }
        return self::$fileValues[$key] ?? $default;
    }

    public static function require(string $key): string
    {
        $value = self::get($key);
        if ($value === null || trim($value) === '') {
            throw new RuntimeException(sprintf('Required environment variable %s is missing.', $key));
        }
        return $value;
    }

    public static function bool(string $key, bool $default = false): bool
    {
        $raw = self::get($key);
        if ($raw === null) {
            return $default;
        }
        $value = filter_var($raw, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
        if ($value === null) {
            throw new RuntimeException(sprintf('%s must be true or false.', $key));
        }
        return $value;
    }

    public static function int(string $key, int $default, int $minimum = 0): int
    {
        $raw = self::get($key);
        if ($raw === null) {
            return $default;
        }
        $value = filter_var($raw, FILTER_VALIDATE_INT);
        if ($value === false || $value < $minimum) {
            throw new RuntimeException(sprintf('%s must be an integer >= %d.', $key, $minimum));
        }
        return $value;
    }

    /** @return list<string> */
    public static function csv(string $key): array
    {
        $raw = self::get($key, '') ?? '';
        return array_values(array_filter(array_map('trim', explode(',', $raw)), static fn (string $v): bool => $v !== ''));
    }
}

