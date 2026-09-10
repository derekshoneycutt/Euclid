package terminalview

import "../../core"
import "../../core/protocol"
import termclipboard "../../terminal/clipboard"
import gfxprotocol "../../terminal/graphics/protocol"
import gfxsemantics "../../terminal/graphics/semantics"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"
import termattachment "../../terminal/attachment"
import termhist "../../terminal/history"
import termhyperlink "../../terminal/hyperlink"
import termpalette "../../terminal/palette"
import termshellintegration "../../terminal/shell_integration"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"

import rl "vendor:raylib"

//   Compose the committed scrollback line shown for one accepted input.
//
// Parameters:
//   - text: The line the user typed before pressing Enter.
//
// Returns:
//   - The prompt-prefixed line as stored in scrollback.
terminal_prompt_line :: proc(text: string) -> string {
    return fmt.tprintf("%s%s", TERMINAL_PROMPT, text)
}

// Publish retained editable-text buffers after all arena allocations succeed.
terminal_publish_retained_text :: proc(
    term: ^core.Terminal_State, eval, completion, preview: []u8) {
    term.pending_eval_storage = eval
    term.pending_completion_storage = completion
    term.completion_preview_storage = preview
}

// Allocate and publish all retained editable-text buffers transactionally.
terminal_init_retained_text :: proc(
    term: ^core.Terminal_State, allocator: mem.Allocator) -> bool {
    eval, eval_error := make(
        []u8, protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES, allocator)
    completion, completion_error := make(
        []u8, protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES, allocator)
    preview, preview_error := make(
        []u8, protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES, allocator)
    if eval_error != nil || completion_error != nil || preview_error != nil {
        return false
    }
    terminal_publish_retained_text(term, eval, completion, preview)
    return true
}

// Publish retained display handles after all arena allocations succeed.
terminal_publish_retained_display :: proc(
    term: ^core.Terminal_State, title: ^termemulator.Terminal_Title_State,
    checkpoint: ^termgrid.Display_Checkpoint,
    synchronized: ^termemulator.Synchronized_Output_State,
    attachments: ^termattachment.Store) {
    term.output_interpreter.title_state = title
    term.output_checkpoint = checkpoint
    term.synchronized_output = synchronized
    synchronized.attachments = attachments
}

//   Allocate and publish the terminal's bounded retained-text buffers.
//
// Parameters:
//   - term: Terminal state receiving the allocated buffers.
//   - allocator: Arena allocator that owns every buffer.
//
// Returns:
//   - true if every buffer was allocated and published.
//
// Side effects:
//   - Allocates four fixed retained-storage blocks and publishes them into terminal
//     state only after all allocations succeed.
terminal_init_retained_storage :: proc(
    term: ^core.Terminal_State, allocator: mem.Allocator) -> bool {
    title_storage, title_error := make(
        []termemulator.Terminal_Title_State, 1, allocator)
    checkpoint_storage, checkpoint_error := make(
        []termgrid.Display_Checkpoint, 1, allocator)
    synchronized_storage, synchronized_error := make(
        []termemulator.Synchronized_Output_State, 1, allocator)
    attachment_storage, attachment_error := make([]termattachment.Store, 1, allocator)
    graphics_storage, graphics_error := make(
        []gfxprotocol.Graphics_Parser_State, 1, allocator)
    hyperlink_storage, hyperlink_error := make(
        []termhyperlink.Hyperlink_Registry, 1, allocator)
    clipboard_storage, clipboard_error := make(
        []termclipboard.Clipboard_Action_Queue, 1, allocator)
    shell_storage, shell_error := make(
        []termshellintegration.Shell_Integration_State, 1, allocator)
    if title_error != nil || checkpoint_error != nil || synchronized_error != nil ||
        attachment_error != nil || graphics_error != nil || hyperlink_error != nil ||
        clipboard_error != nil || shell_error != nil ||
        !terminal_init_retained_text(term, allocator) ||
        !termhyperlink.hyperlink_registry_init(&hyperlink_storage[0], allocator) ||
        !termclipboard.clipboard_action_queue_init(&clipboard_storage[0], allocator) ||
        !termshellintegration.shell_integration_init(
            &shell_storage[0], TERMINAL_SCROLLBACK_ROWS, allocator) {
        return false
    }
    title_storage[0].graphics = &graphics_storage[0]
    termpalette.terminal_palette_init(&title_storage[0].palette)
    terminal_publish_retained_display(
        term, &title_storage[0], &checkpoint_storage[0],
        &synchronized_storage[0], &attachment_storage[0])
    term.hyperlink_registry = &hyperlink_storage[0]
    term.clipboard_actions = &clipboard_storage[0]
    term.shell_integration = &shell_storage[0]
    return true
}

