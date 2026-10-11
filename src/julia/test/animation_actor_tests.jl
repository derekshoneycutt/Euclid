using UUIDs

const ActorAnimationId = UUID("683b096d-5f64-50d2-9853-df907ca19075")

"""Pump until no actor remains ready, bounded for deterministic tests."""
function drain_animation_actors!(runtime::EuclidActorRuntime.ActorRuntime)::Nothing
    for _ in 1:32
        status = EuclidActorRuntime.pump!(
            runtime; max_turns=1, deadline_ns=typemax(UInt64))
        status.remaining_ready == 0 && return nothing
    end
    error("animation actors did not quiesce")
end

"""Count live compatibility program actors owned by one test runtime."""
function live_animation_program_count(
    runtime::EuclidActorRuntime.ActorRuntime)::Int
    return count(runtime.slots) do slot
        slot !== nothing &&
            slot.actor isa EuclidPolicy.CompatibilityAnimationProgram
    end
end

"""Complete the native reset handshake required by one activation request."""
function activate_animation_for_test!(
    runtime::EuclidActorRuntime.ActorRuntime,
    supervisor::EuclidActorRuntime.ActorId,
    request::EuclidPolicy.ActivateAnimation)
    EuclidActorRuntime.send!(runtime, supervisor, request) ===
        EuclidActorRuntime.SendAccepted || error("activation was not accepted")
    drain_animation_actors!(runtime)
    reset = only(EuclidActorRuntime.take_outgoing!(runtime))
    reset isa EuclidPolicy.ResetNativeAnimationState ||
        error("activation did not request native reset")
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(request.request_id, true))
    drain_animation_actors!(runtime)
    return only(EuclidActorRuntime.take_outgoing!(runtime))
end

@testset "checked-in animation fixture executes unchanged through actor" begin
    implementation = AnimationCatalog.ensure_animation_loaded(
        dirname(@__DIR__), test_catalog(), ActorAnimationId)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    supervisor_state = EuclidPolicy.AnimationSupervisor()
    supervisor = EuclidActorRuntime.spawn!(
        runtime, supervisor_state; mailbox_capacity=1)
    program = EuclidPolicy.CompatibilityAnimationProgram(
        supervisor, ActorAnimationId, implementation.entry, C_NULL,
        UInt64(1), UInt64(1), UInt64(0), true)
    actor = EuclidActorRuntime.spawn!(
        runtime, program; supervisor, mailbox_capacity=1)
    supervisor_state.active_program_actor = actor
    supervisor_state.active_animation_id = ActorAnimationId
    supervisor_state.active_animation_generation = UInt64(1)
    key = EuclidPolicy.AnimationRequestKey(UInt64(1))
    command = EuclidPolicy.AnimationProgramCommand(
        key, UInt64(1), UInt64(1), UInt64(1), ActorAnimationId,
        OdinJuliaBridge.ANIMATION_OPERATION_TICK, UInt64(1),
        EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)), 0.25f0)
    @test EuclidActorRuntime.register_request!(runtime, key, actor) ===
        EuclidActorRuntime.RequestRegistered
    @test EuclidActorRuntime.send!(runtime, actor, command) ===
        EuclidActorRuntime.SendAccepted
    drain_animation_actors!(runtime)
    completed = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test completed isa EuclidPolicy.AnimationTickCompleted
    @test completed.program_actor == actor
    @test EuclidActorRuntime.pending_request_count(runtime) == 0
end

