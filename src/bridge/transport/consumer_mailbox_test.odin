package transport

import bridgemodel "../model"
import protocol "../../core/protocol"
import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
import "core:testing"
import "core:thread"
import "core:sync"

// Mailbox_Test_Sender records a reliable publisher's terminal outcome.
Mailbox_Test_Sender :: struct {
    inbox: ^bridgemodel.Consumer_Mailbox(u64),
    count: int,
    outcome: bridgemodel.Communication_Send_Outcome,
}

// Mailbox_Test_Exchange observes ingress pressure before reliably sending a completion.
Mailbox_Test_Exchange :: struct {
    ingress: ^bridgemodel.Consumer_Mailbox(u64),
    egress: ^bridgemodel.Consumer_Mailbox(u64),
    entered: bool,
    ingress_outcome: bridgemodel.Communication_Send_Outcome,
    egress_outcome: bridgemodel.Communication_Send_Outcome,
}

// Publication owns all copied bytes and rejects the 65th message without mutation.
@(test)
consumer_mailbox_copies_and_bounds_messages :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(bridgemodel.Julia_Host_Ingress)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 256*1024, 1024*1024, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    source: [4]u8 = {'a', 0, 'b', 'c'}
    for index in 0..<64 {
        value := bridgemodel.Julia_Host_Ingress(protocol.Evaluation_Requested{
            request_id = protocol.Request_Id(index + 1),
            code = string(source[:]),
        })
        testing.expect_value(t, consumer_mailbox_publish(&inbox, value),
            bridgemodel.Communication_Send_Outcome.Sent)
    }
    source[0] = 'z'
    testing.expect_value(t,
        consumer_mailbox_publish(&inbox, bridgemodel.Julia_Host_Ingress{}),
        bridgemodel.Communication_Send_Outcome.Queue_Full)
    for index in 0..<64 {
        value, ok := consumer_mailbox_try_recv(&inbox)
        testing.expect(t, ok)
        request := value^.(protocol.Evaluation_Requested)
        testing.expect_value(t, request.request_id, protocol.Request_Id(index + 1))
        testing.expect_value(t, request.code, "a\x00bc")
        consumer_mailbox_release(&inbox, value)
    }
    testing.expect_value(t, inbox.outstanding, 0)
    testing.expect_value(t, inbox.accepted_bytes, 0)
}

// Partial consumption keeps admission paused and the full epoch alive until final release.
@(test)
consumer_mailbox_snapshot_and_reuse :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 8192, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    for _ in 0..<3 {
        _ = consumer_mailbox_publish(&inbox, u64(1))
        _ = consumer_mailbox_publish(&inbox, u64(2))
        used, charged := inbox.arena.total_used, inbox.accepted_bytes
        testing.expect_value(t, consumer_mailbox_batch_count(&inbox), 2)
        first, _ := consumer_mailbox_try_recv(&inbox)
        testing.expect_value(t, consumer_mailbox_publish(&inbox, u64(3)),
            bridgemodel.Communication_Send_Outcome.Queue_Full)
        testing.expect_value(t, first^, u64(1))
        consumer_mailbox_release(&inbox, first)
        testing.expect_value(t, inbox.arena.total_used, used)
        testing.expect_value(t, inbox.accepted_bytes, charged)
        testing.expect_value(t, consumer_mailbox_publish(&inbox, u64(3)),
            bridgemodel.Communication_Send_Outcome.Queue_Full)
        second, _ := consumer_mailbox_try_recv(&inbox)
        testing.expect_value(t, second^, u64(2))
        consumer_mailbox_release(&inbox, second)
        testing.expect_value(t, inbox.arena.total_used, uint(0))
        testing.expect_value(t, inbox.accepted_bytes, 0)
        testing.expect(t, !inbox.draining)
    }
    testing.expect_value(t, consumer_mailbox_batch_count(&inbox), 0)
    testing.expect(t, !inbox.draining)
}

// Recycled envelope allocation is aligned and clears all prior envelope bytes.
@(test)
consumer_mailbox_arena_batch_reset_and_zeroing :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 4096, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    _ = consumer_mailbox_publish(&inbox, max(u64))
    first, _ := consumer_mailbox_try_recv(&inbox)
    testing.expect_value(t, uintptr(first) % 16, uintptr(0))
    consumer_mailbox_release(&inbox, first)
    _ = consumer_mailbox_publish(&inbox, u64(0))
    second, _ := consumer_mailbox_try_recv(&inbox)
    testing.expect_value(t, second^, u64(0))
    testing.expect(t, inbox.borrowed.next == nil)
    consumer_mailbox_release(&inbox, second)
}

// Fail arena initialization without publishing an endpoint.
mailbox_test_init_failure :: proc(
    arena: ^vmem.Arena, reservation: uint) -> runtime.Allocator_Error {
    return .Out_Of_Memory
}

