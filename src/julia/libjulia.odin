package julia

import "../core"
import "../particles"
import "../kine"

import "base:runtime"
import "core:c"
import "core:fmt"

import rl "vendor:raylib"

Jl_Value_T  :: struct {}
Jl_Symbol_T  :: struct {}
Jl_Module_T :: struct {}

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


foreign import libjulia "system:julia"
foreign libjulia {
    jl_init        :: proc() ---
    jl_atexit_hook :: proc(status: c.int) ---

    jl_eval_string :: proc(code: cstring) -> rawptr ---

    jl_base_module: ^Jl_Module_T
    jl_main_module: ^Jl_Module_T

    jl_stderr_obj :: proc() -> ^Jl_Value_T ---

    jl_symbol :: proc(str : cstring) -> ^Jl_Symbol_T ---

    jl_get_global :: proc(m : ^Jl_Module_T, var : ^Jl_Symbol_T) -> ^Jl_Value_T ---

    jl_box_bool :: proc(f: i8) -> ^Jl_Value_T ---
    jl_box_float64 :: proc(f: f64) -> ^Jl_Value_T ---
    jl_box_float32 :: proc(f: f32) -> ^Jl_Value_T ---
    jl_box_int64 :: proc(f: i64) -> ^Jl_Value_T ---
    jl_box_int32 :: proc(f: i32) -> ^Jl_Value_T ---
    jl_box_int16 :: proc(f: i16) -> ^Jl_Value_T ---
    jl_box_int8 :: proc(f: i8) -> ^Jl_Value_T ---
    jl_box_voidpointer :: proc(x: rawptr) -> ^Jl_Value_T ---

    jl_call0 :: proc(f: ^Jl_Value_T) -> Jl_Value_T ---
    jl_call1 :: proc(f: ^Jl_Value_T, a: ^Jl_Value_T) -> ^Jl_Value_T ---
    jl_call2 :: proc(f: ^Jl_Value_T, a, b: ^Jl_Value_T) -> ^Jl_Value_T ---
    jl_call3 :: proc(f: ^Jl_Value_T, a, b, c: ^Jl_Value_T) -> ^Jl_Value_T ---
    jl_call4 :: proc(f: ^Jl_Value_T, a, b, c, d: ^Jl_Value_T) -> ^Jl_Value_T ---
    jl_call :: proc(f: ^Jl_Value_T, args: ^^Jl_Value_T, nargs: u32) -> ^Jl_Value_T ---

    jl_exception_occurred :: proc() -> rawptr ---

    jl_typeof_str :: proc(v: rawptr) -> rawptr ---
    jl_string_ptr :: proc(v: ^Jl_Value_T) -> cstring ---

    jl_unbox_bool :: proc(v: ^Jl_Value_T) -> i8 ---
    jl_unbox_float64 :: proc(v: ^Jl_Value_T) -> f64 ---
    jl_unbox_float32 :: proc(v: ^Jl_Value_T) -> f32 ---
    jl_unbox_int64 :: proc(v: ^Jl_Value_T) -> i64 ---
    jl_unbox_int32 :: proc(v: ^Jl_Value_T) -> i32 ---
    jl_unbox_int16 :: proc(v: ^Jl_Value_T) -> i16 ---
    jl_unbox_int8 :: proc(v: ^Jl_Value_T) -> i8 ---
    jl_unbox_voidpointer :: proc(v: ^Jl_Value_T) -> rawptr ---
}

jl_get_function :: #force_inline proc(m : ^Jl_Module_T, name : cstring) -> ^Jl_Value_T {
    return jl_get_global(m, jl_symbol(name))
}

print_julia_exception :: proc(contextOfErr: string) {
    ex_raw := jl_exception_occurred()
    if ex_raw == nil {
        return
    }

    ex := (^Jl_Value_T)(ex_raw)

    ex_type := cstring(jl_typeof_str(ex_raw))

    sprint_fn := jl_get_function(jl_base_module, "sprint")
    showerror_fn := jl_get_function(jl_base_module, "showerror")

    if sprint_fn == nil || showerror_fn == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    args: [2]^Jl_Value_T = {showerror_fn, ex}
    msg_val := jl_call(sprint_fn, &args[0], 2)

    if jl_exception_occurred() != nil || msg_val == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    msg := jl_string_ptr(msg_val)
    fmt.println("Julia exception in ", contextOfErr, " type=", ex_type, " msg=", msg)
}

