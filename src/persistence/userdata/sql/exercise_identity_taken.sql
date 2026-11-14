SELECT 1 AS taken FROM user_exercise WHERE exercise_id = ?1
UNION ALL
SELECT 1 AS taken FROM user_exercise_retired_reference WHERE exercise_id = ?1
LIMIT 1;
