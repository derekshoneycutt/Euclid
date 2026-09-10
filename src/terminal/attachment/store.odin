package termattachment

import "core:mem"

// Immutable owned bytes and metadata for one admitted attachment generation.
Attachment_Entry :: struct {
    // Reusable slot lifecycle checked by every attachment handle lookup.
    generation: u64,
    active: bool,

    // Immutable payload identity, owned bytes, and raster row layout.
    metadata: Attachment_Metadata,
    payload: []u8,
    payload_format: Raster_Format,
    payload_stride: int,
    animation_frames: []Animation_Frame,
    animation_timeline: Animation_Timeline,
    cpu_byte_count: int,
    animation_decode_byte_count: int,
    prepared: bool,
    removal_requested: bool,

    // Independent reasons that prevent payload removal or eviction.
    placement_reference_count: int,
    pin_count: int,
    protocol_retained: bool,

    // Owner sequence used for deterministic least-recently-used eviction.
    last_used: u64,
}

// One terminal-owned placement and its reusable generation.
Placement_Entry :: struct {
    generation: u64,
    active: bool,
    metadata: Placement_Metadata,
}

// Mutable bounded transfer storage that has not become an immutable payload.
Transfer_Entry :: struct {
    generation: u64,
    active: bool,
    origin: Protocol_Origin,
    bytes: []u8,
    count: int,
}

// GPU byte accounting for an attachment whose native resource lives elsewhere.
Residency_Entry :: struct {
    attachment_id: Attachment_Id,
    byte_count: int,
    resident: bool,
    last_used: u64,
}

// Cumulative content-free outcomes for one registry lifetime.
Store_Diagnostics :: struct {
    // Attachment admission and CPU payload eviction outcomes.
    attachment_admission_count: u64,
    attachment_rejection_count: u64,
    attachment_eviction_count: u64,
    animation_admission_count: u64,
    animation_rejection_count: u64,

    // Placement and transfer admission outcomes.
    placement_admission_count: u64,
    placement_rejection_count: u64,
    transfer_admission_count: u64,
    transfer_rejection_count: u64,

    // Invalid capability use and released residency totals.
    stale_handle_count: u64,
    cpu_evicted_bytes: u64,
    gpu_evicted_bytes: u64,
}

// Fixed-occupancy terminal attachment registry with explicit byte ownership.
Store :: struct {
    // Fixed tables and recyclable payloads retain distinct lifetime allocators.
    table_allocator: mem.Allocator,
    payload_allocator: mem.Allocator,
    limits: Limits,

    // Fixed entry tables allocated once and never resized.
    attachments: []Attachment_Entry,
    placements: []Placement_Entry,
    transfers: []Transfer_Entry,
    residency: []Residency_Entry,

    // Current occupancy and aggregate resource accounting.
    attachment_count: int,
    placement_count: int,
    transfer_count: int,
    animated_attachment_count: int,
    cpu_byte_count: int,
    gpu_byte_count: int,
    animation_decode_byte_count: int,

    // Deterministic recency clock and cumulative content-free diagnostics.
    sequence: u64,
    diagnostics: Store_Diagnostics,
}

// Result of reserving GPU residency, including an optional eviction candidate.
Residency_Admission :: struct {
    outcome: Admission_Outcome,
    eviction_count: int,
}

// Reusable exact placement-table snapshot that pins every captured payload.
Placement_Checkpoint :: struct {
    // Store and allocator borrowed or retained for the checkpoint lifetime.
    store: ^Store,
    allocator: mem.Allocator,

    // Fixed mirrors allocated once from the store's configured capacities.
    placements: []Placement_Entry,
    pinned_attachments: []Attachment_Id,

    // Captured occupancy and number of attachment pins currently owned.
    placement_count: int,
    pin_count: int,
    valid: bool,
}

//   Destroy one display-owned native resource before releasing its residency entry.
//
// Parameters:
//   - user_data: Opaque display-owner state borrowed for this callback.
//   - attachment_id: Live attachment whose native resource must be destroyed.
//
// Returns:
//   - True only after the native resource is no longer usable; false preserves
//     registry accounting and rejects the requesting admission.
//
// Side effects:
//   - May destroy display-owned native resources outside this package.
Residency_Evict_Handler :: #type proc(
    user_data: rawptr, attachment_id: Attachment_Id) -> bool

//   Report whether all configured occupancy and resource limits are usable.
//
// Parameters:
//   - limits: Candidate store policy. Every field must be positive.
//
// Returns:
//   - True when fixed tables can be allocated and every admission limit is
//     nonzero; false otherwise.
limits_valid :: proc(limits: Limits) -> bool {
    return limits.attachment_capacity > 0 &&
        limits.placement_capacity > 0 && limits.transfer_capacity > 0 &&
        limits.transfer_byte_limit > 0 && limits.dimension_limit > 0 &&
        limits.image_pixel_limit > 0 && limits.cpu_byte_limit > 0 &&
        limits.gpu_byte_limit > 0 && limits.animated_attachment_limit > 0 &&
        limits.animation_frame_limit > 0 &&
        limits.animation_decode_byte_limit > 0 &&
        limits.animation_min_frame_duration_ns > 0 &&
        limits.animation_max_frame_duration_ns >=
            limits.animation_min_frame_duration_ns &&
        limits.animation_duration_ns_limit > 0
}

// Return the next nonzero generation for one reusable store slot.
store_next_generation :: proc(generation: u64) -> u64 {
    next := generation + 1
    return next if next != 0 else 1
}

// Allocate fixed store tables transactionally into an initialized candidate.
store_allocate_tables :: proc(
    candidate: ^Store, limits: Limits, table_allocator: mem.Allocator) -> bool {
    attachments, attachment_error := make(
        []Attachment_Entry, limits.attachment_capacity, table_allocator)
    if attachment_error != nil { return false }
    candidate.attachments = attachments
    placements, placement_error := make(
        []Placement_Entry, limits.placement_capacity, table_allocator)
    if placement_error != nil { return false }
    candidate.placements = placements
    transfers, transfer_error := make(
        []Transfer_Entry, limits.transfer_capacity, table_allocator)
    if transfer_error != nil { return false }
    candidate.transfers = transfers
    residency, residency_error := make(
        []Residency_Entry, limits.attachment_capacity, table_allocator)
    if residency_error != nil { return false }
    candidate.residency = residency
    return true
}

//   Allocate every fixed entry table with distinct table and payload ownership.
//
// Parameters:
//   - store: Uninitialized destination that assumes ownership on success.
//   - limits: Positive fixed capacities and resource budgets retained by value.
//   - table_allocator: Session-stable allocator for fixed entry tables.
//   - payload_allocator: Free-capable allocator for payload and transfer bytes.
//
// Returns:
//   - True after all tables are allocated; false for invalid input or after
//     rolling back a partial allocation.
//
// Side effects:
//   - Allocates attachment, placement, transfer, and residency tables.
//
// Notes:
//   - The caller must keep both allocators valid until `store_destroy` completes.
store_init_with_allocators :: proc(
    store: ^Store, limits: Limits,
    table_allocator, payload_allocator: mem.Allocator) -> bool {
    if store == nil || len(store.attachments) != 0 || !limits_valid(limits) {
        return false
    }
    candidate := Store {
        table_allocator = table_allocator,
        payload_allocator = payload_allocator,
        limits = limits,
    }
    if !store_allocate_tables(&candidate, limits, table_allocator) {
        store_destroy(&candidate)
        return false
    }
    store^ = candidate
    return true
}