//   Establish the fixed baseline geometry before the first visible frame.
//
// Parameters:
//   - term: Terminal state receiving initial dimensions and geometry policy.
//
// Side effects:
//   - Sets generation-one dimensions, configured limits, and zeroed scroll metrics.
terminal_init_geometry :: proc(term: ^core.Terminal_State) {
    term.geometry = {
        dimensions = {columns = TERMINAL_GRID_COLUMNS, rows = TERMINAL_GRID_ROWS},
        generation = 1,
    }
    term.dimension_limits = TERMINAL_DIMENSION_LIMITS
    term.scroll_offset_y = 0
    term.scroll_content_height = 0
}

// Release terminal semantic owners after initialization fails.
terminal_rollback_init :: proc(
    term: ^core.Terminal_State, history: ^termhist.Termhist_State) {
    termhist.termhist_destroy(history)
}

// Build an unpublished terminal candidate and release every partial owner on failure.
terminal_construct_candidate :: proc(
    term: ^core.Terminal_State,
    allocator: mem.Allocator,
    ambiguous_width: termgrid.Ambiguous_Width_Mode) -> bool {
    history := &term.history_storage
    if !termhist.termhist_init_with_allocator(
        history, TERMINAL_INITIAL_TEXT_CAPACITY,
        TERMINAL_INITIAL_HISTORY_CAPACITY, allocator) {
        terminal_rollback_init(term, history)
        return false
    }
    if !terminal_init_retained_storage(term, allocator) {
        terminal_rollback_init(term, history)
        return false
    }

    if !terminal_output_init(
        term, allocator, allocator, ambiguous_width) {
        terminal_rollback_init(term, history)
        return false
    }
    return true
}

// Initialize one terminal model from an explicit owner allocator and generation.
terminal_init_with_allocator :: proc(
    term: ^core.Terminal_State, allocator: mem.Allocator, generation: u64,
    ambiguous_width: termgrid.Ambiguous_Width_Mode = .Narrow) -> bool {
    if term == nil || allocator.procedure == nil || generation == 0 {
        return false
    }
    if term.initialized || term.history != nil {
        return false
    }
    term^ = {allocator = allocator, animation_generation = generation}
    if !terminal_construct_candidate(term, allocator, ambiguous_width) {
        term^ = {}
        return false
    }
    term.history = &term.history_storage
    term.initialized = true
    terminal_init_geometry(term)
    return true
}

// Initialize one production terminal model in the current animation generation.
terminal_init_for_animation :: proc(
    term: ^core.Terminal_State, memory: ^core.Animation_Memory,
    generation: u64,
    ambiguous_width: termgrid.Ambiguous_Width_Mode = .Narrow) -> bool {
    if memory == nil || memory.generation != generation {
        return false
    }
    return terminal_init_with_allocator(
        term, core.animation_memory_allocator(memory), generation, ambiguous_width)
}

//   Allocate test-owned terminal state with the explicitly supplied context allocator.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//
// Returns:
//   - true if the backing term history state was created.
//
// Side effects:
//   - Initializes history, reserves terminal virtual storage, allocates retained buffers
//     and display resources, and rolls back every acquired resource on failure.
terminal_init :: proc(
    term: ^core.Terminal_State,
    ambiguous_width: termgrid.Ambiguous_Width_Mode = .Narrow) -> bool {
    return terminal_init_with_allocator(
        term, context.allocator, 1, ambiguous_width)
}

//   Initialize checkpoint and interpreter state after all display grids exist.
//
// Parameters:
//   - term: Terminal state whose grids and scrollback are already initialized.
//   - allocator: Owner allocator for the fixed-shape display checkpoint.
//
// Returns:
//   - True after checkpoint and interpreter publication; false after local rollback.
//
// Side effects:
//   - Initializes checkpoint storage, binds the interpreter to both grids and retained
//     title state, and enables line-feed column reset compatibility.
terminal_output_init_interpreter :: proc(
    term: ^core.Terminal_State, allocator: mem.Allocator) -> bool {
    if !termgrid.display_checkpoint_init(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback,
        allocator) {
        return false
    }
    if !termgrid.display_checkpoint_init(
        &term.synchronized_output.checkpoint, &term.output_grid,
        &term.output_scrollback, allocator) {
        termgrid.display_checkpoint_destroy(term.output_checkpoint)
        return false
    }
    term.synchronized_output.scrollback = &term.output_scrollback
    term.synchronized_output.output_started = &term.output_started
    title_state := term.output_interpreter.title_state
    if !termemulator.interpreter_init(
        &term.output_interpreter, &term.output_grid, {
            alternate_grid = &term.output_alternate_grid,
            title_state = title_state,
            synchronized_output = term.synchronized_output,
            hyperlink_registry = term.hyperlink_registry,
            clipboard_actions = term.clipboard_actions,
            shell_integration = term.shell_integration,
        }) {
        termgrid.display_checkpoint_destroy(
            &term.synchronized_output.checkpoint)
        termgrid.display_checkpoint_destroy(term.output_checkpoint)
        return false
    }
    term.output_interpreter.line_feed_resets_column = true
    return true
}

