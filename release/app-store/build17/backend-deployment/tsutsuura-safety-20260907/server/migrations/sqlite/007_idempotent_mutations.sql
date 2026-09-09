ALTER TABLE device_pairings
    ADD COLUMN activation_key_hash TEXT NULL;

ALTER TABLE device_pairings
    ADD COLUMN activation_response_encrypted TEXT NULL;

ALTER TABLE device_pairings
    ADD COLUMN activation_replay_expires_at TEXT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS device_pairings_activation_key_unique
    ON device_pairings (activation_key_hash)
    WHERE activation_key_hash IS NOT NULL;

ALTER TABLE device_recovery_codes
    ADD COLUMN redemption_key_hash TEXT NULL;

ALTER TABLE device_recovery_codes
    ADD COLUMN redemption_response_encrypted TEXT NULL;

ALTER TABLE device_recovery_codes
    ADD COLUMN redemption_replay_expires_at TEXT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS device_recovery_redemption_key_unique
    ON device_recovery_codes (redemption_key_hash)
    WHERE redemption_key_hash IS NOT NULL;

ALTER TABLE phone_otp_challenges
    ADD COLUMN verification_key_hash TEXT NULL;

ALTER TABLE phone_otp_challenges
    ADD COLUMN verification_response_encrypted TEXT NULL;

ALTER TABLE phone_otp_challenges
    ADD COLUMN verification_replay_expires_at TEXT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS phone_otp_verification_key_unique
    ON phone_otp_challenges (verification_key_hash)
    WHERE verification_key_hash IS NOT NULL;

ALTER TABLE phone_enrollment_challenges
    ADD COLUMN verification_key_hash TEXT NULL;

ALTER TABLE phone_enrollment_challenges
    ADD COLUMN verification_response_encrypted TEXT NULL;

ALTER TABLE phone_enrollment_challenges
    ADD COLUMN verification_replay_expires_at TEXT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS phone_enrollment_verification_key_unique
    ON phone_enrollment_challenges (verification_key_hash)
    WHERE verification_key_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS comment_mutation_receipts (
    key_hash TEXT NOT NULL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    request_fingerprint TEXT NOT NULL,
    response_encrypted TEXT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS comment_mutation_receipts_key_unique
    ON comment_mutation_receipts (key_hash);
CREATE INDEX IF NOT EXISTS comment_mutation_receipts_expiry_index
    ON comment_mutation_receipts (expires_at);

CREATE TABLE IF NOT EXISTS setup_mutation_receipts (
    key_hash TEXT NOT NULL PRIMARY KEY,
    operation TEXT NOT NULL,
    actor_user_id INTEGER NULL,
    request_fingerprint TEXT NOT NULL,
    response_encrypted TEXT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS setup_mutation_receipts_key_unique
    ON setup_mutation_receipts (key_hash);
CREATE INDEX IF NOT EXISTS setup_mutation_receipts_expiry_index
    ON setup_mutation_receipts (expires_at);

CREATE TABLE IF NOT EXISTS otp_mutation_receipts (
    key_hash TEXT NOT NULL PRIMARY KEY,
    operation TEXT NOT NULL,
    actor_user_id INTEGER NULL,
    request_fingerprint TEXT NOT NULL,
    outcome_encrypted TEXT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS otp_mutation_receipts_key_unique
    ON otp_mutation_receipts (key_hash);
CREATE INDEX IF NOT EXISTS otp_mutation_receipts_expiry_index
    ON otp_mutation_receipts (expires_at);

CREATE TABLE IF NOT EXISTS lifecycle_mutation_receipts (
    key_hash TEXT NOT NULL PRIMARY KEY,
    operation TEXT NOT NULL,
    result_json TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS lifecycle_mutation_receipts_key_unique
    ON lifecycle_mutation_receipts (key_hash);
