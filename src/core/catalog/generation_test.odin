#+test
package catalog_model

import "core:encoding/uuid"
import "core:testing"
import storage_pkg "../storage"

// Return a distinct nonzero catalogue identity for generation fixtures.
catalog_generation_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Build a valid small generation with optional child records for lifecycle tests.
catalog_generation_test_build :: proc(
    t: ^testing.T, generation: ^Catalog_Generation, identity: u64,
    include_children: bool) -> bool {
    testing.expect_value(t, catalog_generation_begin(generation, identity),
        Catalog_Generation_Status.Ok)
    root_id := catalog_generation_test_id(1)
    name_ref: Catalog_Text_Ref
    path_ref: Catalog_Text_Ref
    testing.expect_value(t, catalog_generation_append_text(
        generation, "Root", CATALOG_NAME_BYTE_CAPACITY, &name_ref),
        Catalog_Generation_Status.Ok)
    testing.expect_value(t, catalog_generation_append_text(
        generation, "root.jl", CATALOG_PATH_BYTE_CAPACITY, &path_ref),
        Catalog_Generation_Status.Ok)
    root := Catalog_Generation_Record{
        stable_id = root_id,
        node_kind = .Category,
        sibling_order = 0,
        catalog_order = 0,
        display_name = name_ref,
        implementation_path = path_ref,
    }
    testing.expect_value(t, catalog_generation_append_record(generation, root),
        Catalog_Generation_Status.Ok)
    if include_children {
        catalog_generation_test_append_child(t, generation, 2, "child.jl")
    }
    return true
}

// Append one deterministic leaf and one root Terminal record to a generation.
catalog_generation_test_append_child :: proc(
    t: ^testing.T, generation: ^Catalog_Generation,
    identity: u8, path: string) {
    child_name: Catalog_Text_Ref
    child_path: Catalog_Text_Ref
    terminal_name: Catalog_Text_Ref
    catalog_generation_test_append_text(t, generation, "Child",
        CATALOG_NAME_BYTE_CAPACITY, &child_name)
    catalog_generation_test_append_text(t, generation, path,
        CATALOG_PATH_BYTE_CAPACITY, &child_path)
    catalog_generation_test_append_text(t, generation, "Terminal",
        CATALOG_NAME_BYTE_CAPACITY, &terminal_name)
    empty_path := Catalog_Text_Ref{offset = u32(generation.text_builder.count)}
    child := Catalog_Generation_Record{
        stable_id = catalog_generation_test_id(identity),
        parent_stable_id = catalog_generation_test_id(1),
        has_parent = true,
        node_kind = .Leaf,
        sibling_order = 0,
        catalog_order = 1,
        display_name = child_name,
        implementation_path = child_path,
    }
    terminal := Catalog_Generation_Record{
        stable_id = catalog_generation_test_id(255),
        node_kind = .Terminal,
        sibling_order = 1,
        catalog_order = 2,
        display_name = terminal_name,
        implementation_path = empty_path,
    }
    testing.expect_value(t, catalog_generation_append_record(generation, child),
        Catalog_Generation_Status.Ok)
    testing.expect_value(t, catalog_generation_append_record(generation, terminal),
        Catalog_Generation_Status.Ok)
}

// Append one fixture string and assert that bounded admission succeeds.
catalog_generation_test_append_text :: proc(
    t: ^testing.T, generation: ^Catalog_Generation, text: string,
    capacity: int, reference: ^Catalog_Text_Ref) {
    testing.expect_value(t, catalog_generation_append_text(
        generation, text, capacity, reference), Catalog_Generation_Status.Ok)
}

// Verify packed name/path references resolve after publication and reject later writes.
@(test)
catalog_generation_packs_text_and_seals_immutable_records :: proc(t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect(t, catalog_generation_test_build(t, &generation, 17, true))
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Ok)

    name, name_status := catalog_generation_text(
        &generation, generation.records[1].display_name)
    path, path_status := catalog_generation_text(
        &generation, generation.records[1].implementation_path)
    testing.expect_value(t, name_status, Catalog_Generation_Status.Ok)
    testing.expect_value(t, path_status, Catalog_Generation_Status.Ok)
    testing.expect_value(t, name, "Child")
    testing.expect_value(t, path, "child.jl")
    testing.expect_value(t, string(generation.text_bytes),
        "Rootroot.jlChildchild.jlTerminal")
    rejected_ref: Catalog_Text_Ref
    testing.expect_value(t, catalog_generation_append_text(
        &generation, "late", CATALOG_NAME_BYTE_CAPACITY, &rejected_ref),
        Catalog_Generation_Status.Invalid_State)
    testing.expect_value(t, catalog_generation_append_record(
        &generation, Catalog_Generation_Record{}),
        Catalog_Generation_Status.Invalid_State)
}

