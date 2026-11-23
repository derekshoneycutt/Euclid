package transport

import bridgemodel "../model"
import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
import "core:sync"
import "core:time"

// Round message layout offsets to preserve nested typed-data alignment.
mailbox_align :: proc(value, alignment: int) -> int {
    return (value + alignment - 1) / alignment * alignment
}

// Initialize one standard growing arena before publishing the mailbox endpoint.
consumer_mailbox_init :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T),
    initial_bytes, byte_limit, count_limit: int,
    initialize: proc(^vmem.Arena, uint) -> runtime.Allocator_Error =
        vmem.arena_init_growing) -> runtime.Allocator_Error {
    if mailbox.initialized || initial_bytes <= 0 || byte_limit <= 0 ||
        count_limit <= 0 || initialize == nil {
        return .Invalid_Argument
    }
    err := initialize(&mailbox.arena, uint(initial_bytes))
    if err != .None {
        vmem.arena_destroy(&mailbox.arena)
        return err
    }
    mailbox.byte_limit = byte_limit
    mailbox.count_limit = count_limit
    mailbox.peak_outstanding = 0
    mailbox.peak_bytes = 0
    mailbox.publication_count = 0
    mailbox.publication_time = 0
    mailbox.lock_wait_time = 0
    mailbox.copy_time = 0
    mailbox.closed = false
    mailbox.initialized = true
    return .None
}

// Close admission and wake both a sleeping consumer and reliable capacity waiters.
consumer_mailbox_close :: proc(mailbox: ^bridgemodel.Consumer_Mailbox($T)) {
    sync.mutex_lock(&mailbox.mutex)
    mailbox.closed = true
    sync.cond_broadcast(&mailbox.changed)
    sync.mutex_unlock(&mailbox.mutex)
}

// Release the arena only after publishers, consumer borrows, and waiters have stopped.
consumer_mailbox_destroy :: proc(mailbox: ^bridgemodel.Consumer_Mailbox($T)) {
    if !mailbox.initialized {
        return
    }
    assert(mailbox.borrowed == nil)
    consumer_mailbox_close(mailbox)
    vmem.arena_destroy(&mailbox.arena)
    mailbox.first = nil
    mailbox.last = nil
    mailbox.accepted_bytes = 0
    mailbox.outstanding = 0
    mailbox.draining = false
    mailbox.initialized = false
}

// Copy a typed message atomically; allocator injection is for deterministic failure tests.
consumer_mailbox_publish :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T), value: T,
    allocator: mem.Allocator = {}) -> bridgemodel.Communication_Send_Outcome {
    started := time.tick_now()
    _, payload_bytes := mailbox_copy_value(value, nil)
    node_bytes := mailbox_align(size_of(bridgemodel.Mailbox_Node(T)), 16)
    required := node_bytes + payload_bytes
    lock_started := time.tick_now()
    sync.mutex_lock(&mailbox.mutex)
    defer sync.mutex_unlock(&mailbox.mutex)
    mailbox.lock_wait_time += time.tick_since(lock_started)
    if !mailbox.initialized || mailbox.closed {
        return .Channel_Closed
    }
    if required > mailbox.byte_limit {
        return .Storage_Full
    }
    if mailbox.draining || mailbox.outstanding >= mailbox.count_limit {
        return .Queue_Full
    }
    if required > mailbox.byte_limit - mailbox.accepted_bytes {
        return .Storage_Full
    }
    selected_allocator := allocator if allocator.procedure != nil else
        vmem.arena_allocator(&mailbox.arena)
    bytes, err := mem.alloc_bytes(required, 16, selected_allocator)
    if err != .None {
        return .Allocation_Failed
    }
    node := cast(^bridgemodel.Mailbox_Node(T))raw_data(bytes)
    copy_started := time.tick_now()
    node.value, _ = mailbox_copy_value(value, bytes[node_bytes:])
    mailbox.copy_time += time.tick_since(copy_started)
    mailbox_commit_node(mailbox, node, required)
    mailbox.publication_time += time.tick_since(started)
    return .Sent
}

// Observe logical pressure and measured publication costs without exposing allocator state.
consumer_mailbox_diagnostics :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T)) ->
        bridgemodel.Consumer_Mailbox_Diagnostics {
    sync.mutex_lock(&mailbox.mutex)
    defer sync.mutex_unlock(&mailbox.mutex)
    return {
        accepted_bytes = mailbox.accepted_bytes,
        byte_limit = mailbox.byte_limit,
        outstanding = mailbox.outstanding,
        peak_outstanding = mailbox.peak_outstanding,
        peak_bytes = mailbox.peak_bytes,
        publication_count = mailbox.publication_count,
        publication_time = mailbox.publication_time,
        lock_wait_time = mailbox.lock_wait_time,
        copy_time = mailbox.copy_time,
    }
}

