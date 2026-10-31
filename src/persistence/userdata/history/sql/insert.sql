INSERT INTO temp.terminal_history (
    submission_id, persistent_entry_id, source, mode, submitted_at_unix_ms,
    terminal_generation, source_revision
) VALUES (?1, NULL, ?2, ?3, ?4, ?5, ?6);
