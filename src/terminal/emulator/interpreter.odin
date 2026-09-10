package termemulator

import "core:unicode/utf8"
import termattachment "../attachment"
import termclipboard "../clipboard"
import gfxprotocol "../graphics/protocol"
import gfxsemantics "../graphics/semantics"
import termgrid "../grid"
import termhyperlink "../hyperlink"
import termmodel "../model"
import termpalette "../palette"
import termshellintegration "../shell_integration"

// Fixed parser limits bound CSI parameter storage, numeric values, and bytes held
// before an overlong CSI or OSC enters a terminator-aware discard state.
CSI_PARAMETER_CAPACITY :: 16
CSI_SEQUENCE_BYTE_CAPACITY :: 64
CSI_PARAMETER_MAX :: 9999
CSI_COLON_PARAMETER_OFFSET :: CSI_PARAMETER_MAX + 1
OSC_SEQUENCE_BYTE_CAPACITY :: 4096
TERMINAL_TITLE_BYTE_CAPACITY :: 256
TERMINAL_QUERY_BYTE_CAPACITY :: 256

// Incremental terminal-control parser state.
//
// CSI and OSC discard states consume rejected payloads through their proper final
// byte or terminator so arbitrary chunks cannot leak control bytes into grid text.
Interpreter_State :: enum {
    Ground,
    Escape,
    Escape_Intermediate,
    Csi,
    Csi_Intermediate,
    Csi_Discard,
    Osc,
    Osc_Escape,
    Osc_Discard,
    Osc_Discard_Escape,
    Apc,
    Apc_Escape,
    Apc_Discard,
    Apc_Discard_Escape,
    Dcs,
    Dcs_Data,
    Dcs_Escape,
    Dcs_Query_Data,
    Dcs_Query_Escape,
    Dcs_Discard,
    Dcs_Discard_Escape,
    Iterm2,
    Iterm2_Escape,
    Iterm2_Discard,
    Iterm2_Discard_Escape,
}

// Maximum semantic replies retained until owner-matched input delivery.
TERMINAL_RESPONSE_CAPACITY :: 16

// Maximum saved Kitty keyboard flag values retained independently per screen.
KITTY_KEYBOARD_STACK_CAPACITY :: 16

// Kitty keyboard enhancement bits 1, 2, 4, 8, and 16.
KITTY_KEYBOARD_SUPPORTED_FLAGS :: u8(31)

// Screen-local Kitty keyboard flags and bounded push/pop history.
Kitty_Keyboard_State :: struct {
    flags: u8,
    stack: [KITTY_KEYBOARD_STACK_CAPACITY]u8,
    stack_count: int,
}

// Display-owned synchronized-output transaction bound to one interpreter.
Synchronized_Output_State :: struct {
    // Independently owned presentation snapshot and borrowed capture sources.
    checkpoint: termgrid.Display_Checkpoint,
    scrollback: ^termgrid.Scrollback,
    output_started: ^bool,
    attachments: ^termattachment.Store,

    // Producer identity, captured presentation metadata, and deadline state.
    producer: termmodel.Terminal_Producer,
    captured_output_started: bool,
    captured_alternate_screen_active: bool,
    captured_cursor_visible: bool,
    active: bool,
    deadline_armed: bool,
    deadline: f64,

    // Lifetime transaction outcomes retained for terminal diagnostics.
    begin_count: u64,
    publish_count: u64,
    forced_publish_count: u64,
    capture_failure_count: u64,
}

// Private parameter prefix retained for one CSI transaction.
Csi_Private_Marker :: enum u8 {
    None,
    Less_Than,
    Equal,
    Greater_Than,
    Question,
}

// Separator preceding one committed CSI parameter token.
Csi_Parameter_Separator :: enum u8 {
    None,
    Semicolon,
    Colon,
}

// Fixed title, producer, and semantic-response storage borrowed by one interpreter.
Terminal_Title_State :: struct {
    // Display-owned color palette retained beside other terminal-lifetime services.
    palette: termpalette.Terminal_Palette_State,

    // Last validated OSC 0/2 title exposed to presentation code.
    title: [TERMINAL_TITLE_BYTE_CAPACITY]u8,
    title_byte_count: int,

    // Transactional OSC title candidate retained until validation and commit.
    candidate: [TERMINAL_TITLE_BYTE_CAPACITY]u8,
    candidate_byte_count: int,

    // Transactional DCS query candidate retained until validation and reply admission.
    query_candidate: [TERMINAL_QUERY_BYTE_CAPACITY]u8,
    query_candidate_byte_count: int,
    query_candidate_invalid: bool,

    // Content-free lifetime query outcomes.
    query_acceptance_count: u64,
    query_rejection_count: u64,

    // Producer-correlated semantic replies awaiting owner-matched delivery.
    responses: [TERMINAL_RESPONSE_CAPACITY]termmodel.Terminal_Response,
    response_start: int,
    response_count: int,

    // Count-only response pressure and stale-owner diagnostics.
    response_rejection_count: u64,
    response_stale_discard_count: u64,

    // Last committed display geometry used only for semantic query snapshots.
    query_geometry: termmodel.Terminal_Query_Geometry,

    // Terminal-global ordinary-key negotiation reset at the stream boundary.
    modify_other_keys_level: u8,

    // Independent Kitty negotiation state for primary and alternate screens.
    primary_kitty: Kitty_Keyboard_State,
    alternate_kitty: Kitty_Keyboard_State,

    // Current write identity and the identity captured when a sequence begins.
    sequence_producer: termmodel.Terminal_Producer,
    write_producer: termmodel.Terminal_Producer,

    // Retained graphics framing state owned beside this title service.
    graphics: ^gfxprotocol.Graphics_Parser_State,
}

// Allocation-free terminal-control interpreter over one active fixed grid.
//
// The interpreter borrows both grids for its lifetime. Parsing and screen swaps
// mutate those grids synchronously; neither grid may move or be destroyed first.
Interpreter :: struct {
    // Active viewport and optional same-sized alternate viewport. Entering DEC
    // mode 1049 swaps grid values so `grid` always points at the rendered screen.
    grid: ^termgrid.Grid,
    alternate_grid: ^termgrid.Grid,
    title_state: ^Terminal_Title_State,
    synchronized_output: ^Synchronized_Output_State,
    hyperlink_registry: ^termhyperlink.Hyperlink_Registry,
    clipboard_actions: ^termclipboard.Clipboard_Action_Queue,
    shell_integration: ^termshellintegration.Shell_Integration_State,
    active_hyperlink: termmodel.Hyperlink_Handle,
    alternate_screen_active: bool,

    // Input compatibility policy applied before ordinary grid line-feed handling.
    line_feed_resets_column: bool,

    // Input encoding modes controlled by DEC private and keypad escape sequences.
    input_mode: termmodel.Terminal_Input_Mode,

    // Incremental control-sequence state. Parameters use -1 for omitted values;
    // the current numeric token remains separate until a separator/final arrives.
    state: Interpreter_State,
    parameters: [CSI_PARAMETER_CAPACITY]int,
    parameter_count: int,
    parameter_value: int,
    parameter_present: bool,
    parameter_separator_is_colon: bool,
    csi_private_marker: Csi_Private_Marker,
    csi_intermediate: u8,
    dcs_query_prefix: u8,
    unsupported_parameter_bytes: bool,
    sequence_bytes: int,

    // Transactional OSC title parsing and the last validated retained title.
    osc_command: int,
    osc_command_present: bool,
    osc_payload_started: bool,
    osc_command_invalid: bool,
    title_candidate_invalid: bool,
    hyperlink_candidate_invalid: bool,

    // Terminal presentation state associated with the currently active viewport.
    cursor_visible: bool,
    saved_cursor: termgrid.Cursor,
    has_saved_cursor: bool,

    // Exact primary presentation state retained while the alternate screen is
    // active and restored when mode 1049 is disabled or recovery forces exit.
    primary_cursor: termgrid.Cursor,
    primary_cursor_visible: bool,
    primary_saved_cursor: termgrid.Cursor,
    primary_has_saved_cursor: bool,

    // Lifetime diagnostics distinguish malformed syntax, valid-but-unsupported
    // commands, and sequences rejected for bounded-storage pressure.
    malformed_sequence_count: u64,
    unsupported_sequence_count: u64,
    cancelled_sequence_count: u64,
    overflow_sequence_count: u64,
    title_acceptance_count: u64,
    title_rejection_count: u64,
    hyperlink_acceptance_count: u64,
    hyperlink_rejection_count: u64,
}

// Optional alternate viewport and retained terminal services borrowed by an interpreter.
Interpreter_Init_Options :: struct {
    alternate_grid: ^termgrid.Grid,
    title_state: ^Terminal_Title_State,
    synchronized_output: ^Synchronized_Output_State,
    hyperlink_registry: ^termhyperlink.Hyperlink_Registry,
    clipboard_actions: ^termclipboard.Clipboard_Action_Queue,
    shell_integration: ^termshellintegration.Shell_Integration_State,
}

//   Initialize an allocation-free interpreter over one or two fixed grids.
//
// Parameters:
//   - interpreter: Zero-valued destination state.
//   - grid: Initialized primary grid borrowed for the interpreter lifetime.
//   - options: Optional alternate grid and retained terminal services.
//
// Returns:
//   - True after initialization; false for invalid primary or alternate storage.
//
// Side effects:
//   - Resets interpreter state and applies the default foreground to the primary grid.
interpreter_init :: proc(
    interpreter: ^Interpreter, grid: ^termgrid.Grid,
    options := Interpreter_Init_Options{}) -> bool {
    if interpreter == nil || grid == nil || len(grid.cells) == 0 {
        return false
    }
    if options.alternate_grid != nil &&
        (len(options.alternate_grid.cells) == 0 ||
         options.alternate_grid.columns != grid.columns ||
         options.alternate_grid.row_count != grid.row_count) {
        return false
    }
    interpreter^ = {
        grid = grid,
        alternate_grid = options.alternate_grid,
        title_state = options.title_state,
        synchronized_output = options.synchronized_output,
        hyperlink_registry = options.hyperlink_registry,
        clipboard_actions = options.clipboard_actions,
        shell_integration = options.shell_integration,
        cursor_visible = true,
    }
    termgrid.grid_set_style(grid, {})
    return true
}

//   Reconcile interpreter-owned cursors after both borrowed grids resize.
//
// Parameters:
//   - interpreter: The parser whose retained cursor state must be adjusted; nil is
//     a no-op.
//   - old_columns, old_rows: Dimensions of the grids before replacement.
//   - new_columns, new_rows: Dimensions of the replacement grids.
//
// Side effects:
//   - Clamps the active saved cursor and retained primary cursors to positions valid
//     under the new dimensions, preserving bottom anchoring on row shrink.
interpreter_resize_state :: proc(
    interpreter: ^Interpreter,
    old_columns, old_rows, new_columns, new_rows: int) {
    if interpreter == nil {
        return
    }
    interpreter.saved_cursor = termgrid.grid_resize_cursor(
        interpreter.saved_cursor,
        old_columns, old_rows, new_columns, new_rows)
    interpreter.primary_cursor = termgrid.grid_resize_cursor(
        interpreter.primary_cursor,
        old_columns, old_rows, new_columns, new_rows)
    interpreter.primary_saved_cursor = termgrid.grid_resize_cursor(
        interpreter.primary_saved_cursor,
        old_columns, old_rows, new_columns, new_rows)
}

//   Ingest arbitrarily chunked terminal bytes without allocating parser storage.
//
// Parameters:
//   - interpreter: The initialized parser and active viewport.
//   - input: Bytes to consume; caller storage is not retained.
//
// Returns:
//   - False only for nil/uninitialized interpreter state; otherwise true.
//
// Side effects:
//   - Advances parser state, mutates the active grid, and updates diagnostics.
interpreter_write :: proc(
    interpreter: ^Interpreter, input: string,
    producer: termmodel.Terminal_Producer = {}) -> bool {
    if interpreter == nil || interpreter.grid == nil {
        return false
    }
    synchronized := interpreter.synchronized_output
    if synchronized != nil && synchronized.active &&
        synchronized.producer != producer {
        interpreter_publish_synchronized_output(interpreter, true)
    }
    retained := interpreter.title_state
    if retained != nil {
        gfxsemantics.graphics_semantics_producer_boundary(retained.graphics, producer)
    }
    if retained != nil && interpreter.state != .Ground &&
        retained.sequence_producer != producer {
        interpreter.malformed_sequence_count += 1
        interpreter_reset_sequence(interpreter)
    }
    if retained != nil {
        retained.write_producer = producer
    }
    for byte in transmute([]u8)input {
        interpreter_ingest_byte(interpreter, byte)
    }
    return true
}

