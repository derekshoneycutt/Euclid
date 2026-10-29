package pcre2

import "core:c"
import sync "core:sync"
import raw "../../libs/pcre2"

// PCRE2 limits chosen to bound history matching while preserving ordinary regex use.
Limits :: struct {
    match_limit: u32,
    depth_limit: u32,
    heap_limit_kib: u32,
}

DEFAULT_LIMITS :: Limits{
    match_limit = 1_000_000,
    depth_limit = 1_000,
    heap_limit_kib = 8_192,
}

// Base.Regex options plus automatic callouts for prompt cancellation checks.
DEFAULT_COMPILE_OPTIONS :: u32(
    raw.COMPILE_UTF | raw.COMPILE_MATCH_INVALID_UTF |
        raw.COMPILE_ALT_BSUX | raw.COMPILE_UCP | raw.COMPILE_AUTO_CALLOUT)
DEFAULT_MATCH_OPTIONS :: raw.MATCH_NO_UTF_CHECK

// Compile_Status distinguishes invalid syntax from resource and state failures.
Compile_Status :: enum {
    Success,
    Invalid_Pattern,
    Out_Of_Memory,
    Invalid_Limits,
    Invalid_State,
    Engine_Error,
}

// Match_Status preserves cancellation and PCRE2 resource-limit outcomes.
Match_Status :: enum {
    Matched,
    No_Match,
    Cancelled,
    Match_Limit,
    Depth_Limit,
    Heap_Limit,
    Out_Of_Memory,
    Invalid_State,
    Engine_Error,
}

// Compile_Result reports pattern errors without converting failures to no-match.
Compile_Result :: struct {
    status: Compile_Status,
    error_code: c.int,
    error_offset: uintptr,
}

// Match_Result includes the positive whole-match byte range when available.
Match_Result :: struct {
    status: Match_Status,
    error_code: c.int,
    start: uintptr,
    end: uintptr,
}

// Cancel_Token is safe to request from another thread during PCRE2 execution.
Cancel_Token :: struct {
    requested: int,
}

when ODIN_TEST {
    // Test builds carry an explicit borrow of caller-owned resource evidence.
    Compiled :: struct {
        code: ^raw.Code,
        match_data: ^raw.Match_Data,
        match_context: ^raw.Match_Context,
        test_resources: ^Resource_Test_State,
    }
} else {
    // Compiled owns PCRE2 resources and is not safe for concurrent matching.
    Compiled :: struct {
        code: ^raw.Code,
        match_data: ^raw.Match_Data,
        match_context: ^raw.Match_Context,
    }
}

// Initialize a cancellation token in the non-cancelled state.
cancel_token_init :: proc(token: ^Cancel_Token) {
    if token != nil {
        sync.atomic_store_explicit(&token^.requested, 0, .Release)
    }
}

// Request cancellation for a match using this token.
cancel_token_request :: proc(token: ^Cancel_Token) {
    if token != nil {
        sync.atomic_store_explicit(&token^.requested, 1, .Release)
    }
}

// Reset a token only after its current match has returned.
cancel_token_reset :: proc(token: ^Cancel_Token) {
    cancel_token_init(token)
}

// Observe cancellation at PCRE2 automatic callout points without allocating.
pcre2_cancellation_callout :: proc "c" (
    block: ^raw.Callout_Block, user_data: rawptr) -> c.int {
    _ = block
    if user_data != nil {
        token := cast(^Cancel_Token)user_data
        if sync.atomic_load_explicit(&token^.requested, .Acquire) != 0 {
            return raw.ERROR_CALLOUT
        }
    }
    return 0
}

// Set all three execution limits on a newly-created PCRE2 match context.
set_limits :: proc(match_context: ^raw.Match_Context, limits: Limits) -> c.int {
    result := raw.pcre2_set_match_limit_8(match_context, limits.match_limit)
    if result != 0 {
        return result
    }
    result = raw.pcre2_set_depth_limit_8(match_context, limits.depth_limit)
    if result != 0 {
        return result
    }
    return raw.pcre2_set_heap_limit_8(
        match_context, limits.heap_limit_kib)
}

// Compile one pattern and acquire reusable matching resources with PCRE2 defaults.
compile :: proc(
    compiled: ^Compiled, pattern: []u8,
    compile_options: u32 = DEFAULT_COMPILE_OPTIONS,
    limits: Limits = DEFAULT_LIMITS) -> Compile_Result {
    if compiled == nil || compiled^.code != nil ||
       compiled^.match_data != nil || compiled^.match_context != nil {
        return {
            status = .Invalid_State,
        }
    }
    if limits.match_limit == 0 || limits.depth_limit == 0 ||
       limits.heap_limit_kib == 0 {
        return {
            status = .Invalid_Limits,
        }
    }
    error_code: c.int
    error_offset: uintptr
    compiled^.code = acquire_code(compiled,
        pattern,
        compile_options | raw.COMPILE_AUTO_CALLOUT,
        &error_code, &error_offset)
    if compiled^.code == nil {
        status := Compile_Status.Invalid_Pattern
        if error_code == raw.ERROR_NOMEMORY || error_code == raw.ERROR_HEAP_FAILED {
            status = Compile_Status.Out_Of_Memory
        } else if error_code < 0 {
            status = Compile_Status.Engine_Error
        }
        return {
            status = status,
            error_code = error_code,
            error_offset = error_offset,
        }
    }
    return initialize_matching_resources(compiled, limits)
}