//   Allocate one registry with a shared free-capable allocator.
//
// Parameters:
//   - store: Uninitialized destination that assumes ownership on success.
//   - limits: Positive fixed capacities and resource budgets retained by value.
//   - allocator: Allocator retained for every owned allocation.
//
// Returns:
//   - True after all tables are allocated; false after transactional rollback.
//
// Notes:
//   - This compatibility form preserves standalone and test ownership behavior.
store_init :: proc(
    store: ^Store, limits: Limits, allocator: mem.Allocator) -> bool {
    return store_init_with_allocators(store, limits, allocator, allocator)
}

//   Release all owned payload, transfer, and fixed table allocations.
//
// Parameters:
//   - store: Registry to destroy; nil is accepted as a no-op.
//
// Side effects:
//   - Frees active payload and transfer buffers, frees every fixed table, and
//     resets the registry to its zero value.
//
// Notes:
//   - Native GPU resources are not owned here and must be destroyed before this
//     procedure by the display owner.
store_destroy :: proc(store: ^Store) {
    if store == nil {
        return
    }
    for &entry in store.attachments {
        delete(entry.animation_frames, store.payload_allocator)
        delete(entry.payload, store.payload_allocator)
    }
    for &entry in store.transfers {
        delete(entry.bytes, store.payload_allocator)
    }
    delete(store.residency, store.table_allocator)
    delete(store.transfers, store.table_allocator)
    delete(store.placements, store.table_allocator)
    delete(store.attachments, store.table_allocator)
    store^ = {}
}

//   Advance the owner sequence used for deterministic oldest-first eviction.
//
// Parameters:
//   - store: Initialized registry whose owner-thread clock is updated.
//
// Returns:
//   - A nonzero sequence value newer than every value previously issued by the
//     current registry lifetime.
//
// Side effects:
//   - Mutates `store.sequence`; wraparound skips zero.
store_next_sequence :: proc(store: ^Store) -> u64 {
    store.sequence += 1
    if store.sequence == 0 {
        store.sequence = 1
    }
    return store.sequence
}

//   Resolve one attachment capability against its reusable slot generation.
//
// Parameters:
//   - store: Registry containing the attachment table; nil is treated as stale.
//   - id: Attachment slot and generation to validate.
//
// Returns:
//   - The mutable owner entry and `.Found`, or nil and `.Stale`.
//
// Side effects:
//   - Increments stale-handle diagnostics when a non-nil store rejects `id`.
//
// Notes:
//   - The returned pointer is invalidated by removal, eviction, or store
//     destruction and must not cross owner mutations.
attachment_entry :: proc(
    store: ^Store, id: Attachment_Id) -> (^Attachment_Entry, Handle_Outcome) {
    if store == nil || id.slot < 0 || id.slot >= len(store.attachments) {
        if store != nil {
            store.diagnostics.stale_handle_count += 1
        }
        return nil, .Stale
    }
    entry := &store.attachments[id.slot]
    if !entry.active || entry.generation != id.generation {
        store.diagnostics.stale_handle_count += 1
        return nil, .Stale
    }
    return entry, .Found
}

//   Resolve one placement capability against its reusable slot generation.
//
// Parameters:
//   - store: Registry containing the placement table; nil is treated as stale.
//   - id: Placement slot and generation to validate.
//
// Returns:
//   - The mutable owner entry and `.Found`, or nil and `.Stale`.
//
// Side effects:
//   - Increments stale-handle diagnostics when a non-nil store rejects `id`.
placement_entry :: proc(
    store: ^Store, id: Placement_Id) -> (^Placement_Entry, Handle_Outcome) {
    if store == nil || id.slot < 0 || id.slot >= len(store.placements) {
        if store != nil {
            store.diagnostics.stale_handle_count += 1
        }
        return nil, .Stale
    }
    entry := &store.placements[id.slot]
    if !entry.active || entry.generation != id.generation {
        store.diagnostics.stale_handle_count += 1
        return nil, .Stale
    }
    return entry, .Found
}

//   Resolve one transfer capability against its reusable slot generation.
//
// Parameters:
//   - store: Registry containing the transfer table; nil is treated as stale.
//   - id: Transfer slot and generation to validate.
//
// Returns:
//   - The mutable owner entry and `.Found`, or nil and `.Stale`.
//
// Side effects:
//   - Increments stale-handle diagnostics when a non-nil store rejects `id`.
transfer_entry :: proc(
    store: ^Store, id: Transfer_Id) -> (^Transfer_Entry, Handle_Outcome) {
    if store == nil || id.slot < 0 || id.slot >= len(store.transfers) {
        if store != nil {
            store.diagnostics.stale_handle_count += 1
        }
        return nil, .Stale
    }
    entry := &store.transfers[id.slot]
    if !entry.active || entry.generation != id.generation {
        store.diagnostics.stale_handle_count += 1
        return nil, .Stale
    }
    return entry, .Found
}

//   Validate attachment dimensions and raster storage before allocation.
//
// Parameters:
//   - store: Initialized registry supplying pixel and byte limits.
//   - metadata: Intrinsic dimensions and bounded fallback metadata to validate.
//   - payload_byte_count: Total source bytes requested for the immutable copy.
//   - payload_stride: Number of source bytes occupied by each raster row.
//   - payload_format: Raster format determining bytes required per pixel.
//
// Returns:
//   - `.Admitted` when the input is internally consistent and within policy;
//     otherwise the most specific invalid, byte-limit, or pixel-limit result.
//
// Notes:
//   - This procedure performs no allocation and does not reserve store capacity.
attachment_admission_valid :: proc(
    store: ^Store, metadata: Attachment_Metadata,
    payload_byte_count, payload_stride: int,
    payload_format: Raster_Format) -> Admission_Outcome {
    width := metadata.metrics.width
    height := metadata.metrics.height
    if width <= 0 || height <= 0 || payload_byte_count <= 0 ||
        payload_stride <= 0 || len(metadata.fallback.bytes) < metadata.fallback.count ||
        metadata.fallback.count < 0 {
        return .Invalid
    }
    if width > store.limits.dimension_limit ||
        height > store.limits.dimension_limit ||
        width > store.limits.image_pixel_limit / height {
        return .Pixel_Limit_Exceeded
    }
    if payload_byte_count > store.limits.cpu_byte_limit {
        return .Byte_Limit_Exceeded
    }
    bytes_per_pixel := 1
    if payload_format == .Rgb8 { bytes_per_pixel = 3 }
    if payload_format == .Rgba8 { bytes_per_pixel = 4 }
    if payload_stride < width * bytes_per_pixel ||
        payload_byte_count < payload_stride * height {
        return .Invalid
    }
    return .Admitted
}

//   Find the oldest attachment whose CPU payload may be evicted.
//
// Parameters:
//   - store: Initialized registry searched in stable slot order.
//
// Returns:
//   - The selected slot, or -1 when every active attachment is retained by
//     protocol identity, placement, pin, or GPU residency.
attachment_eviction_candidate :: proc(store: ^Store) -> int {
    candidate := -1
    oldest := max(u64)
    for &entry, index in store.attachments {
        if !entry.active || entry.protocol_retained ||
            entry.placement_reference_count > 0 || entry.pin_count > 0 ||
            residency_entry(store, {slot = index, generation = entry.generation}) != nil {
            continue
        }
        if entry.last_used < oldest {
            candidate = index
            oldest = entry.last_used
        }
    }
    return candidate
}

