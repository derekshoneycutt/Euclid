SELECT submission_id, source, COALESCE(persistent_entry_id, 0), mode,
       submitted_at_unix_ms, terminal_generation, source_revision,
       0, submission_id,
       length(CAST(source AS BLOB))
FROM temp.terminal_history
WHERE submission_id = ?1;
