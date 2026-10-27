INSERT INTO main.user_terminal_history (
    source, mode, submitted_at_unix_ms, terminal_generation, source_revision
) VALUES (?1, ?2, ?3, ?4, ?5)
RETURNING entry_id;
