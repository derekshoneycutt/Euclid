package color_model

// Color_RGBA8 stores sRGB-encoded channels with straight alpha coverage.
Color_RGBA8 :: struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
}

BLACK :: Color_RGBA8{0, 0, 0, 255}
WHITE :: Color_RGBA8{255, 255, 255, 255}
TRANSPARENT :: Color_RGBA8{0, 0, 0, 0}