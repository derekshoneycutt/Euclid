SELECT r.exercise_id, r.reference, r.identity_retired,
    EXISTS (
        SELECT 1 FROM builtin_exercise AS e
        WHERE e.exercise_id = r.exercise_id
    ) AS identity_live,
    EXISTS (
        SELECT 1 FROM builtin_exercise AS e
        WHERE e.reference = r.reference
    ) AS reference_live
FROM retired_exercise_reference AS r ORDER BY r.reference;
