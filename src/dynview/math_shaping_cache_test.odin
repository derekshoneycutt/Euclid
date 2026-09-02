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
    _ = request.flattened_accent
    if request.standalone_accent {
        request.glyph_output[0] = {glyph_id = 94, x_advance = 640}
        return {1, true}
    }
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

//   Return deterministic bounded variants for one fake display operator.
math_shaping_test_variants :: proc(
    user_data: rawptr,
    request: Math_Glyph_Variants_Request) -> Math_Glyph_Variants_Result {

    _ = user_data
    if request.generation != 7 || request.glyph_id == 0 || len(request.output) < 2 {
        return {}
    }
    request.output[0] = {
        glyph_id = request.glyph_id, advance = 1024,
        extents = {0, 896, 768, -1024}, italic_correction = 64}
    request.output[1] = {
        glyph_id = request.glyph_id + 1, advance = 1536,
        extents = {0, 1280, 1024, -1536}, italic_correction = 96}
    return {2, true, true}
}

//   Return one deterministic bounded three-part vertical assembly.
math_shaping_test_assembly :: proc(
    user_data: rawptr,
    request: Math_Glyph_Assembly_Request) -> Math_Glyph_Assembly_Result {

    _ = user_data
    if request.generation != 7 || request.glyph_id == 0 || len(request.output) < 3 {
        return {}
    }
    request.output[0] = {
        glyph_id = request.glyph_id, end_connector_length = 128,
        full_advance = 640, extents = {0, 640, 512, -640}}
    request.output[1] = {
        glyph_id = request.glyph_id + 1, start_connector_length = 128,
        end_connector_length = 128, full_advance = 512, extender = true,
        extents = {0, 512, 512, -512}}
    request.output[2] = {
        glyph_id = request.glyph_id + 2, start_connector_length = 128,
        full_advance = 640, extents = {0, 640, 512, -640}}
    return {3, 64, 0, true}
}

//   Return one deterministic constant kern range for every glyph corner.
math_shaping_test_kern_table :: proc(
    user_data: rawptr,
    request: Math_Glyph_Kern_Table_Request) -> Math_Glyph_Kern_Table_Result {

    _ = user_data
    if request.generation != 7 || request.glyph_id == 0 ||
        request.corner > 3 || len(request.output) < 1 {
        return {}
    }
    request.output[0] = {max_correction_height = 0, kern_value = 16}
    return {1, true}
}

//   Build one fake shaping service over caller-owned temporary workspaces.
math_shaping_test_service :: proc(
    projection_workspace: []u8,
    glyph_workspace: []core.Shaped_Glyph) -> Math_Shaping_Service {

    constants := core.Font_Math_Constants{
        valid = true,
        generation = 7,
        base_pixel_size = 32,
    }
    constants.values[int(Math_Constant.Script_Percent_Scale_Down)] = 80
    constants.values[int(Math_Constant.Script_Script_Percent_Scale_Down)] = 60
    constants.values[int(Math_Constant.Axis_Height)] = 4 * 64
    constants.values[int(Math_Constant.Fraction_Rule_Thickness)] = 1 * 64
    constants.values[int(
        Math_Constant.Fraction_Numerator_Display_Style_Shift_Up)] = 10 * 64
    constants.values[int(
        Math_Constant.Fraction_Denominator_Display_Style_Shift_Down)] = 8 * 64
    constants.values[int(Math_Constant.Fraction_Num_Display_Style_Gap_Min)] = 3 * 64
    constants.values[int(Math_Constant.Fraction_Denom_Display_Style_Gap_Min)] = 3 * 64
    constants.values[int(Math_Constant.Overbar_Vertical_Gap)] = 3 * 64
    constants.values[int(Math_Constant.Overbar_Rule_Thickness)] = 1 * 64
    constants.values[int(Math_Constant.Overbar_Extra_Ascender)] = 2 * 64
    constants.values[int(Math_Constant.Underbar_Vertical_Gap)] = 3 * 64
    constants.values[int(Math_Constant.Underbar_Rule_Thickness)] = 1 * 64
    constants.values[int(Math_Constant.Underbar_Extra_Descender)] = 2 * 64
    return {
        generation = 7,
        base_pixel_size = 32,
        raster_ascent = 24,
        constants = constants,
        shape = math_shaping_test_shape,
        glyph_metrics = math_shaping_test_metrics,
        glyph_variants = math_shaping_test_variants,
        glyph_assembly = math_shaping_test_assembly,
        horizontal_glyph_variants = math_shaping_test_variants,
        horizontal_glyph_assembly = math_shaping_test_assembly,
        glyph_kern_table = math_shaping_test_kern_table,
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
    cache^.math_command_count = 7
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
        kind = .Radical_Bar, math_program_id = 3, secondary_math_program_id = 2,
        radical_index_text_offset = 3, radical_index_text_len = 1,
        script_style_id = DYNVIEW_STYLE_ITALIC, script_scale = 0.6,
        accent_thickness = 0.05}
    cache^.math_commands[5] = {
        kind = .Accent_Bar, math_program_id = 0, accent_mode = 1}
    cache^.math_commands[6] = {
        kind = .Accent_Bar, math_program_id = 0, accent_mode = 3}
    cache^.math_program_count = 7
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

//   Verify one fake display operator's published variant identity and contents.
math_shaping_expect_operator_variants :: proc(
    t: ^testing.T, cache: ^core.Dynview_Compile_Cache) {

    variants := cache^.math_operator_variants[1]
    testing.expect(t, variants.valid && variants.extended_shape)
    testing.expect_value(t, variants.generation, u64(7))
    testing.expect_value(t, variants.base_glyph_id, u32('S'))
    testing.expect_value(t, variants.count, 2)
    testing.expect_value(t, variants.values[1].glyph_id, u32('T'))
}

//   Verify cached NewCM metrics replace synthetic math-glyph measurements.
@(test)
dynview_math_shaping_measures_cached_intrinsic_metrics :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System)
    defer free(runtime)
    testing.expect(t, core.arena_owner_init(&runtime^.cache_arena))
    defer core.arena_owner_destroy(&runtime^.cache_arena)
    copy(runtime^.command_buffer.text_bytes[:2], []u8{'x', 'S'})
    runtime^.command_buffer.text_bytes_len = 2
    cache := &runtime^.compile_cache
    cache^.last_cell_width = 8
    cache^.math_command_count = 2
    cache^.math_commands[0] = {
        kind = .Math_Glyph_Run, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 0, text_len = 1}
    cache^.math_commands[1] = {
        kind = .Large_Op, style_id = DYNVIEW_STYLE_ITALIC,
        text_offset = 1, text_len = 1,
        operator_growth = OPERATOR_GROWTH_DISPLAY,
    }
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
    math_shaping_expect_operator_variants(t, cache)

    math_shaping_expect_cached_run(t, runtime)
    script_style, script_size := math_child_font_size(
        cache, 32, {.Display, false}, .Superscript)
    testing.expect(t, measure_math_program(cache, &runtime^.command_buffer,
        &cache^.math_programs[0], script_size, script_style))
    testing.expect_value(t, cache^.math_programs[0].draw_width, f32(8))
    script_script_style, script_script_size := math_child_font_size(
        cache, script_size, script_style, .Superscript)
    testing.expect(t, measure_math_program(cache, &runtime^.command_buffer,
        &cache^.math_programs[0], script_script_size, script_script_style))
    testing.expect_value(t, cache^.math_programs[0].draw_width, f32(6))
}

