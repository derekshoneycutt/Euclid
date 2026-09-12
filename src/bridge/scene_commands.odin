package bridge

import "../core"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"

// Scene commands isolate asynchronous Julia callbacks from canonical display state.
// The Julia owner thread writes one bounded batch while the display thread reads an
// immutable query snapshot. The display thread validates the entire completed batch
// before applying any command, so invalid or overflowed batches cannot partially commit.

SCENE_COMMAND_BATCH_CAPACITY :: core.SCENE_COMMAND_BATCH_CAPACITY

//   Per-kind validator shape: report whether one command is valid against state.
Scene_Command_Validator :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool

//   Dispatch table mapping each scene command kind to its validator. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_VALIDATORS :: [Scene_Command_Kind]Scene_Command_Validator{
    .Set_Shape_Position = validate_command_shape_transform,
    .Set_Shape_Color = validate_command_shape_style,
    .Set_Shape_Active_Color = validate_command_shape_style,
    .Set_Shape_Brush = validate_command_shape_style,
    .Set_Shape_Offset = validate_command_shape_style,
    .Set_Shape_Visible = validate_command_shape_style,
    .Set_Shape_Active_Feature = validate_command_shape_active_feature,
    .Set_Tool_Position = validate_command_shape_transform,
    .Set_Tool_Lock = validate_command_tool_lock,
    .Set_Drawing_Sound_Enabled = validate_command_noop,
    .Simulate_Drawing_Sound = validate_command_noop,
    .Emit_Trailing_Particle = validate_command_noop,
    .Emit_Flicker_Particle = validate_command_noop,
    .Notify_Animation_Cycle_Boundary = validate_command_noop,
}

//   Per-kind applier shape: apply one validated command against canonical state.
Scene_Command_Applier :: #type proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command)

//   Dispatch table mapping each scene command kind to its applier. The enum key
//   makes the table exhaustive at compile time.
SCENE_COMMAND_APPLIERS :: [Scene_Command_Kind]Scene_Command_Applier{
    .Set_Shape_Position = apply_set_shape_position,
    .Set_Shape_Color = apply_set_shape_color,
    .Set_Shape_Active_Color = apply_set_shape_active_color,
    .Set_Shape_Brush = apply_set_shape_brush,
    .Set_Shape_Offset = apply_set_shape_offset,
    .Set_Shape_Visible = apply_set_shape_visible,
    .Set_Shape_Active_Feature = apply_set_shape_active_feature,
    .Set_Tool_Position = apply_set_tool_position,
    .Set_Tool_Lock = apply_set_tool_lock,
    .Set_Drawing_Sound_Enabled = apply_set_drawing_sound_enabled,
    .Simulate_Drawing_Sound = apply_simulate_drawing_sound,
    .Emit_Trailing_Particle = apply_emit_trailing_particle,
    .Emit_Flicker_Particle = apply_emit_flicker_particle,
    .Notify_Animation_Cycle_Boundary = apply_notify_animation_cycle_boundary,
}

SCENE_COMMAND_EVIDENCE_KINDS :: [Scene_Command_Kind]evidence_trace.Kind{
    .Set_Shape_Position = .Point_Position_Committed,
    .Set_Shape_Color = .Point_Style_Committed,
    .Set_Shape_Active_Color = .Point_Style_Committed,
    .Set_Shape_Brush = .Point_Style_Committed,
    .Set_Shape_Offset = .Point_Style_Committed,
    .Set_Shape_Visible = .Point_Visibility_Committed,
    .Set_Shape_Active_Feature = .Point_Style_Committed,
    .Set_Tool_Position = .Point_Position_Committed,
    .Set_Tool_Lock = .Point_Position_Committed,
    .Emit_Trailing_Particle = .Particle_Emission_Committed,
    .Emit_Flicker_Particle = .Particle_Emission_Committed,
    .Set_Drawing_Sound_Enabled = .Unknown,
    .Simulate_Drawing_Sound = .Unknown,
    .Notify_Animation_Cycle_Boundary = .Unknown,
}

// Core owns these data shapes because they are referenced by Euclid_General_State.
// Bridge owns their capture, validation, and commit behavior.
Scene_Command_Kind :: core.Scene_Command_Kind
Scene_Command :: core.Scene_Command
Scene_Command_Batch :: core.Scene_Command_Batch
Animation_Query_Snapshot :: core.Animation_Query_Snapshot

