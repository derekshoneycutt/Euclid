package color

// Color_RGBA8 stores sRGB-encoded channels with straight alpha coverage.
Color_RGBA8 :: distinct [4]u8

BLACK :: Color_RGBA8{0, 0, 0, 255}
WHITE :: Color_RGBA8{255, 255, 255, 255}
TRANSPARENT :: Color_RGBA8{0, 0, 0, 0}

#assert(size_of(Color_RGBA8) == 4)
#assert(align_of(Color_RGBA8) == align_of(u8))

// Named_Color_Entry maps one exact source name to an opaque RGBA8 value.
Named_Color_Entry :: struct {
    name: string,
    value: Color_RGBA8,
}

// resolve_named_color resolves Colors.jl names and Euclid's project palette aliases.
resolve_named_color :: proc(name: string) -> (Color_RGBA8, bool) {
    for entry in NAMED_COLORS {
        if entry.name == name {
            return entry.value, true
        }
    }
    switch name {
    case "julia_blue": return {64, 99, 216, 255}, true
    case "julia_green": return {56, 152, 38, 255}, true
    case "julia_purple": return {149, 88, 178, 255}, true
    case "julia_red": return {203, 60, 51, 255}, true
    }
    return {}, false
}