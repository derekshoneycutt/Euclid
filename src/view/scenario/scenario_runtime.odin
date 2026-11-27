package viewscenario

import animation_model "../../core/animation"
import bridgemodel "../../bridge/model"
import presentation_model "../../bridge/presentation"
import particlemodel "../../particles/model"
import particles "../../particles"
import storage "../../core/storage"
import julia "../../bridge/host"
import evidence_allocation "../../evidence/allocation"
import artifact "../../evidence/artifact"
import capture "../../evidence/capture"
import scenario "../../evidence/scenario"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import input "../input"
import setting_model "../../settings"
import ui "../ui"
import utf8 "core:unicode/utf8"
import log "core:log"
import os "core:os"
import strings "core:strings"
import time "core:time"
import viewcapture "../capture"
import viewmodel "../ui/model"
import builderui "../ui/builder"
import uisemantics "../ui/semantics"
import buildermodel "../../animation/builder"
import core "../../core"
import viewevidence "../evidence"
import libraryservice "../ui/library/service"
import uiterminal "../ui/terminal"
import uipresentation "../ui/presentation"
import viewpresentation "../presentation"
import uisplitter "../ui/layout/splitter"
import uilibrary "../ui/library"
import uisettings "../ui/settings"
import terminalview "../terminal"
import terminalservice "../terminal/service"
import termhyperlink "../../terminal/hyperlink"
import termmodel "../../terminal/model"
import capturemodel "../capture/model"
import geometry "../../core/geometry"
import uianimation "../ui/animation"
import viewsharing "../sharing"
import exerciseheader "../../core/exercise_header"
import math "core:math"

// Allow only subpixel-scale float error from board-coordinate projection.
SCENARIO_BUILDER_POSITION_TOLERANCE :: f32(0.00001)

// Deferred display mutation applied before the next frame's UI geometry is prepared.
Scenario_Ui_Mutation_Kind :: enum u8 {
    None,
    View_Scroll,
    Splitters,
}

Scenario_Ui_Mutation :: struct {
    kind: Scenario_Ui_Mutation_Kind,
    value: f32,
    secondary_value: f32,
}

// Display-owned coordinator connecting the generic runner to Euclid actions.
Scenario_Runtime :: struct {
    runner: scenario.Runner,
    capture: capture.Coordinator,
    state: ^core.Euclid_General_State,
    input_runtime: ^input.Input_Runtime,
    // Session-owned presentation runtime borrowed for the current update only.
    presentation: ^viewpresentation.Presentation_Runtime,
    framebuffer_operations: capturemodel.Framebuffer_Capture_Operations,
    next_action_id: u64,
    presented_frame: u64,
    shutdown_requested: bool,
    terminal_recorded: bool,
    terminal_reason: artifact.Reason,
    pending_ui_mutation: Scenario_Ui_Mutation,
    pointer_override: bool,
    pointer_position: geometry.Vector2,
    pointer_down: bool,
    pointer_pressed: bool,
    pointer_released: bool,
    pointer_wheel_delta: f32,
    favorites_memory: Scenario_Favorites_Memory,
    reorder_sample_active: bool,
    reorder_sample_time: f64,
    reorder_sample_floor: f64,
    reorder_frame_time: f64,
    pending_reorder_command: viewmodel.Ui_Focus_Command,
    native_memory: storage.Tlsf_Owner_Diagnostics,
    native_control_count: int,
    native_text_bytes: int,
    native_toolkit_updates: u64,
    native_toolkit_nodes: u64,
}

// Resolved owner-domain identity and its synchronized arena diagnostics.
Scenario_Arena_Sample :: struct {
    kind: evidence_allocation.Arena_Domain_Kind,
    snapshot: evidence_allocation.Arena_Snapshot,
}

// Stable scenario spelling paired with one portable input key.
Scenario_Key_Name :: struct {name: string, key: input.Input_Key}

// Supported deterministic portable keys.
SCENARIO_KEY_NAMES :: [?]Scenario_Key_Name{
    {"a", .A}, {"c", .C}, {"r", .R}, {"s", .S}, {"z", .Z},
    {"escape", .Escape}, {"enter", .Enter}, {"space", .Space}, {"tab", .Tab},
    {"backspace", .Backspace}, {"delete", .Delete},
    {"left", .Left}, {"right", .Right}, {"up", .Up}, {"down", .Down},
    {"home", .Home}, {"end", .End}, {"page_up", .Page_Up},
    {"page_down", .Page_Down},
    {"f10", .F10}, {"menu", .Menu},
}

//   Load and validate one bounded JSONL scenario before runtime execution.
scenario_runtime_load_file :: proc(
    runtime: ^Scenario_Runtime, state: ^core.Euclid_General_State,
    path: string) -> bool {
    if runtime == nil || state == nil || len(path) == 0 {
        return false
    }
    source, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil {
        log.error("scenario_load_failed reason=read")
        return false
    }
    program: scenario.Program
    parse_error := scenario.parse(string(source), &program)
    if parse_error != .None {
        log.errorf("scenario_load_failed reason=parse error=%d", int(parse_error))
        return false
    }
    scenario_runtime_init(runtime, state, program)
    return true
}

//   Initialize one display-owned runtime from a validated fixed program.
scenario_runtime_init :: proc(
    runtime: ^Scenario_Runtime, state: ^core.Euclid_General_State,
    program: scenario.Program) {
    runtime^ = {
        state = state,
        next_action_id = 1,
    }
    scenario.runner_init(&runtime.runner, program)
    log.infof("scenario_started command_count=%d", program.count)
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Scenario,
            kind = .Scenario_Started,
            flags = {.Required},
        })
}

