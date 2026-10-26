package storage

import "base:runtime"
import "core:mem"
import tlsf "core:mem/tlsf"
import "core:testing"

Tlsf_Owner_Test_Allocator_State :: struct {
    remaining_allocations: int,
    live_backing_allocations: int,
}

// Grow beyond the first pool without moving allocations already returned.
@(test)
storage_test_tlsf_owner_grows_and_preserves_live_pointers :: proc(t: ^testing.T) {
    owner: Tlsf_Owner
    status := tlsf_owner_init(
        &owner, context.allocator, 8*uint(mem.Kilobyte), 16*uint(mem.Kilobyte))
    testing.expect_value(t, status, Tlsf_Owner_Status.Ok)
    allocator := tlsf_owner_allocator(&owner)
    first, first_error := runtime.make_aligned(
        []u8, 4096, 256, allocator)
    testing.expect_value(t, first_error, mem.Allocator_Error.None)
    first_address := uintptr(raw_data(first))
    first[0] = 91
    large, large_error := runtime.make_aligned(
        []u8, 2*uint(mem.Megabyte), 256, allocator)
    testing.expect_value(t, large_error, mem.Allocator_Error.None)
    testing.expect(t, uintptr(raw_data(large))%256 == 0)
    testing.expect_value(t, uintptr(raw_data(first)), first_address)
    testing.expect_value(t, first[0], u8(91))
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.pool_count, uint(2))
    testing.expect(t, diagnostics.retained_bytes > 2*uint(mem.Megabyte))
    delete(large, allocator)
    delete(first, allocator)
    tlsf_owner_destroy(&owner)
    diagnostics = tlsf_owner_diagnostics(&owner)
    testing.expect(t, !diagnostics.initialized)
    testing.expect_value(t, diagnostics.retained_bytes, uint(0))
    testing.expect_value(t, diagnostics.destroy_count, uint(1))
}

// Reuse freed TLSF blocks over repeated fixed-shape churn.
@(test)
storage_test_tlsf_owner_reuses_freed_blocks :: proc(t: ^testing.T) {
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, context.allocator, 256*uint(mem.Kilobyte),
        64*uint(mem.Kilobyte)), Tlsf_Owner_Status.Ok)
    allocator := tlsf_owner_allocator(&owner)
    blocks: [32][]u8
    for &block in blocks {
        block = make([]u8, 4096, allocator)
    }
    for block in blocks {
        delete(block, allocator)
    }
    initial_pools := tlsf_owner_diagnostics(&owner).pool_count
    for _ in 0..<20 {
        block := make([]u8, 4096, allocator)
        delete(block, allocator)
    }
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.pool_count, initial_pools)
    testing.expect_value(t, diagnostics.current_live_bytes, uint(0))
    testing.expect_value(t, diagnostics.live_allocation_count, uint(0))
    testing.expect(t, diagnostics.peak_allocation_count >= uint(len(blocks)))
    tlsf_owner_destroy(&owner)
}

// Preserve old bytes when a resize must move into a newly grown pool.
@(test)
storage_test_tlsf_owner_resize_is_failure_atomic :: proc(t: ^testing.T) {
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, context.allocator, 8*uint(mem.Kilobyte),
        16*uint(mem.Kilobyte)), Tlsf_Owner_Status.Ok)
    allocator := tlsf_owner_allocator(&owner)
    bytes := make([]u8, 4096, allocator)
    bytes[0] = 37
    bytes[len(bytes)-1] = 83
    resized, resize_error := allocator.procedure(
        allocator.data,
        .Resize,
        2*int(mem.Megabyte),
        64,
        raw_data(bytes),
        len(bytes))
    testing.expect_value(t, resize_error, mem.Allocator_Error.None)
    if resize_error == nil {
        testing.expect_value(t, resized[0], u8(37))
        testing.expect_value(t, resized[4095], u8(83))
        testing.expect_value(
            t, tlsf_owner_diagnostics(&owner).live_allocation_count, uint(1))
        delete(resized, allocator)
    } else {
        testing.expect_value(t, bytes[0], u8(37))
        testing.expect_value(t, bytes[4095], u8(83))
        delete(bytes, allocator)
    }
    tlsf_owner_destroy(&owner)
}

// Keep a committed allocation intact when growth for its replacement fails.
@(test)
storage_test_tlsf_owner_failed_resize_keeps_old_allocation :: proc(t: ^testing.T) {
    state: Tlsf_Owner_Test_Allocator_State = {
        remaining_allocations = 10,
    }
    backing_allocator := tlsf_owner_test_allocator(&state)
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, backing_allocator, 8*uint(mem.Kilobyte),
        16*uint(mem.Kilobyte)), Tlsf_Owner_Status.Ok)
    allocator := tlsf_owner_allocator(&owner)
    bytes := make([]u8, 4096, allocator)
    bytes[0] = 41
    bytes[4095] = 79
    state.remaining_allocations = 0
    _, resize_error := allocator.procedure(
        allocator.data,
        .Resize,
        2*int(mem.Megabyte),
        64,
        raw_data(bytes),
        len(bytes))
    testing.expect_value(t, resize_error, mem.Allocator_Error.Out_Of_Memory)
    testing.expect_value(t, bytes[0], u8(41))
    testing.expect_value(t, bytes[4095], u8(79))
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.current_live_bytes, uint(len(bytes)))
    testing.expect_value(t, diagnostics.live_allocation_count, uint(1))
    delete(bytes, allocator)
    tlsf_owner_destroy(&owner)
    testing.expect_value(t, state.live_backing_allocations, 0)
}

