#+test
package profile

import "core:os"
import "core:testing"

// Verify the default facade accepts every operation without creating output.
@(test)
profile_test_none_is_noop :: proc(t: ^testing.T) {
    state: State
    init_none(&state)
    zone_begin(&state, "work")
    counter(&state, "depth", 3)
    message(&state, "marker")
    frame(&state)
    zone_end(&state)
    destroy(&state)
    testing.expect_value(t, state.backend, Backend.None)
}

// Verify explicit Spall profiling flushes a readable nonempty stream.
@(test)
profile_test_spall_stream :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/profile.spall"
    os.make_directory_all(".build/test-artifacts")
    os.remove(path)
    state: State
    testing.expect(t, init_spall(&state, path))
    thread_name(&state, "profile-test")
    zone_begin(&state, "work")
    zone_end(&state)
    frame(&state)
    destroy(&state)
    info, info_error := os.stat(path, context.allocator)
    testing.expect(t, info_error == nil)
    testing.expect(t, info.size > 0)
    os.remove(path)
}
