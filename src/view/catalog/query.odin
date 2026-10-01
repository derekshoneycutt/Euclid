package catalog

import "core:unicode/utf8"

// Semantic form of one allowlisted friendly-query item.
Search_Query_Item_Kind :: enum u8 {
    Positive_Term,
    Positive_Phrase,
    Negative_Term,
    Negative_Phrase,
}

// Stable admission and syntax outcomes independent of SQLite diagnostics.
Search_Query_Parse_Status :: enum u8 {
    Success,
    Empty,
    Source_Too_Long,
    Invalid_Utf8,
    Unsupported_Control,
    Too_Many_Items,
    Item_Too_Long,
    Empty_Item,
    Bare_Negation,
    Unmatched_Quote,
    No_Positive_Item,
    Match_Too_Long,
}

// One normalized item whose text owns no FTS5 grammar punctuation.
Search_Query_Item :: struct {
    kind: Search_Query_Item_Kind,
    text_length: u16,
    text: [SEARCH_QUERY_ITEM_BYTE_CAPACITY]u8,
}

// Allocation-free typed representation of one admitted user query.
Search_Parsed_Query :: struct {
    item_count: u8,
    items: [SEARCH_QUERY_ITEM_CAPACITY]Search_Query_Item,
}

// Allocation-free compiler result; `bytes` contains only allowlisted FTS5 syntax.
Search_Compiled_Query :: struct {
    status: Search_Query_Parse_Status,
    byte_count: u16,
    bytes: [SEARCH_MATCH_BYTE_CAPACITY]u8,
    parsed: Search_Parsed_Query,
}

// Report whether an ASCII byte contributes searchable token text.
search_ascii_is_token_byte :: proc(value: u8) -> bool {
    return value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' ||
        value >= '0' && value <= '9'
}

// Append one byte to a bounded item, reporting saturation without partial overflow.
search_item_append_byte :: proc(item: ^Search_Query_Item, value: u8) -> bool {
    count := int(item.text_length)
    if count >= len(item.text) {
        return false
    }
    item.text[count] = value
    item.text_length += 1
    return true
}

// Add one canonical separator between tokenizer-visible runs.
search_item_append_separator :: proc(item: ^Search_Query_Item) -> bool {
    count := int(item.text_length)
    if count == 0 || item.text[count - 1] == ' ' {
        return true
    }
    return search_item_append_byte(item, ' ')
}

// Normalize one source span so punctuation cannot acquire FTS5 authority.
search_normalize_item :: proc(source: string, item: ^Search_Query_Item) -> bool {
    offset := 0
    for offset < len(source) {
        _, width := utf8.decode_rune(source[offset:])
        if width <= 0 {
            return false
        }
        first := source[offset]
        if first >= 0x80 || search_ascii_is_token_byte(first) {
            for byte_index in 0..<width {
                if !search_item_append_byte(item, source[offset + byte_index]) {
                    return false
                }
            }
        } else if !search_item_append_separator(item) {
            return false
        }
        offset += width
    }
    if item.text_length > 0 && item.text[item.text_length - 1] == ' ' {
        item.text_length -= 1
    }
    return item.text_length > 0
}

// Return whether one byte is accepted as friendly-query whitespace.
search_query_is_space :: proc(value: u8) -> bool {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r'
}

// Reject control bytes that are neither supported whitespace nor valid UTF-8 text.
search_query_has_unsupported_control :: proc(source: string) -> bool {
    for value in transmute([]u8)source {
        if value < 0x20 && !search_query_is_space(value) || value == 0x7f {
            return true
        }
    }
    return false
}

// Advance past friendly-query whitespace without interpreting token content.
search_query_skip_space :: proc(source: string, cursor: ^int) {
    for cursor^ < len(source) && search_query_is_space(source[cursor^]) {
        cursor^ += 1
    }
}

// Report whether one parsed item contributes the required positive expression.
search_query_item_is_positive :: proc(kind: Search_Query_Item_Kind) -> bool {
    return kind == .Positive_Term || kind == .Positive_Phrase
}

// Append one parsed item after normalizing its bounded source payload.
search_query_add_item :: proc(
    parsed: ^Search_Parsed_Query, kind: Search_Query_Item_Kind,
    source: string) -> Search_Query_Parse_Status {
    if int(parsed.item_count) >= len(parsed.items) {
        return .Too_Many_Items
    }
    item := &parsed.items[parsed.item_count]
    item.kind = kind
    if !search_normalize_item(source, item) {
        if item.text_length == SEARCH_QUERY_ITEM_BYTE_CAPACITY {
            return .Item_Too_Long
        }
        return .Empty_Item
    }
    parsed.item_count += 1
    return .Success
}

