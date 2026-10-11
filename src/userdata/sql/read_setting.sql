SELECT value_type, integer_value, text_value
FROM user_setting
WHERE namespace = ?1 AND key = ?2
