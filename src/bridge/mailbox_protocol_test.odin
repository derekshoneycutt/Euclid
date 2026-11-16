package bridge

import bridgemodel "model"
import protocol "../core/protocol"
import presentation_model "presentation"
import "../core"
import "base:runtime"
import "core:testing"
import "core:thread"
import "core:time"
import "core:mem"

// Record dispatched values rather than retaining any mailbox envelope or nested pointers.
Mailbox_Test_Collector :: struct {
    requests: [64]protocol.Request_Id,
    count: int,
}

// Initialize an inbox-only service with real native storage and no embedded Julia runtime.
julia_mailbox_test_service :: proc(t: ^testing.T) -> ^Julia_Runtime_Service {
    service := new(Julia_Runtime_Service, context.allocator)
    testing.expect_value(t,
        init_julia_runtime_mailboxes(service), runtime.Allocator_Error.None)
    service.next_request_id = 1
    service.lifecycle = .Ready
    return service
}

// Destroy receiver-owned native storage after test borrows and producers have stopped.
julia_mailbox_test_service_destroy :: proc(service: ^Julia_Runtime_Service) {
    destroy_julia_runtime_mailboxes(service)
    free(service, context.allocator)
}

// Every typed ingress variant preserves its scalars and copies nested text.
@(test)
mailbox_protocol_round_trips_ingress :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    values: []bridgemodel.Julia_Host_Ingress = {
        bridgemodel.Runtime_Initialize_Requested{
            request_id = 1,
        },
        bridgemodel.Runtime_Content_Initialize_Requested{
            request_id = 2,
        },
        bridgemodel.Animation_Tick_Requested{
            request_id = 3,
        },
        bridgemodel.Animation_Lifecycle_Requested{
            request_id = 4,
        },
        bridgemodel.Harness_Scenario_Requested{
            scenario_name = "case",
        },
        bridgemodel.Scenario_View_Content_Requested{
            source = []u8{'x', 0},
        },
        bridgemodel.Runtime_Shutdown_Requested{
            request_id = 7,
        },
        protocol.Terminal_Session_Started{},
        protocol.Terminal_Session_Closed{},
        protocol.Evaluation_Requested{
            code = "a\x00b",
        },
        protocol.Completion_Requested{
            code = "complete",
        },
        protocol.Highlight_Requested{
            source = "highlight",
        },
        protocol.Terminal_Interactive_Input{},
        protocol.Terminal_Geometry_Accepted{},
        protocol.Terminal_Capabilities_Accepted{},
        protocol.Tick_Stream_Configuration_Acknowledged{},
        protocol.Tick_Pulse{},
    }
    for value in values {
        testing.expect_value(t, consumer_mailbox_publish(&service.julia_inbox, value),
            bridgemodel.Communication_Send_Outcome.Sent)
        copied, _ := consumer_mailbox_try_recv(&service.julia_inbox)
        _, bytes := mailbox_copy_value(value, nil)
        _, copied_bytes := mailbox_copy_value(copied^, nil)
        testing.expect_value(t, copied_bytes, bytes)
        mailbox_test_expect_copy(t, value, copied^)
        consumer_mailbox_release(&service.julia_inbox, copied)
    }
}

