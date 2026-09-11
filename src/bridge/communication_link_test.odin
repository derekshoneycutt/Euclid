package bridge

import "../core"
import protocol "../core/protocol"

import "base:runtime"
import "core:testing"
import "core:time"

Communication_Link_Test_Message :: struct {
    sequence: u64,
}

Communication_Link_Oversized_Message :: struct {
    bytes: [8 * 1024]u8,
}

Communication_Link_Egress_Collector :: struct {
    messages: [2]^core.Julia_Host_Egress,
    count: int,
}

COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE :: 33

// Retain routed test envelopes in arrival order for ownership assertions.
communication_link_test_collect_egress :: proc(
    user_data: rawptr, message: ^core.Julia_Host_Egress) -> bool {
    collector := cast(^Communication_Link_Egress_Collector)user_data
    assert(collector != nil && collector^.count < len(collector^.messages))
    collector^.messages[collector^.count] = message
    collector^.count += 1
    return true
}

// Publish one typed content completion through the worker-owned transport helper.
communication_link_test_send_invoke_completion :: proc(
    service: ^Julia_Runtime_Service, request_id: u64) -> core.Communication_Send_Outcome {
    return send_typed_julia_completion(service, {
        protocol = .Runtime_Content_Initialize,
        request_kind = .Invoke,
        request_id = request_id,
    }, {
        kind = .Invoke_Complete,
        request_kind = .Invoke,
        request_id = request_id,
        succeeded = true,
    })
}

// Receive and validate the five non-shutdown typed control families.
communication_link_test_expect_control_families :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service,
    expected_state: ^core.Euclid_General_State,
    tick_handle: core.Animation_Tick_Slot_Handle,
    lifecycle_handle: core.Animation_Lifecycle_Slot_Handle) {
    initialize_message, _ := communication_link_try_recv(&service.request_link)
    content_message, _ := communication_link_try_recv(&service.request_link)
    tick_message, _ := communication_link_try_recv(&service.request_link)
    lifecycle_message, _ := communication_link_try_recv(&service.request_link)
    harness_message, _ := communication_link_try_recv(&service.request_link)
    _, initialize_ok := initialize_message^.(core.Runtime_Initialize_Requested)
    content, content_ok := content_message^.(core.Runtime_Content_Initialize_Requested)
    tick, tick_ok := tick_message^.(core.Animation_Tick_Requested)
    lifecycle, lifecycle_ok :=
        lifecycle_message^.(core.Animation_Lifecycle_Requested)
    harness, harness_ok := harness_message^.(core.Harness_Scenario_Requested)
    testing.expect(t, initialize_ok && content_ok && tick_ok &&
        lifecycle_ok && harness_ok)
    testing.expect_value(t, tick.handle, tick_handle)
    testing.expect_value(t, lifecycle.handle, lifecycle_handle)
    testing.expect_value(t, content.native_state, expected_state)
    testing.expect_value(t, harness.scenario_name, "typed_case")
    testing.expect_value(t, harness.step_count, i64(8))
    messages := [5]^core.Julia_Host_Ingress{initialize_message, content_message,
        tick_message, lifecycle_message, harness_message}
    for message in messages {
        testing.expect(t, communication_link_return(&service.request_link, message))
    }
    _ = drain_julia_ingress_returns(service)
}

// Allocate a service with initialized links and no worker-owned runtime state.
communication_link_test_service :: proc(t: ^testing.T) -> ^Julia_Runtime_Service {
    service := new(Julia_Runtime_Service, context.allocator)
    testing.expect_value(t, init_julia_runtime_channels(service),
        runtime.Allocator_Error.None)
    service.next_request_id = 1
    service.lifecycle = .Ready
    return service
}

// Destroy one link-only service after its producer-side return queues are drained.
communication_link_test_service_destroy :: proc(service: ^Julia_Runtime_Service) {
    _ = drain_julia_ingress_returns(service)
    _ = drain_julia_egress_returns(service)
    if service.display_pending_view_content != nil {
        destroy_julia_egress_message(
            service, service.display_pending_view_content)
    }
    if service.pending_view_content != nil {
        destroy_julia_egress_message(service, service.pending_view_content)
    }
    communication_link_destroy(&service.event_link)
    communication_link_destroy(&service.request_link)
    free(service)
}

