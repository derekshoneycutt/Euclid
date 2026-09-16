package view

import bridgemodel "../bridge/model"
import viewmodel "model"

import presentation_model "../bridge/presentation"

import julia "../bridge"
import "../core"
import capture "../evidence/capture"
import "../diagnostics"
import artifact "../evidence/artifact"
import scenario "../evidence/scenario"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import particlemodel "../particles/model"

import "core:log"
import "core:os"
import "core:strings"
import "base:runtime"
import "core:testing"

// Accept one injected post-presentation capture.
scenario_runtime_test_capture :: proc(
    user_data: rawptr, checkpoint: capture.Checkpoint) -> bool {
    captured := cast(^capture.Checkpoint)user_data
    captured^ = checkpoint
    return true
}

// Verify the expected passed and failed scenario records in one completed log.
scenario_runtime_expect_outcome_logs :: proc(t: ^testing.T, path: string) {
    context.logger = log.nil_logger()
    content_bytes, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(content_bytes)
    defer os.remove(path)
    content := string(content_bytes)
    testing.expect(t, strings.contains(content,
        "scenario_passed step=3 assertions=0 failures=0 reason=0"))
    testing.expect(t, strings.contains(content,
        "scenario_failed step=5 assertions=3 failures=1"))
}

// Verify a running native session remains eligible for scenario-driven input.
@(test)
scenario_runtime_terminal_input_tracks_foreground_owner :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    state^.terminal.initialized = true
    state^.terminal.julia_session_ready = true
    testing.expect(t, scenario_terminal_input_available(state))

    state^.terminal.awaiting_eval = true
    testing.expect(t, !scenario_terminal_input_available(state))

    state^.shell.phase = .Running
    testing.expect(t, scenario_terminal_input_available(state))
}

// Verify ordinary state requests and orderly shutdown flow through the action sink.
@(test)
scenario_runtime_actions_use_display_owned_state :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/scenario-outcomes.log"
    os.make_directory_all(".build/test-artifacts")
    os.remove(path)
    logging_state: diagnostics.Logging_State
    testing.expect(t, diagnostics.logging_start(&logging_state, path, .Info))
    context.logger = logging_state.logger
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true

    program := scenario.Program{count = 3}
    program.commands[0] = {kind = .Pause_Simulation}
    program.commands[1] = {kind = .Resume_Simulation}
    program.commands[2] = {kind = .Shutdown}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Passed)
    testing.expect(t, !state^.ui_runtime.simulation_paused)
    testing.expect(t, runtime.shutdown_requested)

    failed := Scenario_Runtime{
        state = state,
        terminal_reason = artifact.Reason.Assertion_Failed,
    }
    failed.runner.step = 5
    failed.runner.assertion_count = 3
    failed.runner.failure_count = 1
    scenario_runtime_record_terminal(&failed, .Failed)

    context.logger = log.nil_logger()
    diagnostics.logging_stop(&logging_state)
    scenario_runtime_expect_outcome_logs(t, path)
}

// Verify animation policy can pause independently from particle simulation.
@(test)
scenario_runtime_animation_pause_uses_display_owned_state :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity
    pause := scenario.Command{kind = .Pause_Animation}
    resume := scenario.Command{kind = .Resume_Animation}

    handled, accepted := scenario_issue_display_action(&runtime, &pause, &identity)
    testing.expect(t, handled && accepted)
    testing.expect(t, state^.ui_runtime.animation_policy_paused)
    testing.expect(t, !state^.ui_runtime.simulation_paused)
    handled, accepted = scenario_issue_display_action(&runtime, &resume, &identity)
    testing.expect(t, handled && accepted)
    testing.expect(t, !state^.ui_runtime.animation_policy_paused)
}

