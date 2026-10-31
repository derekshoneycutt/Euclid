package viewterminalmodel

import protocol "../../../core/protocol"
import "../../../taskpool"
import termattachment "../../../terminal/attachment"
import termclipboard "../../../terminal/clipboard"
import termemulator "../../../terminal/emulator"
import termgrid "../../../terminal/grid"
import termhist "../../../terminal/history"
import termhiststore "../../../persistence/userdata/history"
import termhistsearch "../../../terminal/history/search"
import historyruntime "../../../terminal/history/runtime"
import termhyperlink "../../../terminal/hyperlink"
import termmodel "../../../terminal/model"
import termsession "../../../terminal/session"
import termshellintegration "../../../terminal/shell_integration"

SHELL_SESSION_OWNER_ID :: u64(1)
SHELL_TERMINFO_NAME :: "euclid"
SHELL_TERMINFO_RELATIVE_DIRECTORY :: "assets/terminfo"

// Terminal_View_Position identifies one rendered cell by line and byte offset.
Terminal_View_Position :: struct {
    line: int,
    byte_offset: int,
}

// Terminal_Graphics_Lifecycle_Proc releases display-owned graphics session resources.
Terminal_Graphics_Lifecycle_Proc :: proc(
    user_data: rawptr, pool: ^taskpool.Task_Pool)

// Terminal_State owns the display-thread terminal runtime for one animation generation.
// Keep its address stable after initialization: history and interpreter bindings point
// into embedded fields. Retire graphics-worker borrowers and destroy Terminal resources
// and source aliases before the animation owner resets the generation arena.
Terminal_State :: struct {
    // Generation and initialization.
    animation_generation: u64,
    initialized: bool,

    // Editor and asynchronous history-navigation state.
    history_storage: termhist.Termhist_State,
    history: ^termhist.Termhist_State,
    input_mode: protocol.Evaluation_Mode,
    input_mode_backup: protocol.Evaluation_Mode,
    collecting_continuation: bool,
    provisional_submission_id: u64,
    provisional_persistent_entry_id: u64,
    provisional_desired_revision: u64,
    provisional_committed_revision: u64,
    provisional_recording_valid: bool,
    history_persistence_notified: bool,
    history_unavailable_notified: bool,
    history_navigation_epoch: u64,
    history_navigation_anchor_id: u64,
    history_navigation_cursor: termhiststore.History_Browse_Cursor,
    history_navigation_cursor_valid: bool,
    history_navigation_request_id: u64,
    history_source_request_id: u64,
    history_navigation_pending_id: u64,
    history_navigation_admission_reported: bool,
    history_source_admission_reported: bool,
    history_write_completion_serial: u64,
    history_navigation_intents: [8]int,
    history_navigation_intent_count: int,
    history_navigation_active: bool,
    history_navigation_draft_mode: protocol.Evaluation_Mode,
    history_navigation_read_source: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8,
    history_explorer: History_Explorer_State,
    history_explorer_open_allowed: bool,

    // Output grids and interpretation. Interpreter bindings borrow these embedded grids;
    // checkpoints and service pointers below refer to generation-allocated storage.
    output_grid: termgrid.Grid,
    output_alternate_grid: termgrid.Grid,
    output_scrollback: termgrid.Scrollback,
    output_interpreter: termemulator.Interpreter,
    clipboard_actions: ^termclipboard.Clipboard_Action_Queue,
    shell_integration: ^termshellintegration.Shell_Integration_State,
    raster_renderer: termattachment.Raster_Renderer,
    output_producer: termmodel.Terminal_Producer,
    output_checkpoint: ^termgrid.Display_Checkpoint,
    // Also borrows output_scrollback and output_started within this state.
    synchronized_output: ^termemulator.Synchronized_Output_State,
    output_checkpoint_started: bool,
    output_started: bool,

    // Geometry and scrolling.
    geometry: protocol.Terminal_Geometry,
    text_size_percent: int,
    julia_geometry_generation: u64,
    dimension_limits: protocol.Terminal_Dimension_Limits,
    rejected_geometry_count: u64,
    scroll_offset_y: f32,
    scroll_content_height: f32,

    // Pointer selection and links. The interpreter borrows the generation-owned registry.
    view_selection_anchor: Terminal_View_Position,
    view_selection_head: Terminal_View_Position,
    view_selection_active: bool,
    view_selection_dragging: bool,
    draft_selection_dragging: bool,
    hyperlink_registry: ^termhyperlink.Hyperlink_Registry,
    hyperlink_pressed: termmodel.Hyperlink_Handle,

    // Evaluation/session state. Source borrows the used prefix of pending_eval_storage.
    banner_ready: bool,
    julia_session_ready: bool,
    julia_session_start_sent: bool,
    awaiting_eval: bool,
    julia_capabilities_observed: bool,
    pending_eval_storage: []u8,
    pending_eval_source: string,
    pending_draft: termhist.Termhist_Snapshot,
    pending_draft_valid: bool,
    next_eval_request_id: protocol.Request_Id,
    pending_eval_request_id: protocol.Request_Id,
    interactive_input_request_id: protocol.Request_Id,
    interactive_input_dropped_event_count: u64,

    // Completion. Source and insertion borrow used prefixes of their respective
    // generation-owned storage slices, never returned bridge-message storage.
    completion_result_received: bool,
    completion_request_scheduled: bool,
    next_completion_request_id: protocol.Request_Id,
    pending_completion_request_id: protocol.Request_Id,
    pending_completion_cursor: int,
    pending_completion_storage: []u8,
    pending_completion_source: string,
    completion_request_due: f64,
    completion_preview_start: int,
    completion_preview_end: int,
    completion_preview_storage: []u8,
    completion_preview_insertion: string,

    // Highlighting. Generation allocation released with the explicit lifecycle allocator.
    highlighting: ^Terminal_Highlighting,
}

