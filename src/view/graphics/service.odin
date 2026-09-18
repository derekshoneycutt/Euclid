// Package viewgraphics owns asynchronous terminal-raster preparation and GPU publication.
package viewgraphics

import "../../taskpool"
import "../../evidence/observe"
import "../../evidence/trace"
import termattachment "../../terminal/attachment"
import termgraphicsprepare "../../terminal/graphics/prepare"
import gfxprotocol "../../terminal/graphics/protocol"
import gfxsemantics "../../terminal/graphics/semantics"
import termmodel "../../terminal/model"

import rl "vendor:raylib"

GRAPHICS_OPERATION_CAPACITY :: gfxprotocol.GRAPHICS_DECODE_REQUEST_CAPACITY
GRAPHICS_TEXTURE_CAPACITY :: termattachment.DEFAULT_ATTACHMENT_CAPACITY

// Display-owned upload capability used to commit one complete animation canvas.
Playback_Upload_Handler :: #type proc(
    user_data: rawptr, id: termattachment.Attachment_Id,
    pixels: []u8) -> bool

// Borrowed texture upload capability and its opaque display-owned context.
Playback_Upload :: struct {
    handler: Playback_Upload_Handler,
    user_data: rawptr,
}

// Display-owner lifecycle for one decode request and its task payload.
Operation_State :: enum u8 {
    Idle,
    Preflight_Retry,
    Preflight_Queued,
    Retry,
    Queued,
}

// Self-contained GIF inspection payload exclusively owned while queued.
Gif_Preflight_Task :: struct {
    session_generation: u64,
    input: []u8,
    limits: termgraphicsprepare.Gif_Animation_Limits,
    inspection: termgraphicsprepare.Gif_Animation_Inspection,
}

// Self-contained CPU preparation payload exclusively owned while queued.
Prepare_Task :: struct {
    session_generation: u64,
    request: termgraphicsprepare.Prepare_Request,
}

// One decode request retained across queue pressure, execution, and publication.
Operation :: struct {
    state: Operation_State,
    decode: gfxprotocol.Graphics_Decode_Request,
    preflight: Gif_Preflight_Task,
    task: Prepare_Task,
    handle: taskpool.Task_Handle,
}

// Borrowed preparation destinations resolved from one pending attachment.
Prepare_Output :: struct {
    pixels: []u8,
    frames: []termattachment.Animation_Frame,
    found: bool,
}

// One display-owned native texture correlated to an exact attachment generation.
Texture_Entry :: struct {
    attachment_id: termattachment.Attachment_Id,
    texture: rl.Texture2D,
    resident: bool,
}

// Bounded display service joining CPU work before publishing native resources.
Service :: struct {
    // Borrowed terminal owners and fixed operation/native-resource tables.
    parser: ^gfxprotocol.Graphics_Parser_State,
    store: ^termattachment.Store,
    trace_ring: ^trace.Ring,
    operations: [GRAPHICS_OPERATION_CAPACITY]Operation,
    textures: [GRAPHICS_TEXTURE_CAPACITY]Texture_Entry,
    playbacks: [GRAPHICS_TEXTURE_CAPACITY]Playback_Entry,
    session_generation: u64,
    monotonic_ns: u64,
    visibility_epoch: u64,
    unbinding: bool,
    stopped: bool,

    // Content-free lifecycle telemetry.
    queue_full_count: u64,
    pending_poll_count: u64,
    failure_count: u64,
    decode_count: u64,
    publication_count: u64,
    cancellation_count: u64,
    stale_completion_count: u64,
    eviction_count: u64,
    playback_transition_count: u64,
    playback_completion_count: u64,
    playback_upload_failure_count: u64,
    playback_stale_count: u64,
    visibility_pause_count: u64,
    visibility_resume_count: u64,
    draw_count: u64,
    draw_rejection_count: u64,
}

// Report whether positive frame-local rectangles have visible overlap.
raster_rectangles_intersect :: proc(
    destination, clip: termattachment.Render_Rectangle) -> bool {
    if destination.width <= 0 || destination.height <= 0 ||
        clip.width <= 0 || clip.height <= 0 {
        return false
    }
    return destination.x < clip.x + clip.width &&
        destination.x + destination.width > clip.x &&
        destination.y < clip.y + clip.height &&
        destination.y + destination.height > clip.y
}

// Record an exact animation generation drawn during the open display epoch.
playback_visibility_record :: proc(
    service: ^Service, id: termattachment.Attachment_Id) {
    if service == nil || id.slot < 0 || id.slot >= len(service.playbacks) { return }
    entry := &service.playbacks[id.slot]
    if entry.active && entry.attachment_id == id {
        entry.visible_epoch = service.visibility_epoch
    }
}

// Commit the completed display epoch and open the next fixed visibility epoch.
playback_visibility_begin_frame :: proc(service: ^Service, now_ns: u64) {
    completed_epoch := service.visibility_epoch
    if completed_epoch != 0 {
        for &entry in service.playbacks {
            was_paused := entry.paused
            playback_visibility_commit(&entry, completed_epoch, now_ns)
            if !was_paused && entry.paused {
                service.visibility_pause_count += 1
            } else if was_paused && !entry.paused {
                service.visibility_resume_count += 1
            }
        }
    }
    if completed_epoch == max(u64) {
        for &entry in service.playbacks { entry.visible_epoch = 0 }
        service.visibility_epoch = 1
    } else {
        service.visibility_epoch += 1
    }
}

