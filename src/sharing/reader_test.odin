#+test
package sharing

import "core:testing"
import "core:mem"

SHARING_TEST_LIMITS :: Sharing_Limits{
    document_bytes = 16 * 1024,
    record_bytes = 512,
    record_count = 64,
    collection_count = 8,
    entries_per_collection = 8,
    entries_per_document = 32,
    note_bytes = 128,
    name_bytes = 64,
    scope_depth = 3,
    diagnostic_count = 64,
}

Sharing_Test_Result :: struct {
    document: Staged_Document,
    rule: Sharing_Rule,
    line: int,
    backing: []u8,
}

Sharing_Test_Feed_Result :: struct {
    rule: Sharing_Rule,
    line: int,
}

Large_Block_Buffers :: struct {
    backing: []u8,
    input: []u8,
    line: []u8,
    scratch: []u8,
    block: []u8,
}

Large_Block_Finish_Context :: struct {
    reader: ^Reader,
    document: ^Staged_Document,
    input: []u8,
    arena: ^mem.Arena,
    delimiter: bool,
    prefix_length: int,
    staged_baseline: int,
    payload_size: int,
}

// Parse one source with bounded owner allocations and the requested feed chunk size.
sharing_test_parse :: proc(
    source: string, chunk_size: int,
    limits := SHARING_TEST_LIMITS) -> Sharing_Test_Result {
    document: Staged_Document
    backing, backing_error := make([]u8, 128 * 1024, context.allocator)
    if backing_error != nil {
        return {
            rule = .Staged_Capacity_Exceeded,
        }
    }
    arena: mem.Arena
    mem.arena_init(&arena, backing)
    allocator := mem.arena_allocator(&arena)
    if rule := staged_document_init(&document, allocator, limits);
       rule != .None {
        return {
            document = document,
            rule = rule,
            backing = backing,
        }
    }
    line, line_error := make([]u8, limits.record_bytes, context.allocator)
    scratch, scratch_error := make(
        []u8, 4 * limits.record_bytes, context.allocator)
    block, block_error := make(
        []u8, max(limits.note_bytes, 1), context.allocator)
    if line_error != nil || scratch_error != nil || block_error != nil {
        return {
            document = document,
            rule = .Staged_Capacity_Exceeded,
            backing = backing,
        }
    }
    defer delete(line)
    defer delete(scratch)
    defer delete(block)
    reader: Reader
    if rule := reader_init(
        &reader, {line, scratch, block}, &document, limits); rule != .None {
        return {
            document = document,
            rule = rule,
            backing = backing,
        }
    }
    feed := sharing_test_feed_loop(&reader, source, chunk_size, &document)
    if feed.rule != .None {
        return {
            document = document,
            rule = feed.rule,
            line = feed.line,
            backing = backing,
        }
    }
    return {
        document = document,
        backing = backing,
    }
}

// Feed chunks until the staging reader succeeds or reports a stable failure.
sharing_test_feed_loop :: proc(
    reader: ^Reader, source: string, chunk_size: int,
    document: ^Staged_Document) -> Sharing_Test_Feed_Result {
    bytes := transmute([]u8)source
    offset := 0
    for offset < len(bytes) || !reader^.finished {
        size := min(chunk_size, len(bytes) - offset)
        consumed, rule := reader_feed(
            reader, bytes[offset:offset + size], offset + size == len(bytes))
        offset += consumed
        if rule != .None {
            line_number := 0
            if document^.diagnostic_count > 0 {
                line_number = document^.diagnostics[0].line
            }
            return {
                rule = rule,
                line = line_number,
            }
        }
        if consumed == 0 && offset < len(bytes) {
            return {
                rule = .Invalid_Record,
            }
        }
    }
    return {
    }
}

