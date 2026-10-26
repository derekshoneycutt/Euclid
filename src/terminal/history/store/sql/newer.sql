SELECT submission_id, source, mode, submitted_at_unix_ms,
       terminal_generation, source_revision,
       length(CAST(source AS BLOB))
FROM temp.terminal_history
WHERE submission_id > ?1
ORDER BY submission_id ASC
LIMIT 1;
