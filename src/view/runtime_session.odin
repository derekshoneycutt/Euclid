package view

import view_core "core"
import "../core"
import "../dynview"
import "../files"
import "../shapes"
import julia "../bridge"
import "../trace"

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:time"

Euclid_Runtime_Session :: struct {
    state: ^Euclid_General_State,
    julia_service: ^julia.Julia_Runtime_Service,
}

//   Created Julia runtime service plus its completed initialize request id.
Session_Julia_Service :: struct {
    service:       ^julia.Julia_Runtime_Service,
    initialize_id: u64,
}

//   Allocated point system plus its default compass and pen tools.
Session_Point_System :: struct {
    point_system: ^Shapes_Point_System,
    compass:      core.Shapes_Compass,
    pen:          core.Shapes_Pen,
}

//   Wait for one Julia startup request without driving a window event loop.
wait_for_julia_request :: proc(
    service: ^julia.Julia_Runtime_Service,
    request_id: u64,
    expected_kind: julia.Julia_Event_Kind,
    timeout_seconds: f64) -> bool {

    started_at := time.tick_now()
    for {
        event, ok := julia.try_receive_julia_event(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            return event.succeeded
        }
        if time.duration_seconds(time.tick_since(started_at)) >= timeout_seconds {
            fmt.eprintln("Julia request timed out; request id: ", request_id)
            return false
        }
        free_all(context.temp_allocator)
    }
}

//   Create the Julia runtime service and wait for its Initialize phase.
//
// Returns:
//   - ok: true when the service was created and initialized.
session_start_julia_service :: proc(out: ^Session_Julia_Service) -> bool {
    julia_service, service_err := julia.create_julia_runtime_service()
    if service_err != .None || julia_service == nil {
        return false
    }

    initialize_id, initialize_sent :=
        julia.try_submit_julia_request(julia_service, .Initialize)
    if !initialize_sent ||
        !wait_for_julia_request(julia_service, initialize_id, .Initialized, 10.0) {
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    out.service = julia_service
    out.initialize_id = initialize_id
    return true
}

//   Allocate runtime state and complete the Julia content Invoke phase.
//
// Returns:
//   - ok: true when state was created and content initialization completed.
session_load_content :: proc(
    julia_service: ^julia.Julia_Runtime_Service,
    settings: ^Euclid_Run_Settings,
    initialize_id: u64,
    out_state: ^^Euclid_General_State) -> bool {

    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }

    _ = trace.record_runtime_event_ex(
        &state^.trace_state, "runtime.starting", julia_service^.runtime_generation,
        int(julia_service^.reload_state), initialize_id)
    content_id, content_sent := julia.try_submit_julia_request(
        julia_service, .Invoke, julia.initialize_julia_state_task, rawptr(state))
    if !content_sent ||
        !wait_for_julia_request(julia_service, content_id, .Invoke_Complete, 10.0) {
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return false
    }

    julia.mark_julia_runtime_ready(julia_service)
    _ = trace.record_runtime_event_ex(
        &state^.trace_state, "runtime.ready", julia_service^.runtime_generation,
        int(julia_service^.reload_state), content_id)
    out_state^ = state
    return true
}

//   Prepare runtime-owned subsystems and state without initializing presentation resources.
create_runtime_session :: proc(
    settings: ^Euclid_Run_Settings) -> (Euclid_Runtime_Session, bool) {
    if settings == nil {
        return {}, false
    }

    files.ensure_packaged_assets_unpacked_root()
    started: Session_Julia_Service
    if !session_start_julia_service(&started) {
        return {}, false
    }
    julia_service := started.service

    state: ^Euclid_General_State
    if !session_load_content(julia_service, settings, started.initialize_id, &state) {
        return {}, false
    }

    return Euclid_Runtime_Session{state = state, julia_service = julia_service}, true
}

//   Allocate and initialize the isometric projection scale.
make_iso_scale :: proc() -> ^Iso_Scale {
    iso_scale := new(Iso_Scale)
    iso_scale^.scale = view_core.ISO_SCALE_VALUE
    iso_scale^.x_offset = view_core.ISO_X_OFFSET
    iso_scale^.y_offset = view_core.ISO_Y_OFFSET
    view_core.recompute_iso_scale_precompute(iso_scale)
    iso_scale^.main_light_dir = linalg.normalize(Vector3{0.35, -0.45, -1.0})
    iso_scale^.use_directional_shadow = true
    return iso_scale
}