// A valid collection and its note stage identically under different feed boundaries.
@(test)
sharing_reader_accepts_delimited_notes_in_single_byte_chunks :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"Study\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_end\":\"::end::\"}\n" +
        "Hello\n::end::\n" +
        "{\"end\":\"e\"}\n{\"end\":\"c\"}\n"
    one := sharing_test_parse(source, 1)
    defer delete(one.backing)
    whole := sharing_test_parse(source, len(source))
    defer delete(whole.backing)
    testing.expect_value(t, one.rule, Sharing_Rule.None)
    testing.expect_value(t, whole.rule, Sharing_Rule.None)
    testing.expect(t, one.document.valid && whole.document.valid)
    testing.expect_value(t, one.document.collection_count, 1)
    testing.expect_value(t, one.document.entry_total, 1)
    testing.expect_value(t, one.document.collections[0].entries[0].note, "Hello")
    testing.expect_value(t, one.document.collections[0].entries[0].note,
        whole.document.collections[0].entries[0].note)
}

// Repeated animation references invalidate only their owning collection.
@(test)
sharing_reader_rejects_duplicate_animation :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e1\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\"}\n" +
        "{\"type\":\"entry\",\"id\":\"e2\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\"}\n" +
        "{\"end\":\"c\"}\n" +
        "{\"type\":\"collection\",\"id\":\"c2\",\"name\":\"Other\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e3\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440001\"}\n" +
        "{\"end\":\"c2\"}\n"
    result := sharing_test_parse(source, len(source))
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.None)
    testing.expect(t, result.document.valid)
    testing.expect(t, !result.document.collections[0].importable)
    testing.expect_value(
        t, result.document.collections[0].reason, Collection_Reason.Duplicate_Animation)
    testing.expect_value(t, result.document.collection_count, 2)
    testing.expect(t, result.document.collections[1].importable)
}

// Nested animation entries fail instead of being flattened.
@(test)
sharing_reader_rejects_unsupported_hierarchy :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[\"entry_hierarchy\"]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e1\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e2\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440001\"}\n"
    result := sharing_test_parse(source, 17)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Unsupported_Hierarchy)
    diagnostic := result.document.diagnostics[0]
    testing.expect_value(t,
        string(diagnostic.detail[:diagnostic.detail_length]), "entry_hierarchy")
}

// Header capability names are checked before collection records are accepted.
@(test)
sharing_reader_reports_unknown_requirement :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[\"x.future.capability\"]}\n"
    result := sharing_test_parse(source, 7)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Unknown_Requirement)
    detail_length := result.document.diagnostics[0].detail_length
    testing.expect_value(t,
        string(result.document.diagnostics[0].detail[:detail_length]),
        "x.future.capability")
}

// Required unknown content reports its type when no failure scope is declared.
@(test)
sharing_reader_reports_unknown_content_name :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"future.geometry.construct\"}\n"
    result := sharing_test_parse(source, 9)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Unsupported_Content)
    diagnostic := result.document.diagnostics[0]
    testing.expect_value(
        t,
        string(diagnostic.detail[:diagnostic.detail_length]),
        "future.geometry.construct")
}

// The notes schema requires a supported MIME type and an actual Boolean flag.
@(test)
sharing_reader_rejects_invalid_note_mime :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"application/unknown\",\"block_bytes\":0}\n\n" +
        "{\"end\":\"e\"}\n{\"end\":\"c\"}\n"
    result := sharing_test_parse(source, len(source))
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.None)
    testing.expect(t, result.document.valid)
    testing.expect_value(
        t, result.document.collections[0].reason, Collection_Reason.Invalid_Notes)
}

// Required document-local identities cannot be empty even on self-contained records.
@(test)
sharing_reader_rejects_empty_collection_id :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"\",\"name\":\"C\"}\n"
    result := sharing_test_parse(source, 5)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Invalid_Scope)
}

// Collections cannot carry animation references intended for entry records.
@(test)
sharing_reader_rejects_collection_animation_reference :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\"," +
        "\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\"}\n"
    result := sharing_test_parse(source, 7)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Invalid_Collection)
}