//   Copy the canonical values a Julia animation may query during one asynchronous tick.
// The snapshot remains worker-owned until that tick completes; callbacks must not read
// concurrently mutating point-system or tool state through another path.
capture_animation_query_snapshot :: proc(
    state: ^core.Euclid_General_State, snapshot: ^Animation_Query_Snapshot) {

    world := state^.shape_world
    if world != nil {
        snapshot^.shapes.registry = world^.registry
        snapshot^.shapes.transforms = world^.transforms
        snapshot^.shapes.render_styles = world^.render_styles
        snapshot^.shapes.active_features = world^.active_features
        snapshot^.shapes.geometries = world^.geometries
        snapshot^.shapes.labels = world^.labels
        snapshot^.shapes.label_store = world^.label_store
    }
    snapshot^.animation_values_valid =
        core.animation_value_store_pack(
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

    batch^ = Scene_Command_Batch{animation = state^.julia_interface^.current_animation}
    state^.scene_command_batch_target = batch
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
    command^ = Scene_Command{kind = kind}
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

//   Capture a scalar-only scene command such as simulated drawing-sound intensity.
capture_scalar_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, scalar: f32) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.scalar = scalar
    }
    return captured
}

//   Capture a boolean-only scene command such as drawing-sound enablement.
capture_flag_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind, flag: bool) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.flag = flag
    }
    return captured
}

//   Capture one particle emission with the position and color observed by Julia.
capture_particle_command :: proc "contextless" (
    state: ^core.Euclid_General_State, kind: Scene_Command_Kind,
    position: core.Vector3, color: Bridge_Color) -> bool {

    command, captured := append_scene_command(state, kind)
    if command != nil {
        command^.position = position
        command^.color = color
    }
    return captured
}

//   Check a command point index against the initialized canonical point span.
// Resolve one packed command identity against the current canonical world.
validate_command_shape_entity :: proc(
    state: ^core.Euclid_General_State,
    command: ^Scene_Command) -> (core.Shape_Entity, bool) {
    return bridge_shape_resolve(state, command^.entity)
}

// Validate one packed command target that requires a transform component.
validate_command_shape_transform :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && core.shape_component_contains(
        &state^.shape_world^.transforms, &state^.shape_world^.registry, entity)
}

// Validate one packed command target that requires a render-style component.
validate_command_shape_style :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && core.shape_component_contains(
        &state^.shape_world^.render_styles, &state^.shape_world^.registry, entity)
}

// Validate one packed command target that requires an active-feature component.
validate_command_shape_active_feature :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    return found && core.shape_component_contains(
        &state^.shape_world^.active_features, &state^.shape_world^.registry, entity)
}

// Validate one packed tool target whose direct snap constraint must exist.
validate_command_tool_lock :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := validate_command_shape_entity(state, command)
    if !found {return false}
    _, constraint_found := tool_lock_constraint(state, entity)
    return constraint_found
}

//   Validate a command with no state dependency (always valid).
validate_command_noop :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    return true
}

//   Report whether a batch is structurally usable before per-command validation.
// Rejects nil inputs, stale animation identity, truncated lists, and overflow.
scene_command_batch_wellformed :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if state == nil || batch == nil || batch^.overflowed ||
        state^.julia_interface == nil {
        return false
    }
    if batch^.command_count < 0 || batch^.command_count > len(batch^.commands) {
        return false
    }
    return batch^.animation == state^.julia_interface^.current_animation
}

// Apply one validated packed-entity transform mutation.
apply_set_shape_position :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_position(state, command^.entity, command^.position)
}

// Apply one packed tool transform mutation with its owner-side effects.
apply_set_tool_position :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_tool_position(state, core.shape_entity_unpack(command^.entity),
        command^.position, command^.flag)
}

// Apply one packed tool snap-lock mutation.
apply_set_tool_lock :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_tool_lock(state, core.shape_entity_unpack(command^.entity),
        command^.position, command^.flag, command^.integer != 0)
}

// Apply one validated packed-entity color mutation.
apply_set_shape_color :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_color(state, command^.entity, command^.color)
}

// Apply one validated packed-entity active-color mutation.
apply_set_shape_active_color :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_active_color(state, command^.entity, command^.color)
}

// Apply one validated packed-entity brush mutation.
apply_set_shape_brush :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_brush_size(state, command^.entity, command^.scalar)
}

// Apply one validated packed-entity offset mutation.
apply_set_shape_offset :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_offset(state, command^.entity, command^.scalar)
}

