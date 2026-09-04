package dynview_math

import app_core "../../core"

// Math_Glyph_Accent_Input contains immutable sources and one measured base box.
Math_Glyph_Accent_Input :: struct {
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    child_width, child_ascent, child_descent: f32,
    base_attachment: f32,
    sources: [2]app_core.Font_Math_Stretch_Source,
    brace_mode: i32,
}

// Math_Glyph_Accent_Geometry seals all placement decisions for drawing.
Math_Glyph_Accent_Geometry :: struct {
    valid: bool,
    flattened: bool,
    child_x, accent_x, accent_line_top: f32,
    width, ascent, descent, scale, raster_ascent: f32,
    top_accent_attachment: f32,
    construction: app_core.Font_Math_Stretch_Construction,
}

Math_Accent_Construction_Bounds :: struct {
    left, right, top, bottom: f32,
    valid: bool,
}

Math_Accent_Source_Selection :: struct {
    source: app_core.Font_Math_Stretch_Source,
    flattened: bool,
    valid: bool,
}

Math_Accent_Resolution :: struct {
    valid: bool,
    flattened: bool,
    accent_base_height: f32,
    scale: f32,
    source: app_core.Font_Math_Stretch_Source,
    construction: app_core.Font_Math_Stretch_Construction,
    bounds: Math_Accent_Construction_Bounds,
}

//   Return the intrinsic accent glyph when no wider construction is available.
math_accent_intrinsic_construction :: proc(
    source: app_core.Font_Math_Stretch_Source,
    generation: u64) -> app_core.Font_Math_Stretch_Construction {

    variants := source.variants
    if !variants.valid || variants.generation != generation ||
        variants.count <= 0 || variants.values[0].glyph_id == 0 {
        return {}
    }
    variant := variants.values[0]
    construction := app_core.Font_Math_Stretch_Construction{
        valid = true, generation = generation,
        base_glyph_id = variants.base_glyph_id,
        advance = f32(max(1, variant.advance)), count = 1,
        top_accent_attachment = f32(variant.top_accent_attachment),
    }
    construction.parts[0] = {
        glyph_id = variant.glyph_id, extents = variant.extents}
    return construction
}

//   Return raw ink bounds for one horizontal construction.
math_accent_construction_bounds :: proc(
    construction: app_core.Font_Math_Stretch_Construction) ->
        Math_Accent_Construction_Bounds {

    result: Math_Accent_Construction_Bounds
    if !construction.valid || construction.count <= 0 ||
        construction.count > len(construction.parts) {
        return result
    }
    for index in 0..<construction.count {
        part := construction.parts[index]
        part_left := part.advance_offset + f32(part.extents.x_bearing)
        part_right := part_left + f32(part.extents.width)
        part_top := f32(part.extents.y_bearing)
        part_bottom := part_top + f32(part.extents.height)
        if index == 0 {
            result.left, result.right = part_left, part_right
            result.top, result.bottom = part_top, part_bottom
        } else {
            result.left, result.right =
                min(result.left, part_left), max(result.right, part_right)
            result.top, result.bottom =
                max(result.top, part_top), min(result.bottom, part_bottom)
        }
    }
    if result.right <= result.left && result.top >= result.bottom {
        attachment := construction.top_accent_attachment
        if attachment <= 0 {
            attachment = (result.left+result.right)*0.5
        }
        half_width := max(32, construction.advance*0.5)
        result.left = attachment-half_width
        result.right = attachment+half_width
    }
    result.valid = result.right > result.left && result.top >= result.bottom
    return result
}

//   Select normal or flattened source from the base-height threshold.
math_accent_select_source :: proc(
    input: Math_Glyph_Accent_Input) -> Math_Accent_Source_Selection {

    flattened_height, ok := math_constant_position_px(input.constants,
        input.generation, .Flattened_Accent_Base_Height, input.font_size)
    if !ok {
        return {}
    }
    flattened := input.child_ascent > flattened_height
    return {input.sources[int(flattened)], flattened, true}
}

