package termattachment

KITTY_DEFAULT_FRAME_DURATION_NS :: u64(40 * 1_000_000)

// Transactional replacement storage for one mutable Kitty timeline.
Kitty_Animation_Allocation :: struct {
    pixels: []u8,
    frames: []Animation_Frame,
    byte_count: int,
    valid: bool,
}

// Validated indexes and geometry for one transactional Kitty frame mutation.
Kitty_Frame_Plan :: struct {
    canvas_byte_count: int,
    old_frame_count: int,
    target_index: int,
    frame_count: int,
    base_index: int,
    width: int,
    valid: bool,
}

// Return the exact full-canvas byte count for one live raster entry.
kitty_animation_canvas_byte_count :: proc(entry: ^Attachment_Entry) -> (int, bool) {
    if entry == nil || entry.metadata.metrics.width <= 0 ||
        entry.metadata.metrics.height <= 0 ||
        entry.metadata.metrics.width > max(int) / entry.metadata.metrics.height ||
        entry.metadata.metrics.width * entry.metadata.metrics.height > max(int) / 4 {
        return 0, false
    }
    return entry.metadata.metrics.width * entry.metadata.metrics.height * 4, true
}

// Validate a one-based frame number against one candidate timeline.
kitty_animation_frame_index :: proc(frame_number, frame_count: int) -> (int, bool) {
    return frame_number - 1, frame_number > 0 && frame_number <= frame_count
}

// Reserve CPU quota and allocate exact replacement pixels and descriptors.
kitty_animation_allocate :: proc(
    store: ^Store, entry: ^Attachment_Entry, frame_count, canvas_byte_count: int) ->
    Kitty_Animation_Allocation {
    if frame_count <= 0 || frame_count > store.limits.animation_frame_limit ||
        frame_count > max(int) / canvas_byte_count ||
        frame_count > max(int) / int(size_of(Animation_Frame)) {
        return {}
    }
    pixel_byte_count := frame_count * canvas_byte_count
    descriptor_byte_count := frame_count * int(size_of(Animation_Frame))
    if pixel_byte_count > max(int) - descriptor_byte_count { return {} }
    byte_count := pixel_byte_count + descriptor_byte_count
    if byte_count > store.limits.cpu_byte_limit { return {} }
    if store.cpu_byte_count - entry.cpu_byte_count + byte_count >
        store.limits.cpu_byte_limit { return {} }
    pixels, pixels_error := make([]u8, pixel_byte_count, store.payload_allocator)
    if pixels_error != nil { return {} }
    frames, frames_error := make(
        []Animation_Frame, frame_count, store.payload_allocator)
    if frames_error != nil {
        delete(pixels, store.payload_allocator)
        return {}
    }
    return {pixels = pixels, frames = frames, byte_count = byte_count, valid = true}
}

// Copy one static RGB/RGBA root into a full-canvas RGBA destination.
kitty_animation_copy_root :: proc(destination: []u8, entry: ^Attachment_Entry) -> bool {
    canvas_byte_count, valid := kitty_animation_canvas_byte_count(entry)
    if !valid || len(destination) != canvas_byte_count { return false }
    width := entry.metadata.metrics.width
    height := entry.metadata.metrics.height
    bytes_per_pixel := 3 if entry.payload_format == .Rgb8 else 4
    if entry.payload_format != .Rgb8 && entry.payload_format != .Rgba8 ||
        entry.payload_stride < width * bytes_per_pixel ||
        len(entry.payload) < entry.payload_stride * height {
        return false
    }
    for row in 0..<height {
        source := entry.payload[row * entry.payload_stride:]
        target := destination[row * width * 4:]
        for column in 0..<width {
            source_offset := column * bytes_per_pixel
            target_offset := column * 4
            copy(target[target_offset:target_offset + 3],
                source[source_offset:source_offset + 3])
            target[target_offset + 3] = source[source_offset + 3] if
                bytes_per_pixel == 4 else 255
        }
    }
    return true
}

