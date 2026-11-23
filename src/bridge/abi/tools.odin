package bridge_abi

import scene "../scene"
import core "../../core"
import shapemodel "../../shapes/model"

// Enable drawing for the process-global literal-line Cycloid guide.
@(export)
show_cycloid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.show_cycloid_tool(state)
}

// Disable drawing for the process-global literal-line Cycloid guide.
@(export)
hide_cycloid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.hide_cycloid_tool(state)
}

// Atomically move both literal endpoints of the process-global Cycloid guide.
@(export)
set_cycloid_tool_line :: proc "c" (
    state: ^core.Euclid_General_State,
    first, second: scene.Vector3) -> i32 {
    return scene.set_cycloid_tool_line(state, first, second)
}

// Atomically configure the process-global Cycloid guide's scalar state.
@(export)
set_cycloid_tool_geometry :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Cycloid_Tool_Geometry) -> i32 {
    return scene.set_cycloid_tool_geometry(state, geometry)
}

// Change only the process-global Cycloid guide's rolling parameter.
@(export)
set_cycloid_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State,
    parameter: f32) -> i32 {
    return scene.set_cycloid_tool_parameter(state, parameter)
}

// Enable drawing for the process-global two-ring trochoid guide.
@(export)
show_trochoid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.show_trochoid_tool(state)
}

// Disable drawing for the process-global two-ring trochoid guide.
@(export)
hide_trochoid_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.hide_trochoid_tool(state)
}

// Move the process-global guide's fixed center and constant elevation.
@(export)
set_trochoid_tool_position :: proc "c" (
    state: ^core.Euclid_General_State,
    position: scene.Vector3) -> i32 {
    return scene.set_trochoid_tool_position(state, position)
}

// Atomically configure the process-global guide's complete analytic state.
@(export)
set_trochoid_tool_geometry :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Trochoid_Tool_Geometry) -> i32 {
    return scene.set_trochoid_tool_geometry(state, geometry)
}

// Change only the process-global guide's rolling parameter.
@(export)
set_trochoid_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State,
    parameter: f32) -> i32 {
    return scene.set_trochoid_tool_parameter(state, parameter)
}

//   Enable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_pen :: proc "c" (state: ^core.Euclid_General_State) {
    scene.show_pen(state)
}

//   Disable drawing for the pen host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_pen :: proc "c" (state: ^core.Euclid_General_State) {
    scene.hide_pen(state)
}

//   Set pen active marker index and active highlight color.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child marker index.
//   - color: RGBA highlight color payload in bridge format.
@(export)
set_pen_active :: proc "c" (
    state: ^core.Euclid_General_State,
    active_abi: i32,
    color: scene.Bridge_Color) {
    scene.set_pen_active(state, active_abi, color)
}

//   Clear pen active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_pen_active :: proc "c" (state: ^core.Euclid_General_State) {
    scene.clear_pen_active(state)
}

//   Move pen joint1 and enable its lock constraint at the same position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
@(export)
lock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: scene.Vector3) {
    scene.lock_pen_joint1(state, pos)
}

//   Disable the lock constraint for pen joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    scene.unlock_pen_joint1(state)
}

//   Move pen joint1 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1.
@(export)
move_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: scene.Vector3) {
    scene.move_pen_joint1(state, pos)
}

//   Read pen joint1 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint1 position, or {0, 0, 0} when joint1 is unavailable.
@(export)
get_pen_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> scene.Vector3 {
    return scene.get_pen_joint1_position(state)
}

//   Move pen joint2 and enable its lock constraint at the same position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2 and its lock restriction.
@(export)
lock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: scene.Vector3) {
    scene.lock_pen_joint2(state, pos)
}

//   Disable the lock constraint for pen joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    scene.unlock_pen_joint2(state)
}

//   Move pen joint2 without changing lock constraint state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2.
@(export)
move_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: scene.Vector3) {
    scene.move_pen_joint2(state, pos)
}

//   Read pen joint2 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint2 position, or {0, 0, 0} when joint2 is unavailable.
@(export)
get_pen_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> scene.Vector3 {
    return scene.get_pen_joint2_position(state)
}

//   Enable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_compass :: proc "c" (state: ^core.Euclid_General_State) {
    scene.show_compass(state)
}

//   Disable drawing for the compass host point.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_compass :: proc "c" (state: ^core.Euclid_General_State) {
    scene.hide_compass(state)
}

//   Set compass active marker index and active highlight color.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child marker index.
//   - color: RGBA highlight color payload in bridge format.
@(export)
set_compass_active :: proc "c" (
    state: ^core.Euclid_General_State,
    active_abi: i32,
    color: scene.Bridge_Color) {
    scene.set_compass_active(state, active_abi, color)
}

//   Clear compass active marker state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_compass_active :: proc "c" (state: ^core.Euclid_General_State) {
    scene.clear_compass_active(state)
}