//   Release one known-active attachment slot while preserving its generation.
//
// Parameters:
//   - store: Registry owning the payload and aggregate counters.
//   - slot: Valid active attachment slot selected by the caller.
//   - evicted: Whether to record this removal as quota-driven eviction.
//
// Side effects:
//   - Frees payload bytes, clears the entry except for its generation, decrements
//     occupancy and CPU bytes, and updates eviction diagnostics when requested.
//
// Notes:
//   - Callers must first prove that no placement, pin, protocol identity, or GPU
//     residency retains the attachment.
attachment_entry_remove :: proc(store: ^Store, slot: int, evicted: bool) {
    entry := &store.attachments[slot]
    store.cpu_byte_count -= entry.cpu_byte_count
    store.animation_decode_byte_count -= entry.animation_decode_byte_count
    if len(entry.animation_frames) > 0 {
        store.animated_attachment_count -= 1
    }
    if evicted {
        store.diagnostics.attachment_eviction_count += 1
        store.diagnostics.cpu_evicted_bytes += u64(entry.cpu_byte_count)
    }
    delete(entry.animation_frames, store.payload_allocator)
    delete(entry.payload, store.payload_allocator)
    generation := entry.generation
    entry^ = {generation = generation}
    store.attachment_count -= 1
}

//   Evict one oldest attachment not retained by any ownership mechanism.
//
// Parameters:
//   - store: Registry from which an eligible CPU payload is removed.
//
// Returns:
//   - The invalidated attachment identity and true, or zero identity and false
//     when no entry is eligible.
//
// Side effects:
//   - Releases payload storage and updates occupancy, byte, and eviction totals.
attachment_evict_one :: proc(store: ^Store) -> (Attachment_Id, bool) {
    if store == nil {
        return {}, false
    }
    slot := attachment_eviction_candidate(store)
    if slot < 0 {
        return {}, false
    }
    id := Attachment_Id{slot = slot, generation = store.attachments[slot].generation}
    attachment_entry_remove(store, slot, true)
    return id, true
}

//   Make CPU-budget room and return an inactive attachment slot.
//
// Parameters:
//   - store: Registry whose CPU quota and fixed table govern admission.
//   - payload_byte_count: Validated bytes required by the pending payload copy.
//
// Returns:
//   - An inactive slot and `.Admitted`, or -1 with the capacity outcome that
//     prevented admission.
//
// Side effects:
//   - May evict one or more oldest eligible attachments.
attachment_slot_acquire :: proc(
    store: ^Store, payload_byte_count: int) -> (int, Admission_Outcome) {
    for store.cpu_byte_count + payload_byte_count > store.limits.cpu_byte_limit {
        _, evicted := attachment_evict_one(store)
        if !evicted {
            return -1, .No_Evictable_Entry
        }
    }
    for &entry, index in store.attachments {
        if !entry.active {
            return index, .Admitted
        }
    }
    _, evicted := attachment_evict_one(store)
    if !evicted {
        return -1, .No_Evictable_Entry
    }
    for &entry, index in store.attachments {
        if !entry.active {
            return index, .Admitted
        }
    }
    return -1, .Capacity_Exceeded
}

// Commit one fully allocated attachment entry into its acquired reusable slot.
attachment_entry_commit :: proc(
    store: ^Store, slot: int, candidate: Attachment_Entry) -> Attachment_Id {
    entry := &store.attachments[slot]
    committed := candidate
    committed.generation = store_next_generation(entry.generation)
    committed.active = true
    committed.last_used = store_next_sequence(store)
    entry^ = committed
    store.attachment_count += 1
    store.cpu_byte_count += candidate.cpu_byte_count
    store.animation_decode_byte_count += candidate.animation_decode_byte_count
    if len(candidate.animation_frames) > 0 {
        store.animated_attachment_count += 1
    }
    store.diagnostics.attachment_admission_count += 1
    return {slot = slot, generation = committed.generation}
}

//   Validate and copy one immutable raster into a reusable attachment slot.
//
// Parameters:
//   - store: Initialized registry that assumes ownership of the copied payload.
//   - admission: Metadata, borrowed source bytes, raster layout, and initial
//     protocol-retention policy.
//
// Returns:
//   - A live generational identity and `.Admitted`, or a zero identity with the
//     reason validation, capacity, quota, or allocation failed.
//
// Side effects:
//   - May evict eligible payloads, allocates an exact immutable copy, advances
//     recency, and updates occupancy and admission diagnostics.
//
// Notes:
//   - `admission.payload` remains caller-owned and is borrowed only for this call.
attachment_admit :: proc(
    store: ^Store, admission: Attachment_Admission) ->
    (Attachment_Id, Admission_Outcome) {
    if store == nil {
        return {}, .Invalid
    }
    validation := attachment_admission_valid(
        store, admission.metadata, len(admission.payload),
        admission.payload_stride, admission.payload_format)
    if validation != .Admitted {
        store.diagnostics.attachment_rejection_count += 1
        return {}, validation
    }
    slot, slot_outcome := attachment_slot_acquire(store, len(admission.payload))
    if slot_outcome != .Admitted {
        store.diagnostics.attachment_rejection_count += 1
        return {}, slot_outcome
    }
    // Session-recyclable storage is released after removal, stale completion,
    // eviction, or destruction.
    owned, allocation_error := make(
        []u8, len(admission.payload), store.payload_allocator)
    if allocation_error != nil {
        store.diagnostics.attachment_rejection_count += 1
        return {}, .Allocation_Failed
    }
    copy(owned, admission.payload)
    id := attachment_entry_commit(store, slot, {
        metadata = admission.metadata,
        payload = owned,
        payload_format = admission.payload_format,
        payload_stride = admission.payload_stride,
        cpu_byte_count = len(owned),
        prepared = true,
        protocol_retained = admission.protocol_retained,
    })
    return id, .Admitted
}

//   Reserve one immutable attachment generation and exact worker output buffer.
//
// Parameters:
//   - store: Initialized registry that owns the reserved output storage.
//   - reservation: Validated metadata, exact byte count, raster layout, and protocol
//     retention policy.
//
// Returns:
//   - A pinned pending generation and `.Admitted`, or zero identity with the validation,
//     capacity, quota, or allocation failure.
//
// Side effects:
//   - May evict eligible attachments, allocates exact zeroed output storage, charges CPU
//     occupancy, and acquires one preparation pin released only by publish or release.
attachment_reserve :: proc(
    store: ^Store, reservation: Attachment_Reservation) ->
    (Attachment_Id, Admission_Outcome) {
    if store == nil { return {}, .Invalid }
    validation := attachment_admission_valid(
        store, reservation.metadata, reservation.payload_byte_count,
        reservation.payload_stride, reservation.payload_format)
    if validation != .Admitted {
        store.diagnostics.attachment_rejection_count += 1
        return {}, validation
    }
    slot, slot_outcome := attachment_slot_acquire(
        store, reservation.payload_byte_count)
    if slot_outcome != .Admitted {
        store.diagnostics.attachment_rejection_count += 1
        return {}, slot_outcome
    }
    // Session-recyclable storage is released after publication removal, stale
    // completion, eviction, or destruction.
    payload, allocation_error := make(
        []u8, reservation.payload_byte_count, store.payload_allocator)
    if allocation_error != nil {
        store.diagnostics.attachment_rejection_count += 1
        return {}, .Allocation_Failed
    }
    id := attachment_entry_commit(store, slot, {
        metadata = reservation.metadata,
        payload = payload,
        payload_format = reservation.payload_format,
        payload_stride = reservation.payload_stride,
        cpu_byte_count = len(payload),
        pin_count = 1,
        protocol_retained = reservation.protocol_retained,
    })
    return id, .Admitted
}