// Copy all existing canvases and descriptors into replacement storage.
kitty_animation_copy_existing :: proc(
    allocation: ^Kitty_Animation_Allocation, entry: ^Attachment_Entry,
    old_frame_count, canvas_byte_count: int) -> bool {
    if old_frame_count == 1 && len(entry.animation_frames) == 0 {
        if !kitty_animation_copy_root(
            allocation.pixels[:canvas_byte_count], entry) {
            return false
        }
        allocation.frames[0] = {
            pixels = {offset = 0, count = canvas_byte_count},
            duration_ns = KITTY_DEFAULT_FRAME_DURATION_NS,
        }
        return true
    }
    if len(entry.animation_frames) != old_frame_count ||
        len(entry.payload) != old_frame_count * canvas_byte_count {
        return false
    }
    copy(allocation.pixels[:len(entry.payload)], entry.payload)
    copy(allocation.frames[:old_frame_count], entry.animation_frames)
    return true
}

// Fill one canvas with a packed `0xRRGGBBAA` Kitty background color.
kitty_animation_fill :: proc(canvas: []u8, rgba: u32) {
    red := u8(rgba >> 24)
    green := u8(rgba >> 16)
    blue := u8(rgba >> 8)
    alpha := u8(rgba)
    for index in 0..<len(canvas) / 4 {
        offset := index * 4
        canvas[offset + 0] = red
        canvas[offset + 1] = green
        canvas[offset + 2] = blue
        canvas[offset + 3] = alpha
    }
}

// Blend one straight-alpha source pixel over one straight-alpha destination.
kitty_animation_blend_pixel :: proc(destination: []u8, source: []u8) {
    source_alpha := u32(source[3])
    destination_alpha := u32(destination[3])
    inverse := 255 - source_alpha
    output_alpha := source_alpha + (destination_alpha * inverse + 127) / 255
    if output_alpha == 0 {
        destination[0] = 0
        destination[1] = 0
        destination[2] = 0
        destination[3] = 0
        return
    }
    for component in 0..<3 {
        numerator := u32(source[component]) * source_alpha * 255 +
            u32(destination[component]) * destination_alpha * inverse
        destination[component] = u8(
            (numerator + output_alpha * 127) / (output_alpha * 255))
    }
    destination[3] = u8(output_alpha)
}

// Composite one raw RGB/RGBA patch into a complete destination canvas.
kitty_animation_apply_patch :: proc(
    canvas: []u8, canvas_width: int, mutation: Kitty_Frame_Mutation) -> bool {
    bytes_per_pixel := 3 if mutation.format == .Rgb8 else 4
    if mutation.format != .Rgb8 && mutation.format != .Rgba8 ||
        mutation.width <= 0 || mutation.height <= 0 ||
        len(mutation.pixels) != mutation.width * mutation.height * bytes_per_pixel {
        return false
    }
    for row in 0..<mutation.height {
        for column in 0..<mutation.width {
            source_offset := (row * mutation.width + column) * bytes_per_pixel
            target_offset := ((mutation.destination_y + row) * canvas_width +
                mutation.destination_x + column) * 4
            source := [4]u8{
                mutation.pixels[source_offset + 0],
                mutation.pixels[source_offset + 1],
                mutation.pixels[source_offset + 2],
                mutation.pixels[source_offset + 3] if bytes_per_pixel == 4 else 255,
            }
            if mutation.overwrite {
                copy(canvas[target_offset:target_offset + 4], source[:])
            } else {
                kitty_animation_blend_pixel(
                    canvas[target_offset:target_offset + 4], source[:])
            }
        }
    }
    return true
}

// Convert a Kitty frame gap to a retained duration, preserving gapless negatives.
kitty_animation_duration :: proc(mutation: Kitty_Frame_Mutation) -> (u64, bool) {
    if !mutation.gap_specified { return KITTY_DEFAULT_FRAME_DURATION_NS, true }
    if mutation.gap_ms < 0 { return 0, true }
    converted := u64(mutation.gap_ms) * 1_000_000
    return converted, converted > 0
}

// Release one uncommitted replacement allocation.
kitty_animation_release :: proc(
    store: ^Store, allocation: Kitty_Animation_Allocation) {
    delete(allocation.frames, store.payload_allocator)
    delete(allocation.pixels, store.payload_allocator)
}

// Validate one normalized frame duration against store policy.
kitty_animation_duration_valid :: proc(store: ^Store, duration_ns: u64) -> bool {
    return duration_ns <= store.limits.animation_max_frame_duration_ns &&
        (duration_ns == 0 ||
         duration_ns >= store.limits.animation_min_frame_duration_ns)
}

