"""Start the persistent animation-policy root after host construction."""
struct StartAnimationSupervisor end

"""Stop animation-policy admission before the remaining host actors."""
struct StopAnimationSupervisor end

"""Report that the persistent animation-policy root accepted startup."""
struct AnimationSupervisorStarted end

"""Report that the persistent animation-policy root completed shutdown."""
struct AnimationSupervisorStopped end

"""Persistent root state for Julia-owned animation policy."""
mutable struct AnimationSupervisor
    ready::Bool
    stopping::Bool
    active_runtime_generation::UInt64
    active_animation_generation::UInt64
    active_animation_id::Union{Nothing,UUID}
    active_program_actor::Union{Nothing,EuclidActorRuntime.ActorId}
    active_program_adopted::Bool
    active_state_ptr::Ptr{Cvoid}
    implementation_cache::Dict{UUID,Any}
    load_implementation::Any
    lifecycle_transaction::Union{Nothing,AnimationLifecycleTransaction}
    failure::Union{Nothing,EuclidActorRuntime.ActorFailed}
    last_tick_sequence::UInt64
    commands_processed::UInt64
end

"""Create animation policy rooted in one committed runtime generation."""
function AnimationSupervisor(
    runtime_generation::UInt64=UInt64(0),
    load_implementation=(_id -> throw(ArgumentError(
        "animation implementation loader is unavailable"))))
    return AnimationSupervisor(
        false, false, runtime_generation, UInt64(0), nothing, nothing, false, C_NULL,
        Dict{UUID,Any}(), load_implementation, nothing, nothing,
        UInt64(0), UInt64(0))
end