//   Finalize incomplete UTF-8 or terminal-control input at a stream boundary.
//
// Parameters:
//   - interpreter: The initialized parser to finish; nil/uninitialized is a no-op.
//
// Side effects:
//   - Counts an incomplete control sequence as malformed, resets to ground, and
//     resolves pending UTF-8 through the active grid's replacement policy.
interpreter_finish_input :: proc(interpreter: ^Interpreter) {
    if interpreter == nil || interpreter.grid == nil {
        return
    }
    interpreter_publish_synchronized_output(interpreter, true)
    if interpreter.title_state != nil {
        gfxsemantics.graphics_semantics_abort_assemblies(interpreter.title_state.graphics)
    }
    if interpreter.state != .Ground {
        interpreter.malformed_sequence_count += 1
        interpreter_reset_sequence(interpreter)
    }
    termgrid.grid_finish_input(interpreter.grid)
    interpreter.active_hyperlink = 0
    interpreter.grid.hyperlink = 0
    interpreter_reset_input_mode(interpreter)
    if interpreter.title_state != nil {
        graphics := interpreter.title_state.graphics
        palette := interpreter.title_state.palette
        interpreter.title_state^ = {}
        interpreter.title_state.graphics = graphics
        interpreter.title_state.palette = palette
    }
}

// Return the current terminal input-mode value without exposing parser ownership.
//
// Parameters:
//   - interpreter: The initialized parser; nil is accepted.
//
// Returns:
//   - A value snapshot of all negotiated input modes, or zero defaults for nil.
interpreter_input_mode :: proc(
    interpreter: ^Interpreter) -> termmodel.Terminal_Input_Mode {
    if interpreter == nil {
        return {}
    }
    return interpreter.input_mode
}

// Return the terminal-global xterm modifyOtherKeys negotiation level.
interpreter_modify_other_keys_level :: proc(interpreter: ^Interpreter) -> u8 {
    if interpreter == nil || interpreter.title_state == nil {
        return 0
    }
    return interpreter.title_state.modify_other_keys_level
}

// Borrow the Kitty keyboard state associated with the active screen.
//
// Returns:
//   - Active screen state, or nil when retained interpreter storage is unavailable.
interpreter_active_kitty_state :: proc(
    interpreter: ^Interpreter) -> ^Kitty_Keyboard_State {
    if interpreter == nil || interpreter.title_state == nil {
        return nil
    }
    if interpreter.alternate_screen_active {
        return &interpreter.title_state.alternate_kitty
    }
    return &interpreter.title_state.primary_kitty
}

// Return the accepted Kitty keyboard flags for the active screen.
interpreter_kitty_keyboard_flags :: proc(interpreter: ^Interpreter) -> u8 {
    state := interpreter_active_kitty_state(interpreter)
    return state.flags if state != nil else 0
}

// Borrow the last validated OSC 0/2 title until the next commit or finalization.
//
// Parameters:
//   - interpreter: The parser with optional retained title state; nil is accepted.
//
// Returns:
//   - A borrowed string over the retained title bytes, or empty when unavailable.
//
// Notes:
//   - The returned string remains valid until another title commits or the title
//     state is finalized or destroyed.
interpreter_title :: proc(interpreter: ^Interpreter) -> string {
    if interpreter == nil {
        return ""
    }
    if interpreter.title_state == nil {
        return ""
    }
    state := interpreter.title_state
    return string(state.title[:state.title_byte_count])
}

// Restore default keyboard modes at an evaluation or process boundary.
//
// Parameters:
//   - interpreter: The parser whose negotiated input state is ending; nil is a no-op.
//
// Side effects:
//   - Clears cursor-key, keypad, paste, focus, mouse-tracking, and mouse-encoding
//     modes together.
interpreter_reset_input_mode :: proc(interpreter: ^Interpreter) {
    if interpreter != nil {
        interpreter.input_mode = {}
    }
}

// Clear retained command candidates owned outside the interpreter value.
interpreter_reset_retained_candidates :: proc(interpreter: ^Interpreter) {
    if interpreter.title_state != nil {
        interpreter.title_state.sequence_producer = {}
        interpreter.title_state.candidate = {}
        interpreter.title_state.candidate_byte_count = 0
        interpreter.title_state.query_candidate = {}
        interpreter.title_state.query_candidate_byte_count = 0
        interpreter.title_state.query_candidate_invalid = false
        interpreter.title_state.palette.candidate = {}
        interpreter.title_state.palette.candidate_byte_count = 0
        interpreter.title_state.palette.candidate_invalid = false
        gfxprotocol.graphics_parser_abort(interpreter.title_state.graphics)
    }
    if interpreter.hyperlink_registry != nil {
        interpreter.hyperlink_registry.candidate = {}
        interpreter.hyperlink_registry.candidate_byte_count = 0
    }
    if interpreter.clipboard_actions != nil {
        interpreter.clipboard_actions.candidate = {}
        interpreter.clipboard_actions.candidate_byte_count = 0
    }
    if interpreter.shell_integration != nil {
        interpreter.shell_integration.candidate = {}
        interpreter.shell_integration.candidate_byte_count = 0
        interpreter.shell_integration.candidate_invalid = false
    }
}

//   Reset bounded sequence storage and return the parser to ground.
//
// Parameters:
//   - interpreter: The parser whose current sequence is complete or abandoned.
//
// Side effects:
//   - Clears CSI parameters, private marker, byte count, and parser state.
interpreter_reset_sequence :: proc(interpreter: ^Interpreter) {
    interpreter.state = .Ground
    interpreter.parameters = {}
    interpreter.parameter_count = 0
    interpreter.parameter_value = 0
    interpreter.parameter_present = false
    interpreter.parameter_separator_is_colon = false
    interpreter.csi_private_marker = .None
    interpreter.csi_intermediate = 0
    interpreter.dcs_query_prefix = 0
    interpreter.unsupported_parameter_bytes = false
    interpreter.sequence_bytes = 0
    interpreter_reset_retained_candidates(interpreter)
    interpreter.osc_command = 0
    interpreter.osc_command_present = false
    interpreter.osc_payload_started = false
    interpreter.osc_command_invalid = false
    interpreter.title_candidate_invalid = false
    interpreter.hyperlink_candidate_invalid = false
}

//   Consume one byte while the parser is in ground state.
//
// Parameters:
//   - interpreter: The initialized parser and active grid.
//   - byte: The next terminal-stream byte.
//
// Side effects:
//   - Enters escape parsing for ESC, otherwise forwards the byte to the grid and may
//     synthesize carriage return before line feed under compatibility policy.
interpreter_ingest_ground_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if byte == '\e' {
        if interpreter.grid.pending_utf8_len > 0 {
            termgrid.grid_finish_input(interpreter.grid)
        }
        interpreter.state = .Escape
        if interpreter.title_state != nil {
            interpreter.title_state.sequence_producer =
                interpreter.title_state.write_producer
        }
        return
    }
    if byte == '\n' && interpreter.line_feed_resets_column {
        termgrid.grid_ingest_byte(interpreter.grid, '\r')
    }
    termgrid.grid_ingest_byte(interpreter.grid, byte)
}

// Apply one complete supported ESC final-byte command.
interpreter_apply_escape_final :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    switch byte {
    case 'D': interpreter_index_forward(interpreter, false)
    case 'E': interpreter_index_forward(interpreter, true)
    case 'H':
        termgrid.grid_set_tab_stop(
            interpreter.grid, interpreter.grid.cursor.column, true)
    case 'M': interpreter_index_reverse(interpreter)
    case '7': interpreter_save_dec_state(interpreter)
    case '8': interpreter_restore_dec_state(interpreter)
    case: return false
    }
    return true
}

// Consume one ESC-state control or DEL byte when applicable.
interpreter_apply_escape_control :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    if byte < 0x20 {
        termgrid.grid_write_control(interpreter.grid, byte)
        return true
    }
    return byte == 0x7f
}

// Enter the terminal sequence family introduced by one ESC follower.
interpreter_enter_escape_family :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    switch byte {
    case '[': interpreter.state = .Csi
    case ']': interpreter.state = .Osc
    case '_': interpreter.state = .Apc
    case 'P': interpreter.state = .Dcs
    case: return false
    }
    interpreter.sequence_bytes = 2
    return true
}

//   Select the sequence family introduced by one byte after escape.
//
// Parameters:
//   - interpreter: The parser currently in the escape state.
//   - byte: The byte following ESC.
//
// Side effects:
//   - Routes to intermediate, CSI, or OSC parsing; applies keypad mode escapes;
//     handles embedded controls; or records unsupported or malformed input.
interpreter_ingest_escape_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if interpreter_apply_escape_control(interpreter, byte) { return }
    if byte >= 0x20 && byte <= 0x2f {
        interpreter.state = .Escape_Intermediate
        interpreter.sequence_bytes += 1
        return
    }
    if interpreter_enter_escape_family(interpreter, byte) { return }
    if byte == '=' || byte == '>' {
        interpreter.input_mode.keypad_application = byte == '='
        interpreter_reset_sequence(interpreter)
        return
    }
    if interpreter_apply_escape_final(interpreter, byte) {
        interpreter_reset_sequence(interpreter)
        return
    }
    if byte >= 0x30 && byte <= 0x7e {
        interpreter.unsupported_sequence_count += 1
    } else {
        interpreter.malformed_sequence_count += 1
    }
    interpreter_reset_sequence(interpreter)
}

//   Consume an ESC intermediate sequence through its final byte.
//
// Parameters:
//   - interpreter: The parser currently in the escape-intermediate state.
//   - byte: The next control, intermediate, final, or malformed byte.
//
// Side effects:
//   - Handles embedded controls, counts bounded intermediate bytes, enters discard
//     on overflow, or records and resets a completed unsupported sequence.
interpreter_ingest_escape_intermediate_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if byte < 0x20 {
        termgrid.grid_write_control(interpreter.grid, byte)
        return
    }
    if byte == 0x7f {
        return
    }
    if byte >= 0x20 && byte <= 0x2f {
        interpreter.sequence_bytes += 1
        if interpreter.sequence_bytes > CSI_SEQUENCE_BYTE_CAPACITY {
            interpreter.overflow_sequence_count += 1
            interpreter.state = .Csi_Discard
        }
        return
    }
    if byte >= 0x30 && byte <= 0x7e {
        interpreter.unsupported_sequence_count += 1
        interpreter_reset_sequence(interpreter)
        return
    }
    interpreter.malformed_sequence_count += 1
    interpreter_reset_sequence(interpreter)
}

//   Consume one byte while recovering from a rejected CSI sequence.
//
// Parameters:
//   - interpreter: The parser currently discarding a CSI sequence.
//   - byte: The next terminal-stream byte.
//
// Side effects:
//   - Restarts escape parsing on ESC or returns to ground after a CSI final byte.
interpreter_ingest_csi_discard_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if byte == '\e' {
        interpreter_reset_sequence(interpreter)
        interpreter.state = .Escape
        return
    }
    if byte >= 0x40 && byte <= 0x7e {
        interpreter_reset_sequence(interpreter)
    }
}

// Cancel the active sequence when one cancellation control is received.
interpreter_cancel_sequence :: proc(interpreter: ^Interpreter, byte: u8) -> bool {
    if interpreter.state == .Ground || (byte != 0x18 && byte != 0x1a) {
        return false
    }
    interpreter.cancelled_sequence_count += 1
    if interpreter.title_state != nil {
        gfxsemantics.graphics_semantics_abort_assemblies(interpreter.title_state.graphics)
    }
    interpreter_reset_sequence(interpreter)
    return true
}

// Restart an escape-family sequence when another ESC arrives.
interpreter_restart_escape_sequence :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    if byte != '\e' || !(interpreter.state == .Escape ||
        interpreter.state == .Escape_Intermediate || interpreter.state == .Csi ||
        interpreter.state == .Csi_Intermediate || interpreter.state == .Csi_Discard) {
        return false
    }
    interpreter_reset_sequence(interpreter)
    interpreter.state = .Escape
    if interpreter.title_state != nil {
        interpreter.title_state.sequence_producer =
            interpreter.title_state.write_producer
    }
    return true
}

// Route one byte through ground, escape, or CSI parser states.
interpreter_ingest_control_sequence_byte :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    #partial switch interpreter.state {
    case .Ground: interpreter_ingest_ground_byte(interpreter, byte)
    case .Escape: interpreter_ingest_escape_byte(interpreter, byte)
    case .Escape_Intermediate:
        interpreter_ingest_escape_intermediate_byte(interpreter, byte)
    case .Csi, .Csi_Intermediate: interpreter_ingest_csi_byte(interpreter, byte)
    case .Csi_Discard: interpreter_ingest_csi_discard_byte(interpreter, byte)
    case: return false
    }
    return true
}

// Route one byte through OSC, APC, DCS, or iTerm2 string parser states.
interpreter_ingest_string_sequence_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    #partial switch interpreter.state {
    case .Osc, .Osc_Escape, .Osc_Discard, .Osc_Discard_Escape:
        interpreter_ingest_osc_state_byte(interpreter, byte)
    case .Apc, .Apc_Escape, .Apc_Discard, .Apc_Discard_Escape:
        interpreter_ingest_apc_state_byte(interpreter, byte)
    case .Dcs, .Dcs_Data, .Dcs_Escape, .Dcs_Query_Data, .Dcs_Query_Escape,
         .Dcs_Discard, .Dcs_Discard_Escape:
        interpreter_ingest_dcs_state_byte(interpreter, byte)
    case .Iterm2, .Iterm2_Escape, .Iterm2_Discard, .Iterm2_Discard_Escape:
        interpreter_ingest_iterm2_state_byte(interpreter, byte)
    }
}

