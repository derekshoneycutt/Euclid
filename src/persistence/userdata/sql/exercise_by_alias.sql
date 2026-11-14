SELECT exercise_id, animation_id, reference, title, instructions
FROM user_exercise
WHERE reference = ?1;
