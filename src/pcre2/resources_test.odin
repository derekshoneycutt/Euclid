#+test
package pcre2

import "core:testing"

// Caller-owned API-boundary evidence; PCRE2 allocates and frees its own storage.
Resource_Test_State :: struct {
    fail_at: int,
    attempts: int,
    acquired: int,
    released: int,
    bad_releases: int,
    handles: [3]rawptr,
}

// Inject a failed acquisition before the selected native allocation API is called.
resource_test_reject_acquisition :: proc(state: ^Resource_Test_State) -> bool {
    if state == nil {
        return false
    }
    state.attempts += 1
    return state.attempts == state.fail_at
}

// Record each real PCRE2 handle acquired while one fixture is active.
resource_test_acquired :: proc(state: ^Resource_Test_State, handle: rawptr) {
    if state == nil || handle == nil {
        return
    }
    for &slot in state.handles {
        if slot == nil {
            slot = handle
            state.acquired += 1
            return
        }
    }
    state.bad_releases += 1
}

// Consume the exact live handle before forwarding to its PCRE2 release API.
resource_test_released :: proc(state: ^Resource_Test_State, handle: rawptr) {
    if state == nil {
        return
    }
    for &slot in state.handles {
        if slot == handle && handle != nil {
            slot = nil
            state.released += 1
            return
        }
    }
    state.bad_releases += 1
}

// Every acquisition failure unwinds the successfully acquired prefix exactly once.
@(test)
pcre2_acquisition_failures_unwind_native_handles :: proc(t: ^testing.T) {
    pattern := "(a)\\1"
    for stage in 1 ..= 3 {
        state: Resource_Test_State = {
            fail_at = stage,
        }
        compiled: Compiled = {
            test_resources = &state,
        }
        result := compile(&compiled, transmute([]u8)pattern)
        release(&compiled)
        release(&compiled)
        testing.expect_value(t, result.status, Compile_Status.Out_Of_Memory)
        testing.expect_value(t, state.attempts, stage)
        testing.expect_value(t, state.acquired, stage - 1)
        testing.expect_value(t, state.released, state.acquired)
        testing.expect_value(t, state.bad_releases, 0)
        testing.expect(t, compiled.code == nil && compiled.match_data == nil &&
            compiled.match_context == nil)
        for handle in state.handles {
            testing.expect(t, handle == nil)
        }
    }
}

// Reusing matching storage and replacing patterns leaves no outstanding handles.
@(test)
pcre2_replacements_balance_native_handles :: proc(t: ^testing.T) {
    state: Resource_Test_State
    pattern := "(a)\\1"
    source := "aa"
    compiled: Compiled = {
        test_resources = &state,
    }
    for _ in 0 ..< 128 {
        result := compile(&compiled, transmute([]u8)pattern)
        testing.expect_value(t, result.status, Compile_Status.Success)
        code, data, match_context := compiled.code, compiled.match_data,
            compiled.match_context
        for _ in 0 ..< 8 {
            testing.expect_value(t, match(&compiled, transmute([]u8)source).status,
                Match_Status.Matched)
        }
        testing.expect(t, code == compiled.code && data == compiled.match_data &&
            match_context == compiled.match_context)
        release(&compiled)
        release(&compiled)
        for handle in state.handles {
            testing.expect(t, handle == nil)
        }
    }
    testing.expect_value(t, state.acquired, 128 * 3)
    testing.expect_value(t, state.released, state.acquired)
    testing.expect_value(t, state.bad_releases, 0)
}
