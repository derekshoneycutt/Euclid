package dynview

import "../core"

Math_Shape_Request :: struct {
    generation: u64,
    text: string,
    italic: bool,
    projection_workspace: []u8,
    glyph_output: []core.Shaped_Glyph,
}

Math_Shape_Result :: struct {
    glyph_count: int,
    ok: bool,
}

// Shape one semantic math text site into caller-owned temporary glyph storage.
Math_Shape_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Shape_Request) -> Math_Shape_Result

Math_Glyph_Metrics_Request :: struct {
    generation: u64,
    glyph_id: u32,
}

Math_Glyph_Metrics_Result :: struct {
    extents: core.Font_Glyph_Extents,
    italic_correction: i32,
    top_accent_attachment: i32,
    ok: bool,
}

// Query approved intrinsic and OpenType MATH metrics for one shaped glyph.
Math_Glyph_Metrics_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Glyph_Metrics_Request) -> Math_Glyph_Metrics_Result

// Borrow worker-owned shaping behavior and temporary storage for one cache rebuild.
Math_Shaping_Service :: struct {
    user_data: rawptr,
    generation: u64,
    base_pixel_size: f32,
    raster_ascent: f32,
    shape: Math_Shape_Handler,
    glyph_metrics: Math_Glyph_Metrics_Handler,
    projection_workspace: []u8,
    glyph_workspace: []core.Shaped_Glyph,
}

// Scaled shaped-run dimensions consumed by recursive math layout.
Shaped_Run_Layout_Metrics :: struct {
    draw_width: f32,
    advance: f32,
    ascent: f32,
    descent: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
}

Shaped_Ink_Bounds :: struct {
    left, right, top, bottom: i32,
}

Shape_Command_Site_Context :: struct {
    builder: ^Dynview_Shaped_Builder,
    runtime: ^core.Dynview_System,
    service: Math_Shaping_Service,
    command_index: int,
    command: core.Dynview_Command,
}

Math_Command_Site :: struct {
    offset, count: int,
    style_id: i32,
    eligible: bool,
}

Shaped_Measure_Accumulator :: struct {
    pen_x: i32,
    bounds: Shaped_Ink_Bounds,
    trailing_italic: i32,
    top_accent: i32,
}

//   Return one sealed shaped run for a math command site.
shaped_run_for_command :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    command: core.Dynview_Command,
    site: core.Dynview_Shaped_Site) -> (^core.Dynview_Shaped_Run, bool) {

    run_index := int(command.shaped_run_indices[int(site)])
    if cache == nil || run_index < 0 || run_index >= len(cache^.shaped_runs) {
        return nil, false
    }
    run := &cache^.shaped_runs[run_index]
    return run, run^.font_generation == cache^.shaped_font_generation &&
        run^.site == site
}

//   Scale cached 32-pixel shaping metrics to one requested math size.
shaped_run_layout_metrics :: #force_inline proc(
    run: ^core.Dynview_Shaped_Run,
    font_size: f32) -> (Shaped_Run_Layout_Metrics, bool) {

    if run == nil || run^.base_pixel_size <= 0 || font_size <= 0 {
        return {}, false
    }
    scale := font_size / run^.base_pixel_size
    left := min(0, run^.ink_left)
    right := max(run^.advance, run^.ink_right)
    return {
        draw_width = max(1, (right-left)*scale),
        advance = max(1, run^.advance*scale),
        ascent = max(1, run^.ascent*scale),
        descent = max(1, run^.descent*scale),
        italic_correction = max(0, run^.italic_correction*scale),
        top_accent_attachment = run^.top_accent_attachment*scale,
    }, true
}

//   Return the complete sealed glyph slice for one shaped run.
shaped_glyphs_for_run :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    run: ^core.Dynview_Shaped_Run) -> ([]core.Shaped_Glyph, bool) {

    if cache == nil || run == nil || run^.glyph_start < 0 || run^.glyph_count <= 0 {
        return nil, false
    }
    glyph_end := run^.glyph_start + run^.glyph_count
    if glyph_end > len(cache^.shaped_glyphs) {
        return nil, false
    }
    return cache^.shaped_glyphs[run^.glyph_start:glyph_end], true
}

//   Build and atomically seal proportional records for supported math text sites.
rebuild_shaped_math_cache :: proc(
    runtime: ^core.Dynview_System,
    arena: ^core.Arena_Owner,
    service: Math_Shaping_Service) -> core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    clear_shaped_records(cache)
    if cache^.math_command_count <= 0 || !math_shaping_service_ready(service) {
        return .Ok
    }
    builder: Dynview_Shaped_Builder
    status := shaped_builder_init(&builder, arena, service.generation)
    if status != .Ok {
        return status
    }
    for command_index in 0..<cache^.math_command_count {
        command := cache^.math_commands[command_index]
        ctx := Shape_Command_Site_Context{
            &builder, runtime, service, command_index, command}
        for site in core.Dynview_Shaped_Site {
            status = shape_math_command_site(ctx, site)
            if status != .Ok {
                clear_shaped_records(cache)
                return status
            }
        }
    }
    return shaped_builder_seal(&builder, cache,
        len(command_buffer_text(&runtime^.command_buffer)),
        cache^.math_command_count, service.generation)
}

//   Report whether one borrowed shaping service can process a complete rebuild.
math_shaping_service_ready :: #force_inline proc(service: Math_Shaping_Service) -> bool {
    return service.generation != 0 && service.base_pixel_size > 0 &&
        service.raster_ascent > 0 &&
        service.shape != nil && service.glyph_metrics != nil &&
        len(service.projection_workspace) > 0 && len(service.glyph_workspace) > 0
}

