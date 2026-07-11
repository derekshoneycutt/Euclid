package julia

// Julia module provides the Odin-Julia Bridge to coordinate all actions between the 2
// languages. Most of these are wrappers around Odin module functions with some specific
// behavior for simplicity on the animation.
// Otherwise, the rest of Julia module is the Julia code.

// We provide a basic Bridge version and feature flags capability for building onto.
// Effort was made to wrap most of what the animations might need for now in the Kine
// system especially, and also some access to particle system.
// Doc comments are verbose in the julia companion to this, and methods are largely 1-to-1.

// Importantly, the catalogue of animations is stored as Julia Animation Interfaces in
// the Julia Interface. There is really not enough to justify separating them out, although
// it can feel a little tight here. Ultimately, the Julia is more in control of the catalogue,
// though it is stored and chosen from via the Odin.

import "../julialib"
import "../core"
import "../particles"
import "../kine"

import "core:strings"

import rl "vendor:raylib"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
MAX_KINECONSTRAINTS :: core.MAX_KINECONSTRAINTS

ANIMATION_RESET_MIN_INTERVAL :: 0.35
FLOOR_CONTACT_Z_EPSILON :: 0.015
COMPASS_LINE_DUST_SAMPLES :: 24

BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY :: (1 << 1)

BRIDGE_VERSION :: 1
BRIDGE_FEATURE_FLAGS :: 1 | BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY

BRIDGE_STATUS_OK :: 0
BRIDGE_STATUS_INVALID_INDEX :: 1
BRIDGE_STATUS_INVALID_ARGUMENT :: 2
BRIDGE_STATUS_INVALID_GRAPH :: 3
BRIDGE_STATUS_INVALID_CONSTRAINT :: 4
BRIDGE_STATUS_OUT_OF_CAPACITY :: 5
BRIDGE_STATUS_ILLEGAL_STATE :: 6
BRIDGE_STATUS_NON_CONVERGED :: 7

KINE_CONSTRAINT_VALID_MASK :: i32((1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6))

CONSTRAINT_SPEC_TRAITS :: (1 << 0)
CONSTRAINT_SPEC_ONPOINT :: (1 << 1)
CONSTRAINT_SPEC_RESTRICTION :: (1 << 2)
CONSTRAINT_SPEC_BOUNCE :: (1 << 3)
CONSTRAINT_SPEC_ALLOWANCE :: (1 << 4)
CONSTRAINT_SPEC_DEPENDON :: (1 << 5)
CONSTRAINT_SPEC_CHILDOFFSET :: (1 << 6)
CONSTRAINT_SPEC_DOAPPLY :: (1 << 7)

Bridge_Color :: struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

Bridge_Point_View :: struct {
    valid: bool,
    index: int,

    point_type: int,
    do_draw: bool,
    brush_size: f32,
    offset: f32,

    has_position: bool,
    position: core.Vector3,
    
    has_color: bool,
    color: Bridge_Color,

    has_active_color: bool,
    active_color: Bridge_Color,

    has_label : bool,
    label : rune,

    active_child: int,
    child_count: int,
    child_point_head: int,
    next_child_point: int,
}

Bridge_Constraint_View :: struct {
    valid: u8,
    index: i32,

    traits: i32,
    on_point: i32,
    restriction: core.Vector3,
    bounce: f32,
    allowance: f32,
    depend_on: i32,
    has_child_offset: u8,
    child_offset: i32,
    do_apply: u8,
}

Bridge_Constraint_Spec :: struct {
    traits: i32,
    on_point: i32,
    restriction: core.Vector3,
    bounce: f32,
    allowance: f32,
    depend_on: i32,
    has_child_offset: u8,
    child_offset: i32,
    do_apply: u8,
}

Bridge_Solve_Result :: struct {
    status: i32,
    iterations: i32,
    initial_error: f32,
    final_error: f32,
    converged: u8,
}

//   Register Julia callbacks that define the null/default animation behavior.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
@(export)
set_null_animations :: proc "c" (
    state: ^core.Euclid_General_State,
    getViewText, init, loop, clean: ^julialib.jl_value_t) {
    
    state^.julia_interface^.null_animation.get_view_text = getViewText
    state^.julia_interface^.null_animation.initiate = init
    state^.julia_interface^.null_animation.loop = loop
    state^.julia_interface^.null_animation.clean = clean
}

//   Register a top-level animation interface entry in the Julia animation registry.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
//   - name: Null-terminated animation label string from Julia.
//
// Returns:
//   - Index of the inserted animation interface entry.
@(export)
add_root_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name : cstring) -> int {

    context = state^.saved_context
    newIndex := state^.julia_interface^.next_animation_index
    state^.julia_interface^.next_animation_index += 1

    animation := &state^.julia_interface^.animations[newIndex]

    animation^.get_view_text = getViewText
    animation^.initiate = init
    animation^.loop = loop
    animation^.clean = clean
    animation^.name = strings.clone(string(name))
    animation^.first_child_id = -1
    animation^.parent_id = -1
    animation^.next_sibling = -1

    return newIndex
}