@testset "compatibility animation actor preserves entry contract" begin
    calls = Tuple{Ptr{Cvoid},Int32,Float32}[]
    loads = Ref(0)
    entry = (state_ptr, operation, dt) -> begin
        push!(calls, (state_ptr, operation, dt))
        true
    end
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, entry)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    supervisor_state = EuclidPolicy.AnimationSupervisor(
        UInt64(7), _id -> begin
            loads[] += 1
            implementation
        end)
    supervisor = EuclidActorRuntime.spawn!(
        runtime, supervisor_state; mailbox_capacity=8)
    @test EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor()) ===
        EuclidActorRuntime.SendAccepted
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)

    activate = EuclidPolicy.ActivateAnimation(
        UInt64(10), UInt64(7), UInt64(3), ActorAnimationId, C_NULL)
    outcomes = [activate_animation_for_test!(runtime, supervisor, activate)]
    @test calls == [(C_NULL, OdinJuliaBridge.ANIMATION_OPERATION_ENTER, 0.0f0)]
    @test only(outcomes).succeeded
    @test loads[] == 1
    actor = something(supervisor_state.active_program_actor)
    @test live_animation_program_count(runtime) == 1

    tick = EuclidPolicy.TickAnimation(
        UInt64(11), UInt64(7), UInt64(3), ActorAnimationId, actor,
        UInt64(1), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.25f0)
    @test EuclidActorRuntime.send!(runtime, supervisor, tick) ===
        EuclidActorRuntime.SendAccepted
    EuclidActorRuntime.pump!(
        runtime; max_turns=1, deadline_ns=typemax(UInt64))
    @test EuclidActorRuntime.mailbox_depth(runtime, actor) == 1
    command = EuclidPolicy.AnimationProgramCommand(
        EuclidPolicy.AnimationRequestKey(UInt64(12)),
        UInt64(12), UInt64(7), UInt64(3), ActorAnimationId,
        OdinJuliaBridge.ANIMATION_OPERATION_TICK, UInt64(2),
        EuclidPolicy.AnimationTickSlotHandle(Int32(1), UInt64(1)), 0.5f0)
    @test EuclidActorRuntime.send!(runtime, actor, command) ===
        EuclidActorRuntime.SendMailboxFull
    drain_animation_actors!(runtime)
    tick_outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test tick_outcome isa EuclidPolicy.AnimationTickCompleted
    @test tick_outcome.succeeded
    @test calls[end] == (
        C_NULL, OdinJuliaBridge.ANIMATION_OPERATION_TICK, 0.25f0)

    stale_tick = EuclidPolicy.TickAnimation(
        UInt64(13), UInt64(7), UInt64(3), ActorAnimationId, actor,
        UInt64(1), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, stale_tick)
    drain_animation_actors!(runtime)
    stale_outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test !stale_outcome.succeeded
    @test stale_outcome.reason === EuclidPolicy.AnimationStaleSequence

    stale_generation = EuclidPolicy.TickAnimation(
        UInt64(17), UInt64(7), UInt64(2), ActorAnimationId, actor,
        UInt64(2), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, stale_generation)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).reason ===
        EuclidPolicy.AnimationStaleGeneration

    retired_actor = EuclidActorRuntime.ActorId(
        actor.index, actor.generation + UInt64(1))
    stale_actor = EuclidPolicy.TickAnimation(
        UInt64(18), UInt64(7), UInt64(3), ActorAnimationId, retired_actor,
        UInt64(2), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, stale_actor)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).reason ===
        EuclidPolicy.AnimationStaleActor

    stale_slot = EuclidPolicy.TickAnimation(
        UInt64(19), UInt64(7), UInt64(3), ActorAnimationId, actor,
        UInt64(2), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(0)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, stale_slot)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).reason ===
        EuclidPolicy.AnimationStaleSlot

    duplicate_key = EuclidPolicy.AnimationRequestKey(UInt64(20))
    @test EuclidActorRuntime.register_request!(runtime, duplicate_key, actor) ===
        EuclidActorRuntime.RequestRegistered
    duplicate = EuclidPolicy.TickAnimation(
        UInt64(20), UInt64(7), UInt64(3), ActorAnimationId, actor,
        UInt64(2), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, duplicate)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).reason ===
        EuclidPolicy.AnimationDuplicateRequest
    @test length(calls) == 2

    reset = EuclidPolicy.ResetAnimation(
        UInt64(14), UInt64(7), UInt64(3), UInt64(4), actor)
    EuclidActorRuntime.send!(runtime, supervisor, reset)
    drain_animation_actors!(runtime)
    native_reset = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test native_reset isa EuclidPolicy.ResetNativeAnimationState
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(UInt64(14), true))
    drain_animation_actors!(runtime)
    reset_outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test reset_outcome.kind === EuclidPolicy.AnimationReset
    @test reset_outcome.succeeded
    @test loads[] == 1
    reset_actor = something(supervisor_state.active_program_actor)
    @test reset_actor != actor
    @test !EuclidActorRuntime.is_live(runtime, actor)
    @test live_animation_program_count(runtime) == 1

    retired_tick = EuclidPolicy.TickAnimation(
        UInt64(21), UInt64(7), UInt64(4), ActorAnimationId, actor,
        UInt64(1), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(2)),
        0.25f0)
    EuclidActorRuntime.send!(runtime, supervisor, retired_tick)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).reason ===
        EuclidPolicy.AnimationStaleActor

    replacement_calls = Tuple{Ptr{Cvoid},Int32,Float32}[]
    replacement = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (state_ptr, operation, dt) -> begin
            push!(replacement_calls, (state_ptr, operation, dt))
            true
        end)
    reload = EuclidPolicy.ReloadAnimation(
        UInt64(15), UInt64(7), UInt64(8), UInt64(4), UInt64(5),
        ActorAnimationId, _id -> replacement)
    EuclidActorRuntime.send!(runtime, supervisor, reload)
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)) isa
        EuclidPolicy.ResetNativeAnimationState
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(UInt64(15), true))
    drain_animation_actors!(runtime)
    reload_outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test reload_outcome.kind === EuclidPolicy.AnimationReload
    @test reload_outcome.runtime_generation == UInt64(8)
    @test reload_outcome.succeeded
    @test length(supervisor_state.implementation_cache) == 1
    reloaded_actor = something(supervisor_state.active_program_actor)
    @test !EuclidActorRuntime.is_live(runtime, reset_actor)
    @test live_animation_program_count(runtime) == 1

    stop = EuclidPolicy.StopAnimation(
        UInt64(16), UInt64(8), UInt64(5), reloaded_actor)
    EuclidActorRuntime.send!(runtime, supervisor, stop)
    drain_animation_actors!(runtime)
    stop_outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test stop_outcome.kind === EuclidPolicy.AnimationStop
    @test stop_outcome.succeeded
    @test supervisor_state.active_program_actor === nothing
    @test live_animation_program_count(runtime) == 0
    @test replacement_calls == [
        (C_NULL, OdinJuliaBridge.ANIMATION_OPERATION_ENTER, 0.0f0),
        (C_NULL, OdinJuliaBridge.ANIMATION_OPERATION_EXIT, 0.0f0)]