// Commit FIFO linkage and epoch admission accounting after the complete payload copy.
mailbox_commit_node :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T),
    node: ^bridgemodel.Mailbox_Node(T), required: int) {
    if mailbox.last != nil {
        mailbox.last.next = node
    } else {
        mailbox.first = node
    }
    mailbox.last = node
    mailbox.outstanding += 1
    mailbox.accepted_bytes += required
    mailbox.peak_outstanding = max(mailbox.peak_outstanding, mailbox.outstanding)
    mailbox.peak_bytes = max(mailbox.peak_bytes, mailbox.accepted_bytes)
    mailbox.publication_count += 1
    sync.cond_broadcast(&mailbox.changed)
}

// Reliably publish outside capacity waits; closure and impossible sizes terminate the wait.
consumer_mailbox_send :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T),
    value: T) -> bridgemodel.Communication_Send_Outcome {
    _, payload_bytes := mailbox_copy_value(value, nil)
    required := mailbox_align(size_of(bridgemodel.Mailbox_Node(T)), 16) + payload_bytes
    for {
        outcome := consumer_mailbox_publish(mailbox, value)
        if outcome != .Queue_Full && outcome != .Storage_Full {
            return outcome
        }
        if required > mailbox.byte_limit {
            return .Storage_Full
        }
        consumer_mailbox_wait(mailbox, time.Millisecond, true)
    }
}

// Observe terminal closure only after every accepted queued or borrowed value is exhausted.
consumer_mailbox_finished :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T)) -> bool {
    sync.mutex_lock(&mailbox.mutex)
    defer sync.mutex_unlock(&mailbox.mutex)
    return mailbox.closed && mailbox.first == nil
}

// Pause admission for one finite accepted FIFO; empty passes leave admission open.
consumer_mailbox_batch_count :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T)) -> int {
    sync.mutex_lock(&mailbox.mutex)
    defer sync.mutex_unlock(&mailbox.mutex)
    if mailbox.first != nil {
        mailbox.draining = true
    }
    return mailbox.outstanding
}

// Borrow the next envelope until explicit release; the sole consumer must finish the drain.
consumer_mailbox_try_recv :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T)) -> (^T, bool) {
    sync.mutex_lock(&mailbox.mutex)
    defer sync.mutex_unlock(&mailbox.mutex)
    assert(mailbox.borrowed == nil)
    if mailbox.first == nil {
        return nil, false
    }
    mailbox.draining = true
    mailbox.borrowed = mailbox.first
    return &mailbox.borrowed.value, true
}

// Wait using queue truth, then pause admission and borrow through the same consumer cursor.
consumer_mailbox_recv :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T)) -> (^T, bool) {
    for {
        if value, ok := consumer_mailbox_try_recv(mailbox); ok {
            return value, true
        }
        sync.mutex_lock(&mailbox.mutex)
        if mailbox.closed {
            sync.mutex_unlock(&mailbox.mutex)
            return nil, false
        }
        if mailbox.first == nil {
            sync.cond_wait(&mailbox.changed, &mailbox.mutex)
        }
        sync.mutex_unlock(&mailbox.mutex)
    }
}

// End one borrow; the final release resets the arena before reopening admission.
consumer_mailbox_release :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T), value: ^T) {
    assert(mailbox.borrowed != nil && value == &mailbox.borrowed.value)
    sync.mutex_lock(&mailbox.mutex)
    mailbox.first = mailbox.borrowed.next
    mailbox.borrowed = nil
    mailbox.outstanding -= 1
    if mailbox.first == nil {
        vmem.arena_free_all(&mailbox.arena)
        mailbox.last = nil
        mailbox.accepted_bytes = 0
        mailbox.draining = false
        sync.cond_broadcast(&mailbox.changed)
    }
    sync.mutex_unlock(&mailbox.mutex)
}

// Sleep with queue/admission predicates; publication, reset, and closure wake waiters.
consumer_mailbox_wait :: proc(
    mailbox: ^bridgemodel.Consumer_Mailbox($T),
    timeout: time.Duration, capacity := false) {
    sync.mutex_lock(&mailbox.mutex)
    if !mailbox.closed && timeout > 0 &&
        (capacity || mailbox.first == nil) {
        _ = sync.cond_wait_with_timeout(&mailbox.changed, &mailbox.mutex, timeout)
    }
    sync.mutex_unlock(&mailbox.mutex)
}
