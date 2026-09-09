<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Http;

final class Router
{
    /** @var list<array{string, string, callable}> */
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler): void
    {
        $regex = preg_replace_callback(
            '/\{([A-Za-z][A-Za-z0-9_]*)\}/',
            static fn (array $match): string => '(?P<' . $match[1] . '>[A-Za-z0-9_-]+)',
            $pattern,
        );
        $this->routes[] = [strtoupper($method), '#^' . $regex . '$#D', $handler];
    }

    public function dispatch(Request $request): mixed
    {
        $allowed = [];
        foreach ($this->routes as [$method, $regex, $handler]) {
            if (preg_match($regex, $request->path, $matches) !== 1) {
                continue;
            }
            if ($method !== $request->method) {
                $allowed[] = $method;
                continue;
            }
            $parameters = array_filter($matches, 'is_string', ARRAY_FILTER_USE_KEY);
            return $handler($request, $parameters);
        }
        if ($allowed !== []) {
            header('Allow: ' . implode(', ', array_unique($allowed)));
            throw new ApiException(405, 'method_not_allowed', 'Method is not allowed for this endpoint.');
        }
        throw new ApiException(404, 'not_found', 'Endpoint not found.');
    }
}