// Verify emit_dust queues one bounded worker request with scenario correlation.
@(test)
scenario_runtime_dust_emission_queues_particle_request :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system)
    executor := new(Simulation_Executor, context.allocator)
    defer free(executor)
    particle_system^.use_max_dust_particles = 100
    state^.particle_system = particle_system
    state^.simulation_executor = executor
    runtime := Scenario_Runtime{state = state}
    command := scenario.Command{
        kind = .Emit_Dust, dust_distribution = .Grid, dust_count = 50,
        value = 0.5, secondary_value = 0.4, tertiary_value = 0.2,
        dust_seed = 9}
    identity := evidence_trace.Identity{.Scenario_Action, 12, 1}

    handled, accepted := scenario_issue_generic_action(
        &runtime, &command, &identity)

    testing.expect(t, handled && accepted)
    testing.expect_value(t, executor^.particle_task.dust_emission_queue.count, 1)
    request := executor^.particle_task.dust_emission_queue.items[0]
    testing.expect_value(t, request.count, u32(50))
    testing.expect_value(t, request.distribution,
        particlemodel.Dust_Emission_Distribution.Grid)
    testing.expect_value(t, request.correlation, u64(12))
    testing.expect_value(t, request.generation, u64(1))
}

// Verify dust disturbances cross bounded owner requests without direct kick mutation.
@(test)
scenario_runtime_dust_disturbances_queue_owner_requests :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system)
    executor := new(Simulation_Executor, context.allocator)
    defer free(executor)
    state^.particle_system = particle_system
    state^.simulation_executor = executor
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    contact := scenario.Command{
        kind = .Contact_Dust, value = 0.25, secondary_value = 0.75}
    handled, accepted := scenario_issue_generic_action(
        &runtime, &contact, &identity)
    testing.expect(t, handled && accepted)
    testing.expect_value(t, particle_system^.dust_tool_contact_count, 1)
    testing.expect_value(t, particle_system^.dust_tool_contacts[0].source,
        particlemodel.Dust_Tool_Contact_Source.Scenario)

    kick := scenario.Command{kind = .Kick_Dust}
    handled, accepted = scenario_issue_generic_action(&runtime, &kick, &identity)
    testing.expect(t, handled && accepted)
    testing.expect(t, executor^.particle_task.scenario_dust_kick_requested)
}

// Verify the particle worker consumes one scenario clear-kick request.
@(test)
scenario_dust_kick_commits_on_particle_worker :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system)
    particle_system^.use_max_dust_particles = 1
    particle_system^.low_particles[0].alive = true
    particle_system^.low_particles[0].life = 1
    before_velocity := particle_system^.low_particles.vel_z[0]
    state^.particle_system = particle_system
    data := Simulation_Task_Data{
        state = state, scenario_dust_kick_requested = true}

    consume_scenario_dust_requests(&data)

    testing.expect(t, !data.scenario_dust_kick_requested)
    testing.expect(t, particle_system^.low_particles.vel_z[0] > before_velocity)
}

// Verify the particle worker emits queued dust and records correlated completion.
@(test)
scenario_dust_emission_commits_on_particle_worker :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system)
    particle_system^.use_max_dust_particles = 16
    state^.particle_system = particle_system
    state^.evidence_session.enabled = true
    state^.evidence_session.lanes = evidence_session.ALL_LANES
    state^.evidence_session.required_evidence_complete = true
    data := new(Simulation_Task_Data, context.allocator)
    defer free(data)
    data^.state = state
    data^.dust_emission_queue.count = 1
    data^.dust_emission_queue.items[0] = {
        distribution = .Point, count = 8, x = 0.5, y = 0.5,
        seed = 3, correlation = 14, generation = 1}
    evidence_trace.ring_init(&data^.evidence_ring, .Particle_Worker)

    consume_scenario_dust_requests(data)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &data^.evidence_ring)

    testing.expect_value(t, data^.dust_emission_queue.count, 0)
    testing.expect_value(t, particle_system^.dust_spawn_sequence, u64(8))
    testing.expect_value(t, state^.evidence_session.event_count, 1)
    event := state^.evidence_session.events[0]
    testing.expect_value(t, event.kind,
        evidence_trace.Kind.Dust_Emission_Committed)
    testing.expect_value(t, event.correlation, u64(14))
    testing.expect_value(t, event.payload.counts.first, u32(8))
    testing.expect_value(t, event.payload.counts.second, u32(8))
}

