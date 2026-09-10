#+test
package shell

import "core:testing"

// Return one parsed part's owned text for compact grammar assertions.
test_part_text :: proc(
    template: ^Command_Template, word_index, part_index: int) -> string {
    word := &template.words[word_index]
    part := &template.parts[word.first_part + part_index]
    return command_template_part_text(template, part)
}

// Verify every exposed index and span in a successful template is bounded.
test_template_is_structurally_valid :: proc(template: ^Command_Template) -> bool {
    if template.source_count < 0 || template.source_count > SHELL_SOURCE_BYTE_CAPACITY ||
       template.decoded_count < 0 ||
       template.decoded_count > SHELL_DECODED_BYTE_CAPACITY ||
       template.word_count <= 0 || template.word_count > SHELL_WORD_CAPACITY ||
       template.part_count < 0 || template.part_count > SHELL_PART_CAPACITY ||
       template.interpolation_count < 0 ||
       template.interpolation_count > SHELL_INTERPOLATION_CAPACITY {
        return false
    }
    expected_first_part := 0
    for word in template.words[:template.word_count] {
        if word.first_part != expected_first_part || word.part_count < 0 ||
           word.first_part + word.part_count > template.part_count ||
           word.source_span.start < 0 ||
           word.source_span.end < word.source_span.start ||
           word.source_span.end > template.source_count {
            return false
        }
        expected_first_part += word.part_count
    }
    if expected_first_part != template.part_count {
        return false
    }
    for part in template.parts[:template.part_count] {
        if part.source_span.start < 0 ||
           part.source_span.end < part.source_span.start ||
           part.source_span.end > template.source_count ||
           part.text_start < 0 || part.text_end < part.text_start ||
           part.text_end > template.decoded_count {
            return false
        }
    }
    return true
}

// Verify whitespace, empty words, quotes, escapes, and Unicode literal decoding.
@(test)
shell_test_literals_quotes_and_escapes :: proc(t: ^testing.T) {
    source := "  echo alpha 'three $x' \"\" one\\ two " +
        "\"\\$x \\\"q\\\" \\\\ \\z\" 東京  "
    result := shell_parse(source)
    testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Success)
    template := &result.template
    testing.expect_value(t, template.word_count, 7)
    testing.expect_value(t, test_part_text(template, 0, 0), "echo")
    testing.expect_value(t, test_part_text(template, 1, 0), "alpha")
    testing.expect_value(t, test_part_text(template, 2, 0), "three $x")
    testing.expect_value(t, template.words[3].part_count, 0)
    testing.expect_value(t, test_part_text(template, 4, 0), "one two")
    testing.expect_value(t, test_part_text(template, 5, 0), "$x \"q\" \\ \\z")
    testing.expect_value(t, test_part_text(template, 6, 0), "東京")
}

// Verify interpolation leaves retain kind, owned text, adjacency, and source spans.
@(test)
shell_test_interpolation_parts_and_spans :: proc(t: ^testing.T) {
    source := "cmd pre$name-post \"$(f(\"x)\", (1 + 2)))\""
    result := shell_parse(source)
    testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Success)
    template := &result.template
    testing.expect_value(t, template.word_count, 3)
    testing.expect_value(t, template.interpolation_count, 2)
    testing.expect_value(t, template.words[1].part_count, 3)
    testing.expect_value(t, template.parts[2].kind,
        Command_Part_Kind.Interpolation_Identifier)
    testing.expect_value(t, test_part_text(template, 1, 1), "name")
    testing.expect_value(t, template.parts[4].kind,
        Command_Part_Kind.Interpolation_Expression)
    testing.expect_value(t, test_part_text(template, 2, 0), "f(\"x)\", (1 + 2))")
    span := template.parts[4].source_span
    testing.expect_value(t, source[span.start:span.end], "$(f(\"x)\", (1 + 2)))")
}

// Verify each reserved unquoted operator fails at its exact source location.
@(test)
shell_test_reserved_operators_are_rejected :: proc(t: ^testing.T) {
    sources := [8]string{
        "echo | value", "echo < value", "echo > value", "echo >> value",
        "echo & value", "echo && value", "echo || value", "echo ; value",
    }
    for source in sources {
        result := shell_parse(source)
        testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Error)
        testing.expect_value(t, result.error.kind,
            Shell_Parse_Error_Kind.Reserved_Operator)
        testing.expect_value(t,
            source[result.error.source_span.start:result.error.source_span.end],
            source[5:6])
    }
}

