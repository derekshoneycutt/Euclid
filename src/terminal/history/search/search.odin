package termhistsearch

import "core:unicode"
import utf8 "core:unicode/utf8"
import pcre2 "../../../pcre2"
import raw "../../../../libs/pcre2"
import protocol "../../../core/protocol"

// Fill plan-owned query storage and acquire reusable PCRE2 resources.
history_search_compile :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    query: string) -> Search_Error {
    if plan == nil || workspace == nil || plan^.initialized ||
       workspace^.initialized {
        return .Invalid_State
    }
    if len(query) > HISTORY_SEARCH_QUERY_MAX_BYTES {
        return .Capacity
    }
    if !utf8.valid_string(query) {
        return .Invalid_Query
    }
    plan^ = {}
    workspace^ = {}
    failure := history_search_parse(plan, workspace, query)
    if failure != .None {
        history_search_destroy(plan, workspace)
        return failure
    }
    plan^.initialized = true
    workspace^.initialized = true
    return .None
}

// Compile an explicit Julia history regex; only malformed syntax is skipped.
history_search_add_regex :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    pattern: []u8, explicit: bool) -> Search_Error {
    return history_search_add_pattern(plan, workspace, pattern, 0, explicit)
}

// Generate Julia's initialism alternatives and compile the bounded expression.
history_search_add_initialism :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    value: []u8) -> Search_Error {
    pattern: [HISTORY_SEARCH_PATTERN_MAX_BYTES]u8
    pattern_length := 0
    for index := 0; index < len(value); {
        character, width := utf8.decode_rune_in_string(string(value[index:]))
        upper := unicode.to_upper(character)
        prefix := "[\\W_]*?(?:(?:\\b|_+)(?:"
        middle := ")\\w+|\\p{Ll}"
        if index == 0 {
            prefix = "(?:(?<![^\\W_])(?:"
            middle = ")\\w+|(?<=\\p{Ll})"
        }
        if !history_search_append(&pattern, &pattern_length, prefix) ||
           !history_search_append_quoted_rune(&pattern, &pattern_length, character) ||
           !history_search_append(&pattern, &pattern_length, "|") ||
           !history_search_append_quoted_rune(&pattern, &pattern_length, upper) ||
           !history_search_append(&pattern, &pattern_length, middle) ||
           !history_search_append_quoted_rune(&pattern, &pattern_length, upper) ||
           !history_search_append(&pattern, &pattern_length, ")") {
            return .Capacity
        }
        index += width
    }
    return history_search_add_pattern(
        plan, workspace, pattern[:pattern_length], 0, false)
}

// Generate Julia's per-word fuzzy regexes with segment-wide smart case.
history_search_add_fuzzy :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    value: []u8) -> Search_Error {
    sensitive := false
    for index := 0; index < len(value); {
        character, width := utf8.decode_rune_in_string(string(value[index:]))
        sensitive = sensitive || unicode.is_upper(character)
        index += width
    }
    for start := 0; start < len(value); {
        character, width := utf8.decode_rune_in_string(string(value[start:]))
        if unicode.is_space(character) {
            start += width
            continue
        }
        end := start + width
        for end < len(value) {
            character, width = utf8.decode_rune_in_string(string(value[end:]))
            if unicode.is_space(character) {
                break
            }
            end += width
        }
        failure := history_search_add_fuzzy_word(
            plan, workspace, value[start:end], sensitive)
        if failure != .None {
            return failure
        }
        start = end
    }
    return .None
}

// Compile one generated fuzzy word without allocating a growing pattern string.
history_search_add_fuzzy_word :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    word: []u8, case_sensitive: bool) -> Search_Error {
    pattern: [HISTORY_SEARCH_PATTERN_MAX_BYTES]u8
    pattern_length := 0
    for index := 0; index < len(word); {
        character, width := utf8.decode_rune_in_string(string(word[index:]))
        if index > 0 && !history_search_append(
            &pattern, &pattern_length,
            "[^\\s\\\"#%&()*+,\\-\\/:;<=>?@[\\]^`{|}~]*?") {
            return .Capacity
        }
        if !history_search_append_quoted_rune(
            &pattern, &pattern_length, character) {
            return .Capacity
        }
        index += width
    }
    options := u32(0)
    if !case_sensitive {
        options = raw.COMPILE_CASELESS
    }
    return history_search_add_pattern(
        plan, workspace, pattern[:pattern_length], options, false)
}

// Quote a literal code point using PCRE2's \Q...\E syntax.
history_search_append_quoted :: proc(
    buffer: ^[HISTORY_SEARCH_PATTERN_MAX_BYTES]u8,
    length: ^int, value: []u8) -> bool {
    return history_search_append(buffer, length, "\\Q") &&
        history_search_append_bytes(buffer, length, value) &&
        history_search_append(buffer, length, "\\E")
}