// Release primary display resources after output initialization fails.
terminal_output_rollback_primary :: proc(term: ^core.Terminal_State) {
    termgrid.grid_destroy(&term.output_grid)
    termgrid.scrollback_destroy(&term.output_scrollback)
}

// Release both display grids and scrollback after interpreter initialization fails.
terminal_output_rollback_grids :: proc(term: ^core.Terminal_State) {
    termgrid.grid_destroy(&term.output_alternate_grid)
    terminal_output_rollback_primary(term)
}

// Initialize and publish primary scrollback and grid transactionally.
terminal_output_init_primary :: proc(
    term: ^core.Terminal_State, retained_allocator,
    resizable_allocator: mem.Allocator,
    ambiguous_width: termgrid.Ambiguous_Width_Mode) -> bool {
    scrollback: termgrid.Scrollback
    if !termgrid.scrollback_init(
        &scrollback, TERMINAL_MAX_COLUMNS, TERMINAL_SCROLLBACK_ROWS,
        retained_allocator, {
            attachment_store = term.synchronized_output.attachments,
            shell_integration = term.shell_integration,
        }) {
        return false
    }
    grid: termgrid.Grid
    term.output_scrollback = scrollback
    if !termgrid.grid_init(
        &grid, TERMINAL_GRID_COLUMNS, TERMINAL_GRID_ROWS,
        resizable_allocator, {
            scrollback = {
                user_data = &term.output_scrollback,
                commit = termgrid.scrollback_sink_commit,
            },
            ambiguous_width = ambiguous_width,
            attachment_store = term.synchronized_output.attachments,
            screen = .Primary,
        }) {
        termgrid.scrollback_destroy(&term.output_scrollback)
        return false
    }
    term.output_grid = grid
    return true
}

// Initialize attachment storage and graphics framing as one ordered service.
terminal_output_init_attachment_services :: proc(
    term: ^core.Terminal_State,
    retained_allocator, resizable_allocator: mem.Allocator) -> bool {
    attachments := term.synchronized_output.attachments
    if !termattachment.store_init_with_allocators(
        attachments, termattachment.limits_default(),
        retained_allocator, resizable_allocator) {
        return false
    }
    graphics := term.output_interpreter.title_state.graphics
    if !gfxprotocol.graphics_parser_init(graphics, attachments) {
        termattachment.store_destroy(attachments)
        return false
    }
    gfxsemantics.graphics_semantics_enable(graphics)
    return true
}

// Release graphics framing before the attachment store that owns its transfers.
terminal_output_destroy_attachment_services :: proc(term: ^core.Terminal_State) {
    gfxprotocol.graphics_parser_destroy(term.output_interpreter.title_state.graphics)
    termattachment.store_destroy(term.synchronized_output.attachments)
}

//   Transactionally initialize the bounded terminal display model.
//
// Parameters:
//   - term: Terminal state receiving owned display resources.
//   - allocator: Allocator retained independently by grids, scrollback, and checkpoint.
//
// Returns:
//   - True after all display resources and interpreter state are initialized; false
//     after releasing every resource acquired by the failed attempt.
//
// Side effects:
//   - Allocates and publishes scrollback, primary and alternate grids, checkpoint, and
//     interpreter state, with transactional rollback on any failure.
terminal_output_init :: proc(
    term: ^core.Terminal_State, retained_allocator,
    resizable_allocator: mem.Allocator,
    ambiguous_width: termgrid.Ambiguous_Width_Mode) -> bool {

    if !terminal_output_init_attachment_services(
        term, retained_allocator, resizable_allocator) {
        return false
    }
    if !terminal_output_init_primary(
        term, retained_allocator, resizable_allocator, ambiguous_width) {
        terminal_output_destroy_attachment_services(term)
        return false
    }
    if !termgrid.grid_init(
        &term.output_alternate_grid, TERMINAL_GRID_COLUMNS,
        TERMINAL_GRID_ROWS, resizable_allocator,
        {
            ambiguous_width = ambiguous_width,
            attachment_store = term.synchronized_output.attachments,
            screen = .Alternate,
        }) {
        terminal_output_rollback_primary(term)
            terminal_output_destroy_attachment_services(term)
        return false
    }
    if !terminal_output_init_interpreter(term, resizable_allocator) {
        terminal_output_rollback_grids(term)
            terminal_output_destroy_attachment_services(term)
        return false
    }
    return true
}

