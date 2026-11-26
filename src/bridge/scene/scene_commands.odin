package bridge_scene

import bridgemodel "../model"
import animation_model "../../core/animation"
import operations "../../animation/operations"
import modifier "../../animation"
import "../../core"
import evidence_trace "../../evidence/trace"

// Hold one resolved canonical Cycloid line.
Command_Cycloid_Line :: struct {
    first: Vector3,
    second: Vector3,
}

// Scene commands isolate asynchronous Julia callbacks from canonical display state.
// The Julia owner thread writes one bounded batch while the display thread reads an
// immutable query snapshot. The display thread validates the entire completed batch
// before applying any command, so invalid or overflowed batches cannot partially commit.

SCENE_COMMAND_BATCH_CAPACITY :: bridgemodel.SCENE_COMMAND_BATCH_CAPACITY

REQUESTS_CAPACITY :: operations.ACTIVE_OPERATION_GROUP_TARGET_CAPACITY + 1

//   Per-kind validator shape: report whether one command is valid against state.
Scene_Command_Validator :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool

//   Dispatch table mapping each scene command kind to its validator. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_VALIDATORS :: [Scene_Command_Kind]Scene_Command_Validator{
    .Set_Shape_Position = validate_command_shape_transform,
    .Set_Shape_Orientation = validate_command_shape_orientation,
    .Apply_Native_Modifier = validate_native_modifier_marker,
    .Submit_Active_Operation = nil,
    .Set_Shape_Color = validate_command_shape_style,
    .Set_Shape_Active_Color = validate_command_shape_style,
    .Set_Shape_Brush = validate_command_shape_style,
    .Set_Shape_Arc = validate_command_shape_arc,
    .Set_Shape_Trochoid = validate_command_shape_trochoid,
    .Set_Shape_Trochoid_Frontier = validate_command_shape_trochoid_frontier,
    .Set_Trochoid_Tool = validate_command_trochoid_tool,
    .Set_Trochoid_Tool_Parameter = validate_command_trochoid_tool_parameter,
    .Set_Shape_Cycloid = validate_command_shape_cycloid,
    .Set_Shape_Cycloid_Frontier = validate_command_shape_cycloid_frontier,
    .Set_Cycloid_Tool_Line = validate_command_cycloid_tool_line,
    .Set_Cycloid_Tool = validate_command_cycloid_tool,
    .Set_Cycloid_Tool_Parameter = validate_command_cycloid_tool_parameter,
    .Set_Shape_Parabola = validate_command_shape_parabola,
    .Set_Shape_Parabola_Frontier = validate_command_shape_parabola_frontier,
    .Set_Shape_Hyperbola = validate_command_shape_hyperbola,
    .Set_Shape_Hyperbola_Frontier = validate_command_shape_hyperbola_frontier,
    .Set_Parabola_Tool_Geometry = validate_command_parabola_tool,
    .Set_Parabola_Tool_Parameter = validate_command_parabola_tool_parameter,
    .Set_Parabola_Tool_Active = validate_command_parabola_tool_active,
    .Set_Hyperbola_Tool_Geometry = validate_command_hyperbola_tool,
    .Set_Hyperbola_Tool_Parameter = validate_command_hyperbola_tool_parameter,
    .Set_Hyperbola_Tool_Active = validate_command_hyperbola_tool_active,
    .Set_Shape_Visible = validate_command_shape_style,
    .Set_Shape_Active_Feature = validate_command_shape_active_feature,
    .Set_Tool_Position = validate_command_shape_transform,
    .Set_Tool_Lock = validate_command_tool_lock,
    .Emit_Trailing_Particle = validate_command_noop,
    .Reveal_Label = validate_command_animation_reveal,
    .Reveal_Region = validate_command_animation_reveal,
    .Reveal_Sweep = validate_command_animation_reveal,
    .Notify_Animation_Cycle_Boundary = validate_command_noop,
}

//   Per-kind applier shape: apply one validated command against canonical state.
Scene_Command_Applier :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command)

