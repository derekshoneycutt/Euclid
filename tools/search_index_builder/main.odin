package main

import sqlite "../../src/sqlite"

import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

CORPUS_SCHEMA_VERSION :: 2
CORPUS_MAX_BYTES :: 2 * 1024 * 1024
CORPUS_LINE_MAX_BYTES :: 16 * 1024
EXPECTED_DOCUMENT_COUNT :: 138

Corpus_Optional_String :: union {
    json.Null,
    string,
}

Corpus_Record :: struct {
    schema: int,
    source_namespace: string,
    animation_id: string,
    parent_animation_id: Corpus_Optional_String,
    node_kind: int,
    display_name: string,
    sibling_order: int,
    catalog_order: int,
    implementation_path: Corpus_Optional_String,
    hierarchy_path: string,
    semantic_text: string,
    aliases: []string,
}

SCHEMA_SQL :: `
PRAGMA page_size=4096;
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
PRAGMA temp_store=MEMORY;
PRAGMA foreign_keys=ON;
CREATE TABLE search_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE animation_catalog (
    rowid INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    parent_animation_id TEXT,
    node_kind INTEGER NOT NULL,
    display_name TEXT NOT NULL,
    sibling_order INTEGER NOT NULL,
    catalog_order INTEGER NOT NULL,
    implementation_path TEXT,
    hierarchy_path TEXT NOT NULL,
    aliases TEXT NOT NULL,
    semantic_text TEXT NOT NULL,
    CONSTRAINT animation_catalog_identity
        UNIQUE (source_namespace, animation_id),
    CONSTRAINT animation_catalog_order
        UNIQUE (source_namespace, catalog_order),
    CONSTRAINT animation_catalog_parent
        FOREIGN KEY (source_namespace, parent_animation_id)
        REFERENCES animation_catalog (source_namespace, animation_id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT animation_catalog_kind
        CHECK (node_kind IN (1, 2, 3)),
    CONSTRAINT animation_catalog_sibling_order
        CHECK (sibling_order >= 0),
    CONSTRAINT animation_catalog_catalog_order
        CHECK (catalog_order >= 0),
    CONSTRAINT animation_catalog_name
        CHECK (length(display_name) > 0),
    CONSTRAINT animation_catalog_implementation
        CHECK (
            (node_kind = 3 AND implementation_path IS NULL) OR
            (node_kind IN (1, 2) AND implementation_path IS NOT NULL AND
                length(implementation_path) > 0)
        )
);
CREATE UNIQUE INDEX animation_catalog_root_sibling_order
ON animation_catalog (source_namespace, sibling_order)
WHERE parent_animation_id IS NULL;
CREATE UNIQUE INDEX animation_catalog_child_sibling_order
ON animation_catalog (source_namespace, parent_animation_id, sibling_order)
WHERE parent_animation_id IS NOT NULL;
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name,
    hierarchy_path,
    aliases,
    semantic_text,
    content='animation_catalog',
    content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 2',
    detail=full
);
CREATE VIRTUAL TABLE search_terms USING spellfix1;
CREATE VIRTUAL TABLE plain_search USING fts5(
    content,
    tokenize='unicode61 remove_diacritics 2'
);
CREATE VIRTUAL TABLE plain_search_vocabulary USING fts5vocab(plain_search, 'row');
`

CATALOG_INSERT_SQL :: `INSERT INTO animation_catalog(
    source_namespace, animation_id, parent_animation_id, node_kind,
    display_name, sibling_order, catalog_order, implementation_path,
    hierarchy_path, aliases, semantic_text)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`

PLAIN_INSERT_SQL :: "INSERT INTO plain_search(content) VALUES (?1)"
METADATA_INSERT_SQL :: "INSERT INTO search_metadata(key, value) VALUES (?1, ?2)"

Builder_Statements :: struct {
    catalog_insert: sqlite.Statement,
    plain_insert: sqlite.Statement,
    metadata_insert: sqlite.Statement,
}

Builder_Database :: struct {
    connection: sqlite.Connection,
    statements: Builder_Statements,
}

// Fail the build with SQLite's connection-owned diagnostic text.
sqlite_fail :: proc(database: ^Builder_Database, operation: string) -> ! {
    panic(fmt.tprintf("search index %s failed: %s", operation,
        string(sqlite.connection_error_message(&database.connection))))
}

