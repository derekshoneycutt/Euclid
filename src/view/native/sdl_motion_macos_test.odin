#+build darwin
#+test

package native

import "core:testing"

// The native query must dispatch the NSWorkspace class and instance selectors.
@(test)
sdl_motion_macos_native_query_is_supported :: proc(t: ^testing.T) {
    _, status := sdl_query_reduced_motion()
    testing.expect_value(t, status, Sdl_Motion_Status.Supported)
}
