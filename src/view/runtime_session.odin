package view

import capturemodel "capture/model"

import bridgemodel "../bridge/model"
import shapemodel "../shapes/model"
import viewcontent "content"
import setting_model "../settings"
import user_data "../userdata"
import core "../core"
import color "../core/color"
import dynview "../dynview"
import evidence_artifact "../evidence/artifact"
import evidence_export "../evidence/export"
import observe "../evidence/observe"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import files "../files"
import shapes "../shapes"
import julia "../bridge"
import taskpool "../taskpool"
import fmt "core:fmt"
import log "core:log"
import math "core:math"
import linalg "core:math/linalg"
import time "core:time"
import projection "world/projection"
import worldmodel "world/model"
import simulationmodel "simulation/model"
import viewmodel "ui/model"
import viewcapture "capture"
import geometry "../core/geometry"
import particlemodel "../particles/model"
import viewpresentation "presentation"
import terminalservice "terminal/service"
import viewsimulation "simulation"
import viewscenario "scenario"
import viewevidence "evidence"
import viewpreferences "preferences"
import uiregions "ui/layout/regions"
import collections "../collections"

when !core.SCENARIOS_ENABLED {
    _ :: observe
}

// Carry app-resolved settings and borrowed store ownership into the view session.
Session_Startup_Inputs :: struct {
    preferences: setting_model.Preferences,
    collections: collections.Set,
    user_store: ^user_data.Store,
}

Euclid_Runtime_Session :: struct {
    state : ^core.Euclid_General_State,
    julia_service : ^bridgemodel.Julia_Runtime_Service,
    presentation : ^viewpresentation.Presentation_Runtime,
    content_service: ^viewcontent.Content_Service,
    startup: Session_Startup_Inputs,
}

//   Created Julia runtime service plus its completed initialize request id.
Session_Julia_Service :: struct {
    service : ^bridgemodel.Julia_Runtime_Service,
    initialize_id : u64,
}

//   Allocated canonical shape world plus its baseline tools.
Session_Shape_Storage :: struct {
    world : ^shapemodel.Shape_World,
    world_trochoid_tool : shapemodel.Shape_Trochoid_Tool_Handle,
    world_cycloid_tool : shapemodel.Shape_Cycloid_Tool_Handle,
    world_compass : shapemodel.Shape_Compass_Handle,
    world_pen : shapemodel.Shape_Pen_Handle,
}

// Supply no-database defaults for existing direct runtime-session callers.
session_startup_inputs :: proc(
    startup: ^Session_Startup_Inputs) -> Session_Startup_Inputs {
    if startup != nil {
        resolved := startup^
        if resolved.collections.collection_count == 0 {
            collections.initialize(&resolved.collections)
        }
        return resolved
    }
    defaults: Session_Startup_Inputs
    defaults.preferences = setting_model.default_preferences()
    collections.initialize(&defaults.collections)
    return defaults
}

//   Wait for one Julia startup request without driving a window event loop.
wait_for_julia_request :: proc(
    service: ^bridgemodel.Julia_Runtime_Service,
    request_id: u64,
    expected_kind: bridgemodel.Julia_Event_Kind,
    timeout_seconds: f64) -> bool {

    started_at := time.tick_now()
    for {
        event, ok := julia.try_route_julia_egress(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            return event.succeeded
        }
        if time.duration_seconds(time.tick_since(started_at)) >= timeout_seconds {
            fmt.eprintln("Julia request timed out; request id: ", request_id)
            log.errorf("julia_request_timeout request_id=%d expected_kind=%d",
                request_id, int(expected_kind))
            return false
        }
        free_all(context.temp_allocator)
    }
}

