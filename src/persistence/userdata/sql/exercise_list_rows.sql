SELECT exercise_id, animation_id, reference, title
FROM user_exercise
WHERE (?1 IS NULL OR animation_id = ?1)
ORDER BY title COLLATE BINARY, exercise_id
LIMIT ?2 OFFSET ?3;
