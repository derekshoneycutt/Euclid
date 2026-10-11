package harfbuzz

import "core:c"

when ODIN_OS == .Windows {
    foreign import harfbuzz_library "system:harfbuzz.lib"
} else {
    foreign import harfbuzz_library "system:harfbuzz"
}

// Opaque HarfBuzz font-data storage referenced by a face.
Blob :: struct {}

// Opaque HarfBuzz view of one font face within a blob.
Face :: struct {}

// Opaque HarfBuzz shaping font configured with OpenType behavior and pixel scale.
Font :: struct {}

// Opaque reusable HarfBuzz input and shaped-output buffer.
Buffer :: struct {}

// HarfBuzz buffer direction values.
Direction :: enum c.int {
    Invalid = 0,
    Left_To_Right = 4,
    Right_To_Left = 5,
    Top_To_Bottom = 6,
    Bottom_To_Top = 7,
}

// OpenType MATH glyph-kern table corners in HarfBuzz ABI order.
Math_Kern :: enum c.int {
    Top_Right = 0,
    Top_Left = 1,
    Bottom_Right = 2,
    Bottom_Left = 3,
}

// HarfBuzz policy controlling whether a blob copies or borrows source bytes.
Memory_Mode :: enum c.int {
    Duplicate = 0,
    Readonly = 1,
    Writable = 2,
    Readonly_May_Make_Writable = 3,
}

// ABI-compatible OpenType feature selection over a source byte interval.
Feature :: struct {
    tag: u32,
    value: u32,
    start: u32,
    end: u32,
}

// ABI-compatible HarfBuzz glyph identity and source-cluster record.
Glyph_Info :: struct {
    codepoint: u32,
    mask: u32,
    cluster: u32,
    private_a: u32,
    private_b: u32,
}

// ABI-compatible HarfBuzz glyph advances and offsets.
Glyph_Position :: struct {
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
    private: i32,
}

// ABI-compatible HarfBuzz glyph ink extents in configured 26.6 units.
Glyph_Extents :: struct {
    x_bearing: i32,
    y_bearing: i32,
    width: i32,
    height: i32,
}

// ABI-compatible OpenType MATH glyph variant and advance record.
Math_Glyph_Variant :: struct {
    glyph: u32,
    advance: i32,
}

// ABI-compatible OpenType MATH glyph assembly part.
Math_Glyph_Part :: struct {
    glyph: u32,
    start_connector_length: i32,
    end_connector_length: i32,
    full_advance: i32,
    flags: u32,
}

// ABI-compatible height boundary and value from one MATH kern table.
Math_Kern_Entry :: struct {
    max_correction_height: i32,
    kern_value: i32,
}

// Mirrors hb_ot_math_constant_t values 0 through 55.
Math_Constant :: enum c.int {
    Script_Percent_Scale_Down = 0,
    Script_Script_Percent_Scale_Down,
    Delimited_Sub_Formula_Min_Height,
    Display_Operator_Min_Height,
    Math_Leading,
    Axis_Height,
    Accent_Base_Height,
    Flattened_Accent_Base_Height,
    Subscript_Shift_Down,
    Subscript_Top_Max,
    Subscript_Baseline_Drop_Min,
    Superscript_Shift_Up,
    Superscript_Shift_Up_Cramped,
    Superscript_Bottom_Min,
    Superscript_Baseline_Drop_Max,
    Sub_Superscript_Gap_Min,
    Superscript_Bottom_Max_With_Subscript,
    Space_After_Script,
    Upper_Limit_Gap_Min,
    Upper_Limit_Baseline_Rise_Min,
    Lower_Limit_Gap_Min,
    Lower_Limit_Baseline_Drop_Min,
    Stack_Top_Shift_Up,
    Stack_Top_Display_Style_Shift_Up,
    Stack_Bottom_Shift_Down,
    Stack_Bottom_Display_Style_Shift_Down,
    Stack_Gap_Min,
    Stack_Display_Style_Gap_Min,
    Stretch_Stack_Top_Shift_Up,
    Stretch_Stack_Bottom_Shift_Down,
    Stretch_Stack_Gap_Above_Min,
    Stretch_Stack_Gap_Below_Min,
    Fraction_Numerator_Shift_Up,
    Fraction_Numerator_Display_Style_Shift_Up,
    Fraction_Denominator_Shift_Down,
    Fraction_Denominator_Display_Style_Shift_Down,
    Fraction_Numerator_Gap_Min,
    Fraction_Num_Display_Style_Gap_Min,
    Fraction_Rule_Thickness,
    Fraction_Denominator_Gap_Min,
    Fraction_Denom_Display_Style_Gap_Min,
    Skewed_Fraction_Horizontal_Gap,
    Skewed_Fraction_Vertical_Gap,
    Overbar_Vertical_Gap,
    Overbar_Rule_Thickness,
    Overbar_Extra_Ascender,
    Underbar_Vertical_Gap,
    Underbar_Rule_Thickness,
    Underbar_Extra_Descender,
    Radical_Vertical_Gap,
    Radical_Display_Style_Vertical_Gap,
    Radical_Rule_Thickness,
    Radical_Extra_Ascender,
    Radical_Kern_Before_Degree,
    Radical_Kern_After_Degree,
    Radical_Degree_Bottom_Raise_Percent,
}

