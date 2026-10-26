INSERT INTO temp.terminal_history (
    submission_id, source, mode, submitted_at_unix_ms,
    terminal_generation, source_revision
) VALUES (?1, ?2, ?3, ?4, ?5, ?6);
