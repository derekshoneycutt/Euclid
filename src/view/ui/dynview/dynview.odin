package dynview

import "../../../core"
import view_core "../../core"

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

Mouse_Input_State :: view_core.Mouse_Input_State

UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR

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
    y_offset: f32,
    line_gap: f32,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

Dynview_Layout_Build_Context :: struct {
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
}

Dynview_Delimiter_Family :: enum {
    None,
    Paren,
    Bracket,
    Brace,
    Vert,
    DoubleVert,
    Ceil,
    Floor,
    Angle,
}