//   Move compass joint1, optionally emit sweep dust, and enable its lock constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1 and its lock restriction.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
lock_compass_joint1 :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: scene.Vector3,
    sweep: bool) {
    scene.lock_compass_joint1(state, pos, sweep)
}

//   Disable the lock constraint for compass joint1.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    scene.unlock_compass_joint1(state)
}

//   Move compass joint1 and optionally emit sweep dust.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint1.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
move_compass_joint1 :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: scene.Vector3,
    sweep: bool) {
    scene.move_compass_joint1(state, pos, sweep)
}

//   Read compass joint1 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint1 position, or {0, 0, 0} when joint1 is unavailable.
@(export)
get_compass_joint1_position :: proc "c" (
    state: ^core.Euclid_General_State) -> scene.Vector3 {
    return scene.get_compass_joint1_position(state)
}

//   Move compass joint2, optionally emit sweep dust, and enable its lock constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2 and its lock restriction.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
lock_compass_joint2 :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: scene.Vector3,
    sweep: bool) {
    scene.lock_compass_joint2(state, pos, sweep)
}

//   Disable the lock constraint for compass joint2.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    scene.unlock_compass_joint2(state)
}

//   Move compass joint2 and optionally emit sweep dust.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Target world-space position for joint2.
//   - sweep: When true, emit sweep dust for floor-contact motion.
@(export)
move_compass_joint2 :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: scene.Vector3,
    sweep: bool) {
    scene.move_compass_joint2(state, pos, sweep)
}

//   Read compass joint2 position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current joint2 position, or {0, 0, 0} when joint2 is unavailable.
@(export)
get_compass_joint2_position :: proc "c" (
    state: ^core.Euclid_General_State) -> scene.Vector3 {
    return scene.get_compass_joint2_position(state)
}

// Show the permanent parabola instrument without treating it as curve ink.
@(export)
show_parabola_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.show_parabola_tool(state)
}

// Hide the permanent parabola instrument without emitting construction dust.
@(export)
hide_parabola_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.hide_parabola_tool(state)
}

// Move the permanent parabola instrument's vertex while retaining its guide parameters.
@(export)
set_parabola_tool_position :: proc "c" (
    state: ^core.Euclid_General_State,
    position: scene.Vector3) -> i32 {
    return scene.set_parabola_tool_position(state, position)
}

// Configure the parabola instrument without validating against its old position.
@(export)
set_parabola_tool_geometry :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Parabola_Tool_Geometry) -> i32 {
    return scene.set_parabola_tool_geometry(state, geometry)
}

// Move the parabola instrument parameter along its configured directed domain.
@(export)
set_parabola_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State,
    parameter: f32) -> i32 {
    return scene.set_parabola_tool_parameter(state, parameter)
}

// Toggle the integrated parabola nib highlight using authored ink-color policy.
@(export)
set_parabola_tool_active :: proc "c" (
    state: ^core.Euclid_General_State,
    active: i32,
    color: scene.Bridge_Color) -> i32 {
    return scene.set_parabola_tool_active(state, active, color)
}

// Show the permanent hyperbola instrument without treating it as curve ink.
@(export)
show_hyperbola_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.show_hyperbola_tool(state)
}

// Hide the permanent hyperbola instrument without emitting construction dust.
@(export)
hide_hyperbola_tool :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return scene.hide_hyperbola_tool(state)
}

// Move the permanent hyperbola instrument's center.
@(export)
set_hyperbola_tool_position :: proc "c" (
    state: ^core.Euclid_General_State,
    position: scene.Vector3) -> i32 {
    return scene.set_hyperbola_tool_position(state, position)
}

// Configure the hyperbola instrument independently from its previous center.
@(export)
set_hyperbola_tool_geometry :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: shapemodel.Bridge_Hyperbola_Tool_Geometry) -> i32 {
    return scene.set_hyperbola_tool_geometry(state, geometry)
}

// Move the hyperbola instrument parameter along its configured finite domain.
@(export)
set_hyperbola_tool_parameter :: proc "c" (
    state: ^core.Euclid_General_State,
    parameter: f32) -> i32 {
    return scene.set_hyperbola_tool_parameter(state, parameter)
}

// Select hyperbola nib contacts without changing either carriage's movement.
@(export)
set_hyperbola_tool_active :: proc "c" (
    state: ^core.Euclid_General_State,
    active: i32,
    color: scene.Bridge_Color,
    branches: shapemodel.Hyperbola_Branches = .Both) -> i32 {
    return scene.set_hyperbola_tool_active(state, active, color, branches)
}

//   Emit trailing particles at a position using bridge color data.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: Particle emission position.
//   - color: RGBA color payload in bridge format.
@(export)
emit_trailing_particle :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: scene.Vector3,
    color: scene.Bridge_Color) {
    scene.emit_trailing_particle(state, pos, color)
}
