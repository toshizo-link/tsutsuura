<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use RuntimeException;
use Tsutsuura\Server\Config;

final class TwilioSmsSender implements SmsSender
{
    public function __construct(private readonly Config $config)
    {
    }

    public function sendOtp(string $phone, string $code): void
    {
        $sid = $this->config->twilioAccountSid;
        $token = $this->config->twilioAuthToken;
        $from = $this->config->twilioFromNumber;
        if ($sid === null || $token === null || $from === null) {
            throw new RuntimeException('Twilio is not configured.');
        }

        $url = sprintf(
            '%s/2010-04-01/Accounts/%s/Messages.json',
            $this->config->twilioApiBase,
            rawurlencode($sid),
        );
        $handle = curl_init($url);
        if ($handle === false) {
            throw new RuntimeException('Unable to initialize SMS delivery.');
        }
        curl_setopt_array($handle, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query([
                'To' => $phone,
                'From' => $from,
                'Body' => "つつうらの認証コードは {$code} です。10分以内に入力してください。",
            ], '', '&', PHP_QUERY_RFC3986),
            CURLOPT_USERPWD => $sid . ':' . $token,
            CURLOPT_HTTPAUTH => CURLAUTH_BASIC,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT => 12,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);
        $response = curl_exec($handle);
        $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        $error = curl_error($handle);
        curl_close($handle);
        if ($response === false || $status < 200 || $status >= 300) {
            error_log(sprintf('Twilio SMS failed (HTTP %d): %s', $status, $error));
            throw new RuntimeException('SMS delivery failed.');
        }
    }
}

