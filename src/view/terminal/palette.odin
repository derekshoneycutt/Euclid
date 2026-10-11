package terminalview

// The 16 standard TTY colors: 0-7 normal tones, 8-15 their brightened variants.
Terminal_Color :: enum {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Light_Grey,
    Dark_Grey,
    Bright_Red,
    Bright_Green,
    Bright_Yellow,
    Bright_Blue,
    Bright_Magenta,
    Bright_Cyan,
    White,
}

// Packed 0xRRGGBB base tones for the 8 normal-tier colors; the bright tier
// (indices 8-14) is derived from these via terminal_brighten, and White (15)
// is the one explicit exception, standing apart from Light_Grey (7).
TERMINAL_NORMAL_PALETTE :: [8]u32{
    0x000000, // Black
    0xCB3C33, // Red
    0x389826, // Green
    0xCB9C33, // Yellow
    0x4063D8, // Blue
    0x9558B2, // Magenta
    0x33A6CB, // Cyan
    0xCCCCCC, // Light Grey
}

// Fraction blended toward white when deriving bright colors from normal tones.
TERMINAL_BRIGHTEN_AMOUNT :: f32(0.35)

// Explicit packed RGB value for terminal White, which is not derived from Light Grey.
TERMINAL_WHITE_RGB :: u32(0xFFFFFF)

//   Resolve one of the 16 standard TTY colors to a packed opaque RGBA color.
//
// Parameters:
//   - color: The standard color index to resolve.
//
// Returns:
//   - The color's packed 0xRRGGBBAA value, fully opaque.
terminal_palette_rgba :: proc(color: Terminal_Color) -> u32 {
    index := int(color)
    normal_palette := TERMINAL_NORMAL_PALETTE

    rgb: u32
    if color == .White {
        rgb = TERMINAL_WHITE_RGB
    } else if index < len(normal_palette) {
        rgb = normal_palette[index]
    } else {
        rgb = terminal_brighten(
            normal_palette[index - len(normal_palette)], TERMINAL_BRIGHTEN_AMOUNT)
    }

    return (rgb << 8) | 0xFF
}

//   Blend one packed 0xRRGGBB color a fraction of the way toward white.
//
// Parameters:
//   - rgb: The base packed 0xRRGGBB color.
//   - amount: The blend fraction toward white, in [0,1].
//
// Returns:
//   - The blended packed 0xRRGGBB color.
terminal_brighten :: proc(rgb: u32, amount: f32) -> u32 {
    r := terminal_brighten_channel(u8(rgb >> 16 & 0xFF), amount)
    g := terminal_brighten_channel(u8(rgb >> 8 & 0xFF), amount)
    b := terminal_brighten_channel(u8(rgb & 0xFF), amount)
    return (u32(r) << 16) | (u32(g) << 8) | u32(b)
}

//   Blend one 0-255 color channel a fraction of the way toward 255.
//
// Parameters:
//   - channel: The base channel value.
//   - amount: The blend fraction toward 255, in [0,1].
//
// Returns:
//   - The blended, rounded channel value.
terminal_brighten_channel :: proc(channel: u8, amount: f32) -> u8 {
    blended := f32(channel) + (255 - f32(channel)) * amount
    return u8(blended + 0.5)
}
