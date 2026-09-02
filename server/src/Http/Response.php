<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Http;

use RuntimeException;

final class Response
{
    /** @param array<string, mixed> $payload */
    public static function json(array $payload, int $status = 200, array $headers = []): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        foreach ($headers as $name => $value) {
            header($name . ': ' . $value);
        }
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        exit;
    }

    public static function redirect(string $url, int $status = 302): never
    {
        http_response_code($status);
        header('Location: ' . $url);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'Redirecting…';
        exit;
    }

    public static function html(string $content, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: text/html; charset=utf-8');
        echo $content;
        exit;
    }

    public static function empty(int $status = 204): never
    {
        http_response_code($status);
        exit;
    }

    public static function file(
        string $path,
        string $mimeType,
        int $byteCount,
        ?string $fileName,
        ?string $range,
        bool $headOnly = false,
    ): never {
        $stream = @fopen($path, 'rb');
        if ($stream === false) {
            throw new RuntimeException('Media file could not be opened.');
        }
        $start = 0;
        $end = $byteCount - 1;
        $status = 200;
        if ($range !== null && $range !== '') {
            if (preg_match('/^bytes=([0-9]*)-([0-9]*)$/', trim($range), $matches) !== 1 ||
                ($matches[1] === '' && $matches[2] === '')) {
                fclose($stream);
                self::rangeNotSatisfiable($byteCount);
            }
            if ($matches[1] === '') {
                $suffix = (int) $matches[2];
                if ($suffix < 1) {
                    fclose($stream);
                    self::rangeNotSatisfiable($byteCount);
                }
                $start = max(0, $byteCount - $suffix);
            } else {
                $start = (int) $matches[1];
                if ($matches[2] !== '') {
                    $end = min($end, (int) $matches[2]);
                }
            }
            if ($start >= $byteCount || $end < $start) {
                fclose($stream);
                self::rangeNotSatisfiable($byteCount);
            }
            $status = 206;
        }
        $length = $end - $start + 1;
        if ($start > 0 && fseek($stream, $start) !== 0) {
            fclose($stream);
            throw new RuntimeException('Media file could not be read.');
        }

        http_response_code($status);
        header('Content-Type: ' . $mimeType);
        header('Content-Length: ' . (string) $length);
        header('Accept-Ranges: bytes');
        header('Cache-Control: private, no-store, max-age=0');
        if ($status === 206) {
            header(sprintf('Content-Range: bytes %d-%d/%d', $start, $end, $byteCount));
        }
        if ($fileName !== null && $fileName !== '') {
            header("Content-Disposition: inline; filename*=UTF-8''" . rawurlencode($fileName));
        }
        if ($headOnly) {
            fclose($stream);
            exit;
        }
        $remaining = $length;
        while ($remaining > 0 && !feof($stream)) {
            $chunk = fread($stream, min(65_536, $remaining));
            if ($chunk === false || $chunk === '') {
                fclose($stream);
                exit;
            }
            echo $chunk;
            $remaining -= strlen($chunk);
        }
        fclose($stream);
        exit;
    }

    private static function rangeNotSatisfiable(int $byteCount): never
    {
        http_response_code(416);
        header('Content-Range: bytes */' . (string) $byteCount);
        header('Content-Length: 0');
        header('Cache-Control: private, no-store, max-age=0');
        exit;
    }
}