//   Emit one operational record for a terminal scenario outcome.
scenario_runtime_log_terminal :: proc(
    runtime: ^Scenario_Runtime, status: scenario.Run_Status) {
    switch status {
    case .Passed:
        log.infof(
            "scenario_passed step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Failed:
        log.errorf(
            "scenario_failed step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Inconclusive:
        log.warnf(
            "scenario_inconclusive step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Ready, .Running:
    }
}

//   Record one terminal scenario outcome and its stable failure reason.
scenario_runtime_record_terminal :: proc(
    runtime: ^Scenario_Runtime, status: scenario.Run_Status) {
    if runtime.terminal_recorded ||
        (status != .Passed && status != .Failed && status != .Inconclusive) {
        return
    }
    kind := evidence_trace.Kind.Scenario_Passed
    flags: evidence_trace.Flags = {.Required}
    if status == .Failed {
        kind = .Scenario_Failed
        flags += {.Failure}
        if runtime.terminal_reason == .None &&
            runtime.runner.step < runtime.runner.program.count {
            command_kind := runtime.runner.program.commands[runtime.runner.step].kind
            runtime.terminal_reason = command_kind == .Wait_Event ||
                command_kind == .Wait_State ? .Wait_Timeout : .Assertion_Failed
        }
    } else if status == .Inconclusive {
        kind = .Scenario_Inconclusive
        flags += {.Failure}
        runtime.terminal_reason = .Required_Evidence_Lost
    }
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Scenario,
            kind = kind,
            correlation_kind = .Scenario_Action,
            correlation = u64(runtime.runner.step),
            flags = flags,
        })
    scenario_runtime_log_terminal(runtime, status)
    runtime.terminal_recorded = true
}

// Advance the display scenario using its owner's current monotonic clock.
scenario_runtime_update_current :: proc(
    runtime: ^Scenario_Runtime,
    input_runtime: ^input.Input_Runtime,
    presentation: ^viewpresentation.Presentation_Runtime = nil) -> scenario.Run_Status {
    return scenario_runtime_update(
        runtime, u64(i64(time.tick_since({}))), input_runtime, presentation)
}

// Advance a scenario using an explicit monotonic timestamp for deterministic tests.
// The optional presentation runtime is display-owned and borrowed only for this call.
scenario_runtime_update :: proc(
    runtime: ^Scenario_Runtime, now_ns: u64,
    input_runtime: ^input.Input_Runtime = nil,
    presentation: ^viewpresentation.Presentation_Runtime = nil) -> scenario.Run_Status {
    if runtime == nil || runtime.state == nil {
        return .Failed
    }
    state := runtime.state
    runtime.input_runtime = input_runtime
    runtime.presentation = presentation
    defer runtime.presentation = nil
    status := scenario.runner_update(&runtime.runner, {
        now_ns = now_ns,
        events = state.evidence_session.events[:state.evidence_session.event_count],
        display = viewevidence.observe_display_state(
            state, viewpresentation.presentation_effects_observe(presentation)),
        actions = {
            user_data = rawptr(runtime),
            issue = scenario_runtime_issue,
        },
    })
    if runtime.capture.checkpoint.status == .Pending && status == .Passed {
        runtime.runner.status = .Running
        return .Running
    }
    if runtime.capture.checkpoint.status == .Failed {
        runtime.runner.status = .Failed
        runtime.terminal_reason = .Capture_Failed
        status = .Failed
    }
    scenario_runtime_record_terminal(runtime, status)
    return status
}

// Report whether the Terminal can admit local or foreground-session input.
scenario_terminal_input_available :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || !state^.terminal.initialized ||
        !state^.terminal.julia_session_ready {
        return false
    }
    return !state^.terminal.awaiting_eval || state^.shell.phase == .Running ||
        state^.terminal.interactive_input_request_id != 0
}

// Inject one complete UTF-8 text action into ordinary next-frame input.
scenario_issue_terminal_text :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if runtime == nil || runtime.input_runtime == nil ||
        !scenario_terminal_input_available(runtime.state) {
        return false
    }
    return scenario_inject_text_events(runtime, text)
}

// Inject text only while the visible Favorites name editor owns input focus.
scenario_issue_library_name_text :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if runtime == nil || runtime.state == nil || runtime.input_runtime == nil {
        return false
    }
    ui := &runtime.state^.ui_runtime
    draft := &ui^.library.entry_name
    if !scenario_favorites_name_editor_focused(&runtime.state^.ui_runtime) {
        log.errorf(
            "scenario_library_name_text_rejected_focus active=%v selected=%v drawer_open=%v",
            draft^.active,
            ui^.library.tree.selected_item_id == draft^.entry_id,
            ui^.library.actions.drawer.open)
        return false
    }
    return scenario_inject_text_events(runtime, text)
}

// Inject note text only while its placement-qualified editor owns keyboard focus.
scenario_issue_collection_note_text :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if runtime == nil || runtime.state == nil || runtime.input_runtime == nil {
        return false
    }
    ui := &runtime.state^.ui_runtime
    note := &ui^.library.collection_note
    focus := ui^.input.interaction_frame.effective_focus
    if note^.status != .Ready || !note^.editing ||
        focus.kind != .Input_Box ||
        focus.id != viewmodel.LIBRARY_COLLECTION_NOTE_INPUT_ID {
        log.error("scenario_collection_note_text_rejected_focus")
        return false
    }
    return scenario_inject_text_events(runtime, text)
}

// Convert one bounded UTF-8 payload to ordinary next-frame text events.
scenario_inject_text_events :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    events: [scenario.SCENARIO_TEXT_CAPACITY]input.Input_Event
    count := 0
    offset := 0
    for offset < len(text) {
        codepoint, width := utf8.decode_rune(text[offset:])
        if width == 0 || count >= len(events) {
            return false
        }
        events[count] = {
            kind = .Text,
            codepoint = codepoint,
        }
        count += 1
        offset += width
    }
    return input.input_runtime_inject_events(
        runtime.input_runtime, events[:count])
}

// Inject one supported portable key into ordinary next-frame input.
scenario_issue_key :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> bool {
    if runtime == nil || runtime.input_runtime == nil || command == nil {
        return false
    }
    name := scenario.text_string(&command.text)
    modifiers: input.Input_Modifiers
    if command.key_shift {
        modifiers += {.Shift}
    }
    if command.key_control {
        modifiers += {.Control}
    }
    for entry in SCENARIO_KEY_NAMES {
        if entry.name == name {
            event: input.Input_Event = {
                kind = .Press,
                key = entry.key,
                modifiers = modifiers,
            }
            return input.input_runtime_inject_events(
                runtime.input_runtime, []input.Input_Event{event})
        }
    }
    return false
}

// Report whether retained Terminal cells contain one requested text fragment.
scenario_terminal_contains :: proc(
    state: ^core.Euclid_General_State, text: string) -> bool {
    for row in 0 ..< uiterminal.terminal_line_count(&state.terminal) {
        if strings.contains(uiterminal.terminal_line_text(&state.terminal, row), text) {
            return true
        }
    }
    return false
}

