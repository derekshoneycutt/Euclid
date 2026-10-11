package viewtelemetry

import native "../native"
import core "../../core"
import log "core:log"
import simulationmodel "../simulation/model"
import telemetrymodel "model"

// Deferred_Visual_Capabilities names visuals outside the active geometry path.
Deferred_Visual_Capabilities :: struct {
    glyph_text: bool,
    terminal_rasters: bool,
    tool_visuals: bool,
    dust_visuals: bool,
    scenario_readback: bool,
    gif_readback: bool,
}

// deferred_visual_capabilities reports explicit later rendering boundaries.
deferred_visual_capabilities :: proc(
    state: ^core.Euclid_General_State) -> Deferred_Visual_Capabilities {
    result := Deferred_Visual_Capabilities{
        gif_readback = state^.gif_capture_status.gif_capture_phase != .Idle,
    }
    when core.SCENARIOS_ENABLED {
        result.scenario_readback = true
    }
    return result
}

// report_draw_frame_telemetry logs one representative submitted geometry frame.
report_draw_frame_telemetry :: proc(
    state: ^core.Euclid_General_State, runtime: ^native.Sdl_Draw_Runtime) {
    if runtime^.telemetry_reported {
        return
    }
    frame := runtime^.last_frame
    deferred := deferred_visual_capabilities(state)
    log.infof("sdl_geometry_frame vertices=%d indices=%d batches=%d commands=%d " +
        "stroke_vertices=%d stroke_draws=%d " +
        "curve_candidate_points=%d curve_retained_points=%d " +
        "dust_instances=%d dust_draws=%d dust_expanded_vertices=%d " +
        "pipeline_bindings=%d upload_operations=%d upload_bytes=%d " +
        "dust_upload_operations=%d dust_upload_bytes=%d " +
        "primitive_overflows=%d scissor_overflows=%d command_overflows=%d " +
        "stroke_overflows=%d dust_overflows=%d " +
        "deferred_glyph_text=%v deferred_terminal_rasters=%v " +
        "deferred_tool_visuals=%v deferred_dust_visuals=%v " +
        "deferred_scenario_readback=%v deferred_gif_readback=%v",
        frame.vertices, frame.indices, frame.batches, frame.commands,
        frame.stroke_vertices, frame.stroke_draws, frame.curve_candidate_points,
        frame.curve_retained_points, frame.dust_instances,
        frame.dust_draws, frame.dust_expanded_vertices, frame.pipeline_bindings,
        frame.upload_operations, frame.upload_bytes, frame.dust_upload_operations,
        frame.dust_upload_bytes, frame.primitive_overflows, frame.scissor_overflows,
        frame.command_overflows, frame.stroke_overflows, frame.dust_overflows,
        deferred.glyph_text, deferred.terminal_rasters,
        deferred.tool_visuals, deferred.dust_visuals,
        deferred.scenario_readback, deferred.gif_readback)
    runtime^.telemetry_reported = true
}

// publish_draw_frame_observation stores bounded renderer metrics for evidence.
publish_draw_frame_observation :: proc(
    state: ^core.Euclid_General_State, runtime: ^native.Sdl_Draw_Runtime) {
    frame := runtime^.last_frame
    state^.telemetry.colored_vertex_count = frame.vertices
    state^.telemetry.colored_index_count = frame.indices
    state^.telemetry.curve_candidate_point_count = frame.curve_candidate_points
    state^.telemetry.curve_retained_point_count = frame.curve_retained_points
    state^.telemetry.curve_retention_ratio = 0
    if frame.curve_candidate_points > 0 {
        state^.telemetry.curve_retention_ratio =
            f32(frame.curve_retained_points) / f32(frame.curve_candidate_points)
    }
    state^.telemetry.colored_primitive_overflow_count = frame.primitive_overflows
}

