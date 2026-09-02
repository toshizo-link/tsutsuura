CREATE TABLE IF NOT EXISTS managed_profiles (
    user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    family_id BIGINT UNSIGNED NOT NULL,
    created_by_user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY managed_profiles_family_index (family_id, created_at),
    KEY managed_profiles_manager_index (created_by_user_id),
    CONSTRAINT managed_profiles_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT managed_profiles_family_fk FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE CASCADE,
    CONSTRAINT managed_profiles_manager_fk FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_pairings (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    family_id BIGINT UNSIGNED NOT NULL,
    managed_user_id BIGINT UNSIGNED NOT NULL,
    created_by_user_id BIGINT UNSIGNED NOT NULL,
    code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    revoked_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY device_pairings_code_unique (code_hash),
    UNIQUE KEY device_pairings_token_unique (token_hash),
    KEY device_pairings_family_index (family_id, created_at),
    KEY device_pairings_member_index (managed_user_id, created_at),
    KEY device_pairings_expiry_index (expires_at),
    CONSTRAINT device_pairings_family_fk FOREIGN KEY (family_id) REFERENCES families (id) ON DELETE CASCADE,
    CONSTRAINT device_pairings_member_fk FOREIGN KEY (managed_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT device_pairings_creator_fk FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