//   Resolve the source, scale, and construction used to place one glyph accent.
math_accent_resolve :: proc(
    input: Math_Glyph_Accent_Input) -> Math_Accent_Resolution {

    accent_base_height, base_ok := math_constant_position_px(input.constants,
        input.generation, .Accent_Base_Height, input.font_size)
    selected_source := math_accent_select_source(input)
    source := selected_source.source
    if !base_ok || !selected_source.valid || source.raster_ascent <= 0 {
        return {}
    }
    scale := input.font_size/input.constants.base_pixel_size/64
    target := i32(input.child_width/scale + 0.999)
    construction := math_stretch_select(
        source.variants, source.assembly, input.generation, target)
    if !construction.valid {
        construction = math_accent_intrinsic_construction(source, input.generation)
    }
    bounds := math_accent_construction_bounds(construction)
    return {
        valid = bounds.valid,
        flattened = selected_source.flattened,
        accent_base_height = accent_base_height,
        scale = scale,
        source = source,
        construction = construction,
        bounds = bounds,
    }
}

//   Place one horizontal brace above or below its measured base.
math_brace_accent_geometry :: proc(
    input: Math_Glyph_Accent_Input,
    resolved: Math_Accent_Resolution,
    child_x, accent_x, base_attachment: f32) -> Math_Glyph_Accent_Geometry {

    gap_key := Math_Constant.Stretch_Stack_Gap_Above_Min
    if input.brace_mode == 15 {
        gap_key = .Stretch_Stack_Gap_Below_Min
    }
    gap, gap_ok := math_constant_position_px(
        input.constants, input.generation, gap_key, input.font_size)
    if !gap_ok {
        return {}
    }
    bounds := resolved.bounds
    scale := resolved.scale
    raster_height := resolved.source.raster_ascent*input.font_size/
        input.constants.base_pixel_size
    width := max(child_x+input.child_width, accent_x+bounds.right*scale)
    if input.brace_mode == 14 {
        desired_bottom := -input.child_ascent-gap
        line_top := desired_bottom+bounds.bottom*scale-raster_height
        ascent := max(input.child_ascent, -desired_bottom+
            (bounds.top-bounds.bottom)*scale)
        return {true, false, child_x, accent_x, line_top, width, ascent,
            input.child_descent, scale, resolved.source.raster_ascent,
            child_x+base_attachment, resolved.construction}
    }
    desired_top := input.child_descent+gap
    line_top := desired_top+bounds.top*scale-raster_height
    descent := max(input.child_descent, desired_top+
        (bounds.top-bounds.bottom)*scale)
    return {true, false, child_x, accent_x, line_top, width,
        input.child_ascent, descent, scale, resolved.source.raster_ascent,
        child_x+base_attachment, resolved.construction}
}

//   Resolve one glyph accent using MATH height, attachment, and construction data.
math_glyph_accent_geometry :: proc(
    input: Math_Glyph_Accent_Input) -> Math_Glyph_Accent_Geometry {

    if input.font_size <= 0 || input.child_width <= 0 {
        return {}
    }
    resolved := math_accent_resolve(input)
    if !resolved.valid {
        return {}
    }
    construction := resolved.construction
    bounds := resolved.bounds
    scale := resolved.scale
    accent_attachment := construction.top_accent_attachment
    if construction.assembled || accent_attachment <= 0 {
        accent_attachment = (bounds.left+bounds.right)*0.5
    }
    base_attachment := input.base_attachment
    if base_attachment <= 0 {
        base_attachment = input.child_width*0.5
    }
    accent_x := base_attachment-accent_attachment*scale
    child_x := max(0, -(accent_x+bounds.left*scale))
    accent_x += child_x
    if input.brace_mode == 14 || input.brace_mode == 15 {
        return math_brace_accent_geometry(
            input, resolved, child_x, accent_x, base_attachment)
    }
    accent_bottom := max(input.child_ascent, resolved.accent_base_height)
    accent_baseline := accent_bottom-bounds.bottom*scale
    width := max(child_x+input.child_width, accent_x+bounds.right*scale)
    ascent := max(input.child_ascent, accent_baseline+bounds.top*scale)
    line_top := -accent_baseline-resolved.source.raster_ascent*input.font_size/
        input.constants.base_pixel_size
    return {true, resolved.flattened, child_x, accent_x, line_top, width, ascent,
        input.child_descent, scale, resolved.source.raster_ascent,
        child_x+base_attachment, construction}
}
