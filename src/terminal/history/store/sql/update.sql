UPDATE temp.terminal_history
SET source = ?1,
    mode = ?2,
    source_revision = ?3
WHERE submission_id = ?4
  AND source_revision = ?5
RETURNING submission_id;