// Sum one candidate timeline without overflow or total-duration policy violation.
kitty_animation_cycle_duration :: proc(
    store: ^Store, frames: []Animation_Frame) -> (u64, bool) {
    duration_ns: u64
    for frame in frames {
        if frame.duration_ns > store.limits.animation_duration_ns_limit -
            duration_ns {
            return 0, false
        }
        duration_ns += frame.duration_ns
    }
    return duration_ns, true
}

// Resolve frame indexes and checked canvas geometry before allocating replacement data.
kitty_animation_frame_plan :: proc(
    store: ^Store, entry: ^Attachment_Entry,
    mutation: Kitty_Frame_Mutation) -> Kitty_Frame_Plan {
    plan: Kitty_Frame_Plan
    plan.canvas_byte_count, plan.valid = kitty_animation_canvas_byte_count(entry)
    plan.old_frame_count = max(len(entry.animation_frames), 1)
    plan.target_index = plan.old_frame_count
    if mutation.edit_frame > 0 {
        edit_valid: bool
        plan.target_index, edit_valid = kitty_animation_frame_index(
            mutation.edit_frame, plan.old_frame_count)
        plan.valid = plan.valid && edit_valid
    }
    plan.frame_count = plan.old_frame_count +
        (1 if mutation.edit_frame == 0 else 0)
    plan.base_index = -1
    if mutation.base_frame > 0 {
        base_valid: bool
        plan.base_index, base_valid = kitty_animation_frame_index(
            mutation.base_frame, plan.old_frame_count)
        plan.valid = plan.valid && base_valid
    }
    plan.width = entry.metadata.metrics.width
    height := entry.metadata.metrics.height
    plan.valid = plan.valid && mutation.destination_x >= 0 &&
        mutation.destination_y >= 0 &&
        mutation.width <= plan.width - mutation.destination_x &&
        mutation.height <= height - mutation.destination_y &&
        plan.frame_count <= store.limits.animation_frame_limit &&
        (len(entry.animation_frames) > 0 || store.animated_attachment_count <
            store.limits.animated_attachment_limit)
    return plan
}

// Build one complete replacement candidate without changing store accounting.
kitty_animation_initialize_target :: proc(
    allocation: ^Kitty_Animation_Allocation, mutation: Kitty_Frame_Mutation,
    plan: Kitty_Frame_Plan) -> []u8 {
    target := allocation.pixels[plan.target_index * plan.canvas_byte_count:
        (plan.target_index + 1) * plan.canvas_byte_count]
    if mutation.edit_frame == 0 {
        if plan.base_index >= 0 {
            copy(target, allocation.pixels[plan.base_index * plan.canvas_byte_count:
                (plan.base_index + 1) * plan.canvas_byte_count])
        } else {
            kitty_animation_fill(target, mutation.background_rgba)
        }
    }
    return target
}

// Build one complete replacement candidate without changing store accounting.
kitty_animation_build_replacement :: proc(
    store: ^Store, entry: ^Attachment_Entry,
    mutation: Kitty_Frame_Mutation,
    plan: Kitty_Frame_Plan) ->
    (Kitty_Animation_Allocation, Animation_Mutation_Outcome) {
    allocation := kitty_animation_allocate(
        store, entry, plan.frame_count, plan.canvas_byte_count)
    if !allocation.valid { return {}, .Capacity_Exceeded }
    if !kitty_animation_copy_existing(
        &allocation, entry, plan.old_frame_count, plan.canvas_byte_count) {
        kitty_animation_release(store, allocation)
        return {}, .Invalid
    }
    target := kitty_animation_initialize_target(&allocation, mutation, plan)
    duration_ns, duration_valid := kitty_animation_duration(mutation)
    if !duration_valid || !kitty_animation_duration_valid(store, duration_ns) ||
        !kitty_animation_apply_patch(target, plan.width, mutation) {
        kitty_animation_release(store, allocation)
        return {}, .Invalid
    }
    if mutation.edit_frame == 0 || mutation.gap_specified {
        allocation.frames[plan.target_index].duration_ns = duration_ns
    }
    allocation.frames[plan.target_index].pixels = {
        offset = plan.target_index * plan.canvas_byte_count,
        count = plan.canvas_byte_count,
    }
    return allocation, .Found
}

