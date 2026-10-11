package evidence_text

// Package evidence_text owns bounded text referenced by semantic events.
//
// Values are copied into allocation-free inline storage and exposed through
// generational handles. Circular replacement bounds memory and invalidates old
// handles without retaining source strings.

// Maximum resident entries and copied bytes per entry.
TEXT_STORE_CAPACITY :: 128
TEXT_ENTRY_CAPACITY :: 256

// Generational reference to one currently resident text slot.
//
// Reusing a slot changes its generation, making every older handle for that
// slot stale. The zero handle does not identify an initialized entry.
Handle :: struct {
    slot: u16,
    generation: u16,
}

// Store-owned text bytes and their replacement policy.
//
// count selects the initialized byte prefix. required means later eviction
// makes evidence loss sticky; truncated describes this entry's original copy.
Entry :: struct {
    // Inline copied bytes and initialized prefix length.
    bytes: [TEXT_ENTRY_CAPACITY]u8,
    count: u16,

    // Handle validation and slot occupancy.
    generation: u16,
    occupied: bool,

    // Eviction criticality and insertion completeness.
    required: bool,
    truncated: bool,
}

// Fixed circular text store with sticky required-evidence loss.
//
// next_slot identifies the next entry to replace. required_evidence_lost stays
// true after any required entry is replaced and clears only when the store is reset.
Store :: struct {
    // Inline entry storage and circular insertion position.
    entries: [TEXT_STORE_CAPACITY]Entry,
    next_slot: int,

    // Sticky indication that required text is no longer resident.
    required_evidence_lost: bool,
}

//   Copy text into the next bounded slot and return its generational handle.
//
// Parameters:
//   - store: Destination store that owns the copied byte prefix.
//   - value: Borrowed source bytes to copy without retaining source storage.
//   - required: Whether later eviction must mark evidence incomplete.
//
// Returns:
//   - A handle valid until its slot is reused and true when all bytes fit.
//   - The zero handle and false for a nil store.
//
// Side effects:
//   - Replaces the next slot, invalidates its prior handle, and advances insertion.
//   - Permanently marks required evidence lost when replacing a required entry.
//
// Notes:
//   - Oversized values retain the first TEXT_ENTRY_CAPACITY bytes and return false.
//   - Truncation is byte-based and does not preserve or validate encoding boundaries.
store_put :: proc(store: ^Store, value: string, required: bool) -> (Handle, bool) {
    if store == nil {
        return {}, false
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
        generation = generation,
        occupied = true,
        required = required,
        truncated = len(value) > TEXT_ENTRY_CAPACITY,
    }
    entry.count = u16(copy(entry.bytes[:], transmute([]u8)value))
    store.next_slot = (slot + 1) % TEXT_STORE_CAPACITY
    return {slot = u16(slot), generation = generation}, !entry.truncated
}

//   Resolve one current handle to borrowed immutable text.
//
// Parameters:
//   - store: Store that issued the handle.
//   - handle: Slot and generation pair to validate.
//
// Returns:
//   - A string borrowing the retained byte prefix and true for a current handle.
//   - An empty string and false for nil, invalid, empty, or stale storage.
//
// Notes:
//   - The string remains valid only until its slot is reused or the store dies.
//   - An empty retained value is distinguishable from failure through the boolean.
store_get :: proc(store: ^Store, handle: Handle) -> (string, bool) {
    if store == nil || int(handle.slot) >= len(store.entries) {
        return "", false
    }
    entry := &store.entries[handle.slot]
    if !entry.occupied || entry.generation != handle.generation {
        return "", false
    }
    return string(entry.bytes[:entry.count]), true
}
