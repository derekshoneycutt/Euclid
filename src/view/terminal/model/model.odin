package viewterminalmodel

import protocol "../../../core/protocol"
import "../../../taskpool"
import termattachment "../../../terminal/attachment"
import termclipboard "../../../terminal/clipboard"
import termemulator "../../../terminal/emulator"
import termgrid "../../../terminal/grid"
import termhist "../../../terminal/history"
import termhyperlink "../../../terminal/hyperlink"
import termmodel "../../../terminal/model"
import termsession "../../../terminal/session"
import termshellintegration "../../../terminal/shell_integration"

import "base:runtime"

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
Terminal_State :: struct {
    animation_generation: u64,
    allocator: runtime.Allocator,
    initialized: bool,
    history_storage: termhist.Termhist_State,
    history: ^termhist.Termhist_State,
    output_grid: termgrid.Grid,
    output_alternate_grid: termgrid.Grid,
    output_scrollback: termgrid.Scrollback,
    output_interpreter: termemulator.Interpreter,
    hyperlink_registry: ^termhyperlink.Hyperlink_Registry,
    clipboard_actions: ^termclipboard.Clipboard_Action_Queue,
    shell_integration: ^termshellintegration.Shell_Integration_State,
    raster_renderer: termattachment.Raster_Renderer,
    output_producer: termmodel.Terminal_Producer,
    geometry: protocol.Terminal_Geometry,
    julia_geometry_generation: u64,
    dimension_limits: protocol.Terminal_Dimension_Limits,
    rejected_geometry_count: u64,
    output_checkpoint: ^termgrid.Display_Checkpoint,
    synchronized_output: ^termemulator.Synchronized_Output_State,
    scroll_offset_y: f32,
    scroll_content_height: f32,
    view_selection_anchor: Terminal_View_Position,
    view_selection_head: Terminal_View_Position,
    hyperlink_pressed: termmodel.Hyperlink_Handle,
    banner_ready: bool,
    julia_session_ready: bool,
    julia_session_start_sent: bool,
    awaiting_eval: bool,
    collecting_continuation: bool,
    input_mode: protocol.Evaluation_Mode,
    input_mode_backup: protocol.Evaluation_Mode,
    output_checkpoint_started: bool,
    output_started: bool,
    julia_capabilities_observed: bool,
    view_selection_active: bool,
    view_selection_dragging: bool,
    completion_result_received: bool,
    completion_request_scheduled: bool,
    pending_eval_storage: []u8,
    pending_eval_source: string,
    next_eval_request_id: protocol.Request_Id,
    pending_eval_request_id: protocol.Request_Id,
    interactive_input_request_id: protocol.Request_Id,
    interactive_input_dropped_event_count: u64,
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
}

// Shell_Runtime owns the native shell service and one bounded foreground transaction.
Shell_Runtime :: struct {
    backend: termsession.Native_Terminal_Backend,
    session: termsession.Terminal_Session_Manager,
    phase: Shell_Launch_Phase,
    request_id: protocol.Request_Id,
    operation_id: termsession.Terminal_Session_Operation_Id,
    working_directory: [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    working_directory_byte_count: int,
    terminfo_directory: [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    terminfo_directory_byte_count: int,
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