//   Fulfill pending capture work after the display has presented a complete frame.
scenario_runtime_after_present :: proc(
    runtime: ^Scenario_Runtime, sink: capture.Sink) -> capture.Checkpoint_Status {
    if runtime == nil || runtime.state == nil {
        return .Idle
    }
    runtime.presented_frame += 1
    status := capture.checkpoint_after_present(
        &runtime.capture, runtime.presented_frame, runtime.state.fixed_step, sink)
    if status == .Completed || status == .Failed {
        checkpoint := runtime.capture.checkpoint
        flags: evidence_trace.Flags = {.Required}
        if status == .Failed {
            flags += {.Failure}
        }
        _ = evidence_session.session_record(
            &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
                lane = .Presentation,
                kind = status == .Completed ? .Capture_Completed : .Capture_Failed,
                correlation_kind = checkpoint.trigger.kind,
                correlation = checkpoint.trigger.id,
                generation = checkpoint.trigger.generation,
                tick = checkpoint.fixed_step,
                revision = checkpoint.presented_frame,
                flags = flags,
            })
    }
    if status == .Failed {
        runtime.runner.failure_count += 1
        runtime.runner.status = .Failed
    }
    return status
}

//   Arm one validated scenario-only failure for the next runtime reload.
scenario_arm_reload_failure :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command) -> bool {
    if state.julia_runtime_service == nil {
        return false
    }
    injection := scenario.text_string(&command.text)
    switch injection {
    case "candidate_load":
        state.julia_runtime_service.reload_failure_injection = .Candidate_Load
    case "animation_enter":
        state.julia_runtime_service.reload_failure_injection = .Animation_Enter
    case:
        return false
    }
    return true
}

//   Select one named animation and retain its next generation identity.
scenario_select_animation :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> bool {
    selected := scenario_find_animation(
        state.julia_interface, scenario.text_string(&command.text))
    if selected == nil || !julia.select_animation_programmatically(state, selected) {
        return false
    }
    identity.kind = .Animation
    identity.id = state.julia_runtime_service.animation_generation + 1
    identity.generation = identity.id
    return true
}

//   Submit one scenario presentation override through the Julia-owner ingress path.
scenario_issue_view_content :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> bool {
    service := state.julia_runtime_service
    if service == nil || state.julia_interface == nil {
        return false
    }
    mime := presentation_model.Presentation_Mime.Text_Plain
    if command.view_content_mime == .Text_Latex {
        mime = .Text_Latex
    }
    outcome := julia.send_scenario_view_content(service, {
        origin = identity^,
        request_id = service.active_request_id,
        runtime_generation = service.runtime_generation,
        animation_generation = service.animation_generation,
        animation = state.julia_interface.current_animation,
        mime = mime,
        source = transmute([]u8)scenario.text_string(&command.text),
    })
    return outcome == .Sent
}

//   Route one animation or Julia-service command through its ordinary owner API.
scenario_issue_julia_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    state := runtime.state
    #partial switch command.kind {
    case .Reset_Animation:
        state.julia_interface.pending_animation_reset = true
        return true, true
    case .Select_Animation:
        return true, scenario_select_animation(state, command, identity)
    case .Reload_Runtime:
        if state.julia_runtime_service == nil {
            return true, false
        }
        service := state.julia_runtime_service
        service.reload_requested = true
        identity.kind = .Runtime_Request
        identity.id = service.runtime_generation + 1
        identity.generation = identity.id
        return true, true
    case .Inject_Reload_Failure:
        return true, scenario_arm_reload_failure(state, command)
    case .Set_View_Content:
        return true, scenario_issue_view_content(state, command, identity)
    case:
        return false, false
    }
}

//   Store a display checkpoint and publish its retained evidence identity.
scenario_issue_checkpoint_action :: proc(
    state: ^core.Euclid_General_State,
    identity: ^evidence_trace.Identity) -> bool {
    handle := viewevidence.record_evidence_checkpoint(state, true)
    if handle.generation == 0 {
        return false
    }
    identity.kind = .Checkpoint
    identity.id = state.fixed_step
    identity.generation = u64(handle.generation)
    return true
}

//   Queue one validated viewport mutation for the next pre-geometry frame boundary.
scenario_issue_viewport_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    if command.kind != .Set_View_Scroll && command.kind != .Set_Splitters {
        return false, false
    }
    if runtime.pending_ui_mutation.kind != .None {
        return true, false
    }
    if command.kind == .Set_View_Scroll {
        if !uipresentation.presentation_scroll_is_available(runtime.state) {
            return true, false
        }
        runtime.pending_ui_mutation = {.View_Scroll, command.value, 0}
        return true, true
    }
    if !uisplitter.splitter_positions_are_mutable(
        capturemodel.gif_capture_view(&runtime.state.gif_capture_status)) {
        return true, false
    }
    runtime.pending_ui_mutation = {
        .Splitters, command.value, command.secondary_value}
    return true, true
}

//   Apply one display-owned simulation or animation policy command.
scenario_issue_simulation_policy_action :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command) -> (bool, bool) {
    #partial switch command.kind {
    case .Pause_Simulation:
        state.ui_runtime.playback.simulation_paused = true
    case .Resume_Simulation:
        state.ui_runtime.playback.simulation_paused = false
    case .Pause_Animation:
        state.ui_runtime.playback.animation_policy_paused = true
    case .Resume_Animation:
        state.ui_runtime.playback.animation_policy_paused = false
    case:
        return false, false
    }
    return true, true
}

// Route transport actions through the same admission path as pointer and keyboard input.
scenario_issue_transport_action :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    playback := &state^.ui_runtime.playback
    #partial switch command.kind {
    case .Pause_Construction, .Resume_Construction:
        paused := command.kind == .Pause_Construction
        if playback^.construction_paused != paused {
            uianimation.apply_animation_control_hit(state, {
                toggle_pause_requested = true,
            })
        }
    case .Show_Completed:
        if !playback^.construction_paused || playback^.completed ||
            playback^.completion_requested {
            return true, false
        }
        uianimation.apply_animation_control_hit(state, {
            cycle_speed_requested = true,
        })
        identity^ = {.Animation_Tick,
            state^.julia_runtime_service^.animation_tick_sequence + 1,
            state^.julia_runtime_service^.animation_generation}
        return true, playback^.completion_requested
    case:
        return false, false
    }
    return true, true
}

