SELECT EXISTS(
    SELECT 1
    FROM main.sqlite_schema
    WHERE type = 'table' AND name = 'user_terminal_history'
);
