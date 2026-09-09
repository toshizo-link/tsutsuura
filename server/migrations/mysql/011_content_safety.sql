CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_user_id BIGINT UNSIGNED NOT NULL,
    blocked_user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    KEY user_blocks_reverse_index (blocked_user_id, blocker_user_id),
    CONSTRAINT user_blocks_blocker_fk FOREIGN KEY (blocker_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT user_blocks_blocked_fk FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CHECK (blocker_user_id <> blocked_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS answer_reports (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    answer_id BIGINT UNSIGNED NOT NULL,
    reported_by_user_id BIGINT UNSIGNED NOT NULL,
    reason ENUM('spam', 'harassment', 'privacy', 'inappropriate', 'other') NOT NULL,
    details VARCHAR(500) NULL,
    status ENUM('pending', 'reviewed', 'dismissed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY answer_reports_reporter_unique (answer_id, reported_by_user_id),
    KEY answer_reports_status_index (status, created_at, id),
    CONSTRAINT answer_reports_answer_fk FOREIGN KEY (answer_id) REFERENCES answers(id) ON DELETE CASCADE,
    CONSTRAINT answer_reports_reporter_fk FOREIGN KEY (reported_by_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS moderation_actions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    report_type ENUM('answer', 'comment') NOT NULL,
    report_id BIGINT UNSIGNED NOT NULL,
    answer_id BIGINT UNSIGNED NULL,
    comment_id BIGINT UNSIGNED NULL,
    decision ENUM('remove', 'dismiss') NOT NULL,
    reviewer VARCHAR(100) NOT NULL,
    note VARCHAR(1000) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY moderation_report_unique (report_type, report_id),
    KEY moderation_answer_index (answer_id, decision),
    KEY moderation_comment_index (comment_id, decision),
    CONSTRAINT moderation_answer_fk FOREIGN KEY (answer_id) REFERENCES answers(id) ON DELETE CASCADE,
    CONSTRAINT moderation_comment_fk FOREIGN KEY (comment_id) REFERENCES comments(id) ON DELETE CASCADE,
    CHECK ((answer_id IS NOT NULL AND comment_id IS NULL) OR (answer_id IS NULL AND comment_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
