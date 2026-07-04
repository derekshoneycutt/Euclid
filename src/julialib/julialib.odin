package julialib

import "core:c"

// Julia C embedding bindings.
//
// This file mirrors the public embedding surface exported through libjulia as
// far as Odin can reasonably represent it. Macros and a few deeply internal
// helpers are intentionally omitted, but the file covers the common embedding
// workflow: initialize Julia, evaluate code, call functions, root GC values,
// work with arrays, inspect exceptions, and access exported runtime globals.

// The original julia.h that this is based on was MIT license. Recommend treating this file under the same license.
// Copyright (c) 2009-2025: Jeff Bezanson, Stefan Karpinski, Viral B. Shah, and other contributors: https://github.com/JuliaLang/julia/contributors
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

when ODIN_OS == .Windows {
    foreign import jl "system:julia.lib"
} else {
    foreign import jl "system:julia"
}

JL_IMAGE_SEARCH :: enum c.int {
    JL_IMAGE_CWD = 0,
    JL_IMAGE_JULIA_HOME = 1,
    JL_IMAGE_IN_MEMORY = 2,
}

jl_image_kind_t :: enum c.int {
    JL_IMAGE_KIND_NONE = 0,
    JL_IMAGE_KIND_JI = 1,
    JL_IMAGE_KIND_SO = 2,
}

jl_gc_collection_t :: enum c.int {
    JL_GC_AUTO = 0,
    JL_GC_FULL = 1,
    JL_GC_INCREMENTAL = 2,
}

jl_nullable_float64_t :: struct {
    hasvalue: u8,
    value: f64,
}

jl_nullable_float32_t :: struct {
    hasvalue: u8,
    value: f32,
}

jl_options_t :: struct {
    quiet: c.int8_t,
    banner: c.int8_t,
    julia_bindir: cstring,
    julia_bin: cstring,
    cmds: ^cstring,
    image_file: cstring,
    cpu_target: cstring,
    nthreadpools: c.int8_t,
    nthreads: c.int16_t,
    nmarkthreads: c.int16_t,
    nsweepthreads: c.int8_t,
    nthreads_per_pool: ^c.int16_t,
    nprocs: c.int32_t,
    machine_file: cstring,
    project: cstring,
    program_file: cstring,
    isinteractive: c.int8_t,
    color: c.int8_t,
    historyfile: c.int8_t,
    startupfile: c.int8_t,
    compile_enabled: c.int8_t,
    code_coverage: c.int8_t,
    malloc_log: c.int8_t,
    tracked_path: cstring,
    opt_level: c.int8_t,
    opt_level_min: c.int8_t,
    debug_level: c.int8_t,
    check_bounds: c.int8_t,
    depwarn: c.int8_t,
    warn_overwrite: c.int8_t,
    can_inline: c.int8_t,
    polly: c.int8_t,
    trace_compile: cstring,
    trace_dispatch: cstring,
    fast_math: c.int8_t,
    worker: c.int8_t,
    cookie: cstring,
    handle_signals: c.int8_t,
    use_experimental_features: c.int8_t,
    use_sysimage_native_code: c.int8_t,
    use_compiled_modules: c.int8_t,
    use_pkgimages: c.int8_t,
    bindto: cstring,
    outputbc: cstring,
    outputunoptbc: cstring,
    outputo: cstring,
    outputasm: cstring,
    outputji: cstring,
    output_code_coverage: cstring,
    incremental: c.int8_t,
    image_file_specified: c.int8_t,
    warn_scope: c.int8_t,
    image_codegen: c.int8_t,
    rr_detach: c.int8_t,
    strip_metadata: c.int8_t,
    strip_ir: c.int8_t,
    permalloc_pkgimg: c.int8_t,
    heap_size_hint: u64,
    hard_heap_limit: u64,
    heap_target_increment: u64,
    trace_compile_timing: c.int8_t,
    trim: c.int8_t,
    trace_eval: c.int8_t,
    task_metrics: c.int8_t,
    timeout_for_safepoint_straggler_s: c.int16_t,
    gc_sweep_always_full: c.int8_t,
    compress_sysimage: c.int8_t,
    alert_on_critical_error: c.int8_t,
    target_sanitize_memory: c.int8_t,
    target_sanitize_thread: c.int8_t,
    target_sanitize_address: c.int8_t,
}

