package dynview

import "../core"
import "../grid"

import rl "vendor:raylib"

UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

DYNVIEW_INVALIDATE_CONTENT :: (1 << 0)
DYNVIEW_INVALIDATE_PANEL :: (1 << 1)
DYNVIEW_INVALIDATE_FONT :: (1 << 2)
DYNVIEW_INVALIDATE_STYLE :: (1 << 3)

DYNVIEW_ENABLED_DEFAULT :: true

DYNVIEW_STATUS_OK :: 0
DYNVIEW_STATUS_INVALID_ARGUMENT :: 2
DYNVIEW_STATUS_OUT_OF_CAPACITY :: 5
DYNVIEW_STATUS_ILLEGAL_STATE :: 6

TEXT_PADDING :: 8

LARGE_OP_KIND_NONE :: 0
LARGE_OP_KIND_SUM :: 1
LARGE_OP_KIND_PROD :: 2
LARGE_OP_KIND_INT :: 3
LARGE_OP_KIND_LIM :: 4

OPERATOR_GROWTH_NONE :: 0
OPERATOR_GROWTH_DISPLAY :: 1
OPERATOR_LIMITS_NONE :: 0
OPERATOR_LIMITS_SIDE :: 1
OPERATOR_LIMITS_STACKED :: 2

DELIMITER_KIND_NONE :: 0
DELIMITER_KIND_LEFT_PAREN :: 1
DELIMITER_KIND_RIGHT_PAREN :: 2
DELIMITER_KIND_LEFT_BRACKET :: 3
DELIMITER_KIND_RIGHT_BRACKET :: 4
DELIMITER_KIND_LEFT_BRACE :: 5
DELIMITER_KIND_RIGHT_BRACE :: 6
DELIMITER_KIND_VERT :: 7
DELIMITER_KIND_DOUBLE_VERT :: 8
DELIMITER_KIND_LEFT_CEIL :: 9
DELIMITER_KIND_RIGHT_CEIL :: 10
DELIMITER_KIND_LEFT_FLOOR :: 11
DELIMITER_KIND_RIGHT_FLOOR :: 12
DELIMITER_KIND_LEFT_ANGLE :: 13
DELIMITER_KIND_RIGHT_ANGLE :: 14
DELIMITER_KIND_COUNT :: 14

// Style schema revision used for cache invalidation when style mapping changes.
DYNVIEW_STYLE_REVISION_PLAIN_TEXT :: 3

DYNVIEW_STYLE_DEFAULT :: 0
DYNVIEW_STYLE_PROMPT :: 1
DYNVIEW_STYLE_OUTPUT :: 2
DYNVIEW_STYLE_ERROR :: 3
DYNVIEW_STYLE_BOLD :: 10
DYNVIEW_STYLE_ITALIC :: 11
DYNVIEW_STYLE_CENTER :: 12
DYNVIEW_STYLE_MEDIUM :: 13
DYNVIEW_STYLE_SEMIBOLD :: 14
DYNVIEW_STYLE_EXTRABOLD :: 15
DYNVIEW_STYLE_BLACK :: 16
DYNVIEW_STYLE_UNDERLINE :: 17
DYNVIEW_STYLE_INLINE_ATOM :: 20

DYNVIEW_STYLE_CUSTOM_FONT :: (1 << 24)
DYNVIEW_STYLE_CUSTOM_FONT_MASK :: 0xFF

Dynview_Text_Alignment :: core.Dynview_Text_Alignment
Dynview_Text_Style :: core.Dynview_Text_Style

Dynview_Compile_State :: struct {
    plain_text_builder: core.Bounded_Byte_Builder,
    copy_payload_builder: core.Bounded_Byte_Builder,
    copy_block_builder: core.Bounded_Element_Builder(core.Dynview_Copy_Block),
    open_block: bool,
    block_id: i32,
    block_kind: i32,
    block_row_start: int,
    block_row_end: int,
    block_payload_start: int,
    block_has_copy_payload: bool,
    current_row: int,
}

Dynview_Layout_Line_Accumulator :: struct {
    item_start: int,
    item_count: int,
    max_ascent: f32,
    max_descent: f32,
}

Dynview_Block_Format :: struct {
    alignment: Dynview_Text_Alignment,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
}

Dynview_Layout_State :: struct {
    line_index: int,
    col: int,
    row: int,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

Dynview_Layout_Build_Context :: struct {
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
    grid_metrics: grid.Cell_Metrics,
}

Dynview_Delimiter_Family :: enum {
    None,
    Paren,
    Bracket,
    Brace,
    Vert,
    Double_Vert,
    Ceil,
    Floor,
    Angle,
}
