package dynview_layout

import app_core "../../core"
import "../../grid"

//   Accumulated item range and vertical extents for one document layout line.
Dynview_Layout_Line_Accumulator :: struct {
    item_start: int,
    item_count: int,
    max_ascent: f32,
    max_descent: f32,
}

//   Block-level alignment, indentation, spacing, and line-height controls.
Dynview_Block_Format :: struct {
    alignment: app_core.Dynview_Text_Alignment,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
}

//   Mutable cursor and active-block state used while building document layout.
Dynview_Layout_State :: struct {
    line_index: int,
    col: int,
    row: int,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

//   Shared inputs and mutable accumulators for one document layout build.
Dynview_Layout_Build_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
    grid_metrics: grid.Cell_Metrics,
}