end

@testset "animation supervisor rejects stale identities before invocation" begin
    calls = Ref(0)
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, _operation, _dt) -> begin
            calls[] += 1
            true
        end)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(4), _id -> implementation)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=8)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)

    stale = EuclidPolicy.ActivateAnimation(
        UInt64(20), UInt64(3), UInt64(1), ActorAnimationId, C_NULL)
    EuclidActorRuntime.send!(runtime, supervisor, stale)
    drain_animation_actors!(runtime)
    outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test outcome.reason === EuclidPolicy.AnimationStaleRuntime
    @test calls[] == 0
    @test state.active_program_actor === nothing
end

@testset "program failure is correlated without implicit restart" begin
    entry = (_state_ptr, operation, _dt) ->
        operation != OdinJuliaBridge.ANIMATION_OPERATION_TICK
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, entry)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(2), _id -> implementation)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=8)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)
    activate_animation_for_test!(runtime, supervisor,
        EuclidPolicy.ActivateAnimation(
            UInt64(30), UInt64(2), UInt64(9), ActorAnimationId, C_NULL))
    actor = something(state.active_program_actor)

    EuclidActorRuntime.send!(runtime, supervisor, EuclidPolicy.TickAnimation(
        UInt64(31), UInt64(2), UInt64(9), ActorAnimationId, actor,
        UInt64(1), EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)),
        0.1f0))
    drain_animation_actors!(runtime)
    outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test !outcome.succeeded
    @test outcome.reason === EuclidPolicy.AnimationProgramRejected
    @test !EuclidActorRuntime.is_live(runtime, actor)
    @test state.active_program_actor === nothing
    @test state.failure !== nothing
    @test EuclidActorRuntime.pending_request_count(runtime) == 0
    @test EuclidActorRuntime.is_live(runtime, supervisor)
