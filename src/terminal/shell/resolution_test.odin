#+test
package shell

import "core:testing"

// Parse one successful template for compact resolution fixtures.
test_parse_template :: proc(t: ^testing.T, source: string) -> Command_Template {
    parsed := shell_parse(source)
    testing.expect_value(t, parsed.kind, Shell_Parse_Result_Kind.Success)
    return parsed.template
}

// Verify literal commands resolve directly without interpolation input.
@(test)
shell_resolution_test_literal_command_bypasses_interpolation :: proc(t: ^testing.T) {
    template := test_parse_template(t, "echo 'a b' \"\"")
    resolved := shell_resolve(&template, nil)
    testing.expect_value(t, resolved.kind, Shell_Resolution_Result_Kind.Success)
    testing.expect_value(t, resolved.command.argument_count, 3)
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 0), "echo")
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 1), "a b")
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 2), "")
}

// Verify scalar interpolation remains data inside compound words.
@(test)
shell_resolution_test_scalar_operator_text_is_never_reparsed :: proc(t: ^testing.T) {
    template := test_parse_template(t, "run pre$value-post")
    values := [1]Shell_Interpolation_Value{{element_count = 1}}
    values[0].elements[0] = "a b | next > file"
    resolved := shell_resolve(&template, values[:])
    testing.expect_value(t, resolved.kind, Shell_Resolution_Result_Kind.Success)
    testing.expect_value(t, resolved.command.argument_count, 2)
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 1),
        "prea b | next > file-post")
}

// Verify a whole-word flat collection expands to distinct ordered arguments.
@(test)
shell_resolution_test_whole_word_collection_expands :: proc(t: ^testing.T) {
    template := test_parse_template(t, "run $values tail")
    values := [1]Shell_Interpolation_Value{{element_count = 3}}
    values[0].elements[0] = "one"
    values[0].elements[1] = "two words"
    values[0].elements[2] = "|"
    resolved := shell_resolve(&template, values[:])
    testing.expect_value(t, resolved.kind, Shell_Resolution_Result_Kind.Success)
    testing.expect_value(t, resolved.command.argument_count, 5)
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 1), "one")
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 2),
        "two words")
    testing.expect_value(t, resolved_command_argument_text(&resolved.command, 3), "|")
}

// Verify empty and multi-element collections cannot imply compound expansion.
@(test)
shell_resolution_test_compound_collection_policy_is_explicit :: proc(t: ^testing.T) {
    template := test_parse_template(t, "run pre$values")
    empty := [1]Shell_Interpolation_Value{{}}
    resolved := shell_resolve(&template, empty[:])
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Empty_Collection_In_Compound_Word)

    multiple := [1]Shell_Interpolation_Value{{element_count = 2}}
    multiple[0].elements[0] = "one"
    multiple[0].elements[1] = "two"
    resolved = shell_resolve(&template, multiple[:])
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Collection_In_Compound_Word)
}

// Verify missing, extra, argument-count, and byte pressure fail explicitly.
@(test)
shell_resolution_test_lifecycle_and_capacity_errors :: proc(t: ^testing.T) {
    template := test_parse_template(t, "run $value")
    resolved := shell_resolve(&template, nil)
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Missing_Interpolation)

    literal := test_parse_template(t, "run")
    extra := [1]Shell_Interpolation_Value{{element_count = 1}}
    extra[0].elements[0] = "unused"
    resolved = shell_resolve(&literal, extra[:])
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Extra_Interpolation)

    collection := [1]Shell_Interpolation_Value{
        {element_count = SHELL_INTERPOLATION_ELEMENT_CAPACITY}}
    many_template := test_parse_template(t, "$values $values $values $values $values")
    many := [5]Shell_Interpolation_Value{
        collection[0], collection[0], collection[0], collection[0], collection[0]}
    resolved = shell_resolve(&many_template, many[:])
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Too_Many_Arguments)

    large_template := test_parse_template(t, "$value")
    large_value := [1]Shell_Interpolation_Value{{element_count = 1}}
    backing: [SHELL_RESOLVED_BYTE_CAPACITY + 1]u8
    large_value[0].elements[0] = string(backing[:])
    resolved = shell_resolve(&large_template, large_value[:])
    testing.expect_value(t, resolved.error.kind,
        Shell_Resolution_Error_Kind.Argument_Data_Too_Long)
}
