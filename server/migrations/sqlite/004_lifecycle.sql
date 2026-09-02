ALTER TABLE comments
    ADD COLUMN parent_comment_id INTEGER NULL
    REFERENCES comments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS comments_parent_index
    ON comments (parent_comment_id, created_at, id);

CREATE TABLE IF NOT EXISTS comment_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    comment_id INTEGER NOT NULL,
    reported_by_user_id INTEGER NOT NULL,
    reason TEXT NOT NULL
        CHECK (reason IN ('spam', 'harassment', 'privacy', 'inappropriate', 'other')),
    details TEXT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'reviewed', 'dismissed')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (comment_id, reported_by_user_id),
    FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE,
    FOREIGN KEY (reported_by_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS comment_reports_status_index
    ON comment_reports (status, created_at, id);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id INTEGER NOT NULL PRIMARY KEY,
    question_reminders_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (question_reminders_enabled IN (0, 1)),
    question_reminder_time TEXT NOT NULL DEFAULT '09:00'
        CHECK (
            question_reminder_time GLOB '[01][0-9]:[0-5][0-9]' OR
            question_reminder_time GLOB '2[0-3]:[0-5][0-9]'
        ),
    comments_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (comments_enabled IN (0, 1)),
    likes_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (likes_enabled IN (0, 1)),
    family_activity_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (family_activity_enabled IN (0, 1)),
    quiet_start TEXT NULL,
    quiet_end TEXT NULL,
    timezone TEXT NULL,
    mute_until TEXT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CHECK (
        quiet_start IS NULL OR
        quiet_start GLOB '[01][0-9]:[0-5][0-9]' OR
        quiet_start GLOB '2[0-3]:[0-5][0-9]'
    ),
    CHECK (
        quiet_end IS NULL OR
        quiet_end GLOB '[01][0-9]:[0-5][0-9]' OR
        quiet_end GLOB '2[0-3]:[0-5][0-9]'
    )
);

CREATE TABLE IF NOT EXISTS notification_reminder_dispatches (
    user_id INTEGER NOT NULL,
    local_date TEXT NOT NULL,
    reminder_time TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'reserved'
        CHECK (status IN ('reserved', 'delivered', 'failed')),
    delivered_count INTEGER NOT NULL DEFAULT 0,
    failed_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, local_date),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS notification_reminder_dispatch_date_index
    ON notification_reminder_dispatches (local_date, status, user_id);

CREATE TABLE IF NOT EXISTS phone_enrollment_challenges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    request_id TEXT NOT NULL UNIQUE,
    phone_e164 TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS phone_enrollment_user_created_index
    ON phone_enrollment_challenges (user_id, created_at);
CREATE INDEX IF NOT EXISTS phone_enrollment_expiry_index
    ON phone_enrollment_challenges (expires_at);

CREATE TABLE IF NOT EXISTS device_recovery_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    code_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    consumed_at TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS device_recovery_user_expiry_index
    ON device_recovery_codes (user_id, expires_at);

CREATE TABLE IF NOT EXISTS account_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_user_id INTEGER NULL,
    family_id INTEGER NULL,
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id TEXT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS account_audit_actor_index
    ON account_audit_log (actor_user_id, created_at, id);
CREATE INDEX IF NOT EXISTS account_audit_family_index
    ON account_audit_log (family_id, created_at, id);
