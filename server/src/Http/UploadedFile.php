<?php
declare(strict_types=1);

namespace Tsutsuura\Server\Http;

final readonly class UploadedFile
{
    private function __construct(
        public string $temporaryPath,
        public string $clientName,
        public int $reportedSize,
        public int $error,
        private bool $httpUpload,
    ) {
    }

    /** @param array{name: mixed, tmp_name: mixed, size: mixed, error: mixed} $upload */
    public static function fromPhpUpload(array $upload): self
    {
        if (!is_string($upload['name']) ||
            !is_string($upload['tmp_name']) ||
            !is_int($upload['size']) ||
            !is_int($upload['error'])) {
            throw new ApiException(400, 'invalid_upload', 'Uploaded file metadata is invalid.');
        }
        return new self(
            temporaryPath: $upload['tmp_name'],
            clientName: $upload['name'],
            reportedSize: $upload['size'],
            error: $upload['error'],
            httpUpload: true,
        );
    }

    /** Intended for CLI validation and smoke tests, not HTTP request data. */
    public static function fromLocalFile(string $path, string $clientName): self
    {
        $size = is_file($path) ? filesize($path) : false;
        return new self(
            temporaryPath: $path,
            clientName: $clientName,
            reportedSize: $size === false ? 0 : $size,
            error: UPLOAD_ERR_OK,
            httpUpload: false,
        );
    }

    public function isTrustedSource(): bool
    {
        return $this->httpUpload ? is_uploaded_file($this->temporaryPath) : is_file($this->temporaryPath);
    }
}
