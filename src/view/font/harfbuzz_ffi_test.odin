#+test
package font

import harfbuzz "../../../libs/harfbuzz"

import "core:testing"

// Verify the dependency-owned HarfBuzz version query ABI is linked and callable.
@(test)
view_test_harfbuzz_library_version :: proc(t: ^testing.T) {
    major, minor, micro: u32
    harfbuzz.hb_version(&major, &minor, &micro)
    testing.expect(t, major > 0)
    testing.expect(t,
        harfbuzz.hb_version_atleast(major, minor, micro) != 0)
    testing.expect(t, harfbuzz.hb_version_string() != nil)
}