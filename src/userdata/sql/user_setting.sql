CREATE TABLE user_setting (
    namespace TEXT NOT NULL,
    key TEXT NOT NULL,
    value_type TEXT NOT NULL,
    integer_value INTEGER,
    text_value TEXT,
    PRIMARY KEY (namespace, key),
    CHECK (
        length(CAST(namespace AS BLOB)) BETWEEN 1 AND 64
        AND instr(namespace, char(0)) = 0
    ),
    CHECK (
        length(CAST(key AS BLOB)) BETWEEN 1 AND 64
        AND instr(key, char(0)) = 0
    ),
    CHECK (
        (
            value_type = 'boolean'
            AND integer_value IS NOT NULL
            AND integer_value IN (0, 1)
            AND text_value IS NULL
        )
        OR (
            value_type = 'integer'
            AND integer_value IS NOT NULL
            AND text_value IS NULL
        )
        OR (
            value_type = 'text'
            AND integer_value IS NULL
            AND text_value IS NOT NULL
            AND length(CAST(text_value AS BLOB)) <= 64
            AND instr(text_value, char(0)) = 0
        )
    )
) STRICT, WITHOUT ROWID;