//   Borrow the exclusive mutable output buffer of one pending preparation generation.
//
// Parameters:
//   - store: Registry owning the pending attachment.
//   - id: Exact generation reserved for asynchronous preparation.
//
// Returns:
//   - Mutable exact-sized bytes and true only while the generation remains pending,
//     pinned, and not logically removed.
//
// Notes:
//   - From task submission through join, the worker exclusively owns the returned bytes;
//     the display owner must not resolve or mutate them concurrently.
attachment_preparation_buffer :: proc(
    store: ^Store, id: Attachment_Id) -> ([]u8, bool) {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || entry.prepared || entry.removal_requested ||
        entry.pin_count <= 0 || len(entry.animation_frames) > 0 {
        return nil, false
    }
    return entry.payload, true
}

//   Publish one joined preparation result as the generation's immutable payload.
//
// Parameters:
//   - store: Registry owning the pending output storage and preparation pin.
//   - id: Exact generation whose worker has completed and been joined.
//
// Returns:
//   - `.Found` after atomic publication, or `.Stale` for a replaced, removed, already
//     published, or otherwise invalid preparation generation.
//
// Side effects:
//   - Marks the payload readable, releases one preparation pin, and advances recency.
attachment_preparation_publish :: proc(
    store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || entry.prepared || entry.removal_requested ||
        entry.pin_count <= 0 || len(entry.animation_frames) > 0 {
        return .Stale
    }
    entry.prepared = true
    entry.pin_count -= 1
    entry.last_used = store_next_sequence(store)
    return .Found
}

//   Release one joined or unsubmitted preparation without publishing its bytes.
//
// Parameters:
//   - store: Registry owning the pending generation.
//   - id: Exact pending generation whose exclusive preparation ownership ended.
//
// Returns:
//   - `.Found` after releasing its preparation pin, or `.Stale` for invalid state.
attachment_preparation_release :: proc(
    store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || entry.prepared || entry.pin_count <= 0 {
        return .Stale
    }
    store.animation_decode_byte_count -= entry.animation_decode_byte_count
    entry.animation_decode_byte_count = 0
    entry.pin_count -= 1
    entry.last_used = store_next_sequence(store)
    return .Found
}

//   Report whether one live generation awaits owner-side native-resource teardown.
//
// Returns:
//   - True only for an exact live generation with a recorded removal request.
attachment_removal_requested :: proc(store: ^Store, id: Attachment_Id) -> bool {
    entry, outcome := attachment_entry(store, id)
    return outcome == .Found && entry.removal_requested
}

//   Return the prepared live attachment generation occupying one bounded table slot.
//
// Returns:
//   - The exact generation and true when the slot is prepared and not pending removal.
//   - A zero handle and false for an invalid, inactive, pending, or removed slot.
//
// Notes:
//   - This query does not update recency and is intended for bounded owner-side scans.
attachment_prepared_id_at :: proc(
    store: ^Store, slot: int) -> (Attachment_Id, bool) {
    if store == nil || slot < 0 || slot >= len(store.attachments) {
        return {}, false
    }
    entry := &store.attachments[slot]
    if !entry.active || !entry.prepared || entry.removal_requested {
        return {}, false
    }
    return {slot = slot, generation = entry.generation}, true
}

//   Borrow one immutable payload and mark its attachment recently used.
//
// Parameters:
//   - store: Registry owning the requested payload.
//   - id: Live attachment capability to resolve.
//
// Returns:
//   - A borrowed payload view and true, or a zero view and false for stale `id`.
//
// Side effects:
//   - Advances the owner sequence and updates the entry's LRU position.
//
// Notes:
//   - The byte slice must not be retained across removal, eviction, or store
//     destruction and must never be mutated by the borrower.
attachment_payload :: proc(
    store: ^Store, id: Attachment_Id) -> (Payload_View, bool) {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return {}, false
    }
    if !entry.prepared || len(entry.animation_frames) > 0 {
        return {}, false
    }
    entry.last_used = store_next_sequence(store)
    return {
        bytes = entry.payload,
        format = entry.payload_format,
        stride = entry.payload_stride,
    }, true
}

//   Borrow immutable intrinsic metrics for one live attachment generation.
//
// Returns:
//   - Copied metrics and true, or zero metrics and false for a stale generation.
attachment_metrics :: proc(
    store: ^Store, id: Attachment_Id) -> (Intrinsic_Metrics, bool) {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared { return {}, false }
    return entry.metadata.metrics, true
}

//   Change whether protocol identity retains an attachment without placements.
//
// Parameters:
//   - store: Registry owning the attachment.
//   - id: Live attachment capability to update.
//   - retained: True while protocol lookup must preserve the attachment.
//
// Returns:
//   - `.Found` after updating the entry, or `.Stale` for an invalid generation.
//
// Side effects:
//   - Mutates protocol retention, advances recency, and may increment stale-handle
//     diagnostics through lookup.
attachment_set_protocol_retained :: proc(
    store: ^Store, id: Attachment_Id, retained: bool) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    entry.protocol_retained = retained
    entry.last_used = store_next_sequence(store)
    return .Found
}

//   Add one attachment pin for checkpoint or asynchronous preparation ownership.
//
// Parameters:
//   - store: Registry owning the attachment and pin count.
//   - id: Live attachment capability to pin.
//
// Returns:
//   - `.Found` after incrementing the pin, or `.Stale` for an invalid generation.
//
// Side effects:
//   - Increments the pin count and advances attachment recency.
//
// Notes:
//   - Every successful call requires one matching `attachment_unpin`.
attachment_pin :: proc(store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    entry.pin_count += 1
    entry.last_used = store_next_sequence(store)
    return .Found
}

//   Release one attachment pin without permitting counter underflow.
//
// Parameters:
//   - store: Registry owning the attachment and pin count.
//   - id: Live attachment capability whose pin is released.
//
// Returns:
//   - `.Found` after decrementing a positive pin count; `.Stale` when the handle
//     is invalid or no matching pin exists.
//
// Side effects:
//   - Decrements the pin count and advances recency after a valid release.
attachment_unpin :: proc(store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    if entry.pin_count <= 0 {
        return .Stale
    }
    entry.pin_count -= 1
    entry.last_used = store_next_sequence(store)
    return .Found
}

//   Remove one attachment after every retaining owner has released it.
//
// Parameters:
//   - store: Registry owning the attachment payload.
//   - id: Live attachment capability requested for removal.
//
// Returns:
//   - `.Found` after removal; `.Stale` when the handle is invalid or the entry is
//     still retained by protocol identity, placement references, or pins.
//
// Side effects:
//   - Frees payload storage and decrements attachment and CPU-byte occupancy.
attachment_remove :: proc(store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    if entry.protocol_retained || entry.placement_reference_count > 0 {
        return .Stale
    }
    if residency_entry(store, id) != nil {
        entry.removal_requested = true
        return .Stale
    }
    if entry.pin_count > 0 {
        if !entry.prepared { entry.removal_requested = true }
        return .Stale
    }
    attachment_entry_remove(store, id.slot, false)
    return .Found
}

// Return the first inactive placement slot, or negative one when the table is full.
placement_available_slot :: proc(store: ^Store) -> int {
    for &entry, index in store.placements {
        if !entry.active { return index }
    }
    return -1
}