// Delimiter and counted blocks with equal bytes produce the same staged note.
@(test)
sharing_reader_stages_equivalent_block_forms :: proc(t: ^testing.T) {
    delimiter := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_end\":\"::end::\"}\n" +
        "Hello\n\n::end::\n{\"end\":\"e\"}\n{\"end\":\"c\"}\n"
    counted := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":6}\n" +
        "Hello\n\n{\"end\":\"e\"}\n{\"end\":\"c\"}\n"
    text := sharing_test_parse(delimiter, 7)
    defer delete(text.backing)
    bytes := sharing_test_parse(counted, 11)
    defer delete(bytes.backing)
    testing.expect_value(t, text.rule, Sharing_Rule.None)
    testing.expect_value(t, bytes.rule, Sharing_Rule.None)
    testing.expect_value(t, text.document.collections[0].entries[0].note, "Hello\n")
    testing.expect_value(
        t,
        text.document.collections[0].entries[0].note,
        bytes.document.collections[0].entries[0].note)
}

// Counted notes reject either framing length mismatch at the descriptor line.
@(test)
sharing_reader_reports_counted_note_length_mismatch :: proc(t: ^testing.T) {
    sources := [?]string{
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":4}\n" +
        "Hello\n{\"end\":\"e\"}\n{\"end\":\"c\"}\n",
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":6}\n" +
        "Hello\n{\"end\":\"e\"}\n{\"end\":\"c\"}\n",
    }
    for source in sources {
        result := sharing_test_parse(source, 5)
        defer delete(result.backing)
        testing.expect_value(t, result.rule, Sharing_Rule.Invalid_Block_Framing_Lf)
        testing.expect_value(t, result.line, 4)
    }
}

// Unknown optional scopes discard their complete subtree without promoting entries.
@(test)
sharing_reader_skips_optional_scope_subtree :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"future\",\"id\":\"x\",\"optional\":true,\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"hidden\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\"}\n" +
        "{\"type\":\"future.required\",\"failure_scope\":\"document\"}\n" +
        "{\"end\":\"x\"}\n" +
        "{\"type\":\"entry\",\"id\":\"visible\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440001\"}\n" +
        "{\"end\":\"c\"}\n"
    result := sharing_test_parse(source, 13)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.None)
    testing.expect_value(t, result.document.collections[0].entry_count, 1)
    testing.expect_value(t, result.document.skipped_optional, 1)
}

// Calendar and zone validation accepts RFC 3339 forms and rejects invalid dates.
@(test)
sharing_reader_validates_rfc3339_timestamps :: proc(t: ^testing.T) {
    valid: []string = {
        "2024-02-29T18:35:10Z",
        "2024-02-29t18:35:10.123+05:30",
        "2023-12-31T23:59:60-00:00",
    }
    invalid: []string = {
        "2023-02-29T18:35:10Z",
        "2024-13-01T18:35:10Z",
        "2024-01-01T24:00:00Z",
        "2024-01-01T18:35:10.",
        "2024-01-01T18:35:10+24:00",
    }
    for value in valid {
        testing.expect(t, sharing_timestamp_valid(value))
    }
    for value in invalid {
        testing.expect(t, !sharing_timestamp_valid(value))
    }
}

// Diagnostic storage stays fixed-capacity and counts every omitted diagnostic.
@(test)
sharing_reader_bounds_diagnostic_storage :: proc(t: ^testing.T) {
    backing, backing_error := make([]u8, 128 * 1024, context.allocator)
    if backing_error != nil {
        testing.expect(t, false)
        return
    }
    defer delete(backing)
    arena: mem.Arena
    mem.arena_init(&arena, backing)
    allocator := mem.arena_allocator(&arena)
    document: Staged_Document
    testing.expect_value(
        t,
        staged_document_init(
            &document, allocator, SHARING_TEST_LIMITS),
        Sharing_Rule.None)
    for line in 0..<65 {
        staged_diagnostic_add(&document, line + 1, .Invalid_Record)
    }
    testing.expect_value(t, document.diagnostic_count, 64)
    testing.expect_value(t, document.diagnostic_overflow, 1)
}

