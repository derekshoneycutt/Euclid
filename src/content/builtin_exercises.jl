module BuiltinExercises

using UUIDs

export Exercise, RetiredReference, EXERCISES, RETIRED_REFERENCES

"""One authored built-in exercise with an explicit stable identity."""
struct Exercise
    id::UUID
    animation_id::UUID
    reference::String
    title::String
    display_order::Int
    instructions::String
end

"""A reserved friendly reference retired by a rename or deletion."""
struct RetiredReference
    exercise_id::UUID
    reference::String
    identity_retired::Bool
end

const EXERCISES = Exercise[
    Exercise(
        UUID("a9237c51-c9f6-4d54-8bf5-f8c651906e1c"),
        UUID("76fdebfe-2600-551e-be64-03f1942f4f49"),
        "elements-i-1",
        "Construct an equilateral triangle",
        0,
        "On a given finite straight line to construct an equilateral triangle."),
]

const RETIRED_REFERENCES = RetiredReference[]

end
