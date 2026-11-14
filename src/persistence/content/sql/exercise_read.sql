SELECT exercise_id, animation_id, reference, title, display_order, instructions
FROM builtin_exercise
WHERE exercise_id = ?1;
