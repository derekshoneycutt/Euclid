package contentstore

import sqlite "../../sqlite"
import contentdata "../../core/content"

// Report whether the worker owns an open content connection.
content_database_ready :: proc(database: ^Content_Database) -> bool {
    return database != nil && database.connection.handle != nil
}

// Prepare one persistent repository-owned statement for worker-lifetime reuse.
search_prepare :: proc(
    connection: ^sqlite.Connection, statement: ^sqlite.Statement,
    sql: cstring) -> bool {
    failure := sqlite.statement_prepare(connection, statement, sql)
    return failure.validation == .None && failure.result == .Ok
}

// Reset one reusable statement and clear every prior binding.
search_statement_reset :: proc(statement: ^sqlite.Statement) -> bool {
    failure := sqlite.statement_reset(statement)
    return failure.validation == .None && failure.result == .Ok
}

// Bind copied text so request-local bytes may be reused immediately.
search_bind_text :: proc(
    statement: ^sqlite.Statement, index: int, value: string) -> bool {
    failure := sqlite.statement_bind_text(statement, index, value)
    return failure.validation == .None && failure.result == .Ok
}

// Bind one checked integer value to a fixed catalogue query parameter.
search_bind_i32 :: proc(statement: ^sqlite.Statement, index: int, value: i32) -> bool {
    failure := sqlite.statement_bind_i32(statement, index, value)
    return failure.validation == .None && failure.result == .Ok
}

// Copy one exact SQLite text column into caller-owned bounded bytes.
search_copy_column :: proc(
    statement: ^sqlite.Statement, column: int,
    destination: []u8) -> (int, bool) {
    count, failure := sqlite.column_text_copy(statement, column, destination)
    return count, failure.validation == .None && failure.result == .Ok
}

// Step one statement and preserve row, done, and failure as distinct outcomes.
search_step :: proc(statement: ^sqlite.Statement) -> sqlite.Step_Status {
    status, _ := sqlite.statement_step(statement)
    return status
}

// Read the exact SQLite storage class for one catalogue column.
search_column_type :: proc(
    statement: ^sqlite.Statement, column: int) -> sqlite.Column_Type {
    return sqlite.column_type(statement, column)
}

// Read an exact integer column as a checked signed 64-bit value.
search_column_i64 :: proc(statement: ^sqlite.Statement, column: int) -> (i64, bool) {
    value, failure := sqlite.column_i64(statement, column)
    return value, failure.validation == .None && failure.result == .Ok
}

// Read an exact integer column as a checked signed 32-bit value.
search_column_i32 :: proc(statement: ^sqlite.Statement, column: int) -> (i32, bool) {
    value, failure := sqlite.column_i32(statement, column)
    return value, failure.validation == .None && failure.result == .Ok
}

// Parse the first 64 bits of one canonical lowercase SHA-256 identity.
search_generation_from_fingerprint :: proc(value: string) -> (u64, bool) {
    if len(value) != contentdata.SEARCH_FINGERPRINT_BYTE_COUNT {
        return 0, false
    }
    generation: u64
    for byte in transmute([]u8)value[:16] {
        digit: u64
        if byte >= '0' && byte <= '9' {
            digit = u64(byte - '0')
        } else if byte >= 'a' && byte <= 'f' {
            digit = u64(byte - 'a' + 10)
        } else {
            return 0, false
        }
        generation = generation << 4 | digit
    }
    return generation, true
}

// Read one required metadata value through the fixed bound lookup statement.
search_metadata_equals :: proc(
    database: ^Content_Database, key, expected: string) -> bool {
    statement := &database.statements.search_metadata
    if !search_bind_text(statement, 1, key) || search_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return false
    }
    value_storage: [contentdata.SEARCH_FINGERPRINT_BYTE_COUNT]u8
    count, copied := search_copy_column(statement, 0, value_storage[:])
    matches := copied && count == len(expected) &&
        string(value_storage[:count]) == expected
    exhausted := search_step(statement) == .Done
    return search_statement_reset(statement) && matches && exhausted
}

// Finalize one optional statement while retaining aggregate cleanup success.
search_finalize :: proc(statement: ^sqlite.Statement, ok: ^bool) {
    if statement.handle == nil {
        return
    }
    failure := sqlite.statement_finalize(statement)
    if failure.validation != .None || failure.result != .Ok {
        ok^ = false
    }
}