//   Dispatch table mapping each scene command kind to its applier. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_APPLIERS :: [Scene_Command_Kind]Scene_Command_Applier{
    .Set_Shape_Position = apply_set_shape_position,
    .Set_Shape_Orientation = apply_set_shape_orientation,
    .Apply_Native_Modifier = nil,
    .Submit_Active_Operation = nil,
    .Set_Shape_Color = apply_set_shape_color,
    .Set_Shape_Active_Color = apply_set_shape_active_color,
    .Set_Shape_Brush = apply_set_shape_brush,
    .Set_Shape_Arc = apply_set_shape_arc,
    .Set_Shape_Trochoid = apply_set_shape_trochoid,
    .Set_Shape_Trochoid_Frontier = apply_set_shape_trochoid_frontier,
    .Set_Trochoid_Tool = apply_set_trochoid_tool,
    .Set_Trochoid_Tool_Parameter = apply_set_trochoid_tool_parameter,
    .Set_Shape_Cycloid = apply_set_shape_cycloid,
    .Set_Shape_Cycloid_Frontier = apply_set_shape_cycloid_frontier,
    .Set_Cycloid_Tool_Line = apply_set_cycloid_tool_line,
    .Set_Cycloid_Tool = apply_set_cycloid_tool,
    .Set_Cycloid_Tool_Parameter = apply_set_cycloid_tool_parameter,
    .Set_Shape_Parabola = apply_set_shape_parabola,
    .Set_Shape_Parabola_Frontier = apply_set_shape_parabola_frontier,
    .Set_Shape_Hyperbola = apply_set_shape_hyperbola,
    .Set_Shape_Hyperbola_Frontier = apply_set_shape_hyperbola_frontier,
    .Set_Parabola_Tool_Geometry = apply_set_parabola_tool,
    .Set_Parabola_Tool_Parameter = apply_set_parabola_tool_parameter,
    .Set_Parabola_Tool_Active = apply_set_parabola_tool_active,
    .Set_Hyperbola_Tool_Geometry = apply_set_hyperbola_tool,
    .Set_Hyperbola_Tool_Parameter = apply_set_hyperbola_tool_parameter,
    .Set_Hyperbola_Tool_Active = apply_set_hyperbola_tool_active,
    .Set_Shape_Visible = apply_set_shape_visible,
    .Set_Shape_Active_Feature = apply_set_shape_active_feature,
    .Set_Tool_Position = apply_set_tool_position,
    .Set_Tool_Lock = apply_set_tool_lock,
    .Emit_Trailing_Particle = apply_emit_trailing_particle,
    .Reveal_Label = nil,
    .Reveal_Region = nil,
    .Reveal_Sweep = nil,
    .Notify_Animation_Cycle_Boundary = apply_notify_animation_cycle_boundary,
}

SCENE_COMMAND_EVIDENCE_KINDS :: [Scene_Command_Kind]evidence_trace.Kind{
    .Set_Shape_Position = .Point_Position_Committed,
    .Set_Shape_Orientation = .Shape_Orientation_Committed,
    .Apply_Native_Modifier = .Unknown,
    .Submit_Active_Operation = .Unknown,
    .Set_Shape_Color = .Point_Style_Committed,
    .Set_Shape_Active_Color = .Point_Style_Committed,
    .Set_Shape_Brush = .Point_Style_Committed,
    .Set_Shape_Arc = .Arc_Geometry_Committed,
    .Set_Shape_Trochoid = .Trochoid_Geometry_Committed,
    .Set_Shape_Trochoid_Frontier = .Trochoid_Frontier_Committed,
    .Set_Trochoid_Tool = .Trochoid_Tool_Geometry_Committed,
    .Set_Trochoid_Tool_Parameter = .Trochoid_Tool_Parameter_Committed,
    .Set_Shape_Cycloid = .Cycloid_Geometry_Committed,
    .Set_Shape_Cycloid_Frontier = .Cycloid_Frontier_Committed,
    .Set_Cycloid_Tool_Line = .Cycloid_Tool_Geometry_Committed,
    .Set_Cycloid_Tool = .Cycloid_Tool_Geometry_Committed,
    .Set_Cycloid_Tool_Parameter = .Cycloid_Tool_Parameter_Committed,
    .Set_Shape_Parabola = .Parabola_Geometry_Committed,
    .Set_Shape_Parabola_Frontier = .Parabola_Frontier_Committed,
    .Set_Shape_Hyperbola = .Hyperbola_Geometry_Committed,
    .Set_Shape_Hyperbola_Frontier = .Hyperbola_Frontier_Committed,
    .Set_Parabola_Tool_Geometry = .Parabola_Tool_Geometry_Committed,
    .Set_Parabola_Tool_Parameter = .Parabola_Tool_Parameter_Committed,
    .Set_Parabola_Tool_Active = .Point_Style_Committed,
    .Set_Hyperbola_Tool_Geometry = .Hyperbola_Tool_Geometry_Committed,
    .Set_Hyperbola_Tool_Parameter = .Hyperbola_Tool_Parameter_Committed,
    .Set_Hyperbola_Tool_Active = .Point_Style_Committed,
    .Set_Shape_Visible = .Point_Visibility_Committed,
    .Set_Shape_Active_Feature = .Point_Style_Committed,
    .Set_Tool_Position = .Point_Position_Committed,
    .Set_Tool_Lock = .Point_Position_Committed,
    .Emit_Trailing_Particle = .Particle_Emission_Committed,
    .Reveal_Label = .Unknown,
    .Reveal_Region = .Unknown,
    .Reveal_Sweep = .Unknown,
    .Notify_Animation_Cycle_Boundary = .Unknown,
}

