package terminalservice

import transport "../../../bridge/transport"

import core "../../../core"
import protocol "../../../core/protocol"
import bridge "../../../bridge/host"
import input "../../input"
import terminalview ".."
import testing "core:testing"

// Keys use the existing encoder and fixed ingress without touching the prompt editor.
@(test)
terminal_interactive_test_routes_and_releases_input :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    state.terminal.animation_generation = 7
    state.terminal.awaiting_eval = true
    state.terminal.interactive_input_request_id = 19
    runtime: input.Input_Runtime
    events: [2]input.Input_Event = {
        {
            kind = .Press,
            key = .Down,
        },
        {
            kind = .Press,
            key = .Enter,
        },
    }
    terminal_service_interactive_input(state, &runtime, {
        events = events[:],
    })
    message, available := transport.consumer_mailbox_try_recv(
        &state.julia_runtime_service.julia_inbox)
    testing.expect(t, available)
    request, typed := message^.(protocol.Terminal_Interactive_Input)
    testing.expect(t, typed)
    testing.expect_value(t, request.request_id, protocol.Request_Id(19))
    testing.expect_value(t, request.animation_generation, u64(7))
    testing.expect_value(t, string(request.bytes[:request.byte_count]), "\e[B\r")
    transport.consumer_mailbox_release(
        &state.julia_runtime_service.julia_inbox, message)
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.owner.kind, input.Input_Owner_Kind.Julia_Interactive)
    testing.expect(t, input.input_terminal_enqueue_string(&runtime, "stale"))
    state.terminal.interactive_input_request_id = 0
    terminal_service_interactive_input(state, &runtime, {})
    testing.expect_value(t, runtime.owner.kind, input.Input_Owner_Kind.None)
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.stale_byte_discard_count, u64(5))
}

// Backpressure never consumes bytes before the fixed ingress accepts the packet.
@(test)
terminal_interactive_test_retains_input_under_pressure :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    state.terminal.animation_generation = 7
    state.terminal.interactive_input_request_id = 19
    runtime: input.Input_Runtime
    testing.expect(t, input.input_terminal_enqueue_string(&runtime, "q"))
    for bridge.send_terminal_ingress(state.julia_runtime_service,
        protocol.Terminal_Session_Started{
            animation_generation = 7,
        }) == .Sent {
    }
    terminal_service_deliver_interactive_input(state, &runtime)
    testing.expect_value(t, runtime.byte_queue_count, 1)
    testing.expect_value(t, runtime.byte_delivery_rejection_count, u64(1))
    for {
        message, available := transport.consumer_mailbox_try_recv(
            &state.julia_runtime_service.julia_inbox)
        if !available {
            break
        }
        transport.consumer_mailbox_release(
            &state.julia_runtime_service.julia_inbox, message)
    }
    terminal_service_deliver_interactive_input(state, &runtime)
    testing.expect_value(t, runtime.byte_queue_count, 0)
    message, available := transport.consumer_mailbox_try_recv(
        &state.julia_runtime_service.julia_inbox)
    testing.expect(t, available)
    transport.consumer_mailbox_release(
        &state.julia_runtime_service.julia_inbox, message)
}

// Publish accepted geometry/capabilities until their exact observations return.
@(test)
terminal_interactive_test_publishes_environment :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    terminal_service_test_runtime_init(t, state)
    defer terminal_service_test_runtime_destroy(state)
    state.terminal.animation_generation = 7
    state.terminal.geometry = {
        dimensions = {
            columns = 90,
            rows = 12,
        },
        generation = 3,
    }
    terminal_service_publish_interactive_environment(state)
    for index in 0..<2 {
        message, available := transport.consumer_mailbox_try_recv(
            &state.julia_runtime_service.julia_inbox)
        testing.expect(t, available)
        if index == 0 {
            request, typed := message^.(protocol.Terminal_Geometry_Accepted)
            testing.expect(t, typed)
            testing.expect_value(t, request.geometry, state.terminal.geometry)
            testing.expect_value(t, request.animation_generation, u64(7))
        } else {
            request, typed := message^.(protocol.Terminal_Capabilities_Accepted)
            testing.expect(t, typed)
            testing.expect_value(t,
                request.capabilities, terminalview.TERMINAL_CAPABILITIES)
        }
        transport.consumer_mailbox_release(
            &state.julia_runtime_service.julia_inbox, message)
    }
    state.terminal.julia_geometry_generation = 3
    state.terminal.julia_capabilities_observed = true
    terminal_service_publish_interactive_environment(state)
    _, available := transport.consumer_mailbox_try_recv(
        &state.julia_runtime_service.julia_inbox)
    testing.expect(t, !available)
}
