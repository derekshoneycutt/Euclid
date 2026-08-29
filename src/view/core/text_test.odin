#+test
package view_core

import "core:testing"

// Verify HarfBuzz byte clusters map to Euclid codepoint columns.
@(test)
text_test_cluster_column :: proc(t: ^testing.T) {
    text: string = "aα=>"

    column, valid := ui_text_cluster_column(text, 0)
    testing.expect(t, valid)
    testing.expect_value(t, column, 0)

    column, valid = ui_text_cluster_column(text, 1)
    testing.expect(t, valid)
    testing.expect_value(t, column, 1)

    column, valid = ui_text_cluster_column(text, 3)
    testing.expect(t, valid)
    testing.expect_value(t, column, 2)

    _, valid = ui_text_cluster_column(text, 2)
    testing.expect(t, !valid)
}