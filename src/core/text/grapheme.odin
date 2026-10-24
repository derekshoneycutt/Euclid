package coretext

import unicode "core:unicode"
import utf8 "core:unicode/utf8"

// Unicode grapheme properties come from Odin core:unicode (Unicode 15.1 data).
// Segmentation follows UAX #29 extended grapheme rules GB3-GB13.

// text_grapheme_clamp_boundary returns the preceding complete cluster boundary.
text_grapheme_clamp_boundary :: proc(text: string, offset: int) -> int {
    target := text_codepoint_clamp_boundary(text, offset)
    boundary := 0
    for boundary < target {
        next := text_grapheme_next_boundary(text, boundary)
        if next > target {
            return boundary
        }
        if next == target {
            return next
        }
        boundary = next
    }
    return boundary
}

// text_grapheme_previous_boundary returns the prior extended-grapheme boundary.
text_grapheme_previous_boundary :: proc(text: string, offset: int) -> int {
    target := text_grapheme_clamp_boundary(text, offset)
    if target <= 0 {
        return 0
    }
    boundary := 0
    previous := 0
    for boundary < target {
        previous = boundary
        boundary = text_grapheme_next_boundary(text, boundary)
    }
    return previous
}

// text_grapheme_next_boundary returns the next complete cluster boundary.
text_grapheme_next_boundary :: proc(text: string, offset: int) -> int {
    boundary := text_codepoint_clamp_boundary(text, offset)
    if boundary >= len(text) {
        return len(text)
    }
    previous, previous_width := utf8.decode_rune_in_string(text[boundary:])
    next := boundary + previous_width
    for next < len(text) {
        current, current_width := utf8.decode_rune_in_string(text[next:])
        if text_grapheme_breaks(text, next, previous, current) {
            break
        }
        previous = current
        next += current_width
    }
    return next
}

// text_grapheme_width measures one cluster in monospace cells.
text_grapheme_width :: proc(text: string, start, end: int) -> int {
    width := 0
    regional_indicators := 0
    for offset := start; offset < end; {
        codepoint, count := utf8.decode_rune_in_string(text[offset:end])
        width = max(width, unicode.normalized_east_asian_width(codepoint))
        if codepoint == 0xFE0F {
            width = max(width, 2)
        }
        if unicode.is_regional_indicator(codepoint) {
            regional_indicators += 1
        }
        offset += count
    }
    return 2 if regional_indicators == 2 else width
}

// text_grapheme_column maps a byte boundary to its monospace display column.
text_grapheme_column :: proc(text: string, offset: int) -> int {
    target := text_grapheme_clamp_boundary(text, offset)
    column := 0
    for start := 0; start < target; {
        end := text_grapheme_next_boundary(text, start)
        column += text_grapheme_width(text, start, end)
        start = end
    }
    return column
}

// text_grapheme_boundary_for_column maps a display column to the nearest cluster edge.
text_grapheme_boundary_for_column :: proc(text: string, column: int) -> int {
    target := max(0, column)
    current_column := 0
    for start := 0; start < len(text); {
        end := text_grapheme_next_boundary(text, start)
        width := text_grapheme_width(text, start, end)
        if width > 0 && target < current_column + width {
            return start if target - current_column < (width + 1) / 2 else end
        }
        current_column += width
        start = end
    }
    return len(text)
}

// text_grapheme_breaks applies UAX #29 boundaries using Odin's Unicode properties.
text_grapheme_breaks :: proc(
    text: string, boundary: int, previous, current: rune) -> bool {
    if previous == '\r' && current == '\n' {
        return false
    }
    if unicode.is_control(previous) || unicode.is_control(current) ||
        previous == '\r' || previous == '\n' || current == '\r' || current == '\n' {
        return true
    }
    if text_grapheme_hangul_no_break(previous, current) {
        return false
    }
    if text_grapheme_extend(current) || current == unicode.ZERO_WIDTH_JOINER ||
        unicode.is_spacing_mark(current) || unicode.is_gcb_prepend_class(previous) {
        return false
    }
    if unicode.is_indic_conjunct_break_consonant(current) &&
        text_indic_conjunct_precedes(text, boundary) {
        return false
    }
    if unicode.is_emoji_extended_pictographic(current) &&
        text_emoji_zwj_precedes(text, boundary) {
        return false
    }
    if unicode.is_regional_indicator(previous) &&
        unicode.is_regional_indicator(current) {
        return text_regional_indicator_count(text, boundary) % 2 == 0
    }
    return true
}

