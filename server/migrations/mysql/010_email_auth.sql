ALTER TABLE users ADD COLUMN email_address VARCHAR(254) CHARACTER SET ascii COLLATE ascii_bin NULL;
ALTER TABLE users ADD COLUMN email_verified_at DATETIME NULL;
CREATE UNIQUE INDEX users_email_unique ON users (email_address);

CREATE TABLE IF NOT EXISTS email_otp_challenges (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    request_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    user_id BIGINT UNSIGNED NULL,
    email_address VARCHAR(254) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX email_otp_expiry_index ON email_otp_challenges (expires_at);

CREATE TABLE IF NOT EXISTS email_enrollment_challenges (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    request_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    user_id BIGINT UNSIGNED NOT NULL,
    email_address VARCHAR(254) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX email_enrollment_user_index ON email_enrollment_challenges (user_id, created_at);
CREATE INDEX email_enrollment_expiry_index ON email_enrollment_challenges (expires_at);
