package operations

import "core:testing"
import modifier "../animation"
import geometry "../core/geometry"

Operation_Storage_Test_Generations :: struct {
    payload: u64,
    target: u64,
    claim: u64,
    control: u64,
}

// Test fixed initialization, capacity, and bounded diagnostics.
@(test)
operation_storage_initialization_capacity_and_diagnostics :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)

    handles: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Handle
    outcomes: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Outcome_Handle
    for index in 0..<ACTIVE_OPERATION_SLOT_COUNT {
        reservation, status := active_operation_reserve(
            &storage, u16(index + 1), u64(index + 1), 7)
        testing.expect_value(t, status, Active_Operation_Status.Ok)
        handles[index] = reservation.execution
        outcomes[index] = reservation.outcome
    }
    _, capacity_status := active_operation_reserve(&storage, 99, 100, 7)
    testing.expect(t, capacity_status == .Execution_Full ||
        capacity_status == .Payload_Full ||
        capacity_status == .Target_Full ||
        capacity_status == .Claim_Full ||
        capacity_status == .Control_Full ||
        capacity_status == .Outcome_Full)
    diagnostics := active_operation_storage_diagnostics(&storage)
    testing.expect_value(t, diagnostics.execution_reserved,
        ACTIVE_OPERATION_SLOT_COUNT)
    testing.expect_value(t, diagnostics.outcome_used,
        ACTIVE_OPERATION_SLOT_COUNT)
    for handle in handles {
        testing.expect_value(t,
            active_operation_release_execution(&storage, handle),
            Active_Operation_Status.Ok)
    }
}

// Release one operation and verify its former execution handle is stale.
operation_storage_test_release_initial_reservation :: proc(
    t: ^testing.T,
    storage: ^Active_Operation_Storage) -> (
        Active_Operation_Handle, Active_Operation_Outcome_Handle) {
    reservation, status := active_operation_reserve(storage, 1, 11, 3)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_admit(storage, reservation.execution),
        Active_Operation_Status.Ok)
    testing.expect_value(t,
        active_operation_release_execution(storage, reservation.execution),
        Active_Operation_Status.Ok)
    testing.expect_value(t,
        active_operation_release_execution(storage, reservation.execution),
        Active_Operation_Status.Invalid_Handle)
    return reservation.execution, reservation.outcome
}

// Test stale and reusable execution generations plus independent outcome delivery.
@(test)
operation_storage_reservation_releases_reuse_and_rejects_stale_handles :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)

    first, first_outcome :=
        operation_storage_test_release_initial_reservation(t, &storage)

    second_reservation, reserve_status := active_operation_reserve(&storage, 2, 12, 4)
    testing.expect_value(t, reserve_status, Active_Operation_Status.Ok)
    second := second_reservation.execution
    outcome := second_reservation.outcome
    testing.expect(t, first.index == second.index)
    testing.expect(t, first.generation != second.generation)
    testing.expect_value(t,
        active_operation_release_execution(&storage, first),
        Active_Operation_Status.Invalid_Handle)
    testing.expect_value(t, active_operation_admit(&storage, second),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_publish_outcome(
        &storage, outcome, .Committed), Active_Operation_Status.Ok)
    testing.expect_value(t,
        active_operation_release_execution(&storage, second),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_publish_outcome(
        &storage, first_outcome, .Rejected), Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_mark_outcome_sent(
        &storage, first_outcome), Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_acknowledge_outcome(
        &storage, first_outcome), Active_Operation_Status.Ok)
}

