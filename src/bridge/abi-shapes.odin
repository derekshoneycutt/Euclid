package bridge

import "../core"
import "../shapes"

import rl "vendor:raylib"

// Group immutable component sources selected for one bridge query.
Bridge_Shape_Query_Source :: struct {
    registry: ^core.Shape_Registry,
    transforms: ^core.Shape_Component_Set(core.Shape_Transform),
    render_styles: ^core.Shape_Component_Set(core.Shape_Render_Style),
    active_features: ^core.Shape_Component_Set(core.Shape_Active_Feature),
    geometries: ^core.Shape_Component_Set(core.Shape_Geometry),
    labels: ^core.Shape_Component_Set(core.Shape_Label),
    label_store: ^core.Shape_Label_Store,
}

// Map canonical world outcomes to stable bridge status values.
bridge_shape_status :: proc(status: core.Shape_World_Status) -> i32 {
    switch status {
    case .Ok: return BRIDGE_STATUS_OK
    case .Invalid_Argument: return BRIDGE_STATUS_INVALID_ARGUMENT
    case .Illegal_State, .Already_Present: return BRIDGE_STATUS_ILLEGAL_STATE
    case .Not_Found: return BRIDGE_STATUS_NOT_FOUND
    case .Out_Of_Capacity: return BRIDGE_STATUS_OUT_OF_CAPACITY
    case .Invalid_Utf8: return BRIDGE_STATUS_INVALID_UTF8
    case .Unsupported_Mime: return BRIDGE_STATUS_UNSUPPORTED_MIME
    }
    return BRIDGE_STATUS_INVALID_ARGUMENT
}

// Resolve the authoritative canonical world owned by one runtime state.
bridge_shape_world :: proc(state: ^core.Euclid_General_State) -> ^core.Shape_World {
    if state == nil {
        return nil
    }
    return state.shape_world
}

// Decode and validate one packed entity against the authoritative registry.
bridge_shape_resolve :: proc(
    state: ^core.Euclid_General_State,
    packed: u64) -> (core.Shape_Entity, bool) {
    world := bridge_shape_world(state)
    entity := core.shape_entity_unpack(packed)
    return entity, world != nil && core.shape_registry_resolves(&world.registry, entity)
}

// Select worker-owned projections during capture and canonical state otherwise.
bridge_shape_query_source :: proc(
    state: ^core.Euclid_General_State) -> (Bridge_Shape_Query_Source, bool) {
    snapshot := active_animation_query_snapshot(state)
    if snapshot != nil {
        shapes := &snapshot.shapes
        return {&shapes.registry, &shapes.transforms, &shapes.render_styles,
            &shapes.active_features, &shapes.geometries, &shapes.labels,
            &shapes.label_store}, true
    }
    world := bridge_shape_world(state)
    if world == nil {
        return {}, false
    }
    return {&world.registry, &world.transforms, &world.render_styles,
        &world.active_features, &world.geometries, &world.labels,
        &world.label_store}, true
}

// Convert ABI presentation values into canonical world construction style.
bridge_shape_style :: proc(style: Bridge_Shape_Style) -> shapes.Shape_Style {
    return {color = rl.Color{style.color.r, style.color.g,
        style.color.b, style.color.a}, brush_size = style.brush_size}
}

// Pack one standalone entity constructor result for ABI return.
bridge_shape_entity_result :: proc(
    entity: core.Shape_Entity,
    status: core.Shape_World_Status) -> Bridge_Shape_Entity_Result {
    return {bridge_shape_status(status), core.shape_entity_pack(entity)}
}

// Create one standalone transform-backed point in the canonical world.
@(export)
shape_create_point :: proc "c" (
    state: ^core.Euclid_General_State,
    input: Bridge_Positioned_Shape_Input) -> Bridge_Shape_Entity_Result {
    context = state.saved_context
    handle, status := shapes.world_create_point(
        state.shape_world, input.position, bridge_shape_style(input.style))
    return bridge_shape_entity_result(handle.entity, status)
}

// Create one null-terminated UTF-8 plain-text label with transactional source copying.
@(export)
shape_create_label :: proc "c" (
    state: ^core.Euclid_General_State,
    source: cstring,
    mime: i32,
    input: Bridge_Positioned_Shape_Input) -> Bridge_Shape_Entity_Result {
    context = state.saved_context
    if source == nil || mime < 0 ||
        mime > i32(core.Shape_Text_Mime.Text_Latex) {
        return {BRIDGE_STATUS_INVALID_ARGUMENT, 0}
    }
    text := string(source)
    handle, status := shapes.world_create_label(state.shape_world, {
        source = text, mime = core.Shape_Text_Mime(mime),
        position = input.position, style = bridge_shape_style(input.style)})
    return bridge_shape_entity_result(handle.entity, status)
}

// Create one line with direct packed endpoint handles.
@(export)
shape_create_line :: proc "c" (
    state: ^core.Euclid_General_State,
    first, second: core.Vector3,
    style: Bridge_Shape_Style) -> Bridge_Shape_Line_Result {
    context = state.saved_context
    handle, status := shapes.world_create_line(
        state.shape_world, first, second, bridge_shape_style(style))
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape),
        core.shape_entity_pack(handle.first), core.shape_entity_pack(handle.second)}
}

