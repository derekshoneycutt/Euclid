#+test
package content_model

import "core:testing"

// Construct a compact admitted projection with two ordinary edition defaults.
specification_test_generation :: proc(t: ^testing.T) -> ^Content_Generation {
    generation := new(Content_Generation, context.allocator)
    testing.expect_value(t, content_generation_init(generation),
        Content_Generation_Status.Ok)
    testing.expect_value(t, content_generation_begin(generation, 17),
        Content_Generation_Status.Ok)
    specification_test_append(t, generation, "en-US", &generation^.data.locales[0].tag)
    generation^.data.locales[0].is_default = true
    generation^.data.locale_count = 1
    generation^.data.subject_count = 2
    generation^.data.subjects[1][15] = 1
    generation^.data.edition_count = 2
    specification_test_edition(t, generation, 0, {"original", "Original", "en-US"})
    specification_test_edition(t, generation, 1, {"heath", "Heath", "grc"})
    generation^.data.availability_count = 2
    for index in 0..<2 {
        generation^.data.availability[index] = Content_Availability{
            subject_index = u16(index), edition_index = u16(index), is_default = true,
        }
    }
    terminal := Catalog_Record{stable_id = {15 = 1}, node_kind = .Terminal}
    specification_test_append(t, generation, "Terminal", &terminal.display_name)
    testing.expect_value(t, content_generation_append_record(generation, terminal),
        Content_Generation_Status.Ok)
    generation^.data.complete = true
    testing.expect_value(t, content_generation_seal(generation),
        Content_Generation_Status.Ok)
    return generation
}

// Append fixture bytes through the generation's explicit packed-storage owner.
specification_test_append :: proc(
    t: ^testing.T, generation: ^Content_Generation,
    text: string, reference: ^Content_Text_Ref) {
    testing.expect_value(t, content_generation_append_text(
        generation, text, 256, reference), Content_Generation_Status.Ok)
}

// Populate one ordinary edition without bypassing generation text storage.
specification_test_edition :: proc(
    t: ^testing.T, generation: ^Content_Generation, index: int,
    fields: [3]string) {
    edition := &generation^.data.editions[index]
    specification_test_append(t, generation, fields[0], &edition^.id)
    specification_test_append(t, generation, fields[1], &edition^.name)
    specification_test_append(t, generation, fields[2], &edition^.language)
}

// Release the fixture's arena before freeing its stable owner address.
specification_test_destroy :: proc(generation: ^Content_Generation) {
    content_generation_destroy(generation)
    free(generation, context.allocator)
}

// Verify uniform resolution, independent language, owned copies, and revision identity.
@(test)
specification_resolution_revision_and_lifetime :: proc(t: ^testing.T) {
    generation := specification_test_generation(t)
    defer specification_test_destroy(generation)
    first, second, reloaded: Animation_Content_Specification
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {}, 0, nil, &first), Animation_Content_Status.Ok)
    testing.expect_value(t, first.selection_revision, u64(1))
    testing.expect_value(t,
        string(first.edition_id[:first.edition_id_length]), "original")
    testing.expect_value(t, resolve_animation_content_specification(
        generation, generation^.data.subjects[1], 0, &first, &second),
        Animation_Content_Status.Ok)
    testing.expect_value(t, second.selection_revision, u64(2))
    testing.expect_value(t, string(second.application_locale[:5]), "en-US")
    testing.expect_value(t, string(second.edition_text_language[:3]), "grc")
    generation^.generation = 18
    testing.expect_value(t, resolve_animation_content_specification(
        generation, second.animation_identity, 1, &second, &reloaded),
        Animation_Content_Status.Ok)
    testing.expect_value(t, reloaded.selection_revision, second.selection_revision)
    testing.expect_value(t, reloaded.content_generation_identity, u64(18))
    testing.expect_value(t, reloaded.runtime_generation_identity, u64(1))
    testing.expect_value(t, content_generation_reset(generation),
        Content_Generation_Status.Ok)
    testing.expect_value(t,
        string(first.edition_name[:first.edition_name_length]), "Original")
    testing.expect_value(t,
        string(reloaded.edition_name[:reloaded.edition_name_length]), "Heath")
}

// Failed resolution must preserve the destination and expose its exact failure.
@(test)
specification_resolution_explicit_errors :: proc(t: ^testing.T) {
    generation := specification_test_generation(t)
    defer specification_test_destroy(generation)
    output := Animation_Content_Specification{selection_revision = 99}
    baseline := output
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {15 = 2}, 0, nil, &output), Animation_Content_Status.Missing_Default)
    testing.expect_value(t, output, baseline)
    generation^.sealed = false
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {}, 0, nil, &output), Animation_Content_Status.Stale_Generation)
    testing.expect_value(t, output, baseline)
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {}, 0, nil, nil), Animation_Content_Status.Invalid_Output)
    generation^.sealed = true
    generation^.data.editions[0].name.length = 257
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {}, 0, nil, &output), Animation_Content_Status.Missing_Default)
    testing.expect_value(t, output, baseline)
}

// Each fixed text field admits exactly its maximum byte count, never maximum plus one.
@(test)
specification_exact_text_bounds :: proc(t: ^testing.T) {
    generation := specification_test_generation(t)
    defer specification_test_destroy(generation)
    text: [257]u8
    for &byte in text { byte = 'a' }
    generation^.text_bytes = text[:]
    references := [?]^Content_Text_Ref{
        &generation^.data.locales[0].tag,
        &generation^.data.editions[0].id,
        &generation^.data.editions[0].name,
        &generation^.data.editions[0].language,
    }
    limits := [?]u32{35, 64, 256, 35}
    for reference, index in references {
        reference^ = {offset = 0, length = limits[index]}
    }
    output: Animation_Content_Specification
    testing.expect_value(t, resolve_animation_content_specification(
        generation, {}, 0, nil, &output), Animation_Content_Status.Ok)
    baseline := output
    for reference, index in references {
        reference^.length += 1
        testing.expect_value(t, resolve_animation_content_specification(
            generation, {}, 0, nil, &output), Animation_Content_Status.Missing_Default)
        testing.expect_value(t, output, baseline)
        reference^.length = limits[index]
    }
}