// A staging arena too small for its fixed arrays cannot create an importable result.
@(test)
sharing_reader_rejects_small_staging_allocator :: proc(t: ^testing.T) {
    backing: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, backing[:])
    document: Staged_Document
    rule := staged_document_init(
        &document, mem.arena_allocator(&arena), SHARING_TEST_LIMITS)
    testing.expect_value(t, rule, Sharing_Rule.Staged_Capacity_Exceeded)
    testing.expect(t, !document.valid)
    testing.expect_value(t, document.collection_count, 0)
}

// Entry-count overflow is rejected before the bounded staging array is written.
@(test)
sharing_reader_enforces_entries_per_document :: proc(t: ^testing.T) {
    limits := SHARING_TEST_LIMITS
    limits.entries_per_collection = 2
    limits.entries_per_document = 1
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e1\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\"}\n" +
        "{\"type\":\"entry\",\"id\":\"e2\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440001\"}\n"
    result := sharing_test_parse(source, 19, limits)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.Too_Many_Entries)
    testing.expect(t, !result.document.valid)
    testing.expect(t, !result.document.collections[0].importable)
}

// Collection count, names, notes, record size, and document size use caller limits.
@(test)
sharing_reader_enforces_collection_count_and_name_limits :: proc(t: ^testing.T) {
    collection_limits := SHARING_TEST_LIMITS
    collection_limits.collection_count = 1
    collections := sharing_test_parse(
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c1\",\"name\":\"C1\"}\n" +
        "{\"type\":\"collection\",\"id\":\"c2\",\"name\":\"C2\"}\n",
        32,
        collection_limits)
    defer delete(collections.backing)
    testing.expect_value(t, collections.rule, Sharing_Rule.Too_Many_Collections)
    name_limits := SHARING_TEST_LIMITS
    name_limits.name_bytes = 3
    name := sharing_test_parse(
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"Long\"}\n",
        32,
        name_limits)
    defer delete(name.backing)
    testing.expect_value(t, name.rule, Sharing_Rule.None)
    testing.expect(t, !name.document.collections[0].importable)
    testing.expect_value(
        t, name.document.collections[0].reason, Collection_Reason.Invalid_Name)
}

// Configured note limits reject oversized counted and delimiter blocks locally.
@(test)
sharing_reader_enforces_configured_note_limits :: proc(t: ^testing.T) {
    note_limits := SHARING_TEST_LIMITS
    note_limits.note_bytes = 4
    note := sharing_test_parse(
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":5}\nHello\n" +
        "{\"end\":\"e\"}\n{\"end\":\"c\"}\n",
        32,
        note_limits)
    defer delete(note.backing)
    testing.expect_value(t, note.rule, Sharing_Rule.None)
    testing.expect(t, note.document.valid)
    testing.expect_value(
        t, note.document.collections[0].reason, Collection_Reason.Note_Too_Large)
    delimiter_note := sharing_test_parse(
        "{\"format\":\"euclid-collections\",\"framing_version\":1,\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_end\":\"::end::\"}\n" +
        "Hello\n::end::\n{\"end\":\"e\"}\n{\"end\":\"c\"}\n",
        17,
        note_limits)
    defer delete(delimiter_note.backing)
    testing.expect_value(t, delimiter_note.rule, Sharing_Rule.None)
    testing.expect(t, delimiter_note.document.valid)
    testing.expect_value(
        t,
        delimiter_note.document.collections[0].reason,
        Collection_Reason.Note_Too_Large)
}

