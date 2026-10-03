package content

import sqlite "../../sqlite"
import contentdata "../../core/content"

import "core:strings"
import "core:unicode/utf8"
import "core:encoding/uuid"

CATALOG_EXPECTED_RECORD_COUNT :: contentdata.CATALOG_RECORD_CAPACITY

// Parse one required canonical UUID while SQLite column memory is current.
content_generation_read_uuid_column :: proc(
    statement: ^sqlite.Statement, column: int) -> (uuid.Identifier, bool) {
    return content_admission_read_uuid(statement, column)
}

// Admit only package-local slash-separated relative implementation paths.
content_generation_implementation_path_is_safe :: proc(path: string) -> bool {
    if len(path) == 0 || path[0] == '/' || strings.contains(path, "\\") ||
       strings.contains(path, ":") || !utf8.valid_string(path) {
        return false
    }
    component_start := 0
    for index in 0..=len(path) {
        if index < len(path) && path[index] != '/' {
            continue
        }
        component := path[component_start:index]
        if len(component) == 0 || component == "." || component == ".." {
            return false
        }
        component_start = index + 1
    }
    return true
}

// Read one normalized catalogue node and preserve nullable parent identity.
content_generation_read_record_identity :: proc(
    statement: ^sqlite.Statement, record: ^Catalog_Record) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := content_admission_copy_text(
        statement, 0, namespace[:], len(namespace), false)
    if !namespace_ok || string(namespace[:namespace_count]) != CONTENT_SOURCE_NAMESPACE {
        return false
    }
    stable_id, id_ok := content_generation_read_uuid_column(statement, 1)
    if !id_ok || stable_id == (uuid.Identifier{}) {
        return false
    }
    record.stable_id = stable_id
    if search_column_type(statement, 2) != .Null {
        parent_id, parent_ok := content_generation_read_uuid_column(statement, 2)
        if !parent_ok || parent_id == (uuid.Identifier{}) {
            return false
        }
        record.parent_stable_id = parent_id
        record.has_parent = true
    }
    return true
}

// Read node kind and exact normalized sibling/catalogue ordering columns.
content_generation_record_metadata_read :: proc(
    statement: ^sqlite.Statement, expected_order: int, record: ^Catalog_Record) -> bool {
    if search_column_type(statement, 3) != .Integer ||
       search_column_type(statement, 4) != .Integer ||
       search_column_type(statement, 5) != .Integer {
        return false
    }
    kind, kind_ok := search_column_i32(statement, 3)
    sibling_order, sibling_ok := search_column_i64(statement, 4)
    catalog_order, catalog_ok := search_column_i64(statement, 5)
    if !kind_ok || kind < 1 || kind > 3 || !sibling_ok || sibling_order < 0 ||
       sibling_order > i64(max(i32)) || !catalog_ok ||
       catalog_order != i64(expected_order) {
        return false
    }
    record.node_kind = Catalog_Node_Kind(kind)
    record.sibling_order = i32(sibling_order)
    record.catalog_order = i32(catalog_order)
    return true
}

// Validate and copy one node's nullable implementation path.
content_generation_record_path_read :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation,
    record: ^Catalog_Record) -> bool {
    if record.node_kind == .Terminal {
        if search_column_type(statement, 6) != .Null {
            return false
        }
        return contentdata.content_generation_append_text(
            generation, "", CATALOG_PATH_BYTE_CAPACITY,
            &record.implementation_path) == .Ok
    }
    path_storage: [CATALOG_PATH_BYTE_CAPACITY]u8
    path_count, path_ok := content_admission_copy_text(
        statement, 6, path_storage[:], len(path_storage), false)
    path := string(path_storage[:path_count])
    if !path_ok || !content_generation_implementation_path_is_safe(path) {
        return false
    }
    return contentdata.content_generation_append_text(
        generation, path, CATALOG_PATH_BYTE_CAPACITY,
        &record.implementation_path) == .Ok
}

// Decode one normalized catalogue row into immutable topology storage.
content_generation_read_record :: proc(
    statement: ^sqlite.Statement, expected_order: int,
    generation: ^Content_Generation, record: ^Catalog_Record) -> bool {
    return content_generation_read_record_identity(statement, record) &&
        content_generation_record_metadata_read(statement, expected_order, record) &&
        content_generation_record_path_read(statement, generation, record)
}

// Materialize all normalized declarations, validate coverage, and seal once.
content_generation_read_database :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    if database == nil || generation == nil {
        return false
    }
    if !generation.initialized {
        content_generation_clear_fields(generation)
        return false
    }
    if contentdata.content_generation_reset(generation) != .Ok ||
       contentdata.content_generation_begin(
           generation, database.index_generation) != .Ok ||
       !content_generation_materialize(database, generation) ||
       !content_admission_validate_complete(database, generation) ||
       contentdata.content_generation_seal(generation) != .Ok ||
       generation.generation != database.index_generation ||
       !generation.data.complete {
        content_generation_reset_failed_read(database, generation)
        return false
    }
    return true
}

// Read every normalized table into the open candidate in dependency order.
content_generation_materialize :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    return content_admission_read_locales(database, generation) &&
        content_admission_read_messages(database, generation) &&
        content_admission_read_arguments(database, generation) &&
        content_admission_read_translations(database, generation) &&
        content_admission_read_subjects(database, generation) &&
        content_generation_read_catalogue(database, generation) &&
        content_admission_read_names(database, generation) &&
        content_admission_read_editions(database, generation) &&
        content_admission_read_availability(database, generation) &&
        content_admission_read_projections(database, generation)
}

// Clear every generation field without touching packed storage ownership.
content_generation_clear_fields :: proc(generation: ^Content_Generation) {
    generation.records = {}
    generation.record_count = 0
    generation.data = {}
    generation.text_bytes = nil
    generation.generation = 0
    generation.sealed = false
}

// Read exactly the bounded normalized catalogue node table.
content_generation_read_catalogue :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.catalog_rows
    for index in 0..<CATALOG_EXPECTED_RECORD_COUNT {
        status := search_step(statement)
        if status != .Row {
            return false
        }
        record: Catalog_Record
        if !content_generation_read_record(statement, index, generation, &record) ||
           contentdata.content_generation_append_record(generation, record) != .Ok {
            return false
        }
    }
    exhausted := search_step(statement) == .Done
    return exhausted && search_statement_reset(statement)
}

// Reset every admission statement and discard all text and normalized fields.
content_generation_reset_failed_read :: proc(
    database: ^Content_Database, generation: ^Content_Generation) {
    _ = search_statement_reset(&database.statements.projection_rows)
    _ = search_statement_reset(&database.statements.availability_rows)
    _ = search_statement_reset(&database.statements.edition_rows)
    _ = search_statement_reset(&database.statements.name_rows)
    _ = search_statement_reset(&database.statements.catalog_rows)
    _ = search_statement_reset(&database.statements.subject_rows)
    _ = search_statement_reset(&database.statements.translation_rows)
    _ = search_statement_reset(&database.statements.argument_rows)
    _ = search_statement_reset(&database.statements.message_rows)
    _ = search_statement_reset(&database.statements.locale_rows)
    _ = search_statement_reset(&database.statements.raw_metadata_rows)
    _ = contentdata.content_generation_reset(generation)
    content_generation_clear_fields(generation)
    database.index_generation = 0
    database.expected_table_counts = {}
    database.expected_record_count = 0
}
