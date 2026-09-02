ALTER TABLE device_pairings
    ADD COLUMN activation_key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN activation_response_encrypted TEXT NULL,
    ADD COLUMN activation_replay_expires_at DATETIME NULL,
    ADD UNIQUE KEY device_pairings_activation_key_unique (activation_key_hash);

ALTER TABLE device_recovery_codes
    ADD COLUMN redemption_key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN redemption_response_encrypted TEXT NULL,
    ADD COLUMN redemption_replay_expires_at DATETIME NULL,
    ADD UNIQUE KEY device_recovery_redemption_key_unique (redemption_key_hash);

ALTER TABLE phone_otp_challenges
    ADD COLUMN verification_key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN verification_response_encrypted TEXT NULL,
    ADD COLUMN verification_replay_expires_at DATETIME NULL,
    ADD UNIQUE KEY phone_otp_verification_key_unique (verification_key_hash);

ALTER TABLE phone_enrollment_challenges
    ADD COLUMN verification_key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN verification_response_encrypted TEXT NULL,
    ADD COLUMN verification_replay_expires_at DATETIME NULL,
    ADD UNIQUE KEY phone_enrollment_verification_key_unique (verification_key_hash);

CREATE TABLE IF NOT EXISTS comment_mutation_receipts (
    key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    response_encrypted TEXT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY comment_mutation_receipts_key_unique (key_hash),
    KEY comment_mutation_receipts_expiry_index (expires_at),
    CONSTRAINT comment_mutation_receipts_user_fk
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS setup_mutation_receipts (
    key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    actor_user_id BIGINT UNSIGNED NULL,
    request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    response_encrypted TEXT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY setup_mutation_receipts_key_unique (key_hash),
    KEY setup_mutation_receipts_expiry_index (expires_at),
    CONSTRAINT setup_mutation_receipts_actor_fk
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS otp_mutation_receipts (
    key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    actor_user_id BIGINT UNSIGNED NULL,
    request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    outcome_encrypted TEXT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY otp_mutation_receipts_key_unique (key_hash),
    KEY otp_mutation_receipts_expiry_index (expires_at),
    CONSTRAINT otp_mutation_receipts_actor_fk
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS lifecycle_mutation_receipts (
    key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    operation VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    result_json TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY lifecycle_mutation_receipts_key_unique (key_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
