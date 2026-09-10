// Package termpalette owns terminal palette state, parsing, mutation, and resolution.
package termpalette

import termmodel "../model"

// Default terminal foreground encoded as RGBA bytes in one `u32`.
TERMINAL_DEFAULT_FOREGROUND_RGBA :: u32(0xFFFFFFFF)

// Transparent default lets the terminal panel supply its ordinary background.
TERMINAL_DEFAULT_BACKGROUND_RGBA :: u32(0x00000000)

// ANSI normal and bright colors occupying the first 16 indexed palette slots.
TERMINAL_PALETTE :: [16]u32{
    0x000000FF, 0xCB3C33FF, 0x389826FF, 0xCB9C33FF,
    0x4063D8FF, 0x9558B2FF, 0x33A6CBFF, 0xCCCCCCFF,
    0x595959FF, 0xDD807AFF, 0x7EBC72FF, 0xDDBF7AFF,
    0x839AE6FF, 0xBA92CDFF, 0x7AC5DDFF, 0xFFFFFFFF,
}

TERMINAL_COLOR_KIND_SHIFT :: 30
TERMINAL_COLOR_VALUE_MASK :: u32(0x3fffffff)
TERMINAL_COLOR_CANDIDATE_CAPACITY :: 4096
TERMINAL_COLOR_OPERATION_CAPACITY :: 256

// Color register selected by one validated dynamic-color operation.
Terminal_Palette_Target :: enum u8 {
    Indexed,
    Foreground,
    Background,
    Cursor,
}

// Mutation or query retained only while one complete OSC transaction commits.
Terminal_Palette_Operation :: struct {
    target: Terminal_Palette_Target,
    index: u16,
    rgba: u32,
    reset: bool,
    reset_all: bool,
    query: bool,
}

// Bounded parse outcome for one complete dynamic-color OSC payload.
Terminal_Palette_Parse_Result :: struct {
    count: int,
    query_count: int,
    valid: bool,
}

// Fixed terminal-lifetime palette with immutable startup values and current values.
Terminal_Palette_State :: struct {
    colors: [256]u32,
    defaults: [256]u32,
    foreground: u32,
    background: u32,
    cursor: u32,
    default_foreground: u32,
    default_background: u32,
    default_cursor: u32,
    generation: u64,

    // Bounded transaction candidate shared by supported dynamic-color OSC families.
    candidate: [TERMINAL_COLOR_CANDIDATE_CAPACITY]u8,
    candidate_byte_count: int,
    candidate_invalid: bool,

    // Content-free lifetime transaction and query outcomes.
    color_acceptance_count: u64,
    color_rejection_count: u64,
    query_acceptance_count: u64,
    query_rejection_count: u64,
}

// Resolve one standard 256-color startup palette index to opaque RGBA.
terminal_indexed_color_rgba :: proc(index: int) -> u32 {
    if index < 16 {
        palette := TERMINAL_PALETTE
        return palette[index]
    }
    if index < 232 {
        levels := [6]u32{0, 95, 135, 175, 215, 255}
        cube := index - 16
        red := levels[cube / 36]
        green := levels[cube / 6 % 6]
        blue := levels[cube % 6]
        return red << 24 | green << 16 | blue << 8 | 0xff
    }
    gray := u32(8 + 10 * (index - 232))
    return gray << 24 | gray << 16 | gray << 8 | 0xff
}

// Initialize current and startup palette values without allocating storage.
terminal_palette_init :: proc(palette: ^Terminal_Palette_State) {
    if palette == nil {
        return
    }
    palette^ = {
        foreground = TERMINAL_DEFAULT_FOREGROUND_RGBA,
        background = TERMINAL_DEFAULT_BACKGROUND_RGBA,
        cursor = TERMINAL_DEFAULT_FOREGROUND_RGBA,
        default_foreground = TERMINAL_DEFAULT_FOREGROUND_RGBA,
        default_background = TERMINAL_DEFAULT_BACKGROUND_RGBA,
        default_cursor = TERMINAL_DEFAULT_FOREGROUND_RGBA,
    }
    for index in 0..<len(palette.colors) {
        rgba := terminal_indexed_color_rgba(index)
        palette.colors[index] = rgba
        palette.defaults[index] = rgba
    }
}