// Test that an outcome remains deliverable after its execution slot is reused.
@(test)
operation_storage_outcome_survives_execution_slot_reuse :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)

    first_reservation, status := active_operation_reserve(&storage, 1, 21, 5)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    first := first_reservation.execution
    outcome := first_reservation.outcome
    first_slot := storage.execution_slots[first.index]
    generations := operation_storage_cold_generations(&storage, first_slot)
    testing.expect_value(t,
        active_operation_release_execution(&storage, first),
        Active_Operation_Status.Ok)

    second_reservation, reserve_status :=
        active_operation_reserve(&storage, 2, 22, 5)
    testing.expect_value(t, reserve_status, Active_Operation_Status.Ok)
    second := second_reservation.execution
    second_slot := storage.execution_slots[second.index]
    testing.expect(t, first.index == second.index)
    testing.expect(t, first.generation != second.generation)
    operation_storage_expect_cold_generations_advanced(
        t, &storage, second_slot, generations)
    testing.expect_value(t, active_operation_publish_outcome(
        &storage, outcome, .Committed), Active_Operation_Status.Ok)
    testing.expect_value(t,
        active_operation_release_execution(&storage, second),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_mark_outcome_sent(
        &storage, outcome), Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_acknowledge_outcome(
        &storage, outcome), Active_Operation_Status.Ok)
}

// Snapshot independent cold-slot generations before releasing execution.
operation_storage_cold_generations :: proc(
    storage: ^Active_Operation_Storage,
    slot: Active_Operation_Execution_Slot) -> Operation_Storage_Test_Generations {
    return {
        storage.payload_slots[slot.payload_index].generation,
        storage.target_slots[slot.target_index].generation,
        storage.claim_slots[slot.claim_index].generation,
        storage.control_slots[slot.control_index].generation,
    }
}

// Verify every reused cold locator receives a fresh nonwrapping generation.
operation_storage_expect_cold_generations_advanced :: proc(
    t: ^testing.T, storage: ^Active_Operation_Storage,
    slot: Active_Operation_Execution_Slot,
    generations: Operation_Storage_Test_Generations) {
    testing.expect(t,
        storage.payload_slots[slot.payload_index].generation > generations.payload)
    testing.expect(t,
        storage.target_slots[slot.target_index].generation > generations.target)
    testing.expect(t,
        storage.claim_slots[slot.claim_index].generation > generations.claim)
    testing.expect(t,
        storage.control_slots[slot.control_index].generation > generations.control)
}

// Test that outcome exhaustion rejects before publishing partial execution records.
@(test)
operation_storage_reservation_rolls_back_at_outcome_exhaustion :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)

    outcomes: [ACTIVE_OPERATION_SLOT_COUNT]Active_Operation_Outcome_Handle
    for index in 0..<ACTIVE_OPERATION_SLOT_COUNT {
        outcome, status := active_operation_reserve_outcome(
            &storage, u64(index + 1))
        testing.expect_value(t, status, Active_Operation_Status.Ok)
        outcomes[index] = outcome
    }
    before := active_operation_storage_diagnostics(&storage)
    _, status := active_operation_reserve(&storage, 1, 99, 8)
    testing.expect_value(t, status, Active_Operation_Status.Outcome_Full)
    after := active_operation_storage_diagnostics(&storage)
    testing.expect_value(t, after.execution_reserved,
        before.execution_reserved)
    testing.expect_value(t, after.payload_used, before.payload_used)
    testing.expect_value(t, after.target_used, before.target_used)
    testing.expect_value(t, after.claim_used, before.claim_used)
    testing.expect_value(t, after.control_used, before.control_used)
    testing.expect_value(t, after.outcome_used, before.outcome_used)

    for outcome in outcomes {
        slot_status := active_operation_publish_outcome(
            &storage, outcome, .Cancelled)
        testing.expect_value(t, slot_status, Active_Operation_Status.Ok)
        testing.expect_value(t, active_operation_mark_outcome_sent(
            &storage, outcome), Active_Operation_Status.Ok)
        testing.expect_value(t, active_operation_acknowledge_outcome(
            &storage, outcome), Active_Operation_Status.Ok)
    }
}