//   Draw one exact-generation texture through the terminal renderer capability.
//
// Returns:
//   - True after issuing a clipped draw command; false for stale or invalid geometry.
//
// Notes:
//   - The caller owns terminal scissoring around this draw.
service_draw_raster :: proc(
    user_data: rawptr, request: termattachment.Raster_Draw_Request) -> bool {
    service := cast(^Service)user_data
    if service == nil || request.attachment_id.slot < 0 ||
        request.attachment_id.slot >= len(service.textures) ||
        request.source.width <= 0 || request.source.height <= 0 ||
        !raster_rectangles_intersect(request.destination, request.clip) {
        if service != nil { service.draw_rejection_count += 1 }
        return false
    }
    entry := &service.textures[request.attachment_id.slot]
    source := request.source
    if !entry.resident || entry.attachment_id != request.attachment_id ||
        !rl.IsTextureValid(entry.texture) || source.x < 0 || source.y < 0 ||
        source.x + source.width > int(entry.texture.width) ||
        source.y + source.height > int(entry.texture.height) {
        service.draw_rejection_count += 1
        return false
    }
    rl.DrawTexturePro(entry.texture,
        {f32(source.x), f32(source.y), f32(source.width), f32(source.height)},
        {request.destination.x, request.destination.y,
            request.destination.width, request.destination.height},
        {}, 0, rl.WHITE)
    termattachment.residency_touch(service.store, request.attachment_id)
    playback_visibility_record(service, request.attachment_id)
    service.draw_count += 1
    return true
}

//   Return the borrowing renderer capability for one live display service.
service_renderer :: proc(service: ^Service) -> termattachment.Raster_Renderer {
    if service == nil || service.store == nil { return {} }
    return {user_data = service, draw = service_draw_raster}
}

//   Copy content-free graphics lifecycle counters into a display observation.
service_observe :: proc(service: ^Service, result: ^observe.Display) {
    if service == nil || service.store == nil || result == nil { return }
    result.graphics_transfer_admission_count =
        service.store.diagnostics.transfer_admission_count
    result.graphics_transfer_rejection_count =
        service.store.diagnostics.transfer_rejection_count
    result.graphics_decode_count = service.decode_count
    result.graphics_failure_count = service.failure_count
    result.graphics_cancellation_count = service.cancellation_count
    result.graphics_publication_count = service.publication_count
    result.graphics_stale_completion_count = service.stale_completion_count
    result.graphics_eviction_count = service.eviction_count
    result.graphics_draw_count = service.draw_count
    result.graphics_draw_rejection_count = service.draw_rejection_count
    result.graphics_cpu_byte_count = service.store.cpu_byte_count
    result.graphics_gpu_byte_count = service.store.gpu_byte_count
    result.graphics_animation_decode_byte_count =
        service.store.animation_decode_byte_count
    result.graphics_animated_attachment_count =
        service.store.animated_attachment_count
    result.graphics_animation_admission_count =
        service.store.diagnostics.animation_admission_count
    result.graphics_animation_rejection_count =
        service.store.diagnostics.animation_rejection_count
    result.graphics_gif_preflight_acceptance_count =
        service.parser.gif_preflight_acceptance_count
    result.graphics_gif_preflight_rejection_count =
        service.parser.gif_preflight_rejection_count
    result.graphics_queue_full_count = service.queue_full_count
    result.graphics_playback_transition_count = service.playback_transition_count
    result.graphics_playback_completion_count = service.playback_completion_count
    result.graphics_playback_upload_failure_count =
        service.playback_upload_failure_count
    result.graphics_playback_stale_count = service.playback_stale_count
    result.graphics_visibility_pause_count = service.visibility_pause_count
    result.graphics_visibility_resume_count = service.visibility_resume_count
}

//   Execute one finite CPU preparation without calling raylib or terminal owners.
//
// Returns:
//   - `.Succeeded` only after the exact reserved RGBA output is complete.
prepare_task_execute :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    task := cast(^Prepare_Task)payload
    prepared := termgraphicsprepare.prepare(&task.request, token)
    if taskpool.task_cancellation_requested(token) { return .Cancelled }
    return .Succeeded if prepared else .Failed
}

// Inspect one complete GIF without allocating decoded pixel storage.
gif_preflight_task_execute :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    task := cast(^Gif_Preflight_Task)payload
    task.inspection = termgraphicsprepare.inspect_gif_animation(
        task.input, task.limits, token)
    if taskpool.task_cancellation_requested(token) { return .Cancelled }
    return .Succeeded if task.inspection.valid else .Failed
}