// Append one quoted Unicode scalar using its canonical UTF-8 encoding.
history_search_append_quoted_rune :: proc(
    buffer: ^[HISTORY_SEARCH_PATTERN_MAX_BYTES]u8, length: ^int,
    value: rune) -> bool {
    encoded: [4]u8
    codepoint := u32(value)
    if codepoint <= 0x7F {
        encoded[0] = u8(codepoint)
        return history_search_append_quoted(buffer, length, encoded[:1])
    }
    if codepoint <= 0x7FF {
        encoded[0] = u8(0xC0 | (codepoint >> 6))
        encoded[1] = u8(0x80 | (codepoint & 0x3F))
        return history_search_append_quoted(buffer, length, encoded[:2])
    }
    if codepoint <= 0xFFFF {
        encoded[0] = u8(0xE0 | (codepoint >> 12))
        encoded[1] = u8(0x80 | ((codepoint >> 6) & 0x3F))
        encoded[2] = u8(0x80 | (codepoint & 0x3F))
        return history_search_append_quoted(buffer, length, encoded[:3])
    }
    encoded[0] = u8(0xF0 | (codepoint >> 18))
    encoded[1] = u8(0x80 | ((codepoint >> 12) & 0x3F))
    encoded[2] = u8(0x80 | ((codepoint >> 6) & 0x3F))
    encoded[3] = u8(0x80 | (codepoint & 0x3F))
    return history_search_append_quoted(buffer, length, encoded[:4])
}

// Split escaped semicolons and preserve every non-separator backslash.
history_search_parse :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    query: string) -> Search_Error {
    segment: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8
    segment_length := 0
    escaped := false
    for query_index := 0; query_index < len(query); query_index += 1 {
        byte := query[query_index]
        if escaped {
            if byte == ';' {
                segment[segment_length - 1] = ';'
            } else {
                segment[segment_length] = byte
                segment_length += 1
            }
            escaped = false
        } else if byte == ';' {
            failure := history_search_add_segment(
                plan, workspace, segment[:segment_length])
            if failure != .None {
                return failure
            }
            segment_length = 0
        } else {
            segment[segment_length] = byte
            segment_length += 1
            escaped = byte == '\\'
        }
    }
    if segment_length > 0 {
        return history_search_add_segment(plan, workspace, segment[:segment_length])
    }
    return .None
}

// Trim and dispatch one parser segment according to Julia's prefix precedence.
history_search_add_segment :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    raw_segment: []u8) -> Search_Error {
    start, end := history_search_trim(raw_segment, true, false)
    if start == end {
        return .None
    }
    if plan^.parsed_condition_count == HISTORY_SEARCH_CONDITION_MAX {
        return .Capacity
    }
    plan^.parsed_condition_count += 1
    segment := raw_segment[start:end]
    prefix := segment[0]
    if prefix == '!' || prefix == '=' || prefix == '`' ||
       prefix == '/' || prefix == '~' {
        return history_search_add_prefixed(plan, workspace, segment)
    }
    return history_search_add_words_and_mode(plan, workspace, segment)
}

// Apply Julia's exact operator-specific trimming and malformed-regex exception.
history_search_add_prefixed :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    segment: []u8) -> Search_Error {
    kind := segment[0]
    value_start, value_end := 0, len(segment) - 1
    if kind == '`' || kind == '~' {
        value_start, value_end = history_search_trim(segment[1:], true, true)
    } else if !history_search_all_space(segment[1:]) {
        value_start, value_end = history_search_trim(segment[1:], kind != '/', true)
    }
    value := segment[1 + value_start:1 + value_end]
    if len(value) == 0 {
        return .None
    }
    if kind == '/' {
        return history_search_add_regex(plan, workspace, value, true)
    }
    if kind == '`' {
        return history_search_add_initialism(plan, workspace, value)
    }
    if kind == '~' {
        return history_search_add_fuzzy(plan, workspace, value)
    }
    condition_kind := Condition_Kind.Negative if kind == '!' else Condition_Kind.Exact
    return history_search_add_literal(plan, condition_kind, value)
}