//   Create the Julia runtime service and wait for its Initialize phase.
//
// Returns:
//   - ok: true when the service was created and initialized.
session_start_julia_service :: proc(
    out: ^Session_Julia_Service,
    profile_path: string = "",
    asset_config: ^files.Asset_Root_Config = nil) -> bool {
    julia_service, service_err := julia.create_julia_runtime_service(
        profile_path, asset_config)
    if service_err != .None || julia_service == nil {
        log.errorf("julia_startup_failed phase=service_create error=%d",
            int(service_err))
        return false
    }

    initialize_id, initialize_sent :=
        julia.try_submit_runtime_initialize(julia_service)
    if !initialize_sent {
        log.error("julia_startup_failed phase=initialize_submit")
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    if !wait_for_julia_request(
        julia_service, initialize_id, .Initialized, 10.0) {
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    out.service = julia_service
    out.initialize_id = initialize_id
    return true
}

//   Derive the independent Julia-worker stream from the configured display path.
julia_worker_profile_path :: proc(profile_path: string) -> string {
    if len(profile_path) == 0 {
        return ""
    }
    return fmt.tprintf("%s.worker.spall", profile_path)
}

//   Record one required Julia runtime lifecycle transition.
record_runtime_lifecycle :: proc(
    state: ^core.Euclid_General_State, kind: evidence_trace.Kind,
    correlation: u64) {
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = kind,
            correlation_kind = .Runtime_Request,
            correlation = correlation,
            generation = state^.julia_runtime_service^.runtime_generation,
            flags = {.Required},
        })
}

//   Allocate runtime state and complete the Julia content Invoke phase.
session_initialize_content :: proc(
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    state: ^core.Euclid_General_State, content_id_out: ^u64) -> bool {
    content_id, content_sent := julia.try_submit_runtime_content_initialize(
        julia_service, state)
    if !content_sent {
        log.error("julia_startup_failed phase=content_submit")
        return false
    }
    content_id_out^ = content_id
    return wait_for_julia_request(
        julia_service, content_id, .Invoke_Complete, 10.0)
}

// Copy the admitted content's catalogue into interface-owned deferred-draw storage.
session_materialize_content :: proc(
    state: ^core.Euclid_General_State,
    content_service: ^viewcontent.Content_Service) -> bool {
    state^.content_service = content_service
    generation := viewcontent.content_service_generation(content_service)
    if generation == nil || !julia.content_generation_materialize(
        state^.julia_interface, generation) {
        return false
    }
    return true
}

//   Allocate runtime state and complete the Julia content Invoke phase.
//
// Returns:
//   - ok: true when state was created and content initialization completed.
session_load_content :: proc(
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    content_service: ^viewcontent.Content_Service,
    settings: ^core.Euclid_Run_Settings,
    initialize_id: u64,
    out_state: ^^core.Euclid_General_State) -> bool {

    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        log.error("julia_startup_failed phase=state_create")
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    if !session_materialize_content(state, content_service) {
        log.error("content_startup_failed phase=registry_materialize")
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return false
    }
    record_runtime_lifecycle(state, .Runtime_Starting, initialize_id)
    content_id: u64
    if !session_initialize_content(julia_service, state, &content_id) {
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return false
    }

    julia.mark_julia_runtime_ready(julia_service)
    record_runtime_lifecycle(state, .Runtime_Ready, content_id)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
    out_state^ = state
    return true
}

// Resolve and start the immutable complete content store for one runtime session.
session_create_content_service :: proc(
    asset_config: ^files.Asset_Root_Config = nil) -> ^viewcontent.Content_Service {
    asset, asset_ok := files.packaged_content_asset_with_config(
        asset_config, context.temp_allocator)
    if asset_ok {
        service := viewcontent.content_service_create(
            asset.database_path, asset.corpus_fingerprint)
        if service != nil {
            return service
        }
    }
    log.error("content_startup_failed phase=database_admission")
    return nil
}

//   Create and attach presentation resources to one initialized runtime session.
session_start_presentation :: proc(session: ^Euclid_Runtime_Session) -> bool {
    session.presentation = viewpresentation.create_presentation_runtime()
    if session.presentation == nil {
        return false
    }
    julia_egress_router_attach(session.state, session.presentation)
    return true
}