// Every typed egress variant preserves ordering; dynamic payloads have independent storage.
@(test)
mailbox_protocol_round_trips_egress :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    values: []bridgemodel.Julia_Host_Egress = {
        bridgemodel.Runtime_Initialized{},
        bridgemodel.Runtime_Content_Initialized{},
        bridgemodel.Animation_Tick_Completed{},
        bridgemodel.Animation_Lifecycle_Completed{},
        bridgemodel.Harness_Scenario_Completed{},
        bridgemodel.Runtime_Shutdown_Completed{},
        bridgemodel.View_Content_Ready{
            content = {
                bytes = []u8{'x'},
            },
        },
        bridgemodel.Exercise_Header_Update{
            text = []u8{'h'},
        },
        bridgemodel.Exercise_Query_Intent{},
        bridgemodel.User_Exercise_Intent{},
        protocol.Terminal_Output_Batch{
            bytes = "a\x00b",
        },
        protocol.Evaluation_Incomplete{},
        protocol.Evaluation_Completed{},
        protocol.Completion_Result{
            insertion = "insert",
        },
        protocol.Completion_Failed{},
        protocol.Highlight_Result{
            source = "h",
            runs = []protocol.Highlight_Run{{
                end_byte = 1,
            }},
        },
        protocol.Highlight_Failed{},
        protocol.Terminal_Input_Acquired{},
        protocol.Terminal_Input_Released{},
        protocol.Terminal_Geometry_Observed{},
        protocol.Terminal_Capabilities_Observed{},
        protocol.Terminal_Session_Ready{
            banner = "banner",
        },
        protocol.Terminal_Session_Stopped{},
        protocol.Tick_Stream_Configure_Requested{},
        protocol.Tick_Stream_Stop_Requested{},
    }
    for value in values {
        testing.expect_value(t, consumer_mailbox_publish(&service.display_inbox, value),
            bridgemodel.Communication_Send_Outcome.Sent)
        copied, _ := consumer_mailbox_try_recv(&service.display_inbox)
        _, expected_bytes := mailbox_copy_value(value, nil)
        _, actual_bytes := mailbox_copy_value(copied^, nil)
        testing.expect_value(t, expected_bytes, actual_bytes)
        mailbox_test_expect_copy(t, value, copied^)
        consumer_mailbox_release(&service.display_inbox, copied)
    }

}

// Canonicalize pointer fields to the same aligned scratch while comparing exact payload bytes.
mailbox_test_expect_copy :: proc(t: ^testing.T, source, actual: $T) {
    scratch: [512]u64
    saved: [4096]u8
    bytes := mem.byte_slice(&scratch, size_of(scratch))
    expected, count := mailbox_copy_value(source, bytes)
    copy(saved[:count], bytes[:count])
    normalized, actual_count := mailbox_copy_value(actual, bytes)
    testing.expect_value(t, actual_count, count)
    testing.expect_value(t, mem.compare(saved[:count], bytes[:count]), 0)
    testing.expect_value(t, mem.compare(mem.byte_slice(&expected, size_of(T)),
        mem.byte_slice(&normalized, size_of(T))), 0)
}

// Initialize an exact completed tick slot, retaining the independent world-update protocol.
julia_mailbox_test_prepare_tick_completion :: proc(
    service: ^Julia_Runtime_Service) -> bridgemodel.Animation_Tick_Completed {
    service.active_request_id = 41
    service.active_request_kind = .Animation_Tick
    service.animation_tick_pending = true
    service.animation_generation = 7
    service.animation_tick_slots[1].state = .Complete
    service.animation_tick_slots[1].request_id = 41
    service.animation_tick_slots[1].reservation_generation = 9
    service.animation_tick_slots[1].generation = 7
    service.animation_tick_slots[1].sequence = 12
    return {
        completion = {
            request_id = 41,
            succeeded = true,
        },
        handle = {
            index = 1,
            reservation_generation = 9,
        },
        animation_generation = 7,
        sequence = 12,
    }
}

// Accepted completion still resolves the exact tick slot and rejects duplicate delivery.
@(test)
animation_tick_completion_accepts_once :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    completed := julia_mailbox_test_prepare_tick_completion(service)
    _ = consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(completed))
    event, accepted := try_route_julia_egress(service)
    testing.expect(t, accepted && event.slot_index == 1)
    testing.expect(t, !service.animation_tick_pending && service.active_request_id == 0)
    _, duplicate := accept_animation_tick_completion(service, completed)
    testing.expect(t, !duplicate)
}

// Stale slot handles cannot accept or recycle a newer incarnation.
@(test)
animation_tick_completion_rejects_stale_handles :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    completed := julia_mailbox_test_prepare_tick_completion(service)
    stale := completed
    stale.handle.index = i32(ANIMATION_TICK_SLOT_COUNT)
    _, accepted := accept_animation_tick_completion(service, stale)
    testing.expect(t, !accepted)
    stale = completed
    stale.handle.reservation_generation -= 1
    _, accepted = accept_animation_tick_completion(service, stale)
    testing.expect(t, !accepted)
    testing.expect_value(t, service.animation_tick_slots[1].state,
        bridgemodel.Animation_Tick_Slot_State.Complete)
    completed.animation_generation -= 1
    service.animation_tick_slots[1].generation -= 1
    _, accepted = accept_animation_tick_completion(service, completed)
    testing.expect(t, !accepted)
    testing.expect_value(t, service.animation_tick_slots[1].state,
        bridgemodel.Animation_Tick_Slot_State.Free)
    testing.expect(t, service.active_request_id == 0 && !service.animation_tick_pending)
}