// text_grapheme_hangul_no_break implements the three Hangul syllable rules.
text_grapheme_hangul_no_break :: proc(previous, current: rune) -> bool {
    joins_leading := unicode.is_hangul_syllable_leading(previous) &&
        (unicode.is_hangul_syllable_leading(current) ||
         unicode.is_hangul_syllable_vowel(current) ||
         unicode.is_hangul_syllable_lv(current) ||
         unicode.is_hangul_syllable_lvt(current))
    joins_vowel := (unicode.is_hangul_syllable_lv(previous) ||
        unicode.is_hangul_syllable_vowel(previous)) &&
        (unicode.is_hangul_syllable_vowel(current) ||
         unicode.is_hangul_syllable_trailing(current))
    joins_trailing := (unicode.is_hangul_syllable_lvt(previous) ||
        unicode.is_hangul_syllable_trailing(previous)) &&
        unicode.is_hangul_syllable_trailing(current)
    return joins_leading || joins_vowel || joins_trailing
}

// text_indic_conjunct_precedes recognizes a linker sequence after a consonant.
text_indic_conjunct_precedes :: proc(text: string, boundary: int) -> bool {
    offset := boundary
    linker_seen := false
    for offset > 0 {
        previous, start := text_previous_rune(text, offset)
        if unicode.is_indic_conjunct_break_linker(previous) {
            linker_seen = true
        } else if !unicode.is_indic_conjunct_break_extend(previous) {
            return linker_seen && unicode.is_indic_conjunct_break_consonant(previous)
        }
        offset = start
    }
    return false
}

// text_emoji_zwj_precedes recognizes Extended_Pictographic Extend* ZWJ context.
text_emoji_zwj_precedes :: proc(text: string, boundary: int) -> bool {
    previous, offset := text_previous_rune(text, boundary)
    if previous != unicode.ZERO_WIDTH_JOINER {
        return false
    }
    for offset > 0 {
        preceding, start := text_previous_rune(text, offset)
        if unicode.is_emoji_extended_pictographic(preceding) {
            return true
        }
        if !text_grapheme_extend(preceding) {
            return false
        }
        offset = start
    }
    return false
}

// text_regional_indicator_count counts the RI run ending immediately before a boundary.
text_regional_indicator_count :: proc(text: string, boundary: int) -> int {
    count := 0
    offset := boundary
    for offset > 0 {
        previous, start := text_previous_rune(text, offset)
        if !unicode.is_regional_indicator(previous) {
            break
        }
        count += 1
        offset = start
    }
    return count
}

// text_grapheme_extend unifies Extend, emoji modifier, and ZWNJ properties.
text_grapheme_extend :: proc(codepoint: rune) -> bool {
    return unicode.is_gcb_extend_class(codepoint) ||
        codepoint == unicode.ZERO_WIDTH_NON_JOINER
}

// text_previous_rune decodes the rune immediately before one known byte boundary.
text_previous_rune :: proc(text: string, boundary: int) -> (rune, int) {
    offset := boundary - 1
    for offset > 0 && (text[offset] & 0xC0) == 0x80 {
        offset -= 1
    }
    codepoint, _ := utf8.decode_rune_in_string(text[offset:boundary])
    return codepoint, offset
}

// text_codepoint_clamp_boundary clamps one byte offset to a UTF-8 boundary.
text_codepoint_clamp_boundary :: proc(text: string, offset: int) -> int {
    result := clamp(offset, 0, len(text))
    for result > 0 && result < len(text) &&
        (text[result] & 0xC0) == 0x80 {
        result -= 1
    }
    return result
}
