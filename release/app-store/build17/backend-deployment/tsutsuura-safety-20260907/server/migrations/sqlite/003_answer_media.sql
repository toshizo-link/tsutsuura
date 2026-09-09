CREATE TABLE IF NOT EXISTS answer_media (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    answer_id INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('audio', 'photo')),
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    storage_key TEXT NOT NULL UNIQUE,
    file_name TEXT NULL,
    mime_type TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
    width INTEGER NULL CHECK (width IS NULL OR width > 0),
    height INTEGER NULL CHECK (height IS NULL OR height > 0),
    duration_ms INTEGER NULL CHECK (duration_ms IS NULL OR duration_ms > 0),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (answer_id, kind, sort_order),
    FOREIGN KEY (answer_id) REFERENCES answers (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS answer_media_answer_index
    ON answer_media (answer_id, kind, sort_order);
