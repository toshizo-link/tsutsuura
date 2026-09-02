<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Http;

final class Request
{
    /** @param array<string, string> $headers */
    private function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $query,
        private readonly array $headers,
        private readonly string $rawBody,
        private readonly array $formFields,
        private readonly array $uploadedFiles,
        public readonly int $contentLength,
        public readonly string $remoteAddress,
        public readonly string $requestId,
    ) {
    }

    public static function fromGlobals(): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = rawurldecode((string) (parse_url($uri, PHP_URL_PATH) ?? '/'));
        $scriptName = str_replace('\\', '/', $_SERVER['SCRIPT_NAME'] ?? '');
        $basePath = rtrim(str_replace('\\', '/', dirname($scriptName)), '/.');
        if ($basePath !== '' && ($path === $basePath || str_starts_with($path, $basePath . '/'))) {
            $path = substr($path, strlen($basePath)) ?: '/';
        }
        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $name = strtolower(str_replace('_', '-', substr($key, 5)));
                $headers[$name] = trim((string) $value);
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = trim((string) $_SERVER['CONTENT_TYPE']);
        }
        $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
        if ($authorization !== null) {
            $headers['authorization'] = trim((string) $authorization);
        }

        $contentType = strtolower(explode(';', $headers['content-type'] ?? '')[0]);
        $isMultipart = $contentType === 'multipart/form-data';
        $contentLength = filter_var(
            $_SERVER['CONTENT_LENGTH'] ?? 0,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 0]],
        );
        $contentLength = $contentLength === false ? 0 : $contentLength;
        if ($isMultipart && $contentLength > 64 * 1024 * 1024) {
            throw new ApiException(413, 'payload_too_large', 'Multipart request exceeds 64 MiB.');
        }
        $rawBody = '';
        if (!$isMultipart) {
            $rawBody = file_get_contents('php://input');
            if ($rawBody === false) {
                $rawBody = '';
            }
            if (strlen($rawBody) > 65_536) {
                throw new ApiException(413, 'payload_too_large', 'Request body exceeds 64 KiB.');
            }
        }

        $providedRequestId = $headers['x-request-id'] ?? '';
        $requestId = preg_match('/^[A-Za-z0-9._-]{8,64}$/', $providedRequestId) === 1
            ? $providedRequestId
            : bin2hex(random_bytes(12));

        return new self(
            method: $method,
            path: '/' . ltrim(rtrim($path, '/') ?: '/', '/'),
            query: $_GET,
            headers: $headers,
            rawBody: $rawBody,
            formFields: $_POST,
            uploadedFiles: $_FILES,
            contentLength: $contentLength,
            remoteAddress: $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0',
            requestId: $requestId,
        );
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    /** @return array<string, mixed> */
    public function json(): array
    {
        if ($this->rawBody === '') {
            return [];
        }
        $contentType = strtolower(explode(';', $this->header('content-type') ?? '')[0]);
        if ($contentType !== 'application/json') {
            throw new ApiException(415, 'unsupported_media_type', 'Content-Type must be application/json.');
        }
        try {
            $decoded = json_decode($this->rawBody, true, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new ApiException(400, 'invalid_json', 'Request body is not valid JSON.');
        }
        if (!is_array($decoded) || array_is_list($decoded)) {
            throw new ApiException(400, 'invalid_json', 'Request body must be a JSON object.');
        }
        return $decoded;
    }

    public function bearerToken(): ?string
    {
        $authorization = $this->header('authorization');
        if ($authorization === null || preg_match('/^Bearer ([A-Za-z0-9_-]{40,128})$/', $authorization, $matches) !== 1) {
            return null;
        }
        return $matches[1];
    }

    public function isMultipart(): bool
    {
        return strtolower(explode(';', $this->header('content-type') ?? '')[0]) === 'multipart/form-data';
    }

    /** @return array<string, mixed> */
    public function form(): array
    {
        if (!$this->isMultipart()) {
            throw new ApiException(415, 'unsupported_media_type', 'Content-Type must be multipart/form-data.');
        }
        if ($this->contentLength > 0 && $this->formFields === [] && $this->uploadedFiles === [] &&
            $this->contentLength > self::iniBytes((string) ini_get('post_max_size'))) {
            throw new ApiException(413, 'payload_too_large', 'Multipart request exceeds the server upload limit.');
        }
        return $this->formFields;
    }

    /** @return list<string> */
    public function uploadedFileFieldNames(): array
    {
        return array_values(array_map('strval', array_keys($this->uploadedFiles)));
    }

    public function uploadedFile(string $field): ?UploadedFile
    {
        $files = $this->uploadedFiles($field);
        if (count($files) > 1) {
            throw new ApiException(422, 'invalid_upload', $field . ' must contain one file.');
        }
        return $files[0] ?? null;
    }

    /** @return list<UploadedFile> */
    public function uploadedFiles(string $field): array
    {
        $value = $this->uploadedFiles[$field] ?? null;
        if ($value === null) {
            return [];
        }
        if (!is_array($value) || !array_key_exists('name', $value) ||
            !array_key_exists('tmp_name', $value) || !array_key_exists('size', $value) ||
            !array_key_exists('error', $value)) {
            throw new ApiException(400, 'invalid_upload', 'Uploaded file metadata is invalid.');
        }
        if (!is_array($value['name'])) {
            $upload = UploadedFile::fromPhpUpload($value);
            return $upload->error === UPLOAD_ERR_NO_FILE ? [] : [$upload];
        }
        foreach (['tmp_name', 'size', 'error'] as $key) {
            if (!is_array($value[$key]) || array_keys($value[$key]) !== array_keys($value['name'])) {
                throw new ApiException(400, 'invalid_upload', 'Uploaded file metadata is invalid.');
            }
        }
        $files = [];
        foreach (array_keys($value['name']) as $key) {
            if (is_array($value['name'][$key]) || is_array($value['tmp_name'][$key]) ||
                is_array($value['size'][$key]) || is_array($value['error'][$key])) {
                throw new ApiException(400, 'invalid_upload', 'Nested file uploads are not supported.');
            }
            $upload = UploadedFile::fromPhpUpload([
                'name' => $value['name'][$key],
                'tmp_name' => $value['tmp_name'][$key],
                'size' => $value['size'][$key],
                'error' => $value['error'][$key],
            ]);
            if ($upload->error !== UPLOAD_ERR_NO_FILE) {
                $files[] = $upload;
            }
        }
        return $files;
    }

    private static function iniBytes(string $value): int
    {
        $value = trim($value);
        if ($value === '' || $value === '-1') {
            return PHP_INT_MAX;
        }
        $number = (int) $value;
        return match (strtolower(substr($value, -1))) {
            'g' => $number * 1024 * 1024 * 1024,
            'm' => $number * 1024 * 1024,
            'k' => $number * 1024,
            default => $number,
        };
    }
}
