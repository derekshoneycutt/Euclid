package julia

import "../core"
import "../particles"

import "base:runtime"
import "core:c"
import "core:fmt"

import rl "vendor:raylib"

Jl_Value_T  :: struct {}
Jl_Symbol_T  :: struct {}
Jl_Module_T :: struct {}

Bridge_Color :: struct {
    R: u8,
    G: u8,
    B: u8,
    A: u8,
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
		// TODO: inspect or print the exception here in the final implementation
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
		// TODO: inspect or print the exception here in the final implementation
		return
	}

	_ = result
}

end_julia :: proc() {
    jl_atexit_hook(0)
}




@(export)
set_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState, active: int, color: Bridge_Color) {

    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    state^.Compass^.Host^.ActiveColor = rlColor
    state^.Compass^.Host^.ActiveChild = active
}

@(export)
clear_compass_active :: proc "c" (
    state: ^core.EuclidGeneralState) {

    state^.Compass^.Host^.ActiveChild = -1
}

@(export)
lock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    state^.Compass^.Joint1^.Position = pos
    state^.Compass^.LockPoint1^.Restriction = pos
    state^.Compass^.LockPoint1^.DoApply = true
}

@(export)
unlock_compass_joint1 :: proc "c" (state: ^core.EuclidGeneralState) {
    state^.Compass^.LockPoint1^.DoApply = false
}

@(export)
lock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState, pos: core.Vector3) {
    state^.Compass^.Joint2^.Position = pos
    state^.Compass^.LockPoint2^.Restriction = pos
    state^.Compass^.LockPoint2^.DoApply = true
}

@(export)
unlock_compass_joint2 :: proc "c" (state: ^core.EuclidGeneralState) {
    state^.Compass^.LockPoint2^.DoApply = false
}

@(export)
set_animation_meta :: proc "c" (state: ^core.EuclidGeneralState, pos: int, metadata: f32) {
    switch pos {
        case 1:
            state^.AnimMetaFloat1 = metadata
        case 2:
            state^.AnimMetaFloat2 = metadata
        case 3:
            state^.AnimMetaFloat3 = metadata
        case 4:
            state^.AnimMetaFloat4 = metadata
        case 5:
            state^.AnimMetaFloat5 = metadata
        case 6:
            state^.AnimMetaFloat6 = metadata
        case 7:
            state^.AnimMetaFloat7 = metadata
        case 8:
            state^.AnimMetaFloat8 = metadata
        case 9:
            state^.AnimMetaFloat9 = metadata
    }
}

@(export)
get_animation_meta :: proc "c" (state: ^core.EuclidGeneralState, pos: int) -> f32 {
    switch pos {
        case 1:
            return state^.AnimMetaFloat1
        case 2:
            return state^.AnimMetaFloat2
        case 3:
            return state^.AnimMetaFloat3
        case 4:
            return state^.AnimMetaFloat4
        case 5:
            return state^.AnimMetaFloat5
        case 6:
            return state^.AnimMetaFloat6
        case 7:
            return state^.AnimMetaFloat7
        case 8:
            return state^.AnimMetaFloat8
        case 9:
            return state^.AnimMetaFloat9
    }
    return 0;
}

@(export)
emit_trailing_particle :: proc "c" (
    state: ^core.EuclidGeneralState, pos: core.Vector2, color: Bridge_Color) {

    context = state^.SavedContext
    rlColor := rl.Color{ color.R, color.G, color.B, color.A }
    particles.emit_trail_particles(
        state^.ParticleSystem, state^.CurrentDeltaTime, pos.x, pos.y, rlColor)
}
