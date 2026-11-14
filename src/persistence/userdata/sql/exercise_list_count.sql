SELECT COUNT(*)
FROM user_exercise
WHERE (?1 IS NULL OR animation_id = ?1);