// Initial and message allocation failures preserve FIFO and logical admission accounting.
@(test)
consumer_mailbox_allocation_failure_is_transactional :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 8192, 64,
        mailbox_test_init_failure), runtime.Allocator_Error.Out_Of_Memory)
    testing.expect(t, !inbox.initialized && inbox.arena.curr_block == nil)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 8192, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    _ = consumer_mailbox_publish(&inbox, u64(1))
    before := consumer_mailbox_diagnostics(&inbox)
    storage: [1]byte
    exhausted: mem.Arena = {
        data = storage[:],
    }
    failing := mem.arena_allocator(&exhausted)
    testing.expect_value(t, consumer_mailbox_publish(&inbox, u64(2), failing),
        bridgemodel.Communication_Send_Outcome.Allocation_Failed)
    after := consumer_mailbox_diagnostics(&inbox)
    testing.expect_value(t, after.accepted_bytes, before.accepted_bytes)
    testing.expect_value(t, after.outstanding, before.outstanding)
    testing.expect_value(t, after.publication_count, before.publication_count)
    first, _ := consumer_mailbox_try_recv(&inbox)
    testing.expect_value(t, first^, u64(1))
    consumer_mailbox_release(&inbox, first)
}

// Saturate a logical epoch, then drain and repeat without assuming allocator backing policy.
mailbox_test_burst_reuse :: proc(
    t: ^testing.T, inbox: ^bridgemodel.Consumer_Mailbox($T), value: T) {
    for _ in 0..<2 {
        count := 0
        for consumer_mailbox_publish(inbox, value) == .Sent {
            count += 1
        }
        before := consumer_mailbox_diagnostics(inbox)
        testing.expect(t, count > 0 && count < inbox.count_limit)
        testing.expect(t, before.accepted_bytes <= before.byte_limit)
        testing.expect_value(t, consumer_mailbox_publish(inbox, value),
            bridgemodel.Communication_Send_Outcome.Storage_Full)
        testing.expect_value(t, consumer_mailbox_batch_count(inbox), count)
        testing.expect_value(t, consumer_mailbox_publish(inbox, value),
            bridgemodel.Communication_Send_Outcome.Queue_Full)
        for _ in 0..<count {
            message, _ := consumer_mailbox_try_recv(inbox)
            consumer_mailbox_release(inbox, message)
        }
        testing.expect_value(t, inbox.accepted_bytes, 0)
    }
}

// Both directional budgets bound accepted message bytes rather than arena reservations.
@(test)
consumer_mailbox_bursts_obey_byte_limits :: proc(t: ^testing.T) {
    ingress: bridgemodel.Consumer_Mailbox(bridgemodel.Julia_Host_Ingress)
    egress: bridgemodel.Consumer_Mailbox(bridgemodel.Julia_Host_Egress)
    testing.expect_value(t, consumer_mailbox_init(&ingress,
        bridgemodel.JULIA_INBOX_INITIAL_BYTES, bridgemodel.JULIA_INBOX_BYTE_LIMIT,
        bridgemodel.JULIA_INBOX_MESSAGE_CAPACITY), runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&ingress)
    testing.expect_value(t, consumer_mailbox_init(&egress,
        bridgemodel.DISPLAY_INBOX_INITIAL_BYTES, bridgemodel.DISPLAY_INBOX_BYTE_LIMIT,
        bridgemodel.DISPLAY_INBOX_MESSAGE_CAPACITY), runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&egress)
    ingress_bytes: [32 * 1024]u8
    egress_bytes: [64 * 1024]u8
    mailbox_test_burst_reuse(t, &ingress, bridgemodel.Julia_Host_Ingress(
        protocol.Evaluation_Requested{
            code = string(ingress_bytes[:]),
        }))
    mailbox_test_burst_reuse(t, &egress, bridgemodel.Julia_Host_Egress(
        protocol.Terminal_Output_Batch{
            bytes = string(egress_bytes[:]),
        }))
}

// Exact logical-byte admission succeeds; one additional payload byte fails even unaligned.
@(test)
consumer_mailbox_exact_storage_bounds :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(bridgemodel.Julia_Host_Ingress)
    node_bytes := mailbox_align(
        size_of(bridgemodel.Mailbox_Node(bridgemodel.Julia_Host_Ingress)), 16)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, node_bytes + 3, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    exact := bridgemodel.Julia_Host_Ingress(protocol.Evaluation_Requested{
        code = "abc",
    })
    oversized := bridgemodel.Julia_Host_Ingress(protocol.Evaluation_Requested{
        code = "abcd",
    })
    testing.expect_value(t, consumer_mailbox_publish(&inbox, exact),
        bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, inbox.accepted_bytes, inbox.byte_limit)
    message, _ := consumer_mailbox_try_recv(&inbox)
    consumer_mailbox_release(&inbox, message)
    testing.expect_value(t, consumer_mailbox_publish(&inbox, oversized),
        bridgemodel.Communication_Send_Outcome.Storage_Full)
    testing.expect_value(t, inbox.outstanding, 0)
    testing.expect_value(t, inbox.accepted_bytes, 0)
    testing.expect_value(t, consumer_mailbox_send(&inbox, oversized),
        bridgemodel.Communication_Send_Outcome.Storage_Full)
    consumer_mailbox_close(&inbox)
    testing.expect_value(t, consumer_mailbox_send(&inbox, oversized),
        bridgemodel.Communication_Send_Outcome.Channel_Closed)
}