//   Route one byte through the current terminal parser state.
//
// Notes:
//   - Escape starts finalize pending grid UTF-8 before control parsing begins.
//   - Discard states suppress rejected bytes until a final byte or new escape.
//
// Parameters:
//   - interpreter: The initialized parser and active grid.
//   - byte: The next byte from the terminal stream.
//
// Side effects:
//   - Advances parser/grid state and may increment malformed/unsupported counters.
interpreter_ingest_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if interpreter_cancel_sequence(interpreter, byte) ||
        interpreter_restart_escape_sequence(interpreter, byte) { return }
    if !interpreter_ingest_control_sequence_byte(interpreter, byte) {
        interpreter_ingest_string_sequence_byte(interpreter, byte)
    }
}

// Retain one OSC hyperlink payload byte.
interpreter_ingest_osc_hyperlink_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    registry := interpreter.hyperlink_registry
    if registry == nil || registry.candidate_byte_count >= len(registry.candidate) {
        interpreter.hyperlink_candidate_invalid = true
        return
    }
    registry.candidate[registry.candidate_byte_count] = byte
    registry.candidate_byte_count += 1
}

// Retain one OSC shell-integration payload byte.
interpreter_ingest_osc_shell_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    state := interpreter.shell_integration
    if state == nil || state.candidate_byte_count >= len(state.candidate) {
        if state != nil { state.candidate_invalid = true }
        return
    }
    state.candidate[state.candidate_byte_count] = byte
    state.candidate_byte_count += 1
}

// Consume one byte in an active Kitty APC candidate.
interpreter_ingest_apc_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if byte == '\e' {
        interpreter.state = .Apc_Escape
    } else if interpreter.sequence_bytes == 2 {
        interpreter.sequence_bytes += 1
        if byte != 'G' || graphics == nil {
            interpreter.state = .Apc_Discard
        }
    } else if !interpreter.osc_payload_started {
        if byte == ';' {
            interpreter.osc_payload_started = true
            if !gfxprotocol.graphics_parser_begin_transfer(graphics, .Kitty) {
                interpreter.state = .Apc_Discard
            }
        } else if !gfxprotocol.graphics_parser_append_header(graphics, byte) {
            interpreter.overflow_sequence_count += 1
            interpreter.state = .Apc_Discard
        }
    } else if !gfxprotocol.graphics_parser_ingest_base64(graphics, byte) {
        interpreter.malformed_sequence_count += 1
        interpreter.state = .Apc_Discard
    }
}

// Finish a Kitty APC candidate or enter discard recovery for malformed ST.
interpreter_ingest_apc_escape_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if byte == '\\' {
        if graphics != nil {
            incomplete_base64 := graphics.base64_quantum_count != 0
            if !gfxprotocol.graphics_parser_finish_frame(
                graphics, .Kitty,
            interpreter_sequence_producer(interpreter),
            interpreter.osc_payload_started) &&
                incomplete_base64 {
                interpreter.malformed_sequence_count += 1
            }
            interpreter_consume_graphics_frames(interpreter)
        } else {
            interpreter.unsupported_sequence_count += 1
        }
        interpreter_reset_sequence(interpreter)
    } else {
        interpreter.malformed_sequence_count += 1
        gfxprotocol.graphics_parser_abort(graphics)
        interpreter.state = .Apc_Discard
    }
}

// Consume one byte in a Kitty APC candidate or terminator-aware discard state.
interpreter_ingest_apc_state_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    graphics := interpreter.title_state.graphics if
        interpreter.title_state != nil else nil
    #partial switch interpreter.state {
    case .Apc:
        interpreter_ingest_apc_byte(interpreter, graphics, byte)
    case .Apc_Escape:
        interpreter_ingest_apc_escape_byte(interpreter, graphics, byte)
    case .Apc_Discard:
        if byte == '\e' {
            interpreter.state = .Apc_Discard_Escape
        }
    case .Apc_Discard_Escape:
        if byte == '\\' {
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter.state = .Apc_Discard
        }
    }
}

// Consume one DCS introducer or Sixel parameter byte.
interpreter_ingest_dcs_control_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if byte == 'q' {
        if interpreter.dcs_query_prefix != 0 && interpreter.title_state != nil {
            interpreter.state = .Dcs_Query_Data
        } else if interpreter.dcs_query_prefix == 0 && graphics != nil &&
            gfxprotocol.graphics_parser_begin_transfer(graphics, .Sixel) {
            interpreter.state = .Dcs_Data
        } else {
            interpreter.state = .Dcs_Discard
        }
    } else if (byte == '$' || byte == '+') &&
        interpreter.dcs_query_prefix == 0 {
        interpreter.dcs_query_prefix = byte
    } else if byte == '\e' {
        interpreter.malformed_sequence_count += 1
        interpreter.state = .Dcs_Discard_Escape
    } else if (byte >= 0x20 && byte <= 0x2f) ||
        (byte >= 0x30 && byte <= 0x3f) {
        if graphics == nil || !gfxprotocol.graphics_parser_append_header(graphics, byte) {
            interpreter.overflow_sequence_count += 1
            interpreter.state = .Dcs_Discard
        }
    } else {
        interpreter.unsupported_sequence_count += 1
        interpreter.state = .Dcs_Discard
    }
}

// Retain one bounded DECRQSS or XTGETTCAP selector byte.
interpreter_ingest_dcs_query_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if byte == '\e' {
        interpreter.state = .Dcs_Query_Escape
        return
    }
    state := interpreter.title_state
    if state == nil || state.query_candidate_byte_count >=
        len(state.query_candidate) {
        if state != nil {
            state.query_candidate_invalid = true
            state.query_rejection_count += 1
        }
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Dcs_Discard
        return
    }
    state.query_candidate[state.query_candidate_byte_count] = byte
    state.query_candidate_byte_count += 1
}

// Consume one raw Sixel payload byte or begin its string terminator.
interpreter_ingest_dcs_data_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if byte == '\e' {
        interpreter.state = .Dcs_Escape
    } else if !gfxprotocol.graphics_parser_ingest_raw(graphics, byte) {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Dcs_Discard
    }
}

// Consume one byte in a Sixel DCS candidate or terminator-aware discard state.
interpreter_ingest_dcs_query_state_byte :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    if interpreter.state == .Dcs_Query_Data {
        interpreter_ingest_dcs_query_byte(interpreter, byte)
        return true
    }
    if interpreter.state != .Dcs_Query_Escape { return false }
    if byte == '\\' {
        interpreter_finish_dcs_query(interpreter)
        interpreter_reset_sequence(interpreter)
    } else {
        interpreter.malformed_sequence_count += 1
        interpreter.state = .Dcs_Discard
    }
    return true
}

// Consume one byte in a Sixel DCS candidate or terminator-aware discard state.
interpreter_ingest_dcs_state_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if interpreter_ingest_dcs_query_state_byte(interpreter, byte) { return }
    graphics := interpreter.title_state.graphics if
        interpreter.title_state != nil else nil
    #partial switch interpreter.state {
    case .Dcs:
        interpreter_ingest_dcs_control_byte(interpreter, graphics, byte)
    case .Dcs_Data:
        interpreter_ingest_dcs_data_byte(interpreter, graphics, byte)
    case .Dcs_Escape:
        if byte == '\\' {
            gfxprotocol.graphics_parser_finish_frame(
                graphics, .Sixel, interpreter_sequence_producer(interpreter), false)
            interpreter_consume_graphics_frames(interpreter)
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter.malformed_sequence_count += 1
            gfxprotocol.graphics_parser_abort(graphics)
            interpreter.state = .Dcs_Discard
        }
    case .Dcs_Discard:
        if byte == '\e' {
            interpreter.state = .Dcs_Discard_Escape
        }
    case .Dcs_Discard_Escape:
        if byte == '\\' {
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter.state = .Dcs_Discard
        }
    }
}

// Complete one specialized OSC 1337 command after BEL or ST.
interpreter_finish_iterm2 :: proc(interpreter: ^Interpreter) {
    graphics := interpreter.title_state.graphics if
        interpreter.title_state != nil else nil
    kind: gfxprotocol.Graphics_Frame_Kind
    base64_payload := false
    valid := graphics != nil
    if valid && gfxprotocol.graphics_parser_header_has_prefix(graphics, "File=") {
        kind = .Iterm2_File
        base64_payload = true
        valid = graphics.transfer_id.generation != 0
    } else if valid && gfxprotocol.graphics_parser_header_equals(graphics, "FilePart=") {
        kind = .Iterm2_File_Part
        base64_payload = true
        valid = graphics.transfer_id.generation != 0
    } else if valid &&
        gfxprotocol.graphics_parser_header_has_prefix(graphics, "MultipartFile=") {
        kind = .Iterm2_Multipart_File
    } else if valid && gfxprotocol.graphics_parser_header_equals(graphics, "FileEnd") {
        kind = .Iterm2_File_End
    } else {
        valid = false
    }
    if valid {
        incomplete_base64 := base64_payload &&
            graphics.base64_quantum_count != 0
        if !gfxprotocol.graphics_parser_finish_frame(
            graphics, kind, interpreter_sequence_producer(interpreter),
            base64_payload) && incomplete_base64 {
            interpreter.malformed_sequence_count += 1
        }
        interpreter_consume_graphics_frames(interpreter)
    } else {
        interpreter.unsupported_sequence_count += 1
    }
    interpreter_reset_sequence(interpreter)
}

// Consume one OSC 1337 header or Base64 payload byte.
interpreter_ingest_iterm2_content_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if interpreter.osc_payload_started {
        if !gfxprotocol.graphics_parser_ingest_base64(graphics, byte) {
            interpreter.malformed_sequence_count += 1
            interpreter.state = .Iterm2_Discard
        }
    } else if gfxprotocol.graphics_parser_header_equals(graphics, "FilePart=") {
        interpreter.osc_payload_started = true
        if !gfxprotocol.graphics_parser_begin_transfer(graphics, .Iterm2) ||
            !gfxprotocol.graphics_parser_ingest_base64(graphics, byte) {
            interpreter.state = .Iterm2_Discard
        }
    } else if byte == ':' &&
        gfxprotocol.graphics_parser_header_has_prefix(graphics, "File=") {
        interpreter.osc_payload_started = true
        if !gfxprotocol.graphics_parser_begin_transfer(graphics, .Iterm2) {
            interpreter.state = .Iterm2_Discard
        }
    } else if !gfxprotocol.graphics_parser_append_header(graphics, byte) {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Iterm2_Discard
    }
}

// Consume one byte in an active OSC 1337 image command.
interpreter_ingest_iterm2_byte :: proc(
    interpreter: ^Interpreter, graphics: ^gfxprotocol.Graphics_Parser_State, byte: u8) {
    if byte == '\a' {
        interpreter_finish_iterm2(interpreter)
    } else if byte == '\e' {
        interpreter.state = .Iterm2_Escape
    } else if graphics == nil {
        interpreter.state = .Iterm2_Discard
    } else {
        interpreter_ingest_iterm2_content_byte(interpreter, graphics, byte)
    }
}

// Consume one byte in an OSC 1337 image command or its discard recovery state.
interpreter_ingest_iterm2_state_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    graphics := interpreter.title_state.graphics if
        interpreter.title_state != nil else nil
    #partial switch interpreter.state {
    case .Iterm2:
        interpreter_ingest_iterm2_byte(interpreter, graphics, byte)
    case .Iterm2_Escape:
        if byte == '\\' {
            interpreter_finish_iterm2(interpreter)
        } else {
            interpreter.malformed_sequence_count += 1
            gfxprotocol.graphics_parser_abort(graphics)
            interpreter.state = .Iterm2_Discard
        }
    case .Iterm2_Discard:
        if byte == '\a' {
            interpreter_reset_sequence(interpreter)
        } else if byte == '\e' {
            interpreter.state = .Iterm2_Discard_Escape
        }
    case .Iterm2_Discard_Escape:
        if byte == '\\' || byte == '\a' {
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter.state = .Iterm2_Discard
        }
    }
}

//   Consume one byte in an active or overflow-discard OSC state.
//
// Notes:
//   - OSC terminates with BEL or the two-byte ST sequence `ESC \\`.
//   - Discard mode recognizes terminators but never exposes payload as grid text.
//
// Parameters:
//   - interpreter: The parser currently in an OSC-family state.
//   - byte: The next terminal-stream byte.
//
// Side effects:
//   - Advances OSC state or resets the complete sequence to ground.
interpreter_ingest_osc_state_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    #partial switch interpreter.state {
    case .Osc:
        interpreter_ingest_osc_byte(interpreter, byte)
    case .Osc_Escape:
        if byte == '\\' {
            interpreter_finish_osc(interpreter)
        } else {
            interpreter.state = .Osc
            interpreter_ingest_osc_byte(interpreter, byte)
        }
    case .Osc_Discard:
        if byte == '\a' {
            interpreter_reset_sequence(interpreter)
        } else if byte == '\e' {
            interpreter.state = .Osc_Discard_Escape
        }
    case .Osc_Discard_Escape:
        if byte == '\\' || byte == '\a' {
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter.state = .Osc_Discard
        }
    }
}

