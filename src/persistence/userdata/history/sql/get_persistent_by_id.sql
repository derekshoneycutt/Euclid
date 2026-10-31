SELECT entry_id, source, entry_id, mode, submitted_at_unix_ms,
       terminal_generation, source_revision, 1, entry_id,
       length(CAST(source AS BLOB))
FROM main.user_terminal_history
WHERE entry_id = ?1;
