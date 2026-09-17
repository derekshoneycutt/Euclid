package input

import "../../core/protocol"

// Stable physical keys understood by input routing and terminal encoding.
//
// Values are independent of raylib and may cross device, scenario, and policy boundaries.
Input_Key :: enum {
    Space,
    Apostrophe,
    Comma,
    Minus,
    Period,
    Slash,
    Digit0,
    Digit1,
    Digit2,
    Digit3,
    Digit4,
    Digit5,
    Digit6,
    Digit7,
    Digit8,
    Digit9,
    Semicolon,
    Equal,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    Left_Bracket,
    Backslash,
    Right_Bracket,
    Grave,
    Escape,
    Enter,
    Tab,
    Backspace,
    Insert,
    Delete,
    Right,
    Left,
    Down,
    Up,
    Page_Up,
    Page_Down,
    Home,
    End,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    Keypad0,
    Keypad1,
    Keypad2,
    Keypad3,
    Keypad4,
    Keypad5,
    Keypad6,
    Keypad7,
    Keypad8,
    Keypad9,
    Keypad_Decimal,
    Keypad_Divide,
    Keypad_Multiply,
    Keypad_Subtract,
    Keypad_Add,
    Keypad_Enter,
    Keypad_Equal,
    Count,
}

// Modifier levels captured with one input event.
Input_Modifier :: enum {
    Control,
    Shift,
    Alt,
    Super,
}

// Modifier combination captured atomically with one input event.
Input_Modifiers :: bit_set[Input_Modifier; u8]

// Device-independent event kinds retained in deterministic frame order.
Input_Event_Kind :: enum {
    Press,
    Repeat,
    Release,
    Text,
}

// Source category used to prevent synthetic and device events from being paired.
Input_Event_Origin :: enum u8 {
    Unknown,
    Device,
    Synthetic,
}

// Reciprocal frame-local relationship between one physical event and bounded text.
Input_Event_Correlation :: struct {
    partner_index: u16,
    partner_count: u16,
    valid: bool,
}

// One bounded keyboard or Unicode text event.
Input_Event :: struct {
    kind: Input_Event_Kind,
    key: Input_Key,
    modifiers: Input_Modifiers,
    codepoint: rune,
    origin: Input_Event_Origin,
    correlation: Input_Event_Correlation,
}

// Stable destination classes that may own reversible text composition.
Input_Text_Owner_Kind :: enum u8 {
    None,
    Terminal_Editor,
}

// Generational editor identity preventing preedit from crossing focus lifetimes.
Input_Text_Owner :: struct {
    kind: Input_Text_Owner_Kind,
    id: u64,
    generation: u64,
}

// Half-open UTF-8 byte range selected within one preedit snapshot.
Input_Composition_Selection :: struct {
    start: int,
    end: int,
}

// Borrowed reversible text state routed with one input frame.
Input_Composition :: struct {
    owner: Input_Text_Owner,
    preedit: string,
    selection: Input_Composition_Selection,
    active: bool,
}

// Device-independent screen-space mouse coordinates.
Input_Position :: struct {
    x: f32,
    y: f32,
}

// Mouse buttons supported by SGR terminal reporting.
Input_Mouse_Button :: enum u8 {
    Left,
    Middle,
    Right,
}

Input_Mouse_Buttons :: bit_set[Input_Mouse_Button; u8]

// Independently routable pointer fields in one input-frame value copy.
Input_Pointer_Field :: enum u8 {
    Screen_Position,
    Motion,
    Press_Edges,
    Release_Edges,
    Levels,
    Wheel,
    Terminal_Position,
    Terminal_Ownership,
}

Input_Pointer_Fields :: bit_set[Input_Pointer_Field; u8]

INPUT_POINTER_FIELDS_ALL :: Input_Pointer_Fields{
    .Screen_Position,
    .Motion,
    .Press_Edges,
    .Release_Edges,
    .Levels,
    .Wheel,
    .Terminal_Position,
    .Terminal_Ownership,
}

// One-based live terminal-grid coordinates resolved by the UI.
Input_Terminal_Position :: struct {
    column: int,
    row: int,
}

