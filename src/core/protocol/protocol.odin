package protocol

// Package protocol defines the typed messages exchanged between the display and
// Julia worker threads. Dynamic strings belong to the producing communication
// link and remain borrowed by the consumer until it returns the message envelope.

// Correlates one request with every intermediate and final result it produces.
// Zero means no active request; request owners issue monotonically increasing IDs.
Request_Id :: distinct u64

// Positive terminal viewport size measured in character cells.
Terminal_Dimensions :: struct {
    columns: u16,
    rows: u16,
}

// Inclusive policy bounds for accepted terminal dimensions.
Terminal_Dimension_Limits :: struct {
    minimum: Terminal_Dimensions,
    maximum: Terminal_Dimensions,
}

// Odin-owned accepted terminal geometry and its monotonic change generation.
Terminal_Geometry :: struct {
    dimensions: Terminal_Dimensions,
    generation: u64,
    column_width: f32,
    line_height: f32,
}

// Version of the stable terminal capability snapshot understood by both hosts.
TERMINAL_CAPABILITY_VERSION :: u16(3)

// Maximum source bytes retained for evaluation and completion correlation.
TERMINAL_RETAINED_TEXT_MAX_BYTES :: 64 * 1024

// Text encoding implemented by the display-owned terminal surface.
Terminal_Text_Encoding :: enum u8 {
    Unknown,
    Utf8,
}

// Highest color model implemented by the display-owned terminal surface.
Terminal_Color_Level :: enum u8 {
    Unknown,
    None,
    Ansi16,
    Indexed256,
    Truecolor,
}

// Stable terminal feature bits independent of negotiated active modes.
Terminal_Capability_Feature :: enum u32 {
    Alternate_Screen,
    Bracketed_Paste,
    Focus_Events,
    Sgr_Mouse,
    Query_Modify_Other_Keys,
    Query_Kitty_Keyboard,
    Query_Primary_Device_Attributes,
    Hyperlinks,
    Clipboard_Writes,
    Synchronized_Output,
    Query_Secondary_Device_Attributes,
    Query_Device_Status,
    Query_Cursor_Position,
    Query_Private_Mode_Status,
    Query_Window_Pixels,
    Query_Cell_Pixels,
    Query_Text_Area_Size,
    Kitty_Graphics,
    Sixel_Graphics,
    Iterm2_Inline_Images,
}

// Immutable host capability snapshot independent of dynamic terminal geometry.
Terminal_Capabilities :: struct {
    version: u16,
    encoding: Terminal_Text_Encoding,
    color: Terminal_Color_Level,
    modify_other_keys_level: u8,
    kitty_keyboard_flags: u8,
    features: bit_set[Terminal_Capability_Feature; u32],
}

// User intent interpreted by Julia policy rather than directly by display code.
Logical_Action :: enum i32 {
    Toggle_Terminal = 1,
}

// Portable physical keys accepted in Julia-registered semantic chords.
Hotkey_Key :: enum i32 {
    A = 1, B, C, D, E, F, G, H, I, J, K, L, M,
    N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

// Routing scope selected by Julia and validated by the display owner.
Hotkey_Scope :: enum i32 {
    Application = 1,
    Reserved_Global = 2,
}

// Stable whole-snapshot validation result.
Hotkey_Registry_Reason :: enum i32 {
    None = 0,
    Invalid_Generation,
    Invalid_Count,
    Invalid_Index,
    Duplicate_Index,
    Duplicate_Chord,
    Unknown_Action,
    Unknown_Key,
    Invalid_Modifiers,
    Invalid_Scope,
    Builtin_Conflict,
    Incomplete,
}

// Opens staging for one complete hotkey registry generation.
Hotkey_Registry_Begin :: struct {
    generation: u64,
    expected_count: i32,
}

// Defines one indexed semantic binding in the staged registry generation.
Hotkey_Registry_Entry :: struct {
    // Snapshot identity and zero-based position within the transaction.
    generation: u64,
    index: i32,

    // Semantic action, exact physical chord, and routing scope.
    action: Logical_Action,
    key: Hotkey_Key,
    modifiers: u8,
    scope: Hotkey_Scope,
}

// Requests atomic validation and activation of one staged generation.
Hotkey_Registry_Commit :: struct {generation: u64}

// Reports the whole-snapshot outcome for one committed generation.
Hotkey_Registry_Result :: struct {
    // Correlated generation and atomic acceptance outcome.
    generation: u64,
    accepted: bool,

    // First rejection detail; the index is negative when no entry caused it.
    reason: Hotkey_Registry_Reason,
    offending_index: i32,
}

// Prompt language selected for one evaluation and its history entry.
Evaluation_Mode :: enum {
    Normal,
    Help,
    Pkg,
    Shell,
}

// Maximum terminal-control and complete UTF-8 bytes delivered in one input batch.
TERMINAL_INTERACTIVE_INPUT_MAX_BYTES :: 16

// Correlated source submission for one animation-owned Terminal session.
Evaluation_Requested :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    code: string,
    mode: Evaluation_Mode,
}