//   Register a child animation interface and link it under an existing parent animation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
//   - name: Null-terminated animation label string from Julia.
//   - parentId: Parent animation index that receives the new child animation entry.
//
// Returns:
//   - Index of the inserted child animation when parentId is valid.
//   - -1 when parentId does not reference a registered animation.
@(export)
add_child_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name : cstring,
    parentId : int) -> int {

    if parentId < 0 || parentId >= state^.julia_interface^.next_animation_index {
        return -1
    }

    context = state^.saved_context
    newIndex := state^.julia_interface^.next_animation_index
    state^.julia_interface^.next_animation_index += 1

    parentAnimation := &state^.julia_interface^.animations[parentId]
    lastChildId := parentAnimation^.first_child_id
    if lastChildId < 0 {
        parentAnimation^.first_child_id = newIndex
    } else {
        reviewChild := &state^.julia_interface^.animations[lastChildId]
        for reviewChild^.next_sibling >= 0 {
            lastChildId = reviewChild^.next_sibling
            reviewChild = &state^.julia_interface^.animations[lastChildId]
        }
        reviewChild^.next_sibling = newIndex
    }

    animation := &state^.julia_interface^.animations[newIndex]

    animation^.get_view_text = getViewText
    animation^.initiate = init
    animation^.loop = loop
    animation^.clean = clean
    animation^.name = strings.clone(string(name))
    animation^.first_child_id = -1
    animation^.parent_id = parentId
    animation^.next_sibling = -1

    return newIndex
}

//   Create a new label shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - label: Rune glyph used by label point shapes.
//   - pos: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Snapshot struct for the newly created label host with resolved draw/style/child fields.
@(export)
create_new_label :: proc "c" (
    state: ^core.Euclid_General_State,
    label: rune, pos: core.Vector3, color: Bridge_Color, brushSize: f32) -> Bridge_Point_View {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    point, index := kine.init_kineshape_label(
        state^.point_system, label, pos, rlColor, brushSize)

    use_pos, hasPos := point^.position.?
    color, hasColor := point^.color.?
    activeColor, hasActiveColor := point^.active_color.?
    use_label, hasLabel := point^.label.?

    return Bridge_Point_View{
        valid = true,
        index = index,

        point_type = 1,
        do_draw = point^.do_draw,
        brush_size = point^.brush_size,
        offset = point^.offset,

        has_position = hasPos,
        position = use_pos,

        has_color = hasColor,
        color = Bridge_Color{ color.r, color.g, color.b, color.a },

        has_active_color = hasActiveColor,
        active_color = Bridge_Color{ activeColor.r, activeColor.g, activeColor.b, activeColor.a },

        has_label = hasLabel,
        label = use_label,

        active_child = point^.active_child,
        child_count = point^.child_count,
        child_point_head = point^.child_point_head,
        next_child_point = point^.next_child_point,
    }
}

//   Create a new point shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Snapshot struct for the newly created point host with resolved draw/style/child fields.
@(export)
create_new_point :: proc "c" (
    state: ^core.Euclid_General_State,
    pos: core.Vector3, color: Bridge_Color, brushSize: f32) -> Bridge_Point_View {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    point, index := kine.init_kineshape_point(
        state^.point_system, pos, rlColor, brushSize)

    use_pos, hasPos := point^.position.?
    color, hasColor := point^.color.?
    activeColor, hasActiveColor := point^.active_color.?
    label, hasLabel := point^.label.?

    return Bridge_Point_View{
        valid = true,
        index = index,

        point_type = 2,
        do_draw = point^.do_draw,
        brush_size = point^.brush_size,
        offset = point^.offset,

        has_position = hasPos,
        position = use_pos,

        has_color = hasColor,
        color = Bridge_Color{ color.r, color.g, color.b, color.a },

        has_active_color = hasActiveColor,
        active_color = Bridge_Color{ activeColor.r, activeColor.g, activeColor.b, activeColor.a },

        has_label = hasLabel,
        label = label,

        active_child = point^.active_child,
        child_count = point^.child_count,
        child_point_head = point^.child_point_head,
        next_child_point = point^.next_child_point,
    }
}

//   Create a new line shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created line host and endpoint points.
@(export)
create_new_line :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2: core.Vector3, color: Bridge_Color, brushSize: f32) -> core.Kine_Shape_Line {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    line := kine.init_kineshape_line(
        state^.point_system, point1, point2, rlColor, brushSize)

    return line
}

//   Create a new circle shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - center: 3D position used for shape/tool placement in world space.
//   - radius: Circle radius in world units.
//   - startTheta: Arc angle bound in radians.
//   - endTheta: Arc angle bound in radians.
//   - color: RGBA color payload in bridge format.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created circle host, center, and perimeter points.
@(export)
create_new_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3, radius, startTheta, endTheta: f32,
    color: Bridge_Color, brushSize: f32) -> core.Kine_Shape_Circle {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    circle := kine.init_kineshape_circle(
        state^.point_system, center, radius, startTheta, endTheta, rlColor, brushSize)

    return circle
}

//   Create a new filledcircle shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - center: 3D position used for shape/tool placement in world space.
//   - radius: Circle radius in world units.
//   - startTheta: Arc angle bound in radians.
//   - endTheta: Arc angle bound in radians.
//   - color: RGBA color payload in bridge format.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Handle ids for the newly created filled circle host, center, and perimeter points.
@(export)
create_new_filledcircle :: proc "c" (
    state: ^core.Euclid_General_State,
    center: core.Vector3, radius, startTheta, endTheta: f32,
    color: Bridge_Color, brushSize: f32) -> core.Kine_Shape_Filled_Circle {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    circle := kine.init_kineshape_filledcircle(
        state^.point_system, center, radius, startTheta, endTheta, rlColor, brushSize)

    return circle
}

