"""Checked reference to one reservation of a native animation tick slot."""
struct AnimationTickSlotHandle
    index::Int32
    reservation_generation::UInt64
end

"""Lifecycle operation serialized by the animation supervisor."""
@enum AnimationLifecycleKind::Int32 begin
    AnimationActivate = 1
    AnimationReset = 2
    AnimationStop = 3
    AnimationReload = 4
end

"""Stable reason reported when animation actor policy rejects an operation."""
@enum AnimationFailureReason::Int32 begin
    AnimationNoFailure = 0
    AnimationNotReady = 1
    AnimationLifecycleBusy = 2
    AnimationStaleRuntime = 3
    AnimationStaleGeneration = 4
    AnimationStaleActor = 5
    AnimationStaleSequence = 6
    AnimationStaleSlot = 7
    AnimationDuplicateRequest = 8
    AnimationMailboxFull = 9
    AnimationProgramRejected = 10
    AnimationProgramFailed = 11
    AnimationNativeCommandRejected = 12
end

"""Correlated request identity isolated from other actor protocol domains."""
struct AnimationRequestKey
    request_id::UInt64
end

"""Private correlation used while the supervisor retires its active child."""
struct AnimationSupervisorShutdownKey end

"""Request activation of one UUID from the committed runtime generation."""
struct ActivateAnimation
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    state_ptr::Ptr{Cvoid}
end

"""Adopt one already-entered native animation without replaying its entry callback."""
struct AdoptActiveAnimation
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    state_ptr::Ptr{Cvoid}
    implementation::Any
end

"""Report the exact actor identity assigned to an adopted native animation."""
struct ActiveAnimationAdopted
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    program_actor::Union{Nothing,EuclidActorRuntime.ActorId}
    succeeded::Bool
    reason::AnimationFailureReason
end

"""Request a reset of the active animation generation."""
struct ResetAnimation
    request_id::UInt64
    runtime_generation::UInt64
    current_animation_generation::UInt64
    target_animation_generation::UInt64
    program_actor::EuclidActorRuntime.ActorId
end

"""Request one checked tick of the active animation program."""
struct TickAnimation
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    program_actor::EuclidActorRuntime.ActorId
    sequence::UInt64
    slot::AnimationTickSlotHandle
    dt::Float32
end

"""Request orderly retirement of the active animation program."""
struct StopAnimation
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    program_actor::EuclidActorRuntime.ActorId
end

"""Request adoption of one newly committed runtime generation and loader."""
struct ReloadAnimation{F}
    request_id::UInt64
    current_runtime_generation::UInt64
    candidate_runtime_generation::UInt64
    current_animation_generation::UInt64
    target_animation_generation::UInt64
    animation_id::UUID
    load_implementation::F
end

"""Acknowledge one native reset command emitted during a lifecycle transaction."""
struct NativeAnimationStateReset
    request_id::UInt64
    accepted::Bool
end

"""Request native reset before a stopped program is activated again."""
struct ResetNativeAnimationState
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
end

"""Correlated terminal result for one animation lifecycle request."""
struct AnimationLifecycleCompleted
    request_id::UInt64
    kind::AnimationLifecycleKind
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::Union{Nothing,UUID}
    succeeded::Bool
    reason::AnimationFailureReason
end

"""Correlated terminal result for one animation tick request."""
struct AnimationTickCompleted
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    program_actor::EuclidActorRuntime.ActorId
    sequence::UInt64
    slot::AnimationTickSlotHandle
    succeeded::Bool
    reason::AnimationFailureReason
end

"""Current stage of one exclusive supervisor lifecycle transaction."""
@enum AnimationLifecycleStage begin
    AnimationProgramStopping
    AnimationNativeResetPending
    AnimationProgramActivating
    AnimationProgramRestoring
end

"""Bounded state retained while one lifecycle request crosses actor turns."""
mutable struct AnimationLifecycleTransaction
    request_id::UInt64
    kind::AnimationLifecycleKind
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::Union{Nothing,UUID}
    state_ptr::Ptr{Cvoid}
    actor::Union{Nothing,EuclidActorRuntime.ActorId}
    stage::AnimationLifecycleStage
    candidate_runtime_generation::UInt64
    candidate_loader::Any
    candidate_implementation::Any
    previous_loader::Any
    previous_implementation::Any
    previous_animation_id::Union{Nothing,UUID}
    previous_animation_generation::UInt64
    rollback_reason::AnimationFailureReason
end