// Atomically install replacement animation storage without changing generation.
kitty_animation_commit :: proc(
    store: ^Store, entry: ^Attachment_Entry,
    allocation: Kitty_Animation_Allocation, cycle_duration_ns: u64) {
    was_animated := len(entry.animation_frames) > 0
    store.cpu_byte_count -= entry.cpu_byte_count
    delete(entry.animation_frames, store.payload_allocator)
    delete(entry.payload, store.payload_allocator)
    entry.payload = allocation.pixels
    entry.payload_format = .Rgba8
    entry.payload_stride = entry.metadata.metrics.width * 4
    entry.animation_frames = allocation.frames
    entry.animation_timeline.frame_count = len(allocation.frames)
    entry.animation_timeline.cycle_duration_ns = cycle_duration_ns
    entry.cpu_byte_count = allocation.byte_count
    entry.last_used = store_next_sequence(store)
    store.cpu_byte_count += allocation.byte_count
    if !was_animated { store.animated_attachment_count += 1 }
}

// Create or edit one Kitty frame through a complete transactional storage swap.
kitty_animation_mutate_frame :: proc(
    store: ^Store, id: Attachment_Id, mutation: Kitty_Frame_Mutation) ->
    Animation_Mutation_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared || entry.metadata.origin != .Kitty {
        return .Stale
    }
    plan := kitty_animation_frame_plan(store, entry, mutation)
    if !plan.valid { return .Invalid }
    allocation, preparation_outcome := kitty_animation_build_replacement(
        store, entry, mutation, plan)
    if preparation_outcome != .Found { return preparation_outcome }
    cycle_duration_ns, cycle_valid := kitty_animation_cycle_duration(
        store, allocation.frames)
    if !cycle_valid {
        kitty_animation_release(store, allocation)
        return .Invalid
    }
    kitty_animation_commit(store, entry, allocation, cycle_duration_ns)
    return .Found
}

// Apply one frame-to-frame rectangle operation to replacement storage.
kitty_animation_apply_composition :: proc(
    source_pixels, destination_pixels: []u8,
    canvas_width, canvas_byte_count: int,
    composition: Kitty_Frame_Composition) {
    source_index := composition.source_frame - 1
    destination_index := composition.destination_frame - 1
    source_canvas := source_pixels[
        source_index * canvas_byte_count:(source_index + 1) * canvas_byte_count]
    destination_canvas := destination_pixels[
        destination_index * canvas_byte_count:(destination_index + 1) * canvas_byte_count]
    for row in 0..<composition.height {
        for column in 0..<composition.width {
            source_offset := ((composition.source_y + row) * canvas_width +
                composition.source_x + column) * 4
            destination_offset := ((composition.destination_y + row) * canvas_width +
                composition.destination_x + column) * 4
            source := source_canvas[source_offset:source_offset + 4]
            destination := destination_canvas[
                destination_offset:destination_offset + 4]
            if composition.overwrite {
                copy(destination, source)
            } else {
                kitty_animation_blend_pixel(destination, source)
            }
        }
    }
}

// Atomically compose one checked source-frame rectangle into a destination frame.
kitty_animation_composition_valid :: proc(
    composition: Kitty_Frame_Composition, width, height: int) -> bool {
    return composition.width > 0 && composition.height > 0 &&
        composition.source_x >= 0 && composition.source_y >= 0 &&
        composition.destination_x >= 0 && composition.destination_y >= 0 &&
        composition.width <= width - composition.source_x &&
        composition.height <= height - composition.source_y &&
        composition.width <= width - composition.destination_x &&
        composition.height <= height - composition.destination_y
}

