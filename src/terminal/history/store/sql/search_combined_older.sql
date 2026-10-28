WITH history AS (
    SELECT submission_id, source, COALESCE(persistent_entry_id, 0) AS persistent_entry_id,
           mode, submitted_at_unix_ms, terminal_generation, source_revision,
           0 AS scope_rank, submission_id AS source_id
    FROM temp.terminal_history
    UNION ALL
    SELECT 0, source, entry_id, mode, submitted_at_unix_ms,
           terminal_generation, source_revision, 1, entry_id
    FROM main.user_terminal_history AS saved
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp.terminal_history AS session
        WHERE session.persistent_entry_id = saved.entry_id
    )
),
candidate_window AS MATERIALIZED (
    SELECT submission_id, source, persistent_entry_id, mode,
           submitted_at_unix_ms, terminal_generation, source_revision,
           scope_rank, source_id
    FROM history
    WHERE ?1 = 0
       OR submitted_at_unix_ms < ?2
       OR (submitted_at_unix_ms = ?2 AND scope_rank > ?3)
       OR (submitted_at_unix_ms = ?2 AND scope_rank = ?3 AND source_id < ?4)
    ORDER BY submitted_at_unix_ms DESC, scope_rank ASC, source_id DESC
    LIMIT ?5
)
SELECT submission_id, COALESCE(substr(CAST(source AS BLOB), 1, ?7), X'') AS source_prefix,
       persistent_entry_id, mode, submitted_at_unix_ms,
       terminal_generation, source_revision, scope_rank, source_id,
       length(CAST(source AS BLOB)) AS source_bytes,
       (?6 = '' OR instr(source, ?6) > 0) AS matches
FROM candidate_window
ORDER BY submitted_at_unix_ms DESC, scope_rank ASC, source_id DESC;
