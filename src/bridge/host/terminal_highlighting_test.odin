package julia_host

import transport "../transport"

import bridgemodel "../model"
import protocol "../../core/protocol"
import "core:testing"

// Construct a source/cache identity distinct from the host's current generation.
highlight_bridge_test_identity :: proc() -> protocol.Highlight_Identity {
    return {
        request_id = 71,
        animation_generation = 9,
        target_id = 12,
        source_revision = 4,
        face_generation = 2,
        target_kind = .History_Entry,
    }
}

// Verify source and typed runs are deep-copied and reclaimed by their receiving owners.
@(test)
highlight_transport_clones_and_returns_owned_storage :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    source: [3]u8 = {'a', 0, 'b'}
    request: protocol.Highlight_Requested = {
        identity = highlight_bridge_test_identity(),
        source = string(source[:]),
    }
    testing.expect_value(t, send_terminal_highlight_request(service, request),
        bridgemodel.Communication_Send_Outcome.Sent)
    ingress, received := transport.consumer_mailbox_try_recv(&service.julia_inbox)
    testing.expect(t, received)
    cloned := ingress^.(protocol.Highlight_Requested)
    source[0] = 'z'
    testing.expect_value(t, cloned.source, "a\x00b")
    runs: [1]protocol.Highlight_Run = {{
        end_byte = 3,
    }}
    result: protocol.Highlight_Result = {
        identity = cloned.identity,
        source = cloned.source,
        runs = runs[:],
    }
    testing.expect_value(t, send_terminal_highlight_result(service, result),
        bridgemodel.Communication_Send_Outcome.Sent)
    egress, ready := try_receive_julia_egress(service)
    testing.expect(t, ready)
    highlight := egress^.(protocol.Highlight_Result)
    testing.expect_value(t, highlight.identity, request.identity)
    testing.expect(t, raw_data(highlight.source) != raw_data(cloned.source))
    testing.expect(t, raw_data(highlight.runs) != raw_data(runs[:]))
    runs[0].end_byte = 1
    testing.expect_value(t, highlight.runs[0].end_byte, u32(3))
    transport.consumer_mailbox_release(&service.julia_inbox, ingress)
    testing.expect_value(t, highlight.source, "a\x00b")
    testing.expect(t, release_julia_egress(service, egress))
}

// Verify a maximum adapter source fits the bounded ingress pool including its envelope.
@(test)
highlight_transport_accepts_maximum_source :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    source := make([]u8, protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES, context.allocator)
    defer delete(source, context.allocator)
    for &byte in source {
        byte = 'x'
    }
    testing.expect_value(t, send_terminal_highlight_request(service, {
        identity = highlight_bridge_test_identity(),
        source = string(source),
    }), bridgemodel.Communication_Send_Outcome.Sent)
    message, received := transport.consumer_mailbox_try_recv(&service.julia_inbox)
    testing.expect(t, received)
    testing.expect_value(t,
        len(message^.(protocol.Highlight_Requested).source), len(source))
    transport.consumer_mailbox_release(&service.julia_inbox, message)
}

// Verify saturation returns explicit pressure and leaves no partially retained payload.
@(test)
highlight_transport_pressure_reclaims_failed_publications :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    for _ in 0..<DISPLAY_INBOX_MESSAGE_CAPACITY {
        testing.expect_value(t, send_terminal_egress(service, protocol.Highlight_Failed{
            identity = highlight_bridge_test_identity(),
            reason = .Mailbox_Full,
        }), bridgemodel.Communication_Send_Outcome.Sent)
    }

    runs: [1]protocol.Highlight_Run = {{
        end_byte = 1,
    }}
    result: protocol.Highlight_Result = {
        identity = highlight_bridge_test_identity(),
        source = "x",
        runs = runs[:],
    }
    testing.expect_value(t, send_terminal_highlight_result(service, result),
        bridgemodel.Communication_Send_Outcome.Queue_Full)
    for _ in 0..<DISPLAY_INBOX_MESSAGE_CAPACITY {
        message, received := try_receive_julia_egress(service)
        testing.expect(t, received)
        testing.expect(t, release_julia_egress(service, message))
    }
    testing.expect_value(t, service.display_inbox.outstanding, 0)
    testing.expect_value(t, send_terminal_highlight_result(service, result),
        bridgemodel.Communication_Send_Outcome.Sent)
    message, received := try_receive_julia_egress(service)
    testing.expect(t, received)
    testing.expect(t, release_julia_egress(service, message))
    service.lifecycle = .Stopped
    testing.expect_value(t, send_terminal_highlight_request(service, {
        identity = highlight_bridge_test_identity(),
        source = "x",
    }), bridgemodel.Communication_Send_Outcome.Runtime_Stopping)
}

// Build maximum-size caller-owned payload storage; the test frees both source and runs.
highlight_bridge_test_large_result :: proc() -> protocol.Highlight_Result {
    source := make([]u8, protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES, context.allocator)
    for &byte in source {
        byte = 'x'
    }
    runs := make([]protocol.Highlight_Run, protocol.TERMINAL_HIGHLIGHT_RUN_CAPACITY,
        context.allocator)
    for &run, index in runs {
        run.start_byte = u32(index)
        run.end_byte = u32(index + 1)
    }
    runs[len(runs) - 1].end_byte = u32(len(source))
    return {
        identity = highlight_bridge_test_identity(),
        source = string(source),
        runs = runs,
    }
}

// Verify large results grow within the configured hard ceiling and reuse receiver storage.
@(test)
highlight_transport_pool_exhaustion_is_transactional :: proc(t: ^testing.T) {
    service := julia_mailbox_test_service(t)
    defer julia_mailbox_test_service_destroy(service)
    result := highlight_bridge_test_large_result()
    defer delete(transmute([]u8)result.source, context.allocator)
    defer delete(result.runs, context.allocator)
    testing.expect_value(t, send_terminal_highlight_result(service, result),
        bridgemodel.Communication_Send_Outcome.Sent)
    message, received := try_receive_julia_egress(service)
    testing.expect(t, received)
    testing.expect(t,
        service.display_inbox.accepted_bytes <= bridgemodel.DISPLAY_INBOX_BYTE_LIMIT)
    testing.expect(t, release_julia_egress(service, message))
}
