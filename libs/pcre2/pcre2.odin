package pcre2_raw

import "core:c"

when ODIN_OS == .Windows {
    foreign import pcre2_library "system:pcre2-8.lib"
} else when ODIN_OS == .Darwin {
    foreign import pcre2_library "system:pcre2-8.0"
} else {
    foreign import pcre2_library "system:pcre2-8"
}

// Opaque PCRE2 compiled pattern handle.
Code :: struct {}

// Opaque PCRE2 reusable match-data handle.
Match_Data :: struct {}

// Opaque PCRE2 execution context handle.
Match_Context :: struct {}

// Opaque PCRE2 callout block passed to cancellation callbacks.
Callout_Block :: struct {}

// PCRE2 callout callback ABI used to observe within-match cancellation.
Callout_Function :: proc "c" (
    block: ^Callout_Block, user_data: rawptr) -> c.int

// PCRE2 error and behavior constants used by the native owner.
ERROR_NOMATCH :: c.int(-1)
ERROR_CALLOUT :: c.int(-37)
ERROR_NOMEMORY :: c.int(-48)
ERROR_HEAP_FAILED :: c.int(121)
ERROR_MATCHLIMIT :: c.int(-47)
ERROR_DEPTHLIMIT :: c.int(-53)
ERROR_HEAPLIMIT :: c.int(-63)
CONFIG_VERSION :: u32(11)
COMPILE_ALT_BSUX :: u32(0x00000002)
COMPILE_AUTO_CALLOUT :: u32(0x00000004)
COMPILE_CASELESS :: u32(0x00000008)
COMPILE_UCP :: u32(0x00020000)
COMPILE_MATCH_INVALID_UTF :: u32(0x04000000)
COMPILE_UTF :: u32(0x00080000)
MATCH_NO_UTF_CHECK :: u32(0x40000000)
MATCH_NOTEMPTY_ATSTART :: u32(0x00000008)
MATCH_ANCHORED :: u32(0x80000000)

foreign pcre2_library {
    pcre2_compile_8 :: proc(
        pattern: [^]u8, length: uintptr, options: u32,
        error_code: ^c.int, error_offset: ^uintptr,
        compile_context: rawptr) -> ^Code ---
    pcre2_code_free_8 :: proc(code: ^Code) ---
    pcre2_match_data_create_from_pattern_8 :: proc(
        code: ^Code, general_context: rawptr) -> ^Match_Data ---
    pcre2_match_data_free_8 :: proc(match_data: ^Match_Data) ---
    pcre2_match_context_create_8 :: proc(
        general_context: rawptr) -> ^Match_Context ---
    pcre2_match_context_free_8 :: proc(match_context: ^Match_Context) ---
    pcre2_set_match_limit_8 :: proc(
        match_context: ^Match_Context, limit: u32) -> c.int ---
    pcre2_set_depth_limit_8 :: proc(
        match_context: ^Match_Context, limit: u32) -> c.int ---
    pcre2_set_heap_limit_8 :: proc(
        match_context: ^Match_Context, limit_kib: u32) -> c.int ---
    pcre2_set_callout_8 :: proc(
        match_context: ^Match_Context, callback: Callout_Function,
        user_data: rawptr) -> c.int ---
    pcre2_match_8 :: proc(
        code: ^Code, subject: [^]u8, length, start_offset: uintptr,
        options: u32, match_data: ^Match_Data,
        match_context: ^Match_Context) -> c.int ---
    pcre2_get_ovector_pointer_8 :: proc(match_data: ^Match_Data) -> [^]uintptr ---
    pcre2_config_8 :: proc(what: u32, wherep: rawptr) -> c.int ---
}
