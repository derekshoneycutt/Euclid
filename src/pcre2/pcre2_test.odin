#+test
package pcre2

import "core:c"
import "core:sync"
import "core:testing"
import raw "../../libs/pcre2"

Pcre2_Test_Callout_State :: struct {
    token: Cancel_Token,
    count: int,
}

// PCRE2 matching preserves UTF property and capture/backreference behavior.
@(test)
pcre2_compiles_unicode_and_backreferences :: proc(t: ^testing.T) {
    compiled: Compiled
    pattern := "^(a)\\1$"
    result := compile(&compiled, transmute([]u8)pattern)
    testing.expect_value(t, result.status, Compile_Status.Success)
    defer release(&compiled)

    matching_source := "aa"
    other_source := "ab"
    match_result := match(&compiled, transmute([]u8)matching_source)
    testing.expect_value(t, match_result.status, Match_Status.Matched)
    testing.expect_value(t, match_result.start, uintptr(0))
    testing.expect_value(t, match_result.end, uintptr(2))
    testing.expect_value(t, match(&compiled, transmute([]u8)other_source).status,
        Match_Status.No_Match)

    unicode_pattern := "^\\p{Greek}+$"
    unicode_source := "\u03bb\u03a9"
    unicode_regex: Compiled
    unicode_result := compile(&unicode_regex, transmute([]u8)unicode_pattern)
    testing.expect_value(t, unicode_result.status, Compile_Status.Success)
    defer release(&unicode_regex)
    testing.expect_value(t,
        match(&unicode_regex, transmute([]u8)unicode_source).status,
        Match_Status.Matched)
    lookbehind: Compiled
    lookbehind_pattern := "(?<=\\p{Greek})(a)\\1"
    lookbehind_source := "\u03bb" + "aa"
    lookbehind_result := compile(
        &lookbehind, transmute([]u8)lookbehind_pattern)
    testing.expect_value(t, lookbehind_result.status, Compile_Status.Success)
    defer release(&lookbehind)
    testing.expect_value(t,
        match(&lookbehind, transmute([]u8)lookbehind_source).status,
        Match_Status.Matched)
}

// Start offsets and anchored non-empty retries support global zero-width iteration.
@(test)
pcre2_match_from_retries_zero_width_alternatives :: proc(t: ^testing.T) {
    compiled: Compiled
    pattern := "(?=a)|a"
    source := "a"
    result := compile(&compiled, transmute([]u8)pattern)
    testing.expect_value(t, result.status, Compile_Status.Success)
    if result.status != .Success {
        return
    }
    defer release(&compiled)
    first := match(&compiled, transmute([]u8)source)
    testing.expect_value(t, first.status, Match_Status.Matched)
    testing.expect_value(t, first.start, uintptr(0))
    testing.expect_value(t, first.end, uintptr(0))
    retry := match_from_with_options(
        &compiled, transmute([]u8)source, 0,
        raw.MATCH_ANCHORED | raw.MATCH_NOTEMPTY_ATSTART)
    testing.expect_value(t, retry.status, Match_Status.Matched)
    testing.expect_value(t, retry.start, uintptr(0))
    testing.expect_value(t, retry.end, uintptr(1))
    testing.expect_value(t,
        match_from_with_options(&compiled, transmute([]u8)source, 1, 0).status,
        Match_Status.No_Match)
}

// Invalid syntax and empty patterns return distinct, releasable outcomes.
@(test)
pcre2_compile_failures_and_empty_pattern :: proc(t: ^testing.T) {
    invalid: Compiled
    invalid_pattern := "("
    invalid_result := compile(&invalid, transmute([]u8)invalid_pattern)
    testing.expect_value(t, invalid_result.status, Compile_Status.Invalid_Pattern)
    testing.expect(t, invalid_result.error_code != 0)
    testing.expect_value(t, invalid.code, (^raw.Code)(nil))
    release(&invalid)

    empty: Compiled
    empty_source := ""
    empty_result := compile(&empty, transmute([]u8)empty_source)
    testing.expect_value(t, empty_result.status, Compile_Status.Success)
    defer release(&empty)
    testing.expect_value(t, match(&empty, transmute([]u8)empty_source).status,
        Match_Status.Matched)
}

