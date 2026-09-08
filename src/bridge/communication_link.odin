package bridge

import "../core"

import "base:runtime"
import "core:mem/tlsf"
import "core:sync/chan"

// Initialize fixed TLSF backing and equally bounded outbound and return channels.
communication_link_init :: proc(
    link: ^core.Communication_Link($T), channel_capacity: int, pool_size: int,
    allocator := context.allocator) -> runtime.Allocator_Error {
    backing, backing_error := make([]byte, pool_size, allocator)
    if backing_error != .None {
        return backing_error
    }
    if tlsf.init_from_buffer(&link.pool, backing) != .None {
        delete(backing, allocator)
        return .Out_Of_Memory
    }
    outbound, outbound_error := chan.create(
        chan.Chan(^T), channel_capacity, allocator)
    if outbound_error != .None {
        delete(backing, allocator)
        return outbound_error
    }
    returns, returns_error := chan.create(
        chan.Chan(^T), channel_capacity, allocator)
    if returns_error != .None {
        _ = chan.destroy(outbound)
        delete(backing, allocator)
        return returns_error
    }
    link.outbound = outbound
    link.returns = returns
    link.backing = backing
    link.backing_allocator = allocator
    return .None
}

// Destroy one stopped link after every borrowed envelope has returned to its producer.
communication_link_destroy :: proc(link: ^core.Communication_Link($T)) {
    _ = chan.destroy(link.outbound)
    _ = chan.destroy(link.returns)
    delete(link.backing, link.backing_allocator)
    link^ = {}
}

// Allocate one zeroed envelope from the caller-owned link pool with explicit failure.
communication_link_alloc :: proc(
    link: ^core.Communication_Link($T)) -> (^T, runtime.Allocator_Error) {
    pool_allocator := tlsf.allocator(&link.pool)
    return new(T, pool_allocator)
}

// Allocate exact nested bytes from the same producer-owned pool as an envelope.
communication_link_alloc_bytes :: proc(
    link: ^core.Communication_Link($T), count: int) -> ([]u8, runtime.Allocator_Error) {
    pool_allocator := tlsf.allocator(&link.pool)
    return make([]u8, count, pool_allocator)
}

// Reclaim nested bytes allocated from one producer-owned link pool.
communication_link_free_bytes :: proc(
    link: ^core.Communication_Link($T), bytes: []u8) {
    delete(bytes, tlsf.allocator(&link.pool))
}

// Reclaim one envelope that the producer has not transferred or has received back.
communication_link_free :: proc(link: ^core.Communication_Link($T), message: ^T) {
    free(message, tlsf.allocator(&link.pool))
}

// Try to transfer one producer-owned envelope without blocking on outbound capacity.
communication_link_try_send :: proc(
    link: ^core.Communication_Link($T), message: ^T) -> bool {
    return chan.try_send(link.outbound, message)
}

// Transfer one producer-owned envelope, waiting for bounded outbound capacity.
communication_link_send :: proc(
    link: ^core.Communication_Link($T), message: ^T) -> bool {
    return chan.send(link.outbound, message)
}

// Wait for one outbound envelope, returning false only when the channel is closed.
communication_link_recv :: proc(
    link: ^core.Communication_Link($T)) -> (^T, bool) {
    return chan.recv(link.outbound)
}

// Try to borrow one outbound envelope without blocking the receiver.
communication_link_try_recv :: proc(
    link: ^core.Communication_Link($T)) -> (^T, bool) {
    return chan.try_recv(link.outbound)
}

// Return one consumed envelope to its producer, waiting for bounded return capacity.
communication_link_return :: proc(
    link: ^core.Communication_Link($T), message: ^T) -> bool {
    return chan.send(link.returns, message)
}

// Borrow one returned envelope for producer-specific nested destruction.
communication_link_try_take_return :: proc(
    link: ^core.Communication_Link($T)) -> (^T, bool) {
    return chan.try_recv(link.returns)
}

// Reclaim every returned envelope on the producer thread and report the drained count.
communication_link_drain_returns :: proc(
    link: ^core.Communication_Link($T)) -> int {
    count := 0
    for {
        message, ok := chan.try_recv(link.returns)
        if !ok {
            return count
        }
        communication_link_free(link, message)
        count += 1
    }
}