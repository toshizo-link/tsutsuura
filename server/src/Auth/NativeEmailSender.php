<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Auth;

use Closure;
use RuntimeException;
use Tsutsuura\Server\Config;

final class NativeEmailSender implements EmailSender
{
    private readonly Closure $send;

    public function __construct(private readonly Config $config, ?Closure $transport = null)
    {
        // Injection is only for local tests; production uses PHP's configured
        // host mail service. No SDK, credentials or shell parameters are used.
        $this->send = $transport ?? static fn (string $to, string $subject, string $body, array $headers): bool =>
            @mail($to, $subject, $body, $headers);
    }

    public function sendOtp(string $email, string $code): void
    {
        $email = EmailAddress::normalize($email);
        if ($this->config->emailFromAddress === null || preg_match('/\A[0-9]{6}\z/D', $code) !== 1) {
            throw new RuntimeException('Email delivery is not configured correctly.');
        }
        $from = EmailAddress::normalize($this->config->emailFromAddress);
        $minutes = (int) ceil($this->config->otpTtlSeconds / 60);
        $message = "津々浦々の確認番号です。\r\n\r\n{$code}\r\n\r\n" .
            "アプリに戻って、この6桁の番号を入力してください。\r\n" .
            "有効期限は{$minutes}分です。番号は人に教えないでください。\r\n\r\n" .
            "心当たりがない場合は、このメールを削除してください。\r\n";
        $accepted = ($this->send)(
            $email,
            '=?UTF-8?B?' . base64_encode('津々浦々の確認番号') . '?=',
            chunk_split(base64_encode($message), 68, "\r\n"),
            [
                'From' => '=?UTF-8?B?' . base64_encode('津々浦々') . '?= <' . $from . '>',
                'MIME-Version' => '1.0',
                'Content-Type' => 'text/plain; charset=UTF-8',
                'Content-Transfer-Encoding' => 'base64',
                'Auto-Submitted' => 'auto-generated',
            ],
        );
        if ($accepted !== true) {
            throw new RuntimeException('The host mail service did not accept the verification email.');
        }
    }
}