// report_draw_runtime_summary logs cumulative work and capacity high waters.
report_draw_runtime_summary :: proc(runtime: ^native.Sdl_Draw_Runtime) {
    statistics := runtime^.statistics
    log.infof("sdl_geometry_summary submitted_frames=%d vertices=%d indices=%d " +
        "batches=%d commands=%d stroke_vertices=%d stroke_draws=%d " +
        "curve_candidate_points=%d curve_retained_points=%d " +
        "dust_instances=%d dust_draws=%d dust_expanded_vertices=%d " +
        "upload_bytes=%d dust_upload_operations=%d dust_upload_bytes=%d " +
        "primitive_overflows=%d scissor_overflows=%d command_overflows=%d " +
        "stroke_overflows=%d dust_overflows=%d max_vertices=%d " +
        "max_indices=%d max_batches=%d max_commands=%d " +
        "max_stroke_vertices=%d max_stroke_draws=%d " +
        "max_curve_candidate_points=%d max_curve_retained_points=%d " +
        "max_dust_instances=%d max_dust_draws=%d " +
        "max_dust_expanded_vertices=%d max_dust_upload_bytes=%d " +
        "max_upload_bytes=%d",
        statistics.submitted_frames, statistics.vertices, statistics.indices,
        statistics.batches, statistics.commands, statistics.stroke_vertices,
        statistics.stroke_draws, statistics.curve_candidate_points,
        statistics.curve_retained_points, statistics.dust_instances,
        statistics.dust_draws,
        statistics.dust_expanded_vertices, statistics.upload_bytes,
        statistics.dust_upload_operations, statistics.dust_upload_bytes,
        statistics.primitive_overflows, statistics.scissor_overflows,
        statistics.command_overflows, statistics.stroke_overflows,
        statistics.dust_overflows,
        statistics.max_vertices, statistics.max_indices, statistics.max_batches,
        statistics.max_commands, statistics.max_stroke_vertices,
        statistics.max_stroke_draws, statistics.max_curve_candidate_points,
        statistics.max_curve_retained_points, statistics.max_dust_instances,
        statistics.max_dust_draws, statistics.max_dust_expanded_vertices,
        statistics.max_dust_upload_bytes,
        statistics.max_upload_bytes)
}

//   Update rolling FPS statistics used for average-FPS overlay display.
//   Advance the rolling FPS window by one full bucket when it completes.
fps_advance_bucket_if_full :: proc(telemetry: ^telemetrymodel.Runtime) {
    if telemetry.fps_avg_bucket_elapsed < 1.0 {
        return
    }

    cursor := telemetry.fps_avg_bucket_cursor
    next_cursor := (cursor + 1) % simulationmodel.FPS_AVERAGE_BUCKET_COUNT

    telemetry.fps_avg_rolling_seconds -=
        telemetry.fps_avg_bucket_seconds[next_cursor]
    telemetry.fps_avg_rolling_frames -=
        telemetry.fps_avg_bucket_frames[next_cursor]

    telemetry.fps_avg_bucket_seconds[next_cursor] = 0
    telemetry.fps_avg_bucket_frames[next_cursor] = 0

    telemetry.fps_avg_bucket_cursor = next_cursor
    telemetry.fps_avg_bucket_elapsed = 0
}

//   Accumulate one frame's elapsed time into the rolling FPS buckets.
fps_accumulate_seconds :: proc(
    telemetry: ^telemetrymodel.Runtime, frame_dt: f32) {

    remaining := frame_dt
    for remaining > 0 {
        space := 1.0 - telemetry.fps_avg_bucket_elapsed
        step := min(remaining, space)

        cursor := telemetry.fps_avg_bucket_cursor
        telemetry.fps_avg_bucket_seconds[cursor] += step
        telemetry.fps_avg_rolling_seconds += step
        telemetry.fps_avg_bucket_elapsed += step
        remaining -= step

        fps_advance_bucket_if_full(telemetry)
    }
}

//   Update the rolling-average FPS from one frame's delta time.
update_average_fps :: proc(state: ^core.Euclid_General_State, frame_dt: f32) {
    if frame_dt <= 0 {
        return
    }

    telemetry := &state^.telemetry
    fps_accumulate_seconds(telemetry, frame_dt)

    cursor := telemetry.fps_avg_bucket_cursor
    telemetry.fps_avg_bucket_frames[cursor] += 1
    telemetry.fps_avg_rolling_frames += 1

    if telemetry.fps_avg_rolling_seconds > 0 {
        telemetry.fps_avg_live =
            f32(telemetry.fps_avg_rolling_frames) / telemetry.fps_avg_rolling_seconds
        return
    }
    telemetry.fps_avg_live = 0
}
