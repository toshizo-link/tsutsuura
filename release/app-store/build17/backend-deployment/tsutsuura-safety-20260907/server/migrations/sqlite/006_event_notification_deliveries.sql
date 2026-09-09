CREATE TABLE IF NOT EXISTS notification_event_deliveries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    outbox_id INTEGER NOT NULL,
    push_token_id INTEGER NULL,
    token_was_present INTEGER NOT NULL DEFAULT 1
        CHECK (token_was_present IN (0, 1)),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'delivered', 'skipped', 'retry', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at TEXT NULL,
    claim_token TEXT NULL,
    completed_at TEXT NULL,
    provider_delivered INTEGER NOT NULL DEFAULT 0 CHECK (provider_delivered IN (0, 1)),
    provider_failed INTEGER NOT NULL DEFAULT 0 CHECK (provider_failed >= 0),
    last_error TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (outbox_id, push_token_id),
    FOREIGN KEY (outbox_id) REFERENCES notification_event_outbox (id) ON DELETE CASCADE,
    FOREIGN KEY (push_token_id) REFERENCES push_tokens (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS notification_event_deliveries_due_index
    ON notification_event_deliveries (status, available_at, id);
CREATE INDEX IF NOT EXISTS notification_event_deliveries_outbox_index
    ON notification_event_deliveries (outbox_id, status, id);
CREATE INDEX IF NOT EXISTS notification_event_deliveries_token_index
    ON notification_event_deliveries (push_token_id);

-- Preserve active rows written before this migration. Each currently
-- registered token receives an independent delivery state. A NULL sentinel
-- records that no token existed at the snapshot so that the event still
-- reaches a terminal, inspectable outcome.
INSERT OR IGNORE INTO notification_event_deliveries
    (outbox_id, push_token_id, token_was_present, status, attempts, available_at)
SELECT outbox.id, token.id, 1,
       CASE WHEN outbox.status IN ('retry', 'processing') THEN 'retry' ELSE 'pending' END,
       outbox.attempts, outbox.available_at
FROM notification_event_outbox outbox
JOIN push_tokens token ON token.user_id = outbox.recipient_user_id
WHERE outbox.status IN ('pending', 'processing', 'retry');

INSERT INTO notification_event_deliveries
    (outbox_id, push_token_id, token_was_present, status, attempts, available_at)
SELECT outbox.id, NULL, 0,
       CASE WHEN outbox.status IN ('retry', 'processing') THEN 'retry' ELSE 'pending' END,
       outbox.attempts, outbox.available_at
FROM notification_event_outbox outbox
WHERE outbox.status IN ('pending', 'processing', 'retry')
  AND NOT EXISTS (
      SELECT 1 FROM notification_event_deliveries delivery
      WHERE delivery.outbox_id = outbox.id
  );