// Record command-specific rejection telemetry for an oversized OSC sequence.
interpreter_reject_osc_overflow :: proc(interpreter: ^Interpreter) {
    if interpreter.osc_command == 0 || interpreter.osc_command == 2 {
        interpreter.title_rejection_count += 1
    } else if interpreter.osc_command == 8 {
        interpreter.hyperlink_rejection_count += 1
    } else if interpreter.title_state != nil &&
        (interpreter.osc_command == 4 ||
         (interpreter.osc_command >= 10 && interpreter.osc_command <= 12) ||
         interpreter.osc_command == 104 ||
         (interpreter.osc_command >= 110 && interpreter.osc_command <= 112)) {
        interpreter.title_state.palette.color_rejection_count += 1
    } else if (interpreter.osc_command == 7 ||
        interpreter.osc_command == 133) && interpreter.shell_integration != nil {
        if interpreter.osc_command == 7 {
            interpreter.shell_integration.cwd_rejection_count += 1
        } else {
            interpreter.shell_integration.marker_rejection_count += 1
        }
    }
}

//   Consume one active OSC payload byte without rendering terminal metadata.
//
// Parameters:
//   - interpreter: The parser currently in `Osc`.
//   - byte: The next payload byte or terminator prefix.
//
// Side effects:
//   - Tracks sequence length, enters ST handling, resets on BEL, or begins discard.
interpreter_ingest_osc_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if byte == '\a' {
        interpreter_finish_osc(interpreter)
        return
    }
    if byte == '\e' {
        interpreter.state = .Osc_Escape
        return
    }
    interpreter.sequence_bytes += 1
    if interpreter.sequence_bytes > OSC_SEQUENCE_BYTE_CAPACITY {
        if interpreter.osc_payload_started {
            interpreter_reject_osc_overflow(interpreter)
        }
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Osc_Discard
        return
    }
    if !interpreter.osc_payload_started {
        interpreter_ingest_osc_command_byte(interpreter, byte)
        return
    }
    interpreter_ingest_osc_payload_byte(interpreter, byte)
}

// Retain one supported OSC payload byte in its command-specific candidate storage.
interpreter_ingest_osc_payload_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if interpreter.osc_command == 8 {
        interpreter_ingest_osc_hyperlink_byte(interpreter, byte)
        return
    }
    if interpreter.osc_command == 52 {
        queue := interpreter.clipboard_actions
        if queue == nil || queue.candidate_byte_count >= len(queue.candidate) {
            return
        }
        queue.candidate[queue.candidate_byte_count] = byte
        queue.candidate_byte_count += 1
        return
    }
    if interpreter.osc_command == 7 || interpreter.osc_command == 133 {
        interpreter_ingest_osc_shell_byte(interpreter, byte)
        return
    }
    if interpreter.osc_command == 4 ||
        (interpreter.osc_command >= 10 && interpreter.osc_command <= 12) ||
        interpreter.osc_command == 104 ||
        (interpreter.osc_command >= 110 && interpreter.osc_command <= 112) {
        state := interpreter.title_state
        if state == nil || state.palette.candidate_byte_count >=
            len(state.palette.candidate) {
            if state != nil { state.palette.candidate_invalid = true }
            return
        }
        palette := &state.palette
        palette.candidate[palette.candidate_byte_count] = byte
        palette.candidate_byte_count += 1
        return
    }
    interpreter_ingest_osc_title_byte(interpreter, byte)
}

// Commit one complete OSC 0/2 title candidate.
interpreter_finish_osc_title :: proc(interpreter: ^Interpreter) {
    state := interpreter.title_state
    if state == nil || interpreter.title_candidate_invalid {
        interpreter.title_rejection_count += 1
        return
    }
    candidate := state.candidate[:state.candidate_byte_count]
    if !utf8.valid_string(string(candidate)) {
        interpreter.title_rejection_count += 1
        return
    }
    state.title = {}
    copy(state.title[:], candidate)
    state.title_byte_count = len(candidate)
    interpreter.title_acceptance_count += 1
}

// Parse one OSC command byte before its required semicolon.
//
// Parameters:
//   - interpreter: The parser accumulating an OSC command identifier.
//   - byte: One command digit, separator, or invalid command byte.
//
// Side effects:
//   - Accumulates a bounded decimal command, starts payload parsing at a semicolon,
//     or marks the command invalid.
interpreter_ingest_osc_command_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if byte >= '0' && byte <= '9' && !interpreter.osc_command_invalid {
        value := interpreter.osc_command * 10 + int(byte - '0')
        if value > CSI_PARAMETER_MAX {
            interpreter.osc_command_invalid = true
        } else {
            interpreter.osc_command = value
            interpreter.osc_command_present = true
        }
    } else if byte == ';' {
        interpreter.osc_payload_started = true
        if !interpreter.osc_command_present {
            interpreter.osc_command_invalid = true
        } else if interpreter.osc_command == 1337 {
            interpreter.osc_payload_started = false
            interpreter.state = .Iterm2
        }
    } else {
        interpreter.osc_command_invalid = true
    }
}

// Retain one OSC 0/2 title byte or mark the candidate invalid.
//
// Parameters:
//   - interpreter: The parser consuming an OSC payload.
//   - byte: One title payload byte.
//
// Side effects:
//   - Appends supported title bytes to bounded candidate storage or marks the
//     candidate invalid when storage is absent or full.
interpreter_ingest_osc_title_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if interpreter.osc_command != 0 && interpreter.osc_command != 2 {
        return
    }
    if interpreter.title_state == nil {
        interpreter.title_candidate_invalid = true
        return
    }
    state := interpreter.title_state
    if state.candidate_byte_count >= len(state.candidate) {
        interpreter.title_candidate_invalid = true
        return
    }
    state.candidate[state.candidate_byte_count] = byte
    state.candidate_byte_count += 1
}

// Commit one complete supported OSC title or preserve the previous title.
//
// Parameters:
//   - interpreter: The parser with one terminated OSC candidate.
//
// Side effects:
//   - Validates and commits OSC 0/2 titles transactionally, updates title or
//     unsupported-sequence diagnostics, and resets sequence state.
interpreter_finish_osc :: proc(interpreter: ^Interpreter) {
    reset_without_payload := interpreter.osc_command == 104 ||
        (interpreter.osc_command >= 110 && interpreter.osc_command <= 112)
    if interpreter.osc_command_invalid ||
        (!interpreter.osc_payload_started && !reset_without_payload) {
        interpreter.unsupported_sequence_count += 1
        interpreter_reset_sequence(interpreter)
        return
    }
    if interpreter.osc_command == 8 {
        interpreter_finish_osc_hyperlink(interpreter)
    } else if interpreter.osc_command == 4 ||
        (interpreter.osc_command >= 10 && interpreter.osc_command <= 12) ||
        interpreter.osc_command == 104 ||
        (interpreter.osc_command >= 110 && interpreter.osc_command <= 112) {
        interpreter_finish_osc_color(interpreter)
    } else if interpreter.osc_command == 7 || interpreter.osc_command == 133 {
        interpreter_finish_osc_shell_integration(interpreter)
    } else if interpreter.osc_command == 52 {
        if interpreter.clipboard_actions == nil {
            interpreter.unsupported_sequence_count += 1
        } else {
            termclipboard.clipboard_action_queue_admit(
                interpreter.clipboard_actions,
                interpreter_sequence_producer(interpreter))
        }
    } else if interpreter.osc_command == 0 || interpreter.osc_command == 2 {
        interpreter_finish_osc_title(interpreter)
    } else if interpreter.osc_command != 1 {
        interpreter.unsupported_sequence_count += 1
    }
    interpreter_reset_sequence(interpreter)
}

// Mark every cell in both retained screens dirty after a palette mutation.
interpreter_invalidate_palette_rendering :: proc(interpreter: ^Interpreter) {
    grids := [2]^termgrid.Grid{interpreter.grid, interpreter.alternate_grid}
    for grid in grids {
        if grid == nil { continue }
        for &row in grid.rows {
            termgrid.grid_mark_dirty(&row, 0, grid.columns)
        }
    }
}

// Reject an invalid or response-blocked color transaction before mutation.
interpreter_reject_osc_color_candidate :: proc(
    state: ^Terminal_Title_State,
    result: termpalette.Terminal_Palette_Parse_Result,
    candidate_invalid: bool) -> bool {
    available_responses := len(state.responses) - state.response_count
    if !candidate_invalid && result.valid &&
        result.query_count <= available_responses { return false }
    state.palette.color_rejection_count += 1
    if result.query_count > available_responses {
        state.palette.query_rejection_count += u64(result.query_count)
        state.response_rejection_count += 1
    }
    return true
}

// Apply one parsed color operation and report whether it mutated the palette.
interpreter_apply_osc_color_operation :: proc(
    interpreter: ^Interpreter,
    operation: termpalette.Terminal_Palette_Operation,
    producer: termmodel.Terminal_Producer) -> bool {
    palette := &interpreter.title_state.palette
    if operation.query {
        interpreter_enqueue_response(interpreter, {
            kind = .Osc_Color,
            first = u32(interpreter.osc_command),
            second = u32(operation.index),
            third = termpalette.terminal_palette_operation_rgba(
                palette, operation),
            producer = producer,
        })
        palette.query_acceptance_count += 1
        return false
    }
    return termpalette.terminal_palette_apply_operation(palette, operation)
}

// Commit one complete dynamic-color OSC transaction or reject it atomically.
interpreter_finish_osc_color :: proc(interpreter: ^Interpreter) {
    state := interpreter.title_state
    if state == nil {
        interpreter.unsupported_sequence_count += 1
        return
    }
    palette := &state.palette
    Palette_Operation :: termpalette.Terminal_Palette_Operation
    operations: [termpalette.TERMINAL_COLOR_OPERATION_CAPACITY]Palette_Operation
    result := termpalette.terminal_palette_parse_osc(
        interpreter.osc_command,
        palette.candidate[:palette.candidate_byte_count], operations[:])
    if interpreter_reject_osc_color_candidate(
        state, result, palette.candidate_invalid) { return }
    producer := interpreter_sequence_producer(interpreter)
    mutated := false
    for operation in operations[:result.count] {
        mutated = interpreter_apply_osc_color_operation(
            interpreter, operation, producer) || mutated
    }
    palette.color_acceptance_count += 1
    if mutated {
        palette.generation += 1
        interpreter_invalidate_palette_rendering(interpreter)
    }
}

// Commit one complete OSC 7 cwd or OSC 133 marker transaction.
interpreter_finish_osc_shell_integration :: proc(interpreter: ^Interpreter) {
    state := interpreter.shell_integration
    if state == nil {
        interpreter.unsupported_sequence_count += 1
        return
    }
    if state.candidate_invalid {
        if interpreter.osc_command == 7 {
            state.cwd_rejection_count += 1
        } else {
            state.marker_rejection_count += 1
        }
        return
    }
    candidate := state.candidate[:state.candidate_byte_count]
    if interpreter.osc_command == 7 {
        termshellintegration.shell_integration_admit_cwd(
            state, string(candidate))
    } else {
        shell_integration_admit_marker(
            state, interpreter.grid, candidate,
            !interpreter.alternate_screen_active)
    }
}

// Validate one complete OSC 8 candidate and return its URI payload.
interpreter_osc_hyperlink_uri :: proc(
    interpreter: ^Interpreter, candidate: []u8) -> (string, bool) {
    separator := -1
    for byte, index in candidate {
        if byte == ';' {
            separator = index
            break
        }
    }
    if interpreter.hyperlink_candidate_invalid || separator < 0 ||
        !termhyperlink.hyperlink_parameters_valid(candidate[:separator]) {
        return "", false
    }
    return string(candidate[separator + 1:]), true
}

// Commit one OSC 8 open/replace/close transaction to active grid write state.
interpreter_finish_osc_hyperlink :: proc(interpreter: ^Interpreter) {
    registry := interpreter.hyperlink_registry
    if registry == nil {
        interpreter.hyperlink_rejection_count += 1
        return
    }
    candidate := registry.candidate[:registry.candidate_byte_count]
    uri, valid := interpreter_osc_hyperlink_uri(interpreter, candidate)
    if !valid {
        interpreter.hyperlink_rejection_count += 1
        return
    }
    if len(uri) == 0 {
        interpreter.active_hyperlink = 0
        interpreter.grid.hyperlink = 0
        interpreter.hyperlink_acceptance_count += 1
        return
    }
    handle, admitted := termhyperlink.hyperlink_registry_admit(
        interpreter.hyperlink_registry, uri)
    if !admitted {
        interpreter.hyperlink_rejection_count += 1
        return
    }
    interpreter.active_hyperlink = handle
    interpreter.grid.hyperlink = handle
    interpreter.hyperlink_acceptance_count += 1
}

