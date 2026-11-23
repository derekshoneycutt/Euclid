package bridge_abi

import scene "../scene"
import core "../../core"
import shapemodel "../../shapes/model"

// Create one standalone transform-backed point in the canonical world.
@(export)
shape_create_point :: proc "c" (
    state: ^core.Euclid_General_State,
    input: scene.Bridge_Positioned_Shape_Input) -> scene.Bridge_Shape_Entity_Result {
    return scene.shape_create_point(state, input)
}

// Create one null-terminated UTF-8 plain-text label with transactional source copying.
@(export)
shape_create_label :: proc "c" (
    state: ^core.Euclid_General_State,
    source: cstring,
    mime: i32,
    input: scene.Bridge_Positioned_Shape_Input) -> scene.Bridge_Shape_Entity_Result {
    return scene.shape_create_label(state, source, mime, input)
}

// Create one line with direct packed endpoint handles.
@(export)
shape_create_line :: proc "c" (
    state: ^core.Euclid_General_State,
    first, second: scene.Vector3,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Line_Result {
    return scene.shape_create_line(state, first, second, style)
}

// Create one outlined arc and return its packed host identity.
@(export)
shape_create_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    center: scene.Vector3,
    arc: shapemodel.Bridge_Arc_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Arc_Result {
    return scene.shape_create_arc(state, center, arc, style)
}

// Create one filled arc and return its packed host identity.
@(export)
shape_create_filled_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    center: scene.Vector3,
    arc: shapemodel.Bridge_Arc_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Arc_Result {
    return scene.shape_create_filled_arc(state, center, arc, style)
}

// Create one two-circle filled region and return its direct packed identities.
@(export)
shape_create_circle_region :: proc "c" (
    state: ^core.Euclid_General_State,
    first_center, second_center: scene.Vector3,
    geometry: shapemodel.Bridge_Circle_Region_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Circle_Region_Result {
    return scene.shape_create_circle_region(
        state, first_center, second_center, geometry, style)
}

// Create one outlined trochoid and return its packed host identity.
@(export)
shape_create_trochoid :: proc "c" (
    state: ^core.Euclid_General_State,
    center: scene.Vector3,
    geometry: shapemodel.Bridge_Trochoid_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Trochoid_Result {
    return scene.shape_create_trochoid(state, center, geometry, style)
}

// Create one literal-line cycloid and return its host and endpoint identities.
@(export)
shape_create_cycloid :: proc "c" (
    state: ^core.Euclid_General_State,
    first, second: scene.Vector3,
    geometry: shapemodel.Bridge_Cycloid_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Cycloid_Result {
    return scene.shape_create_cycloid(state, first, second, geometry, style)
}

// Create one analytic parabola with an exact frontier-aware native curve packet.
@(export)
shape_create_parabola :: proc "c" (
    state: ^core.Euclid_General_State,
    position: scene.Vector3,
    geometry: shapemodel.Bridge_Parabola_Geometry,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Parabola_Result {
    return scene.shape_create_parabola(state, position, geometry, style)
}

// Create one analytic hyperbola host owning both branches.
@(export)
shape_create_hyperbola :: proc "c" (
    state: ^core.Euclid_General_State,
    position: scene.Vector3,
    geometry: shapemodel.Bridge_Hyperbola_Geometry,
    style: scene.Bridge_Shape_Style,
    branches: shapemodel.Hyperbola_Branches = .Both) ->
        scene.Bridge_Shape_Hyperbola_Result {
    return scene.shape_create_hyperbola(state, position, geometry, style, branches)
}

// Create one triangle with direct packed ordered vertex handles.
@(export)
shape_create_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: [3]scene.Vector3,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Triangle_Result {
    return scene.shape_create_triangle(state, vertices, style)
}

// Create one square with direct packed ordered vertex handles.
@(export)
shape_create_square :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: shapemodel.Bridge_Square_Vertices,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Square_Result {
    return scene.shape_create_square(state, vertices, style)
}

// Create one pentagon with direct packed ordered vertex handles.
@(export)
shape_create_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    vertices: shapemodel.Bridge_Pentagon_Vertices,
    style: scene.Bridge_Shape_Style) -> scene.Bridge_Shape_Pentagon_Result {
    return scene.shape_create_pentagon(state, vertices, style)
}

// Resolve one packed entity into pointer-free component projections.
@(export)
shape_get_view :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_View {
    return scene.shape_get_view(state, packed)
}

// Return one resolved arc host's complete mutable geometry.
@(export)
shape_get_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Arc_Query_Result {
    return scene.shape_get_arc(state, packed)
}

// Return one resolved trochoid host's complete mutable geometry.
@(export)
shape_get_trochoid :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Trochoid_Query_Result {
    return scene.shape_get_trochoid(state, packed)
}

// Return one resolved cycloid host's endpoint positions and scalar geometry.
@(export)
shape_get_cycloid :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Cycloid_Query_Result {
    return scene.shape_get_cycloid(state, packed)
}

// Return one resolved parabola's complete analytic description.
@(export)
shape_get_parabola :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Parabola_Query_Result {
    return scene.shape_get_parabola(state, packed)
}

// Return one resolved hyperbola's common analytic description.
@(export)
shape_get_hyperbola :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> scene.Bridge_Shape_Hyperbola_Query_Result {
    return scene.shape_get_hyperbola(state, packed)
}

// Set one complete parabola while preserving its prior interpolation sample.
@(export)
shape_set_parabola :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    geometry: shapemodel.Bridge_Parabola_Geometry) -> i32 {
    return scene.shape_set_parabola(state, packed, geometry)
}

// Change one parabola's reveal frontier without replacing its directed domain.
@(export)
shape_set_parabola_frontier :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    parameter: f32) -> i32 {
    return scene.shape_set_parabola_frontier(state, packed, parameter)
}

// Set one complete hyperbola while preserving prior interpolation values.
@(export)
shape_set_hyperbola :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    geometry: shapemodel.Bridge_Hyperbola_Geometry) -> i32 {
    return scene.shape_set_hyperbola(state, packed, geometry)
}

// Advance selected hyperbola ink without replacing the common directed domain.
@(export)
shape_set_hyperbola_frontier :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    parameter: f32) -> i32 {
    return scene.shape_set_hyperbola_frontier(state, packed, parameter)
}

