ALTER TABLE users ADD COLUMN email_address TEXT NULL;
ALTER TABLE users ADD COLUMN email_verified_at TEXT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique ON users (email_address);

CREATE TABLE IF NOT EXISTS email_otp_challenges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL UNIQUE,
    user_id INTEGER NULL,
    email_address TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS email_otp_expiry_index ON email_otp_challenges (expires_at);

CREATE TABLE IF NOT EXISTS email_enrollment_challenges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL UNIQUE,
    user_id INTEGER NOT NULL,
    email_address TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS email_enrollment_user_index ON email_enrollment_challenges (user_id, created_at);
CREATE INDEX IF NOT EXISTS email_enrollment_expiry_index ON email_enrollment_challenges (expires_at);
