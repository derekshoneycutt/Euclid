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
        Color = BridgeColor{ color.r, color.g, color.r, color.a },

        HasActiveColor = hasActiveColor,
        ActiveColor = BridgeColor{ activeColor.r, activeColor.g, activeColor.r, activeColor.a },

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
            case .Pen:
                type = 4
            case .Compass:
                type = 5
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
            Color = BridgeColor{ color.r, color.g, color.r, color.a },

            HasActiveColor = hasActiveColor,
            ActiveColor = BridgeColor{ activeColor.r, activeColor.g, activeColor.r, activeColor.a },

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
        particles.emit_kine_hide_burst(state^.ParticleSystem, state^.PointSystem, index)
        state^.PointSystem^.Points[index].DoDraw = false
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
