#+test
package main

import pcre2 "pcre2"
import raw "../libs/pcre2"

import "core:c"
import "core:testing"

// Verify native PCRE2 ABI widths and include the owner package in the full unit suite.
@(test)
pcre2_substrate_matches_native_abi :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(c.int), 4)
    testing.expect_value(t, size_of(u32), 4)
    testing.expect_value(t, size_of(uintptr), size_of(c.size_t))
    testing.expect_value(t, size_of(^raw.Code), size_of(rawptr))
    compiled: pcre2.Compiled
    pattern := "a"
    result := pcre2.compile(&compiled, transmute([]u8)pattern)
    testing.expect_value(t, result.status, pcre2.Compile_Status.Success)
    pcre2.release(&compiled)
}
