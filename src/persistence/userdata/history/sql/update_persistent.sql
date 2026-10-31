UPDATE main.user_terminal_history
SET source = ?1,
    mode = ?2,
    source_revision = ?3
WHERE entry_id = ?4
  AND source_revision = ?5
RETURNING entry_id;