// Test teardown clears live execution and outcome handles.
@(test)
operation_storage_destroy_clears_live_logical_records :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    reservation, status := active_operation_reserve(&storage, 1, 31, 9)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    handle := reservation.execution
    outcome := reservation.outcome
    testing.expect_value(t, active_operation_admit(&storage, handle),
        Active_Operation_Status.Ok)
    active_operation_storage_destroy(&storage)
    diagnostics := active_operation_storage_diagnostics(&storage)
    testing.expect(t, !diagnostics.initialized)
    testing.expect_value(t,
        active_operation_release_execution(&storage, handle),
        Active_Operation_Status.Invalid_Handle)
    testing.expect_value(t,
        active_operation_acknowledge_outcome(&storage, outcome),
        Active_Operation_Status.Invalid_Handle)
}

// Verify copied modifier claims, candidate progress, and correlated outcome lifetime.
@(test)
operation_storage_modifier_claims_and_outcome_survive_execution_reuse :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    claim: Active_Operation_Claim = {
        kind = ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = 42,
    }
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = 42,
        duration = 1,
        displacement = {1, 0, 0},
    }
    missing_claim: Active_Operation_Submission_Request = {
        kind = 1,
        request_id = 100,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = request,
    }
    missing_claim.claim_count = 1
    missing_claim.claims[0] = {ACTIVE_OPERATION_CLAIM_ENTITY, 43}
    _, missing_claim_status := active_operation_reserve_modifier(
        &storage, missing_claim)
    testing.expect_value(
        t, missing_claim_status, Active_Operation_Status.Invalid_Argument)
    submission: Active_Operation_Submission_Request = {
        kind = 1,
        request_id = 101,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = request,
    }
    submission.claim_count = 1
    submission.claims[0] = claim
    reservation, status := active_operation_reserve_modifier(
        &storage, submission)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    testing.expect(t, storage.payload_slots[0].payload.modifier_request == request)
    testing.expect(t, active_operation_claims_conflict(
        &storage, []Active_Operation_Claim{claim}))
    testing.expect_value(t, active_operation_admit(&storage, reservation.execution),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_accept_progress(
        &storage, reservation.execution, 0.25), Active_Operation_Status.Ok)
    testing.expect_value(t, storage.execution_slots[0].elapsed, f64(0.25))
    testing.expect_value(t, active_operation_publish_outcome(
        &storage, reservation.outcome, .Committed), Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_release_execution(
        &storage, reservation.execution), Active_Operation_Status.Ok)
    operation_storage_expect_retained_outcome(t, &storage, reservation.outcome)
}

// Validate compass sentinel entities through their explicit physical-joint claims.
@(test)
operation_storage_circle_modifier_requires_compass_claims :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    request: modifier.Modifier_Request = {
        kind = .Construct_Circle,
        entity = 42,
        second_entity = 2,
        third_entity = 3,
        duration = 1,
        radius = 0.2,
    }
    submission: Active_Operation_Submission_Request = {
        kind = ACTIVE_OPERATION_KIND_MODIFIER,
        request_id = 102,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = request,
    }
    submission.claim_count = 3
    submission.claims[0] = {ACTIVE_OPERATION_CLAIM_ENTITY, 42}
    submission.claims[1] = {ACTIVE_OPERATION_CLAIM_ENTITY, 101}
    submission.claims[2] = {ACTIVE_OPERATION_CLAIM_ENTITY, 102}
    testing.expect(t, active_operation_modifier_request_valid(
        &storage, submission))
    submission.claim_count = 1
    testing.expect(t, !active_operation_modifier_request_valid(
        &storage, submission))
}

// Check outcome correlation, duplicate request rejection, and explicit acknowledgment.
operation_storage_expect_retained_outcome :: proc(
    t: ^testing.T, storage: ^Active_Operation_Storage,
    handle: Active_Operation_Outcome_Handle) {
    outcome, status := active_operation_read_outcome(storage, handle)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    testing.expect_value(t, outcome.request_id, u64(101))
    testing.expect_value(t, outcome.session_generation, u64(2))
    testing.expect_value(t, outcome.runtime_generation, u64(3))
    testing.expect_value(t, outcome.animation_generation, u64(4))
    testing.expect_value(t, outcome.state, Active_Operation_Outcome_State.Committed)
    testing.expect_value(t, active_operation_publish_outcome(
        storage, handle, .Rejected), Active_Operation_Status.Conflict)
    duplicate: Active_Operation_Submission_Request = {
        kind = 1,
        request_id = 101,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
    }
    duplicate.claim_count = 1
    duplicate.claims[0] = {1, 42}
    _, duplicate_status := active_operation_reserve_modifier(storage, duplicate)
    testing.expect_value(t, duplicate_status, Active_Operation_Status.Conflict)
    testing.expect_value(t, active_operation_mark_outcome_sent(storage, handle),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_acknowledge_outcome(storage, handle),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_acknowledge_outcome(storage, handle),
        Active_Operation_Status.Invalid_Handle)
}