// Publish an ordered stream from another thread and close without discarding accepted work.
mailbox_test_sender :: proc(data: rawptr) {
    sender := cast(^Mailbox_Test_Sender)data
    for index in 0..<sender.count {
        sender.outcome = consumer_mailbox_send(sender.inbox, u64(index))
        if sender.outcome != .Sent {
            break
        }
    }
    consumer_mailbox_close(sender.inbox)
}

// Concurrent accept/drain/reset cycles preserve every accepted FIFO message.
@(test)
consumer_mailbox_concurrent_fifo_and_close :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 8192, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    sender: Mailbox_Test_Sender = {
        inbox = &inbox,
        count = 1000,
    }
    worker := thread.create_and_start_with_data(&sender, mailbox_test_sender)
    testing.expect(t, worker != nil)
    if worker == nil {
        return
    }
    count := 0
    for {
        message, ok := consumer_mailbox_recv(&inbox)
        if !ok {
            break
        }
        testing.expect_value(t, message^, u64(count))
        consumer_mailbox_release(&inbox, message)
        count += 1
    }
    thread.join(worker)
    thread.destroy(worker)
    testing.expect_value(t, count, 1000)
    testing.expect_value(t, sender.outcome, bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, inbox.outstanding, 0)
}

// Closing during a drain wakes reliable senders; final release cannot reopen closure.
@(test)
consumer_mailbox_close_wakes_capacity_waiter :: proc(t: ^testing.T) {
    inbox: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&inbox, 4096, 8192, 1),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&inbox)
    _ = consumer_mailbox_publish(&inbox, u64(7))
    message, _ := consumer_mailbox_try_recv(&inbox)
    sender: Mailbox_Test_Sender = {
        inbox = &inbox,
        count = 1,
    }
    worker := thread.create_and_start_with_data(&sender, mailbox_test_sender)
    testing.expect(t, worker != nil)
    if worker == nil {
        consumer_mailbox_release(&inbox, message)
        return
    }
    consumer_mailbox_close(&inbox)
    thread.join(worker)
    thread.destroy(worker)
    testing.expect_value(t, sender.outcome,
        bridgemodel.Communication_Send_Outcome.Channel_Closed)
    testing.expect_value(t, message^, u64(7))
    consumer_mailbox_release(&inbox, message)
    testing.expect_value(t, consumer_mailbox_publish(&inbox, u64(8)),
        bridgemodel.Communication_Send_Outcome.Channel_Closed)
    testing.expect(t, consumer_mailbox_finished(&inbox))
}

// Model Julia waiting to publish a completion while display dispatch finishes its batch.
mailbox_test_exchange :: proc(data: rawptr) {
    work := cast(^Mailbox_Test_Exchange)data
    work.ingress_outcome = consumer_mailbox_publish(work.ingress, u64(3))
    sync.atomic_store_explicit(&work.entered, true, .Release)
    work.egress_outcome = consumer_mailbox_send(work.egress, u64(4))
}

// Simultaneous drains report nonblocking pressure and unblock reliable output at reset.
@(test)
consumer_mailbox_bidirectional_drain_pressure :: proc(t: ^testing.T) {
    ingress, egress: bridgemodel.Consumer_Mailbox(u64)
    testing.expect_value(t, consumer_mailbox_init(&ingress, 4096, 4096, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&ingress)
    testing.expect_value(t, consumer_mailbox_init(&egress, 4096, 4096, 64),
        runtime.Allocator_Error.None)
    defer consumer_mailbox_destroy(&egress)
    _ = consumer_mailbox_publish(&ingress, u64(1))
    _ = consumer_mailbox_publish(&egress, u64(2))
    request, _ := consumer_mailbox_try_recv(&ingress)
    output, _ := consumer_mailbox_try_recv(&egress)
    work: Mailbox_Test_Exchange = {
        ingress = &ingress,
        egress = &egress,
    }
    worker := thread.create_and_start_with_data(&work, mailbox_test_exchange)
    assert(worker != nil)
    for !sync.atomic_load_explicit(&work.entered, .Acquire) {
        thread.yield()
    }
    testing.expect_value(t, work.ingress_outcome,
        bridgemodel.Communication_Send_Outcome.Queue_Full)
    testing.expect_value(t, output^, u64(2))
    consumer_mailbox_release(&egress, output)
    thread.join(worker)
    thread.destroy(worker)
    testing.expect_value(t, work.egress_outcome,
        bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, request^, u64(1))
    consumer_mailbox_release(&ingress, request)
    completion, _ := consumer_mailbox_try_recv(&egress)
    testing.expect_value(t, completion^, u64(4))
    consumer_mailbox_release(&egress, completion)
}