//   Bind one reusable service to terminal-owned parser and attachment storage.
//
// Returns:
//   - True for one nonzero generation and valid owners whose attachment table fits.
service_bind_session :: proc(
    service: ^Service, session_generation: u64,
    parser: ^gfxprotocol.Graphics_Parser_State,
    store: ^termattachment.Store, trace_ring: ^trace.Ring) -> bool {
    if service == nil || session_generation == 0 || parser == nil || store == nil ||
        service.stopped || service.store != nil || parser.store != store ||
        store.limits.attachment_capacity > len(service.textures) {
        return false
    }
    service.session_generation = session_generation
    service.parser = parser
    service.store = store
    service.trace_ring = trace_ring
    return true
}

//   Record one exact-generation texture publication as required presentation evidence.
service_record_publication :: proc(
    service: ^Service, id: termattachment.Attachment_Id) {
    if service.trace_ring == nil { return }
    metrics, found := termattachment.attachment_metrics(service.store, id)
    if !found { return }
    trace.ring_record(service.trace_ring, trace.Event{
        correlation = u64(id.slot),
        generation = id.generation,
        correlation_kind = .Attachment,
        lane = .Presentation,
        kind = .Terminal_Raster_Published,
        flags = {.Required},
        payload = {counts = {
            first = u32(metrics.width),
            second = u32(metrics.height),
        }},
    })
}

// Record one committed animation frame or finite completion without pixel content.
service_record_animation :: proc(
    service: ^Service, id: termattachment.Attachment_Id,
    frame_index: int, completed_cycles: u64, completed: bool) {
    if service.trace_ring == nil || frame_index < 0 { return }
    cycles := u32(completed_cycles)
    if completed_cycles > u64(max(u32)) { cycles = max(u32) }
    trace.ring_record(service.trace_ring, trace.Event{
        timestamp_ns = service.monotonic_ns,
        correlation = u64(id.slot),
        generation = id.generation,
        correlation_kind = .Attachment,
        lane = .Presentation,
        kind = .Animation_Playback_Completed if completed else
            .Animation_Frame_Presented,
        flags = {.Required},
        payload = {counts = {
            first = u32(frame_index + 1),
            second = cycles,
        }},
    })
}

//   Convert protocol-neutral decode metadata into one worker preparation request.
operation_prepare_kind :: proc(
    decode_kind: gfxprotocol.Graphics_Decode_Kind) ->
    (termgraphicsprepare.Prepare_Kind, bool) {
    switch decode_kind {
    case .Kitty_Png, .Iterm2_Image: return .Encoded_Image, true
    case .Iterm2_Animated_Gif: return .Animated_Gif, true
    case .Kitty_Zlib_Rgb: return .Zlib_Rgb, true
    case .Kitty_Zlib_Rgba: return .Zlib_Rgba, true
    case .Sixel: return .Sixel, true
    case .Iterm2_Gif_Preflight: return {}, false
    }
    return {}, false
}

// Bind the pending attachment destinations required by one preparation kind.
operation_prepare_output :: proc(
    service: ^Service, operation: ^Operation,
    kind: termgraphicsprepare.Prepare_Kind) -> Prepare_Output {
    if kind == .Animated_Gif {
        preparation, available := termattachment.animation_preparation_buffer(
            service.store, operation.decode.attachment_id)
        return {preparation.pixels, preparation.frames, available}
    }
    output, available := termattachment.attachment_preparation_buffer(
        service.store, operation.decode.attachment_id)
    return {pixels = output, found = available}
}

//   Convert protocol-neutral decode metadata into one worker preparation request.
//
// Returns:
//   - True after binding live transfer input and pending attachment output.
operation_prepare :: proc(service: ^Service, operation: ^Operation) -> bool {
    input, input_found := termattachment.transfer_bytes(
        service.store, operation.decode.transfer_id)
    if !input_found { return false }
    kind, supported := operation_prepare_kind(operation.decode.kind)
    if !supported { return false }
    destination := operation_prepare_output(service, operation, kind)
    if !destination.found { return false }
    operation.task = {
        session_generation = service.session_generation,
        request = {
            kind = kind,
            input = input,
            width = operation.decode.width,
            height = operation.decode.height,
            output = destination.pixels,
            animation_frames = destination.frames,
            attachment_limits = service.store.limits,
            gif_inspection = operation.preflight.inspection,
            palette = operation.decode.palette,
            palette_count = operation.decode.palette_count,
            transparent_background = operation.decode.transparent_background,
        },
    }
    return true
}

// Bind immutable transfer input and limits for one asynchronous GIF inspection.
operation_preflight_prepare :: proc(
    service: ^Service, operation: ^Operation) -> bool {
    input, found := termattachment.transfer_bytes(
        service.store, operation.decode.transfer_id)
    if !found { return false }
    operation.preflight = {
        session_generation = service.session_generation,
        input = input,
        limits = termgraphicsprepare.gif_animation_limits(service.store.limits),
    }
    return true
}