// Record and document byte ceilings reject the first byte beyond their bounds.
@(test)
sharing_reader_enforces_byte_limits :: proc(t: ^testing.T) {
    record_limits := SHARING_TEST_LIMITS
    record_limits.record_bytes = 16
    record := sharing_test_parse(
        "{\"format\":\"euclid-collections\"}\n", 1, record_limits)
    defer delete(record.backing)
    testing.expect_value(t, record.rule, Sharing_Rule.Record_Too_Large)
    document_limits := SHARING_TEST_LIMITS
    document_limits.document_bytes = 24
    document := sharing_test_parse(
        "{\"format\":\"euclid-collections\"}\n", 1, document_limits)
    defer delete(document.backing)
    testing.expect_value(t, document.rule, Sharing_Rule.Document_Too_Large)
}

// Notes preserve JSON-looking text and support empty and trailing-LF payloads.
@(test)
sharing_reader_preserves_literal_note_contents :: proc(t: ^testing.T) {
    source := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n" +
        "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\",\"begin\":true}\n" +
        "{\"type\":\"entry\",\"id\":\"e1\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_end\":\"::end::\"}\n" +
        "{\"end\":\"e2\"}\n{\"type\":\"collection\"}\n::end::\n" +
        "{\"end\":\"e1\"}\n" +
        "{\"type\":\"entry\",\"id\":\"e2\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440001\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":0}\n\n" +
        "{\"end\":\"e2\"}\n" +
        "{\"type\":\"entry\",\"id\":\"e3\",\"animation_id\":\"550e8400-e29b-41d4-a716-446655440002\",\"begin\":true}\n" +
        "{\"type\":\"notes\",\"mime\":\"text/plain\",\"block_bytes\":3}\nx\n\n\n" +
        "{\"end\":\"e3\"}\n{\"end\":\"c\"}\n"
    result := sharing_test_parse(source, 23)
    defer delete(result.backing)
    testing.expect_value(t, result.rule, Sharing_Rule.None)
    entries := result.document.collections[0].entries
    testing.expect_value(
        t, entries[0].note, "{\"end\":\"e2\"}\n{\"type\":\"collection\"}")
    testing.expect(t, entries[1].has_note && entries[1].note == "")
    testing.expect_value(t, entries[2].note, "x\n\n")
}

// Skipped multi-megabyte optional blocks do not grow the staging arena.
@(test)
sharing_reader_skips_large_optional_blocks_without_staging_growth :: proc(t: ^testing.T) {
    sharing_test_large_optional_block_case(t, false)
    sharing_test_large_optional_block_case(t, true)
}

// Stream one large skipped block and verify bounded staging allocations.
sharing_test_large_optional_block_case :: proc(
    t: ^testing.T, delimiter: bool) {
    PAYLOAD_SIZE :: 3 * 1024 * 1024
    limits := SHARING_TEST_LIMITS
    limits.document_bytes = 4 * 1024 * 1024
    buffers, allocated := sharing_test_large_optional_buffers(PAYLOAD_SIZE, limits)
    if !allocated {
        testing.expect(t, false)
        return
    }
    defer delete(buffers.backing)
    defer delete(buffers.input)
    defer delete(buffers.line)
    defer delete(buffers.scratch)
    defer delete(buffers.block)
    arena: mem.Arena
    mem.arena_init(&arena, buffers.backing)
    document: Staged_Document
    rule := staged_document_init(&document, mem.arena_allocator(&arena), limits)
    testing.expect_value(t, rule, Sharing_Rule.None)
    reader: Reader
    rule = reader_init(&reader,
        {buffers.line, buffers.scratch, buffers.block}, &document, limits)
    testing.expect_value(t, rule, Sharing_Rule.None)
    prefix_length := sharing_test_large_optional_prefix(
        t, buffers.input, &reader, delimiter)
    finish: Large_Block_Finish_Context = {
        reader = &reader,
        document = &document,
        input = buffers.input,
        arena = &arena,
        delimiter = delimiter,
        prefix_length = prefix_length,
        staged_baseline = arena.offset,
        payload_size = PAYLOAD_SIZE,
    }
    sharing_test_large_optional_finish(t, finish)
}