// Route one scenario search action through the display-owned search model.
scenario_issue_library_search_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    search := &runtime.state^.ui_runtime.library.search
    #partial switch command.kind {
    case .Set_Library_Search:
        query := scenario.text_string(&command.text)
        if len(query) == 0 || len(query) > len(search^.query) {
            return true, false
        }
        copy(search^.query[:len(query)], query)
        search^.query_length = len(query)
        viewmodel.library_search_query_changed(search, 0, true)
        search^.input.cursor_byte = search^.query_length
        search^.input.anchor_byte = search^.query_length
        search^.submit_requested = true
    case .Apply_Library_Search_Suggestion:
        if search^.suggestion_length == 0 {
            return true, false
        }
        uilibrary.library_search_apply_suggestion(search)
    case .Clear_Library_Search:
        uilibrary.library_search_clear_query(search)
    case:
        return false, false
    }
    search^.scenario_correlation = identity^.id
    search^.scenario_correlation_generation = identity^.generation
    if command.kind == .Clear_Library_Search {
        libraryservice.library_search_record_clear_commit(runtime.state)
    }
    return true, true
}

//   Route one screenshot or GIF command through display-owned capture state.
scenario_issue_capture_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    #partial switch command.kind {
    case .Request_Screenshot:
        if !capture.checkpoint_request(
            &runtime.capture, u32(runtime.runner.step), identity^,
            scenario.text_string(&command.text)) {
            return true, false
        }
        identity.kind = .Capture
    case .Start_Gif, .Stop_Gif:
        runtime.state.gif_capture_status.save_gif_requested = true
        identity.kind = .Capture
    case:
        return false, false
    }
    return true, true
}

//   Route one display or capture command through display-owned state.
scenario_issue_display_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    state := runtime.state
    if handled, accepted := scenario_issue_transport_action(state, command, identity);
       handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_favorites_action(runtime, command); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_settings_action(state, command); handled {
        return handled, accepted
    }

    if handled, accepted := scenario_issue_viewport_action(runtime, command); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_simulation_policy_action(
        state, command); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_capture_action(
        runtime, command, identity); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_library_search_action(
        runtime, command, identity); handled {
        return handled, accepted
    }
    return scenario_issue_owner_action(runtime, command, identity)
}

// Route display-owned header actions, presentation overrides, checkpoints, and shutdown.
scenario_issue_owner_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    if handled, accepted := scenario_issue_exercise_header_action(
        runtime, command); handled {
        return handled, accepted
    }
    #partial switch command.kind {
    case .Set_Arrival_Style:
        return true, scenario_issue_arrival_style_action(runtime, command)
    case .Checkpoint:
        return true, scenario_issue_checkpoint_action(runtime.state, identity)
    case .Shutdown:
        runtime.shutdown_requested = true
        return true, true
    case:
        return false, false
    }
}

// Route bounded exercise-header scenario operations through display-owned state.
scenario_issue_exercise_header_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    #partial switch command.kind {
    case .Set_Exercise_Header:
        return true, scenario_set_exercise_header(runtime, command)
    case .Hide_Exercise_Header:
        return true, scenario_hide_exercise_header(runtime.state)
    case .Expand_Exercise_Header:
        return true, scenario_expand_exercise_header(runtime.state)
    case .Set_Exercise_Header_Scroll:
        return true, scenario_set_exercise_header_scroll(runtime.state, command.value)
    case .Assert_Exercise_Header:
        return true, scenario_assert_exercise_header(runtime.state, command)
    case:
        return false, false
    }
}

// Replace the visible header after invalidating earlier queued producer updates.
scenario_set_exercise_header :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> bool {
    state := runtime.state
    if service := state^.julia_runtime_service; service != nil {
        bridgemodel.exercise_header_invalidate_requests(
            &service^.exercise_header_request_sequence,
            &state^.exercise_header.last_request_id)
    }
    return exerciseheader.show(
        &state^.exercise_header,
        transmute([]u8)scenario.text_string(&command.text))
}

// Hide the header and invalidate all producer requests issued before the hide.
scenario_hide_exercise_header :: proc(state: ^core.Euclid_General_State) -> bool {
    if service := state^.julia_runtime_service; service != nil {
        bridgemodel.exercise_header_invalidate_requests(
            &service^.exercise_header_request_sequence,
            &state^.exercise_header.last_request_id)
    }
    exerciseheader.hide(&state^.exercise_header)
    return true
}

// Expand the visible exercise header for bounded lifecycle scenarios.
scenario_expand_exercise_header :: proc(state: ^core.Euclid_General_State) -> bool {
    header := &state^.exercise_header
    if !header^.visible {
        return false
    }
    header^.expanded = true
    return true
}

// Inject a bounded retained offset that the next prepared viewport must clamp.
scenario_set_exercise_header_scroll :: proc(
    state: ^core.Euclid_General_State, scroll_y: f32) -> bool {
    header := &state^.exercise_header
    if !header^.visible || !header^.expanded {
        return false
    }
    header^.scroll_y = scroll_y
    return true
}

// Compare the visible header's exact bounded source with one scenario assertion.
scenario_assert_exercise_header :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command) -> bool {
    header := &state^.exercise_header
    text := scenario.text_string(&command.text)
    return header^.visible && string(header^.text[:header^.count]) == text
}

// Apply a debug arrival-style override through the borrowed presentation owner.
// The action is rejected when no presentation runtime is bound to this update.
scenario_issue_arrival_style_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> bool {
    if runtime.presentation == nil {
        return false
    }
    viewpresentation.presentation_set_arrival_style(
        runtime.presentation, command.arrival_style)
    return true
}

// Route typed setting edits through control policy and assertions through preference intent.
scenario_issue_settings_action :: proc(
    state: ^core.Euclid_General_State, command: ^scenario.Command) -> (bool, bool) {
    if command.kind == .Set_Setting {
        return true, uisettings.settings_apply_control_edit(
            state, command.setting_id, command.setting_value)
    }
    if command.kind == .Assert_Setting {
        actual := setting_model.setting_value(
            state^.ui_runtime.preferences.values, command.setting_id)
        return true, actual == command.setting_value
    }
    return false, false
}

// Exercise the real two-activation Settings policy and wait for its joined outcome.
scenario_confirm_terminal_history_delete :: proc(
    runtime: ^Scenario_Runtime, outcome: string) -> bool {
    if runtime == nil || runtime.state == nil {
        return false
    }
    panel := &runtime.state^.ui_runtime.settings_panel
    if panel^.history_delete_status == .Idle ||
       panel^.history_delete_status == .Armed {
        uisettings.settings_history_delete_activate(runtime.state, 1)
        uisettings.settings_history_delete_activate(runtime.state, 1.1)
    }
    expected: viewmodel.Ui_History_Delete_Status
    if outcome == "cleared" {
        expected = .Cleared
    } else {
        expected = .Failed
    }
    return panel^.history_delete_status == expected
}

