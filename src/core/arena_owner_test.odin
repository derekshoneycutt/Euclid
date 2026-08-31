package core

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
import "core:testing"

//   Reject deterministic initialization failure without publishing owner state.
@(test)
core_test_arena_owner_rejects_initialization_failure :: proc(t: ^testing.T) {
    owner: Arena_Owner
    initialized := arena_owner_init_with(
        &owner, ARENA_OWNER_DEFAULT_RESERVATION, arena_owner_test_init_failure)
    testing.expect(t, !initialized)
    testing.expect(t, !owner.initialized)
    testing.expect(t, owner.arena.curr_block == nil)
    testing.expect_value(t, owner.initial_reservation, uint(0))
}

//   Retain the first block, release growth blocks, and preserve peak diagnostics.
@(test)
core_test_arena_owner_reset_releases_growth_blocks :: proc(t: ^testing.T) {
    owner: Arena_Owner
    testing.expect(t, arena_owner_init(&owner))
    allocator := arena_owner_allocator(&owner)
    initial := arena_owner_diagnostics(&owner)
    bytes := make([]u8, 2*mem.Megabyte, allocator)
    bytes[0] = 1
    grown := arena_owner_diagnostics(&owner)
    testing.expect(t, grown.current_used >= uint(len(bytes)))
    testing.expect(t, grown.current_reserved > initial.current_reserved)

    arena_owner_reset(&owner)
    reset := arena_owner_diagnostics(&owner)
    testing.expect_value(t, reset.current_used, uint(0))
    testing.expect_value(t, reset.current_reserved, initial.current_reserved)
    testing.expect(t, reset.current_committed <= grown.current_committed)
    testing.expect_value(t, reset.peak_reserved, grown.current_reserved)
    testing.expect_value(t, reset.reset_count, u64(1))
    arena_owner_destroy(&owner)
}

//   Release all storage and retain terminal counters for teardown evidence.
@(test)
core_test_arena_owner_destroy_preserves_diagnostics :: proc(t: ^testing.T) {
    owner: Arena_Owner
    testing.expect(t, arena_owner_init(&owner, 64*uint(mem.Kilobyte)))
    allocator := arena_owner_allocator(&owner)
    bytes := make([]u8, 4096, allocator)
    bytes[0] = 1
    before := arena_owner_diagnostics(&owner)

    arena_owner_destroy(&owner)
    after := arena_owner_diagnostics(&owner)
    testing.expect(t, !after.initialized)
    testing.expect_value(t, after.current_used, uint(0))
    testing.expect_value(t, after.current_reserved, uint(0))
    testing.expect_value(t, after.current_committed, uint(0))
    testing.expect_value(t, after.peak_used, before.peak_used)
    testing.expect_value(t, after.destroy_count, u64(1))
    testing.expect_value(t, arena_owner_allocator(&owner), runtime.Allocator{})
}

//   Supply a deterministic failed initialization for owner cleanup tests.
arena_owner_test_init_failure :: proc(
    arena: ^vmem.Arena, reservation: uint) -> bool {
    arena_error := vmem.arena_init_growing(arena, reservation)
    if arena_error != nil {
        return false
    }
    return false
}