jl_image_buf_t :: struct {
    kind: jl_image_kind_t,
    pointers: rawptr,
    data: cstring,
    size: c.size_t,
    base: u64,
    checksum: u32,
}

jl_cgparams_t :: struct {
    track_allocations: c.int,
    code_coverage: c.int,
    prefer_specsig: c.int,

    gnu_pubnames: c.int,
    debug_info_kind: c.int,
    debug_info_level: c.int,
    safepoint_on_entry: c.int,
    gcstack_arg: c.int,

    use_jlplt: c.int,
    force_emit_all: c.int,

    sanitize_memory: c.int,
    sanitize_thread: c.int,
    sanitize_address: c.int,

    unique_names: c.int,
}

jl_emission_params_t :: struct {
    emit_metadata: c.int,
}

jl_gcframe_t :: struct {}
jl_tls_states_t :: struct {}
jl_value_t :: struct {}
jl_sym_t :: struct {}
jl_svec_t :: struct {}
jl_genericmemory_t :: struct {
    length: c.size_t,
    ptr: rawptr,
}
jl_genericmemoryref_t :: struct {
    ptr_or_offset: rawptr,
    mem: ^jl_genericmemory_t,
}
jl_array_t :: struct {
    ref: jl_genericmemoryref_t,
    dimsize: [1]c.size_t,
}
jl_datatype_t :: struct {}
jl_typename_t :: struct {}
jl_tupletype_t :: struct {}
jl_tvar_t :: struct {}
jl_unionall_t :: struct {}
jl_binding_t :: struct {}
jl_binding_partition_t :: struct {}
jl_globalref_t :: struct {}
jl_method_t :: struct {}
jl_method_instance_t :: struct {}
jl_code_info_t :: struct {}
jl_code_instance_t :: struct {}
jl_debuginfo_t :: struct {}
jl_module_t :: struct {}
jl_task_t :: struct {}
jl_weakref_t :: struct {}
JL_STREAM :: struct {}
ios_t :: struct {}