// Wait until launch-owned history writes and reads have joined their worker task.
scenario_terminal_history_idle :: proc(runtime: ^Scenario_Runtime) -> bool {
    if runtime == nil || runtime.state == nil {
        return false
    }
    history := &runtime.state^.terminal_history_runtime
    return history^.status == .Ready && !history^.task_active &&
        history^.mutation_count == 0 && history^.interactive_read_count == 0 &&
        history^.speculative_read_count == 0 && !history^.read_result_ready
}

//   Consume one accepted viewport mutation before authoritative UI geometry is built.
scenario_runtime_apply_pending_ui :: proc(runtime: ^Scenario_Runtime) -> bool {
    if runtime == nil || runtime.state == nil {
        return false
    }
    mutation := runtime.pending_ui_mutation
    runtime.pending_ui_mutation = {}
    applied := true
    #partial switch mutation.kind {
    case .None:
        return true
    case .View_Scroll:
        applied = uipresentation.set_presentation_scroll_position(
            runtime.state, mutation.value)
    case .Splitters:
        applied = uisplitter.set_splitter_positions(
            &runtime.state.ui_runtime.layout,
            &runtime.state.ui_runtime.input.press_owner,
            mutation.value, mutation.secondary_value,
            capturemodel.gif_capture_view(&runtime.state.gif_capture_status))
    }
    if !applied {
        runtime.runner.failure_count += 1
        runtime.runner.status = .Failed
        runtime.terminal_reason = .Assertion_Failed
    }
    return applied
}

//   Evaluate one allocation-domain scenario command.
scenario_arena_snapshot :: proc(
    state: ^core.Euclid_General_State,
    kind: evidence_allocation.Arena_Domain_Kind) -> evidence_allocation.Arena_Snapshot {

    snapshot: evidence_allocation.Arena_Snapshot
    #partial switch kind {
    case .Animation:
        scenario_add_arena_diagnostics(&snapshot,
            animation_model.animation_memory_diagnostics(&state^.animation_memory))
    case .Snapshot_Slots:
        for &slot in state^.julia_runtime_service^.view_snapshots {
            scenario_add_arena_diagnostics(
                &snapshot, storage.arena_owner_diagnostics(&slot.arena))
        }
    case .Display_Cache:
        scenario_add_arena_diagnostics(&snapshot,
            storage.arena_owner_diagnostics(&state^.dynview.cache_arena))
    case .Sharing_Exchange:
        arena := viewsharing.exchange_runtime_arena(state)
        if arena == nil {
            log.error("sharing_exchange_allocation_state_unavailable")
        } else {
            scenario_add_arena_diagnostics(
                &snapshot, storage.arena_owner_diagnostics(arena))
            snapshot.initialized_count = max(snapshot.initialized_count, 1)
        }
    }
    return snapshot
}

//   Aggregate one owner diagnostic into a fixed scenario arena sample.
scenario_add_arena_diagnostics :: proc(
    snapshot: ^evidence_allocation.Arena_Snapshot,
    diagnostics: storage.Arena_Owner_Diagnostics) {

    if diagnostics.initialized {
        snapshot^.initialized_count += 1
    }
    snapshot^.current_used += diagnostics.current_used
    snapshot^.current_reserved += diagnostics.current_reserved
    snapshot^.current_committed += diagnostics.current_committed
    snapshot^.peak_used += diagnostics.peak_used
    snapshot^.peak_reserved += diagnostics.peak_reserved
    snapshot^.peak_committed += diagnostics.peak_committed
    snapshot^.reset_count += diagnostics.reset_count
}

//   Resolve and sample one named arena domain at the display synchronization point.
scenario_arena_domain_sample :: proc(
    state: ^core.Euclid_General_State,
    name: string) -> (Scenario_Arena_Sample, bool) {

    kind, valid := evidence_allocation.arena_domain_kind(name)
    if !valid || state == nil || state^.julia_runtime_service == nil {
        return {}, false
    }
    return {
        kind = kind,
        snapshot = scenario_arena_snapshot(state, kind),
    }, true
}

//   Evaluate one allocation-domain scenario command.
scenario_issue_allocation_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    state := runtime.state
    sample, valid := scenario_arena_domain_sample(
        state, scenario.text_string(&command.text))
    if command.kind != .Assert_No_Bad_Frees && !valid {
        return true, false
    }
    #partial switch command.kind {
    case .Allocation_Checkpoint:
        accepted := evidence_allocation.arena_checkpoint(
            &state.evidence_arena_baselines, sample.kind, sample.snapshot)
        if accepted {
            scenario_record_allocation_evidence(
                runtime, .Allocation_Checkpoint, sample.kind)
        }
        return true, accepted
    case .Assert_Allocation_Baseline:
        accepted := evidence_allocation.arena_matches_baseline(
            &state.evidence_arena_baselines, sample.kind, sample.snapshot)
        scenario_record_allocation_evidence(runtime,
            accepted ? .Allocation_Baseline_Matched :
                .Allocation_Baseline_Mismatched, sample.kind)
        return true, accepted
    case .Assert_No_Bad_Frees:
        return true, evidence_allocation.domain_has_no_bad_frees(
            state.evidence_allocations)
    case:
        return false, false
    }
}

//   Record the outcome of one named arena checkpoint operation.
scenario_record_allocation_evidence :: proc(
    runtime: ^Scenario_Runtime, event_kind: evidence_trace.Kind,
    domain_kind: evidence_allocation.Arena_Domain_Kind) {

    flags: evidence_trace.Flags = {.Required}
    if event_kind == .Allocation_Baseline_Mismatched {
        flags += {.Failure}
    }
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Domain,
            kind = event_kind,
            correlation_kind = .Scenario_Action,
            correlation = runtime.next_action_id - 1,
            generation = 1,
            flags = flags,
            payload = {
                counts = {
                    first = u32(domain_kind),
                },
            },
        })
}