// Reusing a world-update slot advances its checked reservation incarnation.
@(test)
animation_tick_slot_reuse_advances_reservation_generation :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    first := reserve_animation_tick_slot(service)
    generation := service.animation_tick_slots[first].reservation_generation
    service.animation_tick_slots[first].state = .Accepted
    release_completed_animation_ticks(service)
    second := reserve_animation_tick_slot(service)
    testing.expect_value(t, first, second)
    testing.expect_value(t,
        service.animation_tick_slots[second].reservation_generation, generation + 1)
}

// Establish a committed or rolled-back lifecycle transaction independent of mailbox storage.
julia_mailbox_test_prepare_lifecycle_completion :: proc(
    service: ^Julia_Runtime_Service,
    succeeded: bool) -> bridgemodel.Animation_Lifecycle_Completed {
    service.active_request_id = 51
    service.active_request_kind = .Invoke
    service.animation_lifecycle_slot.state = .Complete
    service.animation_lifecycle_slot.outcome = .Committed if succeeded else .Rolled_Back
    service.animation_lifecycle_slot.request_id = 51
    service.animation_lifecycle_slot.reservation_generation = 4
    service.animation_lifecycle_slot.runtime_generation = 3
    service.animation_lifecycle_slot.animation_generation = 8
    return {
        completion = {
            request_id = 51,
            succeeded = succeeded,
        },
        handle = {
            index = 0,
            reservation_generation = 4,
        },
        runtime_generation = 3,
        animation_generation = 8,
    }
}

// Both commit and rollback close the exact lifecycle transaction exactly once.
@(test)
animation_lifecycle_completion_accepts_terminal_outcomes :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    for succeeded in ([]bool{true, false}) {
        completed := julia_mailbox_test_prepare_lifecycle_completion(service, succeeded)
        event, accepted := accept_animation_lifecycle_completion(service, completed)
        testing.expect(t, accepted && event.succeeded == succeeded)
        testing.expect_value(t, service.active_request_id, u64(0))
        testing.expect_value(t, service.animation_lifecycle_slot.state,
            bridgemodel.Animation_Lifecycle_Slot_State.Free)
        _, duplicate := accept_animation_lifecycle_completion(service, completed)
        testing.expect(t, !duplicate)
    }
}

// Stale lifecycle identity cannot release the transaction; reservations remain bounded at one.
@(test)
animation_lifecycle_completion_rejects_stale_identity :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    first, reserved := reserve_animation_lifecycle_slot(service)
    _, second_reserved := reserve_animation_lifecycle_slot(service)
    testing.expect(t, reserved && !second_reserved)
    service.animation_lifecycle_slot.state = .Free
    second, _ := reserve_animation_lifecycle_slot(service)
    testing.expect_value(t,
        second.reservation_generation, first.reservation_generation + 1)
    completed := julia_mailbox_test_prepare_lifecycle_completion(service, true)
    completed.handle.reservation_generation -= 1
    _, accepted := accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, !accepted)
    completed = julia_mailbox_test_prepare_lifecycle_completion(service, true)
    completed.runtime_generation -= 1
    _, accepted = accept_animation_lifecycle_completion(service, completed)
    testing.expect(t, !accepted)
    testing.expect_value(t, service.animation_lifecycle_slot.state,
        bridgemodel.Animation_Lifecycle_Slot_State.Complete)
}

// Observe ordered evaluation events inside the transient dispatch borrow.
mailbox_test_collect :: proc(
    user_data: rawptr, message: ^bridgemodel.Julia_Host_Egress) {
    collector := cast(^Mailbox_Test_Collector)user_data
    value := message^.(protocol.Evaluation_Completed)
    collector.requests[collector.count] = value.request_id
    collector.count += 1
}

