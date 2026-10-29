#+test
package termhistsearch

import pcre2 "../../../pcre2"
import protocol "../../../core/protocol"

import "core:os"
import "core:testing"

// Julia-compatible conditions preserve smart case, separators, and mode OR.
@(test)
history_search_matches_julia_condition_rules :: proc(t: ^testing.T) {
    history_search_expect_match(t, "foo BAR", "foo BAR", .Normal, true)
    history_search_expect_match(t, "foo BAR", "FOO BAR", .Normal, false)
    history_search_expect_match(t, "foo; BAR", "FOO BAR", .Normal, true)
    history_search_expect_match(t, "\\=literal", "=literal", .Normal, true)
    history_search_expect_match(t, "word\\;part", "WORD;PART", .Normal, true)
    history_search_expect_match(t,
        "=exact text", "prefix exact text suffix", .Normal, true)
    history_search_expect_match(t, "!exclude;julia>", "entry", .Normal, true)
    history_search_expect_match(t, "help>;shell>", "command", .Shell, true)
    history_search_expect_match(t, "unknown>", "command", .Normal, false)
    history_search_expect_match(t, "unknown>;shell>", "command", .Shell, true)
}

// Explicit malformed patterns alone skip; generated-pattern failures remain errors.
@(test)
history_search_skips_only_invalid_explicit_regex :: proc(t: ^testing.T) {
    history_search_expect_match(t, "/[", "anything", .Normal, true)
    history_search_expect_match(t, "needle;/[", "needle here", .Normal, true)
    history_search_expect_match(t, "needle;/[", "other", .Normal, false)
    plan: Search_Plan
    workspace: Search_Workspace
    query := "needle;/["
    failure := history_search_compile(&plan, &workspace, query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure == .None {
        testing.expect_value(t, plan.skipped_regex_count, 1)
        testing.expect_value(t, plan.effective_condition_count, 1)
        testing.expect_value(t, plan.conditions[1].kind, Condition_Kind.Skipped_Regex)
        testing.expect(t, plan.conditions[1].compile_error_code != 0)
        history_search_destroy(&plan, &workspace)
    }
}

// Native PCRE2 retains Julia regex semantics and reuses compiled programs.
@(test)
history_search_uses_native_pcre2_without_recompilation :: proc(t: ^testing.T) {
    plan: Search_Plan
    workspace: Search_Workspace
    query := "/^(a)\\1$"
    failure := history_search_compile(&plan, &workspace, query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    testing.expect_value(t, plan.pattern_count, 1)
    for _ in 0 ..< 8 {
        result := history_search_matches(&plan, &workspace, "aa", .Normal)
        testing.expect(t, result.matched)
        testing.expect_value(t, result.error, Search_Error.None)
    }
    ranges: [2]Search_Range
    for _ in 0 ..< 4 {
        range_result := history_search_match_ranges(
            &plan, &workspace, "aa", ranges[:])
        testing.expect_value(t, range_result.error, Search_Error.None)
        testing.expect_value(t, range_result.count, 1)
    }
    testing.expect_value(t, workspace.pattern_count, 1)
}

// Fuzzy and initialism patterns follow the upstream generated-regex rules.
@(test)
history_search_matches_fuzzy_initialism_and_unicode :: proc(t: ^testing.T) {
    history_search_expect_match(t, "`fb", "foo_bar", .Normal, true)
    history_search_expect_match(t, "`fb", "fooBar", .Normal, true)
    history_search_expect_match(t, "`fb", "afoo bar", .Normal, false)
    history_search_expect_match(t, "`λf", "λx fy", .Normal, true)
    history_search_expect_match(t, "~cs", "test case", .Normal, true)
    history_search_expect_match(t, "~CS", "test case", .Normal, false)
    history_search_expect_match(t, "~λx", "λabcx", .Normal, true)
}

// Positive ranges preserve UTF-8 bytes, duplicates, overlaps, and zero-width progress.
@(test)
history_search_collects_exact_and_regex_ranges :: proc(t: ^testing.T) {
    adjacent := [?]Search_Range{{0, 9}}
    overlapping := [?]Search_Range{{0, 4}, {2, 4}}
    duplicate := [?]Search_Range{{0, 4}, {0, 4}}
    zero_width := [?]Search_Range{{0, 1}}
    lookbehind := [?]Search_Range{{1, 2}}
    history_search_expect_ranges(t, "=αβ;=γδ", "αβ γδ", adjacent[:])
    history_search_expect_ranges(t, "=st;=test", "test", overlapping[:])
    history_search_expect_ranges(t, "=test;=test", "test",
        duplicate[:])
    history_search_expect_ranges(t, "/(?=a)|a", "a", zero_width[:])
    history_search_expect_ranges(t, "/(?<=a)b", "ab", lookbehind[:])
}

// Query, condition, and generated-pattern limits remain typed failures.
@(test)
history_search_reports_bounded_queries :: proc(t: ^testing.T) {
    oversized: [HISTORY_SEARCH_QUERY_MAX_BYTES + 1]u8
    plan: Search_Plan
    workspace: Search_Workspace
    failure := history_search_compile(
        &plan, &workspace, string(oversized[:]))
    testing.expect_value(t, failure, Search_Error.Capacity)

    many_conditions: [129]u8
    for index in 0 ..< len(many_conditions) {
        many_conditions[index] = ';' if index % 2 == 1 else 'a'
    }
    failure = history_search_compile(
        &plan, &workspace, string(many_conditions[:]))
    testing.expect_value(t, failure, Search_Error.Capacity)

    large_fuzzy: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8
    large_fuzzy[0] = '~'
    for index in 1 ..< len(large_fuzzy) {
        large_fuzzy[index] = 'a'
    }
    failure = history_search_compile(
        &plan, &workspace, string(large_fuzzy[:]))
    testing.expect_value(t, failure, Search_Error.Capacity)
}

// Range overflow fails without publishing a partial count.
@(test)
history_search_reports_range_capacity :: proc(t: ^testing.T) {
    plan: Search_Plan
    workspace: Search_Workspace
    literal_query := "=x"
    failure := history_search_compile(
        &plan, &workspace, literal_query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    repeated_source: [300]u8
    for &byte in repeated_source {
        byte = 'x'
    }
    bounded_ranges: [HISTORY_SEARCH_RANGE_MAX]Search_Range
    range_result := history_search_match_ranges(
        &plan, &workspace, string(repeated_source[:]), bounded_ranges[:])
    testing.expect_value(t, range_result.error, Search_Error.Capacity)
    testing.expect_value(t, range_result.count, 0)
}

// Cancellation remains a typed failure rather than an ordinary no-match.
@(test)
history_search_reports_cancelled_match :: proc(t: ^testing.T) {
    plan: Search_Plan
    workspace: Search_Workspace
    query := "/^source$"
    failure := history_search_compile(
        &plan, &workspace, query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    token: pcre2.Cancel_Token
    pcre2.cancel_token_init(&token)
    pcre2.cancel_token_request(&token)
    result := history_search_matches(
        &plan, &workspace, "source", .Normal, &token)
    testing.expect_value(t, result.error, Search_Error.Cancelled)
    testing.expect(t, !result.matched)
}

// Reject malformed UTF-8 before parsing query scalars or publishing byte ranges.
@(test)
history_search_rejects_malformed_utf8 :: proc(t: ^testing.T) {
    invalid_query: [1]u8
    invalid_query[0] = 0xFF
    plan: Search_Plan
    workspace: Search_Workspace
    failure := history_search_compile(
        &plan, &workspace, string(invalid_query[:]))
    testing.expect_value(t, failure, Search_Error.Invalid_Query)

    failure = history_search_compile(&plan, &workspace, "=x")
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    result := history_search_matches(
        &plan, &workspace, string(invalid_query[:]), .Normal)
    testing.expect_value(t, result.error, Search_Error.Invalid_Source)
    ranges: [1]Search_Range
    range_result := history_search_match_ranges(
        &plan, &workspace, string(invalid_query[:]), ranges[:])
    testing.expect_value(t, range_result.error, Search_Error.Invalid_Source)
}

// Compare native decisions and positive byte ranges with the installed Julia oracle.
@(test)
history_search_matches_julia_oracle_corpus :: proc(t: ^testing.T) {
    path_buffer: [4096]u8
    path := os.get_env(path_buffer[:], "EUCLID_HISTORY_SEARCH_ORACLE")
    if len(path) == 0 {
        testing.expect(t, false)
        return
    }
    data, read_error := os.read_entire_file_from_path(path, context.allocator)
    if read_error != nil {
        testing.expect(t, false)
        return
    }
    defer delete(data, context.allocator)
    history_search_check_oracle_corpus(t, string(data))
}

// Validate the corpus identity and compare every nonempty TSV record.
history_search_check_oracle_corpus :: proc(t: ^testing.T, data: string) {
    header_found := false
    row_count := 0
    line_start := 0
    for line_end := 0; line_end <= len(data); line_end += 1 {
        if line_end < len(data) && data[line_end] != '\n' {
            continue
        }
        line := string(data[line_start:line_end])
        line_start = line_end + 1
        if len(line) == 0 {
            continue
        }
        if line[0] == '#' {
            header_found = history_search_contains(line, "Julia REPL.History version=") &&
                history_search_contains(line, "source_sha256=")
            continue
        }
        fields, field_count := history_search_oracle_fields(line)
        if field_count != 6 || fields[0] != "R" {
            testing.expect(t, false)
            return
        }
        if !history_search_check_oracle_row(t, fields) {
            return
        }
        row_count += 1
    }
    testing.expect(t, header_found)
    testing.expect(t, row_count >= 20)
}

// Parse one compact TSV oracle row and compare both native search outputs.
history_search_check_oracle_row :: proc(
    t: ^testing.T, fields: [6]string) -> bool {
    query_storage: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8
    source_storage: [4096]u8
    query_length, query_ok := history_search_decode_hex(fields[1], query_storage[:])
    source_length, source_ok := history_search_decode_hex(fields[3], source_storage[:])
    mode_index, mode_ok := history_search_parse_decimal(fields[2])
    if !query_ok || !source_ok || !mode_ok || fields[4] != "0" && fields[4] != "1" {
        testing.expect(t, false)
        return false
    }
    mode, mode_known := history_search_oracle_mode(mode_index)
    if !mode_known {
        testing.expect(t, false)
        return false
    }
    query := string(query_storage[:query_length])
    source := string(source_storage[:source_length])
    return history_search_check_oracle_outputs(t, query, source, mode, fields)
}

// Compare native candidate and range results for one decoded oracle record.
history_search_check_oracle_outputs :: proc(
    t: ^testing.T, query, source: string,
    mode: protocol.Evaluation_Mode, fields: [6]string) -> bool {
    plan: Search_Plan
    workspace: Search_Workspace
    failure := history_search_compile(&plan, &workspace, query)
    if failure != .None {
        testing.expect_value(t, failure, Search_Error.None)
        return false
    }
    defer history_search_destroy(&plan, &workspace)
    result := history_search_matches(&plan, &workspace, source, mode)
    if result.error != .None {
        testing.expect_value(t, result.error, Search_Error.None)
        return false
    }
    if result.matched != (fields[4] == "1") {
        testing.expect_value(t, result.matched, fields[4] == "1")
        return false
    }
    actual_ranges: [HISTORY_SEARCH_RANGE_MAX]Search_Range
    range_result := history_search_match_ranges(
        &plan, &workspace, source, actual_ranges[:])
    if range_result.error != .None {
        testing.expect_value(t, range_result.error, Search_Error.None)
        return false
    }
    return history_search_compare_oracle_ranges(
        t, fields[5], actual_ranges[:range_result.count])
}

// Compare native ranges with compact start-end values from Julia's matchregions.
history_search_compare_oracle_ranges :: proc(
    t: ^testing.T, encoded: string, actual: []Search_Range) -> bool {
    expected: [HISTORY_SEARCH_RANGE_MAX]Search_Range
    expected_count := 0
    start := 0
    for index := 0; index <= len(encoded); index += 1 {
        if index < len(encoded) && encoded[index] != ',' {
            continue
        }
        if index > start {
            range, valid := history_search_parse_oracle_range(encoded[start:index])
            if !valid || expected_count == HISTORY_SEARCH_RANGE_MAX {
                testing.expect(t, false)
                return false
            }
            expected[expected_count] = range
            expected_count += 1
        }
        start = index + 1
    }
    testing.expect_value(t, len(actual), expected_count)
    if len(actual) != expected_count {
        return false
    }
    for range, index in actual {
        testing.expect_value(t, range, expected[index])
    }
    return true
}

// Decode one start-end byte range without slicing past malformed delimiters.
history_search_parse_oracle_range :: proc(encoded: string) -> (Search_Range, bool) {
    separator := 0
    for separator < len(encoded) && encoded[separator] != '-' {
        separator += 1
    }
    if separator == len(encoded) {
        return {}, false
    }
    first, first_ok := history_search_parse_decimal(encoded[:separator])
    last, last_ok := history_search_parse_decimal(encoded[separator + 1:])
    return {first, last}, first_ok && last_ok
}

// Split one TSV row while preserving its final empty range field.
history_search_oracle_fields :: proc(line: string) -> ([6]string, int) {
    fields: [6]string
    field_count := 0
    field_start := 0
    for index := 0; index <= len(line); index += 1 {
        if index < len(line) && line[index] != '\t' {
            continue
        }
        if field_count == len(fields) {
            return fields, field_count + 1
        }
        fields[field_count] = line[field_start:index]
        field_count += 1
        field_start = index + 1
    }
    return fields, field_count
}

// Decode an ASCII hexadecimal field into a bounded byte slice.
history_search_decode_hex :: proc(value: string, output: []u8) -> (int, bool) {
    if len(value) % 2 != 0 || len(value) / 2 > len(output) {
        return 0, false
    }
    for index := 0; index < len(value); index += 2 {
        high, high_ok := history_search_hex_value(value[index])
        low, low_ok := history_search_hex_value(value[index + 1])
        if !high_ok || !low_ok {
            return 0, false
        }
        output[index / 2] = u8(high << 4 | low)
    }
    return len(value) / 2, true
}

// Convert one ASCII hexadecimal digit into a nibble.
history_search_hex_value :: proc(value: u8) -> (u8, bool) {
    if value >= '0' && value <= '9' {
        return value - '0', true
    }
    if value >= 'a' && value <= 'f' {
        return value - 'a' + 10, true
    }
    if value >= 'A' && value <= 'F' {
        return value - 'A' + 10, true
    }
    return 0, false
}

// Parse a nonnegative decimal field with explicit overflow detection.
history_search_parse_decimal :: proc(value: string) -> (int, bool) {
    if len(value) == 0 {
        return 0, false
    }
    result := 0
    for digit in value {
        if digit < '0' || digit > '9' {
            return 0, false
        }
        if result > (max(int) - int(digit - '0')) / 10 {
            return 0, false
        }
        result = result * 10 + int(digit - '0')
    }
    return result, true
}

// Map Julia's four recorded mode values to Euclid's explicit evaluation modes.
history_search_oracle_mode :: proc(
    index: int) -> (protocol.Evaluation_Mode, bool) {
    switch index {
    case 0:
        return .Normal, true
    case 1:
        return .Help, true
    case 2:
        return .Pkg, true
    case 3:
        return .Shell, true
    }
    return .Normal, false
}

// Compile one query and compare candidate decisions and ranges with a fixed oracle row.
history_search_expect_match :: proc(
    t: ^testing.T, query, source: string,
    mode: protocol.Evaluation_Mode, expected: bool) {
    plan: Search_Plan
    workspace: Search_Workspace
    failure := history_search_compile(&plan, &workspace, query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    result := history_search_matches(&plan, &workspace, source, mode)
    testing.expect_value(t, result.error, Search_Error.None)
    testing.expect_value(t, result.matched, expected)
}

// Verify the exact UTF-8 byte ranges generated by one positive query.
history_search_expect_ranges :: proc(
    t: ^testing.T, query, source: string, expected: []Search_Range) {
    plan: Search_Plan
    workspace: Search_Workspace
    failure := history_search_compile(&plan, &workspace, query)
    testing.expect_value(t, failure, Search_Error.None)
    if failure != .None {
        return
    }
    defer history_search_destroy(&plan, &workspace)
    actual: [HISTORY_SEARCH_RANGE_MAX]Search_Range
    result := history_search_match_ranges(&plan, &workspace, source, actual[:])
    testing.expect_value(t, result.error, Search_Error.None)
    testing.expect_value(t, result.count, len(expected))
    for item, index in expected {
        if index < result.count {
            testing.expect_value(t, actual[index], item)
        }
    }
}