// Queue one validated deterministic dust emission for the particle worker.
scenario_queue_dust_emission :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> bool {
    executor := runtime.state^.simulation_executor
    particle_system := &runtime.state^.particle_system
    if executor == nil ||
        command.dust_count > u32(particle_system^.use_max_dust_particles) {
        return false
    }
    queue := &executor^.particle_task.dust_emission_queue
    if queue^.count >= particlemodel.SCENARIO_DUST_EMISSION_REQUEST_CAP {
        return false
    }
    queue^.items[queue^.count] = {
        distribution = particlemodel.Dust_Emission_Distribution(
            command.dust_distribution),
        count = command.dust_count,
        x = command.value,
        y = command.secondary_value,
        radius = command.tertiary_value,
        seed = command.dust_seed,
        correlation = identity.id,
        generation = identity.generation,
    }
    queue^.count += 1
    return true
}

// Queue one bounded scenario dust request for the next particle step.
scenario_issue_particle_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    executor := runtime.state^.simulation_executor
    particle_system := &runtime.state^.particle_system
    #partial switch command.kind {
    case .Contact_Dust:
        accepted := particles.queue_dust_tool_contact(
            particle_system, {
                endpoint = {command.value, command.secondary_value, 0},
                source = .Scenario,
            })
        return true, accepted
    case .Kick_Dust:
        if executor == nil ||
            executor^.particle_task.scenario_dust_kick_requested {
            return true, false
        }
        executor^.particle_task.scenario_dust_kick_requested = true
        return true, true
    case .Emit_Dust:
        return true, scenario_queue_dust_emission(runtime, command, identity)
    case:
        return false, false
    }
}

// Route one Terminal text, Library name text, or key injection command.
scenario_issue_input_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    text: string) -> (bool, bool) {
    #partial switch command.kind {
    case .Type_Text:
        return true, scenario_issue_terminal_text(runtime, text)
    case .Type_Library_Name:
        return true, scenario_issue_library_name_text(runtime, text)
    case .Type_Collection_Note:
        return true, scenario_issue_collection_note_text(runtime, text)
    case .Key:
        return true, scenario_issue_key(runtime, command)
    case:
        return false, false
    }
}

// Report the actual focused identity when a stable scenario focus assertion fails.
scenario_focus_matches :: proc(runtime: ^Scenario_Runtime, name: string) -> bool {
    focus := runtime^.state^.ui_runtime.semantic_focus
    if focus == nil {
        log.debugf("scenario_focus_mismatch expected=%s semantic_focus_unavailable", name)
        return false
    }
    accepted := ui.semantic_focus_matches_name(focus, name)
    if !accepted {
        log.debugf("scenario_focus_mismatch expected=%s logical=%v effective=%v",
            name, focus^.logical_focus,
            runtime^.state^.ui_runtime.input.interaction_frame.effective_focus)
    }
    return accepted
}

// Route one generic scenario command through ordinary Euclid request state and APIs.
scenario_issue_generic_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    if handled, accepted := scenario_issue_builder_action(runtime, command); handled {
        return handled, accepted
    }
    text := scenario.text_string(&command.text)
    if handled, accepted := scenario_issue_input_action(
        runtime, command, text); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_terminal_action(
        runtime, command.kind, text); handled {
        return handled, accepted
    }
    #partial switch command.kind {
    case .Assert_Focus:
        return true, scenario_focus_matches(runtime, text)
    case .Assert_Library_Search:
        search := &runtime.state^.ui_runtime.library.search
        return true, string(search^.query[:search^.query_length]) == text
    case .Assert_Terminal_Editor:
        return true, scenario_terminal_editor_matches(runtime, command)
    case:
    }
    return scenario_issue_remaining_action(runtime, command, identity)
}

// Route remaining worker, Julia-host, display, or allocation scenario actions.
scenario_issue_remaining_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    if handled, accepted := scenario_issue_particle_action(
        runtime, command, identity); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_julia_action(
        runtime, command, identity); handled {
        return handled, accepted
    }
    if handled, accepted := scenario_issue_display_action(
        runtime, command, identity); handled {
        return handled, accepted
    }
    return scenario_issue_allocation_action(runtime, command)
}

// Route Builder controls and observations through the ordinary display input owner.
scenario_issue_builder_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    #partial switch command.kind {
    case .Builder_Pointer:
        return true, scenario_issue_builder_pointer(
            runtime, command.builder_pointer)
    case .Builder_Control:
        return true, scenario_issue_builder_control(runtime, command.builder_control)
    case .Wait_Builder, .Assert_Builder:
        return true, scenario_builder_observation_matches(
            runtime.state, command.builder_observation)
    case:
        return false, false
    }
}

// Apply one Builder pointer sample through the display's ordinary input frame.
scenario_issue_builder_pointer :: proc(
    runtime: ^Scenario_Runtime,
    request: scenario.Builder_Pointer_Request) -> bool {
    runtime.pointer_override = true
    runtime.pointer_position = {request.position[0], request.position[1]}
    runtime.pointer_wheel_delta = 0
    runtime.pointer_pressed = false
    runtime.pointer_released = false
    switch request.action {
    case .Hover:
        runtime.pointer_down = false
    case .Press:
        runtime.pointer_down = true
        runtime.pointer_pressed = true
    case .Hold:
        runtime.pointer_down = true
    case .Release:
        runtime.pointer_down = false
        runtime.pointer_released = true
    case .Wheel_Up:
        runtime.pointer_wheel_delta = 1
    case .Wheel_Down:
        runtime.pointer_wheel_delta = -1
    }
    return true
}

// Enqueue one accessible Builder action against the stable semantic control identity.
scenario_issue_builder_control :: proc(
    runtime: ^Scenario_Runtime, request: scenario.Builder_Control_Request) -> bool {
    if runtime == nil || runtime.state == nil ||
        !builderui.is_builder_selected(runtime.state) {
        return false
    }
    control_id := scenario_builder_control_id(request.control)
    action, numeric_value := scenario_builder_focus_action(request.action)
    accepted := uisemantics.semantic_apply_external_action(
        runtime.state.ui_runtime.semantic_focus,
        uisemantics.semantic_control_id(.Builder, control_id),
        action, numeric_value)
    if !accepted {
        log.warnf("scenario_builder_control_rejected control=%d focused=%v",
            int(request.control),
            runtime.state.ui_runtime.semantic_focus.window_focused)
    }
    return accepted
}