// Return a validated indexed color reference.
terminal_color_indexed :: proc(index: int) -> termmodel.Terminal_Color_Reference {
    return termmodel.Terminal_Color_Reference(
        u32(termmodel.Terminal_Color_Kind.Indexed) << TERMINAL_COLOR_KIND_SHIFT |
        u32(index))
}

// Return one direct packed-RGBA color reference.
terminal_color_direct :: proc(rgba: u32) -> termmodel.Terminal_Color_Reference {
    return termmodel.Terminal_Color_Reference(
        u32(termmodel.Terminal_Color_Kind.Direct) << TERMINAL_COLOR_KIND_SHIFT |
        rgba >> 8)
}

// Return the semantic kind encoded in one packed color reference.
terminal_color_kind :: proc(
    color: termmodel.Terminal_Color_Reference) -> termmodel.Terminal_Color_Kind {
    return termmodel.Terminal_Color_Kind(u32(color) >> TERMINAL_COLOR_KIND_SHIFT)
}

// Return the payload encoded below one packed color-reference kind.
terminal_color_value :: proc(color: termmodel.Terminal_Color_Reference) -> u32 {
    return u32(color) & TERMINAL_COLOR_VALUE_MASK
}

// Resolve one foreground reference against current palette state or startup defaults.
terminal_color_resolve_foreground :: proc(
    palette: ^Terminal_Palette_State,
    color: termmodel.Terminal_Color_Reference) -> u32 {
    switch terminal_color_kind(color) {
    case .Default:
        return palette.foreground if palette != nil else
            TERMINAL_DEFAULT_FOREGROUND_RGBA
    case .Indexed:
        index := int(terminal_color_value(color))
        if index >= 256 {
            return TERMINAL_DEFAULT_FOREGROUND_RGBA
        }
        return palette.colors[index] if palette != nil else
            terminal_indexed_color_rgba(index)
    case .Direct:
        return terminal_color_value(color) << 8 | 0xff
    }
    return TERMINAL_DEFAULT_FOREGROUND_RGBA
}

// Resolve one background reference against current palette state or startup defaults.
terminal_color_resolve_background :: proc(
    palette: ^Terminal_Palette_State,
    color: termmodel.Terminal_Color_Reference) -> u32 {
    switch terminal_color_kind(color) {
    case .Default:
        return palette.background if palette != nil else
            TERMINAL_DEFAULT_BACKGROUND_RGBA
    case .Indexed:
        index := int(terminal_color_value(color))
        if index >= 256 {
            return TERMINAL_DEFAULT_BACKGROUND_RGBA
        }
        return palette.colors[index] if palette != nil else
            terminal_indexed_color_rgba(index)
    case .Direct:
        return terminal_color_value(color) << 8 | 0xff
    }
    return TERMINAL_DEFAULT_BACKGROUND_RGBA
}

// Resolve the current terminal cursor color or its immutable startup value.
terminal_palette_cursor_rgba :: proc(palette: ^Terminal_Palette_State) -> u32 {
    return palette.cursor if palette != nil else TERMINAL_DEFAULT_FOREGROUND_RGBA
}

// Parse one ASCII hexadecimal digit.
terminal_color_hex_digit :: proc(byte: u8) -> (u32, bool) {
    if byte >= '0' && byte <= '9' { return u32(byte - '0'), true }
    if byte >= 'a' && byte <= 'f' { return u32(byte - 'a' + 10), true }
    if byte >= 'A' && byte <= 'F' { return u32(byte - 'A' + 10), true }
    return 0, false
}

// Parse and normalize one one-to-four-digit hexadecimal channel to eight bits.
terminal_color_parse_channel :: proc(bytes: []u8) -> (u32, bool) {
    if len(bytes) < 1 || len(bytes) > 4 { return 0, false }
    value: u32
    for byte in bytes {
        digit, valid := terminal_color_hex_digit(byte)
        if !valid { return 0, false }
        value = value << 4 | digit
    }
    maximum := u32(1) << u32(len(bytes) * 4) - 1
    return (value * 255 + maximum / 2) / maximum, true
}