// Verify reserved bytes are ordinary data when quoted or escaped.
@(test)
shell_test_reserved_operators_can_be_literal_data :: proc(t: ^testing.T) {
    result := shell_parse("echo '|' \"< > && ;\" \\&")
    testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Success)
    template := &result.template
    testing.expect_value(t, test_part_text(template, 1, 0), "|")
    testing.expect_value(t, test_part_text(template, 2, 0), "< > && ;")
    testing.expect_value(t, test_part_text(template, 3, 0), "&")
}

// Verify malformed quotes, escapes, and interpolation fail without partial success.
@(test)
shell_test_malformed_input_is_specific :: proc(t: ^testing.T) {
    fixtures := [5]struct {
        source: string,
        expected: Shell_Parse_Error_Kind,
    }{
        {"'open", .Unterminated_Single_Quote},
        {"\"open", .Unterminated_Double_Quote},
        {"tail\\", .Trailing_Escape},
        {"echo $", .Invalid_Interpolation},
        {"echo $(f(1)", .Unterminated_Interpolation},
    }
    for fixture in fixtures {
        result := shell_parse(fixture.source)
        testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Error)
        testing.expect_value(t, result.error.kind, fixture.expected)
    }
}

// Verify invalid UTF-8, mismatched delimiters, and nesting pressure fail explicitly.
@(test)
shell_test_interpolation_structural_failures_are_bounded :: proc(t: ^testing.T) {
    invalid_utf8 := [1]u8{0xff}
    result := shell_parse(string(invalid_utf8[:]))
    testing.expect_value(t, result.error.kind, Shell_Parse_Error_Kind.Invalid_Utf8)

    result = shell_parse("echo $([)]")
    testing.expect_value(t, result.error.kind,
        Shell_Parse_Error_Kind.Mismatched_Interpolation_Delimiter)

    nested: [SHELL_SOURCE_BYTE_CAPACITY]u8
    copy(nested[:], "$(")
    byte_count := 2
    for _ in 0..<SHELL_INTERPOLATION_DEPTH_CAPACITY {
        nested[byte_count] = '('
        byte_count += 1
    }
    result = shell_parse(string(nested[:byte_count]))
    testing.expect_value(t, result.error.kind,
        Shell_Parse_Error_Kind.Interpolation_Too_Deep)
}

// Verify empty input and every configured structural limit terminate explicitly.
@(test)
shell_test_empty_and_capacity_limits :: proc(t: ^testing.T) {
    testing.expect_value(t,
        shell_parse("  \t\r\n ").kind, Shell_Parse_Result_Kind.Empty)

    oversized: [SHELL_SOURCE_BYTE_CAPACITY + 1]u8
    for &byte in oversized { byte = 'a' }
    result := shell_parse(string(oversized[:]))
    testing.expect_value(t, result.kind, Shell_Parse_Result_Kind.Error)
    testing.expect_value(t, result.error.kind, Shell_Parse_Error_Kind.Source_Too_Long)

    words: [SHELL_SOURCE_BYTE_CAPACITY]u8
    word_byte_count := 0
    for _ in 0..=SHELL_WORD_CAPACITY {
        words[word_byte_count] = 'x'
        words[word_byte_count + 1] = ' '
        word_byte_count += 2
    }
    result = shell_parse(string(words[:word_byte_count]))
    testing.expect_value(t, result.error.kind, Shell_Parse_Error_Kind.Too_Many_Words)

    interpolations: [SHELL_SOURCE_BYTE_CAPACITY]u8
    copy(interpolations[:], "cmd")
    interpolation_byte_count := 3
    for _ in 0..=SHELL_INTERPOLATION_CAPACITY {
        copy(interpolations[interpolation_byte_count:], "$x")
        interpolation_byte_count += 2
    }
    result = shell_parse(string(interpolations[:interpolation_byte_count]))
    testing.expect_value(t, result.error.kind,
        Shell_Parse_Error_Kind.Too_Many_Interpolations)
}

// Sweep deterministic arbitrary byte strings and validate every successful template.
@(test)
shell_test_arbitrary_inputs_preserve_template_invariants :: proc(t: ^testing.T) {
    alphabet := [18]u8{
        'a', 'Z', '0', ' ', '\t', '\\', '\'', '"', '$', '(', ')', '[', ']',
        '{', '}', '|', ';', 0xff,
    }
    state := u32(0x6d2b79f5)
    input: [96]u8
    for case_index in 0..<1024 {
        state = state * 1664525 + 1013904223
        byte_count := int(state % u32(len(input) + 1))
        for index in 0..<byte_count {
            state = state * 1664525 + 1013904223
            input[index] = alphabet[int(state % u32(len(alphabet)))]
        }
        result := shell_parse(string(input[:byte_count]))
        if result.kind == .Success {
            testing.expect(t, test_template_is_structurally_valid(&result.template))
        } else {
            testing.expect(t, result.kind == .Empty || result.kind == .Error)
        }
        _ = case_index
    }
}