// Core owns these data shapes because they are referenced by Euclid_General_State.
// Bridge owns their capture, validation, and commit behavior.
Scene_Command_Kind :: bridgemodel.Scene_Command_Kind
Scene_Command :: bridgemodel.Scene_Command
Scene_Command_Batch :: bridgemodel.Scene_Command_Batch
Animation_Query_Snapshot :: bridgemodel.Animation_Query_Snapshot

//   Copy the canonical values a Julia animation may query during one asynchronous tick.
// The snapshot remains worker-owned until that tick completes; callbacks must not read
// concurrently mutating point-system or tool state through another path.
capture_animation_query_snapshot :: proc(
    state: ^core.Euclid_General_State, snapshot: ^Animation_Query_Snapshot) {

    if service := state^.julia_runtime_service; service != nil {
        snapshot^.content_specification = service^.active_content_specification
        snapshot^.animation_generation = service^.animation_generation
    }
    world := &state^.shape_world
    snapshot^.shapes.registry = world^.registry
    snapshot^.shapes.transforms = world^.transforms
    snapshot^.shapes.orientations = world^.orientations
    snapshot^.shapes.arcs = world^.arcs
    snapshot^.shapes.trochoids = world^.trochoids
    snapshot^.shapes.trochoid_tools = world^.trochoid_tools
    snapshot^.shapes.cycloids = world^.cycloids
    snapshot^.shapes.cycloid_tools = world^.cycloid_tools
    snapshot^.shapes.parabolas = world^.parabolas
    snapshot^.shapes.hyperbolas = world^.hyperbolas
    snapshot^.shapes.parabola_tools = world^.parabola_tools
    snapshot^.shapes.hyperbola_tools = world^.hyperbola_tools
    snapshot^.shapes.render_styles = world^.render_styles
    snapshot^.shapes.active_features = world^.active_features
    snapshot^.shapes.geometries = world^.geometries
    snapshot^.shapes.labels = world^.labels
    snapshot^.shapes.label_store = world^.label_store
    snapshot^.animation_values_valid =
        animation_model.animation_value_store_pack(
            &state^.animation_values,
            state^.animation_values.generation,
            &snapshot^.animation_values) == .Ok
}

//   Return the worker-owned immutable query snapshot active for the current callback.
// Returns nil outside scene capture; callers must preserve that distinction rather than
// falling back to canonical display state.
active_animation_query_snapshot :: proc "contextless" (
    state: ^core.Euclid_General_State) -> ^Animation_Query_Snapshot {

    return state^.animation_query_snapshot_target
}

//   Reset and attach one worker-owned command batch for the current animation callback.
// The target remains active until end_scene_command_batch and must not outlive its slot.
begin_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) {

    batch^ = Scene_Command_Batch{
        producer = .Julia,
        animation = state^.julia_interface^.current_animation,
    }
    state^.scene_command_batch_target = batch
}

// Attach one display-owned native producer without borrowing Julia callback identity.
begin_native_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch,
    producer_identity: u64 = 1) {
    batch^ = Scene_Command_Batch{
        producer = .Native,
        animation_generation = state^.particle_system.formation.animation_generation,
        tick_sequence = state^.fixed_step + 1,
        animation_progress = state^.particle_system.formation.accepted_progress,
        native_interval_reconcile_julia = true,
        producer_identity = producer_identity,
    }
    state^.scene_command_batch_target = batch
}