//   Create a new triangle shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - point3: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created triangle host and its three vertices.
@(export)
create_new_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2, point3: core.Vector3, color: Bridge_Color) -> core.Kine_Shape_Triangle {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    line := kine.init_kineshape_triangle(
        state^.point_system, point1, point2, point3, rlColor)

    return line
}

//   Create a new square shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - point3: 3D position used for shape/tool placement in world space.
//   - point4: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created square host and its four vertices.
@(export)
create_new_square :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2, point3, point4: core.Vector3, color: Bridge_Color) -> core.Kine_Shape_Square {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    line := kine.init_kineshape_square(
        state^.point_system, point1, point2, point3, point4, rlColor)

    return line
}

//   Create a new pentagon shape in the kine system for Julia-driven animation state.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - point1: 3D position used for shape/tool placement in world space.
//   - point2: 3D position used for shape/tool placement in world space.
//   - point3: 3D position used for shape/tool placement in world space.
//   - point4: 3D position used for shape/tool placement in world space.
//   - point5: 3D position used for shape/tool placement in world space.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Handle ids for the newly created pentagon host and its five vertices.
@(export)
create_new_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    point1, point2, point3, point4, point5: core.Vector3,
    color: Bridge_Color) -> core.Kine_Shape_Pentagon {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    line := kine.init_kineshape_pentagon(
        state^.point_system, point1, point2, point3, point4, point5, rlColor)

    return line
}

//   Build a bridge-safe snapshot of a point entry and its optional fields.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Snapshot struct with valid=false and sentinel fields when index lookup fails.
@(export)
get_point_view :: proc "c" (
    state: ^core.Euclid_General_State,
    index: int) -> Bridge_Point_View {

    if index >= 0 && index < MAX_KINEPOINTS {
        point := state^.point_system^.points[index]
        type: int = 0
        switch point.kind {
        case .Label:
            type = 1
        case .Point:
            type = 2
        case .Line:
            type = 3
        case .Circle:
            type = 4
        case .FilledCircle:
            type = 5
        case .Triangle:
            type = 6
        case .Square:
            type = 7
        case .Pentagon:
            type = 8
        case .Pen:
            type = 100
        case .Compass:
            type = 150
        }
        pos, hasPos := point.position.?
        color, hasColor := point.color.?
        activeColor, hasActiveColor := point.active_color.?
        label, hasLabel := point.label.?

        return Bridge_Point_View{
            valid = true,
            index = index,

            point_type = type,
            do_draw = point.do_draw,
            brush_size = point.brush_size,

            has_position = hasPos,
            position = pos,

            has_color = hasColor,
            color = Bridge_Color{ color.r, color.g, color.b, color.a },

            has_active_color = hasActiveColor,
            active_color = Bridge_Color{ activeColor.r, activeColor.g, activeColor.b, activeColor.a },

            has_label = hasLabel,
            label = label,

            active_child = point.active_child,
            child_count = point.child_count,
            child_point_head = point.child_point_head,
            next_child_point = point.next_child_point,
        }
    }

    return Bridge_Point_View{
        valid = false,
        index = -1,
        
        point_type = -1,
        do_draw = false,
        brush_size = 0,

        has_position = false,
        position = {0, 0, 0},

        has_color = false,
        color = Bridge_Color{ 0, 0, 0, 0 },

        has_active_color = false,
        active_color = Bridge_Color{ 0, 0, 0, 0 },

        has_label = false,
        label = 0,

        active_child = 0,
        child_count = 0,
        child_point_head = 0,
        next_child_point = 0,
    }
}


//   Enable drawing for a point host index when the index is in range.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
@(export)
show_point :: proc "c" (state: ^core.Euclid_General_State, index: int) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].do_draw = true
    }
}

//   Update point draw visibility and emit related visual effects where applicable.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
@(export)
hide_point :: proc "c" (state: ^core.Euclid_General_State, index: int) {
    if index >= 0 && index < MAX_KINEPOINTS {
        context = state^.saved_context
        particles.emit_kine_hide_burst(state^.particle_system, state^.point_system, index, true)
        state^.point_system^.points[index].do_draw = false
    }
}

//   Update point draw visibility and emit related visual effects where applicable.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - indices: Pointer to index array consumed by this batch operation.
//   - count: Number of entries available in the provided array.
@(export)
hide_point_batch :: proc "c" (state: ^core.Euclid_General_State, indices: [^]i32, count: i32) {
    if count <= 0 {
        return
    }
    context = state^.saved_context
    particles.kick_existing_dust(state^.particle_system)
    for i in 0..<int(count) {
        index := int(indices[i])
        if index >= 0 && index < MAX_KINEPOINTS {
            particles.emit_kine_hide_burst(state^.particle_system, state^.point_system, index, false)
            state^.point_system^.points[index].do_draw = false
        }
    }
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
set_point_position :: proc "c" (state: ^core.Euclid_General_State, index: int, pos: core.Vector3) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
    }
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - brushSize: Stroke thickness for rendered point/shape geometry.
@(export)
set_point_brush :: proc "c" (state: ^core.Euclid_General_State, index: int, brushSize: f32) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].brush_size = brushSize
    }
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
@(export)
set_point_color :: proc "c" (state: ^core.Euclid_General_State, index: int, color: Bridge_Color) {
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].color = rlColor
    }
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
@(export)
set_point_active_color :: proc "c" (state: ^core.Euclid_General_State, index: int, color: Bridge_Color) {
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rlColor
    }
}

