ALTER TABLE users ADD COLUMN avatar_mark VARCHAR(256) CHARACTER SET ascii COLLATE ascii_bin NULL;
ALTER TABLE families ADD COLUMN name_tracks_owner TINYINT(1) NOT NULL DEFAULT 0;

UPDATE families SET name_tracks_owner = 1 WHERE name LIKE '%さんの家族';
UPDATE families f
JOIN family_members fm ON fm.family_id = f.id AND fm.role = 'owner'
JOIN users u ON u.id = fm.user_id
SET f.name = CONCAT(LEFT(u.display_name, 75), 'さんの家族')
WHERE f.name_tracks_owner = 1;