// Resolve a Builder toolbar action to its stable focus contract ID.
scenario_builder_control_id :: proc(
    control: scenario.Builder_Control) -> int {
    control_id := int(builderui.BUILDER_SURFACE_SEMANTIC_ID)
    switch control {
    case .Tool:
        control_id = builderui.BUILDER_TOOL_BUTTON_ID
    case .Select:
        control_id = builderui.BUILDER_SELECT_BUTTON_ID
    case .Palette0, .Palette1, .Palette2, .Palette3:
        control_id = builderui.BUILDER_PALETTE_BUTTON_BASE_ID +
            int(control) - int(scenario.Builder_Control.Palette0)
    case .Brush:
        control_id = builderui.BUILDER_BRUSH_SLIDER_ID
    case .Hide:
        control_id = builderui.BUILDER_HIDE_BUTTON_ID
    case .Show:
        control_id = builderui.BUILDER_SHOW_BUTTON_ID
    case .Surface:
        control_id = builderui.BUILDER_SURFACE_SEMANTIC_ID
    }
    return control_id
}

// Resolve a Builder action to its focus operation and numeric adjustment.
scenario_builder_focus_action :: proc(
    requested: scenario.Builder_Control_Action) ->
    (viewmodel.Ui_Focus_Command_Kind, f64) {
    action := viewmodel.Ui_Focus_Command_Kind.Focus
    numeric_value: f64
    switch requested {
    case .Focus:
        action = .Focus
    case .Activate:
        action = .Activate
    case .Increment:
        action = .Increment
    case .Decrement:
        action = .Decrement
    case .Scroll_Up:
        action = .Scroll_Page
        numeric_value = 1
    case .Scroll_Down:
        action = .Scroll_Page
        numeric_value = -1
    }
    return action, numeric_value
}

// Compare requested generation-qualified Builder state at the display owner boundary.
scenario_builder_observation_matches :: proc(
    state: ^core.Euclid_General_State,
    expected: scenario.Builder_Observation) -> bool {
    if state == nil {
        return false
    }
    builder := &state^.builder
    if builder^.generation != expected.generation ||
        builder^.point_count != expected.point_count ||
        builder^.job_count != expected.queue_count ||
        builder^.selected_point.id != expected.selected_point_id ||
        builder^.failed != expected.failed {
        return false
    }
    if expected.phase_present &&
        scenario_builder_phase(builder^.placement_phase) != expected.phase {
        return false
    }
    if expected.status_present &&
        scenario_builder_status(builder^.placement_status) != expected.status {
        return false
    }
    if expected.tool_present &&
        scenario_builder_tool(builder^.tool) != expected.tool {
        return false
    }
    if expected.point_present &&
        !scenario_builder_point_matches(builder, expected.point) {
        return false
    }
    if expected.queue_head_present &&
        !scenario_builder_queue_head_matches(builder, expected.queue_head) {
        return false
    }
    return true
}

// Translate native placement phases into the bounded scenario vocabulary.
scenario_builder_phase :: proc(
    value: buildermodel.Placement_Phase) -> scenario.Builder_Placement_Phase {
    switch value {
    case .Idle:
        return .Idle
    case .Hover:
        return .Hover
    case .Held:
        return .Held
    case .Waiting:
        return .Waiting
    }
    return .Idle
}

// Translate native placement outcomes into the bounded scenario vocabulary.
scenario_builder_status :: proc(
    value: buildermodel.Placement_Status) -> scenario.Builder_Placement_Status {
    switch value {
    case .Ready:
        return .Ready
    case .Point_Queued:
        return .Point_Queued
    case .Queue_Full:
        return .Queue_Full
    case .Point_Capacity_Full:
        return .Point_Capacity_Full
    case .Failed:
        return .Failed
    }
    return .Failed
}

// Translate the native tool selection into the bounded scenario vocabulary.
scenario_builder_tool :: proc(
    value: buildermodel.Tool_Mode) -> scenario.Builder_Tool_Mode {
    switch value {
    case .None:
        return .None
    case .Point:
        return .Point
    }
    return .None
}

// Compare one exact point record without exposing its slot as public identity.
scenario_builder_point_matches :: proc(
    builder: ^buildermodel.Runtime,
    expected: scenario.Builder_Point_Observation) -> bool {
    for index in 0..<builder^.point_count {
        point := &builder^.points[index]
        if point^.identity.id != expected.id ||
            point^.identity.generation != builder^.generation {
            continue
        }
        if scenario_builder_point_state(point^.state) != expected.state ||
            math.abs(point^.position.x - expected.position[0]) >
                SCENARIO_BUILDER_POSITION_TOLERANCE ||
            math.abs(point^.position.y - expected.position[1]) >
                SCENARIO_BUILDER_POSITION_TOLERANCE ||
            math.abs(point^.position.z - expected.position[2]) >
                SCENARIO_BUILDER_POSITION_TOLERANCE ||
            point^.brush_size != expected.brush_size ||
            point^.visible != expected.visible {
            return false
        }
        for color_index in 0..<4 {
            if point^.color[color_index] != expected.color[color_index] {
                return false
            }
        }
        return true
    }
    return false
}

// Compare the FIFO head by its generation-qualified command and point identity.
scenario_builder_queue_head_matches :: proc(
    builder: ^buildermodel.Runtime,
    expected: scenario.Builder_Queue_Observation) -> bool {
    if builder^.job_count == 0 {
        return false
    }
    job := builder^.jobs[builder^.job_head]
    return job.identity.generation == builder^.generation &&
        job.identity.id == expected.command_id &&
        job.point.generation == builder^.generation &&
        job.point.id == expected.point_id &&
        scenario_builder_queue_kind(job.kind) == expected.kind
}

// Convert a native Builder point state to the bounded scenario vocabulary.
scenario_builder_point_state :: proc(
    value: buildermodel.Point_State) -> scenario.Builder_Point_State {
    switch value {
    case .Pending:
        return .Pending
    case .Constructing:
        return .Constructing
    case .Ready:
        return .Ready
    case .Failed:
        return .Failed
    }
    return .Failed
}

// Convert one native FIFO kind to its bounded scenario spelling.
scenario_builder_queue_kind :: proc(
    value: buildermodel.Job_Kind) -> scenario.Builder_Queue_Kind {
    switch value {
    case .Construct_Point:
        return .Construct
    case .Edit_Point_Style:
        return .Edit_Style
    case .Hide_Point:
        return .Hide
    case .Show_Point:
        return .Show
    case .Move_Point:
        return .Move
    }
    return .Construct
}

