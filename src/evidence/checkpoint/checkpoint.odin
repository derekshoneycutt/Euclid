package evidence_checkpoint

// Package evidence_checkpoint owns fixed-capacity Euclid state snapshots.
//
// Checkpoints copy synchronized simulation state into store-owned memory. The
// store performs no allocation: it reuses slots in insertion order and exposes
// their contents through generational handles.

// Maximum resident snapshots and copied points per snapshot.
CHECKPOINT_STORE_CAPACITY :: 8
CHECKPOINT_POINT_CAPACITY :: 256

// Generational reference to one currently resident checkpoint slot.
//
// Reusing a slot changes its generation, which makes every older handle for
// that slot stale. The zero handle does not identify an initialized entry.
Handle :: struct {
    slot : u16,
    generation : u16,
}

// Pointer-free point state copied from the authoritative point system.
//
// The record preserves resolved position, drawing state, and point-system
// identity without retaining source pointers. Position components are valid
// only when has_position is true.
Point :: struct {
    // Resolved world-space position, guarded by has_position.
    x : f32,
    y : f32,
    z : f32,

    // Drawing state needed to inspect the captured point.
    brush_size : f32,
    offset : f32,

    // Stable source slot and its active child relationship.
    index : i32,
    active_child : i32,

    // Captured visibility and optional-position state.
    visible : bool,
    has_position : bool,
}

// Self-contained Euclid state captured after the simulation task fence joins.
//
// Simulation and animation fields identify the exact logical boundary observed.
// point_count selects the initialized prefix of points; it is truncated to
// CHECKPOINT_POINT_CAPACITY when the source system contains more points.
// Constraint counts always summarize the full source system because individual
// constraint records are not copied into the checkpoint.
Snapshot :: struct {
    // Simulation boundary represented by this checkpoint.
    fixed_step : u64,
    simulation_time : f32,

    // Runtime and animation identity current at that boundary.
    runtime_generation : u64,
    animation_generation : u64,
    animation_tick_sequence : u64,

    // Copied point prefix and full-system constraint summary.
    point_count : int,
    constraint_count : int,
    active_constraint_count : int,

    // Inline storage; only points[:point_count] is initialized evidence.
    points : [CHECKPOINT_POINT_CAPACITY]Point,
}

// Store-owned slot containing one snapshot and its overwrite policy.
//
// required marks evidence whose later eviction must make completeness loss
// sticky, even when the replacement itself is optional.
Entry :: struct {
    snapshot : Snapshot,
    generation : u16,
    occupied : bool,
    required : bool,
}

// Fixed circular checkpoint store with sticky required-evidence loss.
//
// Entries and snapshots are inline-owned by the store. next_slot identifies
// the next slot to replace; required_evidence_lost remains true after any
// required entry is replaced and is cleared only when the store is reset.
Store :: struct {
    entries : [CHECKPOINT_STORE_CAPACITY]Entry,
    next_slot : int,
    required_evidence_lost : bool,
}

//   Copy a snapshot into the next circular slot.
//
// Parameters:
//   - store: Destination store that owns the copied snapshot.
//   - snapshot: Complete fixed-size value to copy into store storage.
//   - required: Whether losing this snapshot must mark evidence incomplete.
//
// Returns:
//   - A handle valid until its slot is reused, or the zero handle for nil store.
//
// Side effects:
//   - Replaces the next slot and advances insertion order.
//   - Invalidates the replaced slot's previous handle.
//   - Permanently marks required evidence lost when replacing a required entry.
store_put :: proc(store: ^Store, snapshot: Snapshot, required: bool) -> Handle {
    if store == nil {
        return {}
    }
    slot := store.next_slot
    entry := &store.entries[slot]
    if entry.occupied && entry.required {
        store.required_evidence_lost = true
    }
    generation := entry.generation + 1
    if generation == 0 {
        generation = 1
    }
    entry^ = {
        snapshot = snapshot,
        generation = generation,
        occupied = true,
        required = required,
    }
    store.next_slot = (slot + 1) % CHECKPOINT_STORE_CAPACITY
    return {slot = u16(slot), generation = generation}
}

//   Resolve a current handle to checkpoint storage owned by the store.
//
// Parameters:
//   - store: Store that issued the handle.
//   - handle: Slot and generation pair to validate.
//
// Returns:
//   - A borrowed snapshot pointer and true when the handle is current.
//   - Nil and false for nil stores, invalid slots, empty slots, or stale handles.
//
// Notes:
//   - The pointer remains valid only until its slot is reused or the store's
//     storage lifetime ends. Callers must not retain it across checkpoint writes
//     that can wrap to the same slot.
store_get :: proc(store: ^Store, handle: Handle) -> (^Snapshot, bool) {
    if store == nil || int(handle.slot) >= len(store.entries) {
        return nil, false
    }
    entry := &store.entries[handle.slot]
    if !entry.occupied || entry.generation != handle.generation {
        return nil, false
    }
    return &entry.snapshot, true
}
