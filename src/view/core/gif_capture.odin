package view_core

import viewmodel "../model"
import dyncore "../../dynview/core"

// GIFs are captured only from the view area, excluding the UI. The current session for the
// GIF is always stored on the general state for the application. We need to wait until a
// new animation cycle begins, record it into a gif, and when the cycle completes, write it
// out to a new GIF file.

import "../../core"

import "core:log"
import "core:time"

Gif_Capture_Session :: viewmodel.Gif_Capture_Session
Gif_Capture_Frame :: viewmodel.Gif_Capture_Frame
Gif_Capture_Operations :: viewmodel.Gif_Capture_Operations

GIF_MIN_DELAY_MS :: u64(10)
GIF_MAX_DELAY_MS :: u64(655_350)

//   Logical, screen, and render extents used to resolve a framebuffer crop.
Gif_Capture_Extents :: struct {
    logical_width: int,
    logical_height: int,
    screen_width: int,
    screen_height: int,
    render_width: int,
    render_height: int,
}

//   Freeze one framebuffer crop for the complete active GIF session.
gif_capture_freeze_source_dimensions :: proc(
    session: ^Gif_Capture_Session, width, height: int) {

    session.source_width = max(1, width)
    session.source_height = max(1, height)
}

//   Clear the framebuffer crop owned by a completed or aborted GIF session.
gif_capture_clear_source_dimensions :: proc(session: ^Gif_Capture_Session) {
    session.source_width = 0
    session.source_height = 0
    session.output_width = 0
    session.output_height = 0
    session.staged = false
    session.staged_fixed_step = 0
    session.staged_at = {}
    session.last_duration_ms = 0
}

//   Bind display-owned streaming encoder operations to one portable session.
gif_capture_bind_operations :: proc(
    session: ^Gif_Capture_Session, operations: Gif_Capture_Operations) -> bool {
    if session == nil || operations.begin == nil ||
       operations.stage_frame == nil || operations.commit_frame == nil ||
       operations.close == nil || operations.abort == nil ||
       operations.published_path == nil {
        return false
    }
    session.operations = operations
    return true
}


//   Clear transient GIF status note displayed in the settings panel.
clear_gif_status_note :: proc(ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    ui_runtime.gif_status_note_len = 0
    ui_runtime.gif_status_note[0] = 0
}

//   Store a transient GIF status note displayed in the settings panel.
set_gif_status_note :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, note: string) {
    max_len := len(ui_runtime.gif_status_note) - 1
    n := min(len(note), max_len)

    for i in 0..<n {
        ui_runtime.gif_status_note[i] = note[i]
    }

    ui_runtime.gif_status_note[n] = 0
    ui_runtime.gif_status_note_len = n
}

//   Cancel active/pending GIF capture and publish a human-readable reason.
cancel_gif_capture_with_note :: proc(state: ^core.Euclid_General_State, note: string) {
    if state^.gif_capture.active {
        gif_capture_abort_session(&state^.gif_capture)
    }

    ui_runtime := &state^.ui_runtime
    ui_runtime.gif_capture_phase = .Idle
    ui_runtime.gif_capture_frame_counter = 0
    ui_runtime.gif_captured_frames = 0
    clear_last_gif_path(ui_runtime)
    set_gif_status_note(ui_runtime, note)
}

//   Load the framebuffer and normalize it through the supplied native operations.
//
// Parameters:
//   - state: Global app state providing capture config and encoder state.
//   - downsample: Integer downsample factor, 1 meaning no downsample.
//
// Returns:
//   - frame: Capture pixels owned by the caller; release with framebuffer_release.
//   - ok: true when a usable frame was captured.
gif_capture_normalized_frame_with_operations :: proc(
    state: ^core.Euclid_General_State,
    downsample: int,
    operations: Framebuffer_Capture_Operations) -> (Framebuffer_Pixels, bool) {

    capture_w := max(1, state^.gif_capture.source_width)
    capture_h := max(1, state^.gif_capture.source_height)

    frame, frame_ok := framebuffer_acquire_with_operations(operations)
    if !frame_ok {
        return {}, false
    }

    crop_w := min(capture_w, frame.width)
    crop_h := min(capture_h, frame.height)
    if !framebuffer_crop_with_operations(
        &frame, crop_w, crop_h, operations) {
        framebuffer_release_with_operations(&frame, operations)
        return {}, false
    }

    if downsample > 1 {
        out_w := max(1, frame.width / downsample)
        out_h := max(1, frame.height / downsample)
        if !framebuffer_resize_with_operations(
            &frame, out_w, out_h, operations) {
            framebuffer_release_with_operations(&frame, operations)
            return {}, false
        }
    }

    expected_w := state^.gif_capture.output_width
    expected_h := state^.gif_capture.output_height
    if frame.width != expected_w || frame.height != expected_h {
        // Keep capture frames aligned with encoder dimensions so pitch-based reads stay valid.
        if !framebuffer_resize_with_operations(
            &frame, expected_w, expected_h, operations) {
            framebuffer_release_with_operations(&frame, operations)
            return {}, false
        }
    }

    return frame, true
}

