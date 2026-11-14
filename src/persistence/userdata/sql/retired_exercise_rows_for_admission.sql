SELECT retired.exercise_id, retired.reference, retired.identity_retired,
    EXISTS (
        SELECT 1 FROM user_exercise AS exercise
        WHERE exercise.exercise_id = retired.exercise_id
    ) AS identity_live,
    EXISTS (
        SELECT 1 FROM user_exercise AS exercise
        WHERE exercise.reference = retired.reference
    ) AS reference_live
FROM user_exercise_retired_reference AS retired
ORDER BY retired.reference;