// Acquire reusable execution storage, releasing all handles after partial failure.
initialize_matching_resources :: proc(
    compiled: ^Compiled, limits: Limits) -> Compile_Result {
    compiled^.match_data = acquire_match_data(compiled)
    if compiled^.match_data == nil {
        release(compiled)
        return {
            status = .Out_Of_Memory,
            error_code = raw.ERROR_NOMEMORY,
        }
    }
    compiled^.match_context = acquire_match_context(compiled)
    if compiled^.match_context == nil {
        release(compiled)
        return {
            status = .Out_Of_Memory,
            error_code = raw.ERROR_NOMEMORY,
        }
    }
    limit_error := set_limits(compiled^.match_context, limits)
    if limit_error != 0 {
        release(compiled)
        return {
            status = .Engine_Error,
            error_code = limit_error,
        }
    }
    return {
        status = .Success,
    }
}

// Release only after all matching borrowers return; clear handles to prevent double-free.
release :: proc(compiled: ^Compiled) {
    if compiled == nil {
        return
    }
    if compiled^.match_context != nil {
        release_match_context(compiled)
    }
    if compiled^.match_data != nil {
        release_match_data(compiled)
    }
    if compiled^.code != nil {
        release_code(compiled)
    }
    compiled^.code = nil
    compiled^.match_data = nil
    compiled^.match_context = nil
}

// Borrow source/token only until return; callers serialize matching and join before release.
match :: proc(
    compiled: ^Compiled, subject: []u8,
    cancel: ^Cancel_Token = nil) -> Match_Result {
    return match_from_with_options(compiled, subject, 0, 0, cancel)
}

// Match the complete subject beginning at a UTF-8 byte offset with PCRE2 options.
match_from_with_options :: proc(
    compiled: ^Compiled, subject: []u8, start_offset: int,
    options: u32, cancel: ^Cancel_Token = nil) -> Match_Result {
    if compiled == nil || compiled^.code == nil ||
       compiled^.match_data == nil || compiled^.match_context == nil ||
       start_offset < 0 || start_offset > len(subject) {
        return {
            status = .Invalid_State,
        }
    }
    if cancel != nil &&
       sync.atomic_load_explicit(&cancel^.requested, .Acquire) != 0 {
        return {
            status = .Cancelled,
            error_code = raw.ERROR_CALLOUT,
        }
    }
    callout_error := raw.pcre2_set_callout_8(
        compiled^.match_context, pcre2_cancellation_callout, cancel)
    if callout_error != 0 {
        return {
            status = .Engine_Error,
            error_code = callout_error,
        }
    }
    empty_subject: u8
    subject_data := raw_data(subject)
    if len(subject) == 0 {
        subject_data = &empty_subject
    }
    result := raw.pcre2_match_8(
        compiled^.code, subject_data, uintptr(len(subject)), uintptr(start_offset),
        DEFAULT_MATCH_OPTIONS | options, compiled^.match_data, compiled^.match_context)
    detach_error := raw.pcre2_set_callout_8(compiled^.match_context, nil, nil)
    if detach_error != 0 {
        return {
            status = .Engine_Error,
            error_code = detach_error,
        }
    }
    return read_match_result(compiled, result)
}

// Decode an interpreter result before reusable match data is overwritten.
read_match_result :: proc(compiled: ^Compiled, result: c.int) -> Match_Result {
    if result == raw.ERROR_NOMATCH {
        return {
            status = .No_Match,
            error_code = result,
        }
    }
    if result < 0 {
        return match_error(result)
    }
    if result == 0 {
        return {
            status = .Engine_Error,
            error_code = result,
        }
    }
    offsets := raw.pcre2_get_ovector_pointer_8(compiled^.match_data)
    if offsets == nil {
        return {
            status = .Engine_Error,
        }
    }
    return {
        status = .Matched,
        error_code = result,
        start = offsets[0],
        end = offsets[1],
    }
}

// Translate PCRE2 execution errors into explicit native outcomes.
match_error :: proc(error_code: c.int) -> Match_Result {
    status: Match_Status = .Engine_Error
    switch error_code {
    case raw.ERROR_CALLOUT:
        status = Match_Status.Cancelled
    case raw.ERROR_MATCHLIMIT:
        status = Match_Status.Match_Limit
    case raw.ERROR_DEPTHLIMIT:
        status = Match_Status.Depth_Limit
    case raw.ERROR_HEAPLIMIT:
        status = Match_Status.Heap_Limit
    case raw.ERROR_NOMEMORY:
        status = Match_Status.Out_Of_Memory
    }
    return {
        status = status,
        error_code = error_code,
    }
}