// Verify evaluation source ownership survives saturation and pooled storage recovers.
@(test)
terminal_ingress_pressure_preserves_caller_source :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    for request_id in 1..=JULIA_REQUEST_CAPACITY {
        _, sent := try_submit_runtime_initialize(service)
        testing.expect(t, sent)
        testing.expect_value(t, service.active_request_id, u64(request_id))
    }
    source := "caller-owned"
    request := protocol.Evaluation_Requested{
        request_id = 44,
        animation_generation = 7,
        code = source,
    }
    testing.expect_value(t, send_terminal_evaluation(service, request),
        core.Communication_Send_Outcome.Queue_Full)
    testing.expect_value(t, request.code, source)

    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.request_link, message))
    testing.expect_value(t, send_terminal_evaluation(service, request),
        core.Communication_Send_Outcome.Sent)
}

// Verify oversized terminal source fails without taking caller ownership.
@(test)
terminal_ingress_allocation_failure_preserves_caller_source :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    oversized: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES + 1]u8
    source := string(oversized[:])
    request := protocol.Evaluation_Requested{code = source}
    testing.expect_value(t, send_terminal_evaluation(service, request),
        core.Communication_Send_Outcome.Allocation_Failed)
    testing.expect_value(t, request.code, source)
}

// Round-trip one fixed ingress variant through display-owned allocation and return.
terminal_transport_expect_fixed_ingress :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service,
    value: core.Julia_Host_Ingress) {
    testing.expect_value(t, send_terminal_ingress(service, value),
        core.Communication_Send_Outcome.Sent)
    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.request_link, message))
}

// Round-trip one fixed egress variant through worker-owned allocation and return.
terminal_transport_expect_fixed_egress :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service,
    value: core.Julia_Host_Egress) {
    testing.expect_value(t, send_terminal_egress(service, value),
        core.Communication_Send_Outcome.Sent)
    message, received := communication_link_try_recv(&service.event_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.event_link, message))
}

// Verify every fixed terminal family transfers through Euclid's existing links.
@(test)
terminal_transport_round_trips_fixed_message_families :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    ingress := [5]core.Julia_Host_Ingress{
        protocol.Terminal_Session_Started{animation_generation = 3},
        protocol.Terminal_Session_Closed{animation_generation = 3},
        protocol.Terminal_Interactive_Input{animation_generation = 3},
        protocol.Terminal_Geometry_Accepted{animation_generation = 3},
        protocol.Terminal_Capabilities_Accepted{animation_generation = 3},
    }
    for value in ingress {
        terminal_transport_expect_fixed_ingress(t, service, value)
    }
    egress := [8]core.Julia_Host_Egress{
        protocol.Evaluation_Incomplete{animation_generation = 3},
        protocol.Evaluation_Completed{animation_generation = 3},
        protocol.Completion_Failed{animation_generation = 3},
        protocol.Terminal_Input_Acquired{animation_generation = 3},
        protocol.Terminal_Input_Released{animation_generation = 3},
        protocol.Terminal_Geometry_Observed{animation_generation = 3},
        protocol.Terminal_Capabilities_Observed{animation_generation = 3},
        protocol.Terminal_Session_Stopped{animation_generation = 3},
    }
    for value in egress {
        terminal_transport_expect_fixed_egress(t, service, value)
    }
}

// Verify dynamic completion payloads are cloned and reclaimed by their producers.
@(test)
terminal_transport_round_trips_completion_payloads :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    request := protocol.Completion_Requested{
        request_id = 7,
        animation_generation = 3,
        code = "alp",
        cursor_byte = 3,
    }
    testing.expect_value(t, send_terminal_completion_request(service, request),
        core.Communication_Send_Outcome.Sent)
    ingress, ingress_received := communication_link_try_recv(&service.request_link)
    testing.expect(t, ingress_received)
    cloned_request, is_request := ingress^.(protocol.Completion_Requested)
    testing.expect(t, is_request)
    testing.expect_value(t, cloned_request.code, "alp")
    testing.expect(t, communication_link_return(&service.request_link, ingress))

    result := protocol.Completion_Result{
        request_id = 7,
        animation_generation = 3,
        found = true,
        insertion = "alpha",
    }
    testing.expect_value(t, send_terminal_completion_result(service, result),
        core.Communication_Send_Outcome.Sent)
    egress, egress_received := communication_link_try_recv(&service.event_link)
    testing.expect(t, egress_received)
    cloned_result, is_result := egress^.(protocol.Completion_Result)
    testing.expect(t, is_result)
    testing.expect_value(t, cloned_result.insertion, "alpha")
    testing.expect(t, communication_link_return(&service.event_link, egress))
    testing.expect_value(t, drain_julia_ingress_returns(service), 1)
    testing.expect_value(t, drain_julia_egress_returns(service), 1)
}