// Exact-generation receipts release outcomes; stale and duplicate receipts are inert.
@(test)
operation_storage_outcome_acknowledgment_requires_exact_identity :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    reservation := operation_storage_test_publish_sent_outcome(&storage)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 10,
            outcome_generation = reservation.outcome.generation,
        }),
        Active_Operation_Status.Invalid_Handle)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 11,
            outcome_generation = reservation.outcome.generation + 1,
        }),
        Active_Operation_Status.Invalid_Handle)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 11,
            outcome_generation = reservation.outcome.generation,
        }),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_release_execution(
        &storage, reservation.execution), Active_Operation_Status.Ok)
}

// A delayed receipt cannot release a newly reused outcome slot.
@(test)
operation_storage_outcome_acknowledgment_rejects_reused_slot_receipts :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    first := operation_storage_test_publish_sent_outcome(&storage)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 11,
            outcome_generation = first.outcome.generation,
        }),
        Active_Operation_Status.Ok)
    testing.expect_value(t, active_operation_release_execution(
        &storage, first.execution), Active_Operation_Status.Ok)
    second := operation_storage_test_publish_sent_outcome(&storage)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 11,
            outcome_generation = first.outcome.generation,
        }),
        Active_Operation_Status.Invalid_Handle)
    testing.expect_value(t, active_operation_acknowledge_outcome_identity(
        &storage, {
            request_id = 1,
            session_generation = 21,
            runtime_generation = 9,
            animation_generation = 11,
            outcome_generation = second.outcome.generation,
        }),
        Active_Operation_Status.Ok)
}

// Publish one sent outcome with the common test correlation generations.
operation_storage_test_publish_sent_outcome :: proc(
    storage: ^Active_Operation_Storage) -> Active_Operation_Reservation {
    reservation, status := active_operation_reserve(storage, 1, 1, 21)
    assert(status == .Ok)
    slot := &storage.outcome_slots[reservation.outcome.index]
    slot.session_generation = 21
    slot.runtime_generation = 9
    slot.animation_generation = 11
    assert(active_operation_publish_outcome(
        storage, reservation.outcome, .Committed) == .Ok)
    assert(active_operation_mark_outcome_sent(storage, reservation.outcome) == .Ok)
    return reservation
}

// Refuse to wrap a free slot generation and distinguish it from ordinary fullness.
@(test)
operation_storage_generation_exhaustion_is_explicit :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    for &slot in storage.execution_slots {
        slot.generation = max(u64)
    }
    _, status := active_operation_reserve(&storage, 1, 1, 1)
    testing.expect_value(t, status, Active_Operation_Status.Identity_Exhausted)
    diagnostics := active_operation_storage_diagnostics(&storage)
    testing.expect_value(t, diagnostics.execution_reserved, 0)
    testing.expect_value(t, diagnostics.outcome_used, 0)
}