//   Release all terminal ownership associated with one failed or stale decode.
//
// Side effects:
//   - Removes encoded transfer bytes and discards the pending generation and placements.
operation_discard :: proc(service: ^Service, operation: ^Operation) {
    if operation.decode.transfer_id.generation != 0 {
        termattachment.transfer_remove(service.store, operation.decode.transfer_id)
    }
    if operation.decode.attachment_id.generation != 0 {
        gfxprotocol.graphics_discard_pending_attachment(
            service.parser, operation.decode.attachment_id)
    }
    if operation.decode.mutation_sequence != 0 {
        gfxprotocol.graphics_parser_mark_mutation_ready(
            service.parser, operation.decode.mutation_sequence,
            operation.decode.attachment_id)
    }
}

// Reserve and place the exact target selected by one joined GIF inspection.
operation_preflight_reserve :: proc(
    service: ^Service, operation: ^Operation,
    inspection: termgraphicsprepare.Gif_Animation_Inspection) ->
    (termattachment.Attachment_Id, bool) {
    if inspection.frame_count > 1 {
        id, outcome := termattachment.animation_reserve(service.store, {
            metadata = {
                kind = .Raster,
                origin = .Iterm2,
                metrics = {width = inspection.width, height = inspection.height},
            },
            frame_count = inspection.frame_count,
            payload_byte_count = inspection.decoded_byte_count,
            temporary_decode_byte_count = inspection.temporary_decode_byte_count,
            repeat_count = u32(inspection.repeat_count),
            infinite = inspection.infinite,
        })
        operation.decode.kind = .Iterm2_Animated_Gif
        return id, outcome == .Admitted
    }
    id, status := gfxsemantics.graphics_reserve_pending_attachment(
        service.parser, .Iterm2, inspection.width, inspection.height, false)
    operation.decode.kind = .Iterm2_Image
    return id, status == .Ok
}

// Reserve and place the exact target selected by one joined GIF inspection.
operation_preflight_admit :: proc(
    service: ^Service, operation: ^Operation) -> bool {
    inspection := operation.preflight.inspection
    attachment_id, reserved := operation_preflight_reserve(
        service, operation, inspection)
    if !reserved { return false }
    operation.decode.attachment_id = attachment_id
    if operation.decode.place {
        _, outcome := termattachment.placement_admit(service.store, {
            attachment_id = attachment_id,
            geometry = operation.decode.geometry,
            lifecycle = .Cursor_Anchored,
        })
        if outcome != .Admitted {
            gfxprotocol.graphics_discard_pending_attachment(
                service.parser, attachment_id)
            operation.decode.attachment_id = {}
            return false
        }
    }
    return operation_prepare(service, operation)
}

//   Destroy one cache entry selected by attachment residency policy.
//
// Returns:
//   - True only after finding and unloading the exact native texture.
texture_evict :: proc(user_data: rawptr, id: termattachment.Attachment_Id) -> bool {
    service := cast(^Service)user_data
    if service == nil || id.slot < 0 || id.slot >= len(service.textures) {
        return false
    }
    entry := &service.textures[id.slot]
    if !entry.resident || entry.attachment_id != id ||
        !rl.IsTextureValid(entry.texture) {
        return false
    }
    rl.UnloadTexture(entry.texture)
    entry^ = {}
    service.eviction_count += 1
    return true
}

// Build a borrowed Raylib image over one supported attachment payload.
texture_image :: proc(
    payload: termattachment.Payload_View) -> (rl.Image, bool) {
    bytes_per_pixel: int
    pixel_format: rl.PixelFormat
    switch payload.format {
    case .Rgb8:
        bytes_per_pixel, pixel_format = 3, .UNCOMPRESSED_R8G8B8
    case .Rgba8:
        bytes_per_pixel, pixel_format = 4, .UNCOMPRESSED_R8G8B8A8
    case .Indexed8: return {}, false
    }
    width := payload.stride / bytes_per_pixel
    if width <= 0 || len(payload.bytes) % payload.stride != 0 {
        return {}, false
    }
    return {
        data = raw_data(payload.bytes), width = i32(width),
        height = i32(len(payload.bytes) / payload.stride),
        mipmaps = 1, format = pixel_format,
    }, true
}

// Select the committed current canvas of one exact animated attachment.
texture_animation_payload :: proc(
    service: ^Service, id: termattachment.Attachment_Id) ->
    (termattachment.Payload_View, bool) {
    animation, found := termattachment.animation_view(service.store, id)
    metrics, metrics_found := termattachment.attachment_metrics(service.store, id)
    if !found || !metrics_found || len(animation.frames) == 0 { return {}, false }
    frame_index := 0
    playback := &service.playbacks[id.slot]
    if playback.active && playback.attachment_id == id {
        frame_index = playback.frame_index
    }
    if frame_index < 0 || frame_index >= len(animation.frames) { return {}, false }
    frame := animation.frames[frame_index].pixels
    if frame.offset < 0 || frame.count <= 0 ||
        frame.offset > len(animation.pixels) - frame.count {
        return {}, false
    }
    return {
        bytes = animation.pixels[frame.offset:frame.offset + frame.count],
        format = .Rgba8,
        stride = metrics.width * 4,
    }, true
}

// Select one static payload or the committed current animation canvas.
texture_payload :: proc(
    service: ^Service, id: termattachment.Attachment_Id) ->
    (termattachment.Payload_View, bool) {
    payload, found := termattachment.attachment_payload(service.store, id)
    if found { return payload, true }
    return texture_animation_payload(service, id)
}