// Verify session-ready transport clones borrowed banner text into producer storage.
@(test)
terminal_transport_clones_session_ready_banner :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    source := [6]u8{'J', 'u', 'l', 'i', 'a', '\n'}
    banner := string(source[:])
    testing.expect_value(t, send_terminal_session_ready(service, {
        animation_generation = 3, banner = banner,
    }), core.Communication_Send_Outcome.Sent)
    source[0] = 'X'
    message, received := communication_link_try_recv(&service.event_link)
    testing.expect(t, received)
    ready, is_ready := message^.(protocol.Terminal_Session_Ready)
    testing.expect(t, is_ready)
    testing.expect_value(t, ready.banner, "Julia\n")
    testing.expect(t, communication_link_return(&service.event_link, message))
    testing.expect_value(t, drain_julia_egress_returns(service), 1)
}

// Verify shutdown rejects fixed and dynamic terminal messages before ownership transfer.
@(test)
terminal_transport_rejects_all_messages_during_shutdown :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    service.lifecycle = .Shutdown_Requested
    testing.expect_value(t, send_terminal_ingress(service,
        protocol.Terminal_Session_Closed{animation_generation = 3}),
        core.Communication_Send_Outcome.Runtime_Stopping)
    testing.expect_value(t, send_terminal_evaluation(service,
        protocol.Evaluation_Requested{code = "1"}),
        core.Communication_Send_Outcome.Runtime_Stopping)
    testing.expect_value(t, send_terminal_egress(service,
        protocol.Terminal_Session_Stopped{animation_generation = 3}),
        core.Communication_Send_Outcome.Runtime_Stopping)
    testing.expect_value(t, send_terminal_output(service,
        protocol.Terminal_Output_Batch{bytes = "x"}),
        core.Communication_Send_Outcome.Runtime_Stopping)
}

// Verify bounded transfer preserves pointer identity and producer-side reclamation.
@(test)
communication_link_round_trip_and_saturation :: proc(t: ^testing.T) {
    link: core.Communication_Link(Communication_Link_Test_Message)
    testing.expect_value(t, communication_link_init(&link, 2, 64 * 1024),
        runtime.Allocator_Error.None)
    defer communication_link_destroy(&link)

    first, first_error := communication_link_alloc(&link)
    second, second_error := communication_link_alloc(&link)
    unsent, unsent_error := communication_link_alloc(&link)
    testing.expect_value(t, first_error, runtime.Allocator_Error.None)
    testing.expect_value(t, second_error, runtime.Allocator_Error.None)
    testing.expect_value(t, unsent_error, runtime.Allocator_Error.None)
    first.sequence = 11
    second.sequence = 12
    testing.expect(t, communication_link_try_send(&link, first))
    testing.expect(t, communication_link_try_send(&link, second))
    testing.expect(t, !communication_link_try_send(&link, unsent))
    communication_link_free(&link, unsent)

    received_first, first_ok := communication_link_try_recv(&link)
    received_second, second_ok := communication_link_try_recv(&link)
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, received_first, first)
    testing.expect_value(t, received_second, second)
    testing.expect_value(t, received_first.sequence, u64(11))
    testing.expect_value(t, received_second.sequence, u64(12))
    testing.expect(t, communication_link_return(&link, received_first))
    testing.expect(t, communication_link_return(&link, received_second))
    testing.expect_value(t, communication_link_drain_returns(&link), 2)
}

// Verify pool exhaustion is observable without an ambient allocator fallback.
@(test)
communication_link_reports_allocation_failure :: proc(t: ^testing.T) {
    link: core.Communication_Link(Communication_Link_Oversized_Message)
    testing.expect_value(t, communication_link_init(&link, 1, 4 * 1024),
        runtime.Allocator_Error.None)
    defer communication_link_destroy(&link)

    message, allocation_error := communication_link_alloc(&link)
    testing.expect(t, message == nil)
    testing.expect(t, allocation_error != .None)
}

// Verify provisional request and event pools cover all queued, returned, and held envelopes.
@(test)
julia_runtime_link_pools_cover_envelope_budget :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    requests: [COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE]^core.Julia_Host_Ingress
    events: [COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE]^core.Julia_Host_Egress

    for index in 0..<COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE {
        request, request_error := communication_link_alloc(&service.request_link)
        event, event_error := communication_link_alloc(&service.event_link)
        testing.expect_value(t, request_error, runtime.Allocator_Error.None)
        testing.expect_value(t, event_error, runtime.Allocator_Error.None)
        requests[index] = request
        events[index] = event
    }
    for index in 0..<COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE {
        communication_link_free(&service.request_link, requests[index])
        communication_link_free(&service.event_link, events[index])
    }
}

