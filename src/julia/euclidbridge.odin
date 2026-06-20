package julia

import "../julialib"
import "../core"
import "../particles"
import "../kine"

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"

import rl "vendor:raylib"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
MAX_KINECONSTRAINTS :: core.MAX_KINECONSTRAINTS

ANIMATION_RESET_MIN_INTERVAL :: f32(0.35)
FLOOR_CONTACT_Z_EPSILON :: f32(0.015)
COMPASS_LINE_DUST_SAMPLES :: int(24)

BRIDGE_VERSION :: i32(1)
BRIDGE_FEATURE_FLAGS :: i32(1)

BRIDGE_STATUS_OK :: i32(0)
BRIDGE_STATUS_INVALID_INDEX :: i32(1)
BRIDGE_STATUS_INVALID_ARGUMENT :: i32(2)
BRIDGE_STATUS_INVALID_GRAPH :: i32(3)
BRIDGE_STATUS_INVALID_CONSTRAINT :: i32(4)
BRIDGE_STATUS_OUT_OF_CAPACITY :: i32(5)
BRIDGE_STATUS_ILLEGAL_STATE :: i32(6)
BRIDGE_STATUS_NON_CONVERGED :: i32(7)

KINE_CONSTRAINT_VALID_MASK :: i32((1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6))

CONSTRAINT_SPEC_TRAITS :: i32(1 << 0)
CONSTRAINT_SPEC_ONPOINT :: i32(1 << 1)
CONSTRAINT_SPEC_RESTRICTION :: i32(1 << 2)
CONSTRAINT_SPEC_BOUNCE :: i32(1 << 3)
CONSTRAINT_SPEC_ALLOWANCE :: i32(1 << 4)
CONSTRAINT_SPEC_DEPENDON :: i32(1 << 5)
CONSTRAINT_SPEC_CHILDOFFSET :: i32(1 << 6)
CONSTRAINT_SPEC_DOAPPLY :: i32(1 << 7)

BridgeColor :: struct {
    R: u8,
    G: u8,
    B: u8,
    A: u8,
}

BridgePointView :: struct {
    Valid: bool,
    Index: int,

    PointType: int,
    DoDraw: bool,
    BrushSize: f32,

    HasPosition: bool,
    Position: core.Vector3,
    
    HasColor: bool,
    Color: BridgeColor,

    HasActiveColor: bool,
    ActiveColor: BridgeColor,

    ActiveChild: int,
    ChildCount: int,
    ChildPointHead: int,
    NextChildPoint: int,
}

BridgeConstraintView :: struct {
    Valid: u8,
    Index: i32,

    Traits: i32,
    OnPoint: i32,
    Restriction: core.Vector3,
    Bounce: f32,
    Allowance: f32,
    DependOn: i32,
    HasChildOffset: u8,
    ChildOffset: i32,
    DoApply: u8,
}

BridgeConstraintSpec :: struct {
    Traits: i32,
    OnPoint: i32,
    Restriction: core.Vector3,
    Bounce: f32,
    Allowance: f32,
    DependOn: i32,
    HasChildOffset: u8,
    ChildOffset: i32,
    DoApply: u8,
}

BridgeSolveResult :: struct {
    Status: i32,
    Iterations: i32,
    InitialError: f32,
    FinalError: f32,
    Converged: u8,
}

is_point_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINEPOINTS
}

is_constraint_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINECONSTRAINTS
}

is_valid_constraint_traits_mask :: #force_inline proc(mask: i32) -> bool {
    return mask != 0 && (mask & ~KINE_CONSTRAINT_VALID_MASK) == 0
}

to_u8 :: #force_inline proc(v: bool) -> u8 {
    if v {
        return 1
    }
    return 0
}

constraint_view_invalid :: #force_inline proc() -> BridgeConstraintView {
    return BridgeConstraintView{
        Valid = 0,
        Index = -1,
        Traits = 0,
        OnPoint = -1,
        Restriction = {0, 0, 0},
        Bounce = 0,
        Allowance = 0,
        DependOn = -1,
        HasChildOffset = 0,
        ChildOffset = 0,
        DoApply = 0,
    }
}

push_dust_if_floor_contact :: proc(state: ^core.EuclidGeneralState, pos: core.Vector3) {
    if f32(math.abs(f64(pos.z))) <= FLOOR_CONTACT_Z_EPSILON {
        particles.push_dust_away_from_xy(state^.ParticleSystem, pos.x, pos.y)
    }
}

push_dust_for_compass_segment_if_floor_contact :: proc(state: ^core.EuclidGeneralState) {
    pointIndex1 := state^.Compass.Joint1Id
    pointIndex2 := state^.Compass.Joint2Id
    if pointIndex1 < 0 || pointIndex1 >= MAX_KINEPOINTS || pointIndex2 < 0 || pointIndex2 >= MAX_KINEPOINTS {
        return
    }

    point1 := state^.PointSystem^.Points[pointIndex1].Position.? or_else {0, 0, 0}
    point2 := state^.PointSystem^.Points[pointIndex2].Position.? or_else {0, 0, 0}

    if f32(math.abs(f64(point1.z))) > FLOOR_CONTACT_Z_EPSILON ||
        f32(math.abs(f64(point2.z))) > FLOOR_CONTACT_Z_EPSILON {
        return
    }

    samples := COMPASS_LINE_DUST_SAMPLES
    inv_samples := f32(1.0) / f32(samples)
    for i in 0..<samples {
        t := f32(i) * inv_samples
        x := math.lerp(point1.x, point2.x, t)
        y := math.lerp(point1.y, point2.y, t)
        particles.push_dust_away_from_xy(state^.ParticleSystem, x, y)
    }
}

