package dynview

import "../core"
import "core:testing"

//   Build one fake corner table with exact low, middle, and high ranges.
math_kern_test_table :: proc(corner: u8) -> core.Font_Math_Kern_Table {
    table := core.Font_Math_Kern_Table{
        valid = true, generation = 17, glyph_id = 9, corner = corner, count = 3}
    table.entries[0] = {-64, -12}
    table.entries[1] = {64, 7}
    table.entries[2] = {192, 21}
    return table
}

//   Verify every corner and both sides of every correction-height boundary.
@(test)
math_kern_tables_resolve_all_corners_and_boundaries :: proc(t: ^testing.T) {
    heights := [7]i32{-65, -64, -63, 64, 65, 192, 193}
    expected := [7]i32{-12, -12, 7, 7, 21, 21, 21}
    for corner in u8(0)..=u8(3) {
        table := math_kern_test_table(corner)
        for height, index in heights {
            value, ok := math_kern_value(table, 17, height)
            testing.expect(t, ok)
            testing.expect_value(t, value, expected[index])
        }
    }
}

//   Verify absent data is zero while stale and malformed records reject.
@(test)
math_kern_tables_define_absence_and_reject_invalid_records :: proc(t: ^testing.T) {
    empty := math_kern_test_table(0)
    empty.count = 0
    zero, empty_ok := math_kern_value(empty, 17, 500)
    stale, stale_ok := math_kern_value(empty, 16, 500)
    malformed := math_kern_test_table(0)
    malformed.entries[1].max_correction_height = -128
    _, malformed_ok := math_kern_value(malformed, 17, 0)
    testing.expect(t, empty_ok && zero == 0)
    testing.expect(t, !stale_ok && stale == 0 && !malformed_ok)
}