//   Mark that an animation cycle boundary occurred so host-side systems can consume it once.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
notify_animation_cycle_boundary :: proc "c" (state: ^core.Euclid_General_State) {
    context = state^.saved_context
    notify_animation_cycle_boundary_local(state)
}

//   Return the bridge ABI version expected by Julia-side integration code.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_version :: proc "c" () -> i32 {
    return BRIDGE_VERSION
}

//   Return bridge feature flags that advertise optional ABI capabilities.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_feature_flags :: proc "c" () -> i32 {
    return BRIDGE_FEATURE_FLAGS
}

//   Return compile-time capacity limits exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_point_capacity :: proc "c" () -> i32 {
    return i32(MAX_KINEPOINTS)
}

//   Return the next allocation index in the active runtime system for incremental creation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_point_next_index :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.next_point_index)
}

//   Report whether an index is currently within the valid bridge addressable range.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - 1 when true, 0 when false for C ABI compatibility.
@(export)
is_point_index_in_range :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> u8 {
    context = state^.saved_context
    _ = state
    return to_u8(is_point_index_in_bounds(int(index)))
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - enabled: Non-zero to enable behavior; zero to disable.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_draw_enabled :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, enabled: u8) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].do_draw = enabled != 0
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - pos: 3D position used for shape/tool placement in world space.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_position_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, pos: core.Vector3) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].position = pos
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
clear_point_position :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].position = nil
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_color_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, color: Bridge_Color) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    state^.point_system^.points[pointIndex].color = rlColor
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
clear_point_color :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].color = nil
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - color: RGBA color payload in bridge format.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_active_color_status :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, color: Bridge_Color) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    state^.point_system^.points[pointIndex].active_color = rlColor
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
clear_point_active_color :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].active_color = nil
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - brush: Stroke thickness for rendered point/shape geometry.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_brush_size :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, brush: f32) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].brush_size = brush
    return BRIDGE_STATUS_OK
}

//   Mutate point presentation/state fields through the bridge with index validation and status reporting.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - offset: Visual z/offset scalar used by point rendering paths.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_point_offset :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, offset: f32) -> i32 {

    context = state^.saved_context

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.points[pointIndex].offset = offset
    return BRIDGE_STATUS_OK
}

