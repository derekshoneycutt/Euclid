package core

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"

// Default first-block virtual-memory reservation for a growing arena owner.
ARENA_OWNER_DEFAULT_RESERVATION :: uint(mem.Megabyte)

// Initialize a supplied virtual arena with one explicit first-block reservation.
//
// Parameters:
//   - arena: Arena storage to initialize; the procedure may partially mutate it on
//     failure.
//   - reservation: Requested first-block reservation in bytes.
//
// Returns:
//   - True when the arena is ready for allocator publication; false otherwise.
Arena_Owner_Init_Proc :: proc(arena: ^vmem.Arena, reservation: uint) -> bool

// Report live and lifetime arena usage without exposing mutable owner state.
//
// Notes:
//   - All storage measurements are byte counts.
//   - Current measurements are zero after destruction; lifetime peaks remain available.
Arena_Owner_Diagnostics :: struct {
    // Lifecycle state and the retained first-block reservation established at init.
    initialized : bool,
    initial_reservation : uint,

    // Live aggregate usage across the arena's current block chain.
    current_used : uint,
    current_reserved : uint,
    current_committed : uint,

    // Lifetime high-water marks sampled before reset, destruction, and observation.
    peak_used : uint,
    peak_reserved : uint,
    peak_committed : uint,

    // Successful bulk lifecycle transitions performed by this owner.
    reset_count : u64,
    destroy_count : u64,
}

// Own one growing virtual arena, its allocator, and terminal lifecycle diagnostics.
//
// Notes:
//   - Allocations remain valid only until the next reset or destruction.
//   - The owner must not be copied after successful initialization.
Arena_Owner :: struct {
    // Live virtual-memory arena and allocator published from that arena.
    arena : vmem.Arena,
    allocator : runtime.Allocator,

    // Configured first-block reservation and lifetime usage high-water marks in bytes.
    initial_reservation : uint,
    peak_used : uint,
    peak_reserved : uint,
    peak_committed : uint,

    // Completed bulk transitions and the guard for access to live arena storage.
    reset_count : u64,
    destroy_count : u64,
    initialized : bool,
}

//   Initialize one growing arena with an explicit first-block reservation.
//
// Parameters:
//   - owner: Uninitialized owner that receives the arena and allocator on success.
//   - reservation: Nonzero first-block reservation in bytes.
//
// Returns:
//   - True on complete initialization; false without publishing live owner state.
//
// Side effects:
//   - Reserves virtual address space and publishes the arena allocator on success.
arena_owner_init :: proc(
    owner: ^Arena_Owner,
    reservation := ARENA_OWNER_DEFAULT_RESERVATION) -> bool {
    return arena_owner_init_with(owner, reservation, arena_owner_growing_init)
}

//   Return the allocator for a live owner, or a zero allocator otherwise.
//
// Parameters:
//   - owner: Arena owner whose allocator is requested; nil is accepted.
//
// Returns:
//   - The arena allocator while initialized, or a zero allocator otherwise.
arena_owner_allocator :: proc(owner: ^Arena_Owner) -> runtime.Allocator {
    if owner == nil || !owner.initialized {
        return {}
    }
    return owner.allocator
}

//   Reset logical usage and release growth blocks while retaining the first block.
//
// Parameters:
//   - owner: Live arena owner to reset; nil and uninitialized owners are ignored.
//
// Side effects:
//   - Invalidates every allocation previously returned by this owner.
//   - Samples lifetime peaks and increments `reset_count` after a successful reset.
arena_owner_reset :: proc(owner: ^Arena_Owner) {
    if owner == nil || !owner.initialized {
        return
    }
    arena_owner_sample(owner)
    vmem.arena_free_all(&owner.arena)
    owner.reset_count += 1
}

//   Destroy virtual storage while retaining terminal high-water diagnostics.
//
// Parameters:
//   - owner: Live arena owner to destroy; nil and uninitialized owners are ignored.
//
// Side effects:
//   - Invalidates every allocation and releases all arena reservations.
//   - Clears allocator publication and increments `destroy_count` after destruction.
arena_owner_destroy :: proc(owner: ^Arena_Owner) {
    if owner == nil || !owner.initialized {
        return
    }
    arena_owner_sample(owner)
    vmem.arena_destroy(&owner.arena)
    owner.allocator = {}
    owner.initialized = false
    owner.destroy_count += 1
}