//   Admit one placement and retain its referenced attachment generation.
//
// Parameters:
//   - store: Initialized registry owning both placement and attachment tables.
//   - metadata: Attachment identity, terminal geometry, and lifecycle policy to
//     copy into the new placement.
//
// Returns:
//   - A live placement identity and `.Admitted`; otherwise a zero identity with
//     `.Invalid` or `.Capacity_Exceeded`.
//
// Side effects:
//   - Allocates no memory; occupies one fixed slot, increments the attachment's
//     placement reference, advances recency, and updates admission diagnostics.
placement_admit :: proc(
    store: ^Store, metadata: Placement_Metadata) ->
    (Placement_Id, Admission_Outcome) {
    if store == nil || metadata.geometry.column < 0 ||
        metadata.geometry.column_span < 0 || metadata.geometry.row_span < 0 ||
        metadata.geometry.pixel_width < 0 || metadata.geometry.pixel_height < 0 {
        if store != nil {
            store.diagnostics.placement_rejection_count += 1
        }
        return {}, .Invalid
    }
    attachment, attachment_outcome := attachment_entry(
        store, metadata.attachment_id)
    if attachment_outcome != .Found {
        store.diagnostics.placement_rejection_count += 1
        return {}, .Invalid
    }
    slot := placement_available_slot(store)
    if slot < 0 {
        store.diagnostics.placement_rejection_count += 1
        return {}, .Capacity_Exceeded
    }
    entry := &store.placements[slot]
    generation := store_next_generation(entry.generation)
    entry^ = {generation = generation, active = true, metadata = metadata}
    attachment.placement_reference_count += 1
    attachment.last_used = store_next_sequence(store)
    store.placement_count += 1
    store.diagnostics.placement_admission_count += 1
    return {slot = slot, generation = generation}, .Admitted
}

//   Borrow immutable placement metadata for one live generation.
//
// Parameters:
//   - store: Registry owning the placement table.
//   - id: Placement slot and generation to resolve.
//
// Returns:
//   - A copied metadata value and true, or a zero value and false for stale `id`.
//
// Side effects:
//   - May increment stale-handle diagnostics through placement lookup.
placement_metadata :: proc(
    store: ^Store, id: Placement_Id) -> (Placement_Metadata, bool) {
    entry, outcome := placement_entry(store, id)
    if outcome != .Found {
        return {}, false
    }
    return entry.metadata, true
}

//   Copy live placements for one screen into caller-owned frame storage.
//
// Parameters:
//   - store: Registry owning authoritative placement state.
//   - screen: Screen identity whose placements are currently presented.
//   - output: Fixed caller-owned destination bounding copied occupancy.
//
// Returns:
//   - Number copied, sorted by ascending z-index and stable placement-slot order.
//
// Notes:
//   - Returns zero rather than a partial snapshot when `output` cannot hold every match.
placements_collect :: proc(
    store: ^Store, screen: Screen_Identity,
    output: []Placement_Metadata) -> int {
    if store == nil { return 0 }
    required := 0
    for &entry in store.placements {
        if entry.active && entry.metadata.geometry.screen == screen { required += 1 }
    }
    if required > len(output) { return 0 }
    count := 0
    for &entry in store.placements {
        if !entry.active || entry.metadata.geometry.screen != screen { continue }
        insertion := count
        for insertion > 0 &&
            output[insertion - 1].geometry.z_index > entry.metadata.geometry.z_index {
            output[insertion] = output[insertion - 1]
            insertion -= 1
        }
        output[insertion] = entry.metadata
        count += 1
    }
    return count
}

//   Copy captured placements for one screen into caller-owned frame storage.
//
// Returns:
//   - Number copied in ascending z-index and stable captured-slot order, or zero when
//     the checkpoint is invalid or the destination cannot hold every match.
placement_checkpoint_collect :: proc(
    checkpoint: ^Placement_Checkpoint, screen: Screen_Identity,
    output: []Placement_Metadata) -> int {
    if checkpoint == nil || !checkpoint.valid { return 0 }
    required := 0
    for &entry in checkpoint.placements {
        if entry.active && entry.metadata.geometry.screen == screen { required += 1 }
    }
    if required > len(output) { return 0 }
    count := 0
    for &entry in checkpoint.placements {
        if !entry.active || entry.metadata.geometry.screen != screen { continue }
        insertion := count
        for insertion > 0 &&
            output[insertion - 1].geometry.z_index > entry.metadata.geometry.z_index {
            output[insertion] = output[insertion - 1]
            insertion -= 1
        }
        output[insertion] = entry.metadata
        count += 1
    }
    return count
}

//   Remove one placement and release its attachment reference.
//
// Parameters:
//   - store: Registry owning the placement and referenced attachment.
//   - id: Live placement capability to remove.
//
// Returns:
//   - `.Found` after removal, or `.Stale` when the placement generation is no
//     longer live.
//
// Side effects:
//   - Clears the placement while preserving its generation, decrements placement
//     occupancy and the attachment reference count, and advances attachment
//     recency when the referenced attachment remains live.
placement_remove :: proc(store: ^Store, id: Placement_Id) -> Handle_Outcome {
    entry, outcome := placement_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    attachment, attachment_outcome := attachment_entry(
        store, entry.metadata.attachment_id)
    if attachment_outcome == .Found && attachment.placement_reference_count > 0 {
        attachment.placement_reference_count -= 1
        attachment.last_used = store_next_sequence(store)
    }
    generation := entry.generation
    entry^ = {generation = generation}
    store.placement_count -= 1
    return .Found
}

// Remove every placement referencing one exact attachment generation.
//
// Returns:
//   - Number of live placements removed from the fixed table.
//
// Side effects:
//   - Releases every matching placement reference without removing the payload.
placements_remove_attachment :: proc(
    store: ^Store, attachment_id: Attachment_Id) -> int {
    if store == nil {
        return 0
    }
    removed := 0
    for &entry, slot in store.placements {
        if !entry.active || entry.metadata.attachment_id != attachment_id {
            continue
        }
        id := Placement_Id{slot = slot, generation = entry.generation}
        if placement_remove(store, id) == .Found {
            removed += 1
        }
    }
    return removed
}

//   Remove every placement anchored to one logical row on one screen.
//
// Parameters:
//   - store: Registry owning the placement and attachment references.
//   - screen: Primary or alternate screen containing the logical row.
//   - logical_row: Nonzero stable row identity being discarded.
//
// Returns:
//   - Number of live placements removed from the fixed table.
//
// Side effects:
//   - Releases one attachment reference for each removed placement.
placements_remove_row :: proc(
    store: ^Store, screen: Screen_Identity, logical_row: i64) -> int {
    if store == nil || logical_row == 0 {
        return 0
    }
    removed := 0
    for &entry, slot in store.placements {
        if !entry.active || entry.metadata.geometry.screen != screen ||
            entry.metadata.geometry.logical_row != logical_row {
            continue
        }
        id := Placement_Id{slot = slot, generation = entry.generation}
        if placement_remove(store, id) == .Found {
            removed += 1
        }
    }
    return removed
}

