INSERT INTO user_setting (
    namespace, key, value_type, integer_value, text_value
)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT (namespace, key) DO UPDATE SET
    value_type = excluded.value_type,
    integer_value = excluded.integer_value,
    text_value = excluded.text_value