// Route Terminal assertions and confirmed history deletion through their owners.
scenario_issue_terminal_action :: proc(
    runtime: ^Scenario_Runtime, kind: scenario.Command_Kind,
    text: string) -> (bool, bool) {
    #partial switch kind {
    case .Activate_Terminal_Link:
        return true, scenario_activate_terminal_link(runtime, text)
    case .Wait_Terminal_Contains, .Assert_Terminal_Contains:
        return true, scenario_terminal_contains(runtime.state, text)
    case .Wait_Terminal_History_Idle:
        return true, scenario_terminal_history_idle(runtime)
    case .Wait_Terminal_Explorer:
        return true, scenario_terminal_explorer_matches(runtime, text)
    case .Assert_Terminal_Preview:
        return true, scenario_terminal_preview_matches(runtime, text)
    case .Confirm_Terminal_History_Delete:
        return true, scenario_confirm_terminal_history_delete(runtime, text)
    case:
    }
    return false, false
}

// Activate only an OSC 8 URI already present in Terminal output.
scenario_activate_terminal_link :: proc(
    runtime: ^Scenario_Runtime, uri: string) -> bool {
    if runtime == nil || runtime.state == nil ||
        !runtime.state^.terminal.initialized {
        log.error("scenario_terminal_link_activation_failed reason=terminal_unavailable")
        return false
    }
    term := &runtime.state^.terminal
    for line in 0 ..< uiterminal.terminal_line_count(term) {
        cells, row_valid := terminalview.terminal_output_row(term, line)
        if !row_valid {
            continue
        }
        for column in 0..<len(cells) {
            handle := terminalview.terminal_output_hyperlink_at(term, line, column)
            target, target_valid := termhyperlink.hyperlink_registry_uri(
                term^.hyperlink_registry, handle)
            if target_valid && target == uri {
                return scenario_activate_terminal_link_handle(runtime, handle)
            }
        }
    }
    registry := term^.hyperlink_registry
    if registry == nil {
        log.error("scenario_terminal_link_activation_failed reason=registry_unavailable")
    } else {
        log.errorf(
            "scenario_terminal_link_activation_failed reason=target_not_visible entries=%d accepted=%d rejected=%d",
            registry.count, registry.acceptance_count, registry.rejection_count)
    }
    return false
}

// Invoke one found OSC 8 handle through the production Terminal activation path.
scenario_activate_terminal_link_handle :: proc(
    runtime: ^Scenario_Runtime, handle: termmodel.Hyperlink_Handle) -> bool {
    accepted := terminalview.terminal_activate_hyperlink(
        &runtime.state^.terminal, {
            kind = .Osc8,
            handle = handle,
            requested = true,
        }, {
            user_data = rawptr(runtime.state),
            activate = terminalservice.terminal_service_activate_uri,
        })
    if !accepted {
        log.error("scenario_terminal_link_activation_failed reason=activation_rejected")
    }
    return accepted
}

//   Record one accepted scenario action under its final correlation identity.
scenario_record_issued_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: evidence_trace.Identity) {
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Scenario,
            kind = .Scenario_Action_Issued,
            correlation_kind = identity.kind,
            correlation = identity.id,
            generation = identity.generation,
            flags = {.Required},
            payload = {
                counts = {
                    first = u32(command.kind),
                },
            },
        })
}

//   Route one generic scenario command through ordinary Euclid request state and APIs.
scenario_runtime_issue :: proc(
    user_data: rawptr, command: ^scenario.Command) -> scenario.Action_Result {
    runtime := cast(^Scenario_Runtime)user_data
    if runtime == nil || runtime.state == nil || command == nil {
        return {}
    }
    identity: evidence_trace.Identity = {
        kind = .Scenario_Action,
        id = runtime.next_action_id,
        generation = 1,
    }
    runtime.next_action_id += 1
    handled, accepted := scenario_issue_generic_action(runtime, command, &identity)
    if !handled || !accepted {
        return {}
    }
    scenario_record_issued_action(runtime, command, identity)
    return {
        accepted = true,
        correlation = identity,
    }
}

//   Materialize one requested screenshot after a complete frame presentation.
scenario_runtime_capture_screenshot :: proc(
    user_data: rawptr, checkpoint: capture.Checkpoint) -> bool {
    runtime := cast(^Scenario_Runtime)user_data
    if runtime == nil || checkpoint.status != .Pending {
        return false
    }
    path := capture.checkpoint_path(&runtime.capture)
    if path == nil {
        return false
    }
    started_at := time.tick_now()
    operations := runtime^.framebuffer_operations
    frame, frame_ok := viewcapture.framebuffer_acquire_with_operations(operations)
    if !frame_ok {
        return false
    }
    defer viewcapture.framebuffer_release_with_operations(&frame, operations)
    if !viewcapture.framebuffer_export_with_operations(&frame, path, operations) {
        return false
    }
    persisted := os.exists(capture.checkpoint_path_text(&runtime.capture))
    log.infof("scenario_screenshot_capture persisted=%v elapsed_ms=%.3f",
        persisted, time.duration_seconds(time.tick_since(started_at)) * 1000)
    return persisted
}

//   Report whether the scenario reached any terminal outcome.
scenario_runtime_finished :: proc(runtime: ^Scenario_Runtime) -> bool {
    if runtime == nil {
        return false
    }
    status := runtime.runner.status
    return status == .Passed || status == .Failed || status == .Inconclusive
}

//   Report whether the scenario completed with authoritative success.
scenario_runtime_succeeded :: proc(runtime: ^Scenario_Runtime) -> bool {
    return runtime != nil && runtime.runner.status == .Passed
}

//   Match an exact display name or one direct-parent-qualified display path.
scenario_animation_name_matches :: proc(
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    name: string) -> bool {
    separator := strings.index_byte(name, '/')
    if separator < 0 {
        return animation.name == name
    }
    if separator == 0 || separator == len(name) - 1 ||
        animation.parent == nil {
        return false
    }
    return animation.parent.name == name[:separator] &&
        animation.name == name[separator + 1:]
}

//   Find one registered animation by exact or parent-qualified name without allocation.
scenario_find_animation :: proc(
    interface: ^bridgemodel.Euclid_Julia_Interface,
    name: string) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if interface == nil || len(name) == 0 {
        return nil
    }
    for animation := interface.animation_head;
        animation != nil;
        animation = animation.next_in_registry {
        if scenario_animation_name_matches(animation, name) {
            return animation
        }
    }
    return nil
}
