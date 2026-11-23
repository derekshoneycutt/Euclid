package presentation_source

import presentation_model "../../../bridge/presentation"
import "core:testing"

// Verify MIME and complete outer delimiters jointly determine presentation mode.
@(test)
presentation_source_mode_uses_mime_and_outer_delimiters :: proc(t: ^testing.T) {
    testing.expect_value(t, presentation_source_mode(.Text_Plain, "$x$"),
        Presentation_Source_Mode.Plain)
    testing.expect_value(t, presentation_source_mode(.Text_Latex, " $x$ "),
        Presentation_Source_Mode.Math)
    testing.expect_value(t, presentation_source_mode(.Text_Latex, "\\[x\\]"),
        Presentation_Source_Mode.Math)
    testing.expect_value(t, presentation_source_mode(.Text_Latex, "text $x$"),
        Presentation_Source_Mode.Document)
    testing.expect_value(t, presentation_source_mode(.Text_Latex, "x^2"),
        Presentation_Source_Mode.Document)
}

// Verify literal failure and copy policy borrow the exact canonical bytes.
@(test)
presentation_literal_source_preserves_exact_bytes :: proc(t: ^testing.T) {
    bytes := [?]u8{'A', 0, '\n', '\\', 'x'}
    content: presentation_model.Presented_Text = {
        mime = .Text_Latex,
        bytes = bytes[:],
    }
    literal := presentation_literal_source(content)
    testing.expect_value(t, len(literal), len(bytes))
    testing.expect(t, literal[0] == 'A' && literal[1] == 0)
    testing.expect(t, literal[2] == '\n' && literal[3] == '\\' && literal[4] == 'x')
}