// Attach presentation resources and return the fully initialized session value.
session_finalize_presentation :: proc(
    state: ^core.Euclid_General_State,
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    content_service: ^viewcontent.Content_Service,
    out_session: ^Euclid_Runtime_Session,
    startup: ^Session_Startup_Inputs = nil) -> bool {
    session := Euclid_Runtime_Session{
        state = state,
        julia_service = julia_service,
        content_service = content_service,
        startup = session_startup_inputs(startup),
    }
    session_apply_startup_preferences(
        state, session.startup.preferences,
        session.startup.collections, session.startup.user_store)
    if !session_start_presentation(&session) {
        _ = shutdown_runtime_session(session)
        return false
    }
    out_session^ = session
    return true
}

// Initialize editable preference intent without applying hardware fallbacks.
session_apply_startup_preferences :: proc(
    state: ^core.Euclid_General_State,
    preferences: setting_model.Preferences,
    collection_state: collections.Set,
    store: ^user_data.Store) {
    if state == nil || state^.particle_system == nil {
        return
    }
    state^.ui_runtime.settings_preferences = preferences
    state^.preferences_runtime.settings_store = store
    state^.preferences_runtime.collections_state = collection_state
    state^.ui_runtime.settings_store_available = store != nil
    state^.ui_runtime.settings_save_status =
        .Saved if store != nil else .Unavailable
    state^.ui_runtime.display_fps = preferences.interface.display_fps
    state^.ui_runtime.limit_fps = preferences.rendering.limit_fps
    state^.user_drawing_sound_enabled = preferences.drawing.sound_enabled
    state^.particle_system^.use_max_dust_particles = preferences.drawing.dust_limit
    state^.ui_runtime.use_simd_batch_projection =
        preferences.rendering.simd && projection.simd_batch_projection_available()
}

//   Prepare runtime-owned subsystems and state without initializing presentation resources.
create_runtime_session :: proc(
    settings: ^core.Euclid_Run_Settings,
    asset_config: ^files.Asset_Root_Config = nil,
    startup: ^Session_Startup_Inputs = nil) -> (Euclid_Runtime_Session, bool) {
    if settings == nil {
        return {}, false
    }

    if !files.packaged_asset_archive_exists_root(asset_config) ||
        !files.ensure_packaged_assets_unpacked_root(asset_config) {
        return {}, false
    }
    content_service := session_create_content_service(asset_config)
    if content_service == nil {
        return {}, false
    }
    started: Session_Julia_Service
    if !session_start_julia_service(
        &started, julia_worker_profile_path(settings^.profile_path), asset_config) {
        viewcontent.content_service_destroy_owned(content_service)
        return {}, false
    }
    julia_service := started.service

    state: ^core.Euclid_General_State
    if !session_load_content(
        julia_service, content_service, settings, started.initialize_id, &state) {
        viewcontent.content_service_destroy_owned(content_service)
        return {}, false
    }
    session: Euclid_Runtime_Session
    if !session_finalize_presentation(
        state, julia_service, content_service, &session, startup) {
        return {}, false
    }
    return session, true
}

//   Allocate and initialize the isometric projection scale.
make_iso_scale :: proc() -> ^worldmodel.Iso_Scale {
    iso_scale := new(worldmodel.Iso_Scale, context.allocator)
    iso_scale^.scale = worldmodel.ISO_SCALE_VALUE
    iso_scale^.x_offset = worldmodel.ISO_X_OFFSET
    iso_scale^.y_offset = worldmodel.ISO_Y_OFFSET
    projection.recompute_iso_scale_precompute(iso_scale)
    iso_scale^.main_light_dir = linalg.normalize(geometry.Vector3{0.35, -0.45, -1.0})
    iso_scale^.use_directional_shadow = true
    return iso_scale
}