// Normal display service exhausts the full accepted FIFO and reopens admission.
@(test)
mailbox_display_drain_preserves_budget_and_order :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    collector: Mailbox_Test_Collector
    configure_julia_egress_dispatch(service, mailbox_test_collect, &collector)
    for index in 0..<33 {
        _ = send_terminal_egress(service, protocol.Evaluation_Completed{
            request_id = protocol.Request_Id(index + 1),
        })
    }
    testing.expect_value(t, drain_julia_egress(service), 33)
    testing.expect_value(t, collector.count, 33)
    testing.expect_value(t, drain_julia_egress(service), 0)
    testing.expect(t, !service.display_inbox.draining)
    for request, index in collector.requests[:collector.count] {
        testing.expect_value(t, request, protocol.Request_Id(index + 1))
    }
}

// Accepted shutdown closes ordinary ingress admission while its correlated control survives.
@(test)
mailbox_shutdown_admission_preserves_control :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    request_id, accepted := try_submit_runtime_shutdown(service)
    testing.expect(t, accepted)
    testing.expect_value(t, send_terminal_evaluation(service, {
        code = "x",
    }),
        bridgemodel.Communication_Send_Outcome.Runtime_Stopping)
    message, _ := consumer_mailbox_try_recv(&service.julia_inbox)
    request := message^.(bridgemodel.Runtime_Shutdown_Requested)
    testing.expect_value(t, request.request_id, request_id)
    consumer_mailbox_release(&service.julia_inbox, message)
}

// Deep-copy latest-value retries without retaining sender data or delaying receiver recycling.
@(test)
mailbox_view_content_retry_preserves_latest_bytes :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    for _ in 0..<64 {
        _ = send_terminal_egress(service, protocol.Evaluation_Completed{})
    }
    bytes: [3]u8 = {'a', 0, 'b'}
    content: bridgemodel.View_Content_Ready = {
        presentation_generation = 1,
        content = {
            bytes = bytes[:],
        },
    }
    testing.expect_value(t, publish_or_retain_view_content(service, content),
        bridgemodel.Communication_Send_Outcome.Queue_Full)
    bytes[0] = 'z'
    retained := service.pending_view_content^.(bridgemodel.View_Content_Ready)
    testing.expect_value(t, string(retained.content.bytes), "a\x00b")
    content.presentation_generation = 2
    _ = publish_or_retain_view_content(service, content)
    for _ in 0..<64 {
        message, _ := try_receive_julia_egress(service)
        _ = release_julia_egress(service, message)
    }
    testing.expect_value(t, flush_pending_view_content(service),
        bridgemodel.Communication_Send_Outcome.Sent)
    message, _ := try_receive_julia_egress(service)
    copied := message^.(bridgemodel.View_Content_Ready)
    testing.expect_value(t, copied.presentation_generation, u64(2))
    testing.expect_value(t, string(copied.content.bytes), "z\x00b")
    _ = release_julia_egress(service, message)
    testing.expect(t, service.pending_view_content == nil)
}

// Startup content remains valid after its transport batch has been recycled.
@(test)
mailbox_startup_content_is_display_owned :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    bytes: [3]u8 = {'$', 'x', '$'}
    _ = consumer_mailbox_publish(&service.display_inbox, bridgemodel.Julia_Host_Egress(
        bridgemodel.View_Content_Ready{
            content = {
                bytes = bytes[:],
            },
        }))
    _ = drain_julia_egress(service)
    testing.expect_value(t, service.display_inbox.outstanding, 0)
    testing.expect(t, service.display_pending_view_content != nil)
    bytes[1] = 'z'
    content := service.display_pending_view_content^.(bridgemodel.View_Content_Ready)
    testing.expect_value(t, string(content.content.bytes), "$x$")
}

// Lifecycle barriers must release a deferred presentation borrow before receiving completion.
@(test)
mailbox_lifecycle_wait_releases_deferred_content :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    completed := julia_mailbox_test_prepare_lifecycle_completion(service, true)
    bytes: [3]u8 = {'$', 'x', '$'}
    _ = consumer_mailbox_publish(&service.display_inbox, bridgemodel.Julia_Host_Egress(
        bridgemodel.View_Content_Ready{
            content = {
                bytes = bytes[:],
            },
        }))
    _ = consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(completed))
    _ = consumer_mailbox_publish(&service.display_inbox, bridgemodel.Julia_Host_Egress(
        bridgemodel.View_Content_Ready{
            content = {
                bytes = bytes[:],
            },
        }))
    testing.expect(t, wait_animation_lifecycle_completion(service, 51))
    testing.expect_value(t, service.display_inbox.outstanding, 0)
    testing.expect(t, !service.display_inbox.draining)
    testing.expect_value(t, service.display_inbox.arena.total_used, uint(0))
    testing.expect(t, service.display_pending_view_content != nil)
    retained := service.display_pending_view_content^.(bridgemodel.View_Content_Ready)
    testing.expect_value(t, string(retained.content.bytes), "$x$")
}