// History_Explorer_Status describes the current bounded query/page result state.
History_Explorer_Status :: enum u8 {
    Closed,
    Searching,
    Ready,
    Empty,
    Unavailable,
    Failed,
    Capacity,
}

// History_Explorer_Preview_Status distinguishes current candidate source readiness.
History_Explorer_Preview_Status :: enum u8 {
    Idle,
    Loading,
    Ready,
    Failed,
    Capacity,
}

// History_Explorer_Page_Direction records which chronological boundary is being scanned.
History_Explorer_Page_Direction :: enum u8 {
    None,
    Older,
    Newer,
}

// Help overlays the existing page; no second source or candidate owner is created.
History_Explorer_Help :: enum u8 {
    None,
    Short,
    Extended,
}

// History_Explorer_State owns one bounded transient query and one candidate page.
// Its variable-sized buffers are allocated and released with the Terminal generation.
History_Explorer_State :: struct {
    query_editor: termhist.Termhist_State,
    rows: []termhiststore.History_Candidate_Summary,
    row_ranges: [termhistsearch.HISTORY_SEARCH_RANGE_MAX]termhistsearch.Search_Range,
    summaries: []u8,
    preview_source: []u8,
    initialized: bool,
    active: bool,
    close_requested: bool,
    accept_requested: bool,
    query_dirty: bool,
    search_pending: bool,
    preview_pending: bool,
    opening_generation: u64,
    query_generation: u64,
    identity: historyruntime.History_Explorer_Identity,
    next_search_request_id: u64,
    next_preview_request_id: u64,
    search_request_id: u64,
    preview_request_id: u64,
    status: History_Explorer_Status,
    preview_status: History_Explorer_Preview_Status,
    row_count: int,
    selected_index: int,
    preview_record: termhiststore.History_Record,
    preview_matches: termhiststore.History_Match_Ranges,
    preview_length: int,
    search_direction: History_Explorer_Page_Direction,
    search_cursor: termhiststore.History_Browse_Cursor,
    search_cursor_valid: bool,
    page_older_cursor: termhiststore.History_Browse_Cursor,
    page_older_cursor_valid: bool,
    page_newer_cursor: termhiststore.History_Browse_Cursor,
    page_newer_cursor_valid: bool,
    older_available: bool,
    newer_available: bool,
    page_request: History_Explorer_Page_Direction,
    list_scroll_rows: int,
    list_visible_selection: int,
    query_pointer_selecting: bool,
    preview_scroll_lines: int,
    status_failure: termhiststore.History_Store_Error,
    skipped_regex_count: int,
    help: History_Explorer_Help,
    help_scroll_lines: int,
    saved_query: [termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES]u8,
    saved_query_length: int,
    saved_query_cursor: int,
    saved_query_anchor: int,
}