// gif_capture_stage_frame copies one normalized frame into encoder-owned storage.
gif_capture_stage_frame :: proc(
    state: ^core.Euclid_General_State, frame: ^Framebuffer_Pixels,
    fixed_step: u64, sampled_at: time.Tick) -> bool {
    encoder := state^.gif_capture.operations
    if encoder.stage_frame == nil || !encoder.stage_frame(
        encoder.user_data, {
            pixels = frame^.pixels,
            width = frame^.width,
            height = frame^.height,
            pitch_bytes = frame^.pitch_bytes,
        }) {
        return false
    }
    state^.gif_capture.staged = true
    state^.gif_capture.staged_fixed_step = fixed_step
    state^.gif_capture.staged_at = sampled_at
    return true
}

// gif_capture_fixed_step_duration_ms converts deterministic progress to GIF time.
gif_capture_fixed_step_duration_ms :: #force_inline proc(fixed_steps: u64) -> u64 {
    if fixed_steps == 0 {return 0}
    saturation_steps := GIF_MAX_DELAY_MS * u64(LIMIT_FPS) / 1000
    if fixed_steps >= saturation_steps {return GIF_MAX_DELAY_MS}
    duration_ms := (fixed_steps * 1000 + u64(LIMIT_FPS / 2)) / u64(LIMIT_FPS)
    return clamp(duration_ms, GIF_MIN_DELAY_MS, GIF_MAX_DELAY_MS)
}

// gif_capture_elapsed_duration_ms converts monotonic elapsed seconds to GIF time.
gif_capture_elapsed_duration_ms :: #force_inline proc(seconds: f64) -> u64 {
    if seconds <= 0 {return 0}
    if seconds >= f64(GIF_MAX_DELAY_MS) / 1000 {return GIF_MAX_DELAY_MS}
    return clamp(u64(seconds * 1000 + 0.5), GIF_MIN_DELAY_MS, GIF_MAX_DELAY_MS)
}

// gif_capture_nominal_duration_ms returns one frozen cadence interval.
gif_capture_nominal_duration_ms :: #force_inline proc(frame_step: int) -> u64 {
    return gif_capture_fixed_step_duration_ms(u64(max(1, frame_step)))
}

// gif_capture_commit_staged_frame resolves and commits the prior frame interval.
gif_capture_commit_staged_frame :: proc(
    state: ^core.Euclid_General_State, fixed_step: u64) -> bool {
    session := &state^.gif_capture
    if !session.staged {return true}
    duration_ms: u64
    switch session.active_timing_mode {
    case .Animation:
        if fixed_step >= session.staged_fixed_step {
            duration_ms = gif_capture_fixed_step_duration_ms(
                fixed_step - session.staged_fixed_step)
        }
    case .Recorded:
        duration_ms = gif_capture_elapsed_duration_ms(
            time.duration_seconds(time.tick_since(session.staged_at)))
    }
    if duration_ms == 0 {
        duration_ms = session.last_duration_ms
    }
    if duration_ms == 0 {
        duration_ms = gif_capture_nominal_duration_ms(session.active_frame_step)
    }
    encoder := session.operations
    if encoder.commit_frame == nil ||
       !encoder.commit_frame(encoder.user_data, duration_ms) {
        return false
    }
    session.staged = false
    session.last_duration_ms = duration_ms
    state^.ui_runtime.gif_captured_frames += 1
    return true
}

//   Capture the current view, optionally downsample, and submit it to GIF encoder.
//
// Parameters:
//   - state: Global app state providing capture config and encoder state.
//
// Returns:
//   - ok: true when the frame is accepted or intentionally skipped by frame-step logic.
gif_capture_submit_frame :: proc(
    state: ^core.Euclid_General_State,
    operations: Framebuffer_Capture_Operations) -> bool {
    if !state^.gif_capture.active {
        return false
    }

    ui_runtime := &state.ui_runtime
    frame_step := state^.gif_capture.active_frame_step

    ui_runtime.gif_capture_frame_counter += 1
    if (ui_runtime.gif_capture_frame_counter - 1) % frame_step != 0 {
        return true
    }

    sampled_fixed_step := state^.fixed_step
    sampled_at := time.tick_now()
    if !gif_capture_commit_staged_frame(state, sampled_fixed_step) {
        return false
    }

    downsample := state^.gif_capture.active_downsample_factor
    capture_started_at := time.tick_now()
    frame, frame_ok := gif_capture_normalized_frame_with_operations(
        state, downsample, operations)
    state^.gif_capture.frame_materialization_ms +=
        time.duration_seconds(time.tick_since(capture_started_at)) * 1000
    state^.gif_capture.materialized_frames += 1
    if !frame_ok {
        return false
    }
    defer framebuffer_release_with_operations(&frame, operations)

    return gif_capture_stage_frame(state, &frame, sampled_fixed_step, sampled_at)
}