// Verify service transport copies fixed records before returning producer envelopes.
@(test)
julia_runtime_links_round_trip_requests_and_events :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)

    request_id, sent := try_submit_runtime_initialize(service)
    testing.expect(t, sent)
    request_message, request_ok := communication_link_try_recv(&service.request_link)
    testing.expect(t, request_ok)
    request, is_request := request_message^.(core.Runtime_Initialize_Requested)
    testing.expect(t, is_request)
    testing.expect_value(t, request.request_id, request_id)
    testing.expect(t, communication_link_return(&service.request_link, request_message))

    testing.expect_value(t, send_typed_julia_completion(service, {
        protocol = .Runtime_Initialize,
        request_kind = .Initialize,
        request_id = request_id,
    }, {
        kind = .Initialized,
        request_kind = .Initialize,
        request_id = request_id,
        succeeded = true,
    }), core.Communication_Send_Outcome.Sent)
    event, event_ok := try_route_julia_egress(service)
    testing.expect(t, event_ok)
    testing.expect_value(t, event.request_id, request_id)
    testing.expect_value(t, service.active_request_id, u64(0))
}

// Verify every typed control API publishes its operation-specific ingress variant.
@(test)
julia_control_transport_round_trips_all_request_families :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    tick_handle := core.Animation_Tick_Slot_Handle{
        index = 2, reservation_generation = 11,
    }
    lifecycle_handle := core.Animation_Lifecycle_Slot_Handle{
        index = 0, reservation_generation = 12,
    }

    _, initialize_sent := try_submit_runtime_initialize(service)
    _, content_sent := try_submit_runtime_content_initialize(
        service, state)
    _, tick_sent := try_submit_animation_tick(service, {
        handle = tick_handle,
        animation_generation = 7,
        sequence = 31,
    })
    _, lifecycle_sent := try_submit_animation_lifecycle(
        service, lifecycle_handle, 6, 8)
    _, harness_sent := try_submit_harness_scenario(
        service, "typed_case", 8)
    testing.expect(t, initialize_sent && content_sent && tick_sent &&
        lifecycle_sent && harness_sent)

    communication_link_test_expect_control_families(
        t, service, state, tick_handle, lifecycle_handle)

    _, shutdown_sent := try_submit_runtime_shutdown(service)
    testing.expect(t, shutdown_sent)
    shutdown_message, shutdown_received :=
        communication_link_try_recv(&service.request_link)
    testing.expect(t, shutdown_received)
    _, shutdown_ok := shutdown_message^.(core.Runtime_Shutdown_Requested)
    testing.expect(t, shutdown_ok)
    testing.expect(t, communication_link_return(&service.request_link, shutdown_message))
}

// Verify harness names are copied into pooled storage, bounded, and reclaimed on return.
@(test)
julia_harness_payload_is_bounded_and_reclaimed :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    source := [10]u8{'t', 'y', 'p', 'e', 'd', '_', 'c', 'a', 's', 'e'}
    _, sent := try_submit_harness_scenario(service, string(source[:]), 12)
    testing.expect(t, sent)
    source[0] = 'X'
    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    request, is_request := message^.(core.Harness_Scenario_Requested)
    testing.expect(t, is_request)
    testing.expect_value(t, request.scenario_name, "typed_case")
    testing.expect_value(t, request.step_count, i64(12))
    testing.expect(t, communication_link_return(&service.request_link, message))
    testing.expect_value(t, drain_julia_ingress_returns(service), 1)

    oversized := make([]u8, core.HARNESS_SCENARIO_NAME_CAPACITY + 1,
        context.allocator)
    defer delete(oversized, context.allocator)
    rejected_id, rejected := try_submit_harness_scenario(
        service, string(oversized), 12)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
}

// Verify a completion with foreign identity cannot clear the active request.
@(test)
julia_control_completion_rejects_mismatched_request_identity :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    service.active_request_id = 41
    service.active_request_kind = .Animation_Tick
    service.animation_tick_pending = true
    handle := core.Animation_Tick_Slot_Handle{
        index = 1, reservation_generation = 9,
    }
    testing.expect_value(t, send_typed_julia_completion(service, {
        protocol = .Animation_Tick,
        request_kind = .Animation_Tick,
        request_id = 42,
        slot_index = 1,
        tick_handle = handle,
        animation_generation = 7,
        sequence = 12,
    }, {
        kind = .Animation_Tick_Complete,
        request_kind = .Animation_Tick,
        request_id = 42,
        slot_index = 1,
        succeeded = true,
    }), core.Communication_Send_Outcome.Sent)
    _, routed := try_route_julia_egress(service)
    testing.expect(t, !routed)
    testing.expect_value(t, service.active_request_id, u64(41))
    testing.expect(t, service.animation_tick_pending)
}

