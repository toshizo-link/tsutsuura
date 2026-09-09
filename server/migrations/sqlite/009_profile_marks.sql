ALTER TABLE users ADD COLUMN avatar_mark TEXT NULL
    CHECK (avatar_mark IS NULL OR (length(avatar_mark) = 256 AND avatar_mark NOT GLOB '*[^01]*'));
ALTER TABLE families ADD COLUMN name_tracks_owner INTEGER NOT NULL DEFAULT 0
    CHECK (name_tracks_owner IN (0, 1));

-- Repair the app-generated names, including names left behind by an older
-- client after an organizer renamed themselves. Explicit family renaming
-- disables this link for future profile updates.
UPDATE families SET name_tracks_owner = 1 WHERE name LIKE '%さんの家族';
UPDATE families SET name = (
    SELECT substr(u.display_name, 1, 75) || 'さんの家族'
    FROM family_members fm JOIN users u ON u.id = fm.user_id
    WHERE fm.family_id = families.id AND fm.role = 'owner' LIMIT 1
) WHERE name_tracks_owner = 1 AND EXISTS (
    SELECT 1 FROM family_members fm WHERE fm.family_id = families.id AND fm.role = 'owner'
);