//   Allocate and initialize the drawing surface quad.
make_drawing_surface :: proc() -> ^worldmodel.Euclid_Drawing_Surface {
    drawing_surface := new(worldmodel.Euclid_Drawing_Surface, context.allocator)
    edge := f32(worldmodel.SURFACE_EDGE_SIZE)
    drawing_surface^.zeros = geometry.Vector3{0 - edge, 0 - edge, 0}
    drawing_surface^.right_up = geometry.Vector3{1 + edge, 0 - edge, 0}
    drawing_surface^.left_down = geometry.Vector3{0 - edge, 1 + edge, 0}
    drawing_surface^.right_down = geometry.Vector3{1 + edge, 1 + edge, 0}
    drawing_surface^.color = color.Color_RGBA8(worldmodel.SURFACE_COLOR)
    drawing_surface^.edge_color = color.Color_RGBA8(worldmodel.SURFACE_EDGE_COLOR)
    drawing_surface^.edge_size = worldmodel.SURFACE_EDGE_SIZE
    return drawing_surface
}

//   Allocate the canonical shape world and build its baseline tools.
make_shape_storage :: proc(out: ^Session_Shape_Storage) -> bool {
    world := new(shapemodel.Shape_World, context.allocator)
    world_trochoid_tool, trochoid_tool_status := shapes.world_create_trochoid_tool(
        world, {mode = .External, fixed_radius = 0.2, rolling_radius = 0.1,
            style = {color = color.Color_RGBA8(worldmodel.TOOL_COLOR), brush_size = 5}})
    world_cycloid_tool, cycloid_tool_status := shapes.world_create_cycloid_tool(
        world, {first = {0.04, 0.38, 0}, second = {0.96, 0.38, 0},
            rolling_radius = 0.06, parameter_start = 0,
            parameter_finish = 4 * math.PI,
            style = {color = color.Color_RGBA8(worldmodel.TOOL_COLOR), brush_size = 5}})
    world_compass, compass_status := shapes.world_create_compass(world, {
        joint1 = {0, 0, 0}, pivot = {0.01, 0.01, 0.01},
        joint2 = {0.02, 0.02, 0}, limb_length = worldmodel.TOOL_LENGTH,
        style = {color = color.Color_RGBA8(worldmodel.TOOL_COLOR), brush_size = 5}})
    world_pen, pen_status := shapes.world_create_pen(world, {
        joint1 = {0, 0, 0}, joint2 = {0, 0, 0}, length = worldmodel.TOOL_LENGTH,
        style = {color = color.Color_RGBA8(worldmodel.TOOL_COLOR), brush_size = 5}})
    if trochoid_tool_status != .Ok || cycloid_tool_status != .Ok ||
        compass_status != .Ok || pen_status != .Ok ||
        shapemodel.shape_world_freeze_baseline(world) != .Ok {
        free(world)
        return false
    }
    shapes.world_apply_all_constraints_to_error(
        world, simulationmodel.ALLOWED_CONSTRAINT_ERROR)
    shapes.shape_world_update_previous_values(world)
    out.world = world
    out.world_trochoid_tool = world_trochoid_tool
    out.world_cycloid_tool = world_cycloid_tool
    out.world_compass = world_compass
    out.world_pen = world_pen
    return true
}

//   Derive initial split pixels and portrait-entry state from the resolved mode.
init_ui_layout_pixels :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, width, height: int) {
    if runtime^.current_layout_mode == .Portrait {
        runtime^.vertical_split_x = f32(width)
        runtime^.horizontal_split_y = f32(height) * runtime^.portrait.world_height_ratio
        runtime^.portrait.entered = true
        return
    }
    runtime^.vertical_split_x = f32(width) * runtime^.landscape.vertical_ratio
    runtime^.horizontal_split_y = f32(height) * runtime^.landscape.horizontal_ratio
}