// Initialize one complete tick slot and its active transport correlation.
communication_link_test_prepare_tick_completion :: proc(
    service: ^Julia_Runtime_Service) -> core.Animation_Tick_Completed {
    service.active_request_id = 41
    service.active_request_kind = .Animation_Tick
    service.animation_tick_pending = true
    service.animation_generation = 7
    slot := &service.animation_tick_slots[1]
    slot.state = .Complete
    slot.request_id = 41
    slot.reservation_generation = 9
    slot.generation = 7
    slot.sequence = 12
    return {
        completion = {request_id = 41, succeeded = true},
        handle = {index = 1, reservation_generation = 9},
        animation_generation = 7,
        sequence = 12,
    }
}

// Verify exact completion identity clears the guard and a duplicate is rejected.
@(test)
animation_tick_completion_accepts_once :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_tick_completion(service)

    event, accepted := accept_animation_tick_completion(service, completed)
    testing.expect(t, accepted)
    testing.expect_value(t, event.slot_index, i32(1))
    testing.expect_value(t, service.active_request_id, u64(0))
    testing.expect(t, !service.animation_tick_pending)
    _, duplicate_accepted := accept_animation_tick_completion(service, completed)
    testing.expect(t, !duplicate_accepted)
}

// Verify invalid indices and stale slot or animation generations cannot complete a tick.
@(test)
animation_tick_completion_rejects_stale_handles :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_tick_completion(service)

    invalid_index := completed
    invalid_index.handle.index = i32(ANIMATION_TICK_SLOT_COUNT)
    _, invalid_accepted := accept_animation_tick_completion(service, invalid_index)
    testing.expect(t, !invalid_accepted)
    stale_incarnation := completed
    stale_incarnation.handle.reservation_generation -= 1
    _, incarnation_accepted :=
        accept_animation_tick_completion(service, stale_incarnation)
    testing.expect(t, !incarnation_accepted)
    testing.expect_value(t, service.animation_tick_slots[1].state,
        core.Animation_Tick_Slot_State.Complete)
    stale_animation := completed
    stale_animation.animation_generation -= 1
    service.animation_tick_slots[1].generation -= 1
    _, animation_accepted := accept_animation_tick_completion(service, stale_animation)
    testing.expect(t, !animation_accepted)
    testing.expect_value(t, service.animation_tick_slots[1].state,
        core.Animation_Tick_Slot_State.Free)
    testing.expect_value(t, service.active_request_id, u64(0))
    testing.expect(t, !service.animation_tick_pending)
}

// Verify recycling one fixed slot advances its reservation incarnation.
@(test)
animation_tick_slot_reuse_advances_reservation_generation :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    first_index := reserve_animation_tick_slot(service)
    first_generation := service.animation_tick_slots[first_index].reservation_generation
    service.animation_tick_slots[first_index].state = .Accepted
    release_completed_animation_ticks(service)
    second_index := reserve_animation_tick_slot(service)

    testing.expect_value(t, second_index, first_index)
    testing.expect_value(t,
        service.animation_tick_slots[second_index].reservation_generation,
        first_generation + 1)
}

// Initialize one completed lifecycle slot and its active transport correlation.
communication_link_test_prepare_lifecycle_completion :: proc(
    service: ^Julia_Runtime_Service,
    succeeded: bool) -> core.Animation_Lifecycle_Completed {
    service.active_request_id = 51
    service.active_request_kind = .Invoke
    slot := &service.animation_lifecycle_slot
    slot.state = .Complete
    slot.outcome = .Committed if succeeded else .Rolled_Back
    slot.request_id = 51
    slot.reservation_generation = 4
    slot.runtime_generation = 3
    slot.animation_generation = 8
    return {
        completion = {request_id = 51, succeeded = succeeded},
        handle = {index = 0, reservation_generation = 4},
        runtime_generation = 3,
        animation_generation = 8,
    }
}

// Verify the bounded lifecycle transaction rejects a second reservation.
@(test)
animation_lifecycle_slot_saturates_at_one :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    _, first_reserved := reserve_animation_lifecycle_slot(service)
    _, second_reserved := reserve_animation_lifecycle_slot(service)

    testing.expect(t, first_reserved)
    testing.expect(t, !second_reserved)
}