// Capture an operation marker and its initial sample at one ordered batch position.
capture_active_operation_submission :: proc(
    state: ^core.Euclid_General_State,
    submission: operations.Active_Operation_Submission_Request) -> bool {
    batch := state^.scene_command_batch_target
    requests: [REQUESTS_CAPACITY]modifier.Modifier_Request
    request_count: int
    if !active_operation_initial_sample_requests(submission, &requests, &request_count) {
        return false
    }
    if batch == nil || batch^.producer != .Julia ||
        batch^.active_operation_submission_count >=
            operations.ACTIVE_OPERATION_SUBMISSIONS_PER_BATCH ||
        batch^.command_count + 1 + request_count > len(batch^.commands) {
        if batch != nil {
            batch^.overflowed = true
        }
        return false
    }
    marker, _ := append_scene_command(state, .Submit_Active_Operation)
    if marker == nil {
        return false
    }
    index := batch^.active_operation_submission_count
    batch^.active_operation_submissions[index].request = submission
    batch^.active_operation_submission_count += 1
    marker^.integer = index
    for request in requests[:request_count] {
        sample, _ := append_scene_command(state, .Apply_Native_Modifier)
        assert(sample != nil)
        sample^.modifier = request
    }
    return true
}

// Expand one copied activation snapshot into its ordered time-zero requests.
active_operation_initial_sample_requests :: proc(
    submission: operations.Active_Operation_Submission_Request,
    requests: ^[REQUESTS_CAPACITY]modifier.Modifier_Request,
    request_count: ^int) -> bool {
    initial := submission.modifier_request
    initial.elapsed = 0
    if submission.group_transform.count > 0 {
        return operations.active_operation_group_sample_requests(
            submission.group_transform, initial, 0, requests, request_count)
    }
    if requests == nil || request_count == nil {
        return false
    }
    if initial.kind == .Cycloid_Sequence ||
        initial.kind == .Trochoid_Sequence {
        samples := modifier.rolling_sequence_samples(initial, 0, 0)
        if samples.count <= 0 || samples.count > REQUESTS_CAPACITY {
            return false
        }
        copy(requests[:], samples.requests[:samples.count])
        request_count^ = samples.count
        return true
    }
    if initial.kind == .Parabola_Sequence ||
        initial.kind == .Hyperbola_Sequence {
        samples := modifier.conic_sequence_samples(initial, 0, 0)
        if samples.count <= 0 || samples.count > REQUESTS_CAPACITY {
            return false
        }
        copy(requests[:], samples.requests[:samples.count])
        request_count^ = samples.count
        return true
    }
    requests[0] = initial
    request_count^ = 1
    return true
}


//   Detach the worker batch after callback capture without mutating canonical scene state.
end_scene_command_batch :: proc(state: ^core.Euclid_General_State) {
    state^.scene_command_batch_target = nil
}


//   Reserve and initialize one command in the active bounded batch.
// Returns captured=true when capture mode handled the operation, including overflow.
// Overflow marks the whole batch invalid and deliberately suppresses direct mutation.
append_scene_command :: proc "contextless" (
    state: ^core.Euclid_General_State,
    kind: Scene_Command_Kind) -> (^Scene_Command, bool) {

    if state^.scene_command_batch_target == nil {
        return nil, false
    }
    batch := state^.scene_command_batch_target
    if batch^.command_count >= len(batch^.commands) {
        batch^.overflowed = true
        return nil, true
    }
    command := &batch^.commands[batch^.command_count]
    command^ = Scene_Command{
        kind = kind,
    }
    batch^.command_count += 1
    return command, true
}

// Capture one packed-entity mutation for display-thread validation and commit.
capture_shape_command :: proc "contextless" (
    state: ^core.Euclid_General_State,
    kind: Scene_Command_Kind,
    entity: u64) -> (^Scene_Command, bool) {
    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.entity = entity
    }
    return command, captured
}

//   Capture one particle emission with the position and color observed by Julia.
capture_particle_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    position: Vector3, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
        command^.color = color
    }
    return captured
}