// Exercise exact cold-region backpressure and verify no partial reservation escapes.
@(test)
operation_storage_cold_capacity_failures_are_atomic :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    for &slot in storage.payload_slots {
        slot.occupied = true
    }
    operation_storage_expect_capacity_rejection(
        t, &storage, Active_Operation_Status.Payload_Full)
    active_operation_storage_destroy(&storage)
    testing.expect(t, active_operation_storage_init(&storage))
    for &slot in storage.target_slots {
        slot.occupied = true
    }
    operation_storage_expect_capacity_rejection(
        t, &storage, Active_Operation_Status.Target_Full)
    active_operation_storage_destroy(&storage)
    testing.expect(t, active_operation_storage_init(&storage))
    for &slot in storage.claim_slots {
        slot.occupied = true
    }
    operation_storage_expect_capacity_rejection(
        t, &storage, Active_Operation_Status.Claim_Full)
    active_operation_storage_destroy(&storage)
    testing.expect(t, active_operation_storage_init(&storage))
    for &slot in storage.control_slots {
        slot.occupied = true
    }
    operation_storage_expect_capacity_rejection(
        t, &storage, Active_Operation_Status.Control_Full)
    active_operation_storage_destroy(&storage)
}

// Assert cold capacity failure leaves execution and outcome reservations untouched.
operation_storage_expect_capacity_rejection :: proc(
    t: ^testing.T, storage: ^Active_Operation_Storage,
    expected: Active_Operation_Status) {
    _, status := active_operation_reserve(storage, 1, 99, 8)
    testing.expect_value(t, status, expected)
    diagnostics := active_operation_storage_diagnostics(storage)
    testing.expect_value(t, diagnostics.execution_reserved, 0)
    testing.expect_value(t, diagnostics.outcome_used, 0)
}

// Retire only the requested animation generation and preserve canceled outcomes.
@(test)
operation_storage_animation_retirement_cancels_matching_generation :: proc(
    t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    first, first_status := operation_storage_retirement_test_reserve(
        &storage, 201, 10, 5)
    second, second_status := operation_storage_retirement_test_reserve(
        &storage, 202, 11, 6)
    third, third_status := operation_storage_retirement_test_reserve(
        &storage, 203, 10, 7)
    testing.expect_value(t, first_status, Active_Operation_Status.Ok)
    testing.expect_value(t, second_status, Active_Operation_Status.Ok)
    testing.expect_value(t, third_status, Active_Operation_Status.Ok)
    active_operation_retire_animation_generation(&storage, 5)
    _, first_live := active_operation_observe(&storage, first.execution)
    _, second_live := active_operation_observe(&storage, second.execution)
    _, third_live := active_operation_observe(&storage, third.execution)
    testing.expect_value(t, first_live, false)
    testing.expect_value(t, second_live, true)
    testing.expect_value(t, third_live, true)
    active_operation_retire_session(&storage, 10)
    _, second_live = active_operation_observe(&storage, second.execution)
    _, third_live = active_operation_observe(&storage, third.execution)
    testing.expect_value(t, second_live, true)
    testing.expect_value(t, third_live, false)
    first_outcome, first_read_status :=
        active_operation_read_outcome(&storage, first.outcome)
    testing.expect_value(t, first_read_status, Active_Operation_Status.Ok)
    testing.expect_value(t, first_outcome.state, Active_Operation_Outcome_State.Cancelled)
    third_outcome, third_read_status :=
        active_operation_read_outcome(&storage, third.outcome)
    testing.expect_value(t, third_read_status, Active_Operation_Status.Ok)
    testing.expect_value(t, third_outcome.state, Active_Operation_Outcome_State.Cancelled)
}

// Prepare one reserved operation for generation-retirement tests.
operation_storage_retirement_test_reserve :: proc(
    storage: ^Active_Operation_Storage,
    request_id, session_generation, animation_generation: u64) -> (
        Active_Operation_Reservation, Active_Operation_Status) {
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = request_id,
        duration = 1,
    }
    claim: Active_Operation_Claim = {
        kind = ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = request_id,
    }
    submission: Active_Operation_Submission_Request = {
        kind = 1,
        request_id = request_id,
        session_generation = session_generation,
        runtime_generation = 11,
        animation_generation = animation_generation,
        modifier_request = request,
    }
    submission.claim_count = 1
    submission.claims[0] = claim
    reservation, status := active_operation_reserve_modifier(storage, submission)
    if status == .Ok {
        _ = active_operation_admit(storage, reservation.execution)
    }
    return reservation, status
}