// Apply one validated packed-entity visibility mutation.
apply_set_shape_visible :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_visible(state, command^.entity, u8(command^.flag))
}

// Apply one validated packed-entity active-feature mutation.
apply_set_shape_active_feature :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    _ = shape_set_active_feature(state, command^.entity, u16(command^.integer))
}

//   Validate a complete batch against current canonical state without mutation.
// Validation also rejects stale animation identity, truncated point lists, invalid tool
// dependencies, and any prior capture overflow. Commit must remain all-or-nothing.
validate_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !scene_command_batch_wellformed(state, batch) {
        return false
    }
    if core.animation_value_store_validate_pending(
        &state^.animation_values,
        state^.animation_values.generation,
        &batch^.animation_value_writes) != .Ok {
        return false
    }

    validators := SCENE_COMMAND_VALIDATORS
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        validator := validators[command^.kind]
        if validator == nil || !validator(state, command) {
            return false
        }
    }
    return true
}

//   Apply one set-drawing-sound-enabled command.
apply_set_drawing_sound_enabled :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    set_drawing_sound_enabled(state, command^.flag)
}

//   Apply one simulate-drawing-sound command.
apply_simulate_drawing_sound :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    simulate_drawing_sound(state, command^.scalar)
}

//   Apply one emit-trailing-particle command and record its emission.
apply_emit_trailing_particle :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    emit_trailing_particle(state, command^.position, command^.color)
}

//   Apply one emit-flicker-particle command and record its emission.
apply_emit_flicker_particle :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    emit_flicker_particle(state, command^.position, command^.color)
}

//   Apply one animation-cycle-boundary notification command.
apply_notify_animation_cycle_boundary :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    notify_animation_cycle_boundary_local(state)
}

//   Validate and apply one completed batch in original callback order.
// This procedure runs on the display thread at the fixed-step boundary; commands may
// invoke canonical helpers that emit particles or update audio and tool state.
commit_scene_command_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {

    if !validate_scene_command_batch(state, batch) {
        record_scene_batch_evidence(state, .Scene_Batch_Rejected, true)
        return false
    }
    if core.animation_value_store_apply_pending(
        &state^.animation_values,
        state^.animation_values.generation,
        &batch^.animation_value_writes) != .Ok {
        record_scene_batch_evidence(state, .Scene_Batch_Rejected, true)
        return false
    }

    appliers := SCENE_COMMAND_APPLIERS
    for command_index in 0..<batch^.command_count {
        command := &batch^.commands[command_index]
        applier := appliers[command^.kind]
        if applier != nil {
            applier(state, command)
            record_scene_command_evidence(state, command)
        }
    }
    record_scene_batch_evidence(state, .Scene_Batch_Committed, false)
    return true
}

//   Record one scene-batch outcome using the current animation tick identity.
record_scene_batch_evidence :: proc(
    state: ^core.Euclid_General_State, kind: evidence_trace.Kind,
    failed: bool) {
    service := state^.julia_runtime_service
    flags: evidence_trace.Flags = {.Required}
    if failed {
        flags += {.Failure}
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Transport,
            kind = kind,
            correlation_kind = .Scene_Batch,
            correlation = service != nil ? service^.animation_tick_sequence : 0,
            generation = service != nil ? service^.animation_generation : 0,
            tick = state^.fixed_step,
            flags = flags,
        })
}

//   Select compact typed evidence for one committed scene command.
scene_command_evidence :: proc(
    command: ^Scene_Command) -> (evidence_trace.Kind, evidence_trace.Event_Payload) {
    evidence_kinds := SCENE_COMMAND_EVIDENCE_KINDS
    kind := evidence_kinds[command^.kind]
    payload: evidence_trace.Event_Payload
    #partial switch command^.kind {
    case .Emit_Trailing_Particle, .Emit_Flicker_Particle:
        payload.counts.first = command^.kind == .Emit_Trailing_Particle ? 1 : 10
    case:
    }
    return kind, payload
}

//   Record one committed scene command using compact kind-specific payload fields.
record_scene_command_evidence :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    kind, payload := scene_command_evidence(command)
    if kind == .Unknown {
        return
    }
    service := state^.julia_runtime_service
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = kind,
            correlation_kind = .Scene_Batch,
            correlation = service != nil ? service^.animation_tick_sequence : 0,
            generation = service != nil ? service^.animation_generation : 0,
            tick = state^.fixed_step,
            payload = payload,
        })
}