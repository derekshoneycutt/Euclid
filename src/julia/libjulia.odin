package julia

import "base:runtime"
import "core:c"
import "core:fmt"

Jl_Value_T  :: struct {}
Jl_Module_T :: struct {}
Jl_Function_T :: struct {}

foreign import libjulia "system:julia"
foreign libjulia {
    jl_init        :: proc() ---
    jl_atexit_hook :: proc(status: c.int) ---

    jl_eval_string :: proc(code: cstring) -> rawptr ---

    jl_base_module: ^Jl_Module_T

    jl_get_function :: proc(m: ^Jl_Module_T, name: cstring) -> ^Jl_Function_T ---

    jl_box_float64 :: proc(f: f64) -> ^Jl_Value_T ---
    jl_box_float32 :: proc(f: f32) -> ^Jl_Value_T ---
    jl_box_int64 :: proc(f: i64) -> ^Jl_Value_T ---
    jl_box_int32 :: proc(f: i32) -> ^Jl_Value_T ---

    jl_call0 :: proc(f: ^Jl_Function_T) -> Jl_Value_T ---
    jl_call1 :: proc(f: ^Jl_Function_T, a: ^Jl_Value_T) -> Jl_Value_T ---
    jl_call2 :: proc(f: ^Jl_Function_T, a, b: ^Jl_Value_T) -> Jl_Value_T ---
    jl_call3 :: proc(f: ^Jl_Function_T, a, b, c: ^Jl_Value_T) -> Jl_Value_T ---
    jl_call4 :: proc(f: ^Jl_Function_T, a, b, c, d: ^Jl_Value_T) -> Jl_Value_T ---

    jl_unbox_float64 :: proc(v: ^Jl_Value_T) -> f64 ---
    jl_unbox_float32 :: proc(v: ^Jl_Value_T) -> f32 ---
    jl_unbox_int64 :: proc(v: ^Jl_Value_T) -> i64 ---
    jl_unbox_int32 :: proc(v: ^Jl_Value_T) -> i32 ---
}

initiate_julia :: proc() {
    jl_init()
    _ = jl_eval_string("include(\"./julia/scriptbase.jl\")")
}

end_julia :: proc() {
    jl_atexit_hook(0)
}

// TODO: Do we need more helper functions, etc? Maybe? Idk,
// it's still just nice importing them as a single module, y'know

@(export)
c_add_numbers :: proc "c" (a, b: c.double) -> c.double {
    context = runtime.default_context()
    fmt.println("[Odin] Adding ", a, " and ", b)
    return a + b
}