// Completion ranges use UTF-8 byte offsets into an immutable source snapshot.
Completion_Requested :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    code: string,
    cursor_byte: int,
    show_candidates: bool,
}

// Bounded keyboard-byte chunk for Julia's active interactive-input request.
Terminal_Interactive_Input :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    bytes: [TERMINAL_INTERACTIVE_INPUT_MAX_BYTES]u8,
    byte_count: int,
}

// Announces one display-owned Terminal animation generation to the Julia owner.
Terminal_Session_Started :: struct {animation_generation: u64}

// Retires one display-owned Terminal animation generation from the Julia owner.
Terminal_Session_Closed :: struct {animation_generation: u64}

// Confirms installation or shutdown of one generation-scoped Terminal tick stream.
Tick_Stream_Configuration_Acknowledged :: struct {
    animation_generation: u64,
    stream_generation: u64,
    interval_steps: u64,
    active: bool,
}

// Publishes one contiguous range of display-owned fixed simulation updates.
Tick_Pulse :: struct {
    animation_generation: u64,
    stream_generation: u64,
    sequence: u64,
    first_simulation_tick: u64,
    last_simulation_tick: u64,
    step_count: u64,
}

// Publishes accepted display geometry in monotonic generation order.
Terminal_Geometry_Accepted :: struct {
    animation_generation: u64,
    geometry: Terminal_Geometry,
}

// Publishes the immutable display capability snapshot for one Terminal generation.
Terminal_Capabilities_Accepted :: struct {
    animation_generation: u64,
    capabilities: Terminal_Capabilities,
}

// Ordered worker-owned output borrowed by the display until envelope return.
Terminal_Output_Batch :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    bytes: string,
    truncated_bytes: u64,
}

// Reports that an evaluation needs more source before execution can complete.
Evaluation_Incomplete :: struct {
    request_id: Request_Id,
    animation_generation: u64,
}

// Reports the terminal outcome of one correlated evaluation.
Evaluation_Completed :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    succeeded: bool,
}

// Correlated completion replacement borrowed from the worker-owned envelope.
Completion_Result :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    found: bool,
    replacement_start: int,
    replacement_end: int,
    insertion: string,
    show_candidates: bool,
}

// Stable reason one correlated completion request could not produce a result.
Completion_Failure_Reason :: enum i32 {
    Mailbox_Full = 1,
    Runtime_Stopped,
    Internal_Failure,
    Duplicate_Request,
}

// Terminal failure for one correlated completion request.
Completion_Failed :: struct {
    request_id: Request_Id,
    animation_generation: u64,
    reason: Completion_Failure_Reason,
}

// Grants terminal bytes to one Julia interactive-input request.
Terminal_Input_Acquired :: struct {
    request_id: Request_Id,
    animation_generation: u64,
}

// Releases one Julia interactive-input request from terminal routing.
Terminal_Input_Released :: struct {
    request_id: Request_Id,
    animation_generation: u64,
}

// Confirms Julia observed the exact accepted display geometry.
Terminal_Geometry_Observed :: struct {
    animation_generation: u64,
    geometry: Terminal_Geometry,
}

// Confirms Julia observed the exact immutable capability snapshot.
Terminal_Capabilities_Observed :: struct {
    animation_generation: u64,
    capabilities: Terminal_Capabilities,
}

// Confirms Julia installed one Terminal generation and carries its startup banner.
Terminal_Session_Ready :: struct {
    animation_generation: u64,
    banner: string,
}

// Confirms Julia retired one Terminal animation generation.
Terminal_Session_Stopped :: struct {animation_generation: u64}

// Requests one demand-driven fixed-update stream for a Terminal generation.
Tick_Stream_Configure_Requested :: struct {
    animation_generation: u64,
    stream_generation: u64,
    requested_period_ns: u64,
}

// Requests idempotent shutdown of one exact Terminal tick stream.
Tick_Stream_Stop_Requested :: struct {
    animation_generation: u64,
    stream_generation: u64,
}

// Display-to-worker telemetry, evaluation, and interaction requests.
//
// Request IDs correlate asynchronous results. Dynamic source strings are owned
// by the display link and borrowed by the worker until envelope return.
// Empty telemetry probe requesting confirmation that the worker remains responsive.
Heartbeat_Requested :: struct {}

// Semantic hotkey action paired with the display state observed at dispatch.
Hotkey_Triggered :: struct {
    action: Logical_Action,
    current_terminal_visibility: bool,
    decision_id: u64,
}