// Require one non-SQLite build invariant.
require :: proc(condition: bool, message: string) {
    if !condition {
        panic(message)
    }
}

// Require one exact SQLite status and retain the connection diagnostic.
require_sqlite :: proc(
    database: ^Builder_Database, failure: sqlite.Error, operation: string) {
    if failure.validation != .None || failure.result != .Ok {
        sqlite_fail(database, operation)
    }
}

// Execute one fixed repository-owned SQL program.
execute_sql :: proc(database: ^Builder_Database, sql: cstring) {
    require_sqlite(database,
        sqlite.connection_exec(&database.connection, sql), "schema operation")
}

// Prepare one statement and fail with the active connection diagnostic.
prepare_statement :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement, sql: cstring) {
    require_sqlite(database, sqlite.statement_prepare(
        &database.connection, statement, sql), "statement preparation")
}

// Prepare one temporary validation statement with persistent VM policy.
prepare_temporary_statement :: proc(
    database: ^Builder_Database, sql: cstring) -> sqlite.Statement {
    statement: sqlite.Statement
    prepare_statement(database, &statement, sql)
    return statement
}

// Require one exact row or completion result from a statement.
require_step :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    expected: sqlite.Step_Status, operation: string) {
    actual, failure := sqlite.statement_step(statement)
    if actual != expected {
        if failure.validation != .None || failure.result != .Ok {
            sqlite_fail(database, operation)
        }
        panic(fmt.tprintf("search index %s returned an unexpected row state", operation))
    }
}

// Require one checked integer column to fit in i32.
column_i32 :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement, column: int,
    operation: string) -> i32 {
    value, failure := sqlite.column_i32(statement, column)
    require_sqlite(database, failure, operation)
    return value
}

// Copy one exact text column into fixed caller-owned storage.
column_text :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    column: int, destination: []u8, operation: string) -> int {
    count, failure := sqlite.column_text_copy(statement, column, destination)
    require_sqlite(database, failure, operation)
    return count
}

// Reset one reusable statement and remove all prior bindings.
reset_statement :: proc(database: ^Builder_Database, statement: ^sqlite.Statement) {
    require_sqlite(database, sqlite.statement_reset(statement), "statement reset")
}

// Bind one copied UTF-8 value to a prepared statement.
bind_text :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    index: int, value: string) {
    require_sqlite(database,
        sqlite.statement_bind_text(statement, index, value), "text binding")
}

// Bind one checked 32-bit integer to a prepared statement.
bind_i32 :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    index: int, value: i32, operation: string) {
    require_sqlite(database,
        sqlite.statement_bind_i32(statement, index, value), operation)
}

// Bind SQL NULL to a prepared statement.
bind_null :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    index: int, operation: string) {
    require_sqlite(database,
        sqlite.statement_bind_null(statement, index), operation)
}

// Finalize one statement while preserving the builder's fail-fast diagnostics.
finalize_statement :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement) {
    require_sqlite(database, sqlite.statement_finalize(statement), "finalize")
}

// Join aliases into one FTS token stream without inventing vocabulary.
joined_aliases :: proc(aliases: []string) -> string {
    builder := strings.builder_make(context.temp_allocator)
    for alias, index in aliases {
        if index > 0 {
            strings.write_byte(&builder, '\n')
        }
        strings.write_string(&builder, alias)
    }
    return strings.to_string(builder)
}

// Return the UTF-8 value and presence flag for one nullable corpus field.
optional_string_value :: proc(value: Corpus_Optional_String) -> (string, bool) {
    switch item in value {
    case json.Null:
        return "", false
    case string:
        return item, true
    }
    return "", false
}

// Validate one lowercase canonical UUID string.
valid_animation_id :: proc(value: string) -> bool {
    if len(value) != 36 {
        return false
    }
    for character, index in transmute([]u8)value {
        if index == 8 || index == 13 || index == 18 || index == 23 {
            if character != '-' {
                return false
            }
        } else if !(character >= '0' && character <= '9' ||
            character >= 'a' && character <= 'f') {
            return false
        }
    }
    return true
}