// Close every worker-owned SQLite resource in reverse preparation order.
content_database_close :: proc(database: ^Content_Database) -> bool {
    ok := true
    search_finalize(&database.statements.projection_rows, &ok)
    search_finalize(&database.statements.availability_rows, &ok)
    search_finalize(&database.statements.edition_rows, &ok)
    search_finalize(&database.statements.name_rows, &ok)
    search_finalize(&database.statements.catalog_rows, &ok)
    search_finalize(&database.statements.subject_rows, &ok)
    search_finalize(&database.statements.translation_rows, &ok)
    search_finalize(&database.statements.argument_rows, &ok)
    search_finalize(&database.statements.message_rows, &ok)
    search_finalize(&database.statements.locale_rows, &ok)
    search_finalize(&database.statements.raw_metadata_rows, &ok)
    search_finalize(&database.statements.spellfix, &ok)
    search_finalize(&database.statements.search_metadata, &ok)
    search_finalize(&database.statements.search_rows, &ok)
    search_finalize(&database.statements.count, &ok)
    if database.connection.handle != nil {
        failure := sqlite.connection_close(&database.connection)
        if failure.validation != .None || failure.result != .Ok {
            ok = false
        }
    }
    if ok {
        database^ = {}
    }
    return ok
}

// Prepare the complete fixed runtime statement set transactionally.
content_database_prepare_statements :: proc(database: ^Content_Database) -> bool {
    return content_database_prepare_search_statements(database) &&
        content_database_prepare_declaration_statements(database) &&
        content_database_prepare_catalogue_statements(database)
}

// Prepare one named statement against the owned connection.
content_database_prepare :: proc(
    database: ^Content_Database, statement: ^sqlite.Statement, sql: cstring) -> bool {
    return search_prepare(&database.connection, statement, sql)
}

// Prepare the preserved schema-2 search and raw metadata statements.
content_database_prepare_search_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.count, cstring(SEARCH_COUNT_SQL)) &&
        content_database_prepare(
            database, &statements.search_rows, cstring(SEARCH_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.search_metadata, cstring(SEARCH_METADATA_SQL)) &&
        content_database_prepare(
            database, &statements.spellfix, cstring(SEARCH_SPELLFIX_SQL)) &&
        content_database_prepare(
            database, &statements.raw_metadata_rows, cstring(RAW_METADATA_ROWS_SQL))
}

// Prepare locale and localized UI message declaration statements.
content_database_prepare_declaration_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.locale_rows, cstring(LOCALE_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.message_rows, cstring(MESSAGE_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.argument_rows, cstring(ARGUMENT_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.translation_rows, cstring(TRANSLATION_ROWS_SQL))
}

// Prepare subject, catalogue, edition, availability, and projection statements.
content_database_prepare_catalogue_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.subject_rows, cstring(SUBJECT_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.catalog_rows, cstring(CATALOG_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.name_rows, cstring(NAME_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.edition_rows, cstring(EDITION_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.availability_rows, cstring(AVAILABILITY_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.projection_rows, cstring(PROJECTION_ROWS_SQL))
}

// Validate the immutable database contract before worker readiness publication.
content_database_validate_metadata :: proc(
    database: ^Content_Database, expected_fingerprint: string) -> bool {
    if !search_metadata_equals(database, "schema_version", "2") ||
       !search_metadata_equals(database, "sqlite_version", "3.53.4") ||
       !search_metadata_equals(database, "tokenizer_version", "porter-unicode61-v1") ||
       !search_metadata_equals(database, "query_contract_version", "1") ||
       !search_metadata_equals(database, "document_count", "138") ||
       !search_metadata_equals(database, "catalog_fingerprint", expected_fingerprint) ||
       !search_metadata_equals(database, "index_generation", expected_fingerprint) ||
       !content_admission_validate_metadata(database, expected_fingerprint) {
        return false
    }
    generation, valid := search_generation_from_fingerprint(expected_fingerprint)
    database.index_generation = generation
    return valid
}

// Open, configure, and admit one immutable packaged database.
content_database_open :: proc(
    database: ^Content_Database, path, expected_fingerprint: string,
    generation: ^contentdata.Content_Generation) -> bool {
    open_failure := sqlite.connection_open(
        &database.connection, path, .Immutable_Readonly, context.temp_allocator)
    if open_failure.validation != .None || open_failure.result != .Ok {
        if generation != nil {
            content_generation_reset_failed_read(database, generation)
        }
        _ = content_database_close(database)
        return false
    }
    spellfix_failure := sqlite.connection_register_spellfix(&database.connection)
    if spellfix_failure.validation != .None || spellfix_failure.result != .Ok ||
       !content_database_prepare_statements(database) ||
       !content_database_validate_metadata(database, expected_fingerprint) ||
       !content_generation_read_database(database, generation) {
        if generation != nil {
            content_generation_reset_failed_read(database, generation)
        }
        _ = content_database_close(database)
        return false
    }
    return true
}
