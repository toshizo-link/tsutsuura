CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    CHECK (blocker_user_id <> blocked_user_id)
);
CREATE INDEX IF NOT EXISTS user_blocks_reverse_index ON user_blocks(blocked_user_id, blocker_user_id);

CREATE TABLE IF NOT EXISTS answer_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    answer_id INTEGER NOT NULL REFERENCES answers(id) ON DELETE CASCADE,
    reported_by_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL CHECK (reason IN ('spam', 'harassment', 'privacy', 'inappropriate', 'other')),
    details TEXT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (answer_id, reported_by_user_id)
);
CREATE INDEX IF NOT EXISTS answer_reports_status_index ON answer_reports(status, created_at, id);

CREATE TABLE IF NOT EXISTS moderation_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_type TEXT NOT NULL CHECK (report_type IN ('answer', 'comment')),
    report_id INTEGER NOT NULL,
    answer_id INTEGER NULL REFERENCES answers(id) ON DELETE CASCADE,
    comment_id INTEGER NULL REFERENCES comments(id) ON DELETE CASCADE,
    decision TEXT NOT NULL CHECK (decision IN ('remove', 'dismiss')),
    reviewer TEXT NOT NULL,
    note TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (report_type, report_id),
    CHECK ((answer_id IS NOT NULL AND comment_id IS NULL) OR (answer_id IS NULL AND comment_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS moderation_answer_index ON moderation_actions(answer_id, decision);
CREATE INDEX IF NOT EXISTS moderation_comment_index ON moderation_actions(comment_id, decision);