// Start playback for one newly resident animated generation without resetting it.
texture_activate_playback :: proc(
    service: ^Service, id: termattachment.Attachment_Id) -> bool {
    animation, found := termattachment.animation_view(service.store, id)
    if !found { return true }
    entry := &service.playbacks[id.slot]
    if entry.active && entry.attachment_id == id { return true }
    candidate, valid := playback_begin(id, animation, service.monotonic_ns)
    if !valid { return false }
    entry^ = candidate
    return true
}

//   Publish one immutable RGBA attachment as an exact display-owned texture.
//
// Returns:
//   - True after residency admission and atomic texture-table publication.
//
// Notes:
//   - Must run on the display thread with a live raylib graphics context.
texture_publish :: proc(
    service: ^Service, id: termattachment.Attachment_Id) -> bool {
    if service == nil || id.slot < 0 || id.slot >= len(service.textures) {
        return false
    }
    payload, found := texture_payload(service, id)
    if !found { return false }
    image, valid := texture_image(payload)
    if !valid { return false }
    admission := termattachment.residency_admit(
        service.store, id, len(payload.bytes), texture_evict, service)
    if admission.outcome != .Admitted { return false }
    candidate := rl.LoadTextureFromImage(image)
    if !rl.IsTextureValid(candidate) {
        termattachment.residency_remove(service.store, id)
        return false
    }
    entry := &service.textures[id.slot]
    if entry.resident && rl.IsTextureValid(entry.texture) {
        rl.UnloadTexture(entry.texture)
    }
    entry^ = {attachment_id = id, texture = candidate, resident = true}
    if !texture_activate_playback(service, id) {
        rl.UnloadTexture(entry.texture)
        entry^ = {}
        termattachment.residency_remove(service.store, id)
        return false
    }
    return true
}

// Upload one complete animation canvas into its stable display-owned texture.
playback_upload_texture :: proc(
    user_data: rawptr, id: termattachment.Attachment_Id,
    pixels: []u8) -> bool {
    service := cast(^Service)user_data
    if service == nil || id.slot < 0 || id.slot >= len(service.textures) {
        return false
    }
    texture := &service.textures[id.slot]
    if !texture.resident || texture.attachment_id != id ||
        !rl.IsTextureValid(texture.texture) || len(pixels) !=
            int(texture.texture.width) * int(texture.texture.height) * 4 {
        return false
    }
    rl.UpdateTexture(texture.texture, raw_data(pixels))
    return true
}

// Upload one selected full canvas from an exact live animation generation.
playback_upload_frame :: proc(
    service: ^Service, id: termattachment.Attachment_Id,
    animation: termattachment.Animation_View, frame_index: int,
    upload: Playback_Upload) -> bool {
    if frame_index < 0 || frame_index >= len(animation.frames) ||
        upload.handler == nil {
        return false
    }
    frame := animation.frames[frame_index].pixels
    return frame.offset >= 0 && frame.count > 0 &&
        frame.offset <= len(animation.pixels) - frame.count &&
        upload.handler(upload.user_data, id,
            animation.pixels[frame.offset:frame.offset + frame.count])
}

// Build one Kitty-selected playback candidate without changing committed state.
playback_command_candidate :: proc(
    entry: Playback_Entry, command: gfxprotocol.Kitty_Animation_Command,
    animation: termattachment.Animation_View, now_ns: u64) ->
    (Playback_Entry, bool) {
    candidate := entry
    if candidate.frame_index >= len(animation.frames) {
        candidate.frame_index = len(animation.frames) - 1
    }
    if command.current_frame > 0 {
        if command.current_frame > len(animation.frames) { return entry, false }
        candidate.frame_index = command.current_frame - 1
    }
    if command.kind == .Control {
        switch command.animation_state {
        case 0:
        case 1:
            candidate.stopped = true
            candidate.loading = false
            candidate.completed = false
            candidate.completed_cycles = 0
        case 2:
            candidate.stopped = false
            candidate.loading = true
            candidate.completed = false
        case 3:
            candidate.stopped = false
            candidate.loading = false
            candidate.completed = false
        case: return entry, false
        }
    }
    candidate.deadline_ns = playback_deadline(
        now_ns, animation.frames[candidate.frame_index].duration_ns)
    return candidate, true
}

// Apply one retained Kitty animation effect after exact-generation validation.
playback_apply_command :: proc(
    service: ^Service, command: gfxprotocol.Kitty_Animation_Command,
    now_ns: u64, upload: Playback_Upload_Handler, user_data: rawptr) {
    id := command.attachment_id
    if id.slot < 0 || id.slot >= len(service.playbacks) { return }
    animation, found := termattachment.animation_view(service.store, id)
    if !found { return }
    entry := &service.playbacks[id.slot]
    if !entry.active || entry.attachment_id != id {
        candidate, valid := playback_begin(id, animation, now_ns)
        if !valid { return }
        candidate.stopped = true
        entry^ = candidate
    }
    candidate, valid := playback_command_candidate(
        entry^, command, animation, now_ns)
    if !valid { return }
    if !playback_upload_frame(
        service, id, animation, candidate.frame_index,
        {handler = upload, user_data = user_data}) {
        service.playback_upload_failure_count += 1
        return
    }
    entry^ = candidate
    service_record_animation(service, id, candidate.frame_index,
        candidate.completed_cycles, false)
}