// Verify viewport actions remain deferred until the next pre-geometry boundary.
@(test)
scenario_runtime_defers_viewport_mutations :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := new(bridgemodel.Euclid_Julia_Animation_Interface, context.allocator)
    defer free(animation)
    state^.julia_interface^.selected_animation = animation
    state^.ui_runtime.window = {1280, 720}
    state^.ui_runtime.presentation_visible = true
    state^.ui_runtime.landscape = {
        vertical_ratio = f32(900) / 1280,
        horizontal_ratio = f32(500) / 720,
    }
    state^.ui_runtime.vertical_split_x = 900
    state^.ui_runtime.horizontal_split_y = 500
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    scroll := scenario.Command{kind = .Set_View_Scroll, value = 90}
    handled, accepted := scenario_issue_display_action(&runtime, &scroll, &identity)
    testing.expect(t, handled && accepted)
    testing.expect_value(t, state^.ui_runtime.view_text_scroll_y, f32(0))
    testing.expect(t, scenario_runtime_apply_pending_ui(&runtime))
    testing.expect_value(t, state^.ui_runtime.view_text_scroll_y, f32(90))

    splitters := scenario.Command{
        kind = .Set_Splitters, value = 0, secondary_value = 720}
    handled, accepted = scenario_issue_display_action(
        &runtime, &splitters, &identity)
    testing.expect(t, handled && accepted)
    testing.expect_value(t, state^.ui_runtime.vertical_split_x, f32(900))
    testing.expect(t, scenario_runtime_apply_pending_ui(&runtime))
    testing.expect_value(t, state^.ui_runtime.vertical_split_x, f32(320))
    testing.expect_value(t, state^.ui_runtime.horizontal_split_y, f32(580))
}

// Verify portrait scenario splitter mutation ignores vertical and landscape intent.
@(test)
scenario_runtime_portrait_splitter_mutates_only_world_ratio :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    state^.ui_runtime.window = {1280, 720}
    state^.ui_runtime.landscape = {
        vertical_ratio = f32(900) / 1280,
        horizontal_ratio = f32(500) / 720,
    }
    state^.ui_runtime.vertical_split_x = 320
    state^.ui_runtime.horizontal_split_y = 580
    state^.ui_runtime.current_layout_mode = .Portrait
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity
    landscape := state^.ui_runtime.landscape
    splitters := scenario.Command{
        kind = .Set_Splitters, value = 1000, secondary_value = 360}
    handled, accepted := scenario_issue_display_action(
        &runtime, &splitters, &identity)
    testing.expect(t, handled && accepted)
    testing.expect(t, scenario_runtime_apply_pending_ui(&runtime))
    testing.expect_value(t, state^.ui_runtime.vertical_split_x, f32(320))
    testing.expect_value(t, state^.ui_runtime.horizontal_split_y, f32(360))
    testing.expect_value(t, state^.ui_runtime.portrait.world_height_ratio, f32(0.5))
    testing.expect_value(t, state^.ui_runtime.landscape, landscape)
}

// Verify portrait startup resolves directly to the selected-title View section.
@(test)
runtime_fields_initialize_portrait_view :: proc(t: ^testing.T) {
    settings := Euclid_Run_Settings{
        window = {width = 640, height = 720, layout = .Portrait},
    }
    runtime: viewmodel.Euclid_Ui_Runtime_State
    init_ui_runtime_fields(&runtime, &settings)
    testing.expect_value(t, runtime.current_layout_mode,
        viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, runtime.active_accordion_section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect_value(t, runtime.portrait.active_section,
        viewmodel.Ui_Accordion_Section.View)
    testing.expect(t, runtime.portrait.entered)
}

// Verify a required screenshot keeps the run active until post-presentation completion.
@(test)
scenario_runtime_waits_for_post_present_capture :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true
    state^.fixed_step = 11

    path, copied := scenario.text_copy(".build/test-artifacts/frame.png")
    testing.expect(t, copied)
    program := scenario.Program{count = 1}
    program.commands[0] = {kind = .Request_Screenshot, text = path}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Running)
    captured: capture.Checkpoint
    testing.expect_value(t, scenario_runtime_after_present(&runtime, {
        user_data = &captured,
        capture = scenario_runtime_test_capture,
    }), capture.Checkpoint_Status.Completed)
    testing.expect_value(t, captured.fixed_step, u64(11))
    testing.expect_value(t,
        scenario_runtime_update(&runtime, 2), scenario.Run_Status.Passed)
}