"""Mark the animation-policy root ready to accept later phase protocols."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    _message::StartAnimationSupervisor)::Nothing
    supervisor.stopping && return nothing
    supervisor.ready = true
    supervisor.commands_processed += UInt64(1)
    EuclidActorRuntime.emit!(context, AnimationSupervisorStarted())
    return nothing
end


"""Emit one typed lifecycle result from supervisor-owned transaction data."""
function emit_lifecycle_result!(
    context::EuclidActorRuntime.ActorContext,
    request_id::UInt64,
    kind::AnimationLifecycleKind,
    runtime_generation::UInt64,
    animation_generation::UInt64,
    animation_id::Union{Nothing,UUID},
    succeeded::Bool,
    reason::AnimationFailureReason)::Nothing
    EuclidActorRuntime.emit!(context, AnimationLifecycleCompleted(
        request_id, kind, runtime_generation, animation_generation,
        animation_id, succeeded, reason))
    return nothing
end

"""Complete root shutdown after no active program actor remains."""
function finish_animation_supervisor_shutdown!(
    context::EuclidActorRuntime.ActorContext)::Nothing
    EuclidActorRuntime.emit!(context, AnimationSupervisorStopped())
    EuclidActorRuntime.stop!(context)
    return nothing
end

"""Queue another supervisor shutdown turn after a transaction resolves."""
function resume_animation_supervisor_shutdown!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext)::Nothing
    supervisor.stopping || return nothing
    EuclidActorRuntime.send!(context.runtime, context.self,
        StopAnimationSupervisor()) === EuclidActorRuntime.SendAccepted ||
        error("animation supervisor could not resume shutdown")
    return nothing
end

"""Cache or load one implementation from the active runtime generation."""
function load_animation_implementation!(
    supervisor::AnimationSupervisor,
    animation_id::UUID)
    return get!(supervisor.implementation_cache, animation_id) do
        supervisor.load_implementation(animation_id)
    end
end

"""Register and enqueue one command against its responsible child generation."""
function send_program_command!(
    context::EuclidActorRuntime.ActorContext,
    actor::EuclidActorRuntime.ActorId,
    command::AnimationProgramCommand,
    source)::AnimationFailureReason
    registration = EuclidActorRuntime.register_request!(
        context.runtime, command.request_key, actor; value=source)
    registration === EuclidActorRuntime.RequestRegistered ||
        return AnimationDuplicateRequest
    outcome = EuclidActorRuntime.send!(context.runtime, actor, command)
    outcome === EuclidActorRuntime.SendAccepted && return AnimationNoFailure
    EuclidActorRuntime.resolve_request!(
        context.runtime, command.request_key)
    return outcome === EuclidActorRuntime.SendMailboxFull ?
        AnimationMailboxFull : AnimationStaleActor
end

"""Spawn and activate the program selected by one lifecycle transaction."""
function activate_transaction_program!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    transaction::AnimationLifecycleTransaction)::AnimationFailureReason
    restoring = transaction.stage === AnimationProgramRestoring
    animation_id = restoring ?
        something(transaction.previous_animation_id) :
        something(transaction.animation_id)
    animation_generation = restoring ?
        transaction.previous_animation_generation :
        transaction.animation_generation
    implementation = try
        if restoring
            transaction.previous_implementation
        elseif transaction.candidate_implementation !== nothing
            transaction.candidate_implementation
        else
            load_animation_implementation!(supervisor, animation_id)
        end
    catch exception
        supervisor.failure = EuclidActorRuntime.ActorFailed(
            context.self, exception, transaction)
        return AnimationProgramFailed
    end
    implementation.id == animation_id || return AnimationStaleRuntime
    runtime_generation = transaction.kind === AnimationReload &&
        transaction.stage !== AnimationProgramRestoring ?
        transaction.candidate_runtime_generation : transaction.runtime_generation
    program = CompatibilityAnimationProgram(
        context.self, animation_id, implementation.entry,
        transaction.state_ptr, runtime_generation,
        animation_generation, UInt64(0), false)
    actor = EuclidActorRuntime.spawn!(
        context.runtime, program; supervisor=context.self, mailbox_capacity=1)
    command = AnimationProgramCommand(
        AnimationRequestKey(transaction.request_id), transaction.request_id,
        runtime_generation,
        animation_generation, animation_id,
        OdinJuliaBridge.ANIMATION_OPERATION_ENTER, UInt64(0), nothing, 0.0f0)
    reason = send_program_command!(context, actor, command, transaction)
    if reason !== AnimationNoFailure
        EuclidActorRuntime.stop!(context.runtime, actor)
        return reason
    end
    supervisor.active_program_actor = actor
    supervisor.active_program_adopted = false
    transaction.actor = actor
    restoring || (transaction.stage = AnimationProgramActivating)
    return AnimationNoFailure
end

"""Return the first failed precondition for one activation request."""
function activation_rejection_reason(
    supervisor::AnimationSupervisor,
    request::ActivateAnimation)::AnimationFailureReason
    (!supervisor.ready || supervisor.stopping) && return AnimationNotReady
    supervisor.lifecycle_transaction !== nothing && return AnimationLifecycleBusy
    request.runtime_generation != supervisor.active_runtime_generation &&
        return AnimationStaleRuntime
    request.animation_generation == 0 && return AnimationStaleGeneration
    return AnimationNoFailure
end

"""Return the first failed precondition for native lifecycle adoption."""
function adoption_rejection_reason(
    supervisor::AnimationSupervisor,
    request::AdoptActiveAnimation)::AnimationFailureReason
    (!supervisor.ready || supervisor.stopping) && return AnimationNotReady
    supervisor.lifecycle_transaction !== nothing && return AnimationLifecycleBusy
    if supervisor.failure !== nothing &&
        supervisor.active_runtime_generation == request.runtime_generation &&
        supervisor.active_animation_generation == request.animation_generation &&
        supervisor.active_animation_id == request.animation_id
        return AnimationProgramFailed
    end
    request.implementation.id == request.animation_id || return AnimationStaleRuntime
    return AnimationNoFailure
end

"""Retire an adopted actor that no longer mirrors native lifecycle state."""
function retire_stale_adopted_program!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::AdoptActiveAnimation)
    actor = supervisor.active_program_actor
    actor === nothing && return nothing
    current = supervisor.active_runtime_generation == request.runtime_generation &&
        supervisor.active_animation_generation == request.animation_generation &&
        supervisor.active_animation_id == request.animation_id &&
        EuclidActorRuntime.is_live(context.runtime, actor)
    current && return actor
    EuclidActorRuntime.stop!(context.runtime, actor)
    return nothing
end

"""Adopt native-committed state without replaying the entry callback."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::AdoptActiveAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    reason = adoption_rejection_reason(supervisor, request)
    if reason !== AnimationNoFailure
        EuclidActorRuntime.emit!(context, ActiveAnimationAdopted(
            request.request_id, request.runtime_generation,
            request.animation_generation, request.animation_id, nothing,
            false, reason))
        return nothing
    end
    actor = retire_stale_adopted_program!(supervisor, context, request)
    if actor === nothing
        program = CompatibilityAnimationProgram(
            context.self, request.animation_id, request.implementation.entry,
            request.state_ptr, request.runtime_generation,
            request.animation_generation, UInt64(0), true)
        actor = EuclidActorRuntime.spawn!(
            context.runtime, program; supervisor=context.self, mailbox_capacity=1)
    end
    supervisor.active_runtime_generation = request.runtime_generation
    supervisor.active_animation_generation = request.animation_generation
    supervisor.active_animation_id = request.animation_id
    supervisor.active_program_actor = actor
    supervisor.active_program_adopted = true
    supervisor.active_state_ptr = request.state_ptr
    supervisor.last_tick_sequence = UInt64(0)
    supervisor.failure = nothing
    empty!(supervisor.implementation_cache)
    supervisor.implementation_cache[request.animation_id] = request.implementation
    EuclidActorRuntime.emit!(context, ActiveAnimationAdopted(
        request.request_id, request.runtime_generation,
        request.animation_generation, request.animation_id, actor,
        true, AnimationNoFailure))
    return nothing