//   Remove every placement owned by one terminal screen.
//
// Parameters:
//   - store: Registry owning the placement and attachment references.
//   - screen: Screen whose complete placement namespace is cleared.
//
// Returns:
//   - Number of live placements removed from the fixed table.
//
// Side effects:
//   - Releases one attachment reference for each removed placement.
placements_remove_screen :: proc(store: ^Store, screen: Screen_Identity) -> int {
    if store == nil {
        return 0
    }
    removed := 0
    for &entry, slot in store.placements {
        if !entry.active || entry.metadata.geometry.screen != screen {
            continue
        }
        id := Placement_Id{slot = slot, generation = entry.generation}
        if placement_remove(store, id) == .Found {
            removed += 1
        }
    }
    return removed
}

// Remove placements anchored at one exact screen, logical row, and column.
placements_remove_position :: proc(
    store: ^Store, screen: Screen_Identity,
    logical_row: i64, column: int) -> int {
    if store == nil { return 0 }
    removed := 0
    for &entry, slot in store.placements {
        geometry := entry.metadata.geometry
        if !entry.active || geometry.screen != screen ||
            geometry.logical_row != logical_row || geometry.column != column {
            continue
        }
        if placement_remove(store, {slot = slot, generation = entry.generation}) ==
            .Found {
            removed += 1
        }
    }
    return removed
}

// Remove resident placements of one protocol origin superseded at an exact position.
placements_remove_resident_position_origin_except :: proc(
    store: ^Store, target: Placement_Geometry, origin: Protocol_Origin,
    retained_attachment_id: Attachment_Id) -> int {
    if store == nil { return 0 }
    removed := 0
    for &entry, slot in store.placements {
        geometry := entry.metadata.geometry
        if !entry.active || geometry.screen != target.screen ||
            geometry.logical_row != target.logical_row ||
            geometry.column != target.column ||
            entry.metadata.attachment_id == retained_attachment_id {
            continue
        }
        attachment, outcome := attachment_entry(
            store, entry.metadata.attachment_id)
        if outcome != .Found || attachment.metadata.origin != origin ||
            residency_entry(store, entry.metadata.attachment_id) == nil {
            continue
        }
        attachment_id := entry.metadata.attachment_id
        if placement_remove(store, {slot = slot, generation = entry.generation}) ==
            .Found {
            attachment_remove(store, attachment_id)
            removed += 1
        }
    }
    return removed
}

// Remove placements anchored within one inclusive logical-row interval.
placements_remove_row_range :: proc(
    store: ^Store, screen: Screen_Identity,
    first_row, last_row: i64) -> int {
    if store == nil || first_row > last_row { return 0 }
    removed := 0
    for &entry, slot in store.placements {
        geometry := entry.metadata.geometry
        if !entry.active || geometry.screen != screen ||
            geometry.logical_row < first_row || geometry.logical_row > last_row {
            continue
        }
        if placement_remove(store, {slot = slot, generation = entry.generation}) ==
            .Found {
            removed += 1
        }
    }
    return removed
}

// Remove placements beginning at one terminal column on one screen.
placements_remove_column :: proc(
    store: ^Store, screen: Screen_Identity, column: int) -> int {
    if store == nil { return 0 }
    removed := 0
    for &entry, slot in store.placements {
        geometry := entry.metadata.geometry
        if !entry.active || geometry.screen != screen || geometry.column != column {
            continue
        }
        if placement_remove(store, {slot = slot, generation = entry.generation}) ==
            .Found {
            removed += 1
        }
    }
    return removed
}

// Remove placements with one exact z-index on one screen.
placements_remove_z_index :: proc(
    store: ^Store, screen: Screen_Identity, z_index: i32) -> int {
    if store == nil { return 0 }
    removed := 0
    for &entry, slot in store.placements {
        geometry := entry.metadata.geometry
        if !entry.active || geometry.screen != screen ||
            geometry.z_index != z_index {
            continue
        }
        if placement_remove(store, {slot = slot, generation = entry.generation}) ==
            .Found {
            removed += 1
        }
    }
    return removed
}

//   Release every attachment pin owned by one placement checkpoint.
//
// Parameters:
//   - checkpoint: Initialized checkpoint whose current capture is invalidated.
//
// Side effects:
//   - Releases captured pins and clears capture occupancy without freeing mirrors.
placement_checkpoint_clear :: proc(checkpoint: ^Placement_Checkpoint) {
    if checkpoint == nil || checkpoint.store == nil {
        return
    }
    for index in 0..<checkpoint.pin_count {
        attachment_unpin(checkpoint.store, checkpoint.pinned_attachments[index])
        checkpoint.pinned_attachments[index] = {}
    }
    checkpoint.placement_count = 0
    checkpoint.pin_count = 0
    checkpoint.valid = false
}

//   Allocate reusable mirrors for one store's complete placement table.
//
// Parameters:
//   - checkpoint: Zero-valued destination checkpoint.
//   - store: Registry borrowed for capture, restore, and pin ownership.
//   - allocator: Allocator retained until checkpoint destruction.
//
// Returns:
//   - True after both fixed mirrors are allocated, false after local rollback.
//
// Side effects:
//   - Allocates placement and attachment-identity arrays at placement capacity.
placement_checkpoint_init :: proc(
    checkpoint: ^Placement_Checkpoint, store: ^Store,
    allocator: mem.Allocator) -> bool {
    if checkpoint == nil || store == nil || len(checkpoint.placements) != 0 {
        return false
    }
    // Session-recyclable mirrors are released by placement_checkpoint_destroy.
    placements, placements_error := make(
        []Placement_Entry, len(store.placements), allocator)
    if placements_error != nil {
        return false
    }
    pins, pins_error := make(
        []Attachment_Id, len(store.placements), allocator)
    if pins_error != nil {
        delete(placements, allocator)
        return false
    }
    checkpoint^ = {
        store = store,
        allocator = allocator,
        placements = placements,
        pinned_attachments = pins,
    }
    return true
}

//   Release checkpoint pins and fixed mirror storage.
//
// Parameters:
//   - checkpoint: Checkpoint to destroy; nil is accepted as a no-op.
//
// Side effects:
//   - Unpins captured payloads, frees both mirrors, and resets the checkpoint.
placement_checkpoint_destroy :: proc(checkpoint: ^Placement_Checkpoint) {
    if checkpoint == nil {
        return
    }
    placement_checkpoint_clear(checkpoint)
    delete(checkpoint.pinned_attachments, checkpoint.allocator)
    delete(checkpoint.placements, checkpoint.allocator)
    checkpoint^ = {}
}

//   Capture the complete placement table and pin every referenced payload.
//
// Parameters:
//   - checkpoint: Initialized mirror bound to `store`.
//   - store: Registry whose exact placement generations are captured.
//
// Returns:
//   - True after a complete capture; false for incompatible state or pin failure.
//
// Side effects:
//   - Replaces a prior capture, copies the fixed table, and owns one attachment
//     pin per active placement until clear, recapture, restore lifetime, or destroy.
placement_checkpoint_capture :: proc(
    checkpoint: ^Placement_Checkpoint, store: ^Store) -> bool {
    if checkpoint == nil || checkpoint.store != store ||
        len(checkpoint.placements) != len(store.placements) {
        return false
    }
    placement_checkpoint_clear(checkpoint)
    copy(checkpoint.placements, store.placements)
    for &entry in checkpoint.placements {
        if !entry.active {
            continue
        }
        if attachment_pin(store, entry.metadata.attachment_id) != .Found {
            placement_checkpoint_clear(checkpoint)
            return false
        }
        checkpoint.pinned_attachments[checkpoint.pin_count] =
            entry.metadata.attachment_id
        checkpoint.pin_count += 1
    }
    checkpoint.placement_count = store.placement_count
    checkpoint.valid = true
    return true
}

