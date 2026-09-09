ALTER TABLE questions ADD COLUMN publish_start_minute SMALLINT UNSIGNED NOT NULL DEFAULT 540;
ALTER TABLE questions ADD COLUMN publish_end_minute SMALLINT UNSIGNED NOT NULL DEFAULT 1140;

-- Existing questions about this day's experiences should arrive in the evening.
UPDATE questions SET publish_start_minute = 1020 WHERE prompt LIKE '今日%';

CREATE TABLE IF NOT EXISTS daily_question_publications (
    family_id BIGINT UNSIGNED NOT NULL,
    local_date DATE NOT NULL,
    question_id BIGINT UNSIGNED NOT NULL,
    available_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (family_id, local_date),
    KEY daily_question_publications_date_index (local_date, available_at),
    CONSTRAINT daily_publications_family_fk FOREIGN KEY (family_id)
        REFERENCES families (id) ON DELETE CASCADE,
    CONSTRAINT daily_publications_question_fk FOREIGN KEY (question_id)
        REFERENCES questions (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
