SELECT exercise_id, animation_id, reference, title, display_order
FROM builtin_exercise
WHERE animation_id = ?1
ORDER BY display_order, exercise_id
LIMIT ?2 OFFSET ?3;