// Verify scenario selection uses the programmatic tree synchronization path.
@(test)
scenario_animation_selection_requests_tree_reveal :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(service)
    state^.julia_runtime_service = service
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    nodes[0].name = "Group"
    nodes[1].name = "Target"
    nodes[0].next_in_registry = &nodes[1]
    nodes[0].first_child = &nodes[1]
    nodes[1].parent = &nodes[0]
    nodes[1].stable_id[0] = 7
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    command_text, copied := scenario.text_copy("Target")
    testing.expect(t, copied)
    command := scenario.Command{kind = .Select_Animation, text = command_text}
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    handled, accepted := scenario_issue_julia_action(&runtime, &command, &identity)

    testing.expect(t, handled && accepted)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect(t, nodes[0].is_expanded && nodes[1].is_selected)
    testing.expect(t, state^.ui_runtime.tree_reveal_pending)
    testing.expect_value(t, identity.kind, evidence_trace.Correlation_Kind.Animation)
}

// Verify deferred reload actions identify the runtime generation they will publish.
@(test)
scenario_reload_action_targets_next_runtime_generation :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(service)
    state^.julia_runtime_service = service
    service^.runtime_generation = 7
    command := scenario.Command{kind = .Reload_Runtime}
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    handled, accepted := scenario_issue_julia_action(&runtime, &command, &identity)

    testing.expect(t, handled && accepted && service^.reload_requested)
    testing.expect_value(t, identity.kind,
        evidence_trace.Correlation_Kind.Runtime_Request)
    testing.expect_value(t, identity.id, u64(8))
    testing.expect_value(t, identity.generation, u64(8))
}

// Verify a parent-qualified selector disambiguates duplicate leaf names.
@(test)
scenario_animation_selection_qualified_name :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(service)
    state^.julia_runtime_service = service
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    nodes: [4]bridgemodel.Euclid_Julia_Animation_Interface
    nodes[0].name = "Elements"
    nodes[1].name = "Circle"
    nodes[2].name = "Curves"
    nodes[3].name = "Circle"
    for i in 0..<len(nodes) - 1 {
        nodes[i].next_in_registry = &nodes[i + 1]
    }
    nodes[1].parent = &nodes[0]
    nodes[3].parent = &nodes[2]
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)

    selected := scenario_find_animation(ji, "Curves/Circle")

    testing.expect_value(t, selected, &nodes[3])
}

// Verify one queued view-content request retains exact source and lifecycle identity.
scenario_expect_view_content_request :: proc(
    t: ^testing.T, service: ^bridgemodel.Julia_Runtime_Service,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    identity: evidence_trace.Identity) {
    message, received := julia.communication_link_try_recv(&service^.request_link)
    testing.expect(t, received)
    request, request_ok := message^.(bridgemodel.Scenario_View_Content_Requested)
    testing.expect(t, request_ok)
    testing.expect_value(t, string(request.source), "$A_1$")
    testing.expect_value(t, request.mime, presentation_model.Presentation_Mime.Text_Latex)
    testing.expect_value(t, request.runtime_generation, u64(7))
    testing.expect_value(t, request.animation_generation, u64(9))
    testing.expect_value(t, request.animation, animation)
    testing.expect_value(t, request.origin, identity)
    testing.expect(t, julia.communication_link_return(&service^.request_link, message))
    testing.expect_value(t, julia.drain_julia_ingress_returns(service), 1)
}

// Verify view-content actions copy exact source and lifecycle identity into ingress.
@(test)
scenario_view_content_submits_typed_owner_request :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(service)
    testing.expect_value(t, julia.init_julia_runtime_channels(service),
        runtime.Allocator_Error.None)
    defer julia.communication_link_destroy(&service^.event_link)
    defer julia.communication_link_destroy(&service^.request_link)
    state^.julia_runtime_service = service
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = animation
    service^.lifecycle = .Ready
    service^.runtime_generation = 7
    service^.animation_generation = 9
    source, copied := scenario.text_copy("$A_1$")
    testing.expect(t, copied)
    command := scenario.Command{kind = .Set_View_Content,
        view_content_mime = .Text_Latex, text = source}
    runtime_state := Scenario_Runtime{state = state}
    identity := evidence_trace.Identity{
        kind = .Scenario_Action, id = 4, generation = 1}

    handled, accepted := scenario_issue_julia_action(
        &runtime_state, &command, &identity)
    testing.expect(t, handled && accepted)
    scenario_expect_view_content_request(t, service, animation, identity)
}