//   Copy one valid placement capture into another checkpoint bound to the same store.
//
// Returns:
//   - True after independently pinning and copying the capture; false otherwise.
placement_checkpoint_copy :: proc(
    destination, source: ^Placement_Checkpoint) -> bool {
    if destination == nil || source == nil || !source.valid ||
        destination.store != source.store ||
        len(destination.placements) != len(source.placements) {
        return false
    }
    placement_checkpoint_clear(destination)
    copy(destination.placements, source.placements)
    for index in 0..<source.pin_count {
        id := source.pinned_attachments[index]
        if attachment_pin(destination.store, id) != .Found {
            placement_checkpoint_clear(destination)
            return false
        }
        destination.pinned_attachments[destination.pin_count] = id
        destination.pin_count += 1
    }
    destination.placement_count = source.placement_count
    destination.valid = true
    return true
}

// Relocate or deactivate captured placements for one screen without touching live state.
placement_checkpoint_relocate :: proc(
    checkpoint: ^Placement_Checkpoint, screen: Screen_Identity,
    user_data: rawptr, relocate: Placement_Relocate_Handler) -> bool {
    if checkpoint == nil || !checkpoint.valid || relocate == nil { return false }
    retained := checkpoint.placement_count
    for &entry in checkpoint.placements {
        if !entry.active || entry.metadata.geometry.screen != screen { continue }
        geometry, keep := relocate(user_data, entry.metadata.geometry)
        if !keep {
            generation := entry.generation
            entry = {generation = generation}
            retained -= 1
            continue
        }
        if geometry.screen != screen || geometry.logical_row == 0 ||
            geometry.column < 0 {
            return false
        }
        entry.metadata.geometry = geometry
    }
    checkpoint.placement_count = retained
    return true
}

//   Restore captured placement generations and their attachment references.
//
// Parameters:
//   - checkpoint: Valid capture bound to `store`.
//   - store: Destination registry whose current placements are replaced.
//
// Returns:
//   - True after exact restoration; false for invalid or incompatible state.
//
// Side effects:
//   - Releases all current placement references, copies captured slot generations,
//     and reacquires one reference for each restored placement. Capture pins remain.
placement_checkpoint_restore :: proc(
    checkpoint: ^Placement_Checkpoint, store: ^Store) -> bool {
    if checkpoint == nil || !checkpoint.valid || checkpoint.store != store ||
        len(checkpoint.placements) != len(store.placements) {
        return false
    }
    for &entry, slot in store.placements {
        if entry.active {
            placement_remove(store, {slot = slot, generation = entry.generation})
        }
    }
    copy(store.placements, checkpoint.placements)
    store.placement_count = 0
    for &entry in store.placements {
        if !entry.active {
            continue
        }
        attachment, outcome := attachment_entry(store, entry.metadata.attachment_id)
        if outcome != .Found {
            return false
        }
        attachment.placement_reference_count += 1
        attachment.last_used = store_next_sequence(store)
        store.placement_count += 1
    }
    return store.placement_count == checkpoint.placement_count
}

// Return the first inactive transfer slot, or negative one when the table is full.
transfer_available_slot :: proc(store: ^Store) -> int {
    for &entry, index in store.transfers {
        if !entry.active { return index }
    }
    return -1
}

//   Reserve exact mutable storage for one bounded encoded transfer.
//
// Parameters:
//   - store: Initialized registry that owns the transfer allocation on success.
//   - origin: Protocol associated with the transfer for later dispatch.
//   - byte_capacity: Positive exact reservation, bounded by transfer policy.
//
// Returns:
//   - A live transfer identity and `.Admitted`, or a zero identity with the
//     applicable invalid, byte-limit, capacity, or allocation outcome.
//
// Side effects:
//   - Allocates and zeroes one exact byte buffer, occupies a fixed transfer slot,
//     and updates transfer admission or rejection diagnostics.
transfer_begin :: proc(
    store: ^Store, origin: Protocol_Origin, byte_capacity: int) ->
    (Transfer_Id, Admission_Outcome) {
    if store == nil || byte_capacity <= 0 {
        return {}, .Invalid
    }
    if byte_capacity > store.limits.transfer_byte_limit {
        store.diagnostics.transfer_rejection_count += 1
        return {}, .Byte_Limit_Exceeded
    }
    slot := transfer_available_slot(store)
    if slot < 0 {
        store.diagnostics.transfer_rejection_count += 1
        return {}, .Capacity_Exceeded
    }
    // Session-recyclable transfer storage is released on completion or destruction.
    bytes, allocation_error := make(
        []u8, byte_capacity, store.payload_allocator)
    if allocation_error != nil {
        store.diagnostics.transfer_rejection_count += 1
        return {}, .Allocation_Failed
    }
    entry := &store.transfers[slot]
    generation := store_next_generation(entry.generation)
    entry^ = {
        generation = generation,
        active = true,
        origin = origin,
        bytes = bytes,
    }
    store.transfer_count += 1
    store.diagnostics.transfer_admission_count += 1
    return {slot = slot, generation = generation}, .Admitted
}

//   Append bytes to an existing transfer without growing its reservation.
//
// Parameters:
//   - store: Registry owning the transfer buffer.
//   - id: Live transfer capability to append to.
//   - source: Borrowed bytes copied during this call.
//
// Returns:
//   - `.Admitted` after copying all bytes, `.Byte_Limit_Exceeded` when the exact
//     reservation has insufficient space, or `.Invalid` for a stale handle.
//
// Side effects:
//   - Copies into the uninitialized suffix and advances the initialized count
//     only after the complete source fits.
transfer_append :: proc(
    store: ^Store, id: Transfer_Id, source: []u8) -> Admission_Outcome {
    entry, outcome := transfer_entry(store, id)
    if outcome != .Found {
        return .Invalid
    }
    if len(source) > len(entry.bytes) - entry.count {
        return .Byte_Limit_Exceeded
    }
    copy(entry.bytes[entry.count:], source)
    entry.count += len(source)
    return .Admitted
}

//   Borrow the initialized prefix of one active transfer.
//
// Parameters:
//   - store: Registry owning the transfer buffer.
//   - id: Live transfer capability to resolve.
//
// Returns:
//   - The initialized byte prefix and true, or nil and false for stale `id`.
//
// Notes:
//   - The returned slice is mutable owner storage and must not be retained across
//     append, removal, or store destruction.
transfer_bytes :: proc(store: ^Store, id: Transfer_Id) -> ([]u8, bool) {
    entry, outcome := transfer_entry(store, id)
    if outcome != .Found {
        return nil, false
    }
    return entry.bytes[:entry.count], true
}

//   Finish or abort one transfer and invalidate its issued capability.
//
// Parameters:
//   - store: Registry owning the transfer allocation.
//   - id: Live transfer capability to release.
//
// Returns:
//   - `.Found` after release, or `.Stale` when the generation is no longer live.
//
// Side effects:
//   - Frees the reserved bytes, clears the slot while preserving its generation,
//     and decrements transfer occupancy.
transfer_remove :: proc(store: ^Store, id: Transfer_Id) -> Handle_Outcome {
    entry, outcome := transfer_entry(store, id)
    if outcome != .Found {
        return outcome
    }
    delete(entry.bytes, store.payload_allocator)
    generation := entry.generation
    entry^ = {generation = generation}
    store.transfer_count -= 1
    return .Found
}

