package view

import accessibility "../accessibility"
import testing "core:testing"
import uiaccessibility "ui/accessibility"

// Verify absent semantic relations remain absent across native projection.
@(test)
accessibility_ui_identity_preserves_empty_sentinel :: proc(t: ^testing.T) {
    testing.expect_value(t, uiaccessibility.accessibility_ui_identity({}),
        accessibility.Qualified_Identity{})
}
