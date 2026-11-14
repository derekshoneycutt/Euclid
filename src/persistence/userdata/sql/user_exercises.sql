CREATE TABLE user_exercise (
    exercise_id BLOB PRIMARY KEY NOT NULL
        CHECK (
            length(exercise_id) = 16
            AND exercise_id <> X'00000000000000000000000000000000'
        ),
    animation_id BLOB NOT NULL
        CHECK (
            length(animation_id) = 16
            AND animation_id <> X'00000000000000000000000000000000'
        ),
    reference TEXT NOT NULL UNIQUE
        CHECK (
            length(CAST(reference AS BLOB)) BETWEEN 1 AND 16
            AND instr(reference, char(0)) = 0
            AND reference NOT GLOB '*[^a-z0-9_-]*'
        ),
    title TEXT NOT NULL
        CHECK (
            length(CAST(title AS BLOB)) BETWEEN 1 AND 256
            AND instr(title, char(0)) = 0
        ),
    instructions TEXT NOT NULL
        CHECK (
            length(CAST(instructions AS BLOB)) BETWEEN 1 AND 32768
            AND instr(instructions, char(0)) = 0
        )
) STRICT, WITHOUT ROWID;

CREATE TABLE user_exercise_retired_reference (
    reference TEXT PRIMARY KEY NOT NULL
        CHECK (
            length(CAST(reference AS BLOB)) BETWEEN 1 AND 16
            AND instr(reference, char(0)) = 0
            AND reference NOT GLOB '*[^a-z0-9_-]*'
        ),
    exercise_id BLOB NOT NULL
        CHECK (
            length(exercise_id) = 16
            AND exercise_id <> X'00000000000000000000000000000000'
        ),
    identity_retired INTEGER NOT NULL CHECK (identity_retired IN (0, 1))
) STRICT, WITHOUT ROWID;

CREATE TRIGGER user_exercise_reject_reserved_reference_insert
BEFORE INSERT ON user_exercise
WHEN EXISTS (
    SELECT 1 FROM user_exercise_retired_reference AS retired
    WHERE retired.reference = NEW.reference
)
BEGIN
    SELECT RAISE(ABORT, 'exercise reference retired');
END;

CREATE TRIGGER user_exercise_reject_reserved_identity_insert
BEFORE INSERT ON user_exercise
WHEN EXISTS (
    SELECT 1 FROM user_exercise_retired_reference AS retired
    WHERE retired.exercise_id = NEW.exercise_id
)
BEGIN
    SELECT RAISE(ABORT, 'exercise identity retired');
END;

CREATE TRIGGER user_exercise_reject_reserved_reference_update
BEFORE UPDATE OF reference ON user_exercise
WHEN NEW.reference <> OLD.reference
    AND EXISTS (
        SELECT 1 FROM user_exercise_retired_reference AS retired
        WHERE retired.reference = NEW.reference
    )
BEGIN
    SELECT RAISE(ABORT, 'exercise reference retired');
END;

CREATE TRIGGER user_exercise_reject_identity_update
BEFORE UPDATE OF exercise_id ON user_exercise
BEGIN
    SELECT RAISE(ABORT, 'exercise identity is immutable');
END;
