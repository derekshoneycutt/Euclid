SELECT EXISTS (
    SELECT 1
    FROM retired_exercise_reference
    WHERE (?1 = 1 AND reference = ?2)
        OR (?1 = 2 AND identity_retired = 1 AND exercise_id = ?2)
);