// Verify a successful exact lifecycle completion is accepted and recycled once.
@(test)
animation_lifecycle_completion_accepts_once :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_lifecycle_completion(service, true)

    event, accepted := accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, accepted)
    testing.expect(t, event.succeeded)
    testing.expect_value(t, service.animation_lifecycle_slot.state,
        core.Animation_Lifecycle_Slot_State.Free)
    _, duplicate_accepted := accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, !duplicate_accepted)
}

// Verify rollback is a valid scalar outcome that still closes the transaction.
@(test)
animation_lifecycle_completion_accepts_rollback :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_lifecycle_completion(service, false)

    event, accepted := accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, accepted)
    testing.expect(t, !event.succeeded)
    testing.expect_value(t, service.active_request_id, u64(0))
    testing.expect_value(t, service.animation_lifecycle_slot.state,
        core.Animation_Lifecycle_Slot_State.Free)
}

// Verify stale lifecycle handles and echoed generations cannot recycle the slot.
@(test)
animation_lifecycle_completion_rejects_stale_identity :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_lifecycle_completion(service, true)
    stale_handle := completed
    stale_handle.handle.reservation_generation -= 1
    _, handle_accepted := accept_animation_lifecycle_completion(service, stale_handle)
    testing.expect(t, !handle_accepted)
    stale_generation := completed
    stale_generation.runtime_generation -= 1
    _, generation_accepted :=
        accept_animation_lifecycle_completion(service, stale_generation)
    testing.expect(t, !generation_accepted)
    testing.expect_value(t, service.animation_lifecycle_slot.state,
        core.Animation_Lifecycle_Slot_State.Complete)
    testing.expect_value(t, service.active_request_id, u64(51))
}

// Verify exact completion recycling advances the next lifecycle slot incarnation.
@(test)
animation_lifecycle_slot_reuse_advances_reservation_generation :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    completed := communication_link_test_prepare_lifecycle_completion(service, true)
    _, accepted := accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, accepted)
    handle, reserved := reserve_animation_lifecycle_slot(service)

    testing.expect(t, reserved)
    testing.expect_value(t, handle.reservation_generation, u64(5))
}

// Verify startup routing retains presentation and transfers it when display dispatch attaches.
@(test)
julia_egress_router_transfers_startup_view_content :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    content_message, content_error := communication_link_alloc(&service.event_link)
    testing.expect_value(t, content_error, runtime.Allocator_Error.None)
    bytes, bytes_error := communication_link_alloc_bytes(&service.event_link, 3)
    testing.expect_value(t, bytes_error, runtime.Allocator_Error.None)
    copy(bytes, []u8{'t', 'e', 'x'})
    content_message^ = core.Julia_Host_Egress(core.View_Content_Ready{
        presentation_generation = 7,
        content = {mime = .Text_Latex, bytes = bytes},
    })
    testing.expect(t, communication_link_try_send(
        &service.event_link, content_message))
    testing.expect_value(t, communication_link_test_send_invoke_completion(
        service, 9), core.Communication_Send_Outcome.Sent)

    _, content_is_event := try_route_julia_egress(service)
    testing.expect(t, !content_is_event)
    testing.expect(t, service.display_pending_view_content == content_message)
    collector: Communication_Link_Egress_Collector
    configure_julia_egress_dispatch(
        service, communication_link_test_collect_egress, rawptr(&collector))
    testing.expect_value(t, collector.count, 1)
    testing.expect(t, collector.messages[0] == content_message)

    event, ok := try_route_julia_egress(service)
    testing.expect(t, ok)
    testing.expect_value(t, event.request_id, u64(9))
    content, is_content := collector.messages[0]^.(core.View_Content_Ready)
    testing.expect(t, is_content)
    testing.expect_value(t, string(content.content.bytes), "tex")
    testing.expect(t, return_julia_egress(service, collector.messages[0]))
    clear_julia_egress_dispatch(service)
}

// Verify centralized routing dispatches ordered terminal egress before the following event.
@(test)
julia_egress_router_preserves_terminal_event_order :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    collector: Communication_Link_Egress_Collector
    configure_julia_egress_dispatch(
        service, communication_link_test_collect_egress, rawptr(&collector))
    testing.expect_value(t, send_terminal_output(service, {
        request_id = 7,
        animation_generation = 3,
        bytes = "ordered",
    }), core.Communication_Send_Outcome.Sent)
    testing.expect_value(t, communication_link_test_send_invoke_completion(
        service, 9), core.Communication_Send_Outcome.Sent)

    _, event_received := try_route_julia_egress(service)
    testing.expect(t, !event_received)
    testing.expect_value(t, collector.count, 1)
    output, is_output := collector.messages[0]^.(protocol.Terminal_Output_Batch)
    testing.expect(t, is_output)
    testing.expect_value(t, output.bytes, "ordered")
    event, received := try_route_julia_egress(service)
    testing.expect(t, received)
    testing.expect_value(t, event.request_id, u64(9))
    testing.expect(t, return_julia_egress(service, collector.messages[0]))
    clear_julia_egress_dispatch(service)
}

