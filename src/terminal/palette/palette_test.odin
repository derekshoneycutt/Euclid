#+test
package termpalette

import "core:testing"

// Verify startup palette values and semantic color references resolve exactly.
@(test)
palette_test_color_resolution :: proc(t: ^testing.T) {
    palette: Terminal_Palette_State
    terminal_palette_init(&palette)

    testing.expect_value(t, palette.colors[1], u32(0xCB3C33FF))
    testing.expect_value(t, terminal_color_resolve_foreground(
        &palette, terminal_color_indexed(1)), u32(0xCB3C33FF))
    testing.expect_value(t, terminal_color_resolve_background(
        &palette, terminal_color_direct(0x123456FF)), u32(0x123456FF))
}