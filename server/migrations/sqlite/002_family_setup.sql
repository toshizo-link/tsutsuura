CREATE TABLE IF NOT EXISTS managed_profiles (
    user_id INTEGER NOT NULL PRIMARY KEY,
    family_id INTEGER NOT NULL,
    created_by_user_id INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS managed_profiles_family_index
    ON managed_profiles (family_id, created_at);
CREATE INDEX IF NOT EXISTS managed_profiles_manager_index
    ON managed_profiles (created_by_user_id);

CREATE TABLE IF NOT EXISTS device_pairings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    family_id INTEGER NOT NULL,
    managed_user_id INTEGER NOT NULL,
    created_by_user_id INTEGER NOT NULL,
    code_hash TEXT NOT NULL UNIQUE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    consumed_at TEXT NULL,
    revoked_at TEXT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE CASCADE,
    FOREIGN KEY (managed_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS device_pairings_family_index
    ON device_pairings (family_id, created_at);
CREATE INDEX IF NOT EXISTS device_pairings_member_index
    ON device_pairings (managed_user_id, created_at);
CREATE INDEX IF NOT EXISTS device_pairings_expiry_index
    ON device_pairings (expires_at);
