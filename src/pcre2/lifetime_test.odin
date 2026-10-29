#+test
package pcre2

import "core:c"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import raw "../../libs/pcre2"

// Joined fixture storage remains live until the native match thread returns.
Lifetime_Test_Work :: struct {
    compiled: ^Compiled,
    cancel: Cancel_Token,
    entered: int,
    result: c.int,
}

// Hold an actual interpreter borrow until cancellation is published by the owner.
pcre2_test_hold_borrow :: proc "c" (
    block: ^raw.Callout_Block, user_data: rawptr) -> c.int {
    work := cast(^Lifetime_Test_Work)user_data
    sync.atomic_store_explicit(&work.entered, 1, .Release)
    for sync.atomic_load_explicit(&work.cancel.requested, .Acquire) == 0 {
        sync.cpu_relax()
    }
    return pcre2_cancellation_callout(block, &work.cancel)
}

// Execute a gated native match; no Julia or owning-resource mutation is involved.
pcre2_test_match_worker :: proc(worker: ^thread.Thread) {
    work := cast(^Lifetime_Test_Work)worker.data
    source := "aaaaaaaa"
    work.result = raw.pcre2_match_8(
        work.compiled.code, raw_data(source), uintptr(len(source)), 0,
        DEFAULT_MATCH_OPTIONS, work.compiled.match_data,
        work.compiled.match_context)
}

// Wait with a bounded deadline so a missing automatic callout fails rather than hangs.
pcre2_test_wait_for_borrow :: proc(work: ^Lifetime_Test_Work) -> bool {
    deadline := time.tick_now()
    for time.tick_since(deadline) < 5 * time.Second {
        if sync.atomic_load_explicit(&work.entered, .Acquire) != 0 {
            return true
        }
        thread.yield()
    }
    return false
}

// Cancel and join a real borrower before release, replacement, or shutdown.
pcre2_test_join_borrower :: proc(t: ^testing.T, compiled: ^Compiled) {
    work: Lifetime_Test_Work = {
        compiled = compiled,
    }
    testing.expect_value(t, raw.pcre2_set_callout_8(
        compiled.match_context, pcre2_test_hold_borrow, &work), c.int(0))
    worker := thread.create(pcre2_test_match_worker)
    testing.expect(t, worker != nil)
    if worker == nil {
        return
    }
    worker.data = &work
    thread.start(worker)
    entered := pcre2_test_wait_for_borrow(&work)
    testing.expect(t, entered)
    testing.expect_value(t, compiled.test_resources.released, 0)
    cancel_token_request(&work.cancel)
    thread.join(worker)
    thread.destroy(worker)
    testing.expect_value(t, work.result, raw.ERROR_CALLOUT)
    testing.expect_value(t, raw.pcre2_set_callout_8(
        compiled.match_context, nil, nil), c.int(0))
}

// Replacement and final shutdown each retain all handles until an active borrower joins.
@(test)
pcre2_replacement_and_shutdown_join_before_free :: proc(t: ^testing.T) {
    pattern := "a+"
    for _ in 0 ..< 2 {
        state: Resource_Test_State
        compiled: Compiled = {
            test_resources = &state,
        }
        result := compile(&compiled, transmute([]u8)pattern)
        testing.expect_value(t, result.status, Compile_Status.Success)
        if result.status == .Success {
            pcre2_test_join_borrower(t, &compiled)
        }
        release(&compiled)
        release(&compiled)
        testing.expect_value(t, state.acquired, 3)
        testing.expect_value(t, state.released, 3)
        testing.expect_value(t, state.bad_releases, 0)
        for handle in state.handles {
            testing.expect(t, handle == nil)
        }
    }
}