// Extract three equal-width channels from one supported xterm color syntax.
terminal_color_specification_channels :: proc(
    bytes: []u8, channels: ^[3][]u8) -> bool {
    if len(bytes) > 0 && bytes[0] == '#' {
        if (len(bytes) - 1) % 3 != 0 { return false }
        width := (len(bytes) - 1) / 3
        if width < 1 || width > 4 { return false }
        for index in 0..<3 {
            start := 1 + index * width
            channels[index] = bytes[start:start + width]
        }
    } else {
        if len(bytes) < 4 || bytes[0] != 'r' || bytes[1] != 'g' ||
            bytes[2] != 'b' || bytes[3] != ':' { return false }
        start, channel := 4, 0
        for index in start..=len(bytes) {
            if index < len(bytes) && bytes[index] != '/' { continue }
            if channel >= 3 { return false }
            channels[channel] = bytes[start:index]
            channel += 1
            start = index + 1
        }
        if channel != 3 { return false }
    }
    return len(channels[0]) == len(channels[1]) &&
        len(channels[1]) == len(channels[2])
}

// Parse one xterm `#RGB` or `rgb:R/G/B` specification to opaque RGBA.
terminal_color_parse_specification :: proc(bytes: []u8) -> (u32, bool) {
    channels: [3][]u8
    if !terminal_color_specification_channels(bytes, &channels) {
        return 0, false
    }
    red, red_valid := terminal_color_parse_channel(channels[0])
    green, green_valid := terminal_color_parse_channel(channels[1])
    blue, blue_valid := terminal_color_parse_channel(channels[2])
    if !red_valid || !green_valid || !blue_valid { return 0, false }
    return red << 24 | green << 16 | blue << 8 | 0xff, true
}

// Parse one bounded decimal palette index.
terminal_color_parse_index :: proc(bytes: []u8) -> (u16, bool) {
    if len(bytes) == 0 { return 0, false }
    value := 0
    for byte in bytes {
        if byte < '0' || byte > '9' { return 0, false }
        value = value * 10 + int(byte - '0')
        if value > 255 { return 0, false }
    }
    return u16(value), true
}

// Split one semicolon-delimited payload into caller-owned bounded token storage.
terminal_color_split_payload :: proc(
    payload: []u8, tokens: []([]u8)) -> (int, bool) {
    if len(payload) == 0 { return 0, true }
    count, start := 0, 0
    for index in 0..=len(payload) {
        if index < len(payload) && payload[index] != ';' { continue }
        if count >= len(tokens) || index == start { return 0, false }
        tokens[count] = payload[start:index]
        count += 1
        start = index + 1
    }
    return count, true
}

// Parse OSC 4 indexed set/query pairs into bounded operations.
terminal_palette_parse_indexed_pairs :: proc(
    tokens: []([]u8), operations: []Terminal_Palette_Operation) ->
    Terminal_Palette_Parse_Result {
    if len(tokens) == 0 || len(tokens) % 2 != 0 { return {} }
    result := Terminal_Palette_Parse_Result{valid = true}
    for index in 0..<len(tokens) / 2 {
            palette_index, index_valid := terminal_color_parse_index(tokens[index * 2])
            if !index_valid { return {} }
            specification := tokens[index * 2 + 1]
            operation := Terminal_Palette_Operation{
                target = .Indexed, index = palette_index,
            }
            if len(specification) == 1 && specification[0] == '?' {
                operation.query = true
                result.query_count += 1
            } else {
                rgba, valid := terminal_color_parse_specification(specification)
                if !valid { return {} }
                operation.rgba = rgba
            }
            operations[result.count] = operation
            result.count += 1
    }
    return result
}