// Verify full request queues preserve IDs and recover after producer reclamation.
@(test)
julia_request_link_saturation_is_nonblocking :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)

    for expected_id in 1..=JULIA_REQUEST_CAPACITY {
        request_id, sent := try_submit_runtime_initialize(service)
        testing.expect(t, sent)
        testing.expect_value(t, request_id, u64(expected_id))
    }
    rejected_id, rejected := try_submit_runtime_initialize(service)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
    testing.expect_value(t, service.next_request_id, u64(JULIA_REQUEST_CAPACITY + 1))

    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.request_link, message))
    recovered_id, recovered := try_submit_runtime_initialize(service)
    testing.expect(t, recovered)
    testing.expect_value(t, recovered_id, u64(JULIA_REQUEST_CAPACITY + 1))
}

// Verify shutdown admission closes request transport without consuming another ID.
@(test)
julia_request_link_rejects_work_after_shutdown_begins :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)

    shutdown_id, shutdown_sent := try_submit_runtime_shutdown(service)
    testing.expect(t, shutdown_sent)
    testing.expect_value(t, shutdown_id, u64(1))
    testing.expect_value(t, service.lifecycle, Julia_Lifecycle_State.Shutdown_Requested)

    rejected_id, rejected := try_submit_runtime_initialize(service)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
    testing.expect_value(t, service.next_request_id, u64(2))
    testing.expect_value(t, send_julia_ingress_control(
        service, core.Runtime_Initialize_Requested{request_id = 2}),
        core.Communication_Send_Outcome.Runtime_Stopping)
}

// Verify shutdown admission recovers after full ingress and completes through the router.
@(test)
julia_shutdown_recovers_from_ingress_saturation :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    for _ in 0..<JULIA_REQUEST_CAPACITY {
        _, sent := try_submit_runtime_initialize(service)
        testing.expect(t, sent)
    }
    lifecycle_before_shutdown := service.lifecycle
    rejected_id, rejected := try_submit_runtime_shutdown(service)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
    testing.expect_value(t, service.lifecycle, lifecycle_before_shutdown)

    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.request_link, message))
    shutdown_id, sent := try_submit_runtime_shutdown(service)
    testing.expect(t, sent)
    testing.expect_value(t, shutdown_id, u64(JULIA_REQUEST_CAPACITY + 1))
    testing.expect_value(t, service.lifecycle,
        Julia_Lifecycle_State.Shutdown_Requested)

    testing.expect_value(t, send_typed_julia_completion(service, {
        protocol = .Runtime_Shutdown,
        request_kind = .Shutdown,
        request_id = shutdown_id,
    }, {
        kind = .Shutdown_Complete,
        request_kind = .Shutdown,
        request_id = shutdown_id,
        succeeded = true,
    }), core.Communication_Send_Outcome.Sent)
    testing.expect(t, wait_runtime_shutdown_completion(
        service, shutdown_id, time.tick_now(), 1.0))
    testing.expect_value(t, service.lifecycle, Julia_Lifecycle_State.Stopped)
}

// Fill the worker-owned outbound lane with fixed completion events.
communication_link_fill_event_queue :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service) {
    for request_id in 1..=JULIA_EVENT_CAPACITY {
        testing.expect_value(t, communication_link_test_send_invoke_completion(
            service, u64(request_id)), core.Communication_Send_Outcome.Sent)
    }
}

// Drain every queued event and return each borrowed envelope to its producer.
communication_link_drain_event_queue :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service) {

    for _ in 0..<JULIA_EVENT_CAPACITY {
        message, ok := communication_link_try_recv(&service.event_link)
        testing.expect(t, ok)
        testing.expect(t, communication_link_return(&service.event_link, message))
    }
}

// Flush one retained presentation after creating outbound capacity, then reclaim it.
communication_link_flush_pending_view_content :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service) {
    first, received := communication_link_try_recv(&service.event_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.event_link, first))
    testing.expect_value(t, drain_julia_egress_returns(service), 1)
    testing.expect_value(t, flush_pending_view_content(service),
        core.Communication_Send_Outcome.Sent)
}

