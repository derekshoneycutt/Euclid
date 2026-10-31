SELECT submission_id, COALESCE(substr(CAST(source AS BLOB), 1, ?7), X'') AS source_prefix,
       COALESCE(persistent_entry_id, 0), mode, submitted_at_unix_ms,
       terminal_generation, source_revision, 0 AS scope_rank,
       submission_id AS source_id, length(CAST(source AS BLOB)) AS source_bytes
FROM temp.terminal_history
WHERE (?1 = 0 OR submission_id > ?4)
  AND (?8 = 0 OR history_matches(source, mode, ?6))
ORDER BY submission_id ASC
LIMIT ?5;