//   Resolve GPU accounting for one exact attachment generation.
//
// Parameters:
//   - store: Registry containing the residency table.
//   - id: Attachment identity whose residency is requested.
//
// Returns:
//   - The mutable accounting entry when the exact generation is resident, or nil.
//
// Notes:
//   - The entry accounts for a native resource owned elsewhere. The returned
//     pointer must not cross residency mutation or store destruction.
residency_entry :: proc(store: ^Store, id: Attachment_Id) -> ^Residency_Entry {
    if store == nil || id.slot < 0 || id.slot >= len(store.residency) {
        return nil
    }
    entry := &store.residency[id.slot]
    if !entry.resident || entry.attachment_id != id {
        return nil
    }
    return entry
}

//   Find the oldest resident attachment not protected by a placement or pin.
//
// Parameters:
//   - store: Initialized registry searched in stable residency-slot order.
//
// Returns:
//   - The selected attachment identity and true, or zero identity and false when
//     no native resource may be evicted.
//
// Side effects:
//   - Stale attachment identities encountered in residency may increment
//     stale-handle diagnostics through attachment lookup.
residency_eviction_candidate :: proc(store: ^Store) -> (Attachment_Id, bool) {
    if store == nil {
        return {}, false
    }
    candidate := -1
    oldest := max(u64)
    for &resident, index in store.residency {
        if !resident.resident {
            continue
        }
        attachment, outcome := attachment_entry(store, resident.attachment_id)
        if outcome != .Found || attachment.placement_reference_count > 0 ||
            attachment.pin_count > 0 {
            continue
        }
        if resident.last_used < oldest {
            candidate = index
            oldest = resident.last_used
        }
    }
    if candidate < 0 {
        return {}, false
    }
    return store.residency[candidate].attachment_id, true
}

//   Destroy eligible native resources until one GPU admission fits its budget.
//
// Parameters:
//   - store: Registry owning GPU-byte accounting and eviction order.
//   - byte_count: Positive bytes required by the pending native resource.
//   - evict_handler: Display-owner callback that destroys each selected resource.
//   - user_data: Opaque callback state passed unchanged to `evict_handler`.
//
// Returns:
//   - Number of completed evictions and `.Admitted` when enough room exists;
//     otherwise the completed count and the blocking outcome.
//
// Side effects:
//   - Calls the eviction handler synchronously, clears accounting only after a
//     successful callback, and updates GPU bytes and eviction diagnostics.
//
// Notes:
//   - Failure is not transactional: resources successfully evicted before a
//     later callback failure remain destroyed and unaccounted.
residency_make_room :: proc(
    store: ^Store, byte_count: int, evict_handler: Residency_Evict_Handler,
    user_data: rawptr) -> (int, Admission_Outcome) {
    eviction_count := 0
    for store.gpu_byte_count + byte_count > store.limits.gpu_byte_limit {
        evicted_id, evicted := residency_eviction_candidate(store)
        if !evicted || evict_handler == nil ||
            !evict_handler(user_data, evicted_id) {
            return eviction_count, .No_Evictable_Entry
        }
        resident := residency_entry(store, evicted_id)
        if resident == nil {
            return eviction_count, .Invalid
        }
        store.gpu_byte_count -= resident.byte_count
        store.diagnostics.gpu_evicted_bytes += u64(resident.byte_count)
        resident^ = {}
        eviction_count += 1
    }
    return eviction_count, .Admitted
}

// Update byte accounting for an already resident exact attachment generation.
residency_update_existing :: proc(
    store: ^Store, resident: ^Residency_Entry, byte_count: int) -> bool {
    if store.gpu_byte_count - resident.byte_count + byte_count >
        store.limits.gpu_byte_limit {
        return false
    }
    store.gpu_byte_count -= resident.byte_count
    resident.byte_count = byte_count
    resident.last_used = store_next_sequence(store)
    store.gpu_byte_count += byte_count
    return true
}

// Commit a new exact-generation residency entry and its aggregate accounting.
residency_commit :: proc(
    store: ^Store, attachment: ^Attachment_Entry,
    id: Attachment_Id, byte_count: int) -> bool {
    resident := &store.residency[id.slot]
    if resident.resident { return false }
    resident^ = {
        attachment_id = id,
        byte_count = byte_count,
        resident = true,
        last_used = store_next_sequence(store),
    }
    attachment.last_used = store.sequence
    store.gpu_byte_count += byte_count
    return true
}

//   Reserve bounded GPU bytes for one live attachment generation.
//
// Parameters:
//   - store: Registry owning GPU residency accounting.
//   - id: Live attachment generation receiving or updating residency.
//   - byte_count: Positive native resource size bounded by aggregate GPU policy.
//   - evict_handler: Optional display-owner teardown callback used under pressure.
//   - user_data: Opaque callback state passed unchanged to `evict_handler`.
//
// Returns:
//   - Admission outcome and number of old resources destroyed while making room.
//
// Side effects:
//   - May synchronously destroy eligible native resources through the callback,
//     updates residency and aggregate GPU bytes, and advances attachment recency.
//
// Notes:
//   - A replacement updates accounting for the same attachment generation but
//     does not destroy the old native resource; the display owner must coordinate
//     native replacement around this call.
residency_admit :: proc(
    store: ^Store, id: Attachment_Id, byte_count: int,
    evict_handler: Residency_Evict_Handler = nil,
    user_data: rawptr = nil) -> Residency_Admission {
    if store == nil || byte_count <= 0 {
        return {outcome = .Invalid}
    }
    if byte_count > store.limits.gpu_byte_limit {
        return {outcome = .Byte_Limit_Exceeded}
    }
    attachment, outcome := attachment_entry(store, id)
    if outcome != .Found {
        return {outcome = .Invalid}
    }
    existing := residency_entry(store, id)
    if existing != nil {
        outcome: Admission_Outcome = .Admitted if
            residency_update_existing(store, existing, byte_count) else
            .No_Evictable_Entry
        return {outcome = outcome}
    }
    eviction_count, room_outcome := residency_make_room(
        store, byte_count, evict_handler, user_data)
    if room_outcome != .Admitted {
        return {outcome = room_outcome, eviction_count = eviction_count}
    }
    admission_outcome: Admission_Outcome = .Admitted if
        residency_commit(store, attachment, id, byte_count) else
        .No_Evictable_Entry
    return {outcome = admission_outcome, eviction_count = eviction_count}
}

//   Release GPU accounting after the display owner destroys a native resource.
//
// Parameters:
//   - store: Registry owning the residency ledger.
//   - id: Exact attachment generation whose native resource was destroyed.
//
// Returns:
//   - `.Found` after releasing accounting, or `.Stale` when no matching residency
//     exists.
//
// Side effects:
//   - Clears the residency entry and decrements aggregate GPU bytes.
//
// Notes:
//   - This procedure never destroys native resources; teardown must happen first.
residency_remove :: proc(store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    resident := residency_entry(store, id)
    if resident == nil {
        return .Stale
    }
    store.gpu_byte_count -= resident.byte_count
    resident^ = {}
    return .Found
}

//   Mark one exact native residency as used by the current display frame.
//
// Returns:
//   - `.Found` after advancing recency, or `.Stale` when residency is unavailable.
residency_touch :: proc(store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    resident := residency_entry(store, id)
    if resident == nil { return .Stale }
    resident.last_used = store_next_sequence(store)
    attachment, outcome := attachment_entry(store, id)
    if outcome == .Found { attachment.last_used = store.sequence }
    return .Found
}