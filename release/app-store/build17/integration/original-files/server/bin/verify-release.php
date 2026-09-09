<?php
declare(strict_types=1);

// Read-only release verification: an old server can have a healthy database
// while missing the routes required by the installed iOS client.
$baseURL = rtrim((string) ($argv[1] ?? ''), '/');
$parts = parse_url($baseURL);
if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' ||
    !isset($parts['host']) || isset($parts['user']) || isset($parts['pass']) ||
    isset($parts['query']) || isset($parts['fragment'])) {
    fwrite(STDERR, "Usage: php bin/verify-release.php https://host/api-base\n");
    exit(2);
}
try {
    [$status, $response] = probe($baseURL . '/v1/health');
    if ($status !== 200 || ($response['data']['apiRevision'] ?? null) !== '2026-09-05-email') {
        throw new RuntimeException('The expected 2026-09-05-email API release is not healthy or not deployed.');
    }
    $health = $response['data'];
    foreach (['familySetup', 'answerMedia', 'accountRecovery', 'accountExport', 'notificationPreferences', 'scheduledQuestions', 'immutableAnswers', 'profileMarks', 'emailAuthentication'] as $capability) {
        if (($health['capabilities'][$capability] ?? false) !== true) {
            throw new RuntimeException('Required API capability is unavailable: ' . $capability);
        }
    }
    foreach ([
        '/v1/me/export' => 401,
        '/v1/me/notification-preferences' => 401,
        '/v1/me/recovery-codes' => 405,
        '/v1/me/email/request' => 405,
    ] as $path => $expectedStatus) {
        [$status] = probe($baseURL . $path);
        if ($status !== $expectedStatus) {
            throw new RuntimeException('Release route check failed: GET ' . $path . ' returned ' . $status . '.');
        }
    }
    foreach (['PATCH' => '/v1/me', 'PUT' => '/v1/push-tokens', 'DELETE' => '/v1/me'] as $method => $path) {
        [$status, $response] = probe($baseURL . $path, 'POST', $method);
        if ($status !== 401 || ($response['error']['code'] ?? null) !== 'authentication_required') {
            throw new RuntimeException('POST transport check failed for ' . $method . ' ' . $path . '.');
        }
    }
    echo "API revision, capabilities, and lifecycle routes verified.\n";
    echo "Authenticated mutation routes are reachable through POST transport.\n";
    echo 'Email enrollment: ' . (($health['authProviders']['email'] ?? false) ? 'enabled (host mail delivery still requires a mailbox check)' : 'disabled (configure EMAIL_DRIVER=mail and EMAIL_FROM_ADDRESS)') . ".\n";
} catch (Throwable $exception) {
    fwrite(STDERR, $exception->getMessage() . "\n");
    exit(1);
}

/** @return array{int, array<string, mixed>} */
function probe(string $url, string $method = 'GET', ?string $override = null): array
{
    $curl = curl_init($url);
    $headers = ['Accept: application/json'];
    if ($override !== null) { $headers[] = 'X-HTTP-Method-Override: ' . $override; }
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20,
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
    ]);
    $body = curl_exec($curl);
    if (!is_string($body)) {
        throw new RuntimeException('Release endpoint could not be reached.');
    }
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $json = json_decode($body, true, 64, JSON_THROW_ON_ERROR);
    if (!is_array($json)) {
        throw new RuntimeException('Release endpoint did not return a JSON object.');
    }
    return [$status, $json];
}