end

"""Return the first failed identity check against the active program actor."""
function active_program_rejection_reason(
    supervisor::AnimationSupervisor,
    runtime::EuclidActorRuntime.ActorRuntime,
    runtime_generation::UInt64,
    animation_generation::UInt64,
    actor::EuclidActorRuntime.ActorId)::AnimationFailureReason
    supervisor.lifecycle_transaction !== nothing && return AnimationLifecycleBusy
    runtime_generation != supervisor.active_runtime_generation &&
        return AnimationStaleRuntime
    animation_generation != supervisor.active_animation_generation &&
        return AnimationStaleGeneration
    actor != supervisor.active_program_actor && return AnimationStaleActor
    !EuclidActorRuntime.is_live(runtime, actor) && return AnimationStaleActor
    return AnimationNoFailure
end

"""Return the first failed identity, sequence, or slot check for one tick."""
function tick_rejection_reason(
    supervisor::AnimationSupervisor,
    runtime::EuclidActorRuntime.ActorRuntime,
    request::TickAnimation)::AnimationFailureReason
    (!supervisor.ready || supervisor.stopping) && return AnimationNotReady
    reason = active_program_rejection_reason(
        supervisor, runtime, request.runtime_generation,
        request.animation_generation, request.program_actor)
    reason !== AnimationNoFailure && return reason
    request.animation_id != supervisor.active_animation_id &&
        return AnimationStaleActor
    request.sequence <= supervisor.last_tick_sequence &&
        return AnimationStaleSequence
    (request.slot.index < 0 || request.slot.reservation_generation == 0) &&
        return AnimationStaleSlot
    return AnimationNoFailure
end

"""Register and enqueue one program exit for a lifecycle transaction."""
function begin_program_stop!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    transaction::AnimationLifecycleTransaction,
    source)::AnimationFailureReason
    actor = something(transaction.actor)
    animation_id = something(supervisor.active_animation_id)
    command = AnimationProgramCommand(
        AnimationRequestKey(transaction.request_id), transaction.request_id,
        transaction.runtime_generation, supervisor.active_animation_generation,
        animation_id,
        OdinJuliaBridge.ANIMATION_OPERATION_EXIT, UInt64(0), nothing, 0.0f0)
    supervisor.lifecycle_transaction = transaction
    reason = send_program_command!(context, actor, command, source)
    reason === AnimationNoFailure || (supervisor.lifecycle_transaction = nothing)
    return reason
end