end

@testset "rejected reload retains prior generation cache" begin
    loads = Ref(0)
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, _operation, _dt) -> true)
    loader = _id -> begin
        loads[] += 1
        implementation
    end
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(5), loader)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=8)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)
    activate_animation_for_test!(runtime, supervisor,
        EuclidPolicy.ActivateAnimation(
            UInt64(50), UInt64(5), UInt64(1), ActorAnimationId, C_NULL))

    EuclidActorRuntime.send!(runtime, supervisor, EuclidPolicy.ReloadAnimation(
        UInt64(51), UInt64(5), UInt64(6), UInt64(1), UInt64(2),
        ActorAnimationId, _id -> implementation))
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)) isa
        EuclidPolicy.ResetNativeAnimationState
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(UInt64(51), false))
    drain_animation_actors!(runtime)
    outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test !outcome.succeeded
    @test outcome.reason === EuclidPolicy.AnimationNativeCommandRejected
    @test state.active_runtime_generation == UInt64(5)
    @test state.implementation_cache[ActorAnimationId] === implementation

    EuclidActorRuntime.send!(runtime, supervisor, EuclidPolicy.ActivateAnimation(
        UInt64(52), UInt64(5), UInt64(2), ActorAnimationId, C_NULL))
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)) isa
        EuclidPolicy.ResetNativeAnimationState
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(UInt64(52), true))
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)).succeeded
    @test loads[] == 1
end

@testset "failed candidate activation restores prior generation" begin
    prior_operations = Int32[]
    candidate_operations = Int32[]
    prior = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, operation, _dt) -> begin
            push!(prior_operations, operation)
            true
        end)
    candidate = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, operation, _dt) -> begin
            push!(candidate_operations, operation)
            operation != OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        end)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(5), _id -> prior)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=8)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)
    activate_animation_for_test!(runtime, supervisor,
        EuclidPolicy.ActivateAnimation(
            UInt64(60), UInt64(5), UInt64(1), ActorAnimationId, C_NULL))

    EuclidActorRuntime.send!(runtime, supervisor, EuclidPolicy.ReloadAnimation(
        UInt64(61), UInt64(5), UInt64(6), UInt64(1), UInt64(2),
        ActorAnimationId, _id -> candidate))
    drain_animation_actors!(runtime)
    @test only(EuclidActorRuntime.take_outgoing!(runtime)) isa
        EuclidPolicy.ResetNativeAnimationState
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.NativeAnimationStateReset(UInt64(61), true))
    drain_animation_actors!(runtime)
    outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test outcome.kind === EuclidPolicy.AnimationReload
    @test !outcome.succeeded
    @test outcome.reason === EuclidPolicy.AnimationProgramRejected
    @test outcome.runtime_generation == UInt64(5)
    @test state.active_runtime_generation == UInt64(5)
    @test state.load_implementation(ActorAnimationId) === prior
    @test state.implementation_cache[ActorAnimationId] === prior
    @test EuclidActorRuntime.is_live(
        runtime, something(state.active_program_actor))
    @test live_animation_program_count(runtime) == 1
    @test state.lifecycle_transaction === nothing
    @test prior_operations == [OdinJuliaBridge.ANIMATION_OPERATION_ENTER,
        OdinJuliaBridge.ANIMATION_OPERATION_EXIT,
        OdinJuliaBridge.ANIMATION_OPERATION_ENTER]
    @test candidate_operations == [OdinJuliaBridge.ANIMATION_OPERATION_ENTER]