// Verify nullable paths use an empty reference without consuming bytes.
@(test)
catalog_generation_represents_terminal_path_as_empty_reference :: proc(
    t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect(t, catalog_generation_test_build(t, &generation, 18, true))
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Ok)
    path, status := catalog_generation_text(
        &generation, generation.records[2].implementation_path)
    testing.expect_value(t, status, Catalog_Generation_Status.Ok)
    testing.expect_value(t, len(path), 0)
}

// Verify per-field, UTF-8, embedded-NUL, and total logical text limits.
@(test)
catalog_generation_enforces_text_contracts_and_total_limit :: proc(
    t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect_value(t, catalog_generation_begin(&generation, 19),
        Catalog_Generation_Status.Ok)
    reference: Catalog_Text_Ref
    testing.expect_value(t, catalog_generation_append_text(
        &generation, "oversized", 2, &reference), Catalog_Generation_Status.Capacity)
    invalid_utf8 := transmute(string)[]u8{0xC0, 0xAF}
    testing.expect_value(t, catalog_generation_append_text(
        &generation, invalid_utf8, 8, &reference),
        Catalog_Generation_Status.Invalid_Text)
    testing.expect_value(t, catalog_generation_append_text(
        &generation, "nul\x00value", 16, &reference),
        Catalog_Generation_Status.Invalid_Text)

    catalog_generation_test_fill_text_capacity(t, &generation, &reference)
    testing.expect_value(t, generation.text_builder.count, CATALOG_TEXT_BYTE_CAPACITY)
    testing.expect_value(t, catalog_generation_append_text(
        &generation, "x", 1, &reference), Catalog_Generation_Status.Capacity)
}

// Fill the generation's text builder exactly to its declared logical limit.
catalog_generation_test_fill_text_capacity :: proc(
    t: ^testing.T, generation: ^Catalog_Generation,
    reference: ^Catalog_Text_Ref) {
    chunk := make([]u8, CATALOG_PATH_BYTE_CAPACITY, context.allocator)
    defer delete(chunk, context.allocator)
    for index in 0..<len(chunk) {
        chunk[index] = 'x'
    }
    text := transmute(string)chunk
    full_chunks := CATALOG_TEXT_BYTE_CAPACITY / len(chunk)
    for _ in 0..<full_chunks {
        catalog_generation_test_append_text(
            t, generation, text, CATALOG_PATH_BYTE_CAPACITY, reference)
    }
    remaining := CATALOG_TEXT_BYTE_CAPACITY % len(chunk)
    if remaining > 0 {
        catalog_generation_test_append_text(
            t, generation, text[:remaining], CATALOG_PATH_BYTE_CAPACITY, reference)
    }
}

// Verify sealing catches invalid and overflow-shaped text references.
@(test)
catalog_generation_rejects_invalid_text_references :: proc(t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect(t, catalog_generation_test_build(t, &generation, 20, false))
    generation.records[0].display_name = Catalog_Text_Ref{
        offset = max(u32), length = max(u32),
    }
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Invalid_Reference)

    testing.expect_value(t, catalog_generation_reset(&generation),
        Catalog_Generation_Status.Ok)
    testing.expect_value(t, catalog_generation_begin(&generation, 21),
        Catalog_Generation_Status.Ok)
    testing.expect(t, catalog_generation_test_build_recordless_root(t, &generation))
    generation.records[0].display_name = Catalog_Text_Ref{
        offset = max(u32), length = max(u32),
    }
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Invalid_Reference)
}

// Append one valid root fixture record without resetting the caller's generation.
catalog_generation_test_build_recordless_root :: proc(
    t: ^testing.T, generation: ^Catalog_Generation) -> bool {
    catalog_generation_test_append_root(t, generation)
    catalog_generation_test_append_terminal(t, generation)
    return true
}

// Append the valid category root used by invalid-reference tests.
catalog_generation_test_append_root :: proc(
    t: ^testing.T, generation: ^Catalog_Generation) {
    name: Catalog_Text_Ref
    path: Catalog_Text_Ref
    catalog_generation_test_append_text(t, generation, "Root",
        CATALOG_NAME_BYTE_CAPACITY, &name)
    catalog_generation_test_append_text(t, generation, "root.jl",
        CATALOG_PATH_BYTE_CAPACITY, &path)
    root := Catalog_Generation_Record{
        stable_id = catalog_generation_test_id(1),
        node_kind = .Category,
        sibling_order = 0,
        catalog_order = 0,
        display_name = name,
        implementation_path = path,
    }
    testing.expect_value(t, catalog_generation_append_record(generation, root),
        Catalog_Generation_Status.Ok)
}