// Cancellation is observed inside matching and reports its own outcome.
@(test)
pcre2_cancellation_aborts_match :: proc(t: ^testing.T) {
    compiled: Compiled
    pattern := "a+"
    source := "aaaaaaaa"
    result := compile(&compiled, transmute([]u8)pattern)
    testing.expect_value(t, result.status, Compile_Status.Success)
    defer release(&compiled)

    token: Cancel_Token
    cancel_token_init(&token)
    cancel_token_request(&token)
    testing.expect_value(t,
        match(&compiled, transmute([]u8)source, &token).status,
        Match_Status.Cancelled)
    cancel_token_reset(&token)
    testing.expect_value(t,
        match(&compiled, transmute([]u8)source, &token).status,
        Match_Status.Matched)
}

// Match limits stop pathological backtracking without becoming a no-match.
@(test)
pcre2_match_limit_is_explicit :: proc(t: ^testing.T) {
    limits: Limits = {
        match_limit = 1,
        depth_limit = DEFAULT_LIMITS.depth_limit,
        heap_limit_kib = DEFAULT_LIMITS.heap_limit_kib,
    }
    compiled: Compiled
    pattern := "^(a|aa)+$"
    result := compile(&compiled, transmute([]u8)pattern,
        DEFAULT_COMPILE_OPTIONS, limits)
    testing.expect_value(t, result.status, Compile_Status.Success)
    defer release(&compiled)

    subject: [129]u8
    for index in 0 ..< 128 {
        subject[index] = 'a'
    }
    subject[128] = '!'
    testing.expect_value(t,
        match(&compiled, subject[:]).status,
        Match_Status.Match_Limit)
}

// PCRE2 reports its loaded engine version and repeated release is harmless.
@(test)
pcre2_runtime_and_repeated_lifetimes :: proc(t: ^testing.T) {
    version: [64]u8
    version_length := raw.pcre2_config_8(
        raw.CONFIG_VERSION, rawptr(&version[0]))
    testing.expect(t, version_length > 0 && version_length <= c.int(len(version)))
    testing.expect(t, version[0] != 0)

    for _ in 0 ..< 64 {
        compiled: Compiled
        pattern := "(?<=a)b"
        source := "ab"
        result := compile(&compiled, transmute([]u8)pattern)
        testing.expect_value(t, result.status, Compile_Status.Success)
        testing.expect_value(t,
            match(&compiled, transmute([]u8)source).status,
            Match_Status.Matched)
        release(&compiled)
        release(&compiled)
        testing.expect_value(t, compiled.code, (^raw.Code)(nil))
    }
}

// Invalid limits and reinitialization fail explicitly without acquiring handles.
@(test)
pcre2_rejects_invalid_lifetime_inputs :: proc(t: ^testing.T) {
    limits := DEFAULT_LIMITS
    limits.heap_limit_kib = 0
    compiled: Compiled
    first_pattern := "a"
    second_pattern := "b"
    result := compile(&compiled, transmute([]u8)first_pattern,
        DEFAULT_COMPILE_OPTIONS, limits)
    testing.expect_value(t, result.status, Compile_Status.Invalid_Limits)

    testing.expect_value(t, compile(&compiled, transmute([]u8)first_pattern).status,
        Compile_Status.Success)
    testing.expect_value(t, compile(&compiled, transmute([]u8)second_pattern).status,
        Compile_Status.Invalid_State)
    release(&compiled)
}

// Request cancellation only after the interpreter has entered multiple callout sites.
pcre2_test_cancel_during_callout :: proc "c" (
    block: ^raw.Callout_Block, user_data: rawptr) -> c.int {
    state := cast(^Pcre2_Test_Callout_State)user_data
    state.count += 1
    if state.count == 16 {
        sync.atomic_store_explicit(&state.token.requested, 1, .Release)
    }
    return pcre2_cancellation_callout(block, &state.token)
}

