package bridge

import "../core"

import "base:runtime"
import "core:testing"

Communication_Link_Test_Message :: struct {
    sequence: u64,
}

Communication_Link_Oversized_Message :: struct {
    bytes: [8 * 1024]u8,
}

COMMUNICATION_LINK_MAX_ENVELOPE_COEXISTENCE :: 33

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
    _ = communication_link_drain_returns(&service.request_link)
    _ = drain_julia_egress_returns(service)
    if service.display_deferred_view_content != nil {
        destroy_julia_egress_message(
            service, service.display_deferred_view_content)
    }
    if service.pending_view_content != nil {
        destroy_julia_egress_message(service, service.pending_view_content)
    }
    communication_link_destroy(&service.event_link)
    communication_link_destroy(&service.request_link)
    free(service)
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

    request_id, sent := try_submit_julia_request(service, .Invoke)
    testing.expect(t, sent)
    request_message, request_ok := communication_link_try_recv(&service.request_link)
    testing.expect(t, request_ok)
    request, is_request := request_message^.(Julia_Request)
    testing.expect(t, is_request)
    testing.expect_value(t, request.request_id, request_id)
    testing.expect(t, communication_link_return(&service.request_link, request_message))

    testing.expect_value(t, send_julia_event(service, {
        kind = .Invoke_Complete,
        request_kind = .Invoke,
        request_id = request_id,
        succeeded = true,
    }), core.Communication_Send_Outcome.Sent)
    event, event_ok := try_receive_julia_event(service)
    testing.expect(t, event_ok)
    testing.expect_value(t, event.request_id, request_id)
    testing.expect_value(t, service.active_request_id, u64(0))
}

// Verify event-only consumers retain presentation envelopes for the display owner.
@(test)
julia_event_receive_defers_view_content :: proc(t: ^testing.T) {
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
    testing.expect_value(t, send_julia_event(service, {
        kind = .Invoke_Complete,
        request_kind = .Invoke,
        request_id = 9,
        succeeded = true,
    }), core.Communication_Send_Outcome.Sent)

    event, ok := try_receive_julia_event(service)
    testing.expect(t, ok)
    testing.expect_value(t, event.request_id, u64(9))
    deferred := take_deferred_view_content(service)
    testing.expect(t, deferred == content_message)
    content, is_content := deferred^.(core.View_Content_Ready)
    testing.expect(t, is_content)
    testing.expect_value(t, string(content.content.bytes), "tex")
    testing.expect(t, return_julia_egress(service, deferred))
}

// Verify full request queues preserve IDs and recover after producer reclamation.
@(test)
julia_request_link_saturation_is_nonblocking :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)

    for expected_id in 1..=JULIA_REQUEST_CAPACITY {
        request_id, sent := try_submit_julia_request(service, .Invoke)
        testing.expect(t, sent)
        testing.expect_value(t, request_id, u64(expected_id))
    }
    rejected_id, rejected := try_submit_julia_request(service, .Invoke)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
    testing.expect_value(t, service.next_request_id, u64(JULIA_REQUEST_CAPACITY + 1))

    message, received := communication_link_try_recv(&service.request_link)
    testing.expect(t, received)
    testing.expect(t, communication_link_return(&service.request_link, message))
    recovered_id, recovered := try_submit_julia_request(service, .Invoke)
    testing.expect(t, recovered)
    testing.expect_value(t, recovered_id, u64(JULIA_REQUEST_CAPACITY + 1))
}

// Verify shutdown admission closes request transport without consuming another ID.
@(test)
julia_request_link_rejects_work_after_shutdown_begins :: proc(t: ^testing.T) {
    service := communication_link_test_service(t)
    defer communication_link_test_service_destroy(service)

    shutdown_id, shutdown_sent := try_submit_julia_request(service, .Shutdown)
    testing.expect(t, shutdown_sent)
    testing.expect_value(t, shutdown_id, u64(1))
    testing.expect_value(t, service.lifecycle, Julia_Lifecycle_State.Shutdown_Requested)

    rejected_id, rejected := try_submit_julia_request(service, .Invoke)
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_id, u64(0))
    testing.expect_value(t, service.next_request_id, u64(2))
    testing.expect_value(t, send_julia_request(service, {
        kind = .Invoke,
        request_id = 2,
    }), core.Communication_Send_Outcome.Runtime_Stopping)
}

// Fill the worker-owned outbound lane with fixed completion events.
communication_link_fill_event_queue :: proc(
    t: ^testing.T, service: ^Julia_Runtime_Service) {
    for request_id in 1..=JULIA_EVENT_CAPACITY {
        testing.expect_value(t, send_julia_event(service, {
            kind = .Invoke_Complete,
            request_kind = .Invoke,
            request_id = u64(request_id),
            succeeded = true,
        }), core.Communication_Send_Outcome.Sent)
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