"""Start one compatibility program actor for a valid activation request."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ActivateAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    reason = activation_rejection_reason(supervisor, request)
    if reason !== AnimationNoFailure
        return emit_lifecycle_result!(context, request.request_id,
            AnimationActivate, request.runtime_generation,
            request.animation_generation, request.animation_id, false, reason)
    end
    implementation = try
        load_animation_implementation!(supervisor, request.animation_id)
    catch exception
        supervisor.failure = EuclidActorRuntime.ActorFailed(
            context.self, exception, request)
        emit_lifecycle_result!(context, request.request_id,
            AnimationActivate, request.runtime_generation,
            request.animation_generation, request.animation_id,
            false, AnimationProgramFailed)
        return nothing
    end
    actor = supervisor.active_program_actor
    previous_id = supervisor.active_animation_id
    previous_implementation = previous_id === nothing ? nothing :
        load_animation_implementation!(supervisor, previous_id)
    transaction = AnimationLifecycleTransaction(
        request.request_id, AnimationActivate, request.runtime_generation,
        request.animation_generation, request.animation_id, request.state_ptr,
        actor, actor === nothing ? AnimationNativeResetPending :
            AnimationProgramStopping, UInt64(0), nothing, implementation,
        supervisor.load_implementation, previous_implementation, previous_id,
        supervisor.active_animation_generation, AnimationNoFailure)
    supervisor.lifecycle_transaction = transaction
    if actor === nothing
        EuclidActorRuntime.emit!(context, ResetNativeAnimationState(
            request.request_id, request.runtime_generation,
            request.animation_generation))
        return nothing
    end
    reason = begin_program_stop!(supervisor, context, transaction, request)
    if reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, request.request_id,
            AnimationActivate, request.runtime_generation,
            request.animation_generation, request.animation_id, false, reason)
    end
    return nothing
end

"""Reject or forward one checked tick to the active program actor."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::TickAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    actor = supervisor.active_program_actor
    reason = tick_rejection_reason(supervisor, context.runtime, request)
    if reason !== AnimationNoFailure
        EuclidActorRuntime.emit!(context, AnimationTickCompleted(
            request.request_id, request.runtime_generation,
            request.animation_generation, request.animation_id,
            request.program_actor, request.sequence, request.slot, false, reason))
        return nothing
    end
    command = AnimationProgramCommand(
        AnimationRequestKey(request.request_id), request.request_id,
        request.runtime_generation,
        request.animation_generation, request.animation_id,
        OdinJuliaBridge.ANIMATION_OPERATION_TICK, request.sequence,
        request.slot, request.dt)
    reason = send_program_command!(context, something(actor), command, request)
    if reason !== AnimationNoFailure
        EuclidActorRuntime.emit!(context, AnimationTickCompleted(
            request.request_id, request.runtime_generation,
            request.animation_generation, request.animation_id,
            request.program_actor, request.sequence, request.slot, false, reason))
    end
    return nothing
end

"""Start orderly exit of the matching active program generation."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::StopAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    reason = active_program_rejection_reason(
        supervisor, context.runtime, request.runtime_generation,
        request.animation_generation, request.program_actor)
    if reason !== AnimationNoFailure
        return emit_lifecycle_result!(context, request.request_id, AnimationStop,
            request.runtime_generation, request.animation_generation,
            supervisor.active_animation_id, false, reason)
    end
    id = something(supervisor.active_animation_id)
    transaction = AnimationLifecycleTransaction(
        request.request_id, AnimationStop, request.runtime_generation,
        request.animation_generation, id, supervisor.active_state_ptr,
        request.program_actor, AnimationProgramStopping, UInt64(0), nothing,
        nothing, nothing, nothing, id, request.animation_generation,
        AnimationNoFailure)
    reason = begin_program_stop!(supervisor, context, transaction, request)
    if reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, request.request_id, AnimationStop,
            request.runtime_generation, request.animation_generation,
            id, false, reason)
    end
    return nothing
end

"""Begin a reset by stopping the matching active program actor."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ResetAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    reason = active_program_rejection_reason(
        supervisor, context.runtime, request.runtime_generation,
        request.current_animation_generation, request.program_actor)
    id = supervisor.active_animation_id
    if reason !== AnimationNoFailure
        return emit_lifecycle_result!(context, request.request_id, AnimationReset,
            request.runtime_generation, request.target_animation_generation,
            id, false, reason)
    end
    transaction = AnimationLifecycleTransaction(
        request.request_id, AnimationReset, request.runtime_generation,
        request.target_animation_generation, id, supervisor.active_state_ptr,
        request.program_actor, AnimationProgramStopping, UInt64(0), nothing,
        nothing, nothing, nothing, id, request.current_animation_generation,
        AnimationNoFailure)
    reason = begin_program_stop!(supervisor, context, transaction, request)
    if reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, request.request_id, AnimationReset,
            request.runtime_generation, request.target_animation_generation,
            id, false, reason)
    end
    return nothing
end

"""Return the first failed precondition for one candidate reload."""
function reload_rejection_reason(
    supervisor::AnimationSupervisor,
    request::ReloadAnimation)::AnimationFailureReason
    supervisor.lifecycle_transaction !== nothing && return AnimationLifecycleBusy
    request.current_runtime_generation != supervisor.active_runtime_generation &&
        return AnimationStaleRuntime
    request.candidate_runtime_generation <= request.current_runtime_generation &&
        return AnimationStaleRuntime
    return AnimationNoFailure
