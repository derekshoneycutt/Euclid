package view

// GIFs are captured only from the view area, excluding the UI. The current session for the
// GIF is always stored on the general state for the application. We need to wait until a
// new animation cycle begins, record it into a gif, and when the cycle completes, write it
// out to a new GIF file.

import "../core"
import "../gif"

import "core:fmt"
import "core:math"
import "core:os"

import rl "vendor:raylib"

GIF_CAPTURE_QUALITY :: 12

GifCaptureSession :: core.GifCaptureSession

clear_last_gif_path :: proc(ui_runtime: ^core.EuclidUIRuntimeState) {
    ui_runtime.LastGifPathLen = 0
    ui_runtime.LastGifPath[0] = 0
}

set_last_gif_path :: proc(ui_runtime: ^core.EuclidUIRuntimeState, path: string) {
    max_len := len(ui_runtime.LastGifPath) - 1
    n := min(len(path), max_len)
    for i in 0..<n {
        ui_runtime.LastGifPath[i] = path[i]
    }
    ui_runtime.LastGifPath[n] = 0
    ui_runtime.LastGifPathLen = n
}

gif_output_path :: proc() -> string {
    millis := int(rl.GetTime() * 1000.0)
    return fmt.tprintf("gif_%d.gif", millis)
}

gif_capture_delay_centiseconds :: #force_inline proc(frame_step: int) -> int {
    return max(1, int(f32(frame_step) * FIXED_DT * 100.0 + 0.5))
}

gif_write_bytes_to_file :: proc(path: string, data: []u8) -> bool {
    if len(data) == 0 {
        return false
    }

    write_err := os.write_entire_file(path, data)
    return write_err == nil
}

gif_capture_abort_session :: proc(session: ^GifCaptureSession) {
    if !session.Active {
        return
    }

    result := gif.gif_encode_end(&session.Encoder)
    if len(result.Data) > 0 {
        gif.gif_encode_free(&result)
    }
    session.Active = false
}

gif_capture_begin_session :: proc(
    state: ^core.EuclidGeneralState,
) -> bool {
    ui_runtime := &state.UIRuntime
    downsample := clamp(ui_runtime.GifDownsampleFactor, 1, 4)
    out_w := max(1, VIEW_WIDTH / downsample)
    out_h := max(1, VIEW_HEIGHT / downsample)

    if !gif.gif_encode_begin(&state^.GifCapture.Encoder, out_w, out_h) {
        return false
    }

    state^.GifCapture.Active = true
    ui_runtime.GifCaptureFrameCounter = 0
    ui_runtime.GifCapturedFrames = 0
    return true
}

gif_capture_finalize_session :: proc(
    state: ^core.EuclidGeneralState,
) -> bool {
    if !state^.GifCapture.Active {
        return false
    }

    result := gif.gif_encode_end(&state^.GifCapture.Encoder)
    state^.GifCapture.Active = false
    if len(result.Data) == 0 {
        return false
    }
    defer gif.gif_encode_free(&result)

    path := gif_output_path()
    if !gif_write_bytes_to_file(path, result.Data) {
        return false
    }

    set_last_gif_path(&state.UIRuntime, path)
    return true
}

gif_capture_submit_frame :: proc(
    state: ^core.EuclidGeneralState,
) -> bool {
    if !state^.GifCapture.Active {
        return false
    }

    ui_runtime := &state.UIRuntime
    frame_step := clamp(ui_runtime.GifFrameStep, 1, 4)

    ui_runtime.GifCaptureFrameCounter += 1
    if (ui_runtime.GifCaptureFrameCounter - 1) % frame_step != 0 {
        return true
    }

    image := rl.LoadImageFromScreen()
    if image.data == nil {
        return false
    }
    defer rl.UnloadImage(image)

    rl.ImageCrop(&image, rl.Rectangle{0, 0, VIEW_WIDTH, VIEW_HEIGHT})

    downsample := clamp(ui_runtime.GifDownsampleFactor, 1, 4)
    if downsample > 1 {
        out_w := max(1, int(image.width) / downsample)
        out_h := max(1, int(image.height) / downsample)
        rl.ImageResizeNN(&image, i32(out_w), i32(out_h))
    }

    pitch := int(image.width) * 4
    centiseconds := gif_capture_delay_centiseconds(frame_step)
    if !gif.gif_encode_frame(
        &state^.GifCapture.Encoder,
        image.data,
        centiseconds,
        GIF_CAPTURE_QUALITY,
        pitch,
    ) {
        return false
    }

    ui_runtime.GifCapturedFrames += 1
    return true
}

gif_capture_consume_cycle_boundary :: proc(state: ^core.EuclidGeneralState) -> bool {
    if state.ConsumedCycleBoundaryGeneration == state.CycleBoundaryGeneration {
        return false
    }
    state.ConsumedCycleBoundaryGeneration = state.CycleBoundaryGeneration
    return true
}

gif_capture_update_fixed_step :: proc(
    state: ^core.EuclidGeneralState,
) {
    ui_runtime := &state.UIRuntime

    if ui_runtime.SaveGifRequested {
        ui_runtime.SaveGifRequested = false
        if ui_runtime.GifCapturePhase == .Armed {
            ui_runtime.GifCapturePhase = .Idle
            ui_runtime.GifCapturedFrames = 0
            ui_runtime.GifCaptureFrameCounter = 0
            return
        }

        if ui_runtime.GifCapturePhase != .Armed &&
            ui_runtime.GifCapturePhase != .Recording &&
            ui_runtime.GifCapturePhase != .Finalizing {
            ui_runtime.GifCapturePhase = .Armed
            ui_runtime.GifCapturedFrames = 0
            ui_runtime.GifCaptureFrameCounter = 0
            clear_last_gif_path(ui_runtime)
        }
    }

    if !gif_capture_consume_cycle_boundary(state) {
        return
    }

    switch ui_runtime.GifCapturePhase {
    case .Idle:
    case .Finalizing:
    case .Saved:
    case .Error:
    case .Armed:
        if gif_capture_begin_session(state) {
            ui_runtime.GifCapturePhase = .Recording
        } else {
            ui_runtime.GifCapturePhase = .Error
        }
    case .Recording:
        ui_runtime.GifCapturePhase = .Finalizing
        if gif_capture_finalize_session(state) {
            ui_runtime.GifCapturePhase = .Saved
        } else {
            ui_runtime.GifCapturePhase = .Error
        }
    }
}
