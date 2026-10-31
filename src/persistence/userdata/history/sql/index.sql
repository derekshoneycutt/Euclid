CREATE INDEX temp.terminal_history_persistent_entry
    ON terminal_history(persistent_entry_id)
    WHERE persistent_entry_id IS NOT NULL;