//   Initialize display-owned GIF capture preferences and status.
init_gif_capture_fields :: proc(runtime: ^capturemodel.Gif_Capture_Status) {
    runtime^.gif_downsample_factor = 2
    runtime^.gif_frame_step = 2
    runtime^.gif_timing_mode = .Animation
    runtime^.gif_capture_phase = .Idle
    viewcapture.clear_gif_status_note(runtime)
}

// Resolve the initial accordion section and presentation visibility from layout.
init_ui_active_section :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    runtime^.active_accordion_section = runtime^.landscape.active_section
    if runtime^.current_layout_mode == .Portrait {
        runtime^.active_accordion_section = runtime^.portrait.active_section
    }
    runtime^.presentation_visible =
        runtime^.current_layout_mode == .Landscape ||
        runtime^.active_accordion_section == .View
}

//   Initialize display-owned UI policy and layout memory from run settings.
init_ui_semantic_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    if runtime == nil {
        return false
    }
    runtime^.semantic_focus = new(
        viewmodel.Ui_Semantic_Focus_State, context.allocator)
    return runtime^.semantic_focus != nil
}

//   Initialize display-owned UI policy and layout memory from run settings.
init_ui_runtime_fields :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    settings: ^core.Euclid_Run_Settings) -> bool {
    if settings == nil || !init_ui_semantic_focus(runtime) {
        return false
    }
    runtime^.limit_fps = settings^.limit_fps
    runtime^.simulation_paused = false
    runtime^.use_simd_batch_projection =
        settings^.use_simd_batch_projection &&
        projection.simd_batch_projection_available()
    runtime^.use_gpu_dust_instancing = false
    runtime^.window = {
        width = settings^.window.width,
        height = settings^.window.height,
    }
    runtime^.layout_preference = settings^.window.layout
    runtime^.landscape = {
        vertical_ratio = f32(worldmodel.VIEW_WIDTH) / f32(viewmodel.WINDOW_WIDTH),
        horizontal_ratio = f32(worldmodel.VIEW_HEIGHT) / f32(viewmodel.WINDOW_HEIGHT),
        active_section = .Library,
    }
    runtime^.portrait = {
        world_height_ratio = 0.5,
        active_section = .View,
    }
    runtime^.current_layout_mode = uiregions.resolve_initial_layout_mode(
        settings^.window.layout,
        f32(settings^.window.width), f32(settings^.window.height))
    init_ui_active_section(runtime)
    init_ui_layout_pixels(runtime, settings^.window.width, settings^.window.height)
    return true
}

//   Populate the simulation/UI scalar fields on the general state.
init_runtime_fields :: proc(
    state: ^core.Euclid_General_State, settings: ^core.Euclid_Run_Settings) -> bool {
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.user_drawing_sound_enabled = false
    state^.fixed_step = 0
    state^.simulation_time = 0
    state^.current_delta_time = simulationmodel.FIXED_DT
    state^.accumulator = 0
    if !init_ui_runtime_fields(&state^.ui_runtime, settings) {
        return false
    }
    init_gif_capture_fields(&state^.gif_capture_status)
    dynview.set_enabled(&state.dynview, dynview.DYNVIEW_ENABLED_DEFAULT)
    projection.screenshake_clear(state^.iso_scale)
    return true
}

//   Initialize typed evidence policy, freeing the state and returning false on failure.
init_evidence_session :: proc(
    state: ^core.Euclid_General_State, settings: ^core.Euclid_Run_Settings) -> bool {
    if !evidence_session.session_init(
        &state^.evidence_session, settings^.evidence) {
        fmt.eprintln("Invalid semantic evidence configuration.")
        terminalservice.terminal_graphics_runtime_destroy(state)
        viewsimulation.destroy_simulation_executor(state^.simulation_executor)
        state^.simulation_executor = nil
        free_animations_state(state)
        return false
    }
    state^.julia_runtime_service^.evidence_session = &state^.evidence_session
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Started,
            flags = {.Required},
        })
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Configured,
            flags = {.Required},
        })
    return true
}