//   Report bounded terminal parser and grid counters before storage is released.
//
// Parameters:
//   - term: Initialized terminal whose final counters are reported.
//
// Side effects:
//   - Emits one debug or warning log record containing bounded parser, grid, and
//     scrollback diagnostics.
terminal_teardown_has_rejections :: proc(term: ^core.Terminal_State) -> bool {
    interpreter := &term.output_interpreter
    grid := &term.output_grid
    synchronized := term.synchronized_output
    hyperlinks := term.hyperlink_registry
    shell := term.shell_integration
    query := interpreter.title_state
    palette := &interpreter.title_state.palette
        return interpreter.malformed_sequence_count > 0 ||
       interpreter.unsupported_sequence_count > 0 ||
             interpreter.cancelled_sequence_count > 0 ||
       interpreter.overflow_sequence_count > 0 ||
       grid.invalid_utf8_count > 0 || grid.truncated_grapheme_count > 0 ||
             hyperlinks.rejection_count > 0 ||
             hyperlinks.activation_rejection_count > 0 ||
             shell.cwd_rejection_count > 0 || shell.marker_rejection_count > 0 ||
             shell.lifecycle_malformed_count > 0 ||
         palette.color_rejection_count > 0 || palette.query_rejection_count > 0 ||
             query.query_rejection_count > 0 ||
       synchronized.forced_publish_count > 0 ||
             synchronized.capture_failure_count > 0
}

// Report bounded command-index occupancy, malformed lifecycle, and eviction outcomes.
terminal_log_shell_index_teardown :: proc(term: ^core.Terminal_State) {
    shell := term.shell_integration
    log.debugf(
        "terminal shell command_blocks=%d lifecycle_malformed=%d command_evictions=%d",
        termshellintegration.shell_command_block_count(shell),
        shell.lifecycle_malformed_count, shell.command_eviction_count)
}

// Emit warning-level terminal teardown diagnostics with rejection detail.
terminal_log_teardown_rejections :: proc(term: ^core.Terminal_State) {
    interpreter := &term.output_interpreter
    grid := &term.output_grid
    scrollback := &term.output_scrollback
    synchronized := term.synchronized_output
    hyperlinks := term.hyperlink_registry
    shell := term.shell_integration
    query := interpreter.title_state
    palette := &query.palette
    log.warnf(
        "terminal teardown columns=%d rows=%d scrollback_rows=%d malformed_sequences=%d unsupported_sequences=%d cancelled_sequences=%d overflow_sequences=%d invalid_utf8=%d truncated_graphemes=%d hyperlink_accepts=%d hyperlink_rejects=%d hyperlink_activations=%d hyperlink_activation_rejects=%d hyperlink_http=%d hyperlink_https=%d hyperlink_mailto=%d hyperlink_file=%d shell_cwd_accepts=%d shell_cwd_rejects=%d shell_marker_accepts=%d shell_marker_rejects=%d query_accepts=%d query_rejects=%d palette_generation=%d color_accepts=%d color_rejects=%d color_query_accepts=%d color_query_rejects=%d synchronized_begins=%d synchronized_publishes=%d synchronized_forced_publishes=%d synchronized_capture_failures=%d",
        grid.columns, grid.row_count, scrollback.count,
        interpreter.malformed_sequence_count,
        interpreter.unsupported_sequence_count,
        interpreter.cancelled_sequence_count,
        interpreter.overflow_sequence_count, grid.invalid_utf8_count,
        grid.truncated_grapheme_count, hyperlinks.acceptance_count,
        hyperlinks.rejection_count, hyperlinks.activation_count,
        hyperlinks.activation_rejection_count,
        hyperlinks.acceptance_by_scheme[.Http],
        hyperlinks.acceptance_by_scheme[.Https],
        hyperlinks.acceptance_by_scheme[.Mailto],
        hyperlinks.acceptance_by_scheme[.File],
        shell.cwd_acceptance_count, shell.cwd_rejection_count,
        shell.marker_acceptance_count, shell.marker_rejection_count,
        query.query_acceptance_count, query.query_rejection_count,
        palette.generation, palette.color_acceptance_count,
        palette.color_rejection_count, palette.query_acceptance_count,
        palette.query_rejection_count, synchronized.begin_count,
        synchronized.publish_count, synchronized.forced_publish_count,
        synchronized.capture_failure_count)
}