end

"""Load one candidate implementation and retain any loader failure."""
function load_reload_candidate!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ReloadAnimation)
    try
        return request.load_implementation(request.animation_id)
    catch exception
        supervisor.failure = EuclidActorRuntime.ActorFailed(
            context.self, exception, request)
        return nothing
    end
end

"""Begin candidate activation when no prior program actor is active."""
function begin_inactive_program_reload!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ReloadAnimation,
    candidate_implementation)::Nothing
    transaction = AnimationLifecycleTransaction(
        request.request_id, AnimationReload,
        request.current_runtime_generation, request.target_animation_generation,
        request.animation_id, supervisor.active_state_ptr, nothing,
        AnimationNativeResetPending, request.candidate_runtime_generation,
        request.load_implementation, candidate_implementation,
        supervisor.load_implementation, nothing, nothing, UInt64(0),
        AnimationNoFailure)
    supervisor.lifecycle_transaction = transaction
    EuclidActorRuntime.emit!(context, ResetNativeAnimationState(
        request.request_id, request.current_runtime_generation,
        request.target_animation_generation))
    return nothing
end

"""Stop the active program before activating one candidate generation."""
function begin_active_program_reload!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ReloadAnimation,
    candidate_implementation)::Nothing
    actor = something(supervisor.active_program_actor)
    active_id = something(supervisor.active_animation_id)
    previous_implementation = load_animation_implementation!(supervisor, active_id)
    transaction = AnimationLifecycleTransaction(
        request.request_id, AnimationReload,
        request.current_runtime_generation, request.target_animation_generation,
        request.animation_id, supervisor.active_state_ptr, actor,
        AnimationProgramStopping, request.candidate_runtime_generation,
        request.load_implementation, candidate_implementation,
        supervisor.load_implementation, previous_implementation, active_id,
        supervisor.active_animation_generation, AnimationNoFailure)
    reason = begin_program_stop!(supervisor, context, transaction, request)
    if reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, request.request_id, AnimationReload,
            request.current_runtime_generation, request.target_animation_generation,
            request.animation_id, false, reason)
    end
    return nothing
end

"""Adopt a candidate loader after quiescing any active program actor."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    request::ReloadAnimation)::Nothing
    supervisor.commands_processed += UInt64(1)
    reason = reload_rejection_reason(supervisor, request)
    if reason !== AnimationNoFailure
        return emit_lifecycle_result!(context, request.request_id, AnimationReload,
            request.current_runtime_generation, request.target_animation_generation,
            supervisor.active_animation_id, false, reason)
    end
    candidate_implementation = load_reload_candidate!(supervisor, context, request)
    if candidate_implementation === nothing
        emit_lifecycle_result!(context, request.request_id, AnimationReload,
            request.current_runtime_generation,
            request.target_animation_generation,
            request.animation_id, false, AnimationProgramFailed)
        return nothing
    end
    if supervisor.active_program_actor === nothing
        return begin_inactive_program_reload!(
            supervisor, context, request, candidate_implementation)
    end
    return begin_active_program_reload!(
        supervisor, context, request, candidate_implementation)
end

"""Continue reset or reload after the required native reset acknowledgement."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    acknowledgement::NativeAnimationStateReset)::Nothing
    transaction = supervisor.lifecycle_transaction
    transaction === nothing && return nothing
    transaction.stage === AnimationNativeResetPending || return nothing
    transaction.request_id == acknowledgement.request_id || return nothing
    if !acknowledgement.accepted
        if transaction.previous_implementation !== nothing &&
            restore_lifecycle_program!(supervisor, context, transaction,
                AnimationNativeCommandRejected)
            return nothing
        end
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, transaction.request_id, transaction.kind,
            transaction.runtime_generation, transaction.animation_generation,
            transaction.animation_id, false, AnimationNativeCommandRejected)
        resume_animation_supervisor_shutdown!(supervisor, context)
        return nothing
    end
    if supervisor.stopping
        supervisor.lifecycle_transaction = nothing
        resume_animation_supervisor_shutdown!(supervisor, context)
        return nothing
    end
    if transaction.kind === AnimationReload
        transaction.stage = AnimationProgramActivating
    end
    reason = activate_transaction_program!(supervisor, context, transaction)
    if reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, transaction.request_id, transaction.kind,
            transaction.runtime_generation, transaction.animation_generation,
            transaction.animation_id, false, reason)
    end
    return nothing