// Scan one quoted or bare query item and report unmatched quotes.
search_query_scan_item :: proc(
    source: string, cursor: ^int, quoted: bool) -> Search_Query_Parse_Status {
    if quoted {
        for cursor^ < len(source) && source[cursor^] != '"' {
           cursor^ += 1
        }
        if cursor^ >= len(source) {
           return .Unmatched_Quote
        }
    } else {
        for cursor^ < len(source) && !search_query_is_space(source[cursor^]) {
            cursor^ += 1
        }
    }
    return .Success
}

// Parse one quoted or bare item and advance the caller-owned cursor.
search_query_parse_item :: proc(
    source: string, cursor: ^int,
    parsed: ^Search_Parsed_Query) -> Search_Query_Parse_Status {
    negative := false
    if source[cursor^] == '-' {
        negative = true
        cursor^ += 1
        if cursor^ >= len(source) || search_query_is_space(source[cursor^]) {
            return .Bare_Negation
        }
    }
    quoted := source[cursor^] == '"'
    if quoted {
        cursor^ += 1
    }
    start := cursor^
    scan_status := search_query_scan_item(source, cursor, quoted)
    if scan_status != .Success {
        return scan_status
    }
    kind: Search_Query_Item_Kind = negative ? .Negative_Term : .Positive_Term
    if quoted {
        kind = negative ? .Negative_Phrase : .Positive_Phrase
    }
    status := search_query_add_item(parsed, kind, source[start:cursor^])
    if quoted {
        cursor^ += 1
    }
    return status
}

// Parse bounded UTF-8 friendly syntax into typed positive and negative items.
search_query_parse :: proc(
    source: string, parsed: ^Search_Parsed_Query) -> Search_Query_Parse_Status {
    parsed^ = {}
    if len(source) > SEARCH_QUERY_BYTE_CAPACITY {
        return .Source_Too_Long
    }
    if !utf8.valid_string(source) {
        return .Invalid_Utf8
    }
    if search_query_has_unsupported_control(source) {
        return .Unsupported_Control
    }
    cursor := 0
    positive_count := 0
    for cursor < len(source) {
        search_query_skip_space(source, &cursor)
        if cursor >= len(source) {
            break
        }
        status := search_query_parse_item(source, &cursor, parsed)
        if status != .Success {
            return status
        }
        kind := parsed.items[parsed.item_count - 1].kind
        if search_query_item_is_positive(kind) {
            positive_count += 1
        }
    }
    if parsed.item_count == 0 {
        return .Empty
    }
    if positive_count == 0 {
        return .No_Positive_Item
    }
    return .Success
}

// Append fixed compiler-owned syntax to the MATCH output.
search_match_append :: proc(output: ^Search_Compiled_Query, value: string) -> bool {
    count := int(output.byte_count)
    if len(value) > len(output.bytes) - count {
        return false
    }
    copy(output.bytes[count:], transmute([]u8)value)
    output.byte_count += u16(len(value))
    return true
}

// Serialize one normalized item as an FTS5 quoted string and optional prefix.
search_compile_item :: proc(
    output: ^Search_Compiled_Query, item: ^Search_Query_Item,
    prefix: bool) -> bool {
    if !search_match_append(output, "\"") {
        return false
    }
    text := string(item.text[:item.text_length])
    if !search_match_append(output, text) || !search_match_append(output, "\"") {
        return false
    }
    return !prefix || search_match_append(output, "*")
}

// Compile admitted typed items into the only FTS5 expression shape used at runtime.
search_parsed_query_compile :: proc(
    parsed: Search_Parsed_Query) -> Search_Compiled_Query {
    result := Search_Compiled_Query{status = .Success, parsed = parsed}
    positive_written := 0
    for &item, index in result.parsed.items[:result.parsed.item_count] {
        if item.kind == .Negative_Term || item.kind == .Negative_Phrase {
            continue
        }
        if positive_written > 0 && !search_match_append(&result, " AND ") {
            result.status = .Match_Too_Long
            return result
        }
        prefix := index == int(result.parsed.item_count) - 1 &&
            item.kind == .Positive_Term
        if !search_compile_item(&result, &item, prefix) {
            result.status = .Match_Too_Long
            return result
        }
        positive_written += 1
    }
    for &item in result.parsed.items[:result.parsed.item_count] {
        if item.kind != .Negative_Term && item.kind != .Negative_Phrase {
            continue
        }
        if !search_match_append(&result, " NOT ") ||
           !search_compile_item(&result, &item, false) {
            result.status = .Match_Too_Long
            return result
        }
    }
    return result
}

// Parse and compile one friendly query without exposing raw FTS5 syntax.
search_query_compile :: proc(source: string) -> Search_Compiled_Query {
    parsed: Search_Parsed_Query
    status := search_query_parse(source, &parsed)
    if status != .Success {
        return {status = status, parsed = parsed}
    }
    return search_parsed_query_compile(parsed)
}

// Return the initialized prefix of one successful compiled expression.
search_compiled_text :: proc(compiled: ^Search_Compiled_Query) -> string {
    return string(compiled.bytes[:compiled.byte_count])
}