// Borrowed once-per-frame input snapshot spanning keyboard, focus, and pointer state.
//
// Device polling fills the event, focus, and screen-space mouse fields. Terminal UI
// hit testing later copies the frame and resolves live-grid coordinates plus ownership.
// Only `events` borrows runtime storage; every other field is a frame-local value.
Input_Frame :: struct {
    // Ordered physical-key and text events retained by Input_Runtime until the next poll.
    events: []Input_Event,

    // Reversible text owned by the focused editor. This never mutates destination text.
    composition: Input_Composition,

    // Current window focus and whether it changed from the preceding known sample.
    window_focused: bool,
    window_focus_changed: bool,

    // Raw once-per-frame pointer sample in screen coordinates. `mouse_moved` is false
    // for the first known sample and true only when the device position changed.
    // Button edge sets contain transitions observed this frame; `mouse_down` contains
    // current button levels.
    mouse_position: Input_Position,
    mouse_moved: bool,
    mouse_modifiers: Input_Modifiers,
    mouse_pressed: Input_Mouse_Buttons,
    mouse_released: Input_Mouse_Buttons,
    mouse_down: Input_Mouse_Buttons,

    // Signed vertical wheel movement; magnitude is device data, not protocol report count.
    mouse_wheel_delta: f32,

    // Monotonic device-boundary time used by frame-local UI animation policy.
    sample_time_seconds: f64,

    // UI-resolved one-based live-grid cell and content-pixel locations. Valid positions
    // may be edge-clamped while outside so an admitted drag can still release correctly.
    terminal_mouse_position: Input_Terminal_Position,
    terminal_mouse_pixel_position: Input_Terminal_Position,
    terminal_mouse_position_valid: bool,
    terminal_mouse_inside: bool,
    // False when local UI arbitration, currently Shift override, owns mouse activity.
    terminal_mouse_owned: bool,

    // UI-routed effective focus. Production Terminal frames always mark it known.
    terminal_focus_known: bool,
    terminal_focused: bool,
    terminal_focus_changed: bool,
}

// Exclusive destination for bytes retained across display frames.
Input_Owner_Kind :: enum u8 {
    None,
    Terminal_Session,
    Julia_Interactive,
}

// Generational identity preventing retained bytes from reaching a later consumer.
Input_Owner :: struct {
    kind: Input_Owner_Kind,
    id: u64,
    generation: u64,
}

// Validated semantic chord retained in one active or staged registry snapshot.
Input_Hotkey_Binding :: struct {
    action: protocol.Logical_Action,
    key: Input_Key,
    modifiers: Input_Modifiers,
    scope: protocol.Hotkey_Scope,
}

// First registered semantic action matched to its device-frame event position.
Input_Hotkey_Match :: struct {
    action: protocol.Logical_Action,
    event_index: int,
}

// Return a value copy exposing only the selected pointer field classes.
//
// The event slice and all non-pointer fields remain borrowed and unchanged. A caller
// may provide an off-surface screen position when hidden coordinates must not hit-test.
input_frame_filter_pointer :: proc(
    frame: Input_Frame, fields: Input_Pointer_Fields,
    hidden_position: Input_Position = {}) -> Input_Frame {
    result := frame
    if .Screen_Position not_in fields { result.mouse_position = hidden_position }
    if .Motion not_in fields { result.mouse_moved = false }
    if .Press_Edges not_in fields { result.mouse_pressed = {} }
    if .Release_Edges not_in fields { result.mouse_released = {} }
    if .Levels not_in fields { result.mouse_down = {} }
    if .Wheel not_in fields { result.mouse_wheel_delta = 0 }
    if .Terminal_Position not_in fields {
        result.terminal_mouse_position = {}
        result.terminal_mouse_pixel_position = {}
        result.terminal_mouse_position_valid = false
    }
    if .Terminal_Ownership not_in fields {
        result.terminal_mouse_inside = false
        result.terminal_mouse_owned = false
    }
    return result
}

// Return routed effective focus, defaulting isolated non-routed calls to focused.
input_frame_terminal_focused :: #force_inline proc(frame: Input_Frame) -> bool {
    return frame.terminal_focused || !frame.terminal_focus_known
}