initiate_julia :: proc() {
    jl_init()
    _ = jl_eval_string("include(\"./julia/scriptbase.jl\")")
    _ = jl_eval_string("include(\"./julia/script.jl\")")
}

init_euclid_scripts :: proc(state: ^core.EuclidGeneralState) {
	func := jl_get_function(jl_main_module, "init_euclid_scripts")
	state_value := jl_box_voidpointer(state)
	result := jl_call1(func, state_value)

	if jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
		return
	}

	_ = result
}

get_global_euclid_loop :: proc() -> ^Jl_Value_T {
	func := jl_get_function(jl_main_module, "global_euclid_loop")
    return func
}

call_global_euclid_loop :: proc(func: ^Jl_Value_T, state: ^core.EuclidGeneralState, dt: f32) {
	state_value := jl_box_voidpointer(state)
    dt_value := jl_box_float32(dt)
	result := jl_call2(func, state_value, dt_value)

	if jl_exception_occurred() != nil {
        print_julia_exception("global_euclid_loop")
		return
	}

	_ = result
}

end_julia :: proc() {
    jl_atexit_hook(0)
}


@(export)
create_new_point :: proc "c" (
    state: ^core.EuclidGeneralState,
    pos: core.Vector3, color: BridgeColor, brushSize: f32) -> BridgePointView {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    point, index := kine.init_kineshape_point(
        state^.KinePoints, pos, rlColor, brushSize)

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
        state^.KinePoints, point1, point2, rlColor, brushSize)

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
        state^.KinePoints, center, radius, startTheta, endTheta, rlColor, brushSize)

    return circle
}

@(export)
get_point_view :: proc "c" (
    state: ^core.EuclidGeneralState,
    index: int) -> BridgePointView {

    if index >= 0 && index <= len(state^.KinePoints^) {
        point := state^.KinePoints^[index]
        type: int = 0
        switch point.Type {
            case .Point:
                type = 0
            case .Line:
                type = 1
            case .Circle:
                type = 2
            case .Pen:
                type = 3
            case .Compass:
                type = 4
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
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = true
    }
}

@(export)
hide_point :: proc "c" (state: ^core.EuclidGeneralState, index: int) {
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = false
    }
}

@(export)
set_point_position :: proc "c" (state: ^core.EuclidGeneralState, index: int, pos: core.Vector3) {
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
}

@(export)
set_point_brush :: proc "c" (state: ^core.EuclidGeneralState, index: int, brushSize: f32) {
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].BrushSize = brushSize
    }
}

@(export)
set_point_color :: proc "c" (state: ^core.EuclidGeneralState, index: int, color: BridgeColor) {
    if index >= 0 && index < len(state^.KinePoints^) {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.KinePoints^[index].Color = rlColor
    }
}

@(export)
set_point_active_color :: proc "c" (state: ^core.EuclidGeneralState, index: int, color: BridgeColor) {
    if index >= 0 && index < len(state^.KinePoints^) {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.KinePoints^[index].ActiveColor = rlColor
    }
}


@(export)
show_pen :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = true
    }
}

@(export)
hide_pen :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = false
    }
}

@(export)
set_pen_active :: proc "c" (
    state: ^core.EuclidGeneralState, active: int, color: BridgeColor) {

    index := state^.Pen^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.KinePoints^[index].ActiveColor = rlColor
        state^.KinePoints^[index].ActiveChild = active
    }
}

@(export)
clear_pen_active :: proc "c" (
    state: ^core.EuclidGeneralState) {

    index := state^.Pen^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].ActiveChild = -1
    }
}

