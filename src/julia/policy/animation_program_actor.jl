"""Program command mapped to one existing animation entry operation."""
struct AnimationProgramCommand
    request_key::Any
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    animation_id::UUID
    operation::Int32
    sequence::UInt64
    slot::Union{Nothing,AnimationTickSlotHandle}
    dt::Float32
end

"""Successful internal result returned to the persistent supervisor."""
struct AnimationProgramCompleted
    actor::EuclidActorRuntime.ActorId
    command::AnimationProgramCommand
end

"""Exception raised when a compatibility entry rejects an operation."""
struct AnimationProgramRejectedError <: Exception
    operation::Int32
end

"""One active actor adapting the legacy animation-entry function contract."""
mutable struct CompatibilityAnimationProgram
    supervisor::EuclidActorRuntime.ActorId
    animation_id::UUID
    entry::Function
    state_ptr::Ptr{Cvoid}
    runtime_generation::UInt64
    animation_generation::UInt64
    last_sequence::UInt64
    active::Bool
end

"""Validate immutable program identity before invoking compatibility code."""
function validate_program_identity(
    program::CompatibilityAnimationProgram,
    command::AnimationProgramCommand)::Nothing
    command.runtime_generation == program.runtime_generation ||
        throw(ArgumentError("stale animation runtime generation"))
    command.animation_generation == program.animation_generation ||
        throw(ArgumentError("stale animation generation"))
    command.animation_id == program.animation_id ||
        throw(ArgumentError("stale animation UUID"))
    return nothing
end

"""Validate active state and tick metadata before invoking program code."""
function validate_program_operation(
    program::CompatibilityAnimationProgram,
    command::AnimationProgramCommand)::Nothing
    command.operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER &&
        program.active && throw(ArgumentError("animation already active"))
    command.operation != OdinJuliaBridge.ANIMATION_OPERATION_ENTER &&
        !program.active && throw(ArgumentError("animation is not active"))
    if command.operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        command.sequence > program.last_sequence ||
            throw(ArgumentError("stale animation tick sequence"))
        slot = command.slot
        slot isa AnimationTickSlotHandle && slot.index >= 0 &&
            slot.reservation_generation > 0 ||
            throw(ArgumentError("stale animation tick slot"))
    end
    return nothing
end

"""Validate every program command before invoking compatibility code."""
function validate_program_command(
    program::CompatibilityAnimationProgram,
    command::AnimationProgramCommand)::Nothing
    validate_program_identity(program, command)
    validate_program_operation(program, command)
    return nothing
end

"""Invoke one legacy animation entry and report its correlated success."""
function EuclidActorRuntime.receive!(
    program::CompatibilityAnimationProgram,
    context::EuclidActorRuntime.ActorContext,
    command::AnimationProgramCommand)::Nothing
    pending = get(context.runtime.pending_requests,
        command.request_key, nothing)
    pending !== nothing && pending.owner == context.self || return nothing
    validate_program_command(program, command)
    succeeded = Base.invokelatest(
        program.entry, program.state_ptr, command.operation, command.dt)
    succeeded || throw(AnimationProgramRejectedError(command.operation))
    program.active = command.operation != OdinJuliaBridge.ANIMATION_OPERATION_EXIT
    command.operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK &&
        (program.last_sequence = command.sequence)
    EuclidActorRuntime.resolve_request!(
        context.runtime, command.request_key)
    EuclidActorRuntime.send!(context, program.supervisor,
        AnimationProgramCompleted(context.self, command)) ===
        EuclidActorRuntime.SendAccepted ||
        error("animation supervisor rejected program completion")
    command.operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT &&
        EuclidActorRuntime.stop!(context)
    return nothing
end
