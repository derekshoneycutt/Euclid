package startup

import native "../native"
import files "../../files"
import fmt "core:fmt"
import log "core:log"
import thread "core:thread"
import theme "../ui/theme"
import worldmodel "../world/model"

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
    display: Loading_Display = {
        platform = platform,
        draw_runtime = draw_runtime,
    }
    display.outline = startup_outline_create({
        platform^.metrics.logical_width, platform^.metrics.logical_height})
    native.sdl_frame_clock_reset(&display.clock)
    return display
}

// present_startup_frame draws one callback iteration at already admitted extents.
present_startup_frame :: proc(display: ^Loading_Display) -> bool {
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
        native.to_sdl_color(worldmodel.BACKGROUND_COLOR), {})
    if result == .Failed {
        log.error("sdl_startup_present_failed")
        return false
    }
    return true
}

//   Prepare packaged assets and publish readiness to the joining display thread.
prepare_assets_worker :: proc(thread_handle: ^thread.Thread) {
    result := cast(^Packaged_Assets_Worker_Result)thread_handle.data
    result^.ok = files.packaged_asset_archive_exists_root() &&
        files.ensure_packaged_assets_unpacked_root()
}

// Begin timing one stepped startup phase without entering the scheduler recursively.
begin_startup_phase :: proc(
    display: ^Loading_Display, label: string, progress: f32) -> f64 {
    startup_outline_set_target(&display^.outline, progress)
    fmt.println("Startup: ", label, "...")
    return native.sdl_time_seconds()
}

//   Log elapsed wall time for one completed startup phase.
end_startup_phase :: proc(label: string, started_at: f64) {
    elapsed_ms := int((native.sdl_time_seconds() - started_at) * 1000)
    fmt.println("Startup: ", label, " completed in ", elapsed_ms, " ms")
}