// Set one live transform position by packed entity identity.
@(export)
shape_set_position :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    position: scene.Vector3) -> i32 {
    return scene.shape_set_position(state, packed, position)
}

// Set one live arc's complete mutable geometry by packed host identity.
@(export)
shape_set_arc :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    arc: shapemodel.Bridge_Arc_Geometry) -> i32 {
    return scene.shape_set_arc(state, packed, arc)
}

// Set one live trochoid's complete mutable description.
@(export)
shape_set_trochoid :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    geometry: shapemodel.Bridge_Trochoid_Geometry) -> i32 {
    return scene.shape_set_trochoid(state, packed, geometry)
}

// Set one live trochoid's reveal frontier without changing its complete domain.
@(export)
shape_set_trochoid_frontier :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    frontier: f32) -> i32 {
    return scene.shape_set_trochoid_frontier(state, packed, frontier)
}

// Validate scalar edits against the live rail or the captured transaction's final rail.
@(export)
shape_set_cycloid :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    geometry: shapemodel.Bridge_Cycloid_Geometry) -> i32 {
    return scene.shape_set_cycloid(state, packed, geometry)
}

// Set one live cycloid's reveal frontier without changing its complete domain.
@(export)
shape_set_cycloid_frontier :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    frontier: f32) -> i32 {
    return scene.shape_set_cycloid_frontier(state, packed, frontier)
}

// Set one live render style's visibility by packed entity identity.
@(export)
shape_set_visible :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    visible: u8) -> i32 {
    return scene.shape_set_visible(state, packed, visible)
}

// Capture one authored label reveal for validation at the animation commit boundary.
@(export)
shape_reveal_label :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    duration: f32) -> i32 {
    return scene.shape_reveal_label(state, packed, duration)
}

// Capture one authored filled-region reveal for transactional display validation.
@(export)
shape_reveal_region :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    duration: f32) -> i32 {
    return scene.shape_reveal_region(state, packed, duration)
}

// Capture one authored compass-sector reveal that forms behind the swinging leg.
@(export)
shape_reveal_sweep :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    duration: f32) -> i32 {
    return scene.shape_reveal_sweep(state, packed, duration)
}

// Set one live render style's color by packed entity identity.
@(export)
shape_set_color :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    color: scene.Bridge_Color) -> i32 {
    return scene.shape_set_color(state, packed, color)
}

// Set one live render style's optional active color by packed entity identity.
@(export)
shape_set_active_color :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    color: scene.Bridge_Color) -> i32 {
    return scene.shape_set_active_color(state, packed, color)
}

// Set one live render style's brush size by packed entity identity.
@(export)
shape_set_brush_size :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64,
    brush_size: f32) -> i32 {
    return scene.shape_set_brush_size(state, packed, brush_size)
}
