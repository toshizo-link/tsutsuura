CREATE TABLE IF NOT EXISTS notification_event_deliveries (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    outbox_id BIGINT UNSIGNED NOT NULL,
    push_token_id BIGINT UNSIGNED NULL,
    token_was_present TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    status ENUM('pending', 'processing', 'delivered', 'skipped', 'retry', 'failed')
        NOT NULL DEFAULT 'pending',
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    available_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at DATETIME NULL,
    claim_token CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    completed_at DATETIME NULL,
    provider_delivered TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    provider_failed INT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY notification_event_delivery_token_unique (outbox_id, push_token_id),
    KEY notification_event_deliveries_due_index (status, available_at, id),
    KEY notification_event_deliveries_outbox_index (outbox_id, status, id),
    KEY notification_event_deliveries_token_index (push_token_id),
    CONSTRAINT notification_event_deliveries_outbox_fk
        FOREIGN KEY (outbox_id) REFERENCES notification_event_outbox (id) ON DELETE CASCADE,
    CONSTRAINT notification_event_deliveries_token_fk
        FOREIGN KEY (push_token_id) REFERENCES push_tokens (id) ON DELETE SET NULL,
    CONSTRAINT notification_event_deliveries_token_presence_check
        CHECK (token_was_present IN (0, 1)),
    CONSTRAINT notification_event_deliveries_provider_delivered_check
        CHECK (provider_delivered IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill active recipient rows created under schema 005. INSERT IGNORE makes
-- an interrupted migration safely resumable for non-NULL token snapshots.
INSERT IGNORE INTO notification_event_deliveries
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
