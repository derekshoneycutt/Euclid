package startup

import native "../native"
import files "../../files"
import fmt "core:fmt"
import log "core:log"
import thread "core:thread"
import inputbackend "../input/backend"
import theme "../ui/theme"
import worldmodel "../world/model"
import simulationmodel "../simulation/model"

// Loading_Display owns startup-only reveal state and borrows display GPU owners.
Loading_Display :: struct {
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime,
    outline: Startup_Outline,
    clock: native.Sdl_Frame_Clock,
}

Packaged_Assets_Worker_Result :: struct {
    ok: bool,
}

// loading_display_create initializes progressive geometry from live window metrics.
loading_display_create :: proc(
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime) -> Loading_Display {
    display := Loading_Display{platform = platform, draw_runtime = draw_runtime}
    display.outline = startup_outline_create({
        platform^.metrics.logical_width, platform^.metrics.logical_height})
    native.sdl_frame_clock_reset(&display.clock)
    return display
}

// present_startup_frame pumps lifecycle events and submits one outlined startup frame.
present_startup_frame :: proc(display: ^Loading_Display) -> bool {
    frame_started_at := native.sdl_time_ticks()
    _ = inputbackend.sdl_platform_poll_events(display^.platform)
    if display^.platform^.close_requested {
        return false
    }
    _ = startup_outline_reconcile(&display^.outline, {
        display^.platform^.metrics.logical_width,
        display^.platform^.metrics.logical_height})
    startup_outline_advance(
        &display^.outline, native.sdl_frame_clock_step(&display^.clock))
    encoder: native.Draw_Encoder
    _ = native.draw_encoder_begin(&encoder, display^.draw_runtime^.storage, {
        f32(display^.platform^.metrics.logical_width),
        f32(display^.platform^.metrics.logical_height),
    }, {display^.platform^.scene_width, display^.platform^.scene_height})
    _ = startup_outline_draw(
        &display^.outline, &encoder, theme.UI_BORDER_COLOR, worldmodel.TOOL_COLOR)
    result := native.sdl_platform_present_draw(
        display^.platform, display^.draw_runtime, &encoder,
        native.to_sdl_color(worldmodel.BACKGROUND_COLOR))
    if result == .Failed {
        log.error("sdl_startup_present_failed")
        return false
    }
    native.sdl_delay_until_rate(frame_started_at, u64(simulationmodel.LIMIT_FPS))
    return true
}

//   Prepare packaged assets and publish readiness to the joining display thread.
prepare_assets_worker :: proc(thread_handle: ^thread.Thread) {
    result := cast(^Packaged_Assets_Worker_Result)thread_handle.data
    result^.ok = files.packaged_asset_archive_exists_root() &&
        files.ensure_packaged_assets_unpacked_root()
}

//   Keep drawing and pumping window events until one startup worker is ready.
finish_startup_worker :: proc(
    worker: ^thread.Thread, display: ^Loading_Display) -> bool {
    if worker == nil {
        return true
    }
    startup_active := true
    for !thread.is_done(worker) {
        if startup_active {
            startup_active = present_startup_frame(display)
        }
        free_all(context.temp_allocator)
    }
    thread.destroy(worker)
    return startup_active
}

//   Prepare packaged assets while keeping the startup window responsive.
prepare_assets_with_loading :: proc(
    display: ^Loading_Display) -> bool {
    result: Packaged_Assets_Worker_Result
    worker := thread.create(prepare_assets_worker)
    if worker == nil {
        return files.ensure_packaged_assets_unpacked_root()
    }
    worker.data = &result
    worker.init_context = context
    thread.start(worker)
    startup_active := finish_startup_worker(worker, display)
    return result.ok && startup_active
}

//   Display and begin timing one blocking startup phase.
begin_startup_phase :: proc(
    display: ^Loading_Display, label: string, progress: f32) -> f64 {
    startup_outline_set_target(&display^.outline, progress)
    _ = present_startup_frame(display)
    fmt.println("Startup: ", label, "...")
    return native.sdl_time_seconds()
}

//   Log elapsed wall time for one completed startup phase.
end_startup_phase :: proc(label: string, started_at: f64) {
    elapsed_ms := int((native.sdl_time_seconds() - started_at) * 1000)
    fmt.println("Startup: ", label, " completed in ", elapsed_ms, " ms")
}