//   Advance GIF capture state machine on fixed-step cycle boundaries.
//
// Parameters:
//   - state: Global app state holding GIF capture runtime flags and counters.
//
// Returns:
//   - none.
gif_capture_update_fixed_step :: proc(
    state: ^core.Euclid_General_State, extents: Gif_Capture_Extents) {
    ui_runtime := &state.ui_runtime

    // A save request either cancels an Armed capture or arms a fresh one.
    if ui_runtime.save_gif_requested {
        ui_runtime.save_gif_requested = false
        if ui_runtime.gif_capture_phase == .Armed {
            ui_runtime.gif_capture_phase = .Idle
            ui_runtime.gif_captured_frames = 0
            ui_runtime.gif_capture_frame_counter = 0
            clear_gif_status_note(ui_runtime)
            return
        }
        if ui_runtime.gif_capture_phase != .Recording &&
            ui_runtime.gif_capture_phase != .Finalizing {
            ui_runtime.gif_capture_phase = .Armed
            ui_runtime.gif_captured_frames = 0
            ui_runtime.gif_capture_frame_counter = 0
            clear_last_gif_path(ui_runtime)
            clear_gif_status_note(ui_runtime)
        }
    }

    if !gif_capture_consume_cycle_boundary(state) {
        return
    }

    switch ui_runtime.gif_capture_phase {
    case .Idle, .Finalizing, .Saved, .Error:
    case .Armed:
        gif_capture_advance_armed(state, ui_runtime, extents)
    case .Recording:
        gif_capture_advance_recording(state, ui_runtime)
    }
}

//   Advance the Armed phase: begin a capture session or record the failure.
gif_capture_advance_armed :: proc(
    state: ^core.Euclid_General_State, ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    extents: Gif_Capture_Extents) {
    if gif_capture_begin_session(state, extents) {
        ui_runtime.gif_capture_phase = .Recording
        clear_gif_status_note(ui_runtime)
    } else {
        ui_runtime.gif_capture_phase = .Error
        set_gif_status_note(ui_runtime, "Error: failed to begin GIF capture session.")
    }
}

//   Advance the Recording phase: finalize the file or record the failure.
gif_capture_advance_recording :: proc(
    state: ^core.Euclid_General_State, ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    ui_runtime.gif_capture_phase = .Finalizing
    if gif_capture_finalize_session(state) {
        ui_runtime.gif_capture_phase = .Saved
        clear_gif_status_note(ui_runtime)
    } else {
        ui_runtime.gif_capture_phase = .Error
        set_gif_status_note(ui_runtime, "Error: failed to finalize GIF file.")
    }
}

//   Abort active GIF capture and release any accumulated encoder output.
//
// Parameters:
//   - session: Capture session to abort.
//
// Returns:
//   - none.
gif_capture_abort_session :: proc(session: ^Gif_Capture_Session) {
    if session.active {
        if session.operations.abort != nil {
            session.operations.abort(session.operations.user_data)
        }
    }
    if session.active {
        log.infof(
            "gif_capture_summary outcome=aborted frames=%d presentations=%d " +
            "paused=%d materialization_ms=%.3f",
            session.materialized_frames, session.recording_presentations,
            session.paused_presentations, session.frame_materialization_ms)
    }
    session.active = false
    gif_capture_clear_source_dimensions(session)
}

//   Destroy GIF capture session resources and detach native operations.
//
// Parameters:
//   - session: Capture session to teardown before app shutdown.
//
// Returns:
//   - none.
gif_capture_destroy_session :: proc(session: ^Gif_Capture_Session) {
    if session == nil {
        return
    }

    gif_capture_abort_session(session)
    if session.operations.abort != nil {
        session.operations.abort(session.operations.user_data)
    }
    session.operations = {}
    session.active = false
}






//   Clear stored UI path text for last saved GIF output.
clear_last_gif_path :: proc(ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    ui_runtime.last_gif_path_len = 0
    ui_runtime.last_gif_path[0] = 0
    ui_runtime.last_gif_path_revision += 1
    ui_runtime.last_gif_path_truncated = false
}

