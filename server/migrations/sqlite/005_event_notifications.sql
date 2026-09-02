CREATE TABLE IF NOT EXISTS notification_event_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL
        CHECK (event_type IN ('answer_submitted', 'answer_liked', 'comment_added')),
    category TEXT NOT NULL
        CHECK (category IN ('familyActivity', 'likes', 'comments')),
    family_id INTEGER NOT NULL,
    actor_user_id INTEGER NOT NULL,
    recipient_user_id INTEGER NOT NULL,
    answer_id INTEGER NOT NULL,
    comment_id INTEGER NULL,
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 500),
    data_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'delivered', 'skipped', 'retry', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at TEXT NULL,
    claim_token TEXT NULL,
    completed_at TEXT NULL,
    provider_delivered INTEGER NOT NULL DEFAULT 0 CHECK (provider_delivered >= 0),
    provider_failed INTEGER NOT NULL DEFAULT 0 CHECK (provider_failed >= 0),
    last_error TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (actor_user_id <> recipient_user_id),
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (family_id, recipient_user_id)
        REFERENCES family_members (family_id, user_id) ON DELETE CASCADE,
    FOREIGN KEY (answer_id) REFERENCES answers (id) ON DELETE CASCADE,
    FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS notification_event_outbox_due_index
    ON notification_event_outbox (status, available_at, id);
CREATE INDEX IF NOT EXISTS notification_event_outbox_recipient_index
    ON notification_event_outbox (recipient_user_id, created_at, id);