// Fail the second inbox initialization after the first acquired native storage.
mailbox_test_fail_event_init :: proc(
    service: ^Julia_Runtime_Service) -> runtime.Allocator_Error {
    err := consumer_mailbox_init(&service.julia_inbox, 256*1024, 1024*1024, 64)
    assert(err == .None)
    return .Out_Of_Memory
}

// Partial and repeated startup release both inboxes without changing thread purpose.
@(test)
mailbox_service_initialization_unwinds_and_repeats :: proc(t: ^testing.T) {
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    testing.expect_value(t,
        init_julia_runtime_mailboxes_with(service, mailbox_test_fail_event_init),
        runtime.Allocator_Error.Out_Of_Memory)
    testing.expect(t,
        !service.julia_inbox.initialized && !service.display_inbox.initialized)
    for _ in 0..<2 {
        testing.expect_value(t,
            init_julia_runtime_mailboxes(service), runtime.Allocator_Error.None)
        testing.expect(t, service.julia_inbox.arena.curr_block != nil)
        testing.expect(t, service.display_inbox.arena.curr_block != nil)
        destroy_julia_runtime_mailboxes(service)
    }
}

// Reject native worker creation after inbox and snapshot initialization has succeeded.
mailbox_test_fail_worker_start :: proc(data: rawptr) -> ^thread.Thread {
    return nil
}

// Worker-start failure unwinds initialized native inboxes and reports construction failure.
@(test)
julia_worker_start_failure_releases_service :: proc(t: ^testing.T) {
    service, err := create_julia_runtime_service_with_worker(
        context.allocator, "", nil, mailbox_test_fail_worker_start)
    testing.expect(t, service == nil)
    testing.expect_value(t, err, runtime.Allocator_Error.Out_Of_Memory)
}

// Foreign completion identities cannot clear or recycle the active tick transaction.
@(test)
julia_control_completion_rejects_mismatched_request_identity :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    completed := julia_mailbox_test_prepare_tick_completion(service)
    completed.completion.request_id += 1
    _ = consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(completed))
    _, accepted := try_route_julia_egress(service)
    testing.expect(t, !accepted)
    testing.expect_value(t, service.active_request_id, u64(41))
    testing.expect(t, service.animation_tick_pending)
    testing.expect_value(t, service.display_inbox.outstanding, 0)
    testing.expect_value(t, service.animation_tick_slots[1].state,
        bridgemodel.Animation_Tick_Slot_State.Complete)
}

// Presentation publication copies exact counted bytes, including embedded NUL, before return.
@(test)
publish_presented_text_clones_exact_counted_bytes :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    interface: bridgemodel.Euclid_Julia_Interface
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.saved_context = context
    state.julia_runtime_service = service
    state.julia_interface = &interface
    source: [3]u8 = {'A', 0, 'B'}
    testing.expect_value(t, publish_presented_text(
        state, 1, raw_data(source[:]), i32(len(source))), i32(BRIDGE_STATUS_OK))
    source[0] = 'Z'
    message, received := try_receive_julia_egress(service)
    testing.expect(t, received)
    content := message^.(bridgemodel.View_Content_Ready)
    testing.expect_value(t,
        content.content.mime, presentation_model.Presentation_Mime.Text_Latex)
    testing.expect_value(t, string(content.content.bytes), "A\x00B")
    _ = release_julia_egress(service, message)
    testing.expect_value(t, publish_presented_text(state, 9, nil, 0),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, publish_presented_text(
        state, 0, raw_data(source[:]),
        i32(presentation_model.PRESENTATION_MAX_SOURCE_BYTES + 1)),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
}