// Recognize a mode prefix only when `>` ends the first whitespace-delimited word.
history_search_add_words_and_mode :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    segment: []u8) -> Search_Error {
    start, end := 0, len(segment)
    if segment[0] == '\\' && (len(segment) == 1 || segment[1] != '\\') {
        start = 1
    } else if separator := history_search_mode_separator(segment); separator >= 0 {
        mode_bytes := segment[:separator]
        mode_start, mode_end := history_search_trim(mode_bytes, false, false)
        mode_name := history_search_lower_ascii_mode(mode_bytes[mode_start:mode_end])
        mode, known := search_mode_from_name(mode_name)
        failure := history_search_add_mode(
            plan, mode, known, mode_bytes[mode_start:mode_end])
        if failure != .None {
            return failure
        }
        start = separator + 1
    }
    word_segment := segment[start:end]
    word_start, word_end := history_search_trim(word_segment, true, true)
    words := word_segment[word_start:word_end]
    if len(words) == 0 {
        return .None
    }
    return history_search_add_word_segment(plan, workspace, words)
}

// Return the byte index of the first qualifying `>` or -1.
history_search_mode_separator :: proc(segment: []u8) -> int {
    greater := -1
    first_space := len(segment)
    for index := 0; index < len(segment); {
        character, width := utf8.decode_rune_in_string(string(segment[index:]))
        if character == '>' && greater < 0 {
            greater = index
        }
        if unicode.is_space(character) {
            first_space = index
            break
        }
        index += width
    }
    if greater >= 0 && greater == first_space-1 {
        return greater
    }
    return -1
}

// Split an ordinary segment on Unicode whitespace and apply segment-wide smart case.
history_search_add_word_segment :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    words: []u8) -> Search_Error {
    case_sensitive := false
    for index := 0; index < len(words); {
        character, width := utf8.decode_rune_in_string(string(words[index:]))
        case_sensitive = case_sensitive || unicode.is_upper(character)
        index += width
    }
    for start := 0; start < len(words); {
        character, width := utf8.decode_rune_in_string(string(words[start:]))
        if unicode.is_space(character) {
            start += width
            continue
        }
        end := start + width
        for end < len(words) {
            character, width = utf8.decode_rune_in_string(string(words[end:]))
            if unicode.is_space(character) {
                break
            }
            end += width
        }
        failure := history_search_add_word(
            plan, workspace, words[start:end], case_sensitive)
        if failure != .None {
            return failure
        }
        start = end
    }
    return .None
}

// Add one case-sensitive literal or smart-case regex word.
history_search_add_word :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    word: []u8, case_sensitive: bool) -> Search_Error {
    if case_sensitive {
        return history_search_add_literal(plan, .Exact, word)
    }
    pattern: [HISTORY_SEARCH_PATTERN_MAX_BYTES]u8
    pattern_length := 0
    if !history_search_append(&pattern, &pattern_length, "\\Q") ||
       !history_search_append_bytes(&pattern, &pattern_length, word) ||
       !history_search_append(&pattern, &pattern_length, "\\E") {
        return .Capacity
    }
    return history_search_add_pattern(
        plan, workspace, pattern[:pattern_length], raw.COMPILE_CASELESS, false)
}

// Store a bounded literal condition in plan-owned query bytes.
history_search_add_literal :: proc(
    plan: ^Search_Plan, kind: Condition_Kind, value: []u8) -> Search_Error {
    if !history_search_has_condition_room(plan) ||
       plan^.storage_length + len(value) > len(plan^.storage) {
        return .Capacity
    }
    offset := plan^.storage_length
    copy(plan^.storage[offset:], value)
    plan^.storage_length += len(value)
    plan^.conditions[plan^.condition_count] = {
        kind = kind,
        text_offset = offset,
        text_length = len(value),
    }
    plan^.condition_count += 1
    plan^.effective_condition_count += 1
    return .None
}

// Add an OR-composed mode condition while retaining unknown Julia mode names.
history_search_add_mode :: proc(
    plan: ^Search_Plan, mode: protocol.Evaluation_Mode,
    known: bool, name: []u8) -> Search_Error {
    if !history_search_has_condition_room(plan) ||
       plan^.storage_length + len(name) > len(plan^.storage) {
        return .Capacity
    }
    offset := plan^.storage_length
    copy(plan^.storage[offset:], name)
    plan^.storage_length += len(name)
    plan^.conditions[plan^.condition_count] = {
        kind = .Mode,
        text_offset = offset,
        text_length = len(name),
        mode = mode,
        mode_known = known,
    }
    plan^.condition_count += 1
    plan^.effective_condition_count += 1
    plan^.mode_count += 1
    return .None
}