// Require a package-relative implementation path with normalized components.
valid_implementation_path :: proc(value: string) -> bool {
    if len(value) == 0 || value[0] == '/' || value[len(value) - 1] == '/' {
        return false
    }
    component_start := 0
    for character, index in transmute([]u8)value {
        if character == '\\' || character == 0 {
            return false
        }
        if character == '/' || index == len(value) - 1 {
            component_end := index
            if character != '/' {
                component_end += 1
            }
            component := value[component_start:component_end]
            if len(component) == 0 || component == "." || component == ".." {
                return false
            }
            component_start = index + 1
        }
    }
    return true
}

// Validate one canonical corpus record before database mutation.
validate_record :: proc(record: Corpus_Record, previous_id: string) {
    parent_id, has_parent := optional_string_value(record.parent_animation_id)
    implementation_path, has_implementation :=
        optional_string_value(record.implementation_path)
    require(record.schema == CORPUS_SCHEMA_VERSION, "invalid corpus schema")
    require(record.source_namespace == "builtin", "invalid source namespace")
    require(valid_animation_id(record.animation_id), "invalid animation id")
    require(!has_parent || valid_animation_id(parent_id), "invalid parent animation id")
    require(len(record.display_name) > 0, "empty display name")
    require(len(record.hierarchy_path) > 0, "empty hierarchy path")
    require(record.node_kind >= 1 && record.node_kind <= 3, "invalid node kind")
    require(record.sibling_order >= 0, "invalid sibling order")
    require(record.catalog_order >= 0, "invalid catalog order")
    require(record.node_kind == 3 && !has_implementation ||
        record.node_kind != 3 && has_implementation &&
        valid_implementation_path(implementation_path),
        "invalid implementation path and node kind")
    require(len(record.display_name) <= 256 &&
        len(record.hierarchy_path) <= 2 * 1024 &&
        (!has_implementation || len(implementation_path) <= 2 * 1024),
        "catalogue string exceeds capacity")
    require(record.node_kind != 3 ||
        len(record.semantic_text) == 0 && len(record.aliases) == 0,
        "Terminal must not have authored search content")
    require(record.node_kind == 3 || len(record.semantic_text) > 0,
        "path-backed document has empty semantic text")
    require(previous_id == "" ||
        strings.compare(previous_id, record.animation_id) < 0,
        "corpus animation order is not strictly increasing")
}

// Bind catalogue identity, parent, kind, and display name columns.
bind_catalog_identity :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    record: Corpus_Record) {
    parent_id, has_parent := optional_string_value(record.parent_animation_id)
    bind_text(database, statement, 1, record.source_namespace)
    bind_text(database, statement, 2, record.animation_id)
    if has_parent {
        bind_text(database, statement, 3, parent_id)
    } else {
        bind_null(database, statement, 3, "parent-id binding")
    }
    bind_i32(database, statement, 4, i32(record.node_kind), "node-kind binding")
    bind_text(database, statement, 5, record.display_name)
}

// Bind sibling order, catalogue order, and nullable implementation path columns.
bind_catalog_structure :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    record: Corpus_Record) {
    implementation_path, has_implementation :=
        optional_string_value(record.implementation_path)
    bind_i32(database, statement, 6, i32(record.sibling_order), "sibling-order binding")
    bind_i32(database, statement, 7, i32(record.catalog_order), "catalog-order binding")
    if has_implementation {
        bind_text(database, statement, 8, implementation_path)
    } else {
        bind_null(database, statement, 8, "implementation-path binding")
    }
}

// Bind and insert one validated catalogue row.
insert_catalog_record :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    record: Corpus_Record, aliases: string) {
    bind_catalog_identity(database, statement, record)
    bind_catalog_structure(database, statement, record)
    bind_text(database, statement, 9, record.hierarchy_path)
    bind_text(database, statement, 10, aliases)
    bind_text(database, statement, 11, record.semantic_text)
    require_step(database, statement, .Done, "document insertion")
    reset_statement(database, statement)
}

// Insert one record's normalized search vocabulary text.
insert_plain_search_text :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    record: Corpus_Record, aliases: string) {
    vocabulary_text := fmt.tprintf("%s\n%s\n%s\n%s", record.display_name,
        record.hierarchy_path, aliases, record.semantic_text)
    bind_text(database, statement, 1, vocabulary_text)
    require_step(database, statement, .Done, "vocabulary insertion")
    reset_statement(database, statement)
}

