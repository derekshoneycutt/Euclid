#+test
package terminalview

import "core:testing"

// Verify the anchor colors (black, given hues, explicit white) resolve exactly.
@(test)
terminal_test_palette_rgba_normal :: proc(t: ^testing.T) {
    testing.expect_value(t, terminal_palette_rgba(.Black), u32(0x000000FF))
    testing.expect_value(t, terminal_palette_rgba(.Red), u32(0xCB3C33FF))
    testing.expect_value(t, terminal_palette_rgba(.Green), u32(0x389826FF))
    testing.expect_value(t, terminal_palette_rgba(.Blue), u32(0x4063D8FF))
    testing.expect_value(t, terminal_palette_rgba(.Magenta), u32(0x9558B2FF))
    testing.expect_value(t, terminal_palette_rgba(.White), u32(0xFFFFFFFF))
}

// Verify bright-tier colors are their normal-tier color blended toward white.
@(test)
terminal_test_palette_rgba_bright :: proc(t: ^testing.T) {
    testing.expect_value(t, terminal_palette_rgba(.Dark_Grey), u32(0x595959FF))
    testing.expect_value(t, terminal_palette_rgba(.Bright_Red), u32(0xDD807AFF))
}

// Verify channel brightening blends toward 255 by the given fraction, rounded.
@(test)
terminal_test_brighten_channel :: proc(t: ^testing.T) {
    testing.expect_value(t, terminal_brighten_channel(0, 0.35), u8(89))
    testing.expect_value(t, terminal_brighten_channel(255, 0.35), u8(255))
}