//   Initialize allocation domains and bind the state-owned runtime resources.
init_animations_state_resources :: proc(
    state: ^core.Euclid_General_State,
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    settings: ^core.Euclid_Run_Settings,
    particle_system: ^particlemodel.Particle_System,
    shapes_state: Session_Shape_Storage) -> bool {
    state^.evidence_allocations = settings^.evidence_allocations
    state^.saved_context = context
    state^.julia_runtime_service = julia_service
    state^.iso_scale = make_iso_scale()
    state^.draw_surface = make_drawing_surface()
    state^.particle_system = particle_system
    state^.shape_world = shapes_state.world
    state^.world_trochoid_tool = shapes_state.world_trochoid_tool
    state^.world_cycloid_tool = shapes_state.world_cycloid_tool
    state^.world_compass = shapes_state.world_compass
    state^.world_pen = shapes_state.world_pen
    return init_runtime_fields(state, settings)
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
init_native_shell_or_release :: proc(state: ^core.Euclid_General_State) -> bool {
    if terminalservice.shell_service_runtime_init(state) {
        return true
    }
    fmt.eprintln("Failed to initialize the native shell runtime.")
    free_animations_state(state)
    return false
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
init_runtime_executors :: proc(state: ^core.Euclid_General_State) -> bool {
    evidence_trace.ring_init(&state^.evidence_ring, .Display)
    state^.simulation_executor = viewsimulation.create_simulation_executor(state)
    if state^.simulation_executor == nil {
        fmt.eprintln("Failed to initialize the simulation task pool.")
        return false
    }
    if terminalservice.terminal_graphics_runtime_init(state) {
        return true
    }
    fmt.eprintln("Failed to initialize terminal graphics.")
    return false
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
make_animations_state :: proc(
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    settings: ^core.Euclid_Run_Settings) -> ^core.Euclid_General_State {
    particle_system := new(particlemodel.Particle_System, context.allocator)
    particle_system^.use_max_dust_particles = settings^.dust_particle_max
    shape_storage: Session_Shape_Storage
    if !make_shape_storage(&shape_storage) {
        free(particle_system)
        return nil
    }
    state := new(core.Euclid_General_State, context.allocator)
    if init_animations_state_resources(
        state, julia_service, settings, particle_system, shape_storage) {
        return state
    }
    free(state)
    free(particle_system)
    free(shape_storage.world)
    return nil
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
initiate_animations_state :: proc(
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    settings: ^core.Euclid_Run_Settings) -> ^core.Euclid_General_State {
    state := make_animations_state(julia_service, settings)
    if state == nil {
        return nil
    }
    if !julia.animation_storage_init(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents) {
        fmt.eprintln("Failed to initialize animation storage.")
        free_animations_state(state)
        return nil
    }
    if !init_native_shell_or_release(state) {
        return nil
    }
    if !init_runtime_executors(state) {
        free_animations_state(state)
        return nil
    }

    if !init_evidence_session(state, settings) {
        return nil
    }

    return state
}

when core.SCENARIOS_ENABLED {
    //   Write the terminal scenario artifact when one was requested.
    write_scenario_artifact :: proc(
        session: Euclid_Runtime_Session, runtime: ^viewscenario.Scenario_Runtime,
        simulation: observe.Simulation, output: string) -> bool {
        if runtime == nil || len(output) == 0 {
            return true
        }
        result := evidence_artifact.Result.Inconclusive
        if runtime.runner.status == .Passed {
            result = .Passed
        } else if runtime.runner.status == .Failed {
            result = .Failed
        }
        events := session.state.evidence_session.events[
            :session.state.evidence_session.event_count]
        last_trace_sequence: u64
        if len(events) > 0 {
            last_trace_sequence = events[len(events) - 1].sequence
        }
        return evidence_artifact.write_bundle(output, {
            manifest = {
                result = result,
                reason = runtime.terminal_reason,
                failed_step = runtime.runner.step,
                trace_complete =
                    session.state.evidence_session.required_evidence_complete,
                last_trace_sequence = last_trace_sequence,
            },
            events = events,
            state = viewevidence.observe_display_state(session.state),
            julia_host = observe.julia_host(session.julia_service),
            simulation = simulation,
            allocations = observe.allocation(session.state.evidence_allocations),
            arena_baselines = session.state.evidence_arena_baselines,
        })
    }
}

//   Export the completed evidence session through its selected encoding owner.
write_session_evidence :: proc(session: ^evidence_session.Session) -> bool {
    if session == nil || session.output_mode != .Binary_File {
        return evidence_export.write_session_jsonl(session)
    }
    path := string(session.output_path[:session.output_path_count])
    events := session.events[:session.event_count]
    return evidence_artifact.write_trace(path, events)
}

//   Shut down one runtime session in reverse ownership order.
finish_runtime_evidence :: proc(
    session: Euclid_Runtime_Session, scenario_runtime: ^viewscenario.Scenario_Runtime,
    simulation: observe.Simulation, artifact_output: string) -> (
    artifact_succeeded, evidence_exit_failed: bool) {
    _ = evidence_session.session_record(
        &session.state^.evidence_session, &session.state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Finished,
            flags = {.Required},
        })
    evidence_session.session_accept_ring(
        &session.state^.evidence_session, &session.state^.evidence_ring)
    when core.SCENARIOS_ENABLED {
        artifact_succeeded = write_scenario_artifact(
            session, scenario_runtime, simulation, artifact_output)
    } else {
        artifact_succeeded = true
    }
    export_succeeded := write_session_evidence(
        &session.state^.evidence_session) && artifact_succeeded
    evidence_session.session_finish(
        &session.state^.evidence_session, export_succeeded)
    evidence_exit_failed = evidence_session.session_should_fail_process(
        &session.state^.evidence_session)
    return
}

//   Shut down one runtime session in reverse ownership order.
shutdown_runtime_session :: proc(
    session: Euclid_Runtime_Session,
    scenario_runtime: ^viewscenario.Scenario_Runtime = nil,
    artifact_output: string = "") -> int {
    if session.state == nil || session.julia_service == nil {
        return 0
    }

    viewpresentation.quiesce_presentation_runtime(session.state, session.presentation)
    julia_egress_router_detach(session.state, session.presentation)
    viewpresentation.destroy_presentation_runtime(session.presentation)
    terminalservice.terminal_graphics_runtime_destroy(session.state)
    viewpreferences.settings_save_shutdown(
        session.state, &session.state^.simulation_executor^.pool)
    taskpool.task_pool_shutdown(&session.state^.simulation_executor^.pool)
    simulation := viewevidence.observe_simulation_executor(
        session.state^.simulation_executor)
    viewsimulation.destroy_simulation_executor(session.state^.simulation_executor)
    session.state^.simulation_executor = nil
    shutdown_julia_runtime(session.state, session.julia_service)
    session_retire_content(session)
    artifact_succeeded, evidence_exit_failed := finish_runtime_evidence(
        session, scenario_runtime, simulation, artifact_output)
    julia.release_published_view_snapshot(session.state, session.julia_service)
    julia.destroy_julia_runtime_service(session.julia_service)
    session.state^.julia_runtime_service = nil
    free_animations_state(session.state)
    if evidence_exit_failed || !artifact_succeeded {
        return 1
    }
    return 0
}

// Retire content only after Julia lifecycle readers have acknowledged shutdown.
session_retire_content :: proc(session: Euclid_Runtime_Session) {
    if session.content_service != nil {
        viewcontent.content_service_destroy_owned(session.content_service)
    }
    session.state^.content_service = nil
}
