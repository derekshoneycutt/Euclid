SELECT 1 AS state FROM user_exercise WHERE reference = ?1
UNION ALL
SELECT 2 AS state FROM user_exercise_retired_reference WHERE reference = ?1
LIMIT 1;