//   Parse one bounded CSI byte or enter recovery discard after rejection.
//
// Notes:
//   - Omitted parameters are stored as -1 for command-specific defaulting.
//   - `?` is accepted only before the first private-mode parameter.
//
// Parameters:
//   - interpreter: The parser currently in `Csi`.
//   - byte: The next parameter, separator, final, escape, or malformed byte.
//
// Side effects:
//   - Builds parameters, applies a completed CSI, or updates failure telemetry/state.
interpreter_ingest_csi_byte :: proc(interpreter: ^Interpreter, byte: u8) {
    if byte < 0x20 {
        termgrid.grid_write_control(interpreter.grid, byte)
        return
    }
    if byte == 0x7f {
        return
    }
    interpreter.sequence_bytes += 1
    if interpreter.sequence_bytes > CSI_SEQUENCE_BYTE_CAPACITY {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Csi_Discard
        return
    }
    if interpreter_ingest_csi_parameter_byte(interpreter, byte) {
        return
    }
    if byte >= 0x20 && byte <= 0x2f {
        interpreter_ingest_csi_intermediate_byte(interpreter, byte)
        return
    }
    if byte >= 0x40 && byte <= 0x7e {
        if interpreter.unsupported_parameter_bytes {
            interpreter.unsupported_sequence_count += 1
            interpreter_reset_sequence(interpreter)
        } else {
            interpreter_finish_csi(interpreter, byte)
        }
        return
    }
    interpreter.malformed_sequence_count += 1
    interpreter.state = .Csi_Discard
}

// Retain one CSI intermediate byte or enter unsupported-sequence recovery.
//
// Parameters:
//   - interpreter: Parser that has finished collecting CSI parameters.
//   - byte: Intermediate byte in the inclusive 0x20 through 0x2f range.
//
// Side effects:
//   - Commits a pending parameter and retains the first intermediate, or counts a
//     repeated intermediate and enters discard recovery.
interpreter_ingest_csi_intermediate_byte :: proc(
    interpreter: ^Interpreter, byte: u8) {
    if interpreter.state == .Csi_Intermediate {
        interpreter.unsupported_sequence_count += 1
        interpreter.state = .Csi_Discard
        return
    }
    interpreter_ingest_csi_intermediate(interpreter)
    interpreter.csi_intermediate = byte
}

//   Consume one CSI parameter byte while parameters remain syntactically valid.
//
// Parameters:
//   - interpreter: The parser currently accepting CSI parameter bytes.
//   - byte: A private marker, digit, separator, or other parameter-range byte.
//
// Returns:
//   - True when the byte belongs to CSI parameter syntax; otherwise false.
//
// Side effects:
//   - Updates private-marker, numeric-token, separator, or unsupported-parameter
//     state and may enter bounded discard recovery.
interpreter_ingest_csi_parameter_byte :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    if interpreter_ingest_csi_private_marker(interpreter, byte) {
        return true
    }
    if interpreter.state != .Csi {
        return false
    }
    if byte >= '0' && byte <= '9' {
        interpreter_ingest_csi_digit(interpreter, byte)
        return true
    }
    if byte == ';' || byte == ':' {
        interpreter_ingest_csi_separator(interpreter, byte)
        return true
    }
    return false
}

// Commit one CSI parameter separator or enter bounded overflow recovery.
//
// Parameters:
//   - interpreter: Parser receiving the separator.
//   - byte: Semicolon or colon separator.
//
// Side effects:
//   - Commits the current parameter and records its next separator kind, or enters
//     discard state when parameter storage is full.
interpreter_ingest_csi_separator :: proc(interpreter: ^Interpreter, byte: u8) {
    if !interpreter_push_parameter(interpreter) {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Csi_Discard
        return
    }
    interpreter.parameter_separator_is_colon = byte == ':'
}

// Consume one CSI private marker and retain it only in the leading position.
//
// Parameters:
//   - interpreter: Parser receiving the candidate marker.
//   - byte: Candidate parameter byte.
//
// Returns:
//   - True when byte is a private marker; otherwise false.
//
// Side effects:
//   - Retains one leading marker or marks a duplicate or misplaced marker unsupported.
interpreter_ingest_csi_private_marker :: proc(
    interpreter: ^Interpreter, byte: u8) -> bool {
    marker, recognized := interpreter_csi_private_marker(byte)
    if !recognized {
        return false
    }
    if interpreter.state == .Csi && interpreter.parameter_count == 0 &&
        !interpreter.parameter_present && interpreter.csi_private_marker == .None {
        interpreter.csi_private_marker = marker
    } else {
        interpreter.unsupported_parameter_bytes = true
    }
    return true
}

// Classify one CSI private parameter prefix byte.
//
// Parameters:
//   - byte: Candidate parameter byte.
//
// Returns:
//   - Prefix identity and true for `<`, `=`, `>`, or `?`; otherwise None and false.
interpreter_csi_private_marker :: proc(
    byte: u8) -> (marker: Csi_Private_Marker, recognized: bool) {
    switch byte {
    case '<': return .Less_Than, true
    case '=': return .Equal, true
    case '>': return .Greater_Than, true
    case '?': return .Question, true
    }
    return .None, false
}

//   Enter CSI intermediate state after committing a pending numeric parameter.
//
// Parameters:
//   - interpreter: The parser leaving CSI parameter collection.
//
// Side effects:
//   - Commits a pending token and enters intermediate parsing, or enters discard
//     recovery and records overflow when parameter storage is full.
interpreter_ingest_csi_intermediate :: proc(interpreter: ^Interpreter) {
    if interpreter.state == .Csi && interpreter.parameter_present &&
        !interpreter_push_parameter(interpreter) {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Csi_Discard
        return
    }
    interpreter.state = .Csi_Intermediate
}

//   Accumulate one decimal CSI parameter digit or enter overflow recovery.
//
// Parameters:
//   - interpreter: The parser accumulating the current numeric token.
//   - byte: One ASCII decimal digit.
//
// Side effects:
//   - Extends the current token and marks it present, or records overflow and enters
//     discard when the configured numeric maximum would be exceeded.
interpreter_ingest_csi_digit :: proc(interpreter: ^Interpreter, byte: u8) {
    value := interpreter.parameter_value * 10 + int(byte - '0')
    if value > CSI_PARAMETER_MAX {
        interpreter.overflow_sequence_count += 1
        interpreter.state = .Csi_Discard
        return
    }
    interpreter.parameter_value = value
    interpreter.parameter_present = true
}

//   Commit parameters, apply one CSI final byte, and return to ground.
//
// Parameters:
//   - interpreter: The parser with a complete CSI sequence.
//   - final: The CSI final byte selecting command semantics.
//
// Side effects:
//   - Commits the final token, applies the command when storage permits, records
//     overflow otherwise, and resets sequence state.
interpreter_finish_csi :: proc(interpreter: ^Interpreter, final: u8) {
    parameter_ready := interpreter.state == .Csi_Intermediate &&
        interpreter.parameter_count > 0
    if !parameter_ready && !interpreter_push_parameter(interpreter) {
        interpreter.overflow_sequence_count += 1
    } else {
        interpreter_apply_csi(interpreter, final)
    }
    interpreter_reset_sequence(interpreter)
}

//   Commit the current CSI parameter into fixed parser storage.
//
// Parameters:
//   - interpreter: The active CSI parser.
//
// Returns:
//   - True after appending a present value or -1 default; false when full.
//
// Side effects:
//   - Increments parameter count and resets the current numeric token.
interpreter_push_parameter :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.parameter_count >= len(interpreter.parameters) {
        return false
    }
    value := -1
    if interpreter.parameter_present {
        value = interpreter.parameter_value
    }
    if interpreter.parameter_separator_is_colon {
        value = value + CSI_COLON_PARAMETER_OFFSET if value >= 0 else -2
    }
    interpreter.parameters[interpreter.parameter_count] = value
    interpreter.parameter_count += 1
    interpreter.parameter_value = 0
    interpreter.parameter_present = false
    return true
}

//   Read one CSI parameter with command-specific default substitution.
//
// Parameters:
//   - interpreter: The parser containing committed parameters.
//   - index: Zero-based parameter index.
//   - default: Value used for omitted or absent parameters.
//
// Returns:
//   - The explicit nonnegative parameter, otherwise `default`.
interpreter_parameter :: proc(
    interpreter: ^Interpreter, index, default: int) -> int {

    if index >= interpreter.parameter_count || interpreter.parameters[index] < 0 {
        return default
    }
    value := interpreter.parameters[index]
    if value >= CSI_COLON_PARAMETER_OFFSET {
        value -= CSI_COLON_PARAMETER_OFFSET
    }
    return value
}

//   Apply one completed CSI command or record it as unsupported.
//
// Parameters:
//   - interpreter: The parser containing committed parameters and active grid.
//   - final: The CSI final byte selecting command semantics.
//
// Side effects:
//   - Mutates cursor, cells, style, visibility, or saved state; unsupported commands
//     increment telemetry without leaking sequence bytes into grid text.
interpreter_apply_csi :: proc(interpreter: ^Interpreter, final: u8) {
    if final != 'm' && interpreter_has_colon_parameter(interpreter) {
        interpreter.unsupported_sequence_count += 1
        return
    }
    decrqm := (interpreter.csi_private_marker == .None ||
        interpreter.csi_private_marker == .Question) &&
        interpreter.csi_intermediate == '$' && final == 'p'
    decsca := interpreter.csi_private_marker == .None &&
        interpreter.csi_intermediate == '"' && final == 'q'
    if interpreter.csi_intermediate != 0 && !decrqm && !decsca {
        interpreter.unsupported_sequence_count += 1
        return
    }
    if interpreter.csi_private_marker != .None {
        interpreter_apply_prefixed_csi(interpreter, final)
        return
    }
    if decsca {
        if !interpreter_apply_decsca(interpreter) {
            interpreter.unsupported_sequence_count += 1
        }
        return
    }
    interpreter_apply_unprefixed_csi(interpreter, final)
}

// Apply one unprefixed CSI command or count it as unsupported.
//
// Parameters:
//   - interpreter: Parser containing committed command parameters.
//   - final: CSI final byte selecting command semantics.
//
// Side effects:
//   - Mutates cursor, cells, style, or saved state, or increments unsupported telemetry.
interpreter_apply_unprefixed_csi :: proc(interpreter: ^Interpreter, final: u8) {
    switch final {
    case 'A', 'B', 'C', 'D':
        interpreter_move_cursor(interpreter, final)
    case 'J':
        interpreter_erase_display(interpreter)
    case 'K':
        interpreter_erase_line(interpreter)
    case 'm':
        interpreter_apply_sgr(interpreter)
    case 'c', 'n', 'p', 't':
        if !interpreter_apply_unprefixed_query(interpreter, final) {
            interpreter.unsupported_sequence_count += 1
        }
    case:
        if !interpreter_apply_cursor_state(interpreter, final) &&
            !interpreter_apply_dec_editing_csi(interpreter, final) {
            interpreter.unsupported_sequence_count += 1
        }
    }
}

// Apply one unprefixed terminal query after shared CSI validation.
//
// Parameters:
//   - interpreter: Parser containing the committed query parameters.
//   - final: Query selector `c`, `n`, or `t`.
//
// Returns:
//   - True when the exact query form is supported and its response was queued.
interpreter_apply_unprefixed_query :: proc(
    interpreter: ^Interpreter, final: u8) -> bool {
    switch final {
    case 'c': return interpreter_apply_primary_device_attributes(interpreter)
    case 'n': return interpreter_apply_device_status_report(interpreter)
    case 'p': return interpreter_apply_mode_query(interpreter)
    case 't': return interpreter_apply_window_report(interpreter)
    }
    return false
}

// Queue one ANSI mode status report for `CSI Ps $ p`.
interpreter_apply_mode_query :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != '$' || interpreter.parameter_count != 1 {
        return false
    }
    parameter := interpreter_parameter(interpreter, 0, -1)
    if parameter < 0 { return false }
    status: u32
    if parameter == 4 {
        status = 1 if interpreter.grid.editing.insert_mode else 2
    }
    interpreter_enqueue_response(interpreter, {
        kind = .Mode_Status,
        first = u32(parameter), second = status,
        producer = interpreter_sequence_producer(interpreter),
    })
    return true
}

// Return the producer captured when the current control sequence began.
interpreter_sequence_producer :: proc(
    interpreter: ^Interpreter) -> termmodel.Terminal_Producer {
    if interpreter.title_state == nil {
        return {}
    }
    return interpreter.title_state.sequence_producer
}

// Queue the minimal VT100 primary device-attributes identity.
//
// Returns:
//   - True for an omitted or explicit zero DA1 request; false for extensions.
//
// Side effects:
//   - Queues one producer-tagged semantic reply when retained state is available.
interpreter_apply_primary_device_attributes :: proc(
    interpreter: ^Interpreter) -> bool {
    if interpreter.parameter_count != 1 ||
        interpreter_parameter(interpreter, 0, 0) != 0 {
        return false
    }
    interpreter_enqueue_response(interpreter, {
        kind = .Primary_Device_Attributes,
        producer = interpreter_sequence_producer(interpreter),
    })
    return true
}