// Parse OSC 104 indexed reset selectors into bounded operations.
terminal_palette_parse_indexed_resets :: proc(
    tokens: []([]u8), operations: []Terminal_Palette_Operation) ->
    Terminal_Palette_Parse_Result {
    if len(tokens) == 0 {
        operations[0] = {target = .Indexed, reset = true, reset_all = true}
        return {count = 1, valid = true}
    }
    if len(tokens) > len(operations) { return {} }
    for token, index in tokens {
        palette_index, valid := terminal_color_parse_index(token)
        if !valid { return {} }
        operations[index] = {
            target = .Indexed, index = palette_index, reset = true,
        }
    }
    return {count = len(tokens), valid = true}
}

// Parse one default foreground, background, or cursor color operation.
terminal_palette_parse_default_color :: proc(
    command: int, tokens: []([]u8), operations: []Terminal_Palette_Operation) ->
    Terminal_Palette_Parse_Result {
    target: Terminal_Palette_Target
    switch command {
    case 10, 110: target = .Foreground
    case 11, 111: target = .Background
    case 12, 112: target = .Cursor
    case: return {}
    }
    if command >= 110 {
        if len(tokens) != 0 { return {} }
        operations[0] = {target = target, reset = true}
        return {count = 1, valid = true}
    }
    if len(tokens) != 1 { return {} }
    operation := Terminal_Palette_Operation{target = target}
    if len(tokens[0]) == 1 && tokens[0][0] == '?' {
        operation.query = true
        operations[0] = operation
        return {count = 1, query_count = 1, valid = true}
    } else {
        rgba, valid := terminal_color_parse_specification(tokens[0])
        if !valid { return {} }
        operation.rgba = rgba
    }
    operations[0] = operation
    return {count = 1, valid = true}
}

// Parse one dynamic-color OSC payload into bounded semantic operations.
terminal_palette_parse_osc :: proc(
    command: int, payload: []u8,
    operations: []Terminal_Palette_Operation) -> Terminal_Palette_Parse_Result {
    tokens: [TERMINAL_COLOR_OPERATION_CAPACITY * 2][]u8
    token_count, valid := terminal_color_split_payload(payload, tokens[:])
    if !valid { return {} }
    switch command {
    case 4:
        return terminal_palette_parse_indexed_pairs(
            tokens[:token_count], operations)
    case 104:
        return terminal_palette_parse_indexed_resets(
            tokens[:token_count], operations)
    case 10, 11, 12, 110, 111, 112:
        return terminal_palette_parse_default_color(
            command, tokens[:token_count], operations)
    }
    return {}
}

// Return the current RGBA value selected by one semantic palette operation.
terminal_palette_operation_rgba :: proc(
    palette: ^Terminal_Palette_State,
    operation: Terminal_Palette_Operation) -> u32 {
    switch operation.target {
    case .Indexed: return palette.colors[operation.index]
    case .Foreground: return palette.foreground
    case .Background: return palette.background
    case .Cursor: return palette.cursor
    }
    return 0
}

// Resolve one operation's immutable startup color.
terminal_palette_operation_default :: proc(
    palette: ^Terminal_Palette_State,
    operation: Terminal_Palette_Operation) -> u32 {
    switch operation.target {
    case .Indexed: return palette.defaults[operation.index]
    case .Foreground: return palette.default_foreground
    case .Background: return palette.default_background
    case .Cursor: return palette.default_cursor
    }
    return 0
}

// Store one resolved value in the register selected by an operation.
terminal_palette_store_operation :: proc(
    palette: ^Terminal_Palette_State,
    operation: Terminal_Palette_Operation, value: u32) {
    switch operation.target {
    case .Indexed: palette.colors[operation.index] = value
    case .Foreground: palette.foreground = value
    case .Background: palette.background = value
    case .Cursor: palette.cursor = value
    }
}

// Apply one validated palette mutation and report whether state changed.
terminal_palette_apply_operation :: proc(
    palette: ^Terminal_Palette_State,
    operation: Terminal_Palette_Operation) -> bool {
    if operation.query { return false }
    if operation.reset_all {
        palette.colors = palette.defaults
        return true
    }
    value := terminal_palette_operation_default(palette, operation) if
        operation.reset else operation.rgba
    terminal_palette_store_operation(palette, operation, value)
    return true
}