print_julia_exception :: proc(contextOfErr: string) {
    ex_raw := julialib.jl_exception_occurred()
    if ex_raw == nil {
        return
    }

    ex := (^julialib.jl_value_t)(ex_raw)

    ex_type := cstring(julialib.jl_typeof_str(ex_raw))

    sprint_fn := julialib.jl_get_function(julialib.jl_base_module, "sprint")
    showerror_fn := julialib.jl_get_function(julialib.jl_base_module, "showerror")

    if sprint_fn == nil || showerror_fn == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    args: [2]^julialib.jl_value_t = {(^julialib.jl_value_t)(showerror_fn), ex}
    msg_val := julialib.jl_call(sprint_fn, &args[0], 2)

    if julialib.jl_exception_occurred() != nil || msg_val == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    msg := julialib.jl_string_ptr(msg_val)
    fmt.println("Julia exception in ", contextOfErr, " type=", ex_type, " msg=", msg)
}

initiate_julia :: proc() {
    julialib.jl_init()
    _ = julialib.jl_eval_string("include(\"./julia/script.jl\")")
}

retrieve_interface :: proc() -> ^core.EuclidJuliaInterface {
    ret := new(core.EuclidJuliaInterface)

    ret.InitScripts = julialib.jl_get_function(julialib.jl_main_module, "init_euclid_scripts")
    ret.GlobalLoop = julialib.jl_get_function(julialib.jl_main_module, "global_euclid_loop")
    ret.CurrentAnimationIndex = -1
    ret.SelectedAnimationIndex = -1
    ret.AnimationResetCooldownRemaining = 0

    return ret
}

init_euclid_scripts :: proc(
    state: ^core.EuclidGeneralState) {

    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.JuliaInterface^.InitScripts, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return
    }

    if state^.JuliaInterface^.NullAnimation.Initiate != nil {
        julialib.jl_call1(state^.JuliaInterface^.NullAnimation.Initiate, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("init_euclid_scripts")
            return
        }
    }
}

update_running_animations :: proc(
    state: ^core.EuclidGeneralState, dt: f32) {

    if state^.JuliaInterface^.AnimationResetCooldownRemaining > 0 {
        state^.JuliaInterface^.AnimationResetCooldownRemaining -= dt
        if state^.JuliaInterface^.AnimationResetCooldownRemaining < 0 {
            state^.JuliaInterface^.AnimationResetCooldownRemaining = 0
        }
    }

    switched_animation := false
    if state^.JuliaInterface^.SelectedAnimationIndex !=
        state^.JuliaInterface^.CurrentAnimationIndex {
        previous_animation_index := state^.JuliaInterface^.CurrentAnimationIndex
        change_current_animation_loop(
            state,
            state^.JuliaInterface^.SelectedAnimationIndex,
        )
        switched_animation =
            state^.JuliaInterface^.CurrentAnimationIndex == state^.JuliaInterface^.SelectedAnimationIndex &&
            state^.JuliaInterface^.CurrentAnimationIndex != previous_animation_index
    }

    if state^.JuliaInterface^.PendingAnimationReset &&
        state^.JuliaInterface^.CurrentAnimationIndex == state^.JuliaInterface^.SelectedAnimationIndex {
        if switched_animation {
            state^.JuliaInterface^.PendingAnimationReset = false
        } else {
            if state^.JuliaInterface^.AnimationResetCooldownRemaining <= 0 {
                reset_current_animation_loop(state)
                state^.JuliaInterface^.AnimationResetCooldownRemaining = ANIMATION_RESET_MIN_INTERVAL
                state^.JuliaInterface^.PendingAnimationReset = false
            }
        }
    }
}

call_global_euclid_loop :: proc(
    state: ^core.EuclidGeneralState, dt: f32) {

    state_value := julialib.jl_box_voidpointer(state)
    dt_value := julialib.jl_box_float32(dt)

    result := julialib.jl_call2(state^.JuliaInterface^.GlobalLoop, state_value, dt_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("global_euclid_loop")
        return
    }
}

call_current_animation_loop :: proc(
    state: ^core.EuclidGeneralState, dt: f32) {

    if state^.JuliaInterface^.CurrentAnimation.Loop == nil {
        return
    }

    state_value := julialib.jl_box_voidpointer(state)
    dt_value := julialib.jl_box_float32(dt)

    result := julialib.jl_call2(state^.JuliaInterface^.CurrentAnimation^.Loop, state_value, dt_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Current animation loop")
        return
    }
}

call_current_animation_get_view_text :: proc(
    state: ^core.EuclidGeneralState) -> string {

    if state^.JuliaInterface^.CurrentAnimation == nil ||
        state^.JuliaInterface^.CurrentAnimation^.GetViewText == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)

    result := julialib.jl_call1(state^.JuliaInterface^.CurrentAnimation^.GetViewText, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Current animation get view text")
        return ""
    }
    if result == nil {
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

change_current_animation_loop :: proc(
    state: ^core.EuclidGeneralState, newIndex: int) {
    
    if newIndex < -1 || newIndex >= state^.JuliaInterface^.NextAnimationIndex {
        return
    }

    animation := &state^.JuliaInterface^.Animations[newIndex]
    if newIndex < 0 {
        animation = &state^.JuliaInterface^.NullAnimation
    }
    
    state_value := julialib.jl_box_voidpointer(state)

    if state^.JuliaInterface^.CurrentAnimation^.Loop != nil {
        julialib.jl_call1(state^.JuliaInterface^.CurrentAnimation^.Clean, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("Cleaning previous animation loop")
            return
        }
    }
    
    kine.kine_clear_animation_data(state^.PointSystem, state^.ParticleSystem)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.AnimMetadata) {
        state^.AnimMetadata[i] = 0.0
    }

   julialib.jl_call1(animation^.Initiate, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return
    }

    state^.JuliaInterface^.CurrentAnimation = animation
    state^.JuliaInterface^.CurrentAnimationIndex = newIndex
}

reset_current_animation_loop :: proc(
    state: ^core.EuclidGeneralState) {

    if state^.JuliaInterface^.CurrentAnimation^.Loop == nil {
        return
    }
    
    state_value := julialib.jl_box_voidpointer(state)

   julialib.jl_call1(state^.JuliaInterface^.CurrentAnimation^.Clean, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Cleaning previous animation loop")
        return
    }
    
    kine.kine_clear_animation_data(state^.PointSystem, state^.ParticleSystem)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.AnimMetadata) {
        state^.AnimMetadata[i] = 0.0
    }
    
   julialib.jl_call1(state^.JuliaInterface^.CurrentAnimation^.Initiate, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return
    }
}

