package catalog

import sqlite "../../sqlite"
import catalogdata "../../core/catalog"

import "core:strings"
import "core:unicode/utf8"
import "core:encoding/uuid"

CATALOG_EXPECTED_RECORD_COUNT :: CATALOG_RECORD_CAPACITY

// Copy one required UTF-8 column, rejecting embedded NUL and invalid byte sequences.
catalog_generation_copy_utf8_column :: proc(
    statement: ^sqlite.Statement, column: int, destination: []u8) -> (int, bool) {
    if search_column_type(statement, column) != .Text {
        return 0, false
    }
    count, ok := search_copy_column(statement, column, destination)
    if !ok || count == 0 {
        return 0, false
    }
    value := string(destination[:count])
    return count, utf8.valid_string(value) && !strings.contains(value, "\x00")
}

// Parse one required canonical UUID while SQLite column memory is current.
catalog_generation_read_uuid_column :: proc(
    statement: ^sqlite.Statement, column: int) -> (uuid.Identifier, bool) {
    encoded: [SEARCH_DOCUMENT_ID_BYTE_COUNT]u8
    count, ok := catalog_generation_copy_utf8_column(statement, column, encoded[:])
    if !ok || count != SEARCH_DOCUMENT_ID_BYTE_COUNT {
        return {}, false
    }
    identifier, read_error := uuid.read(string(encoded[:count]))
    return identifier, read_error == .None && identifier != uuid.Identifier{}
}

// Admit only package-local slash-separated relative implementation paths.
catalog_generation_implementation_path_is_safe :: proc(path: string) -> bool {
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

// Validate and copy one row's source identity and optional parent identity.
catalog_generation_record_identity_read :: proc(
    statement: ^sqlite.Statement, record: ^Catalog_Record) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := catalog_generation_copy_utf8_column(
        statement, 0, namespace[:])
    if !namespace_ok || namespace_count != len(namespace) ||
       string(namespace[:]) != "builtin" {
        return false
    }
    stable_id, id_ok := catalog_generation_read_uuid_column(statement, 1)
    if !id_ok {
        return false
    }
    record.stable_id = stable_id
    if search_column_type(statement, 2) != .Null {
        parent_stable_id, parent_ok := catalog_generation_read_uuid_column(statement, 2)
        if !parent_ok {
            return false
        }
        record.parent_stable_id = parent_stable_id
        record.has_parent = true
    }
    return true
}

// Validate and copy one row's node kind, display name, and stable ordering values.
catalog_generation_record_metadata_read :: proc(
    statement: ^sqlite.Statement, expected_order: int,
    generation: ^Catalog_Generation, record: ^Catalog_Record) -> bool {
    if search_column_type(statement, 3) != .Integer ||
       search_column_type(statement, 5) != .Integer ||
       search_column_type(statement, 6) != .Integer {
        return false
    }
    kind, kind_ok := search_column_i32(statement, 3)
    if !kind_ok || kind < 1 || kind > 3 {
        return false
    }
    record.node_kind = Catalog_Node_Kind(kind)
    name_storage: [CATALOG_NAME_BYTE_CAPACITY]u8
    name_count, name_ok := catalog_generation_copy_utf8_column(
        statement, 4, name_storage[:])
    sibling_order, sibling_ok := search_column_i64(statement, 5)
    catalog_order, catalog_ok := search_column_i64(statement, 6)
    if !name_ok || !sibling_ok || !catalog_ok || sibling_order < 0 ||
       sibling_order > i64(max(i32)) || catalog_order != i64(expected_order) {
        return false
    }
    name := string(name_storage[:name_count])
    if catalogdata.catalog_generation_append_text(
        generation, name, CATALOG_NAME_BYTE_CAPACITY, &record.display_name) != .Ok {
        return false
    }
    record.sibling_order = i32(sibling_order)
    record.catalog_order = i32(catalog_order)
    return true
}

// Validate and copy one row's nullable path according to its node kind.
catalog_generation_record_path_read :: proc(
    statement: ^sqlite.Statement, generation: ^Catalog_Generation,
    record: ^Catalog_Record) -> bool {
    path_type := search_column_type(statement, 7)
    if record.node_kind == .Terminal {
        return path_type == .Null && catalogdata.catalog_generation_append_text(
            generation, "", CATALOG_PATH_BYTE_CAPACITY,
            &record.implementation_path) == .Ok
    }
    path_storage: [CATALOG_PATH_BYTE_CAPACITY]u8
    path_count, path_ok := catalog_generation_copy_utf8_column(
        statement, 7, path_storage[:])
    path := string(path_storage[:path_count])
    if !path_ok || !catalog_generation_implementation_path_is_safe(path) {
        return false
    }
    return catalogdata.catalog_generation_append_text(
        generation, path, CATALOG_PATH_BYTE_CAPACITY,
        &record.implementation_path) == .Ok
}

// Decode one catalogue row into compact metadata and generation text references.
catalog_generation_read_record :: proc(
    statement: ^sqlite.Statement, expected_order: int,
    generation: ^Catalog_Generation, record: ^Catalog_Record) -> bool {
    return catalog_generation_record_identity_read(statement, record) &&
        catalog_generation_record_metadata_read(
            statement, expected_order, generation, record) &&
        catalog_generation_record_path_read(statement, generation, record)
}

// Decode, validate, and seal every row before worker readiness publication.
catalog_generation_read_database :: proc(
    database: ^Catalog_Database, generation: ^Catalog_Generation) -> bool {
    if generation == nil || !generation.initialized ||
       catalogdata.catalog_generation_reset(generation) != .Ok {
        return false
    }
    if catalogdata.catalog_generation_begin(
        generation, database.index_generation) != .Ok {
        return false
    }
    statement := &database.statements.catalog_rows
    for index in 0..<CATALOG_RECORD_CAPACITY {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row {
            catalog_generation_reset_failed_read(statement, generation)
            return false
        }
        record: Catalog_Record
        if !catalog_generation_read_record(statement, index, generation, &record) ||
           catalogdata.catalog_generation_append_record(generation, record) != .Ok {
            catalog_generation_reset_failed_read(statement, generation)
            return false
        }
    }
    exhausted := search_step(statement) == .Done
    reset_ok := search_statement_reset(statement)
    if !exhausted || !reset_ok ||
       generation.record_count != CATALOG_EXPECTED_RECORD_COUNT ||
       catalogdata.catalog_generation_seal(generation) != .Ok {
        _ = catalogdata.catalog_generation_reset(generation)
        return false
    }
    return generation.generation == database.index_generation
}

// Reset the statement and candidate generation after a failed decode or append.
catalog_generation_reset_failed_read :: proc(
    statement: ^sqlite.Statement, generation: ^Catalog_Generation) {
    _ = search_statement_reset(statement)
    _ = catalogdata.catalog_generation_reset(generation)
}