// Append the unique root Terminal used by invalid-reference tests.
catalog_generation_test_append_terminal :: proc(
    t: ^testing.T, generation: ^Catalog_Generation) {
    terminal_name: Catalog_Text_Ref
    empty_path: Catalog_Text_Ref
    catalog_generation_test_append_text(t, generation, "Terminal",
        CATALOG_NAME_BYTE_CAPACITY, &terminal_name)
    catalog_generation_test_append_text(t, generation, "",
        CATALOG_PATH_BYTE_CAPACITY, &empty_path)
    terminal := Catalog_Generation_Record{
        stable_id = catalog_generation_test_id(255),
        node_kind = .Terminal,
        sibling_order = 1,
        catalog_order = 1,
        display_name = terminal_name,
        implementation_path = empty_path,
    }
    testing.expect_value(t, catalog_generation_append_record(generation, terminal),
        Catalog_Generation_Status.Ok)
}

// Verify malformed identities, parents, sibling/order values, and cycles fail sealing.
@(test)
catalog_generation_rejects_invalid_topology :: proc(t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect(t, catalog_generation_test_build(t, &generation, 22, true))
    generation.records[1].parent_stable_id = catalog_generation_test_id(9)
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Invalid_Topology)

    testing.expect_value(t, catalog_generation_reset(&generation),
        Catalog_Generation_Status.Ok)
    testing.expect(t, catalog_generation_test_build(t, &generation, 23, true))
    generation.records[0].sibling_order = 1
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Invalid_Topology)

    testing.expect_value(t, catalog_generation_reset(&generation),
        Catalog_Generation_Status.Ok)
    testing.expect(t, catalog_generation_test_build(t, &generation, 24, true))
    generation.records[0].catalog_order = 1
    testing.expect_value(t, catalog_generation_seal(&generation),
        Catalog_Generation_Status.Invalid_Topology)
}

// Verify resetting staged storage leaves an active generation readable.
@(test)
catalog_generation_reset_keeps_active_slot_and_reports_arena_lifecycle :: proc(
    t: ^testing.T) {
    active: Catalog_Generation
    staged: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&active),
        Catalog_Generation_Status.Ok)
    testing.expect_value(t, catalog_generation_init(&staged),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&active)
    defer catalog_generation_destroy(&staged)
    testing.expect(t, catalog_generation_test_build(t, &active, 25, true))
    testing.expect_value(t, catalog_generation_seal(&active),
        Catalog_Generation_Status.Ok)
    testing.expect(t, catalog_generation_test_build(t, &staged, 26, true))
    testing.expect_value(t, catalog_generation_seal(&staged),
        Catalog_Generation_Status.Ok)
    staged_reference := staged.records[1].display_name

    testing.expect_value(t, catalog_generation_reset(&staged),
        Catalog_Generation_Status.Ok)
    _, stale_status := catalog_generation_text(&staged, staged_reference)
    testing.expect_value(t, stale_status, Catalog_Generation_Status.Invalid_State)
    active_name, active_status := catalog_generation_text(
        &active, active.records[1].display_name)
    testing.expect_value(t, active_status, Catalog_Generation_Status.Ok)
    testing.expect_value(t, active_name, "Child")
    diagnostics := storage_pkg.arena_owner_diagnostics(&staged.arena_owner)
    testing.expect(t, diagnostics.initialized)
    testing.expect_value(t, diagnostics.reset_count, u64(1))
    testing.expect_value(t, staged.record_count, u16(0))
    testing.expect(t, !staged.sealed)
}

// Verify generation destruction releases its arena and preserves terminal diagnostics.
@(test)
catalog_generation_destroy_releases_initialized_arena :: proc(t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    testing.expect(t, catalog_generation_test_build(t, &generation, 27, true))
    catalog_generation_destroy(&generation)
    testing.expect(t, !generation.initialized)
    testing.expect(t, !generation.arena_owner.initialized)
    diagnostics := storage_pkg.arena_owner_diagnostics(&generation.arena_owner)
    testing.expect_value(t, diagnostics.destroy_count, u64(1))
}

// Verify the fixed record envelope rejects one record beyond its exact capacity.
@(test)
catalog_generation_enforces_record_capacity :: proc(t: ^testing.T) {
    generation: Catalog_Generation
    testing.expect_value(t, catalog_generation_init(&generation),
        Catalog_Generation_Status.Ok)
    defer catalog_generation_destroy(&generation)
    testing.expect_value(t, catalog_generation_begin(&generation, 28),
        Catalog_Generation_Status.Ok)
    for _ in 0..<CATALOG_RECORD_CAPACITY {
        testing.expect_value(t, catalog_generation_append_record(
            &generation, Catalog_Generation_Record{}),
            Catalog_Generation_Status.Ok)
    }
    testing.expect_value(t, generation.record_count, u16(CATALOG_RECORD_CAPACITY))
    testing.expect_value(t, catalog_generation_append_record(
        &generation, Catalog_Generation_Record{}),
        Catalog_Generation_Status.Capacity)
}