// Consume the optional payload and verify staging storage remains unchanged.
sharing_test_large_optional_finish :: proc(
    t: ^testing.T, finish: Large_Block_Finish_Context) {
    offset := sharing_test_large_optional_payload(
        finish.input, finish.prefix_length,
        finish.payload_size, finish.delimiter)
    consumed, failure := reader_feed(
        finish.reader, finish.input[finish.prefix_length:offset], false)
    testing.expect_value(t, failure, Sharing_Rule.None)
    testing.expect_value(t, consumed, offset-finish.prefix_length)
    testing.expect_value(t, finish.arena^.offset, finish.staged_baseline)
    collection := "{\"type\":\"collection\",\"id\":\"c\",\"name\":\"C\"}\n"
    copy(finish.input[:len(collection)], transmute([]u8)collection)
    consumed, failure = reader_feed(
        finish.reader, finish.input[:len(collection)], true)
    testing.expect_value(t, failure, Sharing_Rule.None)
    testing.expect_value(t, consumed, len(collection))
    testing.expect(t, finish.document^.valid)
}

// Allocate independent caller-owned buffers for one large-block test.
sharing_test_large_optional_buffers :: proc(
    payload_size: int, limits: Sharing_Limits) -> (Large_Block_Buffers, bool) {
    backing, backing_error := make([]u8, 128 * 1024, context.allocator)
    input, input_error := make([]u8, payload_size + 1024, context.allocator)
    line, line_error := make([]u8, limits.record_bytes, context.allocator)
    scratch, scratch_error := make(
        []u8, 4 * limits.record_bytes, context.allocator)
    block, block_error := make([]u8, limits.note_bytes, context.allocator)
    if backing_error != nil || input_error != nil || line_error != nil ||
        scratch_error != nil || block_error != nil {
        delete(backing)
        delete(input)
        delete(line)
        delete(scratch)
        delete(block)
        return {}, false
    }
    return {
        backing = backing,
        input = input,
        line = line,
        scratch = scratch,
        block = block,
    }, true
}

// Publish the schema header and unsupported optional-block descriptor.
sharing_test_large_optional_prefix :: proc(
    t: ^testing.T, input: []u8, reader: ^Reader, delimiter: bool) -> int {
    header := "{\"format\":\"euclid-collections\",\"framing_version\":1," +
        "\"schema_version\":1,\"requires\":[]}\n"
    descriptor := "{\"type\":\"future\",\"optional\":true," +
        "\"block_bytes\":3145728}\n"
    if delimiter {
        descriptor = "{\"type\":\"future\",\"optional\":true," +
            "\"block_end\":\"::end::\"}\n"
    }
    offset := len(header)
    copy(input[:offset], transmute([]u8)header)
    copy(input[offset:offset + len(descriptor)], transmute([]u8)descriptor)
    offset += len(descriptor)
    consumed, failure := reader_feed(reader, input[:offset], false)
    testing.expect_value(t, failure, Sharing_Rule.None)
    testing.expect_value(t, consumed, offset)
    return offset
}

// Fill a counted or delimiter block, feed it, and verify exact consumption.
sharing_test_large_optional_payload :: proc(
    input: []u8, offset, payload_size: int, delimiter: bool) -> int {
    cursor := offset
    if delimiter {
        for index in 0..<payload_size {
            if index%2 == 0 {
                input[cursor + index] = 'x'
            } else {
                input[cursor + index] = '\n'
            }
        }
        cursor += payload_size
        copy(input[cursor:cursor + 8], "::end::\n")
        cursor += 8
    } else {
        for index in 0..<payload_size {
            input[cursor + index] = 'x'
        }
        cursor += payload_size
        input[cursor] = '\n'
        cursor += 1
    }
    return cursor
}
