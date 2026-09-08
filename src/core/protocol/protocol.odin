package protocol

// Package protocol defines the typed messages exchanged between the display and
// Julia worker threads. Dynamic strings belong to the producing communication
// link and remain borrowed by the consumer until it returns the message envelope.

// Correlates one request with every intermediate and final result it produces.
// Zero means no active request; request owners issue monotonically increasing IDs.
Request_Id :: distinct u64





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