// Consume retained Kitty animation effects in terminal stream order.
playback_apply_commands :: proc(service: ^Service, now_ns: u64) {
    for {
        command, available := gfxprotocol.graphics_parser_take_animation_command(
            service.parser)
        if !available { return }
        playback_apply_command(
            service, command, now_ns, playback_upload_texture, service)
    }
}

// Advance one exact-generation playback entry and commit only after upload succeeds.
playback_commit_plan :: proc(
    service: ^Service, entry: ^Playback_Entry, plan: Playback_Plan) {
    service.playback_transition_count += u64(plan.transition_count)
    completed_now := !entry.completed && plan.candidate.completed
    if completed_now { service.playback_completion_count += 1 }
    entry^ = plan.candidate
    if plan.frame_changed {
        service_record_animation(service, entry.attachment_id, entry.frame_index,
            entry.completed_cycles, false)
    }
    if completed_now {
        service_record_animation(service, entry.attachment_id, entry.frame_index,
            entry.completed_cycles, true)
    }
}

// Advance one exact-generation playback entry and commit only after upload succeeds.
playback_update_entry :: proc(
    service: ^Service, entry: ^Playback_Entry, now_ns: u64,
    upload: Playback_Upload_Handler, user_data: rawptr) {
    if !entry.active { return }
    animation, found := termattachment.animation_view(
        service.store, entry.attachment_id)
    if !found {
        service.playback_stale_count += 1
        entry^ = {}
        return
    }
    plan := playback_plan(entry^, animation, now_ns)
    if !plan.valid { return }
    if plan.frame_changed {
        frame := animation.frames[plan.candidate.frame_index].pixels
        if frame.offset < 0 || frame.count <= 0 ||
            frame.offset > len(animation.pixels) - frame.count || upload == nil ||
            !upload(user_data, entry.attachment_id,
                animation.pixels[frame.offset:frame.offset + frame.count]) {
            service.playback_upload_failure_count += 1
            return
        }
    }
    playback_commit_plan(service, entry, plan)
}

// Advance every fixed playback slot with bounded per-entry transition work.
playback_update_all :: proc(service: ^Service, now_ns: u64) {
    for &entry in service.playbacks {
        playback_update_entry(
            service, &entry, now_ns, playback_upload_texture, service)
    }
}

//   Publish prepared generations that bypass asynchronous decode, such as Kitty raw data.
//
// Notes:
//   - Scans only the fixed attachment table and runs on the display thread.
//   - Failed publication discards protocol identity and placement state exactly once.
texture_publish_prepared_all :: proc(service: ^Service) {
    for slot in 0..<service.store.limits.attachment_capacity {
        id, prepared := termattachment.attachment_prepared_id_at(
            service.store, slot)
        if !prepared { continue }
        entry := &service.textures[slot]
        if entry.resident && entry.attachment_id == id { continue }
        if texture_publish(service, id) {
            service.publication_count += 1
            service_record_publication(service, id)
        } else {
            service.failure_count += 1
            gfxprotocol.graphics_discard_attachment(service.parser, id)
        }
    }
}

// Commit one joined decode through its matching static or animation publication path.
//
// Returns:
//   - `.Found` only when the exact pending generation becomes atomically visible.
operation_preparation_publish :: proc(
    service: ^Service, decode: gfxprotocol.Graphics_Decode_Request) ->
    termattachment.Handle_Outcome {
    if decode.kind == .Iterm2_Animated_Gif {
        return termattachment.animation_preparation_publish(
            service.store, decode.attachment_id)
    }
    return termattachment.attachment_preparation_publish(
        service.store, decode.attachment_id)
}

// Publish one successfully decoded attachment or record its rejection.
operation_publish :: proc(
    service: ^Service, decode: gfxprotocol.Graphics_Decode_Request) {
    outcome := operation_preparation_publish(service, decode)
    if decode.mutation_sequence != 0 {
        if outcome != .Found {
            service.stale_completion_count += 1
            gfxprotocol.graphics_discard_pending_attachment(
                service.parser, decode.attachment_id)
        }
        gfxprotocol.graphics_parser_mark_mutation_ready(
            service.parser, decode.mutation_sequence, decode.attachment_id)
        return
    }
    if outcome != .Found {
        service.stale_completion_count += 1
        gfxprotocol.graphics_discard_pending_attachment(
            service.parser, decode.attachment_id)
    } else if texture_publish(service, decode.attachment_id) {
        if decode.kind == .Sixel && decode.place {
            geometry := decode.geometry
            termattachment.placements_remove_resident_position_origin_except(
                service.store, geometry, .Sixel, decode.attachment_id)
        }
        service.publication_count += 1
        service_record_publication(service, decode.attachment_id)
    } else {
        service.failure_count += 1
        gfxprotocol.graphics_discard_pending_attachment(
            service.parser, decode.attachment_id)
    }
}