//   Store saved GIF output path into fixed UI buffer fields.
set_last_gif_path :: proc(ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State, path: string) {
    max_len := len(ui_runtime.last_gif_path) - 1
    n := min(len(path), max_len)
    for n > 0 && n < len(path) && dyncore.text_is_utf8_trailing_byte(path[n]) {
        n -= 1
    }
    for i in 0..<n {
        ui_runtime.last_gif_path[i] = path[i]
    }
    ui_runtime.last_gif_path[n] = 0
    ui_runtime.last_gif_path_len = n
    ui_runtime.last_gif_path_revision += 1
    ui_runtime.last_gif_path_truncated = n < len(path)
}

//   Map one logical axis extent into framebuffer pixels using screen/render sizes.
gif_capture_scaled_extent :: #force_inline proc(
    logical_extent, screen_extent, render_extent: int) -> int {
    if logical_extent <= 0 {
        return 1
    }

    safe_screen := max(1, screen_extent)
    safe_render := max(1, render_extent)
    scaled := (logical_extent * safe_render + safe_screen / 2) / safe_screen
    return max(1, scaled)
}

//   Scale logical world dimensions into bounded framebuffer capture dimensions.
gif_capture_source_dimensions_for_framebuffer :: proc(
    extents: Gif_Capture_Extents) -> (int, int) {

    capture_w := gif_capture_scaled_extent(
        extents.logical_width, extents.screen_width, extents.render_width)
    capture_h := gif_capture_scaled_extent(
        extents.logical_height, extents.screen_height, extents.render_height)

    capture_w = min(capture_w, extents.render_width)
    capture_h = min(capture_h, extents.render_height)
    return capture_w, capture_h
}

//   Initialize encoder and counters for a new GIF capture session.
//
// Notes:
//   - Initializes encoder output size from current downsample settings.
gif_capture_begin_session :: proc(
    state: ^core.Euclid_General_State, extents: Gif_Capture_Extents) -> bool {
    ui_runtime := &state.ui_runtime
    capture_w, capture_h := gif_capture_source_dimensions_for_framebuffer(extents)
    downsample := clamp(ui_runtime.gif_downsample_factor, 1, 4)
    out_w := max(1, capture_w / downsample)
    out_h := max(1, capture_h / downsample)

    encoder := state^.gif_capture.operations
    if encoder.begin == nil || !encoder.begin(encoder.user_data, out_w, out_h) {
        return false
    }

    state^.gif_capture.active = true
    state^.gif_capture.output_width = out_w
    state^.gif_capture.output_height = out_h
    state^.gif_capture.started_at = time.tick_now()
    state^.gif_capture.active_downsample_factor = downsample
    state^.gif_capture.active_frame_step = clamp(ui_runtime.gif_frame_step, 1, 4)
    state^.gif_capture.active_timing_mode = ui_runtime.gif_timing_mode
    state^.gif_capture.staged = false
    state^.gif_capture.staged_fixed_step = 0
    state^.gif_capture.staged_at = {}
    state^.gif_capture.last_duration_ms = 0
    state^.gif_capture.frame_materialization_ms = 0
    state^.gif_capture.materialized_frames = 0
    state^.gif_capture.recording_presentations = 0
    state^.gif_capture.paused_presentations = 0
    gif_capture_freeze_source_dimensions(
        &state^.gif_capture, capture_w, capture_h)
    ui_runtime.gif_capture_frame_counter = 0
    ui_runtime.gif_captured_frames = 0
    return true
}

//   Finalize and atomically publish streaming encoder output.
//
// Notes:
//   - The native owner publishes only after the encoder closes successfully.
gif_capture_finalize_session :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if !state^.gif_capture.active {
        return false
    }

    if !gif_capture_commit_staged_frame(state, state^.fixed_step) {
        gif_capture_abort_session(&state^.gif_capture)
        return false
    }
    encoder := state^.gif_capture.operations
    closed := encoder.close != nil && encoder.close(encoder.user_data)
    state^.gif_capture.active = false
    gif_capture_clear_source_dimensions(&state^.gif_capture)
    if !closed || encoder.published_path == nil {
        return false
    }
    path := encoder.published_path(encoder.user_data)
    if len(path) == 0 {
        return false
    }

    set_last_gif_path(&state.ui_runtime, path)
    log.infof(
        "gif_capture_summary outcome=saved frames=%d presentations=%d paused=%d " +
        "materialization_ms=%.3f total_ms=%.3f",
        state^.gif_capture.materialized_frames,
        state^.gif_capture.recording_presentations,
        state^.gif_capture.paused_presentations,
        state^.gif_capture.frame_materialization_ms,
        time.duration_seconds(time.tick_since(state^.gif_capture.started_at)) * 1000)
    return true
}

//   Consume one pending cycle-boundary generation marker exactly once.
gif_capture_consume_cycle_boundary :: proc(state: ^core.Euclid_General_State) -> bool {
    if state.consumed_cycle_boundary_generation == state.cycle_boundary_generation {
        return false
    }
    state.consumed_cycle_boundary_generation = state.cycle_boundary_generation
    return true
}
