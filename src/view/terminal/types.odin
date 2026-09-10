package terminalview

import "../../core"
import "../../core/protocol"
import termattachment "../../terminal/attachment"
import termgrid "../../terminal/grid"
import termhyperlink "../../terminal/hyperlink"
import termmodel "../../terminal/model"
import termpalette "../../terminal/palette"
import "../font"
import "../input"

import rl "vendor:raylib"

// Caller-visible evaluation submission produced by one keyboard update.
Terminal_Submission :: struct {
    text: string,
    submitted: bool,
}

// Correlated completion query snapshot for one exact code/cursor state.
Terminal_Completion_Request :: struct {
    requested: bool,
    request_id: protocol.Request_Id,
    code: string,
    cursor_byte: int,
    show_candidates: bool,
}

// Correlated Julia completion replacement rendered before user acceptance.
Terminal_Completion_Preview :: struct {
    request_id: protocol.Request_Id,
    found: bool,
    replacement_start: int,
    replacement_end: int,
    insertion: string,
}

// Internal submission, completion, and cursor effects from one keyboard frame.
Terminal_Keyboard_Update :: struct {
    submission: Terminal_Submission,
    completion: Terminal_Completion_Request,
    cursor_moved: bool,
}

// Frame-local actionable link category.
Terminal_Link_Kind :: enum u8 {None, Osc8, Detected}

// Bounded explicit or inferred link under one eligible pointer position.
Terminal_Link_Hit :: struct {
    kind: Terminal_Link_Kind,
    handle: termmodel.Hyperlink_Handle,
    uri: [termhyperlink.HYPERLINK_URI_BYTE_CAPACITY]u8,
    uri_byte_count: int,
    line: int,
    column_start: int,
    column_end: int,
    identity_hash: u64,
}

// Release-confirmed request to activate one terminal hyperlink.
Terminal_Hyperlink_Activation :: struct {
    kind: Terminal_Link_Kind,
    handle: termmodel.Hyperlink_Handle,
    uri: [termhyperlink.HYPERLINK_URI_BYTE_CAPACITY]u8,
    uri_byte_count: int,
    requested: bool,
}

// Semantic command-block range selected through local terminal actions.
Terminal_Command_Range :: enum u8 {Command, Output}

// One bounded command-text candidate with grapheme-boundary view positions.
Terminal_Command_Search_Workspace :: struct {
    text: [TERMINAL_COMMAND_SEARCH_TEXT_BYTE_CAPACITY]u8,
    boundaries: [TERMINAL_COMMAND_SEARCH_POSITION_CAPACITY]bool,
    positions: [TERMINAL_COMMAND_SEARCH_POSITION_CAPACITY]core.Terminal_View_Position,
    byte_count: int,
}

// Resolved view endpoints for one semantic command or output range.
Terminal_Command_View_Range :: struct {
    start: core.Terminal_View_Position,
    end: core.Terminal_View_Position,
    valid: bool,
}

// One candidate match ordered by command index then command-local byte offset.
Terminal_Command_Search_Match :: struct {
    block: termmodel.Command_Block,
    start: core.Terminal_View_Position,
    end: core.Terminal_View_Position,
    block_index: int,
    byte_offset: int,
    valid: bool,
}

// Display-thread boundary used to activate a validated NUL-terminated URI.
Terminal_Hyperlink_Activation_Proc :: proc(
    user_data: rawptr, uri: cstring) -> bool

// Optional display-thread hyperlink activation destination.
Terminal_Hyperlink_Activation_Sink :: struct {
    user_data: rawptr,
    activate: Terminal_Hyperlink_Activation_Proc,
}

// Display-thread boundary used to publish one validated clipboard value.
Terminal_Clipboard_Write_Proc :: proc(user_data: rawptr, text: string) -> bool

// Optional display-thread clipboard write destination.
Terminal_Clipboard_Write_Sink :: struct {
    user_data: rawptr,
    write: Terminal_Clipboard_Write_Proc,
}

// Caller-visible terminal actions produced by one complete input frame.
Terminal_Frame_Update :: struct {
    submission: Terminal_Submission,
    completion: Terminal_Completion_Request,
    geometry_change: Terminal_Geometry_Change,
    hyperlink_activation: Terminal_Hyperlink_Activation,
}

// One committed logical geometry transition returned to the display owner.
Terminal_Geometry_Change :: struct {
    changed: bool,
    previous: protocol.Terminal_Dimensions,
    current: protocol.Terminal_Dimensions,
    generation: u64,
}

// Measured terminal cell pitch and total internal viewport insets.
Terminal_Cell_Metrics :: struct {
    column_width: f32,
    line_height: f32,
    horizontal_inset: f32,
    vertical_inset: f32,
}

// Result of deriving one bounded cell geometry from visible pixel space.
Terminal_Dimension_Candidate :: struct {
    dimensions: protocol.Terminal_Dimensions,
    valid: bool,
}

// Complete two-grid and checkpoint replacement held until one owner-thread commit.
Prepared_Terminal_Resize :: struct {
    primary: termgrid.Prepared_Primary_Reflow,
    alternate: termgrid.Prepared_Grid_Resize,
    placements: termattachment.Placement_Checkpoint,
    selection_anchor: core.Terminal_View_Position,
    selection_head: core.Terminal_View_Position,
    selection_retained: bool,
    scroll_offset_y: f32,
    checkpoint: termgrid.Display_Checkpoint,
    synchronized_checkpoint: termgrid.Display_Checkpoint,
}

// Borrowed context used to relocate primary placement anchors through reflow.
Terminal_Placement_Reflow_Context :: struct {
    primary: ^termgrid.Prepared_Primary_Reflow,
}