// Insert one validated catalogue record and its spelling-index vocabulary.
insert_record :: proc(
    database: ^Builder_Database,
    catalog_statement, plain_statement: ^sqlite.Statement,
    record: Corpus_Record) {
    aliases := joined_aliases(record.aliases)
    insert_catalog_record(database, catalog_statement, record, aliases)
    insert_plain_search_text(database, plain_statement, record, aliases)
}

// Parse and insert every bounded JSON Lines corpus record.
insert_corpus :: proc(
    database: ^Builder_Database, source: string,
    document_statement, plain_statement: ^sqlite.Statement) -> int {
    count := 0
    previous_id := ""
    line_start := 0
    bytes := transmute([]u8)source
    for line_end := 0; line_end <= len(bytes); line_end += 1 {
        if line_end < len(bytes) && bytes[line_end] != '\n' {
            continue
        }
        line := source[line_start:line_end]
        line_start = line_end + 1
        if len(line) == 0 {
            continue
        }
        require(len(line) <= CORPUS_LINE_MAX_BYTES,
            "corpus line exceeds capacity")
        record: Corpus_Record
        require(json.unmarshal_string(
            line, &record, allocator = context.temp_allocator) == nil,
            "invalid corpus JSON")
        validate_record(record, previous_id)
        insert_record(database, document_statement, plain_statement, record)
        previous_id = record.animation_id
        count += 1
    }
    return count
}

// Insert one metadata key and copied value through the fixed statement.
insert_metadata :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    key, value: string) {
    bind_text(database, statement, 1, key)
    bind_text(database, statement, 2, value)
    require_step(database, statement, .Done, "metadata insertion")
    reset_statement(database, statement)
}

// Require SQLite to report no foreign-key violations.
validate_foreign_keys :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database, "PRAGMA foreign_key_check")
    require_step(database, &statement, .Done, "foreign-key check")
    finalize_statement(database, &statement)

}

// Require the catalogue count and explicit total ordering to be complete.
validate_catalog_order :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(
        database, "SELECT count(*) FROM animation_catalog")
    require_step(database, &statement, .Row, "count check")
    require(column_i32(database, &statement, 0, "count read") == EXPECTED_DOCUMENT_COUNT,
        "catalog record count mismatch")
    finalize_statement(database, &statement)

    statement = prepare_temporary_statement(database,
        "SELECT min(catalog_order), max(catalog_order), " +
        "count(DISTINCT catalog_order) FROM animation_catalog")
    require_step(database, &statement, .Row, "catalog-order check")
    require(column_i32(database, &statement, 0, "minimum order read") == 0 &&
        column_i32(database, &statement, 1, "maximum order read") ==
            EXPECTED_DOCUMENT_COUNT - 1 &&
        column_i32(database, &statement, 2, "distinct order count read") ==
            EXPECTED_DOCUMENT_COUNT,
        "catalog order is not contiguous")
    finalize_statement(database, &statement)

}

// Require one pathless Terminal row and a consistent external-content FTS index.
validate_catalog_special_rows :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database,
        "SELECT count(*) FROM animation_catalog WHERE node_kind = 3 " +
        "AND implementation_path IS NULL")
    require_step(database, &statement, .Row, "Terminal count check")
    require(column_i32(database, &statement, 0, "Terminal count read") == 1,
        "catalog must contain exactly one Terminal")
    finalize_statement(database, &statement)

    execute_sql(database,
        "INSERT INTO animation_search(animation_search, rank) " +
        "VALUES('integrity-check', 1)")
}

// Require searchable and spellfix vocabularies to be populated.
validate_search_vocabulary :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database,
        "SELECT count(*) FROM animation_search WHERE animation_search MATCH 'geometry'")
    require_step(database, &statement, .Row, "query check")
    require(column_i32(database, &statement, 0, "query count read") > 0,
        "representative query is empty")
    finalize_statement(database, &statement)

    statement = prepare_temporary_statement(
        database, "SELECT count(*) FROM search_terms")
    require_step(database, &statement, .Row, "spellfix vocabulary check")
    require(column_i32(database, &statement, 0, "spellfix count read") > 0,
        "spellfix vocabulary is empty")
    finalize_statement(database, &statement)
}

