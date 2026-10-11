// Package termmodel defines dependency-light values shared by terminal subsystems.
package termmodel

// Compact identity of one terminal-lifetime hyperlink registry entry.
Hyperlink_Handle :: distinct u32

// Renderer-facing font-weight selection stored with each leading cell.
Font_Weight :: enum {
    Regular,
    Light,
    Medium,
    Semi_Bold,
    Bold,
    Extra_Bold,
    Black,
}

// Semantic source retained for one terminal rendition color.
Terminal_Color_Kind :: enum u8 {
    Default,
    Indexed,
    Direct,
}

// Packed color identity resolved against display-owned palette state at draw time.
Terminal_Color_Reference :: distinct u32

// Output-stream categories that may negotiate terminal replies.
Terminal_Producer_Kind :: enum u8 {
    None,
    Terminal_Session,
    Julia_Evaluation,
}

// Neutral identity of the output stream that produced one semantic reply.
Terminal_Producer :: struct {
    kind: Terminal_Producer_Kind,
    id: u64,
    generation: u64,
}

// Semantic OSC 133 marker classes retained in row metadata.
Shell_Marker_Kind :: enum u8 {
    Prompt,
    Command,
    Execution,
    Finished,
}

// Compact shell positions and optional completion status for one physical row.
Shell_Row_Markers :: struct {
    columns: [Shell_Marker_Kind]u16,
    present: [Shell_Marker_Kind]bool,
    finished_status: i32,
    finished_status_present: bool,
}

// Stable identity of one hard-bounded line across physical row replacement.
Terminal_Logical_Line_Id :: distinct i64

// Stable terminal-content position used by command-block consumers.
Terminal_Semantic_Position :: struct {
    // Identity inherited from the first physical row in the logical line.
    logical_line_id: Terminal_Logical_Line_Id,

    // Leading-grapheme ordinal from the logical line's retained head.
    grapheme_offset: u32,
}

// One retained OSC 133 lifecycle assembled from validated marker admissions.
Command_Block :: struct {
    generation: u32,
    prompt: Terminal_Semantic_Position,
    command: Terminal_Semantic_Position,
    execution: Terminal_Semantic_Position,
    finished: Terminal_Semantic_Position,
    status: i32,
    present: bit_set[Shell_Marker_Kind; u8],
    status_present: bool,
}

// Mouse event classes negotiated through DEC private modes.
Terminal_Mouse_Tracking_Mode :: enum u8 {
    None,
    Button,
    Button_Motion,
    Any_Motion,
}

// Terminal input-encoding modes derived exclusively from child output.
Terminal_Input_Mode :: struct {
    cursor_keys_application: bool,
    keypad_application: bool,
    bracketed_paste: bool,
    focus_reporting: bool,
    mouse_tracking: Terminal_Mouse_Tracking_Mode,
    mouse_sgr_encoding: bool,
    mouse_pixel_coordinates: bool,
}

// Bounded semantic reply kinds retained without arbitrary child bytes.
Terminal_Response_Kind :: enum u8 {
    Modify_Other_Keys,
    Kitty_Keyboard,
    Primary_Device_Attributes,
    Secondary_Device_Attributes,
    Device_Status,
    Cursor_Position,
    Private_Mode_Status,
    Window_Pixels,
    Cell_Pixels,
    Text_Area_Size,
    Osc_Color,
    Mode_Status,
    Decrqss_Sgr,
    Decrqss_Cursor_Style,
    Decrqss_Margins,
    Decrqss_Unsupported,
    Xtgetcap,
}

// One producer-correlated semantic reply awaiting byte-ring admission.
Terminal_Response :: struct {
    kind: Terminal_Response_Kind,
    first: u32,
    second: u32,
    third: u32,
    producer: Terminal_Producer,
}

// Last display-owned pixel geometry available to window-report queries.
Terminal_Query_Geometry :: struct {
    window_width: u32,
    window_height: u32,
    cell_width: u32,
    cell_height: u32,
    valid: bool,
}