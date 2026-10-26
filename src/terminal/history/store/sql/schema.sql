CREATE TEMP TABLE terminal_history (
    submission_id INTEGER PRIMARY KEY CHECK (submission_id > 0),
    source TEXT NOT NULL,
    mode INTEGER NOT NULL,
    submitted_at_unix_ms INTEGER NOT NULL,
    terminal_generation INTEGER NOT NULL CHECK (terminal_generation > 0),
    source_revision INTEGER NOT NULL CHECK (source_revision > 0)
);
