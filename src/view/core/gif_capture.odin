package view_core

// GIFs are captured only from the view area, excluding the UI. The current session for the
// GIF is always stored on the general state for the application. We need to wait until a
// new animation cycle begins, record it into a gif, and when the cycle completes, write it
// out to a new GIF file.

import "../../core"
import "../../files"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:time"

import rl "vendor:raylib"

GIF_CAPTURE_QUALITY :: 12

Gif_Capture_Session :: core.Gif_Capture_Session


//   Clear transient GIF status note displayed in the settings panel.
clear_gif_status_note :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    ui_runtime.gif_status_note_len = 0
    ui_runtime.gif_status_note[0] = 0
}

//   Store a transient GIF status note displayed in the settings panel.
set_gif_status_note :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State, note: string) {
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

//   Capture the current view, optionally downsample, and submit it to GIF encoder.
//
// Parameters:
//   - state: Global app state providing capture config and encoder state.
//
// Returns:
//   - ok: true when the frame is accepted or intentionally skipped by frame-step logic.
gif_capture_submit_frame :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if !state^.gif_capture.active {
        return false
    }

    ui_runtime := &state.ui_runtime
    frame_step := clamp(ui_runtime.gif_frame_step, 1, 4)

    ui_runtime.gif_capture_frame_counter += 1
    if (ui_runtime.gif_capture_frame_counter - 1) % frame_step != 0 {
        return true
    }

    image := rl.LoadImageFromScreen()
    if image.data == nil {
        return false
    }
    defer rl.UnloadImage(image)

    rl.ImageCrop(&image, rl.Rectangle{0, 0, VIEW_WIDTH, VIEW_HEIGHT})

    downsample := clamp(ui_runtime.gif_downsample_factor, 1, 4)
    if downsample > 1 {
        out_w := max(1, int(image.width) / downsample)
        out_h := max(1, int(image.height) / downsample)
        rl.ImageResizeNN(&image, i32(out_w), i32(out_h))
    }

    pitch := int(image.width) * 4
    centiseconds := gif_capture_delay_centiseconds(frame_step)
    if !files.gif_encode_frame(
        &state^.gif_capture.encoder,
        image.data,
        centiseconds,
        GIF_CAPTURE_QUALITY,
        pitch,
    ) {
        return false
    }

    ui_runtime.gif_captured_frames += 1
    return true
}

//   Advance GIF capture state machine on fixed-step cycle boundaries.
//
// Parameters:
//   - state: Global app state holding GIF capture runtime flags and counters.
//
// Returns:
//   - none.
gif_capture_update_fixed_step :: proc(
    state: ^core.Euclid_General_State) {
    ui_runtime := &state.ui_runtime

    if ui_runtime.save_gif_requested {
        ui_runtime.save_gif_requested = false
        if ui_runtime.gif_capture_phase == .Armed {
            ui_runtime.gif_capture_phase = .Idle
            ui_runtime.gif_captured_frames = 0
            ui_runtime.gif_capture_frame_counter = 0
            clear_gif_status_note(ui_runtime)
            return
        }

        if ui_runtime.gif_capture_phase != .Armed &&
            ui_runtime.gif_capture_phase != .Recording &&
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
    case .Idle:
    case .Finalizing:
    case .Saved:
    case .Error:
    case .Armed:
        if gif_capture_begin_session(state) {
            ui_runtime.gif_capture_phase = .Recording
            clear_gif_status_note(ui_runtime)
        } else {
            ui_runtime.gif_capture_phase = .Error
            set_gif_status_note(ui_runtime, "Error: failed to begin GIF capture session.")
        }
    case .Recording:
        ui_runtime.gif_capture_phase = .Finalizing
        if gif_capture_finalize_session(state) {
            ui_runtime.gif_capture_phase = .Saved
            clear_gif_status_note(ui_runtime)
        } else {
            ui_runtime.gif_capture_phase = .Error
            set_gif_status_note(ui_runtime, "Error: failed to finalize GIF file.")
        }
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
    if !session.active {
        return
    }

    result := files.gif_encode_end(&session.encoder)
    if len(result.data) > 0 {
        files.gif_encode_free(&result)
    }
    session.active = false
}






//   Clear stored UI path text for last saved GIF output.
clear_last_gif_path :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) {
    ui_runtime.last_gif_path_len = 0
    ui_runtime.last_gif_path[0] = 0
}

//   Store saved GIF output path into fixed UI buffer fields.
set_last_gif_path :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State, path: string) {
    max_len := len(ui_runtime.last_gif_path) - 1
    n := min(len(path), max_len)
    for i in 0..<n {
        ui_runtime.last_gif_path[i] = path[i]
    }
    ui_runtime.last_gif_path[n] = 0
    ui_runtime.last_gif_path_len = n
}

//   Generate timestamped filename for GIF export output.
gif_output_filename :: proc() -> string {
    now := time.now()
    year := time.year(now)
    month := int(time.month(now))
    day := time.day(now)
    hour, minute, second, nanos := time.precise_clock(now)
    millis := nanos / 1_000_000

    return fmt.tprintf(
        "Euclid_%04d-%02d-%02d_%02d-%02d-%02d-%03d.gif",
        year,
        month,
        day,
        hour,
        minute,
        second,
        millis,
    )
}

//   Resolve writable output path for the next GIF export file.
gif_output_path :: proc() -> string {
    output_dir, ok := files.resolve_writable_pictures_dir(context.temp_allocator)
    if !ok {
        return ""
    }

    output_name := gif_output_filename()
    output_path, err := filepath.join([]string{output_dir, output_name}, context.temp_allocator)
    if err != nil {
        return ""
    }

    return output_path
}

//   Convert frame-step interval into GIF delay centiseconds.
gif_capture_delay_centiseconds :: #force_inline proc(frame_step: int) -> int {
    return max(1, int(f32(frame_step) * FIXED_DT * 100.0 + 0.5))
}

//   Write encoded GIF bytes to disk at the provided path.
gif_write_bytes_to_file :: proc(path: string, data: []u8) -> bool {
    if len(data) == 0 {
        return false
    }

    write_err := os.write_entire_file(path, data)
    return write_err == nil
}

//   Initialize encoder and counters for a new GIF capture session.
//
// Notes:
//   - Initializes encoder output size from current downsample settings.
gif_capture_begin_session :: proc(
    state: ^core.Euclid_General_State) -> bool {
    ui_runtime := &state.ui_runtime
    downsample := clamp(ui_runtime.gif_downsample_factor, 1, 4)
    out_w := max(1, VIEW_WIDTH / downsample)
    out_h := max(1, VIEW_HEIGHT / downsample)

    if !files.gif_encode_begin(&state^.gif_capture.encoder, out_w, out_h) {
        return false
    }

    state^.gif_capture.active = true
    ui_runtime.gif_capture_frame_counter = 0
    ui_runtime.gif_captured_frames = 0
    return true
}

//   Finalize encoder output and persist GIF bytes to a file.
//
// Notes:
//   - Ends encoder session and persists bytes to a generated output path.
gif_capture_finalize_session :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if !state^.gif_capture.active {
        return false
    }

    result := files.gif_encode_end(&state^.gif_capture.encoder)
    state^.gif_capture.active = false
    if len(result.data) == 0 {
        return false
    }
    defer files.gif_encode_free(&result)

    path := gif_output_path()
    if !gif_write_bytes_to_file(path, result.data) {
        return false
    }

    set_last_gif_path(&state.ui_runtime, path)
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