@(export)
lock_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Pen^.Joint1Id
    constraintIndex := state^.Pen^.LockPoint1Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
    if constraintIndex >= 0 && constraintIndex < len(state^.KineConstraints^) {
        state^.KineConstraints^[constraintIndex].Restriction = pos
        state^.KineConstraints^[constraintIndex].DoApply = true
    }
}

@(export)
unlock_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen^.LockPoint1Id
    if index >= 0 && index < len(state^.KineConstraints^) {
        state^.KineConstraints^[index].DoApply = false
    }
}

@(export)
move_pen_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Pen^.Joint1Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
}

@(export)
get_pen_joint1_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Pen^.Joint1Id
    if index >= 0 && index < len(state^.KinePoints^) {
        return state^.KinePoints^[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
lock_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Pen^.Joint2Id
    constraintIndex := state^.Pen^.LockPoint2Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
    if constraintIndex >= 0 && constraintIndex < len(state^.KineConstraints^) {
        state^.KineConstraints^[constraintIndex].Restriction = pos
        state^.KineConstraints^[constraintIndex].DoApply = true
    }
}

@(export)
unlock_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Pen^.LockPoint2Id
    if index >= 0 && index < len(state^.KineConstraints^) {
        state^.KineConstraints^[index].DoApply = false
    }
}

@(export)
move_pen_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Pen^.Joint2Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
}

@(export)
get_pen_joint2_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Pen^.Joint2Id
    if index >= 0 && index < len(state^.KinePoints^) {
        return state^.KinePoints^[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
show_compass :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = true
    }
}

@(export)
hide_compass :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].DoDraw = false
    }
}

@(export)
set_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState, active: int, color: BridgeColor) {

    index := state^.Compass^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        rlColor := rl.Color{ color.R, color.G, color.B, color.A }
        state^.KinePoints^[index].ActiveColor = rlColor
        state^.KinePoints^[index].ActiveChild = active
    }
}

@(export)
clear_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState) {

    index := state^.Compass^.HostId
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].ActiveChild = -1
    }
}

@(export)
lock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    pointIndex := state^.Compass^.Joint1Id
    constraintIndex := state^.Compass^.LockPoint1Id
    if pointIndex > 0 && pointIndex < len(state^.KinePoints^) {
        state^.KinePoints^[pointIndex].Position = pos
    }
    if constraintIndex >= 0 && constraintIndex < len(state^.KineConstraints^) {
        state^.KineConstraints^[constraintIndex].Restriction = pos
        state^.KineConstraints^[constraintIndex].DoApply = true
    }
}

@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass^.LockPoint1Id
    if index >= 0 && index < len(state^.KineConstraints^) {
        state^.KineConstraints^[index].DoApply = false
    }
}

@(export)
move_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Compass^.Joint1Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
}

@(export)
get_compass_joint1_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Compass^.Joint1Id
    if index >= 0 && index < len(state^.KinePoints^) {
        return state^.KinePoints^[index].Position.? or_else {0, 0, 0}
    }
    return {0, 0, 0}
}

@(export)
lock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    pointIndex := state^.Compass^.Joint2Id
    constraintIndex := state^.Compass^.LockPoint2Id
    if pointIndex > 0 && pointIndex < len(state^.KinePoints^) {
        state^.KinePoints^[pointIndex].Position = pos
    }
    if constraintIndex >= 0 && constraintIndex < len(state^.KineConstraints^) {
        state^.KineConstraints^[constraintIndex].Restriction = pos
        state^.KineConstraints^[constraintIndex].DoApply = true
    }
}

@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState) {
    index := state^.Compass^.LockPoint2Id
    if index >= 0 && index < len(state^.KineConstraints^) {
        state^.KineConstraints^[index].DoApply = false
    }
}

@(export)
move_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    index := state^.Compass^.Joint2Id
    if index >= 0 && index < len(state^.KinePoints^) {
        state^.KinePoints^[index].Position = pos
    }
}

@(export)
get_compass_joint2_position :: proc "c" (state: ^core.EuclidGeneralState) -> core.Vector3 {
    index := state^.Compass^.Joint2Id
    if index >= 0 && index < len(state^.KinePoints^) {
        return state^.KinePoints^[index].Position.? or_else {0, 0, 0}
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