// Common exported globals from libjulia.
foreign jl {
    jl_options: jl_options_t
    jl_base_module: ^jl_module_t
    jl_core_module: ^jl_module_t
    jl_main_module: ^jl_module_t
    jl_true: ^jl_value_t
    jl_false: ^jl_value_t
    jl_nothing: ^jl_value_t
    jl_any_type: ^jl_datatype_t
    jl_float64_type: ^jl_datatype_t
    jl_string_type: ^jl_datatype_t
    jl_uint8_type: ^jl_datatype_t
    jl_uint32_type: ^jl_datatype_t
    jl_array_any_type: ^jl_value_t
    jl_array_uint8_type: ^jl_value_t
    jl_array_uint32_type: ^jl_value_t
    jl_task_type: ^jl_datatype_t

    // Initialization and process lifecycle.
    jl_get_libdir :: proc() -> cstring ---
    jl_init :: proc() ---
    jl_init_with_image_file :: proc(julia_bindir, image_path: cstring) ---
    jl_init_with_image_handle :: proc(handle: rawptr) ---
    jl_get_default_sysimg_path :: proc() -> cstring ---
    jl_is_initialized :: proc() -> c.int ---
    jl_atexit_hook :: proc(status: c.int) ---
    jl_task_wait_empty :: proc() ---
    jl_postoutput_hook :: proc() ---
    jl_exit :: proc(status: c.int) ---
    jl_raise :: proc(signo: c.int) ---
    jl_pathname_for_handle :: proc(handle: rawptr) -> cstring ---
    jl_adopt_thread :: proc() -> ^^jl_gcframe_t ---

    // Parsing, lowering, and evaluation.
    jl_parse_all :: proc(text: cstring, text_len: c.size_t, filename: cstring, filename_len: c.size_t, lineno: c.size_t) -> ^jl_value_t ---
    jl_parse_string :: proc(text: cstring, text_len: c.size_t, offset: c.int, greedy: c.int) -> ^jl_value_t ---
    jl_lower :: proc(expr: ^jl_value_t, inmodule: ^jl_module_t, file: cstring, line: c.int, world: c.size_t, warn: c.int) -> ^jl_value_t ---
    jl_toplevel_eval :: proc(m: ^jl_module_t, v: ^jl_value_t) -> ^jl_value_t ---
    jl_toplevel_eval_in :: proc(m: ^jl_module_t, ex: ^jl_value_t) -> ^jl_value_t ---
    jl_eval_string :: proc(str: cstring) -> ^jl_value_t ---
    jl_load_file_string :: proc(text: cstring, len: c.size_t, filename: cstring, module: ^jl_module_t) -> ^jl_value_t ---
    jl_load :: proc(module: ^jl_module_t, fname: cstring) -> ^jl_value_t ---

    // Dynamic libraries.
    jl_load_dynamic_library :: proc(fname: cstring, flags: c.uint, throw_err: c.int) -> rawptr ---
    jl_dlopen :: proc(filename: cstring, flags: c.uint) -> rawptr ---
    jl_dlclose :: proc(handle: rawptr) -> c.int ---
    jl_dlsym :: proc(handle: rawptr, symbol: cstring, value: ^rawptr, throw_err: c.int, search_deps: c.int) -> c.int ---

    // Calling Julia.
    jl_apply_generic :: proc(F: ^jl_value_t, args: ^^jl_value_t, nargs: c.uint) -> ^jl_value_t ---
    jl_invoke :: proc(F: ^jl_value_t, args: ^^jl_value_t, nargs: c.uint, meth: ^jl_method_instance_t) -> ^jl_value_t ---
    jl_invoke_oc :: proc(F: ^jl_value_t, args: ^^jl_value_t, nargs: c.uint, meth: ^jl_method_instance_t) -> ^jl_value_t ---
    jl_invoke_api :: proc(linfo: ^jl_code_instance_t) -> c.int32_t ---
    jl_call :: proc(f: ^jl_value_t, args: ^^jl_value_t, nargs: c.uint) -> ^jl_value_t ---
    jl_call0 :: proc(f: ^jl_value_t) -> ^jl_value_t ---
    jl_call1 :: proc(f: ^jl_value_t, a: ^jl_value_t) -> ^jl_value_t ---
    jl_call2 :: proc(f: ^jl_value_t, a: ^jl_value_t, b: ^jl_value_t) -> ^jl_value_t ---
    jl_call3 :: proc(f: ^jl_value_t, a: ^jl_value_t, b: ^jl_value_t, c: ^jl_value_t) -> ^jl_value_t ---
    jl_call4 :: proc(f: ^jl_value_t, a: ^jl_value_t, b: ^jl_value_t, c: ^jl_value_t, d: ^jl_value_t) -> ^jl_value_t ---
    jl_get_global :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> ^jl_value_t ---
    jl_set_global :: proc(m: ^jl_module_t, var: ^jl_sym_t, val: ^jl_value_t) ---
    jl_set_const :: proc(m: ^jl_module_t, var: ^jl_sym_t, val: ^jl_value_t) ---
    jl_boundp :: proc(m: ^jl_module_t, var: ^jl_sym_t, allow_import: c.int) -> c.int ---
    jl_is_const :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> c.int ---
    jl_module_globalref :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> ^jl_value_t ---
    jl_get_binding :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> ^jl_binding_t ---
    jl_get_binding_wr :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> ^jl_binding_t ---
    jl_get_binding_type :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> ^jl_value_t ---
    jl_get_module_binding_or_nothing :: proc(m: ^jl_module_t, s: ^jl_sym_t) -> ^jl_value_t ---
    jl_new_module :: proc(name: ^jl_sym_t, parent: ^jl_module_t) -> ^jl_module_t ---
    jl_get_module_optlevel :: proc(m: ^jl_module_t) -> c.int ---
    jl_set_module_optlevel :: proc(self: ^jl_module_t, lvl: c.int) ---
    jl_get_module_compile :: proc(m: ^jl_module_t) -> c.int ---
    jl_set_module_compile :: proc(self: ^jl_module_t, value: c.int) ---
    jl_get_module_infer :: proc(m: ^jl_module_t) -> c.int ---
    jl_set_module_infer :: proc(self: ^jl_module_t, value: c.int) ---
    jl_get_module_max_methods :: proc(m: ^jl_module_t) -> c.int ---
    jl_set_module_max_methods :: proc(self: ^jl_module_t, value: c.int) ---
    jl_module_using :: proc(to, from: ^jl_module_t, flags: c.size_t) ---
    jl_module_public :: proc(from: ^jl_module_t, symbols: ^^jl_value_t, nsymbols: c.size_t, exported: c.int) ---
    jl_is_imported :: proc(m: ^jl_module_t, s: ^jl_sym_t) -> c.int ---
    jl_module_exports_p :: proc(m: ^jl_module_t, var: ^jl_sym_t) -> c.int ---

    // Exceptions and error helpers.
    jl_exception_occurred :: proc() -> ^jl_value_t ---
    jl_current_exception :: proc(ct: ^jl_task_t) -> ^jl_value_t ---
    jl_get_current_task :: proc() -> ^jl_task_t ---
    jl_exception_clear :: proc() ---
    jl_stderr_obj :: proc() -> ^jl_value_t ---
    jl_stdout_stream :: proc() -> ^JL_STREAM ---
    jl_stdin_stream :: proc() -> ^JL_STREAM ---
    jl_stderr_stream :: proc() -> ^JL_STREAM ---
    jl_flush_cstdio :: proc() ---
    jl_static_show :: proc(out: ^JL_STREAM, v: ^jl_value_t) -> c.size_t ---
    jl_safe_static_show :: proc(out: ^JL_STREAM, v: ^jl_value_t) -> c.size_t ---
    jl_safe_static_show_func_sig :: proc(out: ^JL_STREAM, type: ^jl_value_t) -> c.size_t ---
    jl_printf :: proc(out: ^JL_STREAM, format: cstring, #c_vararg args: ..any) -> c.int ---
    jl_safe_printf :: proc(str: cstring, #c_vararg args: ..any) ---
    jl_safe_fprintf :: proc(out: ^ios_t, str: cstring, #c_vararg args: ..any) ---
    jl_error :: proc(str: cstring) ---
    jl_too_few_args :: proc(fname: cstring, min: c.int) ---
    jl_too_many_args :: proc(fname: cstring, max: c.int) ---
    jl_type_error :: proc(fname: cstring, expected: ^jl_value_t, got: ^jl_value_t) ---
    jl_type_error_rt :: proc(fname, ctx: cstring, ty: ^jl_value_t, got: ^jl_value_t) ---
    jl_type_error_global :: proc(fname: cstring, mod: ^jl_module_t, sym: ^jl_sym_t, ty: ^jl_value_t, got: ^jl_value_t) ---
    jl_undefined_var_error :: proc(var: ^jl_sym_t, scope: ^jl_value_t) ---
    jl_has_no_field_error :: proc(t: ^jl_datatype_t, var: ^jl_sym_t) ---
    jl_argument_error :: proc(str: cstring) ---
    jl_atomic_error :: proc(str: cstring) ---
    jl_bounds_error :: proc(v, t: ^jl_value_t) ---
    jl_bounds_error_v :: proc(v: ^jl_value_t, idxs: ^^jl_value_t, nidxs: c.size_t) ---
    jl_bounds_error_int :: proc(v: ^jl_value_t, i: c.size_t) ---
    jl_bounds_error_tuple_int :: proc(v: ^^jl_value_t, nv: c.size_t, i: c.size_t) ---
    jl_bounds_error_unboxed_int :: proc(v: rawptr, vt: ^jl_value_t, i: c.size_t) ---
    jl_bounds_error_ints :: proc(v: ^jl_value_t, idxs: ^c.size_t, nidxs: c.size_t) ---
    jl_errorf :: proc(format: cstring, #c_vararg args: ..any) ---
    jl_exceptionf :: proc(ty: ^jl_datatype_t, format: cstring, #c_vararg args: ..any) ---

    // Boxing and unboxing primitive values.
    jl_box_bool :: proc(x: c.int8_t) -> ^jl_value_t ---
    jl_box_int8 :: proc(x: c.int8_t) -> ^jl_value_t ---
    jl_box_uint8 :: proc(x: c.uint8_t) -> ^jl_value_t ---
    jl_box_int16 :: proc(x: c.int16_t) -> ^jl_value_t ---
    jl_box_uint16 :: proc(x: c.uint16_t) -> ^jl_value_t ---
    jl_box_int32 :: proc(x: c.int32_t) -> ^jl_value_t ---
    jl_box_uint32 :: proc(x: c.uint32_t) -> ^jl_value_t ---
    jl_box_char :: proc(x: c.uint32_t) -> ^jl_value_t ---
    jl_box_int64 :: proc(x: c.int64_t) -> ^jl_value_t ---
    jl_box_uint64 :: proc(x: c.uint64_t) -> ^jl_value_t ---
    jl_box_float32 :: proc(x: f32) -> ^jl_value_t ---
    jl_box_float64 :: proc(x: f64) -> ^jl_value_t ---
    jl_box_voidpointer :: proc(x: rawptr) -> ^jl_value_t ---
    jl_box_uint8pointer :: proc(x: ^u8) -> ^jl_value_t ---
    jl_box_ssavalue :: proc(x: c.size_t) -> ^jl_value_t ---
    jl_box_slotnumber :: proc(x: c.size_t) -> ^jl_value_t ---
    jl_unbox_bool :: proc(v: ^jl_value_t) -> c.int8_t ---
    jl_unbox_int8 :: proc(v: ^jl_value_t) -> c.int8_t ---
    jl_unbox_uint8 :: proc(v: ^jl_value_t) -> c.uint8_t ---
    jl_unbox_int16 :: proc(v: ^jl_value_t) -> c.int16_t ---
    jl_unbox_uint16 :: proc(v: ^jl_value_t) -> c.uint16_t ---
    jl_unbox_int32 :: proc(v: ^jl_value_t) -> c.int32_t ---
    jl_unbox_uint32 :: proc(v: ^jl_value_t) -> c.uint32_t ---
    jl_unbox_int64 :: proc(v: ^jl_value_t) -> c.int64_t ---
    jl_unbox_uint64 :: proc(v: ^jl_value_t) -> c.uint64_t ---
    jl_unbox_float32 :: proc(v: ^jl_value_t) -> f32 ---
    jl_unbox_float64 :: proc(v: ^jl_value_t) -> f64 ---
    jl_unbox_voidpointer :: proc(v: ^jl_value_t) -> rawptr ---
    jl_unbox_uint8pointer :: proc(v: ^jl_value_t) -> ^u8 ---
    jl_get_size :: proc(val: ^jl_value_t, pnt: ^c.size_t) -> c.int ---

    // Structs.
    jl_field_index :: proc(t: ^jl_datatype_t, fld: ^jl_sym_t, err: c.int) -> c.int ---
    jl_get_nth_field :: proc(v: ^jl_value_t, i: c.size_t) -> ^jl_value_t ---
    jl_get_nth_field_noalloc :: proc(v: ^jl_value_t, i: c.size_t) -> ^jl_value_t ---
    jl_get_nth_field_checked :: proc(v: ^jl_value_t, i: c.size_t) -> ^jl_value_t ---
    jl_set_nth_field :: proc(v: ^jl_value_t, i: c.size_t, rhs: ^jl_value_t) ---
    jl_field_isdefined :: proc(v: ^jl_value_t, i: c.size_t) -> c.int ---
    jl_field_isdefined_checked :: proc(v: ^jl_value_t, i: c.size_t) -> c.int ---
    jl_get_field :: proc(o: ^jl_value_t, fld: cstring) -> ^jl_value_t ---
    jl_value_ptr :: proc(a: ^jl_value_t) -> ^jl_value_t ---
    jl_islayout_inline :: proc(eltype: ^jl_value_t, fsz: ^c.size_t, al: ^c.size_t) -> c.int ---

    // Types and constructors.
    jl_subtype :: proc(a, b: ^jl_value_t) -> c.int ---
    jl_has_free_typevars :: proc(v: ^jl_value_t) -> c.int ---
    jl_has_typevar :: proc(t: ^jl_value_t, v: ^jl_tvar_t) -> c.int ---
    jl_subtype_env_size :: proc(t: ^jl_value_t) -> c.int ---
    jl_subtype_env :: proc(x, y: ^jl_value_t, env: ^^jl_value_t, envsz: c.int) -> c.int ---
    jl_isa :: proc(a, t: ^jl_value_t) -> c.int ---
    jl_types_equal :: proc(a, b: ^jl_value_t) -> c.int ---
    jl_is_not_broken_subtype :: proc(a, b: ^jl_value_t) -> c.int ---
    jl_type_union :: proc(ts: ^^jl_value_t, n: c.size_t) -> ^jl_value_t ---
    jl_type_intersection :: proc(a, b: ^jl_value_t) -> ^jl_value_t ---
    jl_has_empty_intersection :: proc(x, y: ^jl_value_t) -> c.int ---
    jl_type_unionall :: proc(v: ^jl_tvar_t, body: ^jl_value_t) -> ^jl_value_t ---
    jl_type_morespecific :: proc(a, b: ^jl_value_t) -> c.int ---
    jl_method_morespecific :: proc(ma, mb: ^jl_method_t) -> c.int ---
    jl_isa_compileable_sig :: proc(type: ^jl_tupletype_t, sparams: ^jl_svec_t, definition: ^jl_method_t) -> c.int ---
    jl_new_typename_in :: proc(name: ^jl_sym_t, inmodule: ^jl_module_t, abstract, mutabl: c.int) -> ^jl_typename_t ---
    jl_new_typevar :: proc(name: ^jl_sym_t, lb, ub: ^jl_value_t) -> ^jl_tvar_t ---
    jl_instantiate_unionall :: proc(u: ^jl_unionall_t, p: ^jl_value_t) -> ^jl_value_t ---
    jl_apply_type :: proc(tc: ^jl_value_t, params: ^^jl_value_t, n: c.size_t) -> ^jl_value_t ---
    jl_apply_type1 :: proc(tc, p1: ^jl_value_t) -> ^jl_value_t ---
    jl_apply_type2 :: proc(tc, p1, p2: ^jl_value_t) -> ^jl_value_t ---
    jl_apply_type3 :: proc(tc, p1, p2, p3: ^jl_value_t) -> ^jl_value_t ---
    jl_apply_tuple_type :: proc(params: ^jl_svec_t, check: c.int) -> ^jl_value_t ---
    jl_apply_tuple_type_v :: proc(p: ^^jl_value_t, np: c.size_t) -> ^jl_value_t ---
    jl_new_datatype :: proc(name: ^jl_sym_t, module: ^jl_module_t, super: ^jl_datatype_t, parameters, fnames, ftypes, fattrs: ^jl_svec_t, abstract, mutabl, ninitialized: c.int) -> ^jl_datatype_t ---
    jl_new_primitivetype :: proc(name: ^jl_value_t, module: ^jl_module_t, super: ^jl_datatype_t, parameters: ^jl_svec_t, nbits: c.size_t) -> ^jl_datatype_t ---
    jl_new_bits :: proc(bt: ^jl_value_t, src: rawptr) -> ^jl_value_t ---
    jl_new_struct :: proc(type: ^jl_datatype_t, #c_vararg args: ..any) -> ^jl_value_t ---
    jl_new_structv :: proc(type: ^jl_datatype_t, args: ^^jl_value_t, na: c.uint32_t) -> ^jl_value_t ---
    jl_new_structt :: proc(type: ^jl_datatype_t, tup: ^jl_value_t) -> ^jl_value_t ---
    jl_new_struct_uninit :: proc(type: ^jl_datatype_t) -> ^jl_value_t ---
    jl_svec :: proc(n: c.size_t, #c_vararg args: ..any) -> ^jl_svec_t ---
    jl_svec1 :: proc(a: rawptr) -> ^jl_svec_t ---
    jl_svec2 :: proc(a, b: rawptr) -> ^jl_svec_t ---
    jl_svec3 :: proc(a, b, c: rawptr) -> ^jl_svec_t ---
    jl_alloc_svec :: proc(n: c.size_t) -> ^jl_svec_t ---
    jl_alloc_svec_uninit :: proc(n: c.size_t) -> ^jl_svec_t ---
    jl_svec_copy :: proc(a: ^jl_svec_t) -> ^jl_svec_t ---
    jl_svec_fill :: proc(n: c.size_t, x: ^jl_value_t) -> ^jl_svec_t ---
    jl_symbol :: proc(str: cstring) -> ^jl_sym_t ---
    jl_symbol_lookup :: proc(str: cstring) -> ^jl_sym_t ---
    jl_symbol_n :: proc(str: cstring, len: c.size_t) -> ^jl_sym_t ---
    jl_gensym :: proc() -> ^jl_sym_t ---
    jl_get_root_symbol :: proc() -> ^jl_sym_t ---
    jl_typename_str :: proc(v: ^jl_value_t) -> cstring ---
    jl_typeof_str :: proc(v: ^jl_value_t) -> cstring ---

    // Arrays and generic memory.
    jl_apply_array_type :: proc(type: ^jl_value_t, dim: c.size_t) -> ^jl_value_t ---
    jl_ptr_to_array_1d :: proc(atype: ^jl_value_t, data: rawptr, nel: c.size_t, own_buffer: c.int) -> ^jl_array_t ---
    jl_ptr_to_array :: proc(atype: ^jl_value_t, data: rawptr, dims: ^jl_value_t, own_buffer: c.int) -> ^jl_array_t ---
    jl_alloc_array_1d :: proc(atype: ^jl_value_t, nr: c.size_t) -> ^jl_array_t ---
    jl_alloc_array_2d :: proc(atype: ^jl_value_t, nr, nc: c.size_t) -> ^jl_array_t ---
    jl_alloc_array_3d :: proc(atype: ^jl_value_t, nr, nc, z: c.size_t) -> ^jl_array_t ---
    jl_alloc_array_nd :: proc(atype: ^jl_value_t, dims: ^c.size_t, ndims: c.size_t) -> ^jl_array_t ---
    jl_pchar_to_array :: proc(str: cstring, len: c.size_t) -> ^jl_array_t ---
    jl_pchar_to_string :: proc(str: cstring, len: c.size_t) -> ^jl_value_t ---
    jl_cstr_to_string :: proc(str: cstring) -> ^jl_value_t ---
    jl_alloc_string :: proc(len: c.size_t) -> ^jl_value_t ---
    jl_array_to_string :: proc(a: ^jl_array_t) -> ^jl_value_t ---
    jl_alloc_vec_any :: proc(n: c.size_t) -> ^jl_array_t ---
    jl_array_grow_end :: proc(a: ^jl_array_t, inc: c.size_t) ---
    jl_array_del_end :: proc(a: ^jl_array_t, dec: c.size_t) ---
    jl_array_ptr_1d_push :: proc(a: ^jl_array_t, item: ^jl_value_t) ---
    jl_array_ptr_1d_append :: proc(a, a2: ^jl_array_t) ---
    jl_array_ptr :: proc(a: ^jl_array_t) -> rawptr ---
    jl_array_eltype :: proc(a: ^jl_value_t) -> rawptr ---
    jl_array_rank :: proc(a: ^jl_value_t) -> c.int ---

    jl_new_genericmemory :: proc(mtype: ^jl_value_t, dim: ^jl_value_t) -> ^jl_genericmemory_t ---
    jl_ptr_to_genericmemory :: proc(mtype: ^jl_value_t, data: rawptr, nel: c.size_t, own_buffer: c.int) -> ^jl_genericmemory_t ---
    jl_alloc_genericmemory :: proc(mtype: ^jl_value_t, nel: c.size_t) -> ^jl_genericmemory_t ---
    jl_pchar_to_memory :: proc(str: cstring, len: c.size_t) -> ^jl_genericmemory_t ---
    jl_alloc_genericmemory_unchecked :: proc(ptls: ^jl_tls_states_t, nbytes: c.size_t, mtype: ^jl_datatype_t) -> ^jl_genericmemory_t ---
    jl_genericmemory_to_string :: proc(m: ^jl_genericmemory_t, len: c.size_t) -> ^jl_value_t ---
    jl_alloc_memory_any :: proc(n: c.size_t) -> ^jl_genericmemory_t ---
    jl_genericmemoryref :: proc(m: ^jl_genericmemory_t, i: c.size_t) -> ^jl_value_t ---
    jl_new_memoryref :: proc(typ: ^jl_value_t, mem: ^jl_genericmemory_t, data: rawptr) -> ^jl_genericmemoryref_t ---
    jl_memoryrefget :: proc(m: jl_genericmemoryref_t, isatomic: c.int) -> ^jl_value_t ---
    jl_ptrmemoryrefget :: proc(m: jl_genericmemoryref_t) -> ^jl_value_t ---
    jl_memoryref_isassigned :: proc(m: jl_genericmemoryref_t, isatomic: c.int) -> ^jl_value_t ---
    jl_memoryrefindex :: proc(m: jl_genericmemoryref_t, idx: c.size_t) -> jl_genericmemoryref_t ---
    jl_memoryrefset :: proc(m: jl_genericmemoryref_t, v: ^jl_value_t, isatomic: c.int) ---
    jl_memoryrefunset :: proc(m: jl_genericmemoryref_t, isatomic: c.int) ---
    jl_memoryrefswap :: proc(m: jl_genericmemoryref_t, v: ^jl_value_t, isatomic: c.int) -> ^jl_value_t ---
    jl_memoryrefmodify :: proc(m: jl_genericmemoryref_t, op, v: ^jl_value_t, isatomic: c.int) -> ^jl_value_t ---
    jl_memoryrefreplace :: proc(m: jl_genericmemoryref_t, expected, v: ^jl_value_t, isatomic: c.int) -> ^jl_value_t ---
    jl_memoryrefsetonce :: proc(m: jl_genericmemoryref_t, v: ^jl_value_t, isatomic: c.int) -> ^jl_value_t ---
    jl_string_ptr :: proc(s: ^jl_value_t) -> cstring ---

    // GC helpers.
    JL_GC_PUSH1 :: proc(arg1: rawptr) ---
    JL_GC_PUSH2 :: proc(arg1, arg2: rawptr) ---
    JL_GC_PUSH3 :: proc(arg1, arg2, arg3: rawptr) ---
    JL_GC_PUSH4 :: proc(arg1, arg2, arg3, arg4: rawptr) ---
    JL_GC_PUSH5 :: proc(arg1, arg2, arg3, arg4, arg5: rawptr) ---
    JL_GC_PUSH6 :: proc(arg1, arg2, arg3, arg4, arg5, arg6: rawptr) ---
    JL_GC_PUSH7 :: proc(arg1, arg2, arg3, arg4, arg5, arg6, arg7: rawptr) ---
    JL_GC_PUSH8 :: proc(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8: rawptr) ---
    JL_GC_PUSH9 :: proc(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9: rawptr) ---
    JL_GC_POP :: proc() ---
    _JL_GC_PUSHARGS :: proc(rts_var: ^^jl_value_t, n: c.size_t) ---
    jl_gc_add_finalizer :: proc(v, f: ^jl_value_t) ---
    jl_finalize :: proc(o: ^jl_value_t) ---
    jl_gc_new_weakref :: proc(value: ^jl_value_t) -> ^jl_weakref_t ---
    jl_gc_safepoint :: proc() ---
    jl_gc_enable :: proc(on: c.int) -> c.int ---
    jl_gc_is_enabled :: proc() -> c.int ---
    jl_gc_set_max_memory :: proc(max_mem: u64) ---
    jl_gc_collect :: proc(collection: jl_gc_collection_t) ---
    jl_gc_enable_auto_full_collection :: proc(on: c.int) -> c.int ---
    jl_gc_auto_full_collection_is_enabled :: proc() -> c.int ---
    gc_is_collector_thread :: proc(tid: c.int) -> c.int ---

    // System information and versioning.
    jl_ver_major :: proc() -> c.int ---
    jl_ver_minor :: proc() -> c.int ---
    jl_ver_patch :: proc() -> c.int ---
    jl_ver_is_release :: proc() -> c.int ---
    jl_ver_string :: proc() -> cstring ---
    jl_errno :: proc() -> c.int ---
    jl_set_errno :: proc(e: c.int) ---
    jl_stat :: proc(path: cstring, statbuf: cstring) -> c.int32_t ---
    jl_cpu_threads :: proc() -> c.int ---
    jl_effective_threads :: proc() -> c.int ---
    jl_getpagesize :: proc() -> c.long ---
    jl_getallocationgranularity :: proc() -> c.long ---
    jl_gethugepagesize :: proc() -> c.long ---
    jl_is_debugbuild :: proc() -> c.int ---
    jl_get_UNAME :: proc() -> ^jl_sym_t ---
    jl_get_ARCH :: proc() -> ^jl_sym_t ---
    jl_get_libllvm :: proc() -> ^jl_value_t ---
    jl_environ :: proc(i: c.int) -> ^jl_value_t ---
    jl_generating_output :: proc() -> c.int ---
    jl_sizeof_jl_options :: proc() -> c.size_t ---
    jl_parse_opts :: proc(argcp: ^c.int, argvp: ^^cstring) ---
    jl_format_filename :: proc(output_pattern: cstring) -> cstring ---
    jl_set_ARGS :: proc(argc: c.int, argv: ^^cstring) -> ^jl_value_t ---
}

// Fast helpers for a few common inline C API patterns.
jl_get_function :: proc(m: ^jl_module_t, name: cstring) -> ^jl_value_t {
    return jl_get_global(m, jl_symbol(name))
}

jl_array_nrows :: proc(a: ^jl_array_t) -> c.size_t {
    return a.dimsize[0]
}

jl_array_maxsize :: proc(a: ^jl_array_t) -> c.size_t {
    return a.ref.mem.length
}

jl_array_len :: proc(a: ^jl_array_t) -> c.size_t {
    if jl_array_rank(cast(^jl_value_t)a) == 1 {
        return jl_array_nrows(a)
    }
    return jl_array_maxsize(a)
}

jl_array_data_raw :: proc(a: ^jl_array_t) -> rawptr {
    return jl_array_ptr(a)
}