end

"""Publish one successful correlated tick completion."""
function complete_program_tick!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    completed::AnimationProgramCompleted)::Nothing
    command = completed.command
    supervisor.last_tick_sequence = command.sequence
    EuclidActorRuntime.emit!(context, AnimationTickCompleted(
        command.request_id, command.runtime_generation,
        command.animation_generation, command.animation_id,
        completed.actor, command.sequence,
        something(command.slot), true, AnimationNoFailure))
    resume_animation_supervisor_shutdown!(supervisor, context)
    return nothing
end

"""Commit one successful program activation transaction."""
function complete_program_activation!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    completed::AnimationProgramCompleted,
    transaction::AnimationLifecycleTransaction)::Nothing
    command = completed.command
    if transaction.stage === AnimationProgramRestoring
        supervisor.active_runtime_generation = transaction.runtime_generation
        supervisor.load_implementation = transaction.previous_loader
        empty!(supervisor.implementation_cache)
        supervisor.implementation_cache[command.animation_id] =
            transaction.previous_implementation
        supervisor.active_animation_id = command.animation_id
        supervisor.active_animation_generation = command.animation_generation
        supervisor.active_state_ptr = transaction.state_ptr
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, command.request_id, transaction.kind,
            transaction.runtime_generation, command.animation_generation,
            command.animation_id, false, transaction.rollback_reason)
        return nothing
    end
    if transaction.kind === AnimationReload
        supervisor.active_runtime_generation = command.runtime_generation
        supervisor.load_implementation = transaction.candidate_loader
        empty!(supervisor.implementation_cache)
        supervisor.implementation_cache[command.animation_id] =
            transaction.candidate_implementation
    end
    supervisor.active_animation_id = command.animation_id
    supervisor.active_animation_generation = command.animation_generation
    supervisor.active_state_ptr = transaction.state_ptr
    supervisor.lifecycle_transaction = nothing
    emit_lifecycle_result!(context, command.request_id, transaction.kind,
        command.runtime_generation, command.animation_generation,
        command.animation_id, true, AnimationNoFailure)
    resume_animation_supervisor_shutdown!(supervisor, context)
    return nothing
end

"""Reactivate the prior implementation after a lifecycle transaction fails."""
function restore_lifecycle_program!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    transaction::AnimationLifecycleTransaction,
    reason::AnimationFailureReason)::Bool
    transaction.stage = AnimationProgramRestoring
    transaction.rollback_reason = reason
    restore_reason = activate_transaction_program!(supervisor, context, transaction)
    return restore_reason === AnimationNoFailure
end

"""Commit program exit and advance stop, reset, reload, or root shutdown."""
function complete_program_exit!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    completed::AnimationProgramCompleted,
    transaction::AnimationLifecycleTransaction)::Nothing
    command = completed.command
    supervisor.active_program_actor = nothing
    supervisor.active_program_adopted = false
    supervisor.active_animation_id = nothing
    supervisor.active_animation_generation = UInt64(0)
    supervisor.active_state_ptr = C_NULL
    if supervisor.stopping
        supervisor.lifecycle_transaction = nothing
        finish_animation_supervisor_shutdown!(context)
    elseif transaction.kind === AnimationStop
        supervisor.lifecycle_transaction = nothing
        emit_lifecycle_result!(context, command.request_id, AnimationStop,
            command.runtime_generation, command.animation_generation,
            command.animation_id, true, AnimationNoFailure)
    else
        transaction.stage = AnimationNativeResetPending
        EuclidActorRuntime.emit!(context, ResetNativeAnimationState(
            transaction.request_id, transaction.runtime_generation,
            transaction.animation_generation))
    end
    return nothing
end