// Create one outlined arc with direct packed transform handles.
@(export)
shape_create_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3,
    arc: core.Bridge_Arc_Geometry,
    style: Bridge_Shape_Style) -> Bridge_Shape_Arc_Result {
    context = state.saved_context
    handle, status := shapes.world_create_arc(state.shape_world, {
        center = center, radius = arc.radius, start_theta = arc.start_theta,
        end_theta = arc.end_theta, style = bridge_shape_style(style)})
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape),
        core.shape_entity_pack(handle.center), core.shape_entity_pack(handle.start),
        core.shape_entity_pack(handle.finish)}
}

// Create one filled arc with direct packed transform handles.
@(export)
shape_create_filled_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3,
    arc: core.Bridge_Arc_Geometry,
    style: Bridge_Shape_Style) -> Bridge_Shape_Arc_Result {
    context = state.saved_context
    handle, status := shapes.world_create_filled_arc(state.shape_world, {
        center = center, radius = arc.radius, start_theta = arc.start_theta,
        end_theta = arc.end_theta, style = bridge_shape_style(style)})
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape),
        core.shape_entity_pack(handle.center), core.shape_entity_pack(handle.start),
        core.shape_entity_pack(handle.finish)}
}

// Create one triangle with direct packed ordered vertex handles.
@(export)
shape_create_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: [3]core.Vector3,
    style: Bridge_Shape_Style) -> Bridge_Shape_Triangle_Result {
    context = state.saved_context
    handle, status := shapes.world_create_triangle(
        state.shape_world, vertices, bridge_shape_style(style))
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape),
        core.shape_entity_pack(handle.first), core.shape_entity_pack(handle.second),
        core.shape_entity_pack(handle.third)}
}

// Create one square with direct packed ordered vertex handles.
@(export)
shape_create_square :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: core.Bridge_Square_Vertices,
    style: Bridge_Shape_Style) -> Bridge_Shape_Square_Result {
    context = state.saved_context
    handle, status := shapes.world_create_square(
        state.shape_world, vertices.vertices, bridge_shape_style(style))
    packed: [4]u64
    for entity, index in handle.vertices {
        packed[index] = core.shape_entity_pack(entity)
    }
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape), packed}
}

// Create one pentagon with direct packed ordered vertex handles.
@(export)
shape_create_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: core.Bridge_Pentagon_Vertices,
    style: Bridge_Shape_Style) -> Bridge_Shape_Pentagon_Result {
    context = state.saved_context
    handle, status := shapes.world_create_pentagon(
        state.shape_world, vertices.vertices, bridge_shape_style(style))
    packed: [5]u64
    for entity, index in handle.vertices {
        packed[index] = core.shape_entity_pack(entity)
    }
    return {bridge_shape_status(status), core.shape_entity_pack(handle.shape), packed}
}

// Project one entity's transform and render style into a bridge view.
shape_view_project_presentation :: proc(
    source: ^Bridge_Shape_Query_Source,
    entity: core.Shape_Entity,
    view: ^Bridge_Shape_View) {
    transform, has_transform := core.shape_component_get(
        source^.transforms, source^.registry, entity)
    if has_transform {
        view^.has_transform = 1
        view^.position = transform.position
    }
    style, has_style := core.shape_component_get(
        source^.render_styles, source^.registry, entity)
    if has_style {
        view^.has_style = 1
        view^.visible = u8(style.visible)
        view^.color = {style.color.r, style.color.g, style.color.b, style.color.a}
        active_color, has_active_color := style.active_color.?
        view^.has_active_color = u8(has_active_color)
        view^.active_color = {active_color.r, active_color.g,
            active_color.b, active_color.a}
        view^.brush_size = style.brush_size
        view^.offset = style.offset
    }
}

// Project one entity's semantic components into a bridge view.
shape_view_project_semantics :: proc(
    source: ^Bridge_Shape_Query_Source,
    entity: core.Shape_Entity,
    view: ^Bridge_Shape_View) {
    feature, has_feature := core.shape_component_get(
        source^.active_features, source^.registry, entity)
    if has_feature {
        view^.has_active_feature = 1
        view^.active_feature = feature.index
    }
    geometry, has_geometry := core.shape_component_get(
        source^.geometries, source^.registry, entity)
    if has_geometry {
        view^.kind = i32(geometry.kind)
    }
}

// Resolve one packed entity into pointer-free component projections.
@(export)
shape_get_view :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> Bridge_Shape_View {
    context = state.saved_context
    source, available := bridge_shape_query_source(state)
    entity := core.shape_entity_unpack(packed)
    if !available || !core.shape_registry_resolves(source.registry, entity) {
        return {status = BRIDGE_STATUS_NOT_FOUND, entity = packed}
    }
    view := Bridge_Shape_View{status = BRIDGE_STATUS_OK, entity = packed, kind = -1}
    shape_view_project_presentation(&source, entity, &view)
    shape_view_project_semantics(&source, entity, &view)
    return view
}