// Atomically compose one checked source-frame rectangle into a destination frame.
kitty_animation_compose :: proc(
    store: ^Store, id: Attachment_Id, composition: Kitty_Frame_Composition) ->
    Animation_Mutation_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared || entry.metadata.origin != .Kitty {
        return .Stale
    }
    frame_count := len(entry.animation_frames)
    canvas_byte_count, valid := kitty_animation_canvas_byte_count(entry)
    _, source_valid := kitty_animation_frame_index(
        composition.source_frame, frame_count)
    _, destination_valid := kitty_animation_frame_index(
        composition.destination_frame, frame_count)
    width := entry.metadata.metrics.width
    height := entry.metadata.metrics.height
    if !valid || !source_valid || !destination_valid { return .Not_Found }
    if !kitty_animation_composition_valid(composition, width, height) {
        return .Invalid
    }
    allocation := kitty_animation_allocate(
        store, entry, frame_count, canvas_byte_count)
    if !allocation.valid { return .Capacity_Exceeded }
    if !kitty_animation_copy_existing(
        &allocation, entry, frame_count, canvas_byte_count) {
        delete(allocation.frames, store.payload_allocator)
        delete(allocation.pixels, store.payload_allocator)
        return .Invalid
    }
    kitty_animation_apply_composition(
        entry.payload, allocation.pixels, width, canvas_byte_count, composition)
    kitty_animation_commit(
        store, entry, allocation, entry.animation_timeline.cycle_duration_ns)
    return .Found
}

// Atomically remove one non-root frame or every non-root animation frame.
kitty_animation_delete_frames :: proc(
    store: ^Store, id: Attachment_Id, frame_number: int, all: bool) ->
    Animation_Mutation_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared || entry.metadata.origin != .Kitty {
        return .Stale
    }
    old_frame_count := len(entry.animation_frames)
    if old_frame_count <= 1 { return .Not_Found }
    remove_index := -1
    if !all {
        remove_index, _ = kitty_animation_frame_index(frame_number, old_frame_count)
        if remove_index <= 0 { return .Not_Found }
    }
    frame_count := 1 if all else old_frame_count - 1
    canvas_byte_count, valid := kitty_animation_canvas_byte_count(entry)
    if !valid { return .Invalid }
    allocation := kitty_animation_allocate(
        store, entry, frame_count, canvas_byte_count)
    if !allocation.valid { return .Capacity_Exceeded }
    destination := 0
    cycle_duration_ns: u64
    for source in 0..<old_frame_count {
        if source > 0 && (all || source == remove_index) { continue }
        copy(allocation.pixels[
            destination * canvas_byte_count:(destination + 1) * canvas_byte_count],
            entry.payload[source * canvas_byte_count:(source + 1) * canvas_byte_count])
        allocation.frames[destination] = entry.animation_frames[source]
        allocation.frames[destination].pixels = {
            offset = destination * canvas_byte_count, count = canvas_byte_count,
        }
        cycle_duration_ns += allocation.frames[destination].duration_ns
        destination += 1
    }
    kitty_animation_commit(store, entry, allocation, cycle_duration_ns)
    return .Found
}

// Mutate one frame gap and loop policy without changing canvas storage.
kitty_animation_control :: proc(
    store: ^Store, id: Attachment_Id, control: Kitty_Animation_Control) ->
    Animation_Mutation_Outcome {
    entry, outcome := attachment_entry(store, id)
    if outcome != .Found || !entry.prepared || len(entry.animation_frames) == 0 ||
        entry.metadata.origin != .Kitty {
        return .Stale
    }
    if control.gap_specified {
        frame_index, valid := kitty_animation_frame_index(
            control.frame_number, len(entry.animation_frames))
        if !valid || control.gap_ms == 0 { return .Invalid }
        duration_ns := u64(0) if control.gap_ms < 0 else
            u64(control.gap_ms) * 1_000_000
        old_duration_ns := entry.animation_frames[frame_index].duration_ns
        cycle_without_frame := entry.animation_timeline.cycle_duration_ns -
            old_duration_ns
        if duration_ns > store.limits.animation_max_frame_duration_ns ||
            duration_ns > 0 &&
                duration_ns < store.limits.animation_min_frame_duration_ns ||
            duration_ns > store.limits.animation_duration_ns_limit -
                cycle_without_frame {
            return .Invalid
        }
        entry.animation_timeline.cycle_duration_ns = cycle_without_frame
        entry.animation_frames[frame_index].duration_ns = duration_ns
        entry.animation_timeline.cycle_duration_ns += duration_ns
    }
    if control.loop_count > 0 {
        entry.animation_timeline.infinite = control.loop_count == 1
        entry.animation_timeline.repeat_count = 0 if control.loop_count <= 1 else
            control.loop_count - 1
    }
    entry.last_used = store_next_sequence(store)
    return .Found
}