// Verify group starts, orientation, claims, and all sample requests are copied.
operation_storage_copies_bounded_group_transform :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    submission: Active_Operation_Submission_Request = {
        kind = ACTIVE_OPERATION_KIND_GROUP_TRANSFORM,
        request_id = 301,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = {
            kind = .Rotate_Point,
            entity = 41,
            duration = 2,
            start_position = {1, 2, 3},
            axis_a = {0, 0, 0},
            axis_b = {0, 0, 1},
            angle = -2.5,
        },
        group_transform = {
            count = 2,
            orientation_entity = 43,
            orientation = {0, 0, 0, 1},
            oriented = true,
        },
        claim_count = 3,
    }
    submission.claims[0] = {
        kind = ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = 41,
    }
    submission.claims[1] = {
        kind = ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = 42,
    }
    submission.claims[2] = {
        kind = ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = 43,
    }
    submission.group_transform.targets[0] = {
        entity = 41,
        start_position = {1, 2, 3},
    }
    submission.group_transform.targets[1] = {
        entity = 42,
        start_position = {4, 5, 6},
    }
    reservation, status := active_operation_reserve_modifier(&storage, submission)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    submission.group_transform.targets[0].start_position = {}
    progress, found := active_operation_observe(&storage, reservation.execution)
    testing.expect(t, found)
    testing.expect_value(t, progress.group_transform.targets[0].start_position,
        geometry.Vector3{1, 2, 3})
    requests: [ACTIVE_OPERATION_GROUP_TARGET_CAPACITY + 1]modifier.Modifier_Request
    request_count: int
    testing.expect(t, active_operation_group_sample_requests(
        progress.group_transform, progress.modifier_request, 1,
        &requests, &request_count))
    testing.expect_value(t, request_count, 3)
    testing.expect_value(t, requests[0].elapsed, f32(1))
    testing.expect_value(t, requests[1].entity, u64(42))
    testing.expect_value(t, requests[2].kind,
        modifier.Modifier_Kind.Rotate_Shape_Orientation)
    testing.expect_value(t, requests[2].entity, u64(43))
    testing.expect_value(t,
        active_operation_release_execution(&storage, reservation.execution),
        Active_Operation_Status.Ok)
}

// Verify native polygon traces retain their ordered fixed-capacity targets.
@(test)
operation_storage_copies_bounded_polygon_trace :: proc(t: ^testing.T) {
    storage: Active_Operation_Storage
    testing.expect(t, active_operation_storage_init(&storage))
    defer active_operation_storage_destroy(&storage)
    submission: Active_Operation_Submission_Request = {
        kind = ACTIVE_OPERATION_KIND_POLYGON_TRACE,
        request_id = 302,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = {
            kind = .Identity,
            entity = 50,
            duration = 2,
            radius = 0.14,
        },
        polygon_trace = {
            count = 3,
        },
        claim_count = 4,
    }
    submission.polygon_trace.vertices[0] = {51, {0, 0, 0}}
    submission.polygon_trace.vertices[1] = {52, {1, 0, 0}}
    submission.polygon_trace.vertices[2] = {53, {0, 1, 0}}
    submission.claims[0] = {ACTIVE_OPERATION_CLAIM_ENTITY, 50}
    submission.claims[1] = {ACTIVE_OPERATION_CLAIM_ENTITY, 51}
    submission.claims[2] = {ACTIVE_OPERATION_CLAIM_ENTITY, 52}
    submission.claims[3] = {ACTIVE_OPERATION_CLAIM_ENTITY, 53}
    reservation, status := active_operation_reserve_modifier(&storage, submission)
    testing.expect_value(t, status, Active_Operation_Status.Ok)
    submission.polygon_trace.vertices[1].position = {}
    progress, found := active_operation_observe(&storage, reservation.execution)
    testing.expect(t, found)
    testing.expect_value(t, progress.polygon_trace.vertices[1].position,
        geometry.Vector3{1, 0, 0})
    testing.expect_value(t,
        active_operation_release_execution(&storage, reservation.execution),
        Active_Operation_Status.Ok)
}
