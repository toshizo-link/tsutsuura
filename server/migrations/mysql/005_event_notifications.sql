CREATE TABLE IF NOT EXISTS notification_event_outbox (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_type ENUM('answer_submitted', 'answer_liked', 'comment_added') NOT NULL,
    category ENUM('familyActivity', 'likes', 'comments') NOT NULL,
    family_id BIGINT UNSIGNED NOT NULL,
    actor_user_id BIGINT UNSIGNED NOT NULL,
    recipient_user_id BIGINT UNSIGNED NOT NULL,
    answer_id BIGINT UNSIGNED NOT NULL,
    comment_id BIGINT UNSIGNED NULL,
    title VARCHAR(120) NOT NULL,
    body VARCHAR(500) NOT NULL,
    data_json LONGTEXT NOT NULL,
    status ENUM('pending', 'processing', 'delivered', 'skipped', 'retry', 'failed')
        NOT NULL DEFAULT 'pending',
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    available_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at DATETIME NULL,
    claim_token CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    completed_at DATETIME NULL,
    provider_delivered INT UNSIGNED NOT NULL DEFAULT 0,
    provider_failed INT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY notification_event_outbox_due_index (status, available_at, id),
    KEY notification_event_outbox_recipient_index (recipient_user_id, created_at, id),
    CONSTRAINT notification_event_outbox_actor_fk
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT notification_event_outbox_recipient_membership_fk
        FOREIGN KEY (family_id, recipient_user_id)
        REFERENCES family_members (family_id, user_id) ON DELETE CASCADE,
    CONSTRAINT notification_event_outbox_answer_fk
        FOREIGN KEY (answer_id) REFERENCES answers (id) ON DELETE CASCADE,
    CONSTRAINT notification_event_outbox_comment_fk
        FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE,
    CONSTRAINT notification_event_outbox_actor_recipient_check
        CHECK (actor_user_id <> recipient_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