clean_julia_interfaces :: proc(state: ^core.EuclidGeneralState) {
    for i in 0..<state^.JuliaInterface^.NextAnimationIndex {
        animation := state^.JuliaInterface^.Animations[i]
        delete(animation.Name)
    }
}

end_julia :: proc() {
    julialib.jl_atexit_hook(0)
}


@(export)
set_null_animations :: proc "c" (
    state: ^core.EuclidGeneralState,
    getViewText, init, loop, clean: ^julialib.jl_value_t) {
    
    state^.JuliaInterface^.NullAnimation.GetViewText = getViewText
    state^.JuliaInterface^.NullAnimation.Initiate = init
    state^.JuliaInterface^.NullAnimation.Loop = loop
    state^.JuliaInterface^.NullAnimation.Clean = clean
}

@(export)
add_root_animation_interface :: proc "c" (
    state : ^core.EuclidGeneralState,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name : cstring) -> int {

    context = state^.SavedContext
    newIndex := state^.JuliaInterface^.NextAnimationIndex
    state^.JuliaInterface^.NextAnimationIndex += 1

    animation := &state^.JuliaInterface^.Animations[newIndex]

    animation^.GetViewText = getViewText
    animation^.Initiate = init
    animation^.Loop = loop
    animation^.Clean = clean
    animation^.Name = strings.clone(string(name))
    animation^.FirstChildId = -1
    animation^.ParentId = -1
    animation^.NextSibling = -1

    return newIndex
}

@(export)
add_child_animation_interface :: proc "c" (
    state : ^core.EuclidGeneralState,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name : cstring,
    parentId : int) -> int {

    if parentId < 0 || parentId >= state^.JuliaInterface^.NextAnimationIndex {
        return -1
    }

    context = state^.SavedContext
    newIndex := state^.JuliaInterface^.NextAnimationIndex
    state^.JuliaInterface^.NextAnimationIndex += 1

    parentAnimation := &state^.JuliaInterface^.Animations[parentId]
    lastChildId := parentAnimation^.FirstChildId
    if lastChildId < 0 {
        parentAnimation^.FirstChildId = newIndex
    }
    else {
        reviewChild := &state^.JuliaInterface^.Animations[lastChildId]
        for reviewChild^.NextSibling >= 0 {
            lastChildId = reviewChild^.NextSibling
            reviewChild = &state^.JuliaInterface^.Animations[lastChildId]
        }
        reviewChild^.NextSibling = newIndex
    }

    animation := &state^.JuliaInterface^.Animations[newIndex]

    animation^.GetViewText = getViewText
    animation^.Initiate = init
    animation^.Loop = loop
    animation^.Clean = clean
    animation^.Name = strings.clone(string(name))
    animation^.FirstChildId = -1
    animation^.ParentId = parentId
    animation^.NextSibling = -1

    return newIndex
}

@(export)
create_new_point :: proc "c" (
    state: ^core.EuclidGeneralState,
    pos: core.Vector3, color: BridgeColor, brushSize: f32) -> BridgePointView {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    point, index := kine.init_kineshape_point(
        state^.PointSystem, pos, rlColor, brushSize)

    pos, hasPos := point^.Position.?
    color, hasColor := point^.Color.?
    activeColor, hasActiveColor := point^.ActiveColor.?

    return BridgePointView{
        Valid = true,
        Index = index,

        PointType = 0,
        DoDraw = point^.DoDraw,
        BrushSize = point^.BrushSize,

        HasPosition = hasPos,
        Position = pos,

        HasColor = hasColor,
        Color = BridgeColor{ color.r, color.g, color.b, color.a },

        HasActiveColor = hasActiveColor,
        ActiveColor = BridgeColor{ activeColor.r, activeColor.g, activeColor.b, activeColor.a },

        ActiveChild = point^.ActiveChild,
        ChildCount = point^.ChildCount,
        ChildPointHead = point^.ChildPointHead,
        NextChildPoint = point^.NextChildPoint,
    }
}

@(export)
create_new_line :: proc "c" (
    state: ^core.EuclidGeneralState,
    point1, point2: core.Vector3, color: BridgeColor, brushSize: f32) -> core.KineShapeLine {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    line := kine.init_kineshape_line(
        state^.PointSystem, point1, point2, rlColor, brushSize)

    return line
}

@(export)
create_new_circle :: proc "c" (
    state: ^core.EuclidGeneralState,
    center: core.Vector3, radius, startTheta, endTheta: f32,
    color: BridgeColor, brushSize: f32) -> core.KineShapeCircle {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    circle := kine.init_kineshape_circle(
        state^.PointSystem, center, radius, startTheta, endTheta, rlColor, brushSize)

    return circle
}

@(export)
create_new_filledcircle :: proc "c" (
    state: ^core.EuclidGeneralState,
    center: core.Vector3, radius, startTheta, endTheta: f32,
    color: BridgeColor, brushSize: f32) -> core.KineShapeFilledCircle {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    circle := kine.init_kineshape_filledcircle(
        state^.PointSystem, center, radius, startTheta, endTheta, rlColor, brushSize)

    return circle
}

@(export)
create_new_triangle :: proc "c" (
    state: ^core.EuclidGeneralState,
    point1, point2, point3: core.Vector3, color: BridgeColor) -> core.KineShapeTriangle {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    line := kine.init_kineshape_triangle(
        state^.PointSystem, point1, point2, point3, rlColor)

    return line
}

@(export)
create_new_square :: proc "c" (
    state: ^core.EuclidGeneralState,
    point1, point2, point3, point4: core.Vector3, color: BridgeColor) -> core.KineShapeSquare {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    line := kine.init_kineshape_square(
        state^.PointSystem, point1, point2, point3, point4, rlColor)

    return line
}

@(export)
create_new_pentagon :: proc "c" (
    state: ^core.EuclidGeneralState,
    point1, point2, point3, point4, point5: core.Vector3,
    color: BridgeColor) -> core.KineShapePentagon {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    line := kine.init_kineshape_pentagon(
        state^.PointSystem, point1, point2, point3, point4, point5, rlColor)

    return line
}