foreign harfbuzz_library {
    hb_version :: proc(major, minor, micro: ^u32) ---
    hb_version_string :: proc() -> cstring ---
    hb_version_atleast :: proc(major, minor, micro: u32) -> c.int ---
    hb_blob_create :: proc(
        data: rawptr, length: u32, mode: Memory_Mode,
        user_data, destroy: rawptr) -> ^Blob ---
    hb_blob_destroy :: proc(blob: ^Blob) ---
    hb_blob_get_length :: proc(blob: ^Blob) -> u32 ---
    hb_face_create :: proc(blob: ^Blob, index: u32) -> ^Face ---
    hb_face_destroy :: proc(face: ^Face) ---
    hb_face_get_glyph_count :: proc(face: ^Face) -> u32 ---
    hb_face_reference_table :: proc(face: ^Face, tag: u32) -> ^Blob ---
    hb_font_create :: proc(face: ^Face) -> ^Font ---
    hb_font_destroy :: proc(font: ^Font) ---
    hb_font_set_scale :: proc(font: ^Font, x_scale, y_scale: i32) ---
    hb_font_get_nominal_glyph :: proc(
        font: ^Font, unicode: u32, glyph: ^u32) -> c.int ---
    hb_font_get_glyph_extents :: proc(
        font: ^Font, glyph: u32, extents: ^Glyph_Extents) -> c.int ---
    hb_ot_font_set_funcs :: proc(font: ^Font) ---
    hb_buffer_create :: proc() -> ^Buffer ---
    hb_buffer_destroy :: proc(buffer: ^Buffer) ---
    hb_buffer_pre_allocate :: proc(buffer: ^Buffer, size: u32) -> c.int ---
    hb_buffer_clear_contents :: proc(buffer: ^Buffer) ---
    hb_buffer_set_direction :: proc(buffer: ^Buffer, direction: Direction) ---
    hb_buffer_set_flags :: proc(buffer: ^Buffer, flags: u32) ---
    hb_buffer_get_direction :: proc(buffer: ^Buffer) -> Direction ---
    hb_buffer_set_script :: proc(buffer: ^Buffer, script: u32) ---
    hb_buffer_get_script :: proc(buffer: ^Buffer) -> u32 ---
    hb_buffer_add_utf8 :: proc(
        buffer: ^Buffer, text: cstring, text_length: c.int,
        item_offset: u32, item_length: c.int) ---
    hb_buffer_guess_segment_properties :: proc(buffer: ^Buffer) ---
    hb_buffer_get_length :: proc(buffer: ^Buffer) -> u32 ---
    hb_buffer_get_glyph_infos :: proc(
        buffer: ^Buffer, length: ^u32) -> [^]Glyph_Info ---
    hb_buffer_get_glyph_positions :: proc(
        buffer: ^Buffer, length: ^u32) -> [^]Glyph_Position ---
    hb_shape :: proc(
        font: ^Font, buffer: ^Buffer, features: [^]Feature,
        feature_count: u32) ---
    hb_ot_math_get_glyph_italics_correction :: proc(
        font: ^Font, glyph: u32) -> i32 ---
    hb_ot_math_get_glyph_top_accent_attachment :: proc(
        font: ^Font, glyph: u32) -> i32 ---
    hb_ot_math_get_glyph_kerning :: proc(
        font: ^Font, glyph: u32, corner: Math_Kern,
        correction_height: i32) -> i32 ---
    hb_ot_math_get_glyph_kernings :: proc(
        font: ^Font, glyph: u32, corner: Math_Kern, start_offset: u32,
        entries_count: ^u32, entries: [^]Math_Kern_Entry) -> u32 ---
    hb_ot_math_get_constant :: proc(font: ^Font, constant: Math_Constant) -> i32 ---
    hb_ot_math_get_glyph_variants :: proc(
        font: ^Font, glyph: u32, direction: Direction,
        start_offset: u32, variants_count: ^u32,
        variants: [^]Math_Glyph_Variant) -> u32 ---
    hb_ot_math_get_min_connector_overlap :: proc(
        font: ^Font, direction: Direction) -> i32 ---
    hb_ot_math_get_glyph_assembly :: proc(
        font: ^Font, glyph: u32, direction: Direction, start_offset: u32,
        parts_count: ^u32, parts: [^]Math_Glyph_Part,
        italic_correction: ^i32) -> u32 ---
    hb_ot_math_is_glyph_extended_shape :: proc(face: ^Face, glyph: u32) -> c.int ---
}