end

@testset "supervisor shutdown exits its active program first" begin
    operations = Int32[]
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, operation, _dt) -> begin
            push!(operations, operation)
            true
        end)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(1), _id -> implementation)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=1)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)
    activate_animation_for_test!(runtime, supervisor,
        EuclidPolicy.ActivateAnimation(
            UInt64(40), UInt64(1), UInt64(1), ActorAnimationId, C_NULL))
    actor = something(state.active_program_actor)

    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StopAnimationSupervisor())
    drain_animation_actors!(runtime)
    outcome = only(EuclidActorRuntime.take_outgoing!(runtime))
    @test outcome isa EuclidPolicy.AnimationSupervisorStopped
    @test operations == [OdinJuliaBridge.ANIMATION_OPERATION_ENTER,
        OdinJuliaBridge.ANIMATION_OPERATION_EXIT]
    @test !EuclidActorRuntime.is_live(runtime, actor)
    @test !EuclidActorRuntime.is_live(runtime, supervisor)
    @test EuclidActorRuntime.pending_request_count(runtime) == 0
end

@testset "supervisor shutdown waits behind a full program mailbox" begin
    operations = Int32[]
    implementation = AnimationCatalog.AnimationImplementation(
        ActorAnimationId, (_state_ptr, operation, _dt) -> begin
            push!(operations, operation)
            true
        end)
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(0)))
    state = EuclidPolicy.AnimationSupervisor(UInt64(1), _id -> implementation)
    supervisor = EuclidActorRuntime.spawn!(runtime, state; mailbox_capacity=1)
    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StartAnimationSupervisor())
    drain_animation_actors!(runtime)
    EuclidActorRuntime.take_outgoing!(runtime)
    activate_animation_for_test!(runtime, supervisor,
        EuclidPolicy.ActivateAnimation(
            UInt64(60), UInt64(1), UInt64(1), ActorAnimationId, C_NULL))
    actor = something(state.active_program_actor)

    EuclidActorRuntime.send!(runtime, supervisor,
        EuclidPolicy.StopAnimationSupervisor())
    key = EuclidPolicy.AnimationRequestKey(UInt64(61))
    tick = EuclidPolicy.AnimationProgramCommand(
        key, UInt64(61), UInt64(1), UInt64(1), ActorAnimationId,
        OdinJuliaBridge.ANIMATION_OPERATION_TICK, UInt64(1),
        EuclidPolicy.AnimationTickSlotHandle(Int32(0), UInt64(1)), 0.1f0)
    EuclidActorRuntime.register_request!(runtime, key, actor)
    EuclidActorRuntime.send!(runtime, actor, tick)
    EuclidActorRuntime.pump!(
        runtime; max_turns=1, deadline_ns=typemax(UInt64))
    @test state.stopping
    @test EuclidActorRuntime.is_live(runtime, actor)
    drain_animation_actors!(runtime)
    outcomes = EuclidActorRuntime.take_outgoing!(runtime)
    @test any(outcome -> outcome isa EuclidPolicy.AnimationTickCompleted, outcomes)
    @test any(outcome -> outcome isa EuclidPolicy.AnimationSupervisorStopped, outcomes)
    @test operations == [OdinJuliaBridge.ANIMATION_OPERATION_ENTER,
        OdinJuliaBridge.ANIMATION_OPERATION_TICK,
        OdinJuliaBridge.ANIMATION_OPERATION_EXIT]
    @test EuclidActorRuntime.pending_request_count(runtime) == 0
end