// Validate SQLite integrity, catalogue relations, completeness, and indexes.
validate_database :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database,
        "SELECT integrity_check FROM pragma_integrity_check")
    require_step(database, &statement, .Row, "integrity check")
    integrity: [16]u8
    integrity_count := column_text(
        database, &statement, 0, integrity[:], "integrity result read")
    require(string(integrity[:integrity_count]) == "ok",
        "search index integrity check failed")
    finalize_statement(database, &statement)
    validate_foreign_keys(database)
    validate_catalog_order(database)
    validate_catalog_special_rows(database)
    validate_search_vocabulary(database)
}

// Insert the versioned metadata rows through the builder's named statement.
insert_database_metadata :: proc(
    database: ^Builder_Database, count: int, corpus_fingerprint: string) {
    prepare_statement(database, &database.statements.metadata_insert,
        cstring(METADATA_INSERT_SQL))
    insert_metadata(database, &database.statements.metadata_insert, "schema_version", "2")
    insert_metadata(database, &database.statements.metadata_insert, "sqlite_version", "3.53.4")
    insert_metadata(database, &database.statements.metadata_insert,
        "catalog_fingerprint", corpus_fingerprint)
    insert_metadata(database, &database.statements.metadata_insert,
        "document_count", fmt.tprintf("%d", count))
    insert_metadata(database, &database.statements.metadata_insert,
        "tokenizer_version", "porter-unicode61-v1")
    insert_metadata(database, &database.statements.metadata_insert,
        "query_contract_version", "1")
    insert_metadata(database, &database.statements.metadata_insert,
        "index_generation", corpus_fingerprint)
    finalize_statement(database, &database.statements.metadata_insert)
}

// Populate the immutable index and its versioned metadata transactionally.
build_database :: proc(
    database: ^Builder_Database, source: string, corpus_fingerprint: string) {
    require_sqlite(database,
        sqlite.connection_register_spellfix(&database.connection),
        "spellfix registration")
    execute_sql(database, SCHEMA_SQL)
    execute_sql(database, "BEGIN IMMEDIATE")
    prepare_statement(database, &database.statements.catalog_insert,
        cstring(CATALOG_INSERT_SQL))
    prepare_statement(database, &database.statements.plain_insert,
        cstring(PLAIN_INSERT_SQL))
    count := insert_corpus(database, source,
        &database.statements.catalog_insert, &database.statements.plain_insert)
    require(count == EXPECTED_DOCUMENT_COUNT, "canonical corpus is incomplete")
    finalize_statement(database, &database.statements.catalog_insert)
    finalize_statement(database, &database.statements.plain_insert)
    execute_sql(database,
        "INSERT INTO animation_search(animation_search) VALUES('rebuild')")
    execute_sql(database,
        "INSERT INTO search_terms(word, rank) " +
        "SELECT term, 1000000 - min(cnt, 999999) " +
        "FROM plain_search_vocabulary ORDER BY term")
    insert_database_metadata(database, count, corpus_fingerprint)
    execute_sql(database, "DROP TABLE plain_search_vocabulary; DROP TABLE plain_search")
    execute_sql(database, "COMMIT")
    validate_database(database)
    execute_sql(database, "VACUUM")
}

// Build one validated SQLite database from a canonical corpus file.
main :: proc() {
    require(len(os.args) == 4,
        "usage: search_index_builder INPUT.jsonl OUTPUT.sqlite3 FINGERPRINT")
    source_bytes, read_error := os.read_entire_file(os.args[1], context.allocator)
    require(read_error == nil, "could not read canonical search corpus")
    defer delete(source_bytes)
    require(len(source_bytes) <= CORPUS_MAX_BYTES,
        "search corpus exceeds capacity")
    _ = os.remove(os.args[2])
    database: Builder_Database
    open_failure := sqlite.connection_open(
        &database.connection, os.args[2], .Readwrite_Create, context.temp_allocator)
    require(open_failure.validation == .None && open_failure.result == .Ok,
        "could not create search database")
    build_database(&database, transmute(string)source_bytes, os.args[3])
    require_sqlite(&database, sqlite.connection_close(&database.connection), "close")
}