"""Commit one successful program activation or stop outcome."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    completed::AnimationProgramCompleted)::Nothing
    command = completed.command
    completed.actor == supervisor.active_program_actor || return nothing
    if command.operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        return complete_program_tick!(supervisor, context, completed)
    end
    transaction = supervisor.lifecycle_transaction
    transaction === nothing && return nothing
    completed.actor == transaction.actor || return nothing
    if command.operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        complete_program_activation!(supervisor, context, completed, transaction)
    else
        complete_program_exit!(supervisor, context, completed, transaction)
    end
    return nothing
end

"""Report one failed tick and resume any pending supervisor shutdown."""
function complete_failed_program_tick!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    command::AnimationProgramCommand,
    failure::EuclidActorRuntime.ActorFailed,
    reason::AnimationFailureReason)::Nothing
    EuclidActorRuntime.emit!(context, AnimationTickCompleted(
        command.request_id, command.runtime_generation,
        command.animation_generation, command.animation_id,
        failure.actor, command.sequence, something(command.slot), false, reason))
    resume_animation_supervisor_shutdown!(supervisor, context)
    return nothing
end

"""Restore or terminate lifecycle state after one child program failure."""
function complete_failed_program_lifecycle!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    command::AnimationProgramCommand,
    reason::AnimationFailureReason)::Nothing
    transaction = supervisor.lifecycle_transaction
    kind = transaction === nothing &&
        command.operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER ?
        AnimationActivate : transaction === nothing ? AnimationStop : transaction.kind
    if transaction !== nothing &&
        command.operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER &&
        transaction.stage === AnimationProgramActivating &&
        transaction.previous_implementation !== nothing &&
        restore_lifecycle_program!(supervisor, context, transaction, reason)
        return nothing
    end
    supervisor.lifecycle_transaction = nothing
    supervisor.active_animation_id = nothing
    supervisor.active_animation_generation = UInt64(0)
    supervisor.active_state_ptr = C_NULL
    if command.request_key isa AnimationSupervisorShutdownKey
        finish_animation_supervisor_shutdown!(context)
    else
        emit_lifecycle_result!(context, command.request_id, kind,
            command.runtime_generation, command.animation_generation,
            command.animation_id, false, reason)
        resume_animation_supervisor_shutdown!(supervisor, context)
    end
    return nothing
end

"""Convert one stopped child failure into its typed correlated outcome."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    failure::EuclidActorRuntime.ActorFailed)::Nothing
    failure.actor == supervisor.active_program_actor || return nothing
    supervisor.failure = failure
    supervisor.active_program_actor = nothing
    supervisor.active_program_adopted = false
    command = failure.message
    command isa AnimationProgramCommand || return nothing
    reason = failure.exception isa AnimationProgramRejectedError ?
        AnimationProgramRejected : AnimationProgramFailed
    if command.operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        return complete_failed_program_tick!(
            supervisor, context, command, failure, reason)
    end
    return complete_failed_program_lifecycle!(supervisor, context, command, reason)
end

"""Close animation-policy admission and stop the persistent root actor."""
function EuclidActorRuntime.receive!(
    supervisor::AnimationSupervisor,
    context::EuclidActorRuntime.ActorContext,
    _message::StopAnimationSupervisor)::Nothing
    supervisor.ready = false
    supervisor.stopping = true
    supervisor.commands_processed += UInt64(1)
    actor = supervisor.active_program_actor
    actor === nothing && return finish_animation_supervisor_shutdown!(context)
    supervisor.lifecycle_transaction === nothing || return nothing
    if supervisor.active_program_adopted
        EuclidActorRuntime.stop!(context.runtime, actor)
        supervisor.active_program_actor = nothing
        supervisor.active_program_adopted = false
        return finish_animation_supervisor_shutdown!(context)
    end
    id = something(supervisor.active_animation_id)
    transaction = AnimationLifecycleTransaction(
        UInt64(0), AnimationStop, supervisor.active_runtime_generation,
        supervisor.active_animation_generation, id, supervisor.active_state_ptr,
        actor, AnimationProgramStopping, UInt64(0), nothing, nothing,
        nothing, nothing, id, supervisor.active_animation_generation,
        AnimationNoFailure)
    supervisor.lifecycle_transaction = transaction
    command = AnimationProgramCommand(
        AnimationSupervisorShutdownKey(), UInt64(0),
        supervisor.active_runtime_generation,
        supervisor.active_animation_generation, id,
        OdinJuliaBridge.ANIMATION_OPERATION_EXIT, UInt64(0), nothing, 0.0f0)
    reason = send_program_command!(context, something(actor), command, transaction)
    if reason === AnimationMailboxFull
        supervisor.lifecycle_transaction = nothing
    elseif reason !== AnimationNoFailure
        supervisor.lifecycle_transaction = nothing
        supervisor.active_program_actor = nothing
        supervisor.active_program_adopted = false
        finish_animation_supervisor_shutdown!(context)
    end
    return nothing
end