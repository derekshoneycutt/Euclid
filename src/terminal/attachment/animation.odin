package termattachment

NANOSECONDS_PER_SECOND :: u128(1_000_000_000)

// Exact recyclable buffers allocated together for one pending animation.
Animation_Allocation :: struct {
    pixels: []u8,
    frames: []Animation_Frame,
    valid: bool,
}

// Convert one source-format duration to normalized bounded nanoseconds.
//
// Parameters:
//   - value: Nonnegative source duration measured in `units_per_second` units.
//   - units_per_second: Positive source units in one second.
//   - limits: Frame minimum and maximum policy used for clamping and rejection.
//
// Returns:
//   - A positive duration and true, or zero and false when conversion is invalid
//     or exceeds the configured maximum. Sub-minimum values clamp upward.
animation_duration_from_units :: proc(
    value, units_per_second: u64, limits: Limits) -> (u64, bool) {
    if units_per_second == 0 || limits.animation_min_frame_duration_ns == 0 ||
        limits.animation_max_frame_duration_ns <
            limits.animation_min_frame_duration_ns {
        return 0, false
    }
    converted := u128(value) * NANOSECONDS_PER_SECOND / u128(units_per_second)
    if converted < u128(limits.animation_min_frame_duration_ns) {
        return limits.animation_min_frame_duration_ns, true
    }
    if converted > u128(limits.animation_max_frame_duration_ns) {
        return 0, false
    }
    return u64(converted), true
}

// Validate one animation reservation and return its exact retained CPU charge.
animation_retained_byte_count :: proc(
    reservation: Animation_Reservation) -> (int, Admission_Outcome) {
    width := reservation.metadata.metrics.width
    height := reservation.metadata.metrics.height
    if width <= 0 || height <= 0 || width > max(int) / height ||
        width * height > max(int) / 4 {
        return 0, .Invalid
    }
    canvas_byte_count := width * height * 4
    if reservation.frame_count > max(int) / canvas_byte_count ||
        reservation.payload_byte_count != canvas_byte_count * reservation.frame_count {
        return 0, .Invalid
    }
    if reservation.frame_count > max(int) / int(size_of(Animation_Frame)) {
        return 0, .Byte_Limit_Exceeded
    }
    descriptor_byte_count := reservation.frame_count * int(size_of(Animation_Frame))
    if reservation.payload_byte_count > max(int) - descriptor_byte_count {
        return 0, .Byte_Limit_Exceeded
    }
    return reservation.payload_byte_count + descriptor_byte_count, .Admitted
}

// Validate one animation reservation and return its exact retained CPU charge.
animation_reservation_valid :: proc(
    store: ^Store, reservation: Animation_Reservation) ->
    (int, Admission_Outcome) {
    if store == nil || reservation.frame_count <= 0 ||
        reservation.frame_count > store.limits.animation_frame_limit ||
        reservation.temporary_decode_byte_count < 0 ||
        reservation.temporary_decode_byte_count >
            store.limits.animation_decode_byte_limit ||
        reservation.infinite && reservation.repeat_count != 0 {
        return 0, .Invalid
    }
    if store.animated_attachment_count >= store.limits.animated_attachment_limit {
        return 0, .Capacity_Exceeded
    }
    if reservation.temporary_decode_byte_count >
        store.limits.animation_decode_byte_limit -
            store.animation_decode_byte_count {
        return 0, .Byte_Limit_Exceeded
    }
    retained_byte_count, charge_outcome := animation_retained_byte_count(reservation)
    if charge_outcome != .Admitted { return 0, charge_outcome }
    width := reservation.metadata.metrics.width
    validation := attachment_admission_valid(
        store, reservation.metadata, reservation.payload_byte_count,
        width * 4, .Rgba8)
    if validation != .Admitted { return 0, validation }
    if retained_byte_count > store.limits.cpu_byte_limit {
        return 0, .Byte_Limit_Exceeded
    }
    return retained_byte_count, .Admitted
}

// Allocate exact animation buffers transactionally from recyclable store memory.
//
// Returns:
//   - Both buffers and true, or empty storage after rolling back a partial allocation.
animation_allocate :: proc(
    store: ^Store, reservation: Animation_Reservation) -> Animation_Allocation {
    pixels, pixels_error := make(
        []u8, reservation.payload_byte_count, store.payload_allocator)
    if pixels_error != nil { return {} }
    frames, frames_error := make(
        []Animation_Frame, reservation.frame_count, store.payload_allocator)
    if frames_error != nil {
        delete(pixels, store.payload_allocator)
        return {}
    }
    return {pixels = pixels, frames = frames, valid = true}
}

