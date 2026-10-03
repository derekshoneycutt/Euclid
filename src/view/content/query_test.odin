package content

import "core:testing"

// Verify terms, phrases, exclusions, and final-term typeahead compile deterministically.
@(test)
search_query_compiles_friendly_grammar :: proc(t: ^testing.T) {
    compiled := search_query_compile(`-circle line "is perpendicular to"`)
    testing.expect_value(t, compiled.status, Search_Query_Parse_Status.Success)
    testing.expect_value(t, search_compiled_text(&compiled),
        `"line" AND "is perpendicular to" NOT "circle"`)

    prefix := search_query_compile("right ang")
    testing.expect_value(t, search_compiled_text(&prefix), `"right" AND "ang"*`)
}

// Verify punctuation and operator words remain inert quoted token content.
@(test)
search_query_neutralizes_fts_and_sql_syntax :: proc(t: ^testing.T) {
    fixtures := []string{
        "name:circle", "circle OR line", "circle NEAR(line)",
        "circle*", "Robert'); DROP TABLE search_documents;--",
    }
    for fixture in fixtures {
        compiled := search_query_compile(fixture)
        testing.expect_value(t, compiled.status, Search_Query_Parse_Status.Success)
        text := search_compiled_text(&compiled)
        testing.expect(t, len(text) >= 3)
        testing.expect_value(t, text[0], u8('"'))
    }
    compiled := search_query_compile("name:circle")
    testing.expect_value(t, search_compiled_text(&compiled), `"name circle"*`)
    wildcard := search_query_compile("circle*")
    testing.expect_value(t, search_compiled_text(&wildcard), `"circle"*`)
}

// Verify malformed encoding, controls, incomplete syntax, and capacity fail explicitly.
@(test)
search_query_rejects_invalid_and_saturated_input :: proc(t: ^testing.T) {
    malformed_bytes := []u8{0xc3, 0x28}
    malformed := transmute(string)malformed_bytes
    testing.expect_value(t, search_query_compile(malformed).status,
        Search_Query_Parse_Status.Invalid_Utf8)
    testing.expect_value(t, search_query_compile("line\x00circle").status,
        Search_Query_Parse_Status.Unsupported_Control)
    testing.expect_value(t, search_query_compile(`"open phrase`).status,
        Search_Query_Parse_Status.Unmatched_Quote)
    testing.expect_value(t, search_query_compile("-").status,
        Search_Query_Parse_Status.Bare_Negation)
    testing.expect_value(t, search_query_compile("-circle").status,
        Search_Query_Parse_Status.No_Positive_Item)

    oversized: [SEARCH_QUERY_BYTE_CAPACITY + 1]u8
    for &value in oversized {
       value = 'a'
    }
    testing.expect_value(t, search_query_compile(string(oversized[:])).status,
        Search_Query_Parse_Status.Source_Too_Long)
}

// Verify only a final positive bare item receives compiler-owned prefix syntax.
@(test)
search_query_prefix_requires_final_positive_bare_term :: proc(t: ^testing.T) {
    phrase := search_query_compile(`line "right angle"`)
    testing.expect_value(t, search_compiled_text(&phrase),
        `"line" AND "right angle"`)
    exclusion := search_query_compile("line -circle")
    testing.expect_value(t, search_compiled_text(&exclusion),
        `"line" NOT "circle"`)
}