// Leave the current owner usable when pool metadata allocation fails.
@(test)
storage_test_tlsf_owner_metadata_failure_keeps_committed_pool :: proc(t: ^testing.T) {
    state: Tlsf_Owner_Test_Allocator_State = {
        remaining_allocations = 10,
    }
    backing_allocator := tlsf_owner_test_allocator(&state)
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, backing_allocator, 8*uint(mem.Kilobyte),
        16*uint(mem.Kilobyte)), Tlsf_Owner_Status.Ok)
    state.remaining_allocations = 0
    allocator := tlsf_owner_allocator(&owner)
    _, allocation_error := runtime.make_aligned(
        []u8, 2*uint(mem.Megabyte), int(tlsf.ALIGN_SIZE), allocator)
    testing.expect_value(t, allocation_error, mem.Allocator_Error.Out_Of_Memory)
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.pool_count, uint(1))
    testing.expect_value(t, diagnostics.growth_failure_count, uint(1))
    small := make([]u8, 128, allocator)
    testing.expect_value(t, len(small), 128)
    delete(small, allocator)
    tlsf_owner_destroy(&owner)
    testing.expect_value(t, state.live_backing_allocations, 0)
}

// Release provisional pool metadata when backing acquisition fails.
@(test)
storage_test_tlsf_owner_backing_failure_releases_metadata :: proc(t: ^testing.T) {
    state: Tlsf_Owner_Test_Allocator_State = {
        remaining_allocations = 10,
    }
    backing_allocator := tlsf_owner_test_allocator(&state)
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, backing_allocator, 8*uint(mem.Kilobyte),
        16*uint(mem.Kilobyte)), Tlsf_Owner_Status.Ok)
    state.remaining_allocations = 1
    allocator := tlsf_owner_allocator(&owner)
    _, allocation_error := runtime.make_aligned(
        []u8, 2*uint(mem.Megabyte), int(tlsf.ALIGN_SIZE), allocator)
    testing.expect_value(t, allocation_error, mem.Allocator_Error.Out_Of_Memory)
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.pool_count, uint(1))
    testing.expect_value(t, diagnostics.growth_failure_count, uint(1))
    testing.expect_value(t, state.live_backing_allocations, 2)
    tlsf_owner_destroy(&owner)
    testing.expect_value(t, state.live_backing_allocations, 0)
}

// Reject invalid initialization inputs before publishing allocator state.
@(test)
storage_test_tlsf_owner_rejects_invalid_initialization :: proc(t: ^testing.T) {
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(
        &owner, context.allocator, 0, 1024), Tlsf_Owner_Status.Invalid_Capacity)
    testing.expect(t, !owner.initialized)
    testing.expect_value(t, tlsf_owner_init(
        &owner, {}, 1024, 1024), Tlsf_Owner_Status.Invalid_Owner)
    testing.expect(t, !owner.initialized)
}

// Reject requests whose TLSF class slack would exceed the supported pool range.
@(test)
storage_test_tlsf_owner_rejects_unsupported_request :: proc(t: ^testing.T) {
    owner: Tlsf_Owner
    testing.expect_value(t, tlsf_owner_init(&owner, context.allocator),
        Tlsf_Owner_Status.Ok)
    allocator := tlsf_owner_allocator(&owner)
    _, allocation_error := allocator.procedure(
        allocator.data,
        .Alloc,
        max_pool_capacity(),
        int(tlsf.ALIGN_SIZE),
        nil,
        0)
    testing.expect_value(t, allocation_error, mem.Allocator_Error.Out_Of_Memory)
    diagnostics := tlsf_owner_diagnostics(&owner)
    testing.expect_value(t, diagnostics.pool_count, uint(1))
    testing.expect_value(t, diagnostics.growth_failure_count, uint(1))
    tlsf_owner_destroy(&owner)
}

// Fail deterministic backing requests while forwarding frees to the test heap.
tlsf_owner_test_allocator :: proc(
    state: ^Tlsf_Owner_Test_Allocator_State) -> runtime.Allocator {
    return {
        procedure = tlsf_owner_test_allocator_proc,
        data = state,
    }
}

// Count allocations while preserving normal allocator alignment and release behavior.
tlsf_owner_test_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
        ([]byte, runtime.Allocator_Error) {
    state := cast(^Tlsf_Owner_Test_Allocator_State)allocator_data
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        if state.remaining_allocations <= 0 {
            return nil, .Out_Of_Memory
        }
        state.remaining_allocations -= 1
    }
    result, err := runtime.default_allocator_proc(
        nil, mode, size, alignment, old_memory, old_size, location)
    if err == nil && (mode == .Alloc || mode == .Alloc_Non_Zeroed) {
        state.live_backing_allocations += 1
    } else if err == nil && mode == .Free {
        state.live_backing_allocations -= 1
    }
    return result, err
}