@(export)
get_point_view :: proc "c" (
    state: ^core.EuclidGeneralState,
    index: int) -> BridgePointView {

    if index >= 0 && index < MAX_KINEPOINTS {
        point := state^.PointSystem^.Points[index]
        type: int = 0
        switch point.Type {
            case .Point:
                type = 0
            case .Line:
                type = 1
            case .Circle:
                type = 2
            case .FilledCircle:
                type = 3
            case .Triangle:
                type = 4
            case .Square:
                type = 5
            case .Pentagon:
                type = 6
            case .Pen:
                type = 10
            case .Compass:
                type = 50
        }
        pos, hasPos := point.Position.?
        color, hasColor := point.Color.?
        activeColor, hasActiveColor := point.ActiveColor.?

        return BridgePointView{
            Valid = true,
            Index = index,

            PointType = type,
            DoDraw = point.DoDraw,
            BrushSize = point.BrushSize,

            HasPosition = hasPos,
            Position = pos,

            HasColor = hasColor,
            Color = BridgeColor{ color.r, color.g, color.b, color.a },

            HasActiveColor = hasActiveColor,
            ActiveColor = BridgeColor{ activeColor.r, activeColor.g, activeColor.b, activeColor.a },

            ActiveChild = point.ActiveChild,
            ChildCount = point.ChildCount,
            ChildPointHead = point.ChildPointHead,
            NextChildPoint = point.NextChildPoint,
        }
    }

    return BridgePointView{
        Valid = false,
        Index = -1,
        
        PointType = -1,
        DoDraw = false,
        BrushSize = 0,

        HasPosition = false,
        Position = {0, 0, 0},

        HasColor = false,
        Color = BridgeColor{ 0, 0, 0, 0 },

        HasActiveColor = false,
        ActiveColor = BridgeColor{ 0, 0, 0, 0 },

        ActiveChild = 0,
        ChildCount = 0,
        ChildPointHead = 0,
        NextChildPoint = 0,
    }
}


@(export)
show_point :: proc "c" (state: ^core.EuclidGeneralState, index: int) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].DoDraw = true
    }
}

@(export)
hide_point :: proc "c" (state: ^core.EuclidGeneralState, index: int) {
    if index >= 0 && index < MAX_KINEPOINTS {
        context = state^.SavedContext
        particles.emit_kine_hide_burst(state^.ParticleSystem, state^.PointSystem, index, true)
        state^.PointSystem^.Points[index].DoDraw = false
    }
}

@(export)
hide_point_batch :: proc "c" (state: ^core.EuclidGeneralState, indices: [^]i32, count: i32) {
    if count <= 0 {
        return
    }
    context = state^.SavedContext
    particles.kick_existing_dust(state^.ParticleSystem)
    for i in 0..<int(count) {
        index := int(indices[i])
        if index >= 0 && index < MAX_KINEPOINTS {
            particles.emit_kine_hide_burst(state^.ParticleSystem, state^.PointSystem, index, false)
            state^.PointSystem^.Points[index].DoDraw = false
        }
    }
}

@(export)
set_point_position :: proc "c" (state: ^core.EuclidGeneralState, index: int, pos: core.Vector3) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
    }
}

@(export)
set_point_brush :: proc "c" (state: ^core.EuclidGeneralState, index: int, brushSize: f32) {
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].BrushSize = brushSize
    }
}

@(export)
set_point_color :: proc "c" (state: ^core.EuclidGeneralState, index: int, color: BridgeColor) {
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.PointSystem^.Points[index].Color = rlColor
    }
}

@(export)
set_point_active_color :: proc "c" (state: ^core.EuclidGeneralState, index: int, color: BridgeColor) {
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.PointSystem^.Points[index].ActiveColor = rlColor
    }
}

@(export)
get_bridge_version :: proc "c" () -> i32 {
    return BRIDGE_VERSION
}

@(export)
get_bridge_feature_flags :: proc "c" () -> i32 {
    return BRIDGE_FEATURE_FLAGS
}

@(export)
get_point_capacity :: proc "c" () -> i32 {
    return i32(MAX_KINEPOINTS)
}

@(export)
get_point_next_index :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    return i32(state^.PointSystem^.NextPointIndex)
}

@(export)
is_point_index_in_range :: proc "c" (state: ^core.EuclidGeneralState, index: i32) -> u8 {
    context = state^.SavedContext
    _ = state
    return to_u8(is_point_index_in_bounds(int(index)))
}

@(export)
set_point_draw_enabled :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, enabled: u8) -> i32 {

    context = state^.SavedContext

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].DoDraw = enabled != 0
    return BRIDGE_STATUS_OK
}

@(export)
set_point_position_status :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, pos: core.Vector3) -> i32 {

    context = state^.SavedContext

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].Position = pos
    return BRIDGE_STATUS_OK
}

@(export)
clear_point_position :: proc "c" (state: ^core.EuclidGeneralState, index: i32) -> i32 {
    context = state^.SavedContext
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].Position = nil
    return BRIDGE_STATUS_OK
}

@(export)
set_point_color_status :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, color: BridgeColor) -> i32 {

    context = state^.SavedContext

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    state^.PointSystem^.Points[pointIndex].Color = rlColor
    return BRIDGE_STATUS_OK
}

@(export)
clear_point_color :: proc "c" (state: ^core.EuclidGeneralState, index: i32) -> i32 {
    context = state^.SavedContext
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].Color = nil
    return BRIDGE_STATUS_OK
}

@(export)
set_point_active_color_status :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, color: BridgeColor) -> i32 {

    context = state^.SavedContext

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    state^.PointSystem^.Points[pointIndex].ActiveColor = rlColor
    return BRIDGE_STATUS_OK
}

@(export)
clear_point_active_color :: proc "c" (state: ^core.EuclidGeneralState, index: i32) -> i32 {
    context = state^.SavedContext
    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].ActiveColor = nil
    return BRIDGE_STATUS_OK
}