//   Allocate and initialize the drawing surface quad.
make_drawing_surface :: proc() -> ^Euclid_Drawing_Surface {
    drawing_surface := new(Euclid_Drawing_Surface)
    edge := f32(view_core.SURFACE_EDGE_SIZE)
    drawing_surface^.zeros = Vector3{0 - edge, 0 - edge, 0}
    drawing_surface^.right_up = Vector3{1 + edge, 0 - edge, 0}
    drawing_surface^.left_down = Vector3{0 - edge, 1 + edge, 0}
    drawing_surface^.right_down = Vector3{1 + edge, 1 + edge, 0}
    drawing_surface^.color = view_core.SURFACE_COLOR
    drawing_surface^.edge_color = view_core.SURFACE_EDGE_COLOR
    drawing_surface^.edge_size = view_core.SURFACE_EDGE_SIZE
    return drawing_surface
}

//   Allocate the point system, build the default tools, and settle constraints.
make_point_system :: proc(out: ^Session_Point_System) {
    point_system := new(Shapes_Point_System)
    compass := shapes.init_compass(point_system, TOOL_LENGTH, view_core.TOOL_COLOR, 5)
    pen := shapes.init_pen(point_system, TOOL_LENGTH, view_core.TOOL_COLOR, 5)
    shapes.freeze_system_indices(point_system)
    shapes.apply_all_constraints_to_error(
        point_system, view_core.ALLOWED_CONSTRAINT_ERROR)
    shapes.update_last_cache_vectors(point_system)
    out.point_system = point_system
    out.compass = compass
    out.pen = pen
}

//   Populate the simulation/UI scalar fields on the general state.
init_runtime_fields :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings) {
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.user_drawing_sound_enabled = false
    state^.animation_drawing_sound_enabled = true
    state^.fixed_step = 0
    state^.simulation_time = 0
    state^.current_delta_time = view_core.FIXED_DT
    state^.accumulator = 0
    state^.ui_runtime.limit_fps = settings^.limit_fps
    state^.ui_runtime.simulation_paused = false
    state^.ui_runtime.use_simd_batch_projection =
        settings^.use_simd_batch_projection && view_core.simd_batch_projection_available()
    state^.ui_runtime.use_gpu_dust_instancing = false
    dynview.set_enabled(&state.dynview, dynview.DYNVIEW_ENABLED_DEFAULT)
    state^.ui_runtime.gif_downsample_factor = 2
    state^.ui_runtime.gif_frame_step = 2
    state^.ui_runtime.gif_capture_phase = .Idle
    view_core.clear_gif_status_note(&state^.ui_runtime)
    view_core.screenshake_clear(state^.iso_scale)
}

//   Initialize trace state, freeing the state and returning false on failure.
init_state_trace :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings) -> bool {
    if !trace.initialize_trace_state(&state^.trace_state, settings) {
        fmt.eprintln("Invalid semantic trace configuration.")
        free_animations_state(state)
        return false
    }
    if !trace.begin_trace(&state^.trace_state) {
        fmt.eprintln("Failed to initialize semantic trace output.")
        free_animations_state(state)
        return false
    }
    return true
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
initiate_animations_state :: proc(
    julia_service: ^julia.Julia_Runtime_Service,
    settings: ^Euclid_Run_Settings) -> ^Euclid_General_State {

    particle_system := new(Particle_System)
    particle_system^.use_max_dust_particles = settings^.dust_particle_max

    point_system_parts: Session_Point_System
    make_point_system(&point_system_parts)

    state := new(Euclid_General_State)
    state^.saved_context = context
    state^.julia_runtime_service = julia_service
    state^.iso_scale = make_iso_scale()
    state^.draw_surface = make_drawing_surface()
    state^.point_system = point_system_parts.point_system
    state^.particle_system = particle_system
    state^.compass = point_system_parts.compass
    state^.pen = point_system_parts.pen
    init_runtime_fields(state, settings)
    state^.simulation_executor = create_simulation_executor(state)

    if !init_state_trace(state, settings) {
        return nil
    }

    return state
}

//   Shut down one runtime session in reverse ownership order.
shutdown_runtime_session :: proc(session: Euclid_Runtime_Session) {
    if session.state == nil || session.julia_service == nil {
        return
    }

    trace_exit_code := trace.shutdown_trace_and_exit_code(&session.state^.trace_state)
    destroy_simulation_executor(session.state^.simulation_executor)
    session.state^.simulation_executor = nil
    shutdown_julia_runtime(session.state, session.julia_service)
    free_animations_state(session.state)
    if trace_exit_code != 0 {
        runtime.exit(trace_exit_code)
    }
}
