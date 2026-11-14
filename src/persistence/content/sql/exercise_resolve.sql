SELECT exercise_id, animation_id, reference, title, display_order
FROM builtin_exercise
WHERE (?1 = 1 AND reference = ?2)
    OR (?1 = 2 AND exercise_id = ?2);