// Terminal_Tick_Publisher owns one generation-scoped bounded tick stream.
Terminal_Tick_Publisher :: struct {
    animation_generation: u64,
    stream_generation: u64,
    interval_steps: u64,
    next_sequence: u64,
    accumulated_steps: u64,
    accumulated_first_tick: u64,
    accumulated_last_tick: u64,
    acknowledgement: protocol.Tick_Stream_Configuration_Acknowledged,
    pulse: protocol.Tick_Pulse,
    active: bool,
    acknowledgement_pending: bool,
    pulse_pending: bool,
}

// Shell_Launch_Phase tracks one foreground shell submission.
Shell_Launch_Phase :: enum u8 {
    Inactive,
    Running,
    Closing,
}

// Shell_Runtime owns the native shell service and one bounded foreground transaction.
Shell_Runtime :: struct {
    backend: termsession.Native_Terminal_Backend,
    session: termsession.Terminal_Session_Manager,
    cleanup: termsession.Process_Cleanup_Registry,
    close: termsession.Terminal_Process_Close_Coordinator,
    phase: Shell_Launch_Phase,
    request_id: protocol.Request_Id,
    operation_id: termsession.Terminal_Session_Operation_Id,
    working_directory: [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    working_directory_byte_count: int,
    terminfo_directory: [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    terminfo_directory_byte_count: int,
}

// Report whether one bounded shell close no longer owns an active backend operation.
shell_runtime_close_finished :: proc(runtime: ^Shell_Runtime) -> bool {
    if runtime == nil {
        return true
    }
    return runtime.close.phase == .Complete || runtime.close.phase == .Transferred
}

// Begin bounded close for the current shell generation without blocking its owner.
shell_runtime_close_begin :: proc(runtime: ^Shell_Runtime, now_ns: u64) -> bool {
    if runtime == nil {
        return false
    }
    if runtime.phase == .Closing || shell_runtime_close_finished(runtime) {
        return true
    }
    generation := runtime.session.owner.generation
    if generation == 0 {
        runtime.close.phase = .Complete
        runtime.phase = .Inactive
        return true
    }
    begun := termsession.terminal_process_close_begin(
        &runtime.close, &runtime.session, &runtime.cleanup, {
            generation = generation,
            now_ns = now_ns,
            graceful_ns = termsession.TERMINAL_PROCESS_CLOSE_GRACE_NS,
            final_ns = termsession.TERMINAL_PROCESS_CLOSE_FINAL_NS,
        })
    if !begun {
        return false
    }
    runtime.phase = .Inactive if shell_runtime_close_finished(runtime) else .Closing
    return true
}

// shell_working_directory returns the absolute cwd snapshot owned by the shell runtime.
shell_working_directory :: proc(runtime: ^Shell_Runtime) -> string {
    if runtime == nil || runtime.working_directory_byte_count <= 0 ||
       runtime.working_directory_byte_count > len(runtime.working_directory) {
        return ""
    }
    return string(runtime.working_directory[:runtime.working_directory_byte_count])
}

// shell_terminfo_directory returns the packaged terminfo directory captured at startup.
shell_terminfo_directory :: proc(runtime: ^Shell_Runtime) -> string {
    if runtime == nil || runtime.terminfo_directory_byte_count <= 0 {
        return ""
    }
    return string(runtime.terminfo_directory[:runtime.terminfo_directory_byte_count])
}