// Verify saturated presentation delivery retains only the newest exact pooled bytes.
@(test)
julia_view_content_retry_replaces_and_reclaims_nested_bytes :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    interface: core.Euclid_Julia_Interface
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.julia_runtime_service = service
    state.julia_interface = &interface
    communication_link_fill_event_queue(t, service)

    maximum_source: [core.PRESENTATION_MAX_SOURCE_BYTES]u8
    maximum_outcome := send_presented_text(state, .Text_Latex, maximum_source[:])
    testing.expect_value(t, maximum_outcome,
        core.Communication_Send_Outcome.Queue_Full)
    newest_text: string = "newest"
    newest_source := transmute([]u8)newest_text
    newest_outcome := send_presented_text(state, .Text_Plain, newest_source)
    testing.expect_value(t, newest_outcome,
        core.Communication_Send_Outcome.Queue_Full)
    if service.pending_view_content == nil {
        return
    }
    pending, is_content := service.pending_view_content^.(core.View_Content_Ready)
    testing.expect(t, is_content)
    if !is_content {
        return
    }
    testing.expect_value(t, pending.content.mime, core.Presentation_Mime.Text_Plain)
    testing.expect_value(t, string(pending.content.bytes), "newest")

    communication_link_flush_pending_view_content(t, service)
    communication_link_drain_event_queue(t, service)
    testing.expect_value(t, drain_julia_egress_returns(service), JULIA_EVENT_CAPACITY)
    testing.expect(t, service.pending_view_content == nil)
}

// Verify the raw-pointer ABI clones exact counted bytes and rejects invalid input.
@(test)
publish_presented_text_clones_exact_counted_bytes :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    interface: core.Euclid_Julia_Interface
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.saved_context = context
    state.julia_runtime_service = service
    state.julia_interface = &interface
    source := [?]u8{'A', 0, 'B'}

    testing.expect_value(t, publish_presented_text(
        state, 1, raw_data(source[:]), i32(len(source))), i32(BRIDGE_STATUS_OK))
    message, received := communication_link_try_recv(&service.event_link)
    testing.expect(t, received)
    content, is_content := message^.(core.View_Content_Ready)
    testing.expect(t, is_content)
    testing.expect_value(t, content.content.mime, core.Presentation_Mime.Text_Latex)
    testing.expect_value(t, len(content.content.bytes), len(source))
    testing.expect(t, content.content.bytes[1] == 0)
    testing.expect(t, communication_link_return(&service.event_link, message))
    testing.expect_value(t, drain_julia_egress_returns(service), 1)

    testing.expect_value(t, publish_presented_text(state, 9, nil, 0),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, publish_presented_text(
        state, 0, raw_data(source[:]), i32(core.PRESENTATION_MAX_SOURCE_BYTES + 1)),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
}

// Verify the egress pool covers sixteen maximum payloads plus one retained replacement.
@(test)
julia_event_link_covers_maximum_presentation_budget :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)
    interface: core.Euclid_Julia_Interface
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.julia_runtime_service = service
    state.julia_interface = &interface
    source: [core.PRESENTATION_MAX_SOURCE_BYTES]u8

    for _ in 0..<JULIA_EVENT_CAPACITY {
        testing.expect_value(t, send_presented_text(state, .Text_Latex, source[:]),
            core.Communication_Send_Outcome.Sent)
    }
    testing.expect_value(t, send_presented_text(state, .Text_Latex, source[:]),
        core.Communication_Send_Outcome.Queue_Full)
    testing.expect(t, service.pending_view_content != nil)

    first, received := communication_link_try_recv(&service.event_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.event_link, first))
    testing.expect_value(t, drain_julia_egress_returns(service), 1)
    testing.expect_value(t, flush_pending_view_content(service),
        core.Communication_Send_Outcome.Sent)

    for _ in 0..<JULIA_EVENT_CAPACITY {
        message, ok := communication_link_try_recv(&service.event_link)
        testing.expect(t, ok)
        testing.expect(t, communication_link_return(&service.event_link, message))
    }
    testing.expect_value(t, drain_julia_egress_returns(service), JULIA_EVENT_CAPACITY)
    testing.expect_value(t, send_presented_text(state, .Text_Latex, source[:]),
        core.Communication_Send_Outcome.Sent)
    final_message, final_received := communication_link_try_recv(&service.event_link)
    testing.expect(t, final_received)
    testing.expect(t, communication_link_return(&service.event_link, final_message))
    testing.expect_value(t, drain_julia_egress_returns(service), 1)
}