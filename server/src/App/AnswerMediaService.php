<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use DateTimeImmutable;
use FilesystemIterator;
use PDO;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use RuntimeException;
use Throwable;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Http\UploadedFile;
use Tsutsuura\Server\Security\Crypto;

final class AnswerMediaService
{
    private const MAX_AUDIO_DURATION_MS = 86_400_000;
    private const MAX_IMAGE_DIMENSION = 20_000;
    private const MAX_IMAGE_PIXELS = 100_000_000;

    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly Config $config,
    ) {
    }

    /**
     * @param list<UploadedFile> $photos
     * @return list<array<string, mixed>>
     */
    public function prepareUploads(
        ?UploadedFile $audio,
        array $photos,
        mixed $audioDurationMilliseconds,
    ): array {
        if (count($photos) > $this->config->answerPhotoMaxCount) {
            throw new ApiException(
                422,
                'too_many_photos',
                sprintf('An answer can include at most %d photos.', $this->config->answerPhotoMaxCount),
            );
        }
        foreach ($photos as $photo) {
            if (!$photo instanceof UploadedFile) {
                throw new ApiException(400, 'invalid_upload', 'Photo upload metadata is invalid.');
            }
        }
        $duration = $this->duration($audioDurationMilliseconds, $audio !== null);
        $descriptors = [];
        if ($audio !== null) {
            $descriptors[] = $this->inspectAudio($audio, $duration);
        }
        foreach ($photos as $position => $photo) {
            $descriptors[] = $this->inspectPhoto($photo, $position);
        }
        if ($descriptors === []) {
            return [];
        }

        $this->ensureStorageReady();
        $prepared = [];
        try {
            foreach ($descriptors as $descriptor) {
                $prepared[] = $this->store($descriptor);
            }
        } catch (Throwable $exception) {
            $this->discardPrepared($prepared);
            throw $exception;
        }
        return $prepared;
    }

    /**
     * Replaces all media rows for an answer inside the caller's transaction.
     *
     * @param list<array<string, mixed>> $prepared
     * @return list<string> previous storage keys to delete after commit
     */
    public function replaceForAnswer(PDO $pdo, int $answerId, array $prepared): array
    {
        $familyStatement = $pdo->prepare(
            'SELECT f.id
             FROM families f
             JOIN answers a ON a.family_id = f.id
             WHERE a.id = :answer' . ($this->database->isSqlite() ? '' : ' FOR UPDATE')
        );
        $familyStatement->execute(['answer' => $answerId]);
        $familyId = $familyStatement->fetchColumn();
        if ($familyId === false) {
            throw new RuntimeException('Answer media quota could not resolve the answer family.');
        }
        $oldStatement = $pdo->prepare(
            'SELECT storage_key, byte_count FROM answer_media WHERE answer_id = :answer'
        );
        $oldStatement->execute(['answer' => $answerId]);
        $oldRows = $oldStatement->fetchAll();
        $oldKeys = array_map(
            static fn (array $row): string => (string) $row['storage_key'],
            $oldRows,
        );
        $oldBytes = array_sum(array_map(
            static fn (array $row): int => (int) $row['byte_count'],
            $oldRows,
        ));
        $familyBytesStatement = $pdo->prepare(
            'SELECT COALESCE(SUM(am.byte_count), 0)
             FROM answer_media am
             JOIN answers a ON a.id = am.answer_id
             WHERE a.family_id = :family'
        );
        $familyBytesStatement->execute(['family' => (int) $familyId]);
        $familyBytes = (int) $familyBytesStatement->fetchColumn();
        $newBytes = array_sum(array_map(
            static fn (array $media): int => (int) $media['byteCount'],
            $prepared,
        ));
        $projectedBytes = $familyBytes - $oldBytes + $newBytes;
        if ($projectedBytes > $this->config->answerMediaFamilyQuotaBytes &&
            $projectedBytes > $familyBytes) {
            throw new ApiException(
                422,
                'media_quota_exceeded',
                'The family answer media storage quota has been reached.',
                ['maximumBytes' => $this->config->answerMediaFamilyQuotaBytes],
            );
        }
        $delete = $pdo->prepare('DELETE FROM answer_media WHERE answer_id = :answer');
        $delete->execute(['answer' => $answerId]);

        $insert = $pdo->prepare(
            'INSERT INTO answer_media
                (answer_id, kind, sort_order, storage_key, file_name, mime_type,
                 byte_count, width, height, duration_ms)
             VALUES
                (:answer, :kind, :sort_order, :storage_key, :file_name, :mime_type,
                 :byte_count, :width, :height, :duration_ms)'
        );
        foreach ($prepared as $media) {
            $insert->execute([
                'answer' => $answerId,
                'kind' => $media['kind'],
                'sort_order' => $media['position'],
                'storage_key' => $media['storageKey'],
                'file_name' => $media['fileName'],
                'mime_type' => $media['mimeType'],
                'byte_count' => $media['byteCount'],
                'width' => $media['width'],
                'height' => $media['height'],
                'duration_ms' => $media['durationMilliseconds'],
            ]);
        }
        return $oldKeys;
    }

    /** @param list<array<string, mixed>> $prepared */
    public function discardPrepared(array $prepared): void
    {
        foreach ($prepared as $media) {
            if (isset($media['storageKey']) && is_string($media['storageKey'])) {
                $this->deleteStorageKey($media['storageKey']);
            }
        }
    }

    /** @param list<string> $storageKeys */
    public function deleteStorageKeys(array $storageKeys): void
    {
        foreach ($storageKeys as $storageKey) {
            $this->deleteStorageKey($storageKey);
        }
    }

    /**
     * @param list<int> $answerIds
     * @return array<int, list<array<string, mixed>>>
     */
    public function forAnswers(array $answerIds): array
    {
        $answerIds = array_values(array_unique(array_filter(
            $answerIds,
            static fn (int $id): bool => $id > 0,
        )));
        if ($answerIds === []) {
            return [];
        }
        $placeholders = implode(',', array_fill(0, count($answerIds), '?'));
        $statement = $this->database->connection()->prepare(
            'SELECT id, answer_id, kind, sort_order, storage_key, file_name, mime_type,
                    byte_count, duration_ms
             FROM answer_media
             WHERE answer_id IN (' . $placeholders . ')
             ORDER BY answer_id ASC,
                      CASE kind WHEN \'audio\' THEN 0 ELSE 1 END ASC,
                      sort_order ASC, id ASC'
        );
        foreach ($answerIds as $index => $answerId) {
            $statement->bindValue($index + 1, $answerId, PDO::PARAM_INT);
        }
        $statement->execute();
        $byAnswer = [];
        foreach ($statement->fetchAll() as $row) {
            $answerId = (int) $row['answer_id'];
            $byAnswer[$answerId] ??= [];
            $byAnswer[$answerId][] = $this->present($row);
        }
        return $byAnswer;
    }

    /**
     * @return array{path: string, mimeType: string, fileName: ?string, byteCount: int}
     */
    public function download(int $userId, string $mediaIdValue, string $token): array
    {
        if (preg_match('/^[1-9][0-9]{0,18}$/', $mediaIdValue) !== 1 ||
            preg_match('/^[a-f0-9]{64}$/', $token) !== 1) {
            throw new ApiException(404, 'media_not_found', 'Answer media not found.');
        }
        $statement = $this->database->connection()->prepare(
            'SELECT am.id, am.storage_key, am.file_name, am.mime_type, am.byte_count
             FROM answer_media am
             JOIN answers a ON a.id = am.answer_id
             JOIN family_members fm ON fm.family_id = a.family_id
             WHERE am.id = :media AND fm.user_id = :user
             LIMIT 1'
        );
        $statement->execute(['media' => (int) $mediaIdValue, 'user' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row) || !hash_equals($this->accessToken($row), $token)) {
            throw new ApiException(404, 'media_not_found', 'Answer media not found.');
        }
        $path = $this->pathForStorageKey((string) $row['storage_key']);
        $realRoot = realpath($this->config->mediaStoragePath);
        $realPath = realpath($path);
        if ($realRoot === false || $realPath === false ||
            !str_starts_with($realPath, rtrim($realRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR) ||
            !is_file($realPath) || !is_readable($realPath)) {
            throw new ApiException(404, 'media_not_found', 'Answer media not found.');
        }
        $actualSize = filesize($realPath);
        if ($actualSize === false || $actualSize !== (int) $row['byte_count']) {
            throw new ApiException(404, 'media_not_found', 'Answer media not found.');
        }
        return [
            'path' => $realPath,
            'mimeType' => (string) $row['mime_type'],
            'fileName' => $row['file_name'] === null ? null : (string) $row['file_name'],
            'byteCount' => $actualSize,
        ];
    }

    public function ensureStorageReady(): void
    {
        $path = $this->config->mediaStoragePath;
        $created = false;
        if (!is_dir($path)) {
            if (!mkdir($path, 0700, true) && !is_dir($path)) {
                throw new RuntimeException('Answer media storage directory could not be created.');
            }
            $created = true;
        }
        if (!is_writable($path)) {
            throw new RuntimeException('Answer media storage directory is not writable.');
        }
        if ($created) {
            @chmod($path, 0700);
        }
    }

    public function assertUploadRuntimeReady(): void
    {
        $fileUploads = filter_var(ini_get('file_uploads'), FILTER_VALIDATE_BOOLEAN);
        if ($fileUploads !== true) {
            throw new RuntimeException('PHP file_uploads must be enabled for answer media.');
        }
        $requiredFileBytes = max(
            $this->config->answerAudioMaxBytes,
            $this->config->answerPhotoMaxBytes,
        );
        if (self::iniBytes((string) ini_get('upload_max_filesize'), false) < $requiredFileBytes) {
            throw new RuntimeException('PHP upload_max_filesize is below the configured answer media limit.');
        }
        $requiredPostBytes = $this->config->answerAudioMaxBytes +
            ($this->config->answerPhotoMaxBytes * $this->config->answerPhotoMaxCount) +
            (1024 * 1024);
        if (self::iniBytes((string) ini_get('post_max_size'), true) < $requiredPostBytes) {
            throw new RuntimeException('PHP post_max_size is below the configured answer media aggregate limit.');
        }
        if ((int) ini_get('max_file_uploads') < $this->config->answerPhotoMaxCount + 1) {
            throw new RuntimeException('PHP max_file_uploads is below the configured answer media file count.');
        }
        $temporaryDirectory = trim((string) ini_get('upload_tmp_dir'));
        $temporaryDirectory = $temporaryDirectory === '' ? sys_get_temp_dir() : $temporaryDirectory;
        if (!is_dir($temporaryDirectory) || !is_writable($temporaryDirectory)) {
            throw new RuntimeException('PHP upload temporary directory is not writable.');
        }
    }

    public function cleanupOrphanedFiles(?DateTimeImmutable $olderThan = null): int
    {
        $this->ensureStorageReady();
        $olderThan ??= new DateTimeImmutable('-1 hour');
        $statement = $this->database->connection()->query('SELECT storage_key FROM answer_media');
        $referenced = [];
        foreach ($statement->fetchAll() as $row) {
            $referenced[(string) $row['storage_key']] = true;
        }
        $root = rtrim($this->config->mediaStoragePath, DIRECTORY_SEPARATOR);
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::CHILD_FIRST,
        );
        $deleted = 0;
        foreach ($iterator as $item) {
            if ($item->isDir()) {
                if (preg_match('/^[a-f0-9]{2}$/', $item->getBasename()) === 1) {
                    @rmdir($item->getPathname());
                }
                continue;
            }
            $relative = str_replace(DIRECTORY_SEPARATOR, '/', substr(
                $item->getPathname(),
                strlen($root) + 1,
            ));
            if (preg_match('#^[a-f0-9]{2}/[a-f0-9]{62}$#', $relative) !== 1 ||
                isset($referenced[$relative]) || $item->getMTime() >= $olderThan->getTimestamp()) {
                continue;
            }
            if (@unlink($item->getPathname())) {
                $deleted++;
            }
        }
        return $deleted;
    }

    /** @return array<string, mixed> */
    private function inspectAudio(UploadedFile $audio, ?int $duration): array
    {
        $size = $this->validatedSize($audio, $this->config->answerAudioMaxBytes, 'audio');
        $prefix = file_get_contents($audio->temporaryPath, false, null, 0, 64);
        if ($prefix === false) {
            throw new ApiException(400, 'invalid_audio', 'Audio recording could not be read.');
        }
        $detected = $this->detectedMime($audio->temporaryPath);
        $mime = null;
        if (strlen($prefix) >= 12 && substr($prefix, 4, 4) === 'ftyp' &&
            in_array(substr($prefix, 8, 4), ['M4A ', 'M4B ', 'mp42', 'isom'], true) &&
            in_array($detected, ['audio/mp4', 'audio/x-m4a', 'video/mp4', 'application/octet-stream'], true)) {
            $mime = 'audio/mp4';
        } elseif ((str_starts_with($prefix, 'ID3') || self::isMpegFrame($prefix)) &&
            in_array($detected, ['audio/mpeg', 'audio/mp3', 'application/octet-stream'], true)) {
            $mime = 'audio/mpeg';
        } elseif (self::isAdts($prefix) &&
            in_array($detected, ['audio/aac', 'audio/x-hx-aac-adts', 'application/octet-stream'], true)) {
            $mime = 'audio/aac';
        } elseif (strlen($prefix) >= 12 && str_starts_with($prefix, 'RIFF') && substr($prefix, 8, 4) === 'WAVE' &&
            in_array($detected, ['audio/wav', 'audio/x-wav', 'audio/vnd.wave'], true)) {
            $mime = 'audio/wav';
        } elseif (str_starts_with($prefix, 'caff') &&
            in_array($detected, ['audio/x-caf', 'application/octet-stream'], true)) {
            $mime = 'audio/x-caf';
        }
        if ($mime === null) {
            throw new ApiException(
                422,
                'invalid_audio_type',
                'Audio must be an M4A, AAC, MP3, WAV, or CAF recording.',
            );
        }
        return [
            'kind' => 'audio',
            'position' => 0,
            'source' => $audio->temporaryPath,
            'fileName' => $this->fileName($audio->clientName, 'recording.m4a'),
            'mimeType' => $mime,
            'byteCount' => $size,
            'width' => null,
            'height' => null,
            'durationMilliseconds' => $duration,
        ];
    }

    /** @return array<string, mixed> */
    private function inspectPhoto(UploadedFile $photo, int $position): array
    {
        $size = $this->validatedSize($photo, $this->config->answerPhotoMaxBytes, 'photo');
        $detected = $this->detectedMime($photo->temporaryPath);
        $image = @getimagesize($photo->temporaryPath);
        $allowed = [
            IMAGETYPE_JPEG => 'image/jpeg',
            IMAGETYPE_PNG => 'image/png',
            IMAGETYPE_WEBP => 'image/webp',
        ];
        if (!is_array($image) || !isset($image[0], $image[1], $image[2], $allowed[$image[2]]) ||
            $detected !== $allowed[$image[2]]) {
            throw new ApiException(
                422,
                'invalid_photo_type',
                'Photos must be valid JPEG, PNG, or WebP images.',
            );
        }
        $width = (int) $image[0];
        $height = (int) $image[1];
        if ($width < 1 || $height < 1 || $width > self::MAX_IMAGE_DIMENSION ||
            $height > self::MAX_IMAGE_DIMENSION || $width * $height > self::MAX_IMAGE_PIXELS) {
            throw new ApiException(422, 'invalid_photo_dimensions', 'Photo dimensions are not supported.');
        }
        return [
            'kind' => 'photo',
            'position' => $position,
            'source' => $photo->temporaryPath,
            'fileName' => $this->fileName($photo->clientName, 'photo'),
            'mimeType' => $allowed[$image[2]],
            'byteCount' => $size,
            'width' => $width,
            'height' => $height,
            'durationMilliseconds' => null,
        ];
    }

    private function validatedSize(UploadedFile $file, int $maximum, string $kind): int
    {
        if (in_array($file->error, [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true)) {
            throw new ApiException(413, 'payload_too_large', ucfirst($kind) . ' upload is too large.');
        }
        if (in_array($file->error, [UPLOAD_ERR_NO_TMP_DIR, UPLOAD_ERR_CANT_WRITE, UPLOAD_ERR_EXTENSION], true)) {
            throw new ApiException(503, 'upload_unavailable', 'Media upload storage is unavailable.');
        }
        if ($file->error !== UPLOAD_ERR_OK) {
            throw new ApiException(400, 'invalid_upload', ucfirst($kind) . ' upload did not complete.');
        }
        if (!$file->isTrustedSource() || !is_readable($file->temporaryPath)) {
            throw new ApiException(400, 'invalid_upload', ucfirst($kind) . ' upload is invalid.');
        }
        $size = filesize($file->temporaryPath);
        if ($size === false || $size < 1) {
            throw new ApiException(422, 'invalid_' . $kind, ucfirst($kind) . ' upload is empty.');
        }
        if ($size > $maximum || $file->reportedSize > $maximum) {
            throw new ApiException(413, 'payload_too_large', ucfirst($kind) . ' upload is too large.');
        }
        return $size;
    }

    private function detectedMime(string $path): string
    {
        $finfo = new \finfo(FILEINFO_MIME_TYPE);
        $mime = $finfo->file($path);
        return is_string($mime) ? strtolower(trim($mime)) : '';
    }

    private function duration(mixed $value, bool $hasAudio): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!$hasAudio || (!is_int($value) && !is_string($value)) ||
            preg_match('/^[1-9][0-9]{0,8}$/', (string) $value) !== 1) {
            throw new ApiException(
                422,
                'invalid_audio_duration',
                'audioDurationMilliseconds must be a positive integer for an audio upload.',
            );
        }
        $duration = (int) $value;
        if ($duration > self::MAX_AUDIO_DURATION_MS) {
            throw new ApiException(422, 'invalid_audio_duration', 'Audio duration cannot exceed 24 hours.');
        }
        return $duration;
    }

    /** @param array<string, mixed> $descriptor
     *  @return array<string, mixed>
     */
    private function store(array $descriptor): array
    {
        for ($attempt = 0; $attempt < 3; $attempt++) {
            $random = bin2hex(random_bytes(32));
            $storageKey = substr($random, 0, 2) . '/' . substr($random, 2);
            $directory = $this->config->mediaStoragePath . DIRECTORY_SEPARATOR . substr($random, 0, 2);
            if (!is_dir($directory) && !mkdir($directory, 0700) && !is_dir($directory)) {
                throw new RuntimeException('Answer media storage bucket could not be created.');
            }
            $realRoot = realpath($this->config->mediaStoragePath);
            $realDirectory = realpath($directory);
            if (is_link($directory) || $realRoot === false || $realDirectory === false ||
                dirname($realDirectory) !== rtrim($realRoot, DIRECTORY_SEPARATOR)) {
                throw new RuntimeException('Answer media storage bucket is unsafe.');
            }
            @chmod($directory, 0700);
            $destination = $this->pathForStorageKey($storageKey);
            $output = @fopen($destination, 'x+b');
            if ($output === false) {
                continue;
            }
            $input = @fopen((string) $descriptor['source'], 'rb');
            if ($input === false) {
                fclose($output);
                @unlink($destination);
                throw new RuntimeException('Uploaded media could not be opened.');
            }
            try {
                $copied = stream_copy_to_stream($input, $output);
                if ($copied === false || $copied !== $descriptor['byteCount'] || !fflush($output)) {
                    throw new RuntimeException('Uploaded media could not be stored completely.');
                }
            } catch (Throwable $exception) {
                fclose($input);
                fclose($output);
                @unlink($destination);
                throw $exception;
            }
            fclose($input);
            fclose($output);
            @chmod($destination, 0600);
            unset($descriptor['source']);
            $descriptor['storageKey'] = $storageKey;
            return $descriptor;
        }
        throw new RuntimeException('A unique answer media storage key could not be allocated.');
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function present(array $row): array
    {
        $media = [
            'id' => (string) $row['id'],
            'kind' => (string) $row['kind'],
            'url' => $this->config->appUrl . '/v1/answer-media/' . rawurlencode((string) $row['id']) .
                '/' . $this->accessToken($row),
            'mimeType' => (string) $row['mime_type'],
            'byteCount' => (int) $row['byte_count'],
        ];
        if ($row['file_name'] !== null && $row['file_name'] !== '') {
            $media['fileName'] = (string) $row['file_name'];
        }
        if ($row['duration_ms'] !== null) {
            $media['durationMilliseconds'] = (int) $row['duration_ms'];
        }
        return $media;
    }

    /** @param array<string, mixed> $row */
    private function accessToken(array $row): string
    {
        return $this->crypto->hashOpaque(
            "answer-media\0" . (string) $row['id'] . "\0" . (string) $row['storage_key'],
        );
    }

    private function pathForStorageKey(string $storageKey): string
    {
        if (preg_match('#^[a-f0-9]{2}/[a-f0-9]{62}$#', $storageKey) !== 1) {
            throw new RuntimeException('Stored answer media key is invalid.');
        }
        return rtrim($this->config->mediaStoragePath, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR .
            str_replace('/', DIRECTORY_SEPARATOR, $storageKey);
    }

    private function deleteStorageKey(string $storageKey): void
    {
        try {
            $path = $this->pathForStorageKey($storageKey);
        } catch (RuntimeException) {
            return;
        }
        if (is_file($path)) {
            if (!@unlink($path)) {
                // The row has already committed its deletion. Leave the file
                // in place for cleanupOrphanedFiles() to retry and emit only a
                // keyed identifier, never a user filename or public URL.
                error_log('Deferred orphan media deletion: ' . hash('sha256', $storageKey));
                return;
            }
        }
        $directory = dirname($path);
        if (is_dir($directory)) {
            @rmdir($directory);
        }
    }

    private function fileName(string $value, string $fallback): string
    {
        if (!mb_check_encoding($value, 'UTF-8')) {
            return $fallback;
        }
        $value = str_replace('\\', '/', $value);
        $value = basename($value);
        $value = preg_replace('/[\x00-\x1F\x7F]/u', '', $value) ?? '';
        $value = trim($value, " .\t\n\r\0\x0B");
        if ($value === '') {
            return $fallback;
        }
        return mb_substr($value, 0, 200);
    }

    private static function isMpegFrame(string $prefix): bool
    {
        if (strlen($prefix) < 3 || ord($prefix[0]) !== 0xff) {
            return false;
        }
        $second = ord($prefix[1]);
        $third = ord($prefix[2]);
        return ($second & 0xe0) === 0xe0 &&
            (($second >> 3) & 0x03) !== 0x01 &&
            (($second >> 1) & 0x03) !== 0x00 &&
            (($third >> 4) & 0x0f) !== 0x00 &&
            (($third >> 4) & 0x0f) !== 0x0f &&
            (($third >> 2) & 0x03) !== 0x03;
    }

    private static function isAdts(string $prefix): bool
    {
        return strlen($prefix) >= 2 && ord($prefix[0]) === 0xff && (ord($prefix[1]) & 0xf6) === 0xf0;
    }

    private static function iniBytes(string $value, bool $zeroIsUnlimited): int
    {
        $value = trim($value);
        if ($value === '' || $value === '-1' || ($zeroIsUnlimited && $value === '0')) {
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