// Automatic callouts stop an already-running match, not only pre-cancelled work.
@(test)
pcre2_cancels_inside_interpreter :: proc(t: ^testing.T) {
    pattern := "(*NO_START_OPT)(*NO_AUTO_POSSESS)^(a|aa)+$"
    subject := "aaaaaaaaaaaaaaaaaaaaaaaa!"
    compiled: Compiled
    result := compile(&compiled, transmute([]u8)pattern)
    testing.expect_value(t, result.status, Compile_Status.Success)
    defer release(&compiled)
    if result.status != .Success {
        return
    }
    state: Pcre2_Test_Callout_State
    testing.expect_value(t, raw.pcre2_set_callout_8(
        compiled.match_context, pcre2_test_cancel_during_callout, &state), c.int(0))
    match_code := raw.pcre2_match_8(
        compiled.code, raw_data(subject), uintptr(len(subject)), 0,
        DEFAULT_MATCH_OPTIONS, compiled.match_data, compiled.match_context)
    testing.expect_value(t, state.count, 16)
    testing.expect_value(t, match_code, raw.ERROR_CALLOUT)
    testing.expect_value(t, match_error(match_code).status, Match_Status.Cancelled)
}

// Cleanup accepts every acquired prefix and clears all handles after release.
@(test)
pcre2_releases_partially_initialized_resources :: proc(t: ^testing.T) {
    pattern := "a"
    for stage in 0 ..< 3 {
        compiled: Compiled
        error_code: c.int
        error_offset: uintptr
        compiled.code = raw.pcre2_compile_8(
            raw_data(pattern), uintptr(len(pattern)), DEFAULT_COMPILE_OPTIONS,
            &error_code, &error_offset, nil)
        testing.expect(t, compiled.code != nil)
        if stage >= 1 {
            compiled.match_data = raw.pcre2_match_data_create_from_pattern_8(
                compiled.code, nil)
            testing.expect(t, compiled.match_data != nil)
        }
        if stage >= 2 {
            compiled.match_context = raw.pcre2_match_context_create_8(nil)
            testing.expect(t, compiled.match_context != nil)
        }
        release(&compiled)
        testing.expect(t, compiled.code == nil && compiled.match_data == nil &&
            compiled.match_context == nil)
    }
}

// Preserve distinct resource failures even when PCRE2 allocation failures are rare.
@(test)
pcre2_preserves_native_failure_causes :: proc(t: ^testing.T) {
    testing.expect_value(t, match_error(raw.ERROR_NOMEMORY).status,
        Match_Status.Out_Of_Memory)
    testing.expect_value(t, match_error(raw.ERROR_DEPTHLIMIT).status,
        Match_Status.Depth_Limit)
    testing.expect_value(t, match_error(raw.ERROR_HEAPLIMIT).status,
        Match_Status.Heap_Limit)
    testing.expect_value(t, match_error(c.int(-34)).status, Match_Status.Engine_Error)
}

// Real interpreter depth and heap exhaustion remain distinct from no-match.
@(test)
pcre2_enforces_depth_and_heap_limits :: proc(t: ^testing.T) {
    pattern := "(*NO_START_OPT)(*NO_AUTO_POSSESS)^(a|aa)+$"
    source := "aaaaaaaaaaaaaaaaaaaaaaaa!"
    for kind in 0 ..< 2 {
        limits := DEFAULT_LIMITS
        expected := Match_Status.Depth_Limit
        if kind == 0 {
            limits.depth_limit = 1
        } else {
            limits.heap_limit_kib = 1
            expected = .Heap_Limit
        }
        compiled: Compiled
        result := compile(&compiled, transmute([]u8)pattern,
            DEFAULT_COMPILE_OPTIONS, limits)
        testing.expect_value(t, result.status, Compile_Status.Success)
        if result.status == .Success {
            testing.expect_value(t, match(&compiled, transmute([]u8)source).status,
                expected)
        }
        release(&compiled)
    }
}