// Commit every ready Kitty store mutation in retained terminal stream order.
operation_apply_mutations :: proc(service: ^Service) {
    for {
        request, available := gfxprotocol.graphics_parser_take_mutation_request(
            service.parser)
        if !available { return }
        status := gfxsemantics.graphics_kitty_apply_mutation_request(
            service.parser, request)
        if status != .Ok { service.failure_count += 1 }
    }
}

//   Consume one joined task result and release its operation slot.
//
// Side effects:
//   - Removes transfer ownership, rejects stale generations, and may publish a texture.
operation_finish :: proc(
    service: ^Service, operation: ^Operation,
    result: taskpool.Task_Result, joined: taskpool.Task_Join_Outcome) {
    if operation.task.session_generation != service.session_generation {
        service.stale_completion_count += 1
        operation^ = {}
        return
    }
    if joined == .Joined && result == .Cancelled {
        service.cancellation_count += 1
        operation_discard(service, operation)
        operation^ = {}
        return
    }
    termattachment.transfer_remove(service.store, operation.decode.transfer_id)
    if service.unbinding {
        gfxprotocol.graphics_discard_pending_attachment(
            service.parser, operation.decode.attachment_id)
        operation^ = {}
        return
    }
    if joined != .Joined || result != .Succeeded {
        service.failure_count += 1
        gfxprotocol.graphics_discard_pending_attachment(
            service.parser, operation.decode.attachment_id)
        operation^ = {}
        return
    }
    service.decode_count += 1
    operation_publish(service, operation.decode)
    operation^ = {}
}

// Consume one joined GIF inspection and transition its slot into decode retry.
operation_preflight_finish :: proc(
    service: ^Service, operation: ^Operation,
    result: taskpool.Task_Result, joined: taskpool.Task_Join_Outcome) {
    if operation.preflight.session_generation != service.session_generation {
        service.stale_completion_count += 1
        operation_discard(service, operation)
        operation^ = {}
        return
    }
    if joined == .Joined && result == .Cancelled {
        service.cancellation_count += 1
        operation_discard(service, operation)
        operation^ = {}
        return
    }
    if service.unbinding || joined != .Joined || result != .Succeeded {
        if !service.unbinding {
            service.failure_count += 1
            service.parser.gif_preflight_rejection_count += 1
        }
        operation_discard(service, operation)
        operation^ = {}
        return
    }
    service.parser.gif_preflight_acceptance_count += 1
    if !operation_preflight_admit(service, operation) {
        service.failure_count += 1
        operation_discard(service, operation)
        operation^ = {}
        return
    }
    operation.state = .Retry
    operation.handle = {}
}

//   Join every ready operation without waiting on pending work.
operation_poll_all :: proc(service: ^Service, pool: ^taskpool.Task_Pool) {
    for &operation in service.operations {
        if operation.state != .Queued && operation.state != .Preflight_Queued {
            continue
        }
        poll := taskpool.task_pool_poll(pool, operation.handle)
        if poll == .Pending {
            service.pending_poll_count += 1
            continue
        }
        result, joined := taskpool.task_pool_wait(pool, operation.handle)
        if operation.state == .Preflight_Queued {
            operation_preflight_finish(service, &operation, result, joined)
        } else {
            operation_finish(service, &operation, result, joined)
        }
    }
}

//   Fill idle operation slots from the terminal decode queue.
operation_intake :: proc(service: ^Service) {
    if service.unbinding || service.stopped { return }
    for &operation in service.operations {
        if operation.state != .Idle { continue }
        request, available := gfxprotocol.graphics_parser_take_decode_request(
            service.parser)
        if !available { return }
        operation.decode = request
        if request.kind == .Iterm2_Gif_Preflight &&
            operation_preflight_prepare(service, &operation) {
            operation.state = .Preflight_Retry
        } else if request.kind != .Iterm2_Gif_Preflight &&
            operation_prepare(service, &operation) {
            operation.state = .Retry
        } else {
            service.failure_count += 1
            operation_discard(service, &operation)
            operation = {}
        }
    }
}

//   Attempt bounded submissions while retaining ownership on queue pressure.
operation_submit_all :: proc(service: ^Service, pool: ^taskpool.Task_Pool) {
    for &operation in service.operations {
        if operation.state != .Retry && operation.state != .Preflight_Retry {
            continue
        }
        preflight := operation.state == .Preflight_Retry
        handle, outcome := taskpool.task_pool_submit(pool,
            gif_preflight_task_execute if preflight else prepare_task_execute,
            &operation.preflight if preflight else &operation.task)
        switch outcome {
        case .Queued:
            operation.handle = handle
            operation.state = .Preflight_Queued if preflight else .Queued
        case .Queue_Full:
            service.queue_full_count += 1
        case .Pool_Stopped:
            service.failure_count += 1
            operation_discard(service, &operation)
            operation = {}
        }
    }
}

