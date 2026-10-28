WITH candidate_window AS MATERIALIZED (
    SELECT submission_id, source,
           COALESCE(persistent_entry_id, 0) AS persistent_entry_id,
           mode, submitted_at_unix_ms, terminal_generation, source_revision
    FROM temp.terminal_history
    WHERE ?1 = 0 OR submission_id < ?4
    ORDER BY submission_id DESC
    LIMIT ?5
)
SELECT submission_id, COALESCE(substr(CAST(source AS BLOB), 1, ?7), X'') AS source_prefix,
       persistent_entry_id, mode, submitted_at_unix_ms,
       terminal_generation, source_revision, 0 AS scope_rank,
       submission_id AS source_id, length(CAST(source AS BLOB)) AS source_bytes,
       (?6 = '' OR instr(source, ?6) > 0) AS matches
FROM candidate_window
ORDER BY submission_id DESC;
