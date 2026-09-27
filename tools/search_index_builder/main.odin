package main

import sqlite3 "../../libs/sqlite3"

import "core:c"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

CORPUS_SCHEMA_VERSION :: 1
CORPUS_MAX_BYTES :: 2 * 1024 * 1024
CORPUS_LINE_MAX_BYTES :: 16 * 1024
EXPECTED_DOCUMENT_COUNT :: 138

Corpus_Record :: struct {
    schema: int,
    source_namespace: string,
    document_id: string,
    node_kind: int,
    display_name: string,
    hierarchy_path: string,
    semantic_text: string,
    aliases: []string,
}

SCHEMA_SQL :: `
PRAGMA page_size=4096;
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
PRAGMA temp_store=MEMORY;
CREATE TABLE search_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE search_documents (
    rowid INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    document_id TEXT NOT NULL,
    node_kind INTEGER NOT NULL,
    display_name TEXT NOT NULL,
    hierarchy_path TEXT NOT NULL,
    aliases TEXT NOT NULL,
    semantic_text TEXT NOT NULL,
    UNIQUE (source_namespace, document_id)
);
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name,
    hierarchy_path,
    aliases,
    semantic_text,
    content='search_documents',
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

DOCUMENT_INSERT_SQL :: `INSERT INTO search_documents(
    source_namespace, document_id, node_kind, display_name,
    hierarchy_path, aliases, semantic_text)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`

PLAIN_INSERT_SQL :: "INSERT INTO plain_search(content) VALUES (?1)"
METADATA_INSERT_SQL :: "INSERT INTO search_metadata(key, value) VALUES (?1, ?2)"

// Fail the build with SQLite's connection-owned diagnostic text.
sqlite_fail :: proc(database: ^sqlite3.Database, operation: string) -> ! {
    panic(fmt.tprintf("search index %s failed: %s", operation,
        string(sqlite3.sqlite3_errmsg(database))))
}

// Require one non-SQLite build invariant.
require :: proc(condition: bool, message: string) {
    if !condition {
        panic(message)
    }
}

// Require one exact SQLite status and retain the connection diagnostic.
require_sqlite :: proc(
    database: ^sqlite3.Database, actual, expected: sqlite3.Result,
    operation: string) {
    if actual != expected {
        sqlite_fail(database, operation)
    }
}

// Execute one fixed repository-owned SQL program.
execute_sql :: proc(database: ^sqlite3.Database, sql: cstring) {
    error_message: cstring
    status := sqlite3.sqlite3_exec(database, sql, nil, nil, &error_message)
    if error_message != nil {
        defer sqlite3.sqlite3_free(rawptr(error_message))
    }
    require_sqlite(database, status, .Ok, "schema operation")
}

// Prepare one persistent repository-owned statement.
prepare_statement :: proc(
    database: ^sqlite3.Database, sql: cstring) -> ^sqlite3.Statement {
    statement: ^sqlite3.Statement
    status := sqlite3.sqlite3_prepare_v3(database, sql, -1,
        c.uint(sqlite3.Prepare_Flag.Persistent), &statement, nil)
    require_sqlite(database, status, .Ok, "statement preparation")
    return statement
}

// Reset one reusable statement and remove all prior bindings.
reset_statement :: proc(database: ^sqlite3.Database, statement: ^sqlite3.Statement) {
    require_sqlite(database, sqlite3.sqlite3_reset(statement), .Ok,
        "statement reset")
    require_sqlite(database, sqlite3.sqlite3_clear_bindings(statement), .Ok,
        "binding clearance")
}

// Bind one copied UTF-8 value to a prepared statement.
bind_text :: proc(
    database: ^sqlite3.Database, statement: ^sqlite3.Statement,
    index: c.int, value: string) {
    encoded := strings.clone_to_cstring(value, context.temp_allocator)
    status := sqlite3.sqlite3_bind_text(statement, index, encoded,
        c.int(len(value)), sqlite3.transient_destructor())
    require_sqlite(database, status, .Ok, "text binding")
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

// Validate one canonical corpus record before database mutation.
validate_record :: proc(record: Corpus_Record, previous_id: string) {
    require(record.schema == CORPUS_SCHEMA_VERSION, "invalid corpus schema")
    require(record.source_namespace == "builtin", "invalid source namespace")
    require(len(record.document_id) == 36, "invalid document id")
    require(len(record.display_name) > 0, "empty display name")
    require(len(record.hierarchy_path) > 0, "empty hierarchy path")
    require(record.node_kind >= 1 && record.node_kind <= 3, "invalid node kind")
    require(record.node_kind != 3 ||
        len(record.semantic_text) == 0 && len(record.aliases) == 0,
        "Terminal must not have authored search content")
    require(record.node_kind == 3 || len(record.semantic_text) > 0,
        "path-backed document has empty semantic text")
    require(previous_id == "" ||
        strings.compare(previous_id, record.document_id) < 0,
        "corpus document order is not strictly increasing")
}

// Bind and insert one validated document and its plain vocabulary text.
insert_record :: proc(
    database: ^sqlite3.Database, document_statement: ^sqlite3.Statement,
    plain_statement: ^sqlite3.Statement, record: Corpus_Record) {
    aliases := joined_aliases(record.aliases)
    bind_text(database, document_statement, 1, record.source_namespace)
    bind_text(database, document_statement, 2, record.document_id)
    require_sqlite(database, sqlite3.sqlite3_bind_int(
        document_statement, 3, c.int(record.node_kind)), .Ok,
        "node-kind binding")
    bind_text(database, document_statement, 4, record.display_name)
    bind_text(database, document_statement, 5, record.hierarchy_path)
    bind_text(database, document_statement, 6, aliases)
    bind_text(database, document_statement, 7, record.semantic_text)
    require_sqlite(database, sqlite3.sqlite3_step(document_statement), .Done,
        "document insertion")
    reset_statement(database, document_statement)

    vocabulary_text := fmt.tprintf("%s\n%s\n%s\n%s", record.display_name,
        record.hierarchy_path, aliases, record.semantic_text)
    bind_text(database, plain_statement, 1, vocabulary_text)
    require_sqlite(database, sqlite3.sqlite3_step(plain_statement), .Done,
        "vocabulary insertion")
    reset_statement(database, plain_statement)
}

// Parse and insert every bounded JSON Lines corpus record.
insert_corpus :: proc(
    database: ^sqlite3.Database, source: string,
    document_statement, plain_statement: ^sqlite3.Statement) -> int {
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
        previous_id = record.document_id
        count += 1
    }
    return count
}

// Insert one metadata key and copied value through the fixed statement.
insert_metadata :: proc(
    database: ^sqlite3.Database, statement: ^sqlite3.Statement,
    key, value: string) {
    bind_text(database, statement, 1, key)
    bind_text(database, statement, 2, value)
    require_sqlite(database, sqlite3.sqlite3_step(statement), .Done,
        "metadata insertion")
    reset_statement(database, statement)
}

// Validate integrity, completeness, and one representative FTS query.
validate_database :: proc(database: ^sqlite3.Database) {
    statement := prepare_statement(database,
        "SELECT integrity_check FROM pragma_integrity_check")
    require_sqlite(database, sqlite3.sqlite3_step(statement), .Row,
        "integrity check")
    require(string(sqlite3.sqlite3_column_text(statement, 0)) == "ok",
        "search index integrity check failed")
    require_sqlite(database, sqlite3.sqlite3_finalize(statement), .Ok, "finalize")

    statement = prepare_statement(database,
        "SELECT count(*) FROM search_documents")
    require_sqlite(database, sqlite3.sqlite3_step(statement), .Row, "count check")
    require(sqlite3.sqlite3_column_int(statement, 0) == EXPECTED_DOCUMENT_COUNT,
        "search index document count mismatch")
    require_sqlite(database, sqlite3.sqlite3_finalize(statement), .Ok, "finalize")

    statement = prepare_statement(database,
        "SELECT count(*) FROM animation_search WHERE animation_search MATCH 'geometry'")
    require_sqlite(database, sqlite3.sqlite3_step(statement), .Row, "query check")
    require(sqlite3.sqlite3_column_int(statement, 0) > 0,
        "representative query is empty")
    require_sqlite(database, sqlite3.sqlite3_finalize(statement), .Ok, "finalize")

    statement = prepare_statement(database, "SELECT count(*) FROM search_terms")
    require_sqlite(database, sqlite3.sqlite3_step(statement), .Row,
        "spellfix vocabulary check")
    require(sqlite3.sqlite3_column_int(statement, 0) > 0,
        "spellfix vocabulary is empty")
    require_sqlite(database, sqlite3.sqlite3_finalize(statement), .Ok, "finalize")
}

// Populate the immutable index and its versioned metadata transactionally.
build_database :: proc(
    database: ^sqlite3.Database, source: string, corpus_fingerprint: string) {
    require_sqlite(database, sqlite3.euclid_sqlite_register_spellfix(database),
        .Ok, "spellfix registration")
    execute_sql(database, SCHEMA_SQL)
    execute_sql(database, "BEGIN IMMEDIATE")
    documents := prepare_statement(database, DOCUMENT_INSERT_SQL)
    plain := prepare_statement(database, PLAIN_INSERT_SQL)
    count := insert_corpus(database, source, documents, plain)
    require(count == EXPECTED_DOCUMENT_COUNT, "canonical corpus is incomplete")
    require_sqlite(database, sqlite3.sqlite3_finalize(documents), .Ok, "finalize")
    require_sqlite(database, sqlite3.sqlite3_finalize(plain), .Ok, "finalize")
    execute_sql(database,
        "INSERT INTO animation_search(animation_search) VALUES('rebuild')")
    execute_sql(database,
        "INSERT INTO search_terms(word, rank) " +
        "SELECT term, 1000000 - min(cnt, 999999) " +
        "FROM plain_search_vocabulary ORDER BY term")
    metadata := prepare_statement(database, METADATA_INSERT_SQL)
    insert_metadata(database, metadata, "schema_version", "1")
    insert_metadata(database, metadata, "sqlite_version", "3.53.4")
    insert_metadata(database, metadata, "catalog_fingerprint", corpus_fingerprint)
    insert_metadata(database, metadata, "document_count", fmt.tprintf("%d", count))
    insert_metadata(database, metadata, "tokenizer_version", "porter-unicode61-v1")
    insert_metadata(database, metadata, "query_contract_version", "1")
    insert_metadata(database, metadata, "index_generation", corpus_fingerprint)
    require_sqlite(database, sqlite3.sqlite3_finalize(metadata), .Ok, "finalize")
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
    database: ^sqlite3.Database
    output_path := strings.clone_to_cstring(os.args[2], context.temp_allocator)
    flags := c.int(sqlite3.Open_Flag.Readwrite) | c.int(sqlite3.Open_Flag.Create)
    require(sqlite3.sqlite3_open_v2(output_path, &database, flags, nil) == .Ok,
        "could not create search database")
    build_database(database, transmute(string)source_bytes, os.args[3])
    require_sqlite(database, sqlite3.sqlite3_close(database), .Ok, "close")
}