// Compile one generated or explicit PCRE2 expression into the reusable workspace.
history_search_add_pattern :: proc(
    plan: ^Search_Plan, workspace: ^Search_Workspace,
    pattern: []u8, options: u32, explicit: bool) -> Search_Error {
    if !history_search_has_condition_room(plan) ||
       workspace^.pattern_count >= HISTORY_SEARCH_CONDITION_MAX {
        return .Capacity
    }
    if !explicit &&
       plan^.generated_pattern_bytes + len(pattern) >
            HISTORY_SEARCH_PATTERN_MAX_BYTES {
        return .Capacity
    }
    index := workspace^.pattern_count
    result := pcre2.compile(
        &workspace^.patterns[index], pattern,
        pcre2.DEFAULT_COMPILE_OPTIONS | options)
    if result.status == .Invalid_Pattern && explicit {
        plan^.skipped_regex_count += 1
        return history_search_add_skipped_regex(plan, pattern, result)
    }
    if result.status != .Success {
        if result.status == .Out_Of_Memory {
            return .Out_Of_Memory
        }
        return .Pattern_Engine
    }
    workspace^.pattern_count += 1
    plan^.pattern_count += 1
    if !explicit {
        plan^.generated_pattern_bytes += len(pattern)
    }
    plan^.conditions[plan^.condition_count] = {
        kind = .Regex,
        regex_index = index,
    }
    plan^.condition_count += 1
    plan^.effective_condition_count += 1
    return .None
}

// Retain the exact malformed explicit term and its typed PCRE2 diagnostic.
history_search_add_skipped_regex :: proc(
    plan: ^Search_Plan, pattern: []u8, result: pcre2.Compile_Result) -> Search_Error {
    if !history_search_has_condition_room(plan) ||
       plan^.storage_length + len(pattern) > len(plan^.storage) {
        return .Capacity
    }
    offset := plan^.storage_length
    copy(plan^.storage[offset:], pattern)
    plan^.storage_length += len(pattern)
    plan^.conditions[plan^.condition_count] = {
        kind = .Skipped_Regex,
        text_offset = offset,
        text_length = len(pattern),
        compile_error_code = result.error_code,
        compile_error_offset = result.error_offset,
    }
    plan^.condition_count += 1
    return .None
}

// Check the common fixed condition bound before adding any condition.
history_search_has_condition_room :: proc(plan: ^Search_Plan) -> bool {
    return plan^.condition_count < HISTORY_SEARCH_CONDITION_MAX
}

// Return trimmed byte bounds using Unicode whitespace rather than ASCII-only tests.
history_search_trim :: proc(
    value: []u8, trim_start, trim_end: bool) -> (int, int) {
    start, end := 0, len(value)
    if trim_start {
        for start < end {
            character, width := utf8.decode_rune_in_string(string(value[start:end]))
            if !unicode.is_space(character) {
                break
            }
            start += width
        }
    }
    if trim_end {
        for end > start {
            previous := history_search_previous_rune(value[:end])
            if !unicode.is_space(previous.rune) {
                break
            }
            end = previous.start
        }
    }
    return start, end
}

// Find one preceding UTF-8 rune at a known valid string boundary.
history_search_previous_rune :: proc(value: []u8) -> struct {rune: rune, start: int} {
    start := len(value) - 1
    for start > 0 && (value[start] & 0xC0) == 0x80 {
        start -= 1
    }
    character, _ := utf8.decode_rune_in_string(string(value[start:]))
    return {character, start}
}

// Determine whether a value contains only Unicode whitespace.
history_search_all_space :: proc(value: []u8) -> bool {
    if len(value) == 0 {
        return true
    }
    for index := 0; index < len(value); {
        character, width := utf8.decode_rune_in_string(string(value[index:]))
        if !unicode.is_space(character) {
            return false
        }
        index += width
    }
    return true
}

// Lowercase mode labels without locale-dependent or Julia-runtime calls.
history_search_lower_ascii_mode :: proc(value: []u8) -> string {
    for index := 0; index < len(value); {
        character, width := utf8.decode_rune_in_string(string(value[index:]))
        if character < 0x80 {
            value[index] = u8(unicode.to_lower(character))
        }
        index += width
    }
    return string(value)
}

// Append text to one fixed pattern buffer without implicit growth.
history_search_append :: proc(
    buffer: ^[HISTORY_SEARCH_PATTERN_MAX_BYTES]u8,
    length: ^int, value: string) -> bool {
    return history_search_append_bytes(buffer, length, transmute([]u8)value)
}

// Append bytes to one fixed pattern buffer without exceeding its explicit bound.
history_search_append_bytes :: proc(
    buffer: ^[HISTORY_SEARCH_PATTERN_MAX_BYTES]u8,
    length: ^int, value: []u8) -> bool {
    if length^ + len(value) > len(buffer^) {
        return false
    }
    copy(buffer^[length^:], value)
    length^ += len(value)
    return true
}