@(export)
set_point_brush_size :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, brush: f32) -> i32 {

    context = state^.SavedContext

    pointIndex := int(index)
    if !is_point_index_in_bounds(pointIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Points[pointIndex].BrushSize = brush
    return BRIDGE_STATUS_OK
}

@(export)
attach_child_point :: proc "c" (
    state: ^core.EuclidGeneralState, parentIndex, childIndex: i32) -> i32 {

    context = state^.SavedContext

    parent := int(parentIndex)
    child := int(childIndex)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if parent == child {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    parentPoint := &state^.PointSystem^.Points[parent]
    childPoint := &state^.PointSystem^.Points[child]

    if childPoint^.NextChildPoint >= 0 {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parentPoint^.ChildPointHead < 0 {
        parentPoint^.ChildPointHead = child
        parentPoint^.ChildCount = 1
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.ChildPointHead
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
        next := state^.PointSystem^.Points[current].NextChildPoint
        if next < 0 {
            break
        }
        current = next
    }

    state^.PointSystem^.Points[tail].NextChildPoint = child
    parentPoint^.ChildCount = count + 1
    return BRIDGE_STATUS_OK
}

@(export)
detach_child_point :: proc "c" (
    state: ^core.EuclidGeneralState, parentIndex, childIndex: i32) -> i32 {

    context = state^.SavedContext

    parent := int(parentIndex)
    child := int(childIndex)
    if !is_point_index_in_bounds(parent) || !is_point_index_in_bounds(child) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.PointSystem^.Points[parent]
    head := parentPoint^.ChildPointHead
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

        next := state^.PointSystem^.Points[current].NextChildPoint
        if current == child {
            removed = true
            if prev < 0 {
                parentPoint^.ChildPointHead = next
            } else {
                state^.PointSystem^.Points[prev].NextChildPoint = next
            }
            state^.PointSystem^.Points[current].NextChildPoint = -1
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

@(export)
rebuild_child_count :: proc "c" (state: ^core.EuclidGeneralState, parentIndex: i32) -> i32 {
    context = state^.SavedContext
    parent := int(parentIndex)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.PointSystem^.Points[parent]
    if parentPoint^.ChildPointHead < 0 {
        parentPoint^.ChildCount = 0
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.ChildPointHead
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
        current = state^.PointSystem^.Points[current].NextChildPoint
    }

    parentPoint^.ChildCount = count
    return BRIDGE_STATUS_OK
}

@(export)
validate_parent_child_chain :: proc "c" (
    state: ^core.EuclidGeneralState, parentIndex: i32) -> i32 {

    context = state^.SavedContext

    parent := int(parentIndex)
    if !is_point_index_in_bounds(parent) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    parentPoint := &state^.PointSystem^.Points[parent]
    if parentPoint^.ChildPointHead < 0 {
        if parentPoint^.ChildCount != 0 {
            return BRIDGE_STATUS_INVALID_GRAPH
        }
        return BRIDGE_STATUS_OK
    }

    visited: [MAX_KINEPOINTS]bool
    current := parentPoint^.ChildPointHead
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
        current = state^.PointSystem^.Points[current].NextChildPoint
    }

    if parentPoint^.ChildCount != count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    if parentPoint^.ActiveChild < -1 || parentPoint^.ActiveChild >= count {
        return BRIDGE_STATUS_INVALID_GRAPH
    }

    return BRIDGE_STATUS_OK
}

@(export)
get_constraint_capacity :: proc "c" () -> i32 {
    return i32(MAX_KINECONSTRAINTS)
}

@(export)
get_constraint_next_index :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    return i32(state^.PointSystem^.NextConstraintIndex)
}

@(export)
is_constraint_index_in_range :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32) -> u8 {

    context = state^.SavedContext

    _ = state
    return to_u8(is_constraint_index_in_bounds(int(index)))
}

@(export)
get_constraint_view :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32) -> BridgeConstraintView {

    context = state^.SavedContext

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return constraint_view_invalid()
    }

    constraint := state^.PointSystem^.Constraints[constraintIndex]
    childOffset, hasChildOffset := constraint.ChildOffset.?

    return BridgeConstraintView{
        Valid = 1,
        Index = index,
        Traits = i32(constraint.Traits),
        OnPoint = i32(constraint.OnPoint),
        Restriction = constraint.Restriction,
        Bounce = constraint.Bounce,
        Allowance = constraint.Allowance,
        DependOn = constraint.DependOn,
        HasChildOffset = to_u8(hasChildOffset),
        ChildOffset = childOffset,
        DoApply = to_u8(constraint.DoApply),
    }
}

@(export)
create_constraint :: proc "c" (
    state: ^core.EuclidGeneralState, spec: BridgeConstraintSpec, outIndex: ^i32) -> i32 {

    context = state^.SavedContext

    if !is_valid_constraint_traits_mask(spec.Traits) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    onPoint := int(spec.OnPoint)
    if !is_point_index_in_bounds(onPoint) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.DependOn >= 0 && !is_constraint_index_in_bounds(int(spec.DependOn)) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.HasChildOffset != 0 && spec.ChildOffset < 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    nextIndex := state^.PointSystem^.NextConstraintIndex
    if nextIndex < 0 || nextIndex >= MAX_KINECONSTRAINTS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }

    state^.PointSystem^.Constraints[nextIndex] = core.KineConstraint{
        Traits = core.KineConstraintTrait(spec.Traits),
        OnPoint = onPoint,
        Restriction = spec.Restriction,
        Bounce = spec.Bounce,
        Allowance = spec.Allowance,
        DependOn = spec.DependOn,
        ChildOffset = nil,
        DoApply = spec.DoApply != 0,
    }
    if spec.HasChildOffset != 0 {
        state^.PointSystem^.Constraints[nextIndex].ChildOffset = spec.ChildOffset
    }

    state^.PointSystem^.NextConstraintIndex += 1
    if outIndex != nil {
        outIndex^ = i32(nextIndex)
    }
    return BRIDGE_STATUS_OK
}