// Queue one supported device-status or cursor-position response.
interpreter_apply_device_status_report :: proc(
    interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != 0 || interpreter.parameter_count != 1 {
        return false
    }
    parameter := interpreter_parameter(interpreter, 0, 0)
    response := termmodel.Terminal_Response{
        producer = interpreter_sequence_producer(interpreter),
    }
    switch parameter {
    case 5:
        response.kind = .Device_Status
    case 6:
        response.kind = .Cursor_Position
        response.first = u32(interpreter.grid.cursor.row + 1)
        response.second = u32(interpreter.grid.cursor.column + 1)
    case:
        return false
    }
    interpreter_enqueue_response(interpreter, response)
    return true
}

// Queue one supported terminal size report from committed semantic geometry.
interpreter_apply_window_report :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != 0 || interpreter.parameter_count != 1 {
        return false
    }
    response := termmodel.Terminal_Response{
        producer = interpreter_sequence_producer(interpreter),
    }
    geometry: termmodel.Terminal_Query_Geometry
    if interpreter.title_state != nil {
        geometry = interpreter.title_state.query_geometry
    }
    switch interpreter_parameter(interpreter, 0, 0) {
    case 14:
        if !geometry.valid { return false }
        response.kind = .Window_Pixels
        response.first = geometry.window_height
        response.second = geometry.window_width
    case 16:
        if !geometry.valid { return false }
        response.kind = .Cell_Pixels
        response.first = geometry.cell_height
        response.second = geometry.cell_width
    case 18:
        response.kind = .Text_Area_Size
        response.first = u32(interpreter.grid.row_count)
        response.second = u32(interpreter.grid.columns)
    case:
        return false
    }
    interpreter_enqueue_response(interpreter, response)
    return true
}

// Apply one marker-qualified CSI command or count it as unsupported.
//
// Parameters:
//   - interpreter: Parser containing the retained marker and parameters.
//   - final: CSI final byte selecting command semantics.
//
// Side effects:
//   - Applies supported DEC private modes or increments unsupported telemetry once.
interpreter_apply_prefixed_csi :: proc(interpreter: ^Interpreter, final: u8) {
    if interpreter.csi_private_marker == .Greater_Than && final == 'c' &&
        interpreter_apply_secondary_device_attributes(interpreter) {
        return
    }
    if interpreter.csi_private_marker == .Question && final == 'p' &&
        interpreter_apply_private_mode_query(interpreter) {
        return
    }
    if interpreter.csi_private_marker == .Question &&
        (final == 'J' || final == 'K') &&
        interpreter_selective_erase(interpreter, final) {
        return
    }
    if final == 'm' && interpreter_apply_modify_other_keys(interpreter) {
        return
    }
    if final == 'u' && interpreter_apply_kitty_keyboard(interpreter) {
        return
    }
    if interpreter.csi_private_marker == .Question &&
        interpreter_apply_private_mode(interpreter, final) {
        return
    }
    interpreter.unsupported_sequence_count += 1
}

// Queue Euclid's fixed secondary device identity.
interpreter_apply_secondary_device_attributes :: proc(
    interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != 0 || interpreter.parameter_count != 1 ||
        interpreter_parameter(interpreter, 0, 0) != 0 {
        return false
    }
    interpreter_enqueue_response(interpreter, {
        kind = .Secondary_Device_Attributes,
        producer = interpreter_sequence_producer(interpreter),
    })
    return true
}

// Return DECRQM state for mouse and focus input modes.
interpreter_input_mode_status :: proc(
    interpreter: ^Interpreter, parameter: int) -> (u32, bool) {
    mode := interpreter.input_mode
    switch parameter {
    case 1000: return 1 if mode.mouse_tracking == .Button else 2, true
    case 1002: return 1 if mode.mouse_tracking == .Button_Motion else 2, true
    case 1003: return 1 if mode.mouse_tracking == .Any_Motion else 2, true
    case 1004: return 1 if mode.focus_reporting else 2, true
    case 1006: return 1 if mode.mouse_sgr_encoding else 2, true
    case 1016: return 1 if mode.mouse_pixel_coordinates else 2, true
    }
    return 0, false
}

// Return DECRQM state for grid editing modes.
interpreter_grid_mode_status :: proc(
    interpreter: ^Interpreter, parameter: int) -> (u32, bool) {
    editing := interpreter.grid.editing
    switch parameter {
    case 6: return 1 if editing.origin_mode else 2, true
    case 7: return 1 if editing.autowrap_mode else 2, true
    case 80: return 1 if editing.sixel_scrolling_mode else 2, true
    case 8452: return 1 if editing.sixel_cursor_right_mode else 2, true
    case 1048: return 1 if editing.dec_saved.valid else 2, true
    }
    return 0, false
}

// Return DECRQM state for display lifecycle modes.
interpreter_display_mode_status :: proc(
    interpreter: ^Interpreter, parameter: int) -> (u32, bool) {
    switch parameter {
    case 25: return 1 if interpreter.cursor_visible else 2, true
    case 1049: return 1 if interpreter.alternate_screen_active else 2, true
    case 2026:
        synchronized := interpreter.synchronized_output
        if synchronized == nil { return 0, true }
        return 1 if synchronized.active else 2, true
    }
    return 0, false
}

// Return the DECRQM state code for one implemented DEC private mode.
interpreter_private_mode_status :: proc(
    interpreter: ^Interpreter, parameter: int) -> u32 {
    if status, found := interpreter_input_mode_status(
        interpreter, parameter); found {
        return status
    }
    if status, found := interpreter_grid_mode_status(
        interpreter, parameter); found {
        return status
    }
    if status, found := interpreter_display_mode_status(
        interpreter, parameter); found {
        return status
    }
    switch parameter {
    case 1:
        return 1 if interpreter.input_mode.cursor_keys_application else 2
    case 2004:
        return 1 if interpreter.input_mode.bracketed_paste else 2
    }
    return 0
}

// Queue one DEC private-mode status report for `CSI ? Ps $ p`.
interpreter_apply_private_mode_query :: proc(
    interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != '$' || interpreter.parameter_count != 1 {
        return false
    }
    parameter := interpreter_parameter(interpreter, 0, -1)
    if parameter < 0 { return false }
    interpreter_enqueue_response(interpreter, {
        kind = .Private_Mode_Status,
        first = u32(parameter),
        second = interpreter_private_mode_status(interpreter, parameter),
        producer = interpreter_sequence_producer(interpreter),
    })
    return true
}

// Apply one exact xterm modifyOtherKeys query.
//
// Returns:
//   - True when the current parameters name the supported query.
//
// Side effects:
//   - Queues one producer-tagged semantic reply when retained state is available.
interpreter_query_modify_other_keys :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_private_marker != .Question ||
        interpreter.parameter_count != 1 || interpreter.parameters[0] != 4 {
        return false
    }
    state := interpreter.title_state
    if state != nil {
        interpreter_enqueue_response(interpreter, {
            kind = .Modify_Other_Keys,
            first = u32(state.modify_other_keys_level),
            producer = state.sequence_producer,
        })
    }
    return true
}

// Apply one exact xterm modifyOtherKeys level mutation.
//
// Returns:
//   - True when the current parameters name a supported set or reset command.
//
// Side effects:
//   - Updates the terminal-global level when retained state is available.
interpreter_set_modify_other_keys :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_private_marker != .Greater_Than ||
        interpreter.parameters[0] != 4 {
        return false
    }
    state := interpreter.title_state
    if interpreter.parameter_count == 1 {
        if state != nil { state.modify_other_keys_level = 0 }
        return true
    }
    if interpreter.parameter_count != 2 || interpreter.parameters[1] < 0 ||
        interpreter.parameters[1] > 2 {
        return false
    }
    if state != nil {
        state.modify_other_keys_level = u8(interpreter.parameters[1])
    }
    return true
}

// Apply one exact xterm modifyOtherKeys mutation or query.
//
// Returns:
//   - True when the marker and parameters name a supported Phase 4 command.
interpreter_apply_modify_other_keys :: proc(interpreter: ^Interpreter) -> bool {
    return interpreter_query_modify_other_keys(interpreter) ||
        interpreter_set_modify_other_keys(interpreter)
}

// Push the active Kitty flags, evicting the oldest entry when storage is full.
interpreter_push_kitty_keyboard :: proc(
    state: ^Kitty_Keyboard_State, flags: u8) {
    if state == nil {
        return
    }
    if state.stack_count == len(state.stack) {
        copy(state.stack[:], state.stack[1:])
        state.stack_count -= 1
    }
    state.stack[state.stack_count] = state.flags
    state.stack_count += 1
    state.flags = flags & KITTY_KEYBOARD_SUPPORTED_FLAGS
}

// Pop bounded Kitty state, resetting flags when the requested count exhausts it.
interpreter_pop_kitty_keyboard :: proc(
    state: ^Kitty_Keyboard_State, count: int) {
    if state == nil {
        return
    }
    if count >= state.stack_count {
        state.flags = 0
        state.stack = {}
        state.stack_count = 0
        return
    }
    state.stack_count -= count
    state.flags = state.stack[state.stack_count]
}

// Return whether every Kitty parameter boundary uses a semicolon.
interpreter_kitty_parameters_are_semicolon :: proc(
    interpreter: ^Interpreter) -> bool {
    for index in 1..<interpreter.parameter_count {
        if interpreter_parameter_separator(interpreter, index) != .Semicolon {
            return false
        }
    }
    return true
}

// Apply one exact Kitty push command to the active screen.
interpreter_apply_kitty_push :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.parameter_count != 1 || interpreter.parameters[0] < -1 {
        return false
    }
    flags := u8(interpreter_parameter(interpreter, 0, 0) &
        int(KITTY_KEYBOARD_SUPPORTED_FLAGS))
    interpreter_push_kitty_keyboard(
        interpreter_active_kitty_state(interpreter), flags)
    return true
}

// Apply one exact Kitty pop command to the active screen.
interpreter_apply_kitty_pop :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.parameter_count != 1 ||
        (interpreter.parameters[0] != -1 && interpreter.parameters[0] <= 0) {
        return false
    }
    interpreter_pop_kitty_keyboard(
        interpreter_active_kitty_state(interpreter),
        interpreter_parameter(interpreter, 0, 1))
    return true
}

// Apply one exact Kitty replace, set, or clear command to the active screen.
interpreter_apply_kitty_flags :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.parameter_count > 2 || interpreter.parameters[0] < 0 {
        return false
    }
    mode := interpreter_parameter(interpreter, 1, 1)
    if mode < 1 || mode > 3 {
        return false
    }
    state := interpreter_active_kitty_state(interpreter)
    if state == nil { return true }
    flags := u8(interpreter.parameters[0] & int(KITTY_KEYBOARD_SUPPORTED_FLAGS))
    if mode == 1 { state.flags = flags }
    if mode == 2 { state.flags |= flags }
    if mode == 3 { state.flags &~= flags }
    return true
}

// Apply one Kitty keyboard mutation to the active screen.
interpreter_mutate_kitty_keyboard :: proc(
    interpreter: ^Interpreter, marker: Csi_Private_Marker) -> bool {
    if interpreter.parameter_count < 1 ||
        !interpreter_kitty_parameters_are_semicolon(interpreter) {
        return false
    }
    switch marker {
    case .Greater_Than:
        return interpreter_apply_kitty_push(interpreter)
    case .Less_Than:
        return interpreter_apply_kitty_pop(interpreter)
    case .Equal:
        return interpreter_apply_kitty_flags(interpreter)
    case .None, .Question:
        return false
    }
    return false
}

// Apply one Kitty keyboard query or mutation.
//
// Returns:
//   - True when the marker and parameters name a supported Kitty command.
interpreter_apply_kitty_keyboard :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_private_marker == .Question &&
        interpreter.parameter_count == 1 && interpreter.parameters[0] == -1 {
        state := interpreter_active_kitty_state(interpreter)
        value := state.flags if state != nil else 0
        producer: termmodel.Terminal_Producer
        if interpreter.title_state != nil {
            producer = interpreter.title_state.sequence_producer
        }
        interpreter_enqueue_response(interpreter, {
            kind = .Kitty_Keyboard, first = u32(value), producer = producer,
        })
        return true
    }
    return interpreter_mutate_kitty_keyboard(
        interpreter, interpreter.csi_private_marker)
}

// Retain one semantic reply in the fixed interpreter queue.
//
// Returns:
//   - True after complete admission; false when bounded storage is full.
//
// Side effects:
//   - Increments response rejection telemetry on capacity pressure.
interpreter_enqueue_response :: proc(
    interpreter: ^Interpreter, response: termmodel.Terminal_Response) -> bool {
    state := interpreter.title_state
    if state == nil || state.response_count >= len(state.responses) {
        if state != nil {
            state.response_rejection_count += 1
        }
        return false
    }
    index := (state.response_start + state.response_count) % len(state.responses)
    state.responses[index] = response
    state.response_count += 1
    return true
}