//   Manage and validate parent-child point chain topology used by composite kine shapes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parentIndex: Parent point index whose child chain is being modified or validated.
//   - childIndex: Child point index to attach or detach from the parent chain.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
attach_child_point :: proc "c" (
    state: ^core.Euclid_General_State, parentIndex, childIndex: i32) -> i32 {

    context = state^.saved_context

    parent := int(parentIndex)
    child := int(childIndex)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if parent == child {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    parentPoint := &state^.point_system^.points[parent]
    childPoint := &state^.point_system^.points[child]

    if childPoint^.next_child_point >= 0 {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parentPoint^.child_point_head < 0 {
        parentPoint^.child_point_head = child
        parentPoint^.child_count = 1
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.child_point_head
    tail := current
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true
        if current == child {
            return BRIDGE_STATUS_INVALID_GRAPH
        }

        tail = current
        count += 1
        next := state^.point_system^.points[current].next_child_point
        if next < 0 {
            break
        }
        current = next
    }

    state^.point_system^.points[tail].next_child_point = child
    parentPoint^.child_count = count + 1
    return BRIDGE_STATUS_OK
}

//   Manage and validate parent-child point chain topology used by composite kine shapes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parentIndex: Parent point index whose child chain is being modified or validated.
//   - childIndex: Child point index to attach or detach from the parent chain.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
detach_child_point :: proc "c" (
    state: ^core.Euclid_General_State, parentIndex, childIndex: i32) -> i32 {

    context = state^.saved_context

    parent := int(parentIndex)
    child := int(childIndex)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.point_system^.points[parent]
    head := parentPoint^.child_point_head
    if head < 0 {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    visited: [MAX_KINEPOINTS]bool
    current := head
    prev := -1
    removed := false

    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true

        next := state^.point_system^.points[current].next_child_point
        if current == child {
            removed = true
            if prev < 0 {
                parentPoint^.child_point_head = next
            } else {
                state^.point_system^.points[prev].next_child_point = next
            }
            state^.point_system^.points[current].next_child_point = -1
            break
        }

        prev = current
        current = next
    }

    if !removed {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    _ = rebuild_child_count(state, parentIndex)
    return BRIDGE_STATUS_OK
}

//   Manage and validate parent-child point chain topology used by composite kine shapes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parentIndex: Parent point/animation index that receives a child linkage.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
rebuild_child_count :: proc "c" (state: ^core.Euclid_General_State, parentIndex: i32) -> i32 {
    context = state^.saved_context
    parent := int(parentIndex)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.point_system^.points[parent]
    if parentPoint^.child_point_head < 0 {
        parentPoint^.child_count = 0
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.child_point_head
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true
        count += 1
        current = state^.point_system^.points[current].next_child_point
    }

    parentPoint^.child_count = count
    return BRIDGE_STATUS_OK
}

//   Manage and validate parent-child point chain topology used by composite kine shapes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - parentIndex: Parent point/animation index that receives a child linkage.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
validate_parent_child_chain :: proc "c" (
    state: ^core.Euclid_General_State, parentIndex: i32) -> i32 {

    context = state^.saved_context

    parent := int(parentIndex)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.point_system^.points[parent]
    if parentPoint^.child_point_head < 0 {
        if parentPoint^.child_count != 0 {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.child_point_head
    count := 0
    for current >= 0 {
        if !is_point_index_in_bounds(current) {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        if visited[current] {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        visited[current] = true
        count += 1
        current = state^.point_system^.points[current].next_child_point
    }

    if parentPoint^.child_count != count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parentPoint^.active_child < -1 || parentPoint^.active_child >= count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    return BRIDGE_STATUS_OK
}

//   Return compile-time capacity limits exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_capacity :: proc "c" () -> i32 {
    return i32(MAX_KINECONSTRAINTS)
}

//   Return the next allocation index in the active runtime system for incremental creation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_next_index :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.next_constraint_index)
}

//   Report whether an index is currently within the valid bridge addressable range.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - 1 when true, 0 when false for C ABI compatibility.
@(export)
is_constraint_index_in_range :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> u8 {

    context = state^.saved_context

    _ = state
    return to_u8(is_constraint_index_in_bounds(int(index)))
}

//   Build a bridge-safe snapshot of a constraint entry and its optional child offset field.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Snapshot struct with valid=0 and sentinel fields when index lookup fails.
@(export)
get_constraint_view :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> Bridge_Constraint_View {

    context = state^.saved_context

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return constraint_view_invalid()
    }

    constraint := state^.point_system^.constraints[constraintIndex]
    childOffset, hasChildOffset := constraint.child_offset.?

    return Bridge_Constraint_View{
        valid = 1,
        index = index,
        traits = i32(constraint.traits),
        on_point = i32(constraint.on_point),
        restriction = constraint.restriction,
        bounce = constraint.bounce,
        allowance = constraint.allowance,
        depend_on = constraint.depend_on,
        has_child_offset = to_u8(hasChildOffset),
        child_offset = childOffset,
        do_apply = to_u8(constraint.do_apply),
    }
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - spec: Constraint specification payload used for create/update operations.
//   - outIndex: Optional output pointer that receives the created constraint index.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
create_constraint :: proc "c" (
    state: ^core.Euclid_General_State, spec: Bridge_Constraint_Spec, outIndex: ^i32) -> i32 {

    context = state^.saved_context

    if !is_valid_constraint_traits_mask(spec.traits) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    onPoint := int(spec.on_point)
    if !is_point_index_in_bounds(onPoint) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.depend_on >= 0 && !is_constraint_index_in_bounds(int(spec.depend_on)) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.has_child_offset != 0 && spec.child_offset < 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    nextIndex := state^.point_system^.next_constraint_index
    if nextIndex < 0 || nextIndex >= MAX_KINECONSTRAINTS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }

    state^.point_system^.constraints[nextIndex] = core.Kine_Constraint{
        traits = core.Kine_Constraint_Trait(spec.traits),
        on_point = onPoint,
        restriction = spec.restriction,
        bounce = spec.bounce,
        allowance = spec.allowance,
        depend_on = spec.depend_on,
        child_offset = nil,
        do_apply = spec.do_apply != 0,
    }
    if spec.has_child_offset != 0 {
        state^.point_system^.constraints[nextIndex].child_offset = spec.child_offset
    }

    state^.point_system^.next_constraint_index += 1
    if outIndex != nil {
        outIndex^ = i32(nextIndex)
    }
    return BRIDGE_STATUS_OK
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - specMask: Bitmask selecting which fields from spec are applied during update.
//   - spec: Constraint specification payload used for create/update operations.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
update_constraint :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, specMask: i32, spec: Bridge_Constraint_Spec) -> i32 {

    context = state^.saved_context

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.point_system^.constraints[constraintIndex]

    if specMask & CONSTRAINT_SPEC_TRAITS != 0 {
        if !is_valid_constraint_traits_mask(spec.traits) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        constraint^.traits = core.Kine_Constraint_Trait(spec.traits)
    }
    if specMask & CONSTRAINT_SPEC_ONPOINT != 0 {
        onPoint := int(spec.on_point)
        if !is_point_index_in_bounds(onPoint) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.on_point = onPoint
    }
    if specMask & CONSTRAINT_SPEC_RESTRICTION != 0 {
        constraint^.restriction = spec.restriction
    }
    if specMask & CONSTRAINT_SPEC_BOUNCE != 0 {
        constraint^.bounce = spec.bounce
    }
    if specMask & CONSTRAINT_SPEC_ALLOWANCE != 0 {
        constraint^.allowance = spec.allowance
    }
    if specMask & CONSTRAINT_SPEC_DEPENDON != 0 {
        if spec.depend_on >= 0 && !is_constraint_index_in_bounds(int(spec.depend_on)) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.depend_on = spec.depend_on
    }
    if specMask & CONSTRAINT_SPEC_CHILDOFFSET != 0 {
        if spec.has_child_offset != 0 {
            if spec.child_offset < 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            constraint^.child_offset = spec.child_offset
        } else {
            constraint^.child_offset = nil
        }
    }
    if specMask & CONSTRAINT_SPEC_DOAPPLY != 0 {
        constraint^.do_apply = spec.do_apply != 0
    }

    return BRIDGE_STATUS_OK
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - enabled: Non-zero to enable behavior; zero to disable.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_constraint_enabled :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, enabled: u8) -> i32 {

    context = state^.saved_context

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraintIndex].do_apply = enabled != 0
    return BRIDGE_STATUS_OK
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
clear_constraint :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraintIndex] = {}
    state^.point_system^.constraints[constraintIndex].do_apply = false
    return BRIDGE_STATUS_OK
}

//   Expose constraint error measurements from the solver for Julia-side control logic.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Single-precision value reported by the host constraint or metadata subsystem.
@(export)
get_total_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State) -> f32 {
    context = state^.saved_context
    return kine.get_total_constraint_error(state^.point_system)
}

//   Expose constraint error measurements from the solver for Julia-side control logic.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - constraintIndex: Target point or constraint index for this bridge operation.
//   - outError: Output pointer that receives computed error for one constraint.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraintIndex: i32, outError: ^f32) -> i32 {

    context = state^.saved_context

    idx := int(constraintIndex)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if outError == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    constraint := &state^.point_system^.constraints[idx]
    outError^ = kine.get_constraint_error(constraint, &state^.point_system^.points)
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - constraintIndex: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
apply_constraint_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraintIndex: i32) -> i32 {

    context = state^.saved_context

    idx := int(constraintIndex)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.point_system^.constraints[idx]
    kine.apply_constraint(constraint, &state^.point_system^.points)
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - reverse: Non-zero to apply constraints in reverse traversal order.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
apply_all_constraints_bridge :: proc "c" (
    state: ^core.Euclid_General_State, reverse: u8) -> i32 {

    context = state^.saved_context

    if reverse != 0 {
        kine.apply_all_constraints_reverse(state^.point_system)
    } else {
        kine.apply_all_constraints(state^.point_system)
    }
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - allowableError: Target maximum total constraint error for iterative solving.
//   - maxIterations: Maximum solve iterations to attempt before reporting non-convergence.
//
// Returns:
//   - Structured solver outcome including status, iteration count, error bounds, and converged flag.
//
// Notes:
//   - If status is BRIDGE_STATUS_NON_CONVERGED, inspect final_error to decide next solver action.
@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.Euclid_General_State, allowableError: f32, maxIterations: i32) -> Bridge_Solve_Result {

    context = state^.saved_context

    if allowableError < 0 {
        return Bridge_Solve_Result{
            status = BRIDGE_STATUS_INVALID_ARGUMENT,
            iterations = 0,
            initial_error = 0,
            final_error = 0,
            converged = 0,
        }
    }

    iterationLimit := maxIterations
    if iterationLimit <= 0 {
        iterationLimit = 32
    }
    if iterationLimit > 4096 {
        iterationLimit = 4096
    }

    initialError := kine.get_total_constraint_error(state^.point_system)
    if initialError <= allowableError {
        return Bridge_Solve_Result{
            status = BRIDGE_STATUS_OK,
            iterations = 0,
            initial_error = initialError,
            final_error = initialError,
            converged = 1,
        }
    }

    reverse := false
    error := initialError
    iterations: i32 = 0
    for iterations < iterationLimit && error > allowableError {
        if reverse {
            kine.apply_all_constraints_reverse(state^.point_system)
        } else {
            kine.apply_all_constraints(state^.point_system)
        }
        reverse = !reverse
        iterations += 1
        error = kine.get_total_constraint_error(state^.point_system)
    }

    converged := error <= allowableError
    status : i32 = BRIDGE_STATUS_NON_CONVERGED
    if converged {
        status = BRIDGE_STATUS_OK
    }

    return Bridge_Solve_Result{
        status = status,
        iterations = iterations,
        initial_error = initialError,
        final_error = error,
        converged = to_u8(converged),
    }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_line_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Line {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Line{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Line {
        return core.Kine_Shape_Line{ -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Kine_Shape_Line{ -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Kine_Shape_Line{ -1, -1, -1 }
    }

    return core.Kine_Shape_Line{ host, p1, p2 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_circle_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Circle {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Circle{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Circle {
        return core.Kine_Shape_Circle{ -1, -1, -1 }
    }

    start := point.child_point_head
    if !is_point_index_in_bounds(start) {
        return core.Kine_Shape_Circle{ -1, -1, -1 }
    }
    finish := state^.point_system^.points[start].next_child_point
    if !is_point_index_in_bounds(finish) {
        return core.Kine_Shape_Circle{ -1, -1, -1 }
    }

    return core.Kine_Shape_Circle{ host, start, finish }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_filledcircle_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Filled_Circle {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Filled_Circle{ -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .FilledCircle {
        return core.Kine_Shape_Filled_Circle{ -1, -1, -1 }
    }

    start := point.child_point_head
    if !is_point_index_in_bounds(start) {
        return core.Kine_Shape_Filled_Circle{ -1, -1, -1 }
    }
    finish := state^.point_system^.points[start].next_child_point
    if !is_point_index_in_bounds(finish) {
        return core.Kine_Shape_Filled_Circle{ -1, -1, -1 }
    }

    return core.Kine_Shape_Filled_Circle{ host, start, finish }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_triangle_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Triangle {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Triangle{ -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Triangle {
        return core.Kine_Shape_Triangle{ -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Kine_Shape_Triangle{ -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Kine_Shape_Triangle{ -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Kine_Shape_Triangle{ -1, -1, -1, -1 }
    }

    return core.Kine_Shape_Triangle{ host, p1, p2, p3 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_square_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Square {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Square {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }
    p4 := state^.point_system^.points[p3].next_child_point
    if !is_point_index_in_bounds(p4) {
        return core.Kine_Shape_Square{ -1, -1, -1, -1, -1 }
    }

    return core.Kine_Shape_Square{ host, p1, p2, p3, p4 }
}

//   Resolve a typed shape view from a host point and validate expected child linkage indices.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - hostId: Host point index expected to own the requested shape kind.
//
// Returns:
//   - Typed shape handle with -1 sentinel indices when host id is invalid or does not match expected shape kind.
@(export)
get_shape_pentagon_view :: proc "c" (
    state: ^core.Euclid_General_State, hostId: i32) -> core.Kine_Shape_Pentagon {

    context = state^.saved_context
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    point := state^.point_system^.points[host]
    if point.kind != .Pentagon {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    p1 := point.child_point_head
    if !is_point_index_in_bounds(p1) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p2 := state^.point_system^.points[p1].next_child_point
    if !is_point_index_in_bounds(p2) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p3 := state^.point_system^.points[p2].next_child_point
    if !is_point_index_in_bounds(p3) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p4 := state^.point_system^.points[p3].next_child_point
    if !is_point_index_in_bounds(p4) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p5 := state^.point_system^.points[p4].next_child_point
    if !is_point_index_in_bounds(p5) {
        return core.Kine_Shape_Pentagon{ -1, -1, -1, -1, -1, -1 }
    }

    return core.Kine_Shape_Pentagon{ host, p1, p2, p3, p4, p5 }
}

//   Return the current tool shape handle used by bridge-controlled interactions.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current pen handle from runtime state, including host and joint ids.
@(export)
get_pen_view :: proc "c" (state: ^core.Euclid_General_State) -> core.Kine_Shape_Pen {
    return state^.pen
}

//   Return the current tool shape handle used by bridge-controlled interactions.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Current compass handle from runtime state, including host, pivot, and joint ids.
@(export)
get_compass_view :: proc "c" (state: ^core.Euclid_General_State) -> core.Kine_Shape_Compass {
    return state^.compass
}

//   Expose and maintain animation-boundary bookkeeping for points, constraints, and graph validity.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Point index where animation-owned points begin.
@(export)
get_kine_anim_points_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.anim_points_start)
}

//   Expose and maintain animation-boundary bookkeeping for points, constraints, and graph validity.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Constraint index where animation-owned constraints begin.
@(export)
get_kine_anim_constraints_start :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.anim_constraints_start)
}

//   Expose and maintain animation-boundary bookkeeping for points, constraints, and graph validity.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK after freezing current next indices as the animation boundary.
@(export)
freeze_kine_animation_boundary :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    kine.kine_freeze_system_indices(state^.point_system)
    return BRIDGE_STATUS_OK
}

//   Expose and maintain animation-boundary bookkeeping for points, constraints, and graph validity.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK after clearing animation-owned points and constraints.
@(export)
clear_kine_animation_data :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    kine.kine_clear_animation_data(state^.point_system, state^.particle_system)
    return BRIDGE_STATUS_OK
}

//   Return compile-time capacity limits exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_max_kine_points :: proc "c" () -> i32 {
    return i32(MAX_KINEPOINTS)
}

//   Return compile-time capacity limits exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_max_kine_constraints :: proc "c" () -> i32 {
    return i32(MAX_KINECONSTRAINTS)
}

//   Expose and maintain animation-boundary bookkeeping for points, constraints, and graph validity.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
validate_kine_graph :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context

    for i in 0..<MAX_KINEPOINTS {
        point := state^.point_system^.points[i]
        if point.child_point_head >= 0 {
            validateStatus := validate_parent_child_chain(state, i32(i))
            if validateStatus != BRIDGE_STATUS_OK {
                return validateStatus
            }
        }
    }

    for i in 0..<MAX_KINECONSTRAINTS {
        constraint := state^.point_system^.constraints[i]
        if constraint.do_apply {
            if !is_point_index_in_bounds(constraint.on_point) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
            if constraint.depend_on >= 0 && !is_constraint_index_in_bounds(int(constraint.depend_on)) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
        }
    }

    return BRIDGE_STATUS_OK
}


//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_pen :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].do_draw = true
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_pen :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].do_draw = false
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child/endpoint marker index for tool highlighting.
//   - color: RGBA color payload in bridge format.
@(export)
set_pen_active :: proc "c" (
    state: ^core.Euclid_General_State, active: int, color: Bridge_Color) {

    index := state^.pen.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rlColor
        state^.point_system^.points[index].active_child = active
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_pen_active :: proc "c" (
    state: ^core.Euclid_General_State) {

    index := state^.pen.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].active_child = -1
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
lock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint1_id
    constraintIndex := state^.pen.lock_point1_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.lock_point1_id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
move_pen_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint1_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Joint position vector, or {0,0,0} when the joint index is unavailable.
@(export)
get_pen_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.pen.joint1_id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
lock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint2_id
    constraintIndex := state^.pen.lock_point2_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.pen.lock_point2_id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
@(export)
move_pen_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3) {
    context = state^.saved_context
    index := state^.pen.joint2_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Joint position vector, or {0,0,0} when the joint index is unavailable.
@(export)
get_pen_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.pen.joint2_id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
show_compass :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].do_draw = true
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
hide_compass :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].do_draw = false
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - active: Active child/endpoint marker index for tool highlighting.
//   - color: RGBA color payload in bridge format.
@(export)
set_compass_active :: proc "c" (
    state: ^core.Euclid_General_State, active: int, color: Bridge_Color) {

    index := state^.compass.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.r, color.g, color.b, color.a }
        state^.point_system^.points[index].active_color = rlColor
        state^.point_system^.points[index].active_child = active
    }
}

//   Control pen/compass tool visibility and active marker state for interactive animation steps.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
clear_compass_active :: proc "c" (
    state: ^core.Euclid_General_State) {

    index := state^.compass.host_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].active_child = -1
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - sweep: When true, emit sweep dust along the compass segment movement.
@(export)
lock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    pointIndex := state^.compass.joint1_id
    pivotIndex := state^.compass.pivot_id
    constraintIndex := state^.compass.lock_point1_id
    if pointIndex > 0 && pointIndex < MAX_KINEPOINTS {
        state^.point_system^.points[pointIndex].position = pos
        push_dust_if_floor_contact(state, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }
    
        pointpos := state^.point_system^.points[pointIndex].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.lock_point1_id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - sweep: When true, emit sweep dust along the compass segment movement.
@(export)
move_compass_joint1 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint1_id
    pivotIndex := state^.compass.pivot_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[index].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Joint position vector, or {0,0,0} when the joint index is unavailable.
@(export)
get_compass_joint1_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.compass.joint1_id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - sweep: When true, emit sweep dust along the compass segment movement.
@(export)
lock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    pointIndex := state^.compass.joint2_id
    pivotIndex := state^.compass.pivot_id
    constraintIndex := state^.compass.lock_point2_id
    if pointIndex > 0 && pointIndex < MAX_KINEPOINTS {
        state^.point_system^.points[pointIndex].position = pos
        push_dust_if_floor_contact(state, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[pointIndex].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[constraintIndex].restriction = pos
        state^.point_system^.constraints[constraintIndex].do_apply = true
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State) {
    index := state^.compass.lock_point2_id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.point_system^.constraints[index].do_apply = false
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - sweep: When true, emit sweep dust along the compass segment movement.
@(export)
move_compass_joint2 :: proc "c" (state: ^core.Euclid_General_State, pos: core.Vector3, sweep: bool) {
    context = state^.saved_context
    index := state^.compass.joint2_id
    pivotIndex := state^.compass.pivot_id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.point_system^.points[index].position = pos
        push_dust_if_floor_contact(state, pos)
        if sweep {
            push_dust_for_compass_segment_if_floor_contact(state)
        }

        pointpos := state^.point_system^.points[index].position.? or_else { 0, 0, 0 }
        pivotpos := state^.point_system^.points[pivotIndex].position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.point_system^.points[pivotIndex].position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

//   Read or update tool joint state, including optional lock constraints and floor-contact effects.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Joint position vector, or {0,0,0} when the joint index is unavailable.
@(export)
get_compass_joint2_position :: proc "c" (state: ^core.Euclid_General_State) -> core.Vector3 {
    index := state^.compass.joint2_id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.point_system^.points[index].position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

//   Set or read animation metadata slots used for lightweight Julia-to-host state exchange.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//   - metadata: Metadata value stored in the animation scratch slot.
@(export)
set_animation_meta :: proc "c" (state: ^core.Euclid_General_State, pos: int, metadata: f32) {
    if pos >= 0 && pos < len(state^.anim_metadata) {
        state^.anim_metadata[pos] = metadata
    }
}

//   Set or read animation metadata slots used for lightweight Julia-to-host state exchange.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for shape/tool placement in world space.
//
// Returns:
//   - Metadata value at pos when in range, or 0 when pos is out of range.
@(export)
get_animation_meta :: proc "c" (state: ^core.Euclid_General_State, pos: int) -> f32 {
    if pos >= 0 && pos <= len(state^.anim_metadata) {
        return state^.anim_metadata[pos]
    }
    return 0
}

//   Emit bridge-triggered particle effects using the host particle system at the requested position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 2D position used for particle emission.
//   - color: RGBA color payload in bridge format.
@(export)
emit_trailing_particle :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector2, color: Bridge_Color) {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_trail_particles(
        state^.particle_system, state^.current_delta_time, pos.x, pos.y, rlColor)
}

//   Emit bridge-triggered particle effects using the host particle system at the requested position.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - pos: 3D position used for particle emission.
//   - color: RGBA color payload in bridge format.
@(export)
emit_flicker_particle :: proc "c" (
    state: ^core.Euclid_General_State, pos: core.Vector3, color: Bridge_Color) {

    context = state^.saved_context
    rlColor := rl.Color{ color.r, color.g, color.b, color.a }
    particles.emit_flicker_particles(state^.particle_system, pos.x, pos.y, pos.z, rlColor, 10)
}
