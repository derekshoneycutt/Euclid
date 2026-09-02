package dynview

import "../core"
import "core:math"

//   Evaluate one immutable MATH corner table at a raw 26.6 correction height.
math_kern_value :: proc(
    table: core.Font_Math_Kern_Table,
    generation: u64,
    correction_height: i32) -> (i32, bool) {

    if !table.valid || table.generation != generation || table.glyph_id == 0 ||
        table.corner > 3 || table.count < 0 || table.count > len(table.entries) {
        return 0, false
    }
    if table.count == 0 {
        return 0, true
    }
    previous_height: i32
    for index in 0..<table.count {
        entry := table.entries[index]
        if index > 0 && entry.max_correction_height <= previous_height {
            return 0, false
        }
        if correction_height <= entry.max_correction_height {
            return entry.kern_value, true
        }
        previous_height = entry.max_correction_height
    }
    return table.entries[table.count-1].kern_value, true
}

//   Find one immutable generation-specific corner table by edge glyph identity.
math_kern_table_for_glyph :: proc(
    cache: ^core.Dynview_Compile_Cache,
    glyph_id: u32,
    corner: u8) -> (core.Font_Math_Kern_Table, bool) {

    if cache == nil || glyph_id == 0 || corner > 3 {
        return {}, false
    }
    for table in cache^.math_kern_tables {
        if table.valid && table.generation == cache^.shaped_font_generation &&
            table.glyph_id == glyph_id && table.corner == corner {
            return table, true
        }
    }
    return {}, false
}

//   Evaluate and scale one 32-pixel 26.6 kern table at a physical layout height.
math_kern_value_px :: proc(
    table: core.Font_Math_Kern_Table,
    generation: u64,
    correction_height: f32,
    glyph_font_size: f32,
    base_pixel_size: f32) -> f32 {

    if glyph_font_size <= 0 || base_pixel_size <= 0 {
        return 0
    }
    raw_height := i32(math.round(f64(
        correction_height * base_pixel_size * 64 / glyph_font_size)))
    raw_value, ok := math_kern_value(table, generation, raw_height)
    if !ok {
        return 0
    }
    return f32(raw_value) * glyph_font_size / (base_pixel_size * 64)
}