@(export)
update_constraint :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, specMask: i32, spec: BridgeConstraintSpec) -> i32 {

    context = state^.SavedContext

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.PointSystem^.Constraints[constraintIndex]

    if specMask & CONSTRAINT_SPEC_TRAITS != 0 {
        if !is_valid_constraint_traits_mask(spec.Traits) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        constraint^.Traits = core.KineConstraintTrait(spec.Traits)
    }
    if specMask & CONSTRAINT_SPEC_ONPOINT != 0 {
        onPoint := int(spec.OnPoint)
        if !is_point_index_in_bounds(onPoint) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.OnPoint = onPoint
    }
    if specMask & CONSTRAINT_SPEC_RESTRICTION != 0 {
        constraint^.Restriction = spec.Restriction
    }
    if specMask & CONSTRAINT_SPEC_BOUNCE != 0 {
        constraint^.Bounce = spec.Bounce
    }
    if specMask & CONSTRAINT_SPEC_ALLOWANCE != 0 {
        constraint^.Allowance = spec.Allowance
    }
    if specMask & CONSTRAINT_SPEC_DEPENDON != 0 {
        if spec.DependOn >= 0 && !is_constraint_index_in_bounds(int(spec.DependOn)) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.DependOn = spec.DependOn
    }
    if specMask & CONSTRAINT_SPEC_CHILDOFFSET != 0 {
        if spec.HasChildOffset != 0 {
            if spec.ChildOffset < 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            constraint^.ChildOffset = spec.ChildOffset
        } else {
            constraint^.ChildOffset = nil
        }
    }
    if specMask & CONSTRAINT_SPEC_DOAPPLY != 0 {
        constraint^.DoApply = spec.DoApply != 0
    }

    return BRIDGE_STATUS_OK
}

@(export)
set_constraint_enabled :: proc "c" (
    state: ^core.EuclidGeneralState, index: i32, enabled: u8) -> i32 {

    context = state^.SavedContext

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Constraints[constraintIndex].DoApply = enabled != 0
    return BRIDGE_STATUS_OK
}

@(export)
clear_constraint :: proc "c" (state: ^core.EuclidGeneralState, index: i32) -> i32 {
    context = state^.SavedContext
    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.PointSystem^.Constraints[constraintIndex] = {}
    state^.PointSystem^.Constraints[constraintIndex].DoApply = false
    return BRIDGE_STATUS_OK
}

@(export)
get_total_constraint_error_bridge :: proc "c" (
    state: ^core.EuclidGeneralState) -> f32 {
    context = state^.SavedContext
    return kine.get_total_constraint_error(state^.PointSystem)
}

@(export)
get_constraint_error_bridge :: proc "c" (
    state: ^core.EuclidGeneralState, constraintIndex: i32, outError: ^f32) -> i32 {

    context = state^.SavedContext

    idx := int(constraintIndex)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if outError == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    constraint := &state^.PointSystem^.Constraints[idx]
    outError^ = kine.get_constraint_error(constraint, &state^.PointSystem^.Points)
    return BRIDGE_STATUS_OK
}

@(export)
apply_constraint_bridge :: proc "c" (
    state: ^core.EuclidGeneralState, constraintIndex: i32) -> i32 {

    context = state^.SavedContext

    idx := int(constraintIndex)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.PointSystem^.Constraints[idx]
    kine.apply_constraint(constraint, &state^.PointSystem^.Points)
    return BRIDGE_STATUS_OK
}

@(export)
apply_all_constraints_bridge :: proc "c" (
    state: ^core.EuclidGeneralState, reverse: u8) -> i32 {

    context = state^.SavedContext

    if reverse != 0 {
        kine.apply_all_constraints_reverse(state^.PointSystem)
    } else {
        kine.apply_all_constraints(state^.PointSystem)
    }
    return BRIDGE_STATUS_OK
}

@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.EuclidGeneralState, allowableError: f32, maxIterations: i32) -> BridgeSolveResult {

    context = state^.SavedContext

    if allowableError < 0 {
        return BridgeSolveResult{
            Status = BRIDGE_STATUS_INVALID_ARGUMENT,
            Iterations = 0,
            InitialError = 0,
            FinalError = 0,
            Converged = 0,
        }
    }

    iterationLimit := maxIterations
    if iterationLimit <= 0 {
        iterationLimit = 32
    }
    if iterationLimit > 4096 {
        iterationLimit = 4096
    }

    initialError := kine.get_total_constraint_error(state^.PointSystem)
    if initialError <= allowableError {
        return BridgeSolveResult{
            Status = BRIDGE_STATUS_OK,
            Iterations = 0,
            InitialError = initialError,
            FinalError = initialError,
            Converged = 1,
        }
    }

    reverse := false
    error := initialError
    iterations: i32 = 0
    for iterations < iterationLimit && error > allowableError {
        if reverse {
            kine.apply_all_constraints_reverse(state^.PointSystem)
        } else {
            kine.apply_all_constraints(state^.PointSystem)
        }
        reverse = !reverse
        iterations += 1
        error = kine.get_total_constraint_error(state^.PointSystem)
    }

    converged := error <= allowableError
    status := BRIDGE_STATUS_NON_CONVERGED
    if converged {
        status = BRIDGE_STATUS_OK
    }

    return BridgeSolveResult{
        Status = status,
        Iterations = iterations,
        InitialError = initialError,
        FinalError = error,
        Converged = to_u8(converged),
    }
}

