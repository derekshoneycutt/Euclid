package ui_dynview

import "core:testing"

//   Verify stacked limits remain inside the large operator's measured box.
@(test)
layout_draw_test_large_op_limit_tops_match_measured_stack :: proc(t: ^testing.T) {
    metrics := Large_Op_Metrics{
        glyph_ascent = 20,
        glyph_descent = 8,
        sup_height = 6,
        limit_gap = 2,
        sup_cols = 1,
    }

    sup_top := large_op_limit_top(metrics, 10, .Superscript)
    sub_top := large_op_limit_top(metrics, 10, .Subscript)

    testing.expect_value(t, sup_top, f32(10))
    testing.expect_value(t, sub_top, f32(48))
}