// Copy one label's immutable source bytes from the active query projection.
@(export)
shape_copy_label_source :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    destination: ^u8,
    capacity: i32) -> Bridge_Label_Copy_Result {
    context = state.saved_context
    if destination == nil || capacity < 0 {
        return {status = BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    source, available := bridge_shape_query_source(state)
    entity := core.shape_entity_unpack(packed)
    if !available || !core.shape_registry_resolves(source.registry, entity) {
        return {status = BRIDGE_STATUS_NOT_FOUND}
    }
    label, found := core.shape_component_get(source.labels, source.registry, entity)
    if !found {return {status = BRIDGE_STATUS_NOT_FOUND}}
    text, valid := core.shape_label_source(source.label_store, label^)
    if !valid || len(text) > int(capacity) {
        return {status = BRIDGE_STATUS_OUT_OF_CAPACITY}
    }
    destination_bytes := cast([^]u8)destination
    copy(destination_bytes[:len(text)], transmute([]u8)text)
    return {BRIDGE_STATUS_OK, i32(len(text)), i32(label.mime)}
}

// Set one live transform position by packed entity identity.
@(export)
shape_set_position :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    position: core.Vector3) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(state, .Set_Shape_Position, packed)
    if command != nil {
        command.position = position
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    transform, has_transform := core.shape_component_get_mut(
        &state.shape_world.transforms, &state.shape_world.registry, entity)
    if !has_transform {return BRIDGE_STATUS_NOT_FOUND}
    transform.position = position
    return BRIDGE_STATUS_OK
}

// Set one live render style's visibility by packed entity identity.
@(export)
shape_set_visible :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    visible: u8) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(state, .Set_Shape_Visible, packed)
    if command != nil {
        command.flag = visible != 0
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := core.shape_component_get_mut(
        &state.shape_world.render_styles, &state.shape_world.registry, entity)
    if !has_style {return BRIDGE_STATUS_NOT_FOUND}
    style.visible = visible != 0
    return BRIDGE_STATUS_OK
}

// Set one live render style's color by packed entity identity.
@(export)
shape_set_color :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    color: Bridge_Color) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(state, .Set_Shape_Color, packed)
    if command != nil {
        command.color = color
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := core.shape_component_get_mut(
        &state.shape_world.render_styles, &state.shape_world.registry, entity)
    if !has_style {return BRIDGE_STATUS_NOT_FOUND}
    style.color = {color.r, color.g, color.b, color.a}
    return BRIDGE_STATUS_OK
}

// Set one live render style's optional active color by packed entity identity.
@(export)
shape_set_active_color :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    color: Bridge_Color) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(
        state, .Set_Shape_Active_Color, packed)
    if command != nil {
        command.color = color
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := core.shape_component_get_mut(
        &state.shape_world.render_styles, &state.shape_world.registry, entity)
    if !has_style {return BRIDGE_STATUS_NOT_FOUND}
    style.active_color = rl.Color{color.r, color.g, color.b, color.a}
    return BRIDGE_STATUS_OK
}

// Set one live render style's brush size by packed entity identity.
@(export)
shape_set_brush_size :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    brush_size: f32) -> i32 {
    context = state.saved_context
    if brush_size < 0 {return BRIDGE_STATUS_INVALID_ARGUMENT}
    command, captured := capture_shape_command(state, .Set_Shape_Brush, packed)
    if command != nil {
        command.scalar = brush_size
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := core.shape_component_get_mut(
        &state.shape_world.render_styles, &state.shape_world.registry, entity)
    if !has_style {return BRIDGE_STATUS_NOT_FOUND}
    style.brush_size = brush_size
    return BRIDGE_STATUS_OK
}

// Set one live render style's presentation offset by packed entity identity.
@(export)
shape_set_offset :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    offset: f32) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(state, .Set_Shape_Offset, packed)
    if command != nil {
        command.scalar = offset
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    style, has_style := core.shape_component_get_mut(
        &state.shape_world.render_styles, &state.shape_world.registry, entity)
    if !has_style {return BRIDGE_STATUS_NOT_FOUND}
    style.offset = offset
    return BRIDGE_STATUS_OK
}

// Set one live optional active feature by packed entity identity.
@(export)
shape_set_active_feature :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    active_feature: u16) -> i32 {
    context = state.saved_context
    command, captured := capture_shape_command(
        state, .Set_Shape_Active_Feature, packed)
    if command != nil {
        command.integer = int(active_feature)
    }
    if captured {return BRIDGE_STATUS_OK}
    entity, found := bridge_shape_resolve(state, packed)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    feature, has_feature := core.shape_component_get_mut(
        &state.shape_world.active_features, &state.shape_world.registry, entity)
    if !has_feature {return BRIDGE_STATUS_NOT_FOUND}
    feature.index = active_feature
    return BRIDGE_STATUS_OK
}