// Superseded grid resources released after an infallible prepared publication.
Terminal_Superseded_Display :: struct {
    primary: termgrid.Grid,
    alternate: termgrid.Grid,
}

// Frame-local terminal geometry and selection used by the draw pipeline.
Terminal_Draw_Layout :: struct {
    padded_bounds: rl.Rectangle,
    line_height: f32,
    line_count: int,
    prompt_visible: bool,
    content_height: f32,
    selection: Terminal_Selection_Bounds,
    regular: rl.Font,
    theme: Terminal_Draw_Theme,
}

// Frame-local semantic colors supplied by the terminal container owner.
Terminal_Draw_Theme :: struct {
    default_foreground: rl.Color,
    cursor_foreground: rl.Color,
    selection_foreground: rl.Color,
    selection_background: rl.Color,
}

// Complete frame-local request for terminal input and geometry update.
Terminal_Update_Request :: struct {
    frame: input.Input_Frame,
    now: f64,
    font: rl.Font,
    bounds: rl.Rectangle,
    update_geometry: bool,
}

// Complete frame-local request for terminal presentation.
Terminal_Draw_Request :: struct {
    bounds: rl.Rectangle,
    frame: input.Input_Frame,
    theme: Terminal_Draw_Theme,
}

// Frame-local presentation inputs supplied by the UI-owned scroll container.
Terminal_Draw_Content_Context :: struct {
    layout: Terminal_Draw_Layout,
    origin: rl.Vector2,
    bounds: rl.Rectangle,
    frame: input.Input_Frame,
}

// Frame-local source and destination geometry for one raster placement.
Terminal_Raster_Geometry :: struct {
    source: termattachment.Pixel_Rectangle,
    destination: termattachment.Render_Rectangle,
    valid: bool,
}

// One raster z-index partition drawn on a specific side of terminal text.
Terminal_Raster_Layer :: enum {Behind_Text, In_Front_Of_Text}

// Shared layout and layer state for drawing one terminal raster placement.
Terminal_Raster_Draw_Context :: struct {
    layout: Terminal_Draw_Layout,
    origin: rl.Vector2,
    layer: Terminal_Raster_Layer,
    column_width: f32,
}

// Frame-local placement of the interpreter-owned output cursor.
Terminal_Output_Cursor_Style :: enum {Filled, Outline}

// Frame-local output cursor placement in combined scrollback/grid coordinates.
Terminal_Output_Cursor_Presentation :: struct {
    visible: bool,
    style: Terminal_Output_Cursor_Style,
    line: int,
    column: int,
    width: int,
}

// Byte ranges excluded from prompt shaping by interactive overlays.
Terminal_Prompt_Shape_Exclusions :: struct {
    cursor_start: int,
    cursor_end: int,
    selection_start: int,
    selection_end: int,
}

// Complete state for drawing one prompt row and its shaped text fragments.
Terminal_Prompt_Draw :: struct {
    resolver: font.Font_Resolver,
    current_text: string,
    prompt_prefix: string,
    prompt_color: rl.Color,
    position: rl.Vector2,
    exclusions: Terminal_Prompt_Shape_Exclusions,
    theme: Terminal_Draw_Theme,
}

// Complete state for drawing one single-line prompt and its overlays.
Terminal_Single_Line_Prompt_Draw :: struct {
    term: ^core.Terminal_State,
    resolver: font.Font_Resolver,
    layout: Terminal_Draw_Layout,
    position: rl.Vector2,
    regular: rl.Font,
    current_text: string,
    prompt_prefix: string,
}

// Complete state for drawing one physical row of a multiline prompt.
Terminal_Multiline_Prompt_Row_Draw :: struct {
    term: ^core.Terminal_State,
    resolver: font.Font_Resolver,
    text: string,
    prompt_color: rl.Color,
    position: rl.Vector2,
    line: int,
    line_start: int,
    cursor: int,
    theme: Terminal_Draw_Theme,
}

// Complete state for drawing one eligible shaped cell run.
Terminal_Shaped_Run_Draw :: struct {
    resolver: font.Font_Resolver,
    cells: []termgrid.Cell,
    start_column: int,
    position: rl.Vector2,
    column_width: f32,
    key: font.Font_Key,
    color: rl.Color,
}

// Shared immutable inputs for one attempted shaped output chunk.
Terminal_Shaped_Output_Context :: struct {
    resolver: font.Font_Resolver,
    cells: []termgrid.Cell,
    position: rl.Vector2,
    palette: ^termpalette.Terminal_Palette_State,
    column_width: f32,
    theme: Terminal_Draw_Theme,
}

// Complete state for drawing shaped and fallback prompt text fragments.
Terminal_Prompt_Text_Draw :: struct {
    resolver: font.Font_Resolver,
    regular: rl.Font,
    current_text: string,
    position: rl.Vector2,
    exclusions: Terminal_Prompt_Shape_Exclusions,
    color: rl.Color,
}

// Shared text, placement, font, and theme for cursor and selection overlays.
Terminal_Text_Overlay_Draw :: struct {
    resolver: font.Font_Resolver,
    font: rl.Font,
    text: string,
    position: rl.Vector2,
    theme: Terminal_Draw_Theme,
}

// Fixed stack workspace for preparing one shaped terminal run without allocation.
Terminal_Shaped_Run_Workspace :: struct {
    text_storage: [TERMINAL_SHAPING_CAPACITY]u8,
    cell_offsets: [TERMINAL_SHAPING_RUN_COLUMNS + 1]int,
    cell_columns: [TERMINAL_SHAPING_RUN_COLUMNS + 1]int,
    shaped_glyphs: [TERMINAL_SHAPING_CAPACITY]font.Shaped_Glyph,
    source_columns: [TERMINAL_SHAPING_CAPACITY]int,
    glyph_count: int,
}