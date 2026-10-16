-- Apologion leaderboard database (SQLite).
-- Created automatically by app.py the first time it runs.

CREATE TABLE IF NOT EXISTS churches (
    id          TEXT PRIMARY KEY,            -- e.g. "fpc-haines-city" (same id the game uses)
    name        TEXT NOT NULL,
    city        TEXT NOT NULL DEFAULT '',
    region      TEXT NOT NULL DEFAULT '',    -- state / province / region
    country     TEXT NOT NULL DEFAULT '',
    approved    INTEGER NOT NULL DEFAULT 0,  -- 0 = waiting for a moderator, 1 = visible to everyone
    submitter_ip TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS players (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    token       TEXT NOT NULL,               -- secret the game keeps; needed to post scores
    name        TEXT NOT NULL,
    church_id   TEXT REFERENCES churches(id),
    total       INTEGER NOT NULL DEFAULT 0,  -- lifetime enemies defeated
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS scores (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id   INTEGER NOT NULL REFERENCES players(id),
    delta       INTEGER NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS scores_player_time ON scores(player_id, created_at);
CREATE INDEX IF NOT EXISTS players_church ON players(church_id);

-- The two preset churches (already approved)
INSERT OR IGNORE INTO churches (id, name, city, region, country, approved) VALUES
    ('christs-church-on-the-move', 'Christ''s Church on the Move', 'Lake Wales', 'Florida', 'USA', 1),
    ('fpc-haines-city', 'FPC Haines City', 'Haines City', 'Florida', 'USA', 1);
