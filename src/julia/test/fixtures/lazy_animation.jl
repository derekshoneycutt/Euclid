module LazyAnimationFixture

using UUIDs

const AnimationId = UUID("683b096d-5f64-50d2-9853-df907ca19075")

"""Return true for the fixture animation's supported operation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    return state_ptr == C_NULL && operation == Int32(2) && dt == 0.25f0
end

end

AnimationCatalog.animation(
    LazyAnimationFixture.AnimationId, LazyAnimationFixture.animation_entry)
