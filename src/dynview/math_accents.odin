package dynview

import "../core"

// Math_Glyph_Accent_Input contains immutable sources and one measured base box.
Math_Glyph_Accent_Input :: struct {
    constants: core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    child_width, child_ascent, child_descent: f32,
    base_attachment: f32,
    sources: [2]core.Font_Math_Stretch_Source,
}

// Math_Glyph_Accent_Geometry seals all placement decisions for drawing.
Math_Glyph_Accent_Geometry :: struct {
    valid: bool,
    flattened: bool,
    child_x, accent_x, accent_line_top: f32,
    width, ascent, descent, scale, raster_ascent: f32,
    top_accent_attachment: f32,
    construction: core.Font_Math_Stretch_Construction,
}

Math_Accent_Construction_Bounds :: struct {
    left, right, top, bottom: f32,
    valid: bool,
}

Math_Accent_Source_Selection :: struct {
    source: core.Font_Math_Stretch_Source,
    flattened: bool,
    valid: bool,
}

//   Return raw ink bounds for one horizontal construction.
math_accent_construction_bounds :: proc(
    construction: core.Font_Math_Stretch_Construction) ->
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

//   Resolve one glyph accent using MATH height, attachment, and construction data.
math_glyph_accent_geometry :: proc(
    input: Math_Glyph_Accent_Input) -> Math_Glyph_Accent_Geometry {

    if input.font_size <= 0 || input.child_width <= 0 {
        return {}
    }
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
    bounds := math_accent_construction_bounds(construction)
    if !bounds.valid {
        return {}
    }
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
    accent_bottom := max(input.child_ascent, accent_base_height)
    accent_baseline := accent_bottom-bounds.bottom*scale
    width := max(child_x+input.child_width, accent_x+bounds.right*scale)
    ascent := max(input.child_ascent, accent_baseline+bounds.top*scale)
    line_top := -accent_baseline-source.raster_ascent*input.font_size/
        input.constants.base_pixel_size
    return {true, selected_source.flattened, child_x, accent_x, line_top, width, ascent,
        input.child_descent, scale, source.raster_ascent,
        child_x+base_attachment, construction}
}