@(export)
get_shape_line_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapeLine {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapeLine{ -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .Line {
        return core.KineShapeLine{ -1, -1, -1 }
    }

    p1 := point.ChildPointHead
    if !is_point_index_in_bounds(p1) {
        return core.KineShapeLine{ -1, -1, -1 }
    }
    p2 := state^.PointSystem^.Points[p1].NextChildPoint
    if !is_point_index_in_bounds(p2) {
        return core.KineShapeLine{ -1, -1, -1 }
    }

    return core.KineShapeLine{ host, p1, p2 }
}

@(export)
get_shape_circle_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapeCircle {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapeCircle{ -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .Circle {
        return core.KineShapeCircle{ -1, -1, -1 }
    }

    start := point.ChildPointHead
    if !is_point_index_in_bounds(start) {
        return core.KineShapeCircle{ -1, -1, -1 }
    }
    finish := state^.PointSystem^.Points[start].NextChildPoint
    if !is_point_index_in_bounds(finish) {
        return core.KineShapeCircle{ -1, -1, -1 }
    }

    return core.KineShapeCircle{ host, start, finish }
}

@(export)
get_shape_filledcircle_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapeFilledCircle {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapeFilledCircle{ -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .FilledCircle {
        return core.KineShapeFilledCircle{ -1, -1, -1 }
    }

    start := point.ChildPointHead
    if !is_point_index_in_bounds(start) {
        return core.KineShapeFilledCircle{ -1, -1, -1 }
    }
    finish := state^.PointSystem^.Points[start].NextChildPoint
    if !is_point_index_in_bounds(finish) {
        return core.KineShapeFilledCircle{ -1, -1, -1 }
    }

    return core.KineShapeFilledCircle{ host, start, finish }
}

@(export)
get_shape_triangle_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapeTriangle {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapeTriangle{ -1, -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .Triangle {
        return core.KineShapeTriangle{ -1, -1, -1, -1 }
    }

    p1 := point.ChildPointHead
    if !is_point_index_in_bounds(p1) {
        return core.KineShapeTriangle{ -1, -1, -1, -1 }
    }
    p2 := state^.PointSystem^.Points[p1].NextChildPoint
    if !is_point_index_in_bounds(p2) {
        return core.KineShapeTriangle{ -1, -1, -1, -1 }
    }
    p3 := state^.PointSystem^.Points[p2].NextChildPoint
    if !is_point_index_in_bounds(p3) {
        return core.KineShapeTriangle{ -1, -1, -1, -1 }
    }

    return core.KineShapeTriangle{ host, p1, p2, p3 }
}

@(export)
get_shape_square_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapeSquare {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .Square {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }

    p1 := point.ChildPointHead
    if !is_point_index_in_bounds(p1) {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }
    p2 := state^.PointSystem^.Points[p1].NextChildPoint
    if !is_point_index_in_bounds(p2) {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }
    p3 := state^.PointSystem^.Points[p2].NextChildPoint
    if !is_point_index_in_bounds(p3) {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }
    p4 := state^.PointSystem^.Points[p3].NextChildPoint
    if !is_point_index_in_bounds(p4) {
        return core.KineShapeSquare{ -1, -1, -1, -1, -1 }
    }

    return core.KineShapeSquare{ host, p1, p2, p3, p4 }
}

@(export)
get_shape_pentagon_view :: proc "c" (
    state: ^core.EuclidGeneralState, hostId: i32) -> core.KineShapePentagon {

    context = state^.SavedContext
    host := int(hostId)
    if !is_point_index_in_bounds(host) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }

    point := state^.PointSystem^.Points[host]
    if point.Type != .Pentagon {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }

    p1 := point.ChildPointHead
    if !is_point_index_in_bounds(p1) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p2 := state^.PointSystem^.Points[p1].NextChildPoint
    if !is_point_index_in_bounds(p2) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p3 := state^.PointSystem^.Points[p2].NextChildPoint
    if !is_point_index_in_bounds(p3) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p4 := state^.PointSystem^.Points[p3].NextChildPoint
    if !is_point_index_in_bounds(p4) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }
    p5 := state^.PointSystem^.Points[p4].NextChildPoint
    if !is_point_index_in_bounds(p5) {
        return core.KineShapePentagon{ -1, -1, -1, -1, -1, -1 }
    }

    return core.KineShapePentagon{ host, p1, p2, p3, p4, p5 }
}

@(export)
get_pen_view :: proc "c" (state: ^core.EuclidGeneralState) -> core.KineShapePen {
    return state^.Pen
}

@(export)
get_compass_view :: proc "c" (state: ^core.EuclidGeneralState) -> core.KineShapeCompass {
    return state^.Compass
}

@(export)
get_kine_anim_points_start :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    return i32(state^.PointSystem^.AnimPointsStart)
}

@(export)
get_kine_anim_constraints_start :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    return i32(state^.PointSystem^.AnimConstraintsStart)
}

@(export)
freeze_kine_animation_boundary :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    context = state^.SavedContext
    kine.kine_freeze_system_indices(state^.PointSystem)
    return BRIDGE_STATUS_OK
}

@(export)
clear_kine_animation_data :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    context = state^.SavedContext
    kine.kine_clear_animation_data(state^.PointSystem, state^.ParticleSystem)
    return BRIDGE_STATUS_OK
}

@(export)
get_max_kine_points :: proc "c" () -> i32 {
    return i32(MAX_KINEPOINTS)
}

@(export)
get_max_kine_constraints :: proc "c" () -> i32 {
    return i32(MAX_KINECONSTRAINTS)
}

@(export)
validate_kine_graph :: proc "c" (state: ^core.EuclidGeneralState) -> i32 {
    context = state^.SavedContext

    for i in 0..<MAX_KINEPOINTS {
        point := state^.PointSystem^.Points[i]
        if point.ChildPointHead >= 0 {
            validateStatus := validate_parent_child_chain(state, i32(i))
            if validateStatus != BRIDGE_STATUS_OK {
                return validateStatus
            }
        }
    }

    for i in 0..<MAX_KINECONSTRAINTS {
        constraint := state^.PointSystem^.Constraints[i]
        if constraint.DoApply {
            if !is_point_index_in_bounds(constraint.OnPoint) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
            if constraint.DependOn >= 0 && !is_constraint_index_in_bounds(int(constraint.DependOn)) {
                return BRIDGE_STATUS_INVALID_CONSTRAINT
            }
        }
    }

    return BRIDGE_STATUS_OK
}


@(export)
show_pen :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].DoDraw = true
    }
}

@(export)
hide_pen :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].DoDraw = false
    }
}

@(export)
set_pen_active :: proc "c" (
    state: ^core.EuclidGeneralState, active: int, color: BridgeColor) {

    index := state^.Pen.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.PointSystem^.Points[index].ActiveColor = rlColor
        state^.PointSystem^.Points[index].ActiveChild = active
    }
}

