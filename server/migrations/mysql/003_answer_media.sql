CREATE TABLE IF NOT EXISTS answer_media (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    answer_id BIGINT UNSIGNED NOT NULL,
    kind ENUM('audio', 'photo') NOT NULL,
    sort_order TINYINT UNSIGNED NOT NULL DEFAULT 0,
    storage_key VARCHAR(191) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    file_name VARCHAR(255) NULL,
    mime_type VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    byte_count BIGINT UNSIGNED NOT NULL,
    width INT UNSIGNED NULL,
    height INT UNSIGNED NULL,
    duration_ms INT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY answer_media_storage_unique (storage_key),
    UNIQUE KEY answer_media_slot_unique (answer_id, kind, sort_order),
    KEY answer_media_answer_index (answer_id, kind, sort_order),
    CONSTRAINT answer_media_answer_fk FOREIGN KEY (answer_id) REFERENCES answers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