//   Complete deferred deletions after unloading their display-owned textures.
texture_service_removals :: proc(service: ^Service) {
    for &entry in service.textures {
        if !entry.resident || !termattachment.attachment_removal_requested(
            service.store, entry.attachment_id) {
            continue
        }
        id := entry.attachment_id
        if texture_evict(service, id) {
            termattachment.residency_remove(service.store, id)
            termattachment.attachment_remove(service.store, id)
        }
    }
}

//   Advance decode submission, joining, publication, eviction, and deletion once.
//
// Notes:
//   - Must be called only by the display owner while the raylib context is live.
service_update :: proc(
    service: ^Service, pool: ^taskpool.Task_Pool, monotonic_ns: u64) {
    if service == nil || service.store == nil || pool == nil { return }
    service.monotonic_ns = monotonic_ns
    texture_service_removals(service)
    playback_visibility_begin_frame(service, monotonic_ns)
    operation_poll_all(service, pool)
    playback_apply_commands(service, monotonic_ns)
    operation_apply_mutations(service)
    texture_publish_prepared_all(service)
    playback_apply_commands(service, monotonic_ns)
    playback_update_all(service, monotonic_ns)
    operation_intake(service)
    operation_submit_all(service, pool)
}

//   Cancel unpublished graphics work from one exact terminal producer.
//
// Parameters:
//   - service: Bound display graphics service owning queued decode operations.
//   - producer: Exact output producer whose work must no longer publish.
//
// Side effects:
//   - Discards matching parser and retry work immediately. Submitted workers retain
//     their borrowed buffers until normal join, when their output is discarded.
//   - Leaves every resident attachment and texture unchanged.
service_cancel_producer :: proc(
    service: ^Service, pool: ^taskpool.Task_Pool,
    producer: termmodel.Terminal_Producer) {
    if service == nil || pool == nil || service.parser == nil || service.store == nil ||
        producer.kind == .None {
        return
    }
    queued_count := service.parser.decode_request_count
    for _ in 0..<queued_count {
        request, available := gfxprotocol.graphics_parser_take_decode_request(
            service.parser)
        if !available { break }
        if request.producer == producer {
            operation := Operation{decode = request}
            operation_discard(service, &operation)
        } else if !gfxprotocol.graphics_parser_queue_decode_request(
            service.parser, request) {
            service.failure_count += 1
            operation := Operation{decode = request}
            operation_discard(service, &operation)
        }
    }
    for &operation in service.operations {
        if operation.decode.producer != producer {
            continue
        }
        if operation.state == .Retry || operation.state == .Preflight_Retry {
            operation_discard(service, &operation)
            operation = {}
        } else if operation.state == .Queued ||
            operation.state == .Preflight_Queued {
            taskpool.task_pool_cancel(pool, operation.handle)
        }
    }
}

// Reject every decode request still waiting in the parser queue.
service_discard_parser_requests :: proc(service: ^Service) {
    for {
        request, available := gfxprotocol.graphics_parser_take_decode_request(
            service.parser)
        if !available { return }
        operation := Operation{decode = request}
        operation_discard(service, &operation)
    }
}

// Discard retry operations and join every queued graphics decode operation.
service_finish_operations :: proc(
    service: ^Service, pool: ^taskpool.Task_Pool) {
    for &operation in service.operations {
        if operation.state == .Retry || operation.state == .Preflight_Retry {
            operation_discard(service, &operation)
            operation = {}
        }
    }
    for &operation in service.operations {
        if operation.state == .Queued || operation.state == .Preflight_Queued {
            taskpool.task_pool_cancel(pool, operation.handle)
        }
    }
    for &operation in service.operations {
        if operation.state != .Queued && operation.state != .Preflight_Queued {
            continue
        }
        result, joined := taskpool.task_pool_wait(pool, operation.handle)
        if operation.state == .Preflight_Queued {
            operation_preflight_finish(service, &operation, result, joined)
        } else {
            operation_finish(service, &operation, result, joined)
        }
    }
}

// Unload every resident texture and remove its residency accounting.
service_unload_textures :: proc(service: ^Service) {
    for &entry in service.textures {
        if !entry.resident { continue }
        id := entry.attachment_id
        texture_evict(service, id)
        termattachment.residency_remove(service.store, id)
    }
}

//   Unbind one session after quiescing work and destroying every native texture.
//
// Side effects:
//   - Rejects parser work, joins accepted tasks, unloads cache entries, and clears all
//     borrowed session pointers while leaving the service reusable.
service_unbind_session :: proc(service: ^Service, pool: ^taskpool.Task_Pool) {
    if service == nil || service.store == nil || pool == nil { return }
    service.unbinding = true
    service_discard_parser_requests(service)
    service_finish_operations(service, pool)
    gfxprotocol.graphics_parser_cancel_all_mutation_requests(service.parser)
    service_unload_textures(service)
    service.parser = nil
    service.store = nil
    service.trace_ring = nil
    service.session_generation = 0
    service.monotonic_ns = 0
    service.visibility_epoch = 0
    service.playbacks = {}
    service.unbinding = false
}

// Permanently stop the graphics service after unbinding its current session.
service_shutdown :: proc(service: ^Service, pool: ^taskpool.Task_Pool) {
    if service == nil { return }
    service_unbind_session(service, pool)
    service.stopped = true
}