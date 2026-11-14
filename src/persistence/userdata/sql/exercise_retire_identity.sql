UPDATE user_exercise_retired_reference
SET identity_retired = 1
WHERE exercise_id = ?1;
