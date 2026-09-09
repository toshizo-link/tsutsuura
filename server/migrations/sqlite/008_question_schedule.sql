ALTER TABLE questions ADD COLUMN publish_start_minute INTEGER NOT NULL DEFAULT 540
    CHECK (publish_start_minute BETWEEN 540 AND 1140);
ALTER TABLE questions ADD COLUMN publish_end_minute INTEGER NOT NULL DEFAULT 1140
    CHECK (publish_end_minute BETWEEN 540 AND 1140);

-- Existing questions about this day's experiences should arrive in the evening.
UPDATE questions SET publish_start_minute = 1020 WHERE prompt LIKE '今日%';

CREATE TABLE IF NOT EXISTS daily_question_publications (
    family_id INTEGER NOT NULL,
    local_date TEXT NOT NULL,
    question_id INTEGER NOT NULL,
    available_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (family_id, local_date),
    FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE CASCADE,
    FOREIGN KEY (question_id) REFERENCES questions (id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS daily_question_publications_date_index
    ON daily_question_publications (local_date, available_at);
