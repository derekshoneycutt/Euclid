package dynview

import "../core"
import "core:testing"

//   Shape deterministic fake glyphs with one whole-run missing-glyph sentinel.
math_shaping_test_shape :: proc(
    user_data: rawptr,
    request: Math_Shape_Request) -> Math_Shape_Result {

    _ = user_data
    _ = request.generation
    _ = request.italic
    _ = request.projection_workspace
    if len(request.text) == 0 || request.text[0] == '?' ||
        len(request.text) > len(request.glyph_output) {
        return {}
    }
    for index in 0..<len(request.text) {
        request.glyph_output[index] = {
            glyph_id = u32(request.text[index]), x_advance = 640}
    }
    return {len(request.text), true}
}

//   Return deterministic 26.6 extents and MATH attachment values.
math_shaping_test_metrics :: proc(
    user_data: rawptr,
    request: Math_Glyph_Metrics_Request) -> Math_Glyph_Metrics_Result {

    _ = user_data
    _ = request.generation
    return {
        extents = {x_bearing = 0, y_bearing = 640, width = 512, height = -768},
        italic_correction = 128,
        top_accent_attachment = 320,
        ok = request.glyph_id != 0,
    }
}

//   Build one fake shaping service over caller-owned temporary workspaces.
math_shaping_test_service :: proc(
    projection_workspace: []u8,
    glyph_workspace: []core.Shaped_Glyph) -> Math_Shaping_Service {

    return {
        generation = 7,
        base_pixel_size = 32,
        raster_ascent = 24,
        shape = math_shaping_test_shape,
        glyph_metrics = math_shaping_test_metrics,
        projection_workspace = projection_workspace,
        glyph_workspace = glyph_workspace,
    }
}

//   Populate the nested script, fraction, and radical measurement fixture.
math_shaping_test_populate_recursive_fixture :: proc(runtime: ^core.Dynview_System) {
    copy(runtime^.command_buffer.text_bytes[:4], []u8{'x', '2', 'y', '3'})
    runtime^.command_buffer.text_bytes_len = 4
    cache := &runtime^.compile_cache
    cache^.last_cell_width = 8
    cache^.math_command_count = 5
    cache^.math_commands[0] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 0, text_len = 1}
    cache^.math_commands[1] = {
        kind = .Script_Attach, math_program_id = 0,
        script_sup_text_offset = 1, script_sup_text_len = 1,
        script_style_id = DYNVIEW_STYLE_ITALIC, script_scale = 0.7,
        script_gap = 0.1}
    cache^.math_commands[2] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 2, text_len = 1}
    cache^.math_commands[3] = {
        kind = .Frac, math_program_id = 1, secondary_math_program_id = 2,
        accent_thickness = 0.05}
    cache^.math_commands[4] = {
        kind = .Radical_Bar, math_program_id = 3,
        radical_index_text_offset = 3, radical_index_text_len = 1,
        script_style_id = DYNVIEW_STYLE_ITALIC, script_scale = 0.6,
        accent_thickness = 0.05}
    cache^.math_program_count = 5
    for index in 0..<cache^.math_program_count {
        cache^.math_programs[index] = {
            valid = true, command_start = index, command_count = 1}
    }
}

//   Verify cached NewCM metrics replace synthetic math-glyph measurements.
math_shaping_expect_cached_run :: proc(
    t: ^testing.T,
    runtime: ^core.Dynview_System) {
    cache := &runtime^.compile_cache
    command := cache^.math_commands[0]
    run, run_ok := shaped_run_for_command(cache, command, .Primary)
    cached_glyphs, glyphs_ok := shaped_glyphs_for_run(cache, run)
    item, item_ok := math_program_item(
        cache, &runtime^.command_buffer, command, 32, 0)
    testing.expect(t, run_ok && glyphs_ok && item_ok)
    testing.expect_value(t, item.math_command_index, i32(0))
    testing.expect_value(t, len(cached_glyphs), 1)
    testing.expect_value(t, cached_glyphs[0].glyph_id, u32('x'))
    testing.expect_value(t, run^.advance, f32(10))
    testing.expect_value(t, run^.raster_ascent, f32(24))
}

//   Verify cached NewCM metrics replace synthetic math-glyph measurements.
@(test)
dynview_math_shaping_measures_cached_intrinsic_metrics :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System)
    defer free(runtime)
    testing.expect(t, core.arena_owner_init(&runtime^.cache_arena))
    defer core.arena_owner_destroy(&runtime^.cache_arena)
    runtime^.command_buffer.text_bytes[0] = 'x'
    runtime^.command_buffer.text_bytes_len = 1
    cache := &runtime^.compile_cache
    cache^.last_cell_width = 8
    cache^.math_command_count = 1
    cache^.math_commands[0] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 0, text_len = 1}
    cache^.math_program_count = 1
    cache^.math_programs[0] = {valid = true, command_count = 1}
    projection: [16]u8
    glyphs: [8]core.Shaped_Glyph

    status := rebuild_shaped_math_cache(runtime, &runtime^.cache_arena,
        math_shaping_test_service(projection[:], glyphs[:]))
    measured := measure_math_program(
        cache, &runtime^.command_buffer, &cache^.math_programs[0], 32)

    testing.expect_value(t, status, core.Bounded_Builder_Status.Ok)
    testing.expect(t, measured)
    testing.expect_value(t, cache^.math_programs[0].draw_width, f32(10))
    testing.expect_value(t, cache^.math_programs[0].ascent, f32(10))
    testing.expect_value(t, cache^.math_programs[0].descent, f32(2))
    testing.expect_value(t, cache^.math_programs[0].italic_correction, f32(2))
    testing.expect_value(t, cache^.math_programs[0].top_accent_attachment, f32(5))

    math_shaping_expect_cached_run(t, runtime)
}