// Record one rejected animation reservation and return its original outcome.
animation_reject :: proc(
    store: ^Store, outcome: Admission_Outcome) -> (Attachment_Id, Admission_Outcome) {
    if store != nil {
        store.diagnostics.attachment_rejection_count += 1
        store.diagnostics.animation_rejection_count += 1
    }
    return {}, outcome
}

// Reserve exact recyclable pixels and descriptors for one pending animation generation.
//
// Returns:
//   - A pinned pending generation and `.Admitted`, or a zero identity and rejection.
//
// Side effects:
//   - May evict eligible attachments and transactionally allocates both exact buffers.
animation_reserve :: proc(
    store: ^Store, reservation: Animation_Reservation) ->
    (Attachment_Id, Admission_Outcome) {
    retained_byte_count, validation := animation_reservation_valid(store, reservation)
    if validation != .Admitted {
        return animation_reject(store, validation)
    }
    slot, slot_outcome := attachment_slot_acquire(store, retained_byte_count)
    if slot_outcome != .Admitted {
        return animation_reject(store, slot_outcome)
    }
    allocation := animation_allocate(store, reservation)
    if !allocation.valid {
        return animation_reject(store, .Allocation_Failed)
    }
    id := attachment_entry_commit(store, slot, {
        metadata = reservation.metadata,
        payload = allocation.pixels,
        payload_format = .Rgba8,
        payload_stride = reservation.metadata.metrics.width * 4,
        animation_frames = allocation.frames,
        animation_timeline = {
            frame_count = reservation.frame_count,
            repeat_count = reservation.repeat_count,
            infinite = reservation.infinite,
        },
        cpu_byte_count = retained_byte_count,
        animation_decode_byte_count = reservation.temporary_decode_byte_count,
        pin_count = 1,
        protocol_retained = reservation.protocol_retained,
    })
    store.diagnostics.animation_admission_count += 1
    return id, .Admitted
}

// Borrow exact mutable animation destinations while one pending generation is pinned.
animation_preparation_buffer :: proc(
    store: ^Store, id: Attachment_Id) -> (Animation_Preparation, bool) {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || entry.prepared || entry.removal_requested ||
        entry.pin_count <= 0 || len(entry.animation_frames) == 0 {
        return {}, false
    }
    return {pixels = entry.payload, frames = entry.animation_frames}, true
}

// Validate one complete full-canvas frame table and calculate its cycle duration.
animation_frames_valid :: proc(
    entry: ^Attachment_Entry, limits: Limits) -> (u64, bool) {
    canvas_byte_count := entry.metadata.metrics.width *
        entry.metadata.metrics.height * 4
    cycle_duration_ns: u64
    for frame, index in entry.animation_frames {
        if frame.pixels.offset != index * canvas_byte_count ||
            frame.pixels.count != canvas_byte_count || frame.duration_ns == 0 ||
            frame.duration_ns < limits.animation_min_frame_duration_ns ||
            frame.duration_ns > limits.animation_max_frame_duration_ns ||
            frame.duration_ns > limits.animation_duration_ns_limit -
                cycle_duration_ns {
            return 0, false
        }
        cycle_duration_ns += frame.duration_ns
    }
    return cycle_duration_ns, true
}

// Publish one joined animation only after validating every frame and duration atomically.
animation_preparation_publish :: proc(
    store: ^Store, id: Attachment_Id) -> Handle_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || entry.prepared || entry.removal_requested ||
        entry.pin_count <= 0 || len(entry.animation_frames) == 0 {
        return .Stale
    }
    cycle_duration_ns, valid := animation_frames_valid(entry, store.limits)
    if !valid { return .Stale }
    entry.animation_timeline.cycle_duration_ns = cycle_duration_ns
    store.animation_decode_byte_count -= entry.animation_decode_byte_count
    entry.animation_decode_byte_count = 0
    entry.prepared = true
    entry.pin_count -= 1
    entry.last_used = store_next_sequence(store)
    return .Found
}

// Borrow one immutable normalized animation and mark its attachment recently used.
animation_view :: proc(
    store: ^Store, id: Attachment_Id) -> (Animation_View, bool) {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared || len(entry.animation_frames) == 0 {
        return {}, false
    }
    entry.last_used = store_next_sequence(store)
    return {
        pixels = entry.payload,
        frames = entry.animation_frames,
        timeline = entry.animation_timeline,
    }, true
}