//   Snapshot current and lifetime-high arena usage for evidence and diagnostics.
//
// Parameters:
//   - owner: Arena owner to observe; nil returns zero diagnostics.
//
// Returns:
//   - Current byte counts, lifetime peaks, and lifecycle counters for the owner.
//
// Side effects:
//   - Advances high-water fields to include current arena usage.
arena_owner_diagnostics :: proc(owner: ^Arena_Owner) -> Arena_Owner_Diagnostics {
    if owner == nil {
        return {}
    }
    arena_owner_sample(owner)
    return Arena_Owner_Diagnostics {
        initialized = owner.initialized,
        initial_reservation = owner.initial_reservation,
        current_used = owner.arena.total_used,
        current_reserved = owner.arena.total_reserved,
        current_committed = arena_owner_committed(owner),
        peak_used = owner.peak_used,
        peak_reserved = owner.peak_reserved,
        peak_committed = owner.peak_committed,
        reset_count = owner.reset_count,
        destroy_count = owner.destroy_count,
    }
}

//   Initialize through a supplied primitive so failure cleanup is deterministic.
//
// Parameters:
//   - owner: Uninitialized owner that receives the arena and allocator on success.
//   - reservation: Nonzero first-block reservation in bytes.
//   - init_proc: Initialization primitive used to create the virtual arena.
//
// Returns:
//   - True on complete initialization; false after cleaning any partial arena state.
//
// Side effects:
//   - Destroys storage left by a failed initializer before clearing the owner.
arena_owner_init_with :: proc(
    owner: ^Arena_Owner,
    reservation: uint,
    init_proc: Arena_Owner_Init_Proc) -> bool {
    if owner == nil || owner.initialized || reservation == 0 || init_proc == nil {
        return false
    }
    owner^ = {}
    if !init_proc(&owner.arena, reservation) {
        if owner.arena.curr_block != nil {
            vmem.arena_destroy(&owner.arena)
        }
        owner^ = {}
        return false
    }
    owner.allocator = vmem.arena_allocator(&owner.arena)
    owner.initial_reservation = owner.arena.total_reserved
    owner.initialized = true
    arena_owner_sample(owner)
    return true
}

//   Adapt Odin's allocator-error result to the owner initialization contract.
//
// Parameters:
//   - arena: Arena storage initialized through Odin's growing-arena primitive.
//   - reservation: Requested first-block reservation in bytes.
//
// Returns:
//   - True when growing-arena initialization reports no allocator error.
arena_owner_growing_init :: proc(arena: ^vmem.Arena, reservation: uint) -> bool {
    arena_error := vmem.arena_init_growing(arena, reservation)
    return arena_error == nil
}

//   Include current arena counters in the owner's lifetime high-water values.
//
// Parameters:
//   - owner: Live owner to sample; nil and uninitialized owners are ignored.
//
// Side effects:
//   - Raises lifetime peaks when current usage exceeds a prior observation.
arena_owner_sample :: proc(owner: ^Arena_Owner) {
    if owner == nil || !owner.initialized {
        return
    }
    owner.peak_used = max(owner.peak_used, owner.arena.total_used)
    owner.peak_reserved = max(owner.peak_reserved, owner.arena.total_reserved)
    owner.peak_committed = max(
        owner.peak_committed, arena_owner_committed(owner))
}

//   Sum committed bytes across the live growing-arena block chain.
//
// Parameters:
//   - owner: Live owner whose block chain is inspected.
//
// Returns:
//   - Aggregate committed bytes, or zero for nil and uninitialized owners.
arena_owner_committed :: proc(owner: ^Arena_Owner) -> uint {
    if owner == nil || !owner.initialized {
        return 0
    }
    committed: uint
    block := owner.arena.curr_block
    for block != nil {
        committed += block.committed
        block = block.prev
    }
    return committed
}