// Read the oldest semantic reply without removing it.
interpreter_peek_response :: proc(
    interpreter: ^Interpreter) -> (termmodel.Terminal_Response, bool) {
    if interpreter == nil || interpreter.title_state == nil ||
        interpreter.title_state.response_count == 0 {
        return {}, false
    }
    state := interpreter.title_state
    return state.responses[state.response_start], true
}

// Remove the oldest semantic reply after admission or stale-owner rejection.
interpreter_pop_response :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter == nil || interpreter.title_state == nil ||
        interpreter.title_state.response_count == 0 {
        return false
    }
    state := interpreter.title_state
    state.responses[state.response_start] = {}
    state.response_start = (state.response_start + 1) % len(state.responses)
    state.response_count -= 1
    if state.response_count == 0 {
        state.response_start = 0
    }
    return true
}

// Return whether one committed CSI parameter was introduced by a colon.
//
// Parameters:
//   - interpreter: The parser containing committed CSI parameters.
//
// Returns:
//   - True when any committed parameter carries colon-separator metadata.
interpreter_has_colon_parameter :: proc(interpreter: ^Interpreter) -> bool {
    for parameter in interpreter.parameters[:interpreter.parameter_count] {
        if parameter == -2 || parameter >= CSI_COLON_PARAMETER_OFFSET {
            return true
        }
    }
    return false
}

// Return the separator that introduced one committed CSI parameter.
//
// Parameters:
//   - interpreter: The parser containing committed CSI parameters.
//   - index: Zero-based parameter index to inspect.
//
// Returns:
//   - Colon or Semicolon for a valid introduced parameter; None for the first or
//     an out-of-range parameter.
interpreter_parameter_separator :: proc(
    interpreter: ^Interpreter, index: int) -> Csi_Parameter_Separator {
    if index <= 0 || index >= interpreter.parameter_count {
        return .None
    }
    parameter := interpreter.parameters[index]
    return .Colon if parameter == -2 ||
        parameter >= CSI_COLON_PARAMETER_OFFSET else .Semicolon
}

//   Apply cursor positioning, save, and restore CSI commands.
//
// Parameters:
//   - interpreter: The parser containing command parameters and active grid state.
//   - final: The CSI final byte to interpret as position, save, or restore.
//
// Returns:
//   - True when the final byte names a supported cursor-state command.
//
// Side effects:
//   - Moves the active cursor, captures it as saved state, or restores previously
//     saved state when available.
interpreter_apply_cursor_state :: proc(interpreter: ^Interpreter, final: u8) -> bool {
    switch final {
    case 'H', 'f':
        row := interpreter_parameter(interpreter, 0, 1) - 1
        column := interpreter_parameter(interpreter, 1, 1) - 1
        if interpreter.grid.editing.origin_mode {
            row += interpreter.grid.editing.scroll_top
            row = clamp(row, interpreter.grid.editing.scroll_top,
                interpreter.grid.editing.scroll_bottom)
        }
        termgrid.grid_set_cursor(interpreter.grid, row, column)
    case 's':
        interpreter.saved_cursor = interpreter.grid.cursor
        interpreter.has_saved_cursor = true
    case 'u':
        if interpreter.has_saved_cursor {
            cursor := interpreter.saved_cursor
            termgrid.grid_set_cursor(interpreter.grid, cursor.row, cursor.column)
        }
    case:
        return false
    }
    return true
}

//   Apply supported DEC private mode transitions in parameter order.
//
// Notes:
//   - Mode 1 controls cursor-key encoding, mode 25 controls cursor visibility,
//     mode 1049 swaps alternate-screen state, and mode 2004 controls paste framing.
//   - Supported modes in a mixed list apply even when another mode is unsupported.
//
// Parameters:
//   - interpreter: The parser with committed private parameters.
//   - final: `h` to set the mode or `l` to reset it.
//
// Returns:
//   - True when every private mode is supported; otherwise false.
//
// Side effects:
//   - May change cursor visibility or enter/leave the alternate viewport.
interpreter_apply_private_mode :: proc(
    interpreter: ^Interpreter, final: u8) -> bool {
    if interpreter.parameter_count == 0 || (final != 'h' && final != 'l') {
        return false
    }
    supported := true
    for index in 0..<interpreter.parameter_count {
        if !interpreter_apply_private_mode_value(
            interpreter, interpreter_parameter(interpreter, index, -1), final) {
            supported = false
        }
    }
    return supported
}

// Select or conditionally clear one mutually exclusive mouse tracking mode.
//
// Parameters:
//   - interpreter: Parser whose negotiated tracking mode is updated.
//   - tracking: Tracking mode selected or conditionally cleared.
//   - final: `h` to select tracking or `l` to clear it when active.
//
// Side effects:
//   - Mutates the authoritative mouse tracking mode.
interpreter_apply_mouse_tracking_mode :: proc(
    interpreter: ^Interpreter, tracking: termmodel.Terminal_Mouse_Tracking_Mode,
    final: u8) {
    if final == 'h' {
        interpreter.input_mode.mouse_tracking = tracking
    } else if interpreter.input_mode.mouse_tracking == tracking {
        interpreter.input_mode.mouse_tracking = .None
    }
}

// Apply one supported mouse-reporting DEC private mode value.
//
// Parameters:
//   - interpreter: The parser whose negotiated input modes are updated.
//   - parameter: The candidate DEC private mode number.
//   - final: `h` to set the mode or `l` to reset it.
//
// Returns:
//   - True for recognized modes 1000, 1002, 1003, 1006, and 1016; otherwise false.
//
// Side effects:
//   - Selects button, button-motion, or any-motion tracking; conditionally clears the
//     selected tracking mode; or toggles independent SGR syntax and pixel coordinates.
interpreter_apply_mouse_private_mode_value :: proc(
    interpreter: ^Interpreter, parameter: int, final: u8) -> bool {
    switch parameter {
    case 1000:
        interpreter_apply_mouse_tracking_mode(interpreter, .Button, final)
    case 1002:
        interpreter_apply_mouse_tracking_mode(interpreter, .Button_Motion, final)
    case 1003:
        interpreter_apply_mouse_tracking_mode(interpreter, .Any_Motion, final)
    case 1006:
        interpreter.input_mode.mouse_sgr_encoding = final == 'h'
    case 1016:
        interpreter.input_mode.mouse_pixel_coordinates = final == 'h'
    case:
        return false
    }
    return true
}

// Apply one supported screen-local DEC state mode.
interpreter_apply_dec_state_private_mode :: proc(
    interpreter: ^Interpreter, parameter: int, final: u8) -> bool {
    switch parameter {
    case 6:
        interpreter.grid.editing.origin_mode = final == 'h'
        row := interpreter.grid.editing.scroll_top if final == 'h' else 0
        termgrid.grid_set_cursor(interpreter.grid, row, 0)
    case 7:
        interpreter.grid.editing.autowrap_mode = final == 'h'
        interpreter.grid.cursor.wrap_pending = false
    case 1048:
        if final == 'h' {
            interpreter_save_dec_state(interpreter)
        } else {
            interpreter_restore_dec_state(interpreter)
        }
    case: return false
    }
    return true
}

// Apply alternate-screen or synchronized-output private modes.
interpreter_apply_display_private_mode :: proc(
    interpreter: ^Interpreter, parameter: int, final: u8) -> (bool, bool) {
    if parameter == 1049 {
        if interpreter.alternate_grid == nil { return false, true }
        if final == 'h' {
            interpreter_enter_alternate_screen(interpreter)
        } else {
            interpreter_leave_alternate_screen(interpreter)
        }
        return true, true
    }
    if parameter == 2026 {
        applied := interpreter_begin_synchronized_output(interpreter) if
            final == 'h' else
            interpreter_publish_synchronized_output(interpreter, false)
        return applied, true
    }
    return false, false
}

// Apply one DEC private mode value.
//
// Parameters:
//   - interpreter: The parser and presentation state to update.
//   - parameter: The candidate DEC private mode number.
//   - final: `h` to set the mode or `l` to reset it.
//
// Returns:
//   - True when the mode is supported and applicable; otherwise false.
//
// Side effects:
//   - May update negotiated input modes, cursor visibility, or active primary and
//     alternate screen state.
interpreter_apply_private_mode_value :: proc(
    interpreter: ^Interpreter, parameter: int, final: u8) -> bool {
    if interpreter_apply_mouse_private_mode_value(interpreter, parameter, final) {
        return true
    }
    if interpreter_apply_dec_state_private_mode(interpreter, parameter, final) {
        return true
    }
    if applied, recognized := interpreter_apply_display_private_mode(
        interpreter, parameter, final); recognized {
        return applied
    }
    switch parameter {
    case 1:
        interpreter.input_mode.cursor_keys_application = final == 'h'
        return true
    case 80:
        interpreter.grid.editing.sixel_scrolling_mode = final == 'h'
        return true
    case 8452:
        interpreter.grid.editing.sixel_cursor_right_mode = final == 'h'
        return true
    case 25:
        interpreter.cursor_visible = final == 'h'
        return true
    case 1004:
        interpreter.input_mode.focus_reporting = final == 'h'
        return true
    case 2004:
        interpreter.input_mode.bracketed_paste = final == 'h'
        return true
    }
    return false
}

// Capture the current presentation once before synchronized mutations continue.
interpreter_begin_synchronized_output :: proc(interpreter: ^Interpreter) -> bool {
    synchronized := interpreter.synchronized_output
    if synchronized == nil || synchronized.scrollback == nil ||
        synchronized.output_started == nil {
        return false
    }
    if synchronized.active {
        return true
    }
    if !termgrid.display_checkpoint_capture(
        &synchronized.checkpoint, interpreter.grid, synchronized.scrollback) {
        synchronized.capture_failure_count += 1
        return true
    }
    synchronized.producer = interpreter_sequence_producer(interpreter)
    synchronized.captured_output_started = synchronized.output_started^ ||
        termgrid.display_checkpoint_contains_output(&synchronized.checkpoint)
    synchronized.captured_alternate_screen_active =
        interpreter.alternate_screen_active
    synchronized.captured_cursor_visible = interpreter.cursor_visible
    synchronized.active = true
    synchronized.deadline_armed = false
    synchronized.deadline = 0
    synchronized.begin_count += 1
    return true
}

// Publish live authoritative state after a normal reset or forced boundary.
interpreter_publish_synchronized_output :: proc(
    interpreter: ^Interpreter, forced: bool) -> bool {
    synchronized := interpreter.synchronized_output
    if synchronized == nil {
        return false
    }
    if !synchronized.active {
        return true
    }
    synchronized.active = false
    synchronized.producer = {}
    synchronized.deadline_armed = false
    synchronized.deadline = 0
    if forced {
        synchronized.forced_publish_count += 1
    } else {
        synchronized.publish_count += 1
    }
    return true
}

//   Enter a freshly cleared alternate viewport while preserving primary state.
//
// Notes:
//   - Repeated entry while already active is a no-op.
//   - Alternate output uses the alternate grid's sink, normally none, so it does
//     not enter primary scrollback.
//
// Parameters:
//   - interpreter: An initialized interpreter with a compatible alternate grid.
//
// Side effects:
//   - Saves primary cursor/visibility state, clears the alternate grid, swaps grid
//     values, resets active saved-cursor state, and marks mode 1049 active.
interpreter_enter_alternate_screen :: proc(interpreter: ^Interpreter) {
    if interpreter.alternate_screen_active {
        return
    }
    interpreter_publish_synchronized_output(interpreter, true)
    interpreter.primary_cursor = interpreter.grid.cursor
    interpreter.primary_cursor_visible = interpreter.cursor_visible
    interpreter.primary_saved_cursor = interpreter.saved_cursor
    interpreter.primary_has_saved_cursor = interpreter.has_saved_cursor

    alternate := interpreter.alternate_grid
    termgrid.grid_remove_placements(alternate)
    for row_index in 0..<alternate.row_count {
        termgrid.grid_clear_row(alternate, row_index)
    }
    alternate.cursor = {}
    alternate.style = {}
    alternate.hyperlink = interpreter.active_hyperlink
    alternate.pending_utf8_len = 0

    primary := interpreter.grid^
    interpreter.grid^ = alternate^
    alternate^ = primary
    interpreter.saved_cursor = {}
    interpreter.has_saved_cursor = false
    interpreter.cursor_visible = true
    interpreter.alternate_screen_active = true
}

//   Leave the alternate viewport and restore exact primary presentation state.
//
// Notes:
//   - Repeated leave while primary is active is a no-op.
//
// Parameters:
//   - interpreter: The interpreter whose mode 1049 state may be active.
//
// Side effects:
//   - Swaps grid values back and restores primary cursor, visibility, and saved cursor.
interpreter_leave_alternate_screen :: proc(interpreter: ^Interpreter) {
    if !interpreter.alternate_screen_active {
        return
    }
    interpreter_publish_synchronized_output(interpreter, true)
    termgrid.grid_remove_placements(interpreter.grid)
    alternate := interpreter.grid^
    interpreter.grid^ = interpreter.alternate_grid^
    interpreter.alternate_grid^ = alternate
    interpreter.grid.cursor = interpreter.primary_cursor
    interpreter.grid.hyperlink = interpreter.active_hyperlink
    interpreter.cursor_visible = interpreter.primary_cursor_visible
    interpreter.saved_cursor = interpreter.primary_saved_cursor
    interpreter.has_saved_cursor = interpreter.primary_has_saved_cursor
    interpreter.alternate_screen_active = false
}