//   Verify bar and glyph accents inherit published MATH geometry.
math_shaping_expect_recursive_accents :: proc(
    t: ^testing.T,
    runtime: ^core.Dynview_System) {

    cache := &runtime^.compile_cache
    bar_item, bar_ok := math_program_item(
        cache, &runtime^.command_buffer, cache^.math_commands[5], 32, 5,
        {.Text, false})
    testing.expect(t, bar_ok && bar_item.accent_geometry_valid)
    testing.expect_value(t, bar_item.accent_rule_center, f32(-13.5))
    testing.expect_value(t, bar_item.accent_rule_thickness, f32(1))
    testing.expect_value(t, bar_item.ascent, f32(16))
    glyph_accent, glyph_accent_ok := math_program_item(
        cache, &runtime^.command_buffer, cache^.math_commands[6], 32, 6,
        {.Text, false})
    testing.expect(t, glyph_accent_ok && glyph_accent.accent_geometry_valid)
    testing.expect(t, glyph_accent.accent_glyph_construction.valid)
    testing.expect_value(t, glyph_accent.accent_glyph_font_generation, u64(7))
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
    radical_source := cache^.math_stretch_sources[5][0]
    testing.expect(t, radical_source.variants.valid && radical_source.assembly.valid)
    testing.expect(t, radical_source.assembly.count == 3)
    radical_item, radical_ok := math_program_item(
        cache, &runtime^.command_buffer, cache^.math_commands[4], 32, 4)
    testing.expect(t, radical_ok && radical_item.radical_geometry_valid)
    testing.expect_value(t, radical_item.secondary_math_program_id, i32(2))
    testing.expect(t, radical_item.math_stretch_content_x < 30)
    fraction_item, fraction_ok := math_program_item(
        cache, &runtime^.command_buffer, cache^.math_commands[3], 32, 3)
    numerator_bottom := fraction_item.fraction_numerator_baseline +
        cache^.math_programs[1].descent
    rule_top := fraction_item.fraction_rule_center -
        fraction_item.fraction_rule_thickness * 0.5
    testing.expect(t, fraction_ok && fraction_item.fraction_geometry_valid)
    testing.expect_value(t, fraction_item.fraction_rule_center, f32(-4))
    testing.expect(t, rule_top-numerator_bottom >= 3)
    script_item, script_ok := math_program_item(
        cache, &runtime^.command_buffer, cache^.math_commands[1], 32, 1)
    testing.expect(t, script_ok && script_item.math_has_edge_glyphs)
    testing.expect_value(t, script_item.script_base_glyph_id, u32('x'))
    testing.expect_value(t, script_item.script_sup_glyph_id, u32('2'))
    math_shaping_expect_recursive_accents(t, runtime)
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
    testing.expect_value(t, len(cache^.math_kern_tables), 8)
    testing.expect(t, cache^.math_kern_tables[0].valid)
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
    testing.expect_value(t, len(cache^.math_kern_tables), 0)
    testing.expect(t, measured)
    testing.expect_value(t, cache^.math_programs[0].draw_width, f32(16))
}