// Emit compact debug-level terminal teardown diagnostics without rejections.
terminal_log_teardown_clean :: proc(term: ^core.Terminal_State) {
    interpreter := &term.output_interpreter
    grid := &term.output_grid
    scrollback := &term.output_scrollback
    synchronized := term.synchronized_output
    hyperlinks := term.hyperlink_registry
    shell := term.shell_integration
    query := interpreter.title_state
    palette := &query.palette
    log.debugf(
        "terminal teardown columns=%d rows=%d scrollback_rows=%d malformed_sequences=0 unsupported_sequences=0 cancelled_sequences=0 overflow_sequences=0 invalid_utf8=0 truncated_graphemes=0 hyperlink_accepts=%d hyperlink_rejects=0 hyperlink_activations=%d hyperlink_activation_rejects=0 shell_cwd_accepts=%d shell_cwd_rejects=0 shell_marker_accepts=%d shell_marker_rejects=0 query_accepts=%d query_rejects=0 palette_generation=%d color_accepts=%d color_rejects=0 color_query_accepts=%d color_query_rejects=0 synchronized_begins=%d synchronized_publishes=%d synchronized_forced_publishes=0 synchronized_capture_failures=0",
        grid.columns, grid.row_count, scrollback.count,
        hyperlinks.acceptance_count, hyperlinks.activation_count,
        shell.cwd_acceptance_count, shell.marker_acceptance_count,
        query.query_acceptance_count, palette.generation,
        palette.color_acceptance_count, palette.query_acceptance_count,
        synchronized.begin_count, synchronized.publish_count)
}

//   Report bounded terminal parser and grid counters before storage is released.
terminal_log_teardown :: proc(term: ^core.Terminal_State) {
    if terminal_teardown_has_rejections(term) {
        terminal_log_teardown_rejections(term)
    } else {
        terminal_log_teardown_clean(term)
    }
}

// Release display models and transfer services in dependency order.
terminal_output_destroy :: proc(term: ^core.Terminal_State) {
    termgrid.grid_destroy(&term.output_grid)
    termgrid.grid_destroy(&term.output_alternate_grid)
    termgrid.scrollback_destroy(&term.output_scrollback)
    termgrid.display_checkpoint_destroy(
        &term.synchronized_output.checkpoint)
    termgrid.display_checkpoint_destroy(term.output_checkpoint)
    terminal_output_destroy_attachment_services(term)
}

//   Release the term history state backing a simulated terminal.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//
// Side effects:
//   - Logs final diagnostics, destroys history and display resources, releases retained
//     source views, destroys the storage arena, and clears published storage handles.
terminal_destroy_semantics :: proc(term: ^core.Terminal_State) {
    if term == nil {
        return
    }

    termemulator.interpreter_publish_synchronized_output(
        &term.output_interpreter, true)
    terminal_log_teardown(term)
    terminal_log_shell_index_teardown(term)
    terminal_log_clipboard_teardown(term)

    if term.history != nil {
        termhist.termhist_destroy(term.history)
        term.history = nil
    }
    terminal_output_destroy(term)
    termhyperlink.hyperlink_registry_destroy(term.hyperlink_registry)
    termclipboard.clipboard_action_queue_destroy(term.clipboard_actions)
    termshellintegration.shell_integration_destroy(term.shell_integration)
    if len(term.pending_eval_source) > 0 {
        term.pending_eval_source = ""
    }
    if len(term.pending_completion_source) > 0 {
        term.pending_completion_source = ""
    }
    terminal_clear_completion_preview(term)
    term.pending_eval_storage = nil
    term.pending_completion_storage = nil
    term.completion_preview_storage = nil
    term.shell_integration = nil
}

// Release semantic terminal owners before the animation owner resets shared memory.
terminal_destroy :: proc(term: ^core.Terminal_State) {
    if term == nil || !term.initialized {
        return
    }
    terminal_destroy_semantics(term)
    term^ = {}
}

// Borrow the last validated local working-directory URI observed through OSC 7.
terminal_observed_cwd_uri :: proc(term: ^core.Terminal_State) -> string {
    if term == nil || term.shell_integration == nil {
        return ""
    }
    state := term.shell_integration
    return string(state.observed_cwd_uri[:state.observed_cwd_uri_byte_count])
}

//   Mark the terminal as waiting for the final event from an evaluation.
//
// Parameters:
//   - term: Terminal state beginning a correlated evaluation; nil is rejected.
//   - source: Submitted source copied into bounded retained storage.
//
// Returns:
//   - True after cloning source and assigning a new request ID; false for nil/allocation failure.
//
// Side effects:
//   - Clears completion state and replaces any prior pending evaluation source.
terminal_begin_eval :: proc(term: ^core.Terminal_State, source: string) -> bool {
    if term == nil {
        return false
    }

    terminal_clear_completion(term)

    if len(source) > len(term.pending_eval_storage) {
        return false
    }
    if len(source) > 0 {
        copy(term.pending_eval_storage[:len(source)], transmute([]u8)source)
    }
    term.pending_eval_source = string(term.pending_eval_storage[:len(source)])
    term.next_eval_request_id += 1
    term.pending_eval_request_id = term.next_eval_request_id
    term.awaiting_eval = true
    term.collecting_continuation = false
    return true
}