@(export)
clear_pen_active :: proc "c" (
    state: ^core.EuclidGeneralState) {

    index := state^.Pen.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].ActiveChild = -1
    }
}

@(export)
lock_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Pen.Joint1Id
    constraintIndex := state^.Pen.LockPoint1Id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[constraintIndex].Restriction = pos
        state^.PointSystem^.Constraints[constraintIndex].DoApply = true
    }
}

@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen.LockPoint1Id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[index].DoApply = false
    }
}

@(export)
move_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Pen.Joint1Id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
    }
}

@(export)
get_pen_joint1_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Pen.Joint1Id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.PointSystem^.Points[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
lock_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Pen.Joint2Id
    constraintIndex := state^.Pen.LockPoint2Id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[constraintIndex].Restriction = pos
        state^.PointSystem^.Constraints[constraintIndex].DoApply = true
    }
}

@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen.LockPoint2Id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[index].DoApply = false
    }
}

@(export)
move_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Pen.Joint2Id
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
    }
}

@(export)
get_pen_joint2_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Pen.Joint2Id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.PointSystem^.Points[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
show_compass :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].DoDraw = true
    }
}

@(export)
hide_compass :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].DoDraw = false
    }
}

@(export)
set_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState, active: int, color: BridgeColor) {

    index := state^.Compass.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.PointSystem^.Points[index].ActiveColor = rlColor
        state^.PointSystem^.Points[index].ActiveChild = active
    }
}

@(export)
clear_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState) {

    index := state^.Compass.HostId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].ActiveChild = -1
    }
}

@(export)
lock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    pointIndex := state^.Compass.Joint1Id
    pivotIndex := state^.Compass.PivotId
    constraintIndex := state^.Compass.LockPoint1Id
    if pointIndex > 0 && pointIndex < MAX_KINEPOINTS {
        state^.PointSystem^.Points[pointIndex].Position = pos
        push_dust_if_floor_contact(state, pos)
        push_dust_for_compass_segment_if_floor_contact(state)
    
        pointpos := state^.PointSystem^.Points[pointIndex].Position.? or_else { 0, 0, 0 }
        pivotpos := state^.PointSystem^.Points[pivotIndex].Position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.PointSystem^.Points[pivotIndex].Position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[constraintIndex].Restriction = pos
        state^.PointSystem^.Constraints[constraintIndex].DoApply = true
    }
}

@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass.LockPoint1Id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[index].DoApply = false
    }
}

@(export)
move_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Compass.Joint1Id
    pivotIndex := state^.Compass.PivotId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
        push_dust_for_compass_segment_if_floor_contact(state)

        pointpos := state^.PointSystem^.Points[index].Position.? or_else { 0, 0, 0 }
        pivotpos := state^.PointSystem^.Points[pivotIndex].Position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.PointSystem^.Points[pivotIndex].Position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

@(export)
get_compass_joint1_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Compass.Joint1Id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.PointSystem^.Points[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
lock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    pointIndex := state^.Compass.Joint2Id
    pivotIndex := state^.Compass.PivotId
    constraintIndex := state^.Compass.LockPoint2Id
    if pointIndex > 0 && pointIndex < MAX_KINEPOINTS {
        state^.PointSystem^.Points[pointIndex].Position = pos
        push_dust_if_floor_contact(state, pos)
        push_dust_for_compass_segment_if_floor_contact(state)

        pointpos := state^.PointSystem^.Points[pointIndex].Position.? or_else { 0, 0, 0 }
        pivotpos := state^.PointSystem^.Points[pivotIndex].Position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.PointSystem^.Points[pivotIndex].Position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
    if constraintIndex >= 0 && constraintIndex < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[constraintIndex].Restriction = pos
        state^.PointSystem^.Constraints[constraintIndex].DoApply = true
    }
}

@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass.LockPoint2Id
    if index >= 0 && index < MAX_KINECONSTRAINTS {
        state^.PointSystem^.Constraints[index].DoApply = false
    }
}

@(export)
move_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    context = state^.SavedContext
    index := state^.Compass.Joint2Id
    pivotIndex := state^.Compass.PivotId
    if index >= 0 && index < MAX_KINEPOINTS {
        state^.PointSystem^.Points[index].Position = pos
        push_dust_if_floor_contact(state, pos)
        push_dust_for_compass_segment_if_floor_contact(state)

        pointpos := state^.PointSystem^.Points[index].Position.? or_else { 0, 0, 0 }
        pivotpos := state^.PointSystem^.Points[pivotIndex].Position.? or_else { 0, 0, 0 }
        if pointpos.z >= pivotpos.z {
            state^.PointSystem^.Points[pivotIndex].Position =
                core.Vector3{ pivotpos.x, pivotpos.z, pointpos.z + 0.01 }
        }
    }
}

@(export)
get_compass_joint2_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Compass.Joint2Id
    if index >= 0 && index < MAX_KINEPOINTS {
        return state^.PointSystem^.Points[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
set_animation_meta :: proc "c" (state: ^core.EuclidGeneralState, pos: int, metadata: f32) {
    if pos >= 0 && pos <= len(state^.AnimMetadata) {
        state^.AnimMetadata[pos] = metadata
    }
}

@(export)
get_animation_meta :: proc "c" (state: ^core.EuclidGeneralState, pos: int) -> f32 {
    if pos >= 0 && pos <= len(state^.AnimMetadata) {
        return state^.AnimMetadata[pos]
    }
    return 0;
}

@(export)
emit_trailing_particle :: proc "c" (
    state: ^core.EuclidGeneralState, pos: core.Vector2, color: BridgeColor) {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    particles.emit_trail_particles(
        state^.ParticleSystem, state^.CurrentDeltaTime, pos.x, pos.y, rlColor)
}

@(export)
emit_flicker_particle :: proc "c" (
    state: ^core.EuclidGeneralState, pos: core.Vector2, color: BridgeColor) {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    particles.emit_flicker_particles(state^.ParticleSystem, pos.x, pos.y, rlColor, 10)
}