//   Verify scripts, fractions, radicals, nesting, and grid width use shaped metrics.
@(test)
dynview_math_shaping_propagates_recursive_metrics :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System)
    defer free(runtime)
    testing.expect(t, core.arena_owner_init(&runtime^.cache_arena))
    defer core.arena_owner_destroy(&runtime^.cache_arena)
    math_shaping_test_populate_recursive_fixture(runtime)
    cache := &runtime^.compile_cache
    projection: [16]u8
    glyphs: [8]core.Shaped_Glyph

    status := rebuild_shaped_math_cache(runtime, &runtime^.cache_arena,
        math_shaping_test_service(projection[:], glyphs[:]))
    measured := measure_math_program(
        cache, &runtime^.command_buffer, &cache^.math_programs[4], 32)
    columns := math_block_columns(cache^.math_programs[4].draw_width, 8, 2)

    testing.expect_value(t, status, core.Bounded_Builder_Status.Ok)
    testing.expect(t, measured)
    testing.expect(t, cache^.math_programs[1].draw_width > 19)
    testing.expect(t, cache^.math_programs[3].draw_width > 20)
    testing.expect(t, cache^.math_programs[4].draw_width >
        cache^.math_programs[3].draw_width)
    testing.expect_value(t, columns.span, 2)
    testing.expect(t, columns.overflows_horizontally)
}

//   Verify recursive matrix columns inherit proportional shaped cell widths.
@(test)
dynview_math_shaping_measures_matrix_cells :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System)
    defer free(runtime)
    testing.expect(t, core.arena_owner_init(&runtime^.cache_arena))
    defer core.arena_owner_destroy(&runtime^.cache_arena)
    copy(runtime^.command_buffer.text_bytes[:4], []u8{'x', 'y', '1', '2'})
    runtime^.command_buffer.text_bytes_len = 4
    cache := &runtime^.compile_cache
    cache^.last_cell_width = 8
    cache^.math_command_count = 3
    cache^.math_commands[0] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 0, text_len = 1}
    cache^.math_commands[1] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 1, text_len = 1}
    cache^.math_commands[2] = {
        kind = .Matrix, math_program_id = 0,
        radical_index_text_offset = 2, radical_index_text_len = 1,
        script_sup_text_offset = 3, script_sup_text_len = 1}
    cache^.math_program_count = 2
    cache^.math_programs[0] = {valid = true, command_count = 2}
    cache^.math_programs[1] = {valid = true, command_start = 2, command_count = 1}
    projection: [16]u8
    glyphs: [8]core.Shaped_Glyph

    status := rebuild_shaped_math_cache(runtime, &runtime^.cache_arena,
        math_shaping_test_service(projection[:], glyphs[:]))
    measured := measure_math_program(
        cache, &runtime^.command_buffer, &cache^.math_programs[1], 32)

    testing.expect_value(t, status, core.Bounded_Builder_Status.Ok)
    testing.expect(t, measured)
    testing.expect_value(t, len(cache^.shaped_runs), 2)
    testing.expect(t, cache^.math_programs[1].draw_width > 30)
}

//   Verify missing glyphs retain whole-run synthetic fallback without partial spans.
@(test)
dynview_math_shaping_missing_glyph_uses_whole_run_fallback :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System)
    defer free(runtime)
    testing.expect(t, core.arena_owner_init(&runtime^.cache_arena))
    defer core.arena_owner_destroy(&runtime^.cache_arena)
    copy(runtime^.command_buffer.text_bytes[:2], []u8{'?', 'x'})
    runtime^.command_buffer.text_bytes_len = 2
    cache := &runtime^.compile_cache
    cache^.last_cell_width = 8
    cache^.math_command_count = 1
    cache^.math_commands[0] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 0, text_len = 2}
    cache^.math_program_count = 1
    cache^.math_programs[0] = {valid = true, command_count = 1}
    projection: [16]u8
    glyphs: [8]core.Shaped_Glyph

    status := rebuild_shaped_math_cache(runtime, &runtime^.cache_arena,
        math_shaping_test_service(projection[:], glyphs[:]))
    measured := measure_math_program(
        cache, &runtime^.command_buffer, &cache^.math_programs[0], 32)

    testing.expect_value(t, status, core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(cache^.shaped_runs), 0)
    testing.expect(t, measured)
    testing.expect_value(t, cache^.math_programs[0].draw_width, f32(16))
}