//   Shape, measure, and append one already validated semantic text site.
shape_valid_math_command_site :: proc(
    ctx: Shape_Command_Site_Context,
    site: core.Dynview_Shaped_Site,
    command_site: Math_Command_Site,
    text: string) -> core.Bounded_Builder_Status {
    service := ctx.service
    result := service.shape(service.user_data, {
        generation = service.generation,
        text = text,
        italic = style_by_id(command_site.style_id).italic,
        projection_workspace = service.projection_workspace,
        glyph_output = service.glyph_workspace,
    })
    if !result.ok || result.glyph_count <= 0 ||
        result.glyph_count > len(service.glyph_workspace) {
        return .Ok
    }
    glyphs := service.glyph_workspace[:result.glyph_count]
    metrics, measured := measure_shaped_glyphs(service, glyphs)
    if !measured {
        return .Ok
    }
    return shaped_builder_append(ctx.builder, {
        math_command_index = ctx.command_index,
        site = site,
        text_offset = command_site.offset,
        text_len = command_site.count,
        glyphs = glyphs,
        metrics = metrics,
    })
}

//   Shape one eligible command site, retaining baseline fallback on native rejection.
shape_math_command_site :: proc(
    ctx: Shape_Command_Site_Context,
    site: core.Dynview_Shaped_Site) -> core.Bounded_Builder_Status {

    command_site := math_command_site(ctx.command, site)
    if !command_site.eligible || command_site.count <= 0 {
        return .Ok
    }
    text_bytes := command_buffer_text(&ctx.runtime^.command_buffer)
    if command_site.offset < 0 ||
        command_site.count > len(text_bytes)-command_site.offset {
        return .Invalid_Argument
    }
    text := string(text_bytes[
        command_site.offset:command_site.offset+command_site.count])
    return shape_valid_math_command_site(ctx, site, command_site, text)
}

//   Select one semantic text span and style from a recursive math command.
math_command_site :: #force_inline proc(
    command: core.Dynview_Command,
    site: core.Dynview_Shaped_Site) -> Math_Command_Site {

    switch site {
    case .Primary:
        eligible := command.kind == .Math_Glyph_Run || command.kind == .Large_Op
        return {command.text_offset, command.text_len, command.style_id, eligible}
    case .Superscript:
        eligible := command.kind == .Script_Attach || command.kind == .Large_Op
        return {command.script_sup_text_offset, command.script_sup_text_len,
            command.script_style_id, eligible}
    case .Subscript:
        eligible := command.kind == .Script_Attach || command.kind == .Large_Op
        return {command.script_sub_text_offset, command.script_sub_text_len,
            command.script_style_id, eligible}
    case .Radical_Index:
        return {command.radical_index_text_offset, command.radical_index_text_len,
            command.script_style_id, command.kind == .Radical_Bar}
    }
    return {}
}

//   Aggregate one shaped run's advance, ink bounds, and approved MATH values.
measure_shaped_glyphs :: proc(
    service: Math_Shaping_Service,
    glyphs: []core.Shaped_Glyph) -> (core.Dynview_Shaped_Run, bool) {

    accumulator: Shaped_Measure_Accumulator
    for glyph, glyph_index in glyphs {
        if !measure_shaped_glyph_include(
            &accumulator, service, glyph, glyph_index) {
            return {}, false
        }
    }
    unit := f32(1.0 / 64.0)
    return core.Dynview_Shaped_Run{
        base_pixel_size = service.base_pixel_size,
        raster_ascent = service.raster_ascent,
        advance = f32(accumulator.pen_x) * unit,
        ink_left = f32(accumulator.bounds.left) * unit,
        ink_right = f32(accumulator.bounds.right) * unit,
        ascent = max(0, f32(accumulator.bounds.top) * unit),
        descent = max(0, -f32(accumulator.bounds.bottom) * unit),
        italic_correction = f32(accumulator.trailing_italic) * unit,
        top_accent_attachment = f32(accumulator.top_accent) * unit,
    }, true
}

//   Query and accumulate one positioned glyph's intrinsic and MATH metrics.
measure_shaped_glyph_include :: proc(
    accumulator: ^Shaped_Measure_Accumulator,
    service: Math_Shaping_Service,
    glyph: core.Shaped_Glyph,
    glyph_index: int) -> bool {

    metrics := service.glyph_metrics(service.user_data,
        {service.generation, glyph.glyph_id})
    if !metrics.ok {
        return false
    }
    left := accumulator^.pen_x + glyph.x_offset + metrics.extents.x_bearing
    top := glyph.y_offset + metrics.extents.y_bearing
    right := left + metrics.extents.width
    bottom := top + metrics.extents.height
    if glyph_index == 0 {
        accumulator^.bounds = {left, right, top, bottom}
        accumulator^.top_accent = metrics.top_accent_attachment
    } else {
        shaped_ink_bounds_include(&accumulator^.bounds, left, right, top, bottom)
    }
    accumulator^.pen_x += glyph.x_advance
    accumulator^.trailing_italic = metrics.italic_correction
    return true
}

//   Expand aggregate ink bounds with one positioned glyph extent.
shaped_ink_bounds_include :: #force_inline proc(
    bounds: ^Shaped_Ink_Bounds,
    left, right, top, bottom: i32) {

    bounds^.left = min(bounds^.left, left)
    bounds^.right = max(bounds^.right, right)
    bounds^.top = max(bounds^.top, top)
    bounds^.bottom = min(bounds^.bottom, bottom)
}