//   Mark an evaluation stream complete and restore the live input prompt.
//
// Parameters:
//   - term: Terminal state completing its current evaluation; nil is a no-op.
//
// Side effects:
//   - Forces the primary screen, clears evaluation/checkpoint/completion state, releases
//     pending source ownership, and appends one blank output line.
terminal_complete_eval :: proc(term: ^core.Terminal_State) {
    if term == nil {
        return
    }
    termemulator.interpreter_restore_primary_screen(&term.output_interpreter)
    termemulator.interpreter_finish_input(&term.output_interpreter)
    term.awaiting_eval = false
    term.collecting_continuation = false
    term.output_checkpoint.valid = false
    term.pending_eval_request_id = 0
    terminal_clear_completion(term)
    if len(term.pending_eval_source) > 0 {
        term.pending_eval_source = ""
    }
    terminal_append_output_line(term, "")
}

// Restore the synchronized pre-submission output checkpoint when available.
terminal_restore_output_checkpoint :: proc(term: ^core.Terminal_State) {
    termemulator.interpreter_publish_synchronized_output(
        &term.output_interpreter, true)
    if termgrid.display_checkpoint_restore(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback) {
        term.output_started = term.output_checkpoint_started
    }
}

// Return the indentation prefix of the retained source's final physical line.
terminal_continuation_indent :: proc(source: string) -> string {
    last_line_start := 0
    for byte, index in source {
        if byte == '\n' { last_line_start = index + 1 }
    }
    indent_end := last_line_start
    for indent_end < len(source) &&
        (source[indent_end] == ' ' || source[indent_end] == '\t') {
        indent_end += 1
    }
    return source[last_line_start:indent_end]
}

//   Restore an editable continuation prompt while retaining incomplete source.
//
// Notes:
//   - Restores the pre-submission display checkpoint so an incomplete attempt does not
//     remain committed, then rebuilds editable input and carries last-line indentation.
//
// Parameters:
//   - term: Terminal state returning incomplete source to its editor; nil is a no-op.
//
// Side effects:
//   - Clears request/completion state, transfers pending source back through termhist,
//     releases the owned source copy, and enters continuation collection.
terminal_continue_eval :: proc(term: ^core.Terminal_State) {
    if term == nil || term.history == nil {
        return
    }

    terminal_restore_output_checkpoint(term)
    term.pending_eval_request_id = 0
    source := term.pending_eval_source
    termhist.termhist_clear(term.history)
    if !termhist.termhist_insert_text(term.history, source) {
        return
    }

    termhist.termhist_insert_text(term.history, "\n")
    termhist.termhist_insert_text(term.history, terminal_continuation_indent(source))
    if len(term.pending_eval_source) > 0 {
        term.pending_eval_source = ""
    }
    term.awaiting_eval = false
    term.collecting_continuation = true
    terminal_clear_completion(term)
}

//   Return the source submitted for the current live line.
//
// Notes:
//   - Continuation text is already rebuilt into termhist by `terminal_continue_eval`;
//     this hook intentionally returns the supplied line unchanged.
//
// Parameters:
//   - term: Terminal state associated with the submission; currently unused.
//   - line: Borrowed live-line source supplied by the caller.
//
// Returns:
//   - The supplied line unchanged.
terminal_eval_source :: proc(term: ^core.Terminal_State, line: string) -> string {
    return line
}

//   Return whether the terminal should expose its live input prompt.
//
// Parameters:
//   - term: Terminal state to inspect; nil is not prompt-visible.
//
// Returns:
//   - True after the banner is ready and while no evaluation is pending.
terminal_prompt_visible :: proc(term: ^core.Terminal_State) -> bool {
    return term != nil && term.banner_ready && !term.awaiting_eval
}

//   Return the primary, continuation, help, or pkg prefix for the live input line.
//
// Parameters:
//   - term: Terminal state selecting prompt mode; nil uses the normal Julia prompt.
//
// Returns:
//   - Continuation prefix while collecting incomplete input; otherwise the active mode prompt.
terminal_prompt_prefix :: proc(term: ^core.Terminal_State) -> string {
    if term != nil && term.collecting_continuation {
        return TERMINAL_CONTINUATION_PROMPT
    }
    if term != nil && term.input_mode == .Pkg {
        return TERMINAL_PKG_PROMPT
    }
    if term != nil && term.input_mode == .Help {
        return TERMINAL_HELP_PROMPT
    }
    if term != nil && term.input_mode == .Shell {
        return TERMINAL_SHELL_PROMPT
    }
    return TERMINAL_PROMPT
}

//   Return the mode-specific primary prefix for the first editable row.
//
// Notes:
//   - Unlike `terminal_prompt_prefix`, continuation collection does not replace row zero.
//
// Parameters:
//   - term: Terminal state selecting prompt mode; nil uses the normal Julia prompt.
//
// Returns:
//   - The active mode's primary prompt prefix.
terminal_primary_prompt_prefix :: proc(term: ^core.Terminal_State) -> string {
    if term != nil && term.input_mode == .Pkg {
        return TERMINAL_PKG_PROMPT
    }
    if term != nil && term.input_mode == .Help {
        return TERMINAL_HELP_PROMPT
    }
    if term != nil && term.input_mode == .Shell {
        return TERMINAL_SHELL_PROMPT
    }
    return TERMINAL_PROMPT
}

//   Return the terminal's active prompt/evaluation mode.
//
// Parameters:
//   - term: Terminal state to inspect; nil defaults to normal mode.
//
// Returns:
//   - The active evaluation mode, or Normal for nil state.
terminal_input_mode :: proc(term: ^core.Terminal_State) -> protocol.Evaluation_Mode {
    if term == nil {
        return .Normal
    }
    return term.input_mode
}

//   Return whether the terminal is currently in Julia's `?` help mode.
//
// Parameters:
//   - term: Terminal state to inspect; nil is never in help mode.
//
// Returns:
//   - True only while the active evaluation mode is Help.
terminal_is_help_mode :: proc(term: ^core.Terminal_State) -> bool {
    return term != nil && term.input_mode == .Help
}

//   Return whether the terminal is currently in Julia's `]` pkg mode.
//
// Parameters:
//   - term: Terminal state to inspect; nil is never in package mode.
//
// Returns:
//   - True only while the active evaluation mode is Pkg.
terminal_is_pkg_mode :: proc(term: ^core.Terminal_State) -> bool {
    return term != nil && term.input_mode == .Pkg
}

//   Leave Julia's `?` help mode, restoring the standard `julia>` prompt.
//
// Notes:
//   - Real Julia REPL help mode is single-shot: submitting a help query
//     returns to the standard prompt immediately, before its output shows.
//   - Pkg mode is sticky and is never exited by this helper.
//
// Parameters:
//   - term: Terminal state whose single-shot help mode may be active; nil is a no-op.
//
// Side effects:
//   - Restores Normal mode only when Help is currently active.
terminal_exit_help_mode :: proc(term: ^core.Terminal_State) {
    if term != nil && term.input_mode == .Help {
        term.input_mode = .Normal
    }
}

//   Cancel active package mode and restore the standard Julia prompt.
//
// Parameters:
//   - term: Terminal state whose package mode may be active; nil is rejected.
//
// Returns:
//   - True after leaving package mode; false when package mode is not active.
//
// Side effects:
//   - Clears editable input and completion state.
terminal_cancel_pkg_mode :: proc(term: ^core.Terminal_State) -> bool {
    if term == nil || term.input_mode != .Pkg {
        return false
    }
    term.input_mode = .Normal
    if term.history != nil {
        termhist.termhist_clear(term.history)
    }
    terminal_clear_completion(term)
    return true
}

//   Render Julia's own startup banner and unblock the live input prompt.
//
// Notes:
//   - Input stays blocked (see `terminal_prompt_visible`) until this runs, so
//     the prompt and banner only appear once Julia is actually ready and has
//     reported its real running version.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - text: The ANSI-colored banner text sourced from `REPL.banner`.
//
// Side effects:
//   - Appends the banner as styled output runs via termhist.
terminal_display_banner :: proc(term: ^core.Terminal_State, text: string) {
    if term == nil || term.history == nil {
        return
    }

    terminal_append_ansi_output(term, text)
    term.banner_ready = true
}

//   Poll keyboard and mouse input for the active frame and apply it to the terminal.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled keyboard and mouse state.
//   - font: The monospace font used for hit-testing mouse selection.
//   - bounds: The rectangle the terminal is drawn within, matching terminal_draw.
//
// Returns:
//   - Submission and completion request details for this frame.
//
// Side effects:
//   - Mutates the live input line, cursor, and committed scrollback via termhist.
//   - Mutates the mouse-driven view selection and may write to the clipboard.
terminal_update :: proc(
    term: ^core.Terminal_State,
    request: Terminal_Update_Request) -> Terminal_Frame_Update {
    if term == nil || term.history == nil {
        return {}
    }

    terminal_update_synchronized_output(term, request.now)
    geometry_change: Terminal_Geometry_Change
    if request.update_geometry {
        geometry_change = terminal_update_geometry(
            term, request.font, request.bounds)
    }
    keyboard := terminal_update_keyboard(term, request.frame)
    if keyboard.cursor_moved {
        term.view_selection_active = false
        term.view_selection_dragging = false
        if !keyboard.completion.requested {
            terminal_clear_completion(term)
            terminal_schedule_completion(term, request.now)
        }
    }

    hyperlink_activation := terminal_update_hyperlink_click(
        term, request.frame, request.bounds)
    terminal_update_mouse_selection(
        term, request.frame, request.font, request.bounds)
    terminal_update_clipboard_copy(term, request.frame)
    completion := keyboard.completion
    if !completion.requested {
        completion = terminal_take_scheduled_completion(term, request.now)
    }
    return {
        submission = keyboard.submission,
        completion = completion,
        geometry_change = geometry_change,
        hyperlink_activation = hyperlink_activation,
    }
}

//   Commit the live input line to scrollback and return its text for the
//   caller to send for evaluation.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//
// Returns:
//   - The submitted line's text, borrowed from termhist storage (valid
//     for the rest of this frame).
//
// Side effects:
//   - Appends a bold prompt run plus the committed input line, then clears
//     the live line via termhist. Does not append any output line; the
//     caller appends the real evaluated result once it arrives.
terminal_submit :: proc(term: ^core.Terminal_State) -> string {
    text := termhist.termhist_current_text(term.history)
    if term.collecting_continuation {
        terminal_restore_output_checkpoint(term)
    } else {
        term.output_checkpoint_started = term.output_started
        termgrid.display_checkpoint_capture(
            term.output_checkpoint, &term.output_grid, &term.output_scrollback)
    }

    prompt_style := termhist.Termhist_Text_Style{
        color_rgba = terminal_palette_rgba(
            terminal_prompt_palette_color(term.input_mode)),
        is_bold = true,
    }
    history_tag := terminal_history_tag_for_mode(term.input_mode)

    terminal_append_submitted_input(term, text, prompt_style)
    termhist.termhist_accept_current(
        term.history, history_tag, term.collecting_continuation)
    return text
}

// Append one submitted physical row with its prompt and input styles.
terminal_append_submitted_line :: proc(
    term: ^core.Terminal_State, prefix, line: string,
    prompt_style, input_style: termgrid.Cell_Style) {
    termgrid.grid_set_style(&term.output_grid, prompt_style)
    termgrid.grid_write(&term.output_grid, prefix)
    termgrid.grid_set_style(&term.output_grid, input_style)
    termgrid.grid_write(&term.output_grid, line)
    termgrid.grid_write(&term.output_grid, "\r\n")
    term.output_started = true
}

//   Commit submitted source into the output grid one physical row at a time.
//
// Parameters:
//   - term: Terminal whose active output grid receives the submission.
//   - text: Unprefixed source, possibly containing embedded newlines.
//   - prompt_style: Style used for primary and continuation prefixes.
//
// Side effects:
//   - Writes mode-aware first prefix, continuation prefixes, default-color source cells, and
//     CRLF row endings; restores the prior grid style before return.
terminal_append_submitted_input :: proc(
    term: ^core.Terminal_State, text: string,
    prompt_style: termhist.Termhist_Text_Style) {
    saved_style := term.output_grid.style
    prompt_cell_style := termgrid.Cell_Style{
        foreground = termpalette.terminal_color_direct(prompt_style.color_rgba),
        bold = prompt_style.is_bold,
    }
    input_cell_style := termgrid.Cell_Style{}
    remaining := text
    first_line := true
    for {
        newline_index := strings.index_byte(remaining, '\n')
        line := remaining
        if newline_index >= 0 {
            line = remaining[:newline_index]
        }
        prefix := TERMINAL_CONTINUATION_PROMPT
        if first_line {
            prefix = terminal_primary_prompt_prefix(term)
            first_line = false
        }
        terminal_append_submitted_line(
            term, prefix, line, prompt_cell_style, input_cell_style)
        if newline_index < 0 {
            termgrid.grid_set_style(&term.output_grid, saved_style)
            return
        }
        remaining = remaining[newline_index + 1:]
    }
}

//   Map the active prompt mode to its bold prompt run color.
//
// Parameters:
//   - mode: Evaluation mode whose semantic palette entry is requested.
//
// Returns:
//   - The terminal palette color assigned to that prompt mode.
terminal_prompt_palette_color :: proc(
    mode: protocol.Evaluation_Mode) -> Terminal_Color {
    switch mode {
    case .Pkg:
        return .Blue
    case .Help:
        return .Yellow
    case .Shell:
        return .Red
    case .Normal:
        return .Green
    }
    return .Green
}

//   Map the active prompt mode to its live prompt draw color.
//
// Parameters:
//   - mode: Evaluation mode whose Raylib draw color is requested.
//
// Returns:
//   - The configured prompt color assigned to that mode.
terminal_prompt_draw_color :: proc(mode: protocol.Evaluation_Mode) -> rl.Color {
    switch mode {
    case .Pkg:
        return TERMINAL_PKG_PROMPT_COLOR
    case .Help:
        return TERMINAL_HELP_PROMPT_COLOR
    case .Shell:
        return TERMINAL_SHELL_PROMPT_COLOR
    case .Normal:
        return TERMINAL_PROMPT_COLOR
    }
    return TERMINAL_PROMPT_COLOR
}
