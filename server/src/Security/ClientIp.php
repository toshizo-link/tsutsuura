<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Security;

use Tsutsuura\Server\Config;
use Tsutsuura\Server\Http\Request;

final class ClientIp
{
    public static function resolve(Request $request, Config $config): string
    {
        $remote = filter_var($request->remoteAddress, FILTER_VALIDATE_IP) !== false
            ? $request->remoteAddress
            : '0.0.0.0';
        if (!in_array($remote, $config->trustedProxies, true)) {
            return $remote;
        }

        $forwarded = $request->header('x-forwarded-for');
        if ($forwarded === null) {
            return $remote;
        }
        foreach (array_map('trim', explode(',', $forwarded)) as $candidate) {
            if (filter_var($candidate, FILTER_VALIDATE_IP) !== false) {
                return $candidate;
            }
        }
        return $remote;
    }
}

