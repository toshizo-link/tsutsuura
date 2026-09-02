ALTER TABLE comments
    ADD COLUMN parent_comment_id BIGINT UNSIGNED NULL AFTER user_id,
    ADD KEY comments_parent_index (parent_comment_id, created_at, id),
    ADD CONSTRAINT comments_parent_fk
        FOREIGN KEY (parent_comment_id) REFERENCES comments (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS comment_reports (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    comment_id BIGINT UNSIGNED NOT NULL,
    reported_by_user_id BIGINT UNSIGNED NOT NULL,
    reason ENUM('spam', 'harassment', 'privacy', 'inappropriate', 'other') NOT NULL,
    details VARCHAR(500) NULL,
    status ENUM('pending', 'reviewed', 'dismissed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY comment_reports_reporter_unique (comment_id, reported_by_user_id),
    KEY comment_reports_status_index (status, created_at, id),
    CONSTRAINT comment_reports_comment_fk
        FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE,
    CONSTRAINT comment_reports_reporter_fk
        FOREIGN KEY (reported_by_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    question_reminders_enabled TINYINT(1) NOT NULL DEFAULT 1,
    question_reminder_time TIME NOT NULL DEFAULT '09:00:00',
    comments_enabled TINYINT(1) NOT NULL DEFAULT 1,
    likes_enabled TINYINT(1) NOT NULL DEFAULT 1,
    family_activity_enabled TINYINT(1) NOT NULL DEFAULT 1,
    quiet_start TIME NULL,
    quiet_end TIME NULL,
    timezone VARCHAR(64) NULL,
    mute_until DATETIME NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT notification_preferences_user_fk
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notification_reminder_dispatches (
    user_id BIGINT UNSIGNED NOT NULL,
    local_date DATE NOT NULL,
    reminder_time TIME NOT NULL,
    status ENUM('reserved', 'delivered', 'failed') NOT NULL DEFAULT 'reserved',
    delivered_count INT UNSIGNED NOT NULL DEFAULT 0,
    failed_count INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, local_date),
    KEY notification_reminder_dispatch_date_index (local_date, status, user_id),
    CONSTRAINT notification_reminder_dispatch_user_fk
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS phone_enrollment_challenges (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    request_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phone_e164 VARCHAR(20) NOT NULL,
    code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    max_attempts SMALLINT UNSIGNED NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY phone_enrollment_request_unique (request_id),
    KEY phone_enrollment_user_created_index (user_id, created_at),
    KEY phone_enrollment_expiry_index (expires_at),
    CONSTRAINT phone_enrollment_user_fk
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_recovery_codes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY device_recovery_code_unique (code_hash),
    KEY device_recovery_user_expiry_index (user_id, expires_at),
    CONSTRAINT device_recovery_user_fk
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS account_audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    actor_user_id BIGINT UNSIGNED NULL,
    family_id BIGINT UNSIGNED NULL,
    action VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_type VARCHAR(50) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(191) NULL,
    metadata_json LONGTEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY account_audit_actor_index (actor_user_id, created_at, id),
    KEY account_audit_family_index (family_id, created_at, id),
    CONSTRAINT account_audit_actor_fk
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT account_audit_family_fk
        FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
