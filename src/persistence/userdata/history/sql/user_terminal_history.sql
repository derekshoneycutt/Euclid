CREATE TABLE user_terminal_history (
    entry_id INTEGER PRIMARY KEY,
    source TEXT NOT NULL
        CHECK (length(CAST(source AS BLOB)) <= 65536),
    mode INTEGER NOT NULL CHECK (mode BETWEEN 0 AND 3),
    submitted_at_unix_ms INTEGER NOT NULL CHECK (submitted_at_unix_ms >= 0),
    terminal_generation INTEGER NOT NULL CHECK (terminal_generation > 0),
    source_revision INTEGER NOT NULL CHECK (source_revision > 0)
) STRICT;