// Malformed, blank, and oversized instructions fail before mailbox publication.
mailbox_test_rejects_invalid_exercise_header :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    blank: [3]u8 = {' ', '\t', '\n'}
    invalid_utf8: [2]u8 = {0xc3, 0x28}
    oversized: [32 * 1024 + 1]u8
    for source in ([][]u8{blank[:], invalid_utf8[:], oversized[:]}) {
        testing.expect_value(t,
            publish_exercise_header(state, raw_data(source), i32(len(source))),
            i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    }
}

// Exercise-header updates own accepted bytes; hides carry a fresh identity and no text.
@(test)
publish_exercise_header_clones_validated_bytes :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.saved_context = context
    state.julia_runtime_service = service
    state.terminal.initialized = true
    state.terminal.animation_generation = 9
    service.host_exercise_header_animation_generation = 9
    mailbox_test_rejects_invalid_exercise_header(t, state)
    exact: [32 * 1024]u8
    for &byte in exact[:] {
        byte = 'x'
    }
    testing.expect_value(t, publish_exercise_header(
        state, raw_data(exact[:]), i32(len(exact))), i32(BRIDGE_STATUS_OK))
    exact[0] = 'z'
    message, _ := try_receive_julia_egress(service)
    update := message^.(bridgemodel.Exercise_Header_Update)
    testing.expect(t,
        update.visible && update.animation_generation == 9 && update.request_id == 1)
    testing.expect_value(t, len(update.text), len(exact))
    testing.expect_value(t, update.text[0], u8('x'))
    _ = release_julia_egress(service, message)
    testing.expect_value(t, hide_exercise_header(state), i32(BRIDGE_STATUS_OK))
    message, _ = try_receive_julia_egress(service)
    update = message^.(bridgemodel.Exercise_Header_Update)
    testing.expect(t, !update.visible && update.request_id == 2 && len(update.text) == 0)
    _ = release_julia_egress(service, message)
}

// A closed inbox drains accepted work before stopping the uninitialized host without spinning.
@(test)
mailbox_closed_ingress_stops_uninitialized_host :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    _ = consumer_mailbox_publish(&service.julia_inbox, bridgemodel.Julia_Host_Ingress(
        protocol.Tick_Pulse{}))
    consumer_mailbox_close(&service.julia_inbox)
    testing.expect(t, !consumer_mailbox_finished(&service.julia_inbox))
    message, _ := consumer_mailbox_try_recv(&service.julia_inbox)
    testing.expect(t, !consumer_mailbox_finished(&service.julia_inbox))
    consumer_mailbox_release(&service.julia_inbox, message)
    testing.expect(t, consumer_mailbox_finished(&service.julia_inbox))
    result := julia_runtime_worker_run_host(service)
    testing.expect(t, !result.shutting_down)
}

// Shutdown admission recovers after ingress saturation without consuming a rejected ID.
@(test)
julia_shutdown_recovers_from_ingress_saturation :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    for _ in 0..<JULIA_INBOX_MESSAGE_CAPACITY {
        _, sent := try_submit_runtime_initialize(service)
        testing.expect(t, sent)
    }
    lifecycle_before_shutdown := service.lifecycle
    shutdown_id, sent := try_submit_runtime_shutdown(service)
    testing.expect(t, !sent && shutdown_id == 0 &&
        service.lifecycle == lifecycle_before_shutdown)
    for _ in 0..<JULIA_INBOX_MESSAGE_CAPACITY {
        message, _ := consumer_mailbox_try_recv(&service.julia_inbox)
        consumer_mailbox_release(&service.julia_inbox, message)
    }
    shutdown_id, sent = try_submit_runtime_shutdown(service)
    testing.expect(t, sent)
    testing.expect_value(t, shutdown_id, u64(JULIA_INBOX_MESSAGE_CAPACITY + 1))
    testing.expect_value(t, service.lifecycle, Julia_Lifecycle_State.Shutdown_Requested)
    testing.expect_value(t, send_typed_julia_completion(service, {
        protocol = .Runtime_Shutdown,
        request_kind = .Shutdown,
        request_id = shutdown_id,
    }, {
        kind = .Shutdown_Complete,
        request_kind = .Shutdown,
        request_id = shutdown_id,
        succeeded = true,
    }), bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect(t, wait_runtime_shutdown_completion(
        service, shutdown_id, time.tick_now(), 1.0))
    testing.expect_value(t, service.lifecycle, Julia_Lifecycle_State.Stopped)
}