//   Recover a usable primary viewport after abnormal backend termination.
//
// Parameters:
//   - interpreter: The interpreter expected to be on the alternate screen.
//
// Returns:
//   - True after recovery, or false for nil/inactive state.
//
// Side effects:
//   - Drops alternate pending UTF-8, counts/resets an incomplete control sequence,
//     restores primary state, and forces visible cursor/default style.
interpreter_restore_primary_screen :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter == nil || !interpreter.alternate_screen_active {
        return false
    }
    interpreter.grid.pending_utf8_len = 0
    if interpreter.state != .Ground {
        interpreter.malformed_sequence_count += 1
        interpreter_reset_sequence(interpreter)
    }
    interpreter_leave_alternate_screen(interpreter)
    interpreter.cursor_visible = true
    interpreter.grid.style = {
        foreground = {},
    }
    return true
}

//   Move the cursor by one defaulted positive CSI distance.
//
// Parameters:
//   - interpreter: The parser and active grid to update.
//   - final: One of `A`, `B`, `C`, or `D` selecting movement direction.
//
// Side effects:
//   - Moves by at least one cell, clamps to visible bounds, and cancels delayed wrap.
interpreter_move_cursor :: proc(interpreter: ^Interpreter, final: u8) {
    amount := max(interpreter_parameter(interpreter, 0, 1), 1)
    row := interpreter.grid.cursor.row
    column := interpreter.grid.cursor.column
    switch final {
    case 'A':
        row -= amount
        if interpreter.grid.editing.origin_mode {
            row = max(row, interpreter.grid.editing.scroll_top)
        }
    case 'B':
        row += amount
        if interpreter.grid.editing.origin_mode {
            row = min(row, interpreter.grid.editing.scroll_bottom)
        }
    case 'C': column += amount
    case 'D': column -= amount
    }
    termgrid.grid_set_cursor(interpreter.grid, row, column)
}

//   Apply supported CSI erase-in-line mode without moving the cursor.
//
// Parameters:
//   - interpreter: The parser containing the optional mode and active grid.
//
// Side effects:
//   - Erases mode 0, 1, or 2 using active style; unsupported modes increment telemetry.
interpreter_erase_line :: proc(interpreter: ^Interpreter) {
    mode := interpreter_parameter(interpreter, 0, 0)
    column := interpreter.grid.cursor.column
    switch mode {
    case 0:
        termgrid.grid_erase_range(interpreter.grid, interpreter.grid.cursor.row,
            column, interpreter.grid.columns)
    case 1:
        termgrid.grid_erase_range(interpreter.grid, interpreter.grid.cursor.row, 0, column + 1)
    case 2:
        termgrid.grid_erase_range(interpreter.grid, interpreter.grid.cursor.row,
            0, interpreter.grid.columns)
    case:
        interpreter.unsupported_sequence_count += 1
    }
}

//   Apply supported CSI erase-in-display mode without moving the cursor.
//
// Parameters:
//   - interpreter: The parser containing the optional mode and active grid.
//
// Side effects:
//   - Erases mode 0, 1, or 2 across bounded rows; unsupported modes increment
//     telemetry. termgrid.Cursor position and scrollback remain unchanged.
interpreter_erase_display :: proc(interpreter: ^Interpreter) {
    mode := interpreter_parameter(interpreter, 0, 0)
    grid := interpreter.grid
    switch mode {
    case 0:
        termgrid.grid_erase_range(grid, grid.cursor.row, grid.cursor.column, grid.columns)
        for row in grid.cursor.row + 1..<grid.row_count {
            termgrid.grid_erase_range(grid, row, 0, grid.columns)
        }
    case 1:
        for row in 0..<grid.cursor.row {
            termgrid.grid_erase_range(grid, row, 0, grid.columns)
        }
        termgrid.grid_erase_range(grid, grid.cursor.row, 0, grid.cursor.column + 1)
    case 2:
        for row in 0..<grid.row_count {
            termgrid.grid_erase_range(grid, row, 0, grid.columns)
        }
    case:
        interpreter.unsupported_sequence_count += 1
    }
}

//   Apply all parameters from one completed SGR sequence.
//
// Notes:
//   - An omitted sole parameter defaults to reset (`0`).
//   - Supported parameters still apply when another parameter is unsupported.
//
// Parameters:
//   - interpreter: The parser containing SGR parameters and active grid style.
//
// Side effects:
//   - Mutates active style and increments unsupported telemetry once if any value
//     falls outside the supported subset.
interpreter_apply_sgr :: proc(interpreter: ^Interpreter) {
    if interpreter.parameter_count == 1 && interpreter.parameters[0] < 0 {
        interpreter_apply_sgr_parameter(interpreter.grid, 0)
        return
    }
    supported := true
    index := 0
    for index < interpreter.parameter_count {
        parameter := max(interpreter_parameter(interpreter, index, 0), 0)
        if parameter == 38 || parameter == 48 {
            consumed, color_supported := interpreter_apply_sgr_color(
                interpreter, index, parameter == 38)
            supported = color_supported && supported
            index += consumed
        } else {
            supported = interpreter_apply_sgr_parameter(
                interpreter.grid, parameter) && supported
            index += 1
        }
    }
    if !supported {
        interpreter.unsupported_sequence_count += 1
    }
}

// Apply one complete indexed or direct-color SGR group.
//
// Parameters:
//   - interpreter: The parser containing committed SGR parameters.
//   - index: Zero-based position of the leading 38 or 48 parameter.
//   - foreground: Whether the group targets foreground rather than background.
//
// Returns:
//   - The number of parameters consumed and whether a supported color was applied.
//
// Side effects:
//   - Delegates valid indexed or direct-color groups to the active grid style.
interpreter_apply_sgr_color :: proc(
    interpreter: ^Interpreter, index: int,
    foreground: bool) -> (consumed: int, supported: bool) {
    if index + 1 >= interpreter.parameter_count {
        return 1, false
    }
    separator := interpreter_parameter_separator(interpreter, index + 1)
    if separator != .Semicolon && separator != .Colon {
        return 1, false
    }
    mode := interpreter_parameter(interpreter, index + 1, -1)
    if mode == 5 {
        return interpreter_apply_sgr_indexed_color(
            interpreter, index, separator, foreground)
    }
    if mode == 2 {
        return interpreter_apply_sgr_direct_color(
            interpreter, index, separator, foreground)
    }
    return 2, false
}

// Apply one validated `38/48;5` or `38/48:5` indexed color.
//
// Parameters:
//   - interpreter: The parser containing the indexed-color group.
//   - index: Zero-based position of the leading 38 or 48 parameter.
//   - separator: Separator form that all group members must match.
//   - foreground: Whether the group targets foreground rather than background.
//
// Returns:
//   - The number of parameters consumed and true for a valid palette index;
//     otherwise a bounded recovery count and false.
//
// Side effects:
//   - Applies the resolved palette color to the active grid style on success.
interpreter_apply_sgr_indexed_color :: proc(
    interpreter: ^Interpreter, index: int,
    separator: Csi_Parameter_Separator, foreground: bool) -> (int, bool) {
    value_index := index + 2
    if value_index >= interpreter.parameter_count ||
        interpreter_parameter_separator(interpreter, value_index) != separator {
        return min(2, interpreter.parameter_count - index), false
    }
    if separator == .Colon && value_index + 1 < interpreter.parameter_count &&
        interpreter_parameter_separator(interpreter, value_index + 1) == .Colon {
        return interpreter_sgr_colon_group_length(interpreter, index), false
    }
    value := interpreter_parameter(interpreter, value_index, -1)
    if value < 0 || value > 255 {
        return 3, false
    }
    interpreter_set_sgr_color(
        interpreter.grid, termpalette.terminal_color_indexed(value), foreground)
    return 3, true
}

// Apply one validated semicolon or colon direct-RGB color.
//
// Parameters:
//   - interpreter: The parser containing the direct-color group.
//   - index: Zero-based position of the leading 38 or 48 parameter.
//   - separator: Separator form that all group members must match.
//   - foreground: Whether the group targets foreground rather than background.
//
// Returns:
//   - The number of parameters consumed and true when all RGB components are valid;
//     otherwise a bounded recovery count and false.
//
// Side effects:
//   - Packs and applies an opaque direct color to the active grid style on success.
interpreter_apply_sgr_direct_color :: proc(
    interpreter: ^Interpreter, index: int,
    separator: Csi_Parameter_Separator, foreground: bool) -> (int, bool) {
    red_index := index + 2
    if separator == .Colon && red_index < interpreter.parameter_count &&
        interpreter_parameter(interpreter, red_index, -1) < 0 {
        red_index += 1
    }
    blue_index := red_index + 2
    consumed := blue_index - index + 1
    if blue_index >= interpreter.parameter_count {
        return interpreter.parameter_count - index, false
    }
    for component_index in red_index..=blue_index {
        if interpreter_parameter_separator(interpreter, component_index) != separator {
            return consumed, false
        }
    }
    if separator == .Colon && blue_index + 1 < interpreter.parameter_count &&
        interpreter_parameter_separator(interpreter, blue_index + 1) == .Colon {
        return interpreter_sgr_colon_group_length(interpreter, index), false
    }
    red := interpreter_parameter(interpreter, red_index, -1)
    green := interpreter_parameter(interpreter, red_index + 1, -1)
    blue := interpreter_parameter(interpreter, blue_index, -1)
    if red < 0 || red > 255 || green < 0 || green > 255 ||
        blue < 0 || blue > 255 {
        return consumed, false
    }
    rgba := u32(red << 24 | green << 16 | blue << 8 | 0xff)
    interpreter_set_sgr_color(
        interpreter.grid, termpalette.terminal_color_direct(rgba), foreground)
    return consumed, true
}

// Count one colon-delimited SGR group through its next semicolon boundary.
//
// Parameters:
//   - interpreter: The parser containing committed SGR parameters.
//   - index: Zero-based start of the group to count.
//
// Returns:
//   - The number of parameters through the next non-colon separator or list end.
interpreter_sgr_colon_group_length :: proc(
    interpreter: ^Interpreter, index: int) -> int {
    end := index + 1
    for end < interpreter.parameter_count &&
        interpreter_parameter_separator(interpreter, end) == .Colon {
        end += 1
    }
    return end - index
}

// Set one active rendition color channel.
//
// Parameters:
//   - grid: The active grid whose current style is updated.
//   - color: Semantic color reference to install.
//   - foreground: True for the foreground channel; false for the background.
//
// Side effects:
//   - Mutates the selected active style channel for future cell writes.
interpreter_set_sgr_color :: proc(
    grid: ^termgrid.Grid, color: termmodel.Terminal_Color_Reference, foreground: bool) {
    if foreground {
        grid.style.foreground = color
    } else {
        grid.style.background = color
    }
}

//   Apply one SGR parameter to the grid's active rendition.
//
// Parameters:
//   - grid: The active grid whose future-write style is modified.
//   - parameter: One normalized nonnegative SGR value.
//
// Returns:
//   - True for reset, attributes, or supported foreground/background colors;
//     false without mutation for unsupported values.
//
// Side effects:
//   - Mutates only `grid.style`; existing cells retain their captured rendition.
interpreter_apply_sgr_parameter :: proc(grid: ^termgrid.Grid, parameter: int) -> bool {
    if parameter == 0 {
        grid.style = {}
        return true
    }
    if interpreter_apply_sgr_attribute(grid, parameter) {
        return true
    }
    if parameter >= 30 && parameter <= 37 {
        grid.style.foreground = termpalette.terminal_color_indexed(parameter - 30)
        return true
    }
    if parameter >= 90 && parameter <= 97 {
        grid.style.foreground = termpalette.terminal_color_indexed(parameter - 82)
        return true
    }
    if parameter >= 40 && parameter <= 47 {
        grid.style.background = termpalette.terminal_color_indexed(parameter - 40)
        return true
    }
    if parameter >= 100 && parameter <= 107 {
        grid.style.background = termpalette.terminal_color_indexed(parameter - 92)
        return true
    }
    if parameter == 49 {
        grid.style.background = {}
        return true
    }
    return false
}

//   Apply one supported SGR text-attribute transition.
//
// Parameters:
//   - grid: The active grid whose current style is updated.
//   - parameter: One normalized SGR attribute parameter.
//
// Returns:
//   - True when the parameter is a supported attribute transition; otherwise false.
//
// Side effects:
//   - Toggles bold, italic, or underline state, or restores the default foreground.
interpreter_apply_sgr_attribute :: proc(grid: ^termgrid.Grid, parameter: int) -> bool {
    switch parameter {
    case 1: grid.style.bold = true
    case 3: grid.style.italic = true
    case 4: grid.style.underline = true
    case 22: grid.style.bold = false
    case 23: grid.style.italic = false
    case 24: grid.style.underline = false
    case 39: grid.style.foreground = {}
    case:
        return false
    }
    return true
}