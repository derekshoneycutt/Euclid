package main

import sqlite "../../src/sqlite"

import "core:crypto/sha2"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

CONTENT_CORPUS_SCHEMA_VERSION :: 3
CONTENT_MAX_BYTES :: 4 * 1024 * 1024
CONTENT_LINE_MAX_BYTES :: 16 * 1024
EXPECTED_LOCALE_COUNT :: 1
EXPECTED_MESSAGE_COUNT :: 74
EXPECTED_TRANSLATION_COUNT :: 74
EXPECTED_SUBJECT_COUNT :: 139
EXPECTED_CATALOG_NODE_COUNT :: 138
EXPECTED_CATALOG_NAME_COUNT :: 138
EXPECTED_EDITION_COUNT :: 3
EXPECTED_AVAILABILITY_COUNT :: 139
EXPECTED_PROJECTION_COUNT :: 138
SOURCE_METADATA_COUNT :: 6

RECORD_FIELD_COUNTS :: [12]int{0, 4, 4, 5, 6, 5, 4, 9, 6, 6, 7, 10}
RECORD_FIELDS :: [12][10]string{
    {},
    {"schema", "kind", "key", "value", "", "", "", "", "", ""},
    {"schema", "kind", "tag", "is_default", "", "", "", "", "", ""},
    {"schema", "kind", "message_key", "native_message_id", "developer_context",
        "", "", "", "", ""},
    {"schema", "kind", "message_key", "ordinal", "argument_name", "argument_type",
        "", "", "", ""},
    {"schema", "kind", "locale_tag", "message_key", "template", "", "", "", "", ""},
    {"schema", "kind", "source_namespace", "animation_id", "", "", "", "", "", ""},
    {"schema", "kind", "source_namespace", "animation_id", "parent_animation_id",
        "node_kind", "sibling_order", "catalog_order", "implementation_path", ""},
    {"schema", "kind", "source_namespace", "animation_id", "locale_tag", "display_name",
        "", "", "", ""},
    {"schema", "kind", "edition_id", "unique_name", "text_language_tag", "description",
        "", "", "", ""},
    {"schema", "kind", "source_namespace", "animation_id", "locale_tag",
        "edition_id", "is_default", "", "", ""},
    {"schema", "kind", "source_namespace", "animation_id", "locale_tag", "edition_id",
        "display_name", "hierarchy_path", "semantic_text", "aliases"},
}

Content_Optional_String :: union {
    json.Null,
    string,
}

Content_Record :: struct {
    schema: int,
    kind: int,
    key: string,
    value: string,
    tag: string,
    is_default: bool,
    message_key: string,
    native_message_id: int,
    developer_context: string,
    ordinal: int,
    argument_name: string,
    argument_type: string,
    locale_tag: string,
    template: string,
    source_namespace: string,
    animation_id: string,
    parent_animation_id: Content_Optional_String,
    node_kind: int,
    sibling_order: int,
    catalog_order: int,
    implementation_path: Content_Optional_String,
    display_name: string,
    edition_id: string,
    unique_name: string,
    text_language_tag: string,
    description: string,
    hierarchy_path: string,
    semantic_text: string,
    aliases: []string,
}

Message_Signature :: struct {
    count: int,
    names: [2]string,
}

Message_Entry :: struct {
    key: string,
    signature: Message_Signature,
}

Message_Signatures :: struct {
    count: int,
    entries: [80]Message_Entry,
}

SCHEMA_SQL :: #load("sql/schema.sql", string)
METADATA_INSERT_SQL :: #load("sql/metadata_insert.sql", string)
LOCALE_INSERT_SQL :: #load("sql/locale_insert.sql", string)
MESSAGE_INSERT_SQL :: #load("sql/message_insert.sql", string)
ARGUMENT_INSERT_SQL :: #load("sql/argument_insert.sql", string)
TRANSLATION_INSERT_SQL :: #load("sql/translation_insert.sql", string)
SUBJECT_INSERT_SQL :: #load("sql/subject_insert.sql", string)
NODE_INSERT_SQL :: #load("sql/node_insert.sql", string)
NAME_INSERT_SQL :: #load("sql/name_insert.sql", string)
EDITION_INSERT_SQL :: #load("sql/edition_insert.sql", string)
AVAILABILITY_INSERT_SQL :: #load("sql/availability_insert.sql", string)
PROJECTION_INSERT_SQL :: #load("sql/projection_insert.sql", string)
PLAIN_INSERT_SQL :: #load("sql/plain_insert.sql", string)

Builder_Statements :: struct {
    metadata: sqlite.Statement,
    locale: sqlite.Statement,
    message: sqlite.Statement,
    argument: sqlite.Statement,
    translation: sqlite.Statement,
    subject: sqlite.Statement,
    node: sqlite.Statement,
    name: sqlite.Statement,
    edition: sqlite.Statement,
    availability: sqlite.Statement,
    projection: sqlite.Statement,
    plain: sqlite.Statement,
}

Builder_Database :: struct {
    connection: sqlite.Connection,
    statements: Builder_Statements,
    counts: [12]int,
}

// Fail with the active SQLite connection's diagnostic text.
sqlite_fail :: proc(database: ^Builder_Database, operation: string) -> ! {
    panic(fmt.tprintf("content database %s failed: %s", operation,
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

// Prepare one fixed statement and fail with the active connection diagnostic.
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
        panic(fmt.tprintf(
            "content database %s returned an unexpected row state", operation))
    }
}

// Read one checked integer column from the active SQLite connection.
column_i32 :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    column: int, operation: string) -> i32 {
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
    index: int, value: int, operation: string) {
    require_sqlite(database,
        sqlite.statement_bind_i32(statement, index, i32(value)), operation)
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

// Return a nullable string value and its presence flag.
optional_string_value :: proc(value: Content_Optional_String) -> (string, bool) {
    switch item in value {
    case json.Null:
        return "", false
    case string:
        return item, true
    }
    return "", false
}

// Reject invalid bounded text values before they reach persistent storage.
validate_text :: proc(value, label: string, capacity: int, allow_empty: bool) {
    require(utf8.valid_string(value),
        fmt.tprintf("%s is not valid UTF-8", label))
    require(len(value) <= capacity,
        fmt.tprintf("%s exceeds byte capacity", label))
    require(strings.index_byte(value, 0) < 0,
        fmt.tprintf("%s contains NUL", label))
    require(allow_empty || len(value) > 0,
        fmt.tprintf("%s is empty", label))
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

// Verify the supplied whole-record-stream SHA-256 identity.
valid_content_fingerprint :: proc(source, expected: string) -> bool {
    if len(expected) != 64 {
        return false
    }
    hash := sha2.Context_256{}
    sha2.init_256(&hash)
    sha2.update(&hash, transmute([]u8)source)
    digest: [32]byte
    sha2.final(&hash, digest[:])
    HEX :: "0123456789abcdef"
    hexadecimal := HEX
    for value, index in digest {
        if expected[index * 2] != hexadecimal[value >> 4] ||
            expected[index * 2 + 1] != hexadecimal[value & 0x0f] {
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

// Return the exact number of fields for one canonical record kind.
expected_record_field_count :: proc(kind: int) -> int {
    if kind < 1 || kind >= len(RECORD_FIELD_COUNTS) {
        return 0
    }
    counts := RECORD_FIELD_COUNTS
    return counts[kind]
}

// Return one required field name at its canonical position.
expected_record_field :: proc(kind, index: int) -> string {
    require(index >= 0 && index < expected_record_field_count(kind),
        "canonical content record field index is invalid")
    fields := RECORD_FIELDS
    return fields[kind][index]
}

// Find the closing quote of a validated JSON string without treating escapes as quotes.
json_string_end :: proc(line: string, start: int) -> int {
    escaped := false
    for index := start + 1; index < len(line); index += 1 {
        character := line[index]
        if escaped {
            escaped = false
        } else if character == '\\' {
            escaped = true
        } else if character == '"' {
            return index
        }
    }
    return len(line)
}

// Find the end of one validated JSON value while respecting strings and arrays.
json_value_end :: proc(line: string, start: int) -> int {
    depth := 0
    for index := start; index < len(line); index += 1 {
        character := line[index]
        require(character != ' ' && character != '\t' &&
            character != '\r' && character != '\n',
            "content record JSON is not compact")
        switch character {
        case '"':
            index = json_string_end(line, index)
        case '[', '{':
            depth += 1
        case ']':
            depth -= 1
        case '}':
            if depth == 0 {
                return index
            }
            depth -= 1
        case ',':
            if depth == 0 {
                return index
            }
        }
    }
    return len(line)
}

// Reject unknown, duplicate, reordered, or non-compact top-level JSON fields.
validate_record_shape :: proc(line: string, kind: int) {
    field_count := expected_record_field_count(kind)
    require(field_count > 0 && len(line) > 1 && line[0] == '{',
        "invalid canonical content record shape")
    position := 1
    for index in 0..<field_count {
        field := expected_record_field(kind, index)
        require(position < len(line) && line[position] == '"',
            "canonical content record field is missing")
        key_start := position + 1
        key_end := key_start
        for key_end < len(line) && line[key_end] != '"' {
            require(line[key_end] != '\\',
                "canonical content record keys cannot be escaped")
            key_end += 1
        }
        require(key_end < len(line) && line[key_start:key_end] == field,
            "canonical content record fields are unknown or out of order")
        position = key_end + 1
        require(position < len(line) && line[position] == ':',
            "canonical content record field separator is missing")
        position = json_value_end(line, position + 1)
        if index + 1 < field_count {
            require(position < len(line) && line[position] == ',',
                "canonical content record field separator is invalid")
            position += 1
        }
    }
    require(position == len(line) - 1 && line[position] == '}',
        "canonical content record has trailing or missing fields")
}

// Derive a stable record identity for order and duplicate detection.
record_identity :: proc(record: Content_Record) -> string {
    switch record.kind {
    case 1: return record.key
    case 2: return record.tag
    case 3: return record.message_key
    case 4: return fmt.tprintf("%s|%02d", record.message_key, record.ordinal)
    case 5: return fmt.tprintf("%s|%s", record.locale_tag, record.message_key)
    case 6, 7: return fmt.tprintf("%s|%s",
        record.source_namespace, record.animation_id)
    case 8: return fmt.tprintf("%s|%s|%s",
        record.source_namespace, record.animation_id, record.locale_tag)
    case 9: return record.edition_id
    case 10, 11: return fmt.tprintf("%s|%s|%s|%s",
        record.source_namespace, record.animation_id,
        record.locale_tag, record.edition_id)
    }
    return ""
}

// Accept a bounded placeholder identifier with a lowercase initial letter.
valid_argument_name :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > 32 ||
        !(name[0] >= 'a' && name[0] <= 'z') {
        return false
    }
    for character in transmute([]u8)name {
        if !(character >= 'a' && character <= 'z' ||
            character >= '0' && character <= '9' || character == '_') {
            return false
        }
    }
    return true
}

// Retain each distinct placeholder once without growing bounded signature storage.
append_template_argument :: proc(signature: ^Message_Signature, name: string) -> bool {
    for existing in signature.names[:signature.count] {
        if existing == name {
            return true
        }
    }
    if signature.count == len(signature.names) {
        return false
    }
    signature.names[signature.count] = name
    signature.count += 1
    return true
}

// Parse the distinct brace-delimited arguments using the stable message grammar.
parse_template_signature :: proc(template: string) -> (Message_Signature, bool) {
    signature: Message_Signature
    index := 0
    for index < len(template) {
        if template[index] == '}' {
            return signature, false
        }
        if template[index] != '{' {
            index += 1
            continue
        }
        closing := strings.index_byte(template[index + 1:], '}')
        if closing < 0 {
            return signature, false
        }
        end := index + 1 + closing
        name := template[index + 1:end]
        if !valid_argument_name(name) || !append_template_argument(&signature, name) {
            return signature, false
        }
        index = end + 1
    }
    return signature, true
}

// Require a translation's named placeholders to match its declared signature.
validate_translation_signature :: proc(
    record: Content_Record, signatures: ^Message_Signatures) {
    index, exists := find_message_signature(signatures, record.message_key)
    require(exists, "translation references an unknown message signature")
    signature := signatures.entries[index].signature
    actual_signature, valid := parse_template_signature(record.template)
    require(valid, "translation has malformed placeholder syntax")
    require(actual_signature.count == signature.count,
        "translation placeholder count does not match its signature")
    for expected in signature.names[:signature.count] {
        found := false
        for actual in actual_signature.names[:actual_signature.count] {
            found = found || expected == actual
        }
        require(found, "translation placeholders do not match its signature")
    }
}

// Find one message's bounded signature entry.
find_message_signature :: proc(
    signatures: ^Message_Signatures, key: string) -> (int, bool) {
    for index in 0..<signatures.count {
        if signatures.entries[index].key == key {
            return index, true
        }
    }
    return 0, false
}

// Validate source metadata, locale, and UI declaration payloads.
validate_ui_record :: proc(record: Content_Record) {
    switch record.kind {
    case 1:
        validate_text(record.key, "metadata key", 64, false)
        validate_text(record.value, "metadata value", 256, false)
    case 2:
        validate_text(record.tag, "locale tag", 35, false)
        require(record.tag == "en-US", "unsupported shipped locale")
    case 3:
        validate_text(record.message_key, "message key", 64, false)
        validate_text(record.developer_context, "message context", 256, false)
        require(record.native_message_id >= 1 && record.native_message_id <= 65535,
            "invalid native message ID")
    case 4:
        validate_text(record.message_key, "argument message key", 64, false)
        validate_text(record.argument_name, "argument name", 32, false)
        require(record.ordinal >= 0 && record.ordinal <= 1,
            "invalid argument ordinal")
        require(record.argument_type == "text" ||
            record.argument_type == "uint32" ||
            record.argument_type == "int64" ||
            record.argument_type == "float32_1dp",
            "invalid argument type")
    case 5:
        validate_text(record.locale_tag, "translation locale", 35, false)
        validate_text(record.message_key, "translation message key", 64, false)
        validate_text(record.template, "translation template", 128, false)
    }
}

// Validate catalogue topology, ordering, and optional implementation bindings.
validate_catalog_node :: proc(record: Content_Record) {
    validate_text(record.source_namespace, "catalogue namespace", 64, false)
    require(record.source_namespace == "builtin" &&
        valid_animation_id(record.animation_id),
        "invalid catalogue node identity")
    require(record.node_kind >= 1 && record.node_kind <= 3,
        "invalid catalogue node kind")
    require(record.sibling_order >= 0 && record.catalog_order >= 0,
        "invalid catalogue node ordering")
    parent_id, has_parent := optional_string_value(record.parent_animation_id)
    implementation_path, has_implementation :=
        optional_string_value(record.implementation_path)
    require(!has_parent || valid_animation_id(parent_id),
        "invalid catalogue parent identity")
    require(record.node_kind == 3 && !has_implementation ||
        record.node_kind != 3 && has_implementation &&
        valid_implementation_path(implementation_path),
        "invalid catalogue implementation path")
    if has_implementation {
        validate_text(implementation_path, "implementation path", 2048, false)
    }
}

// Validate projection text bounds and unique aliases before index derivation.
validate_projection :: proc(record: Content_Record) {
    validate_text(record.source_namespace, "projection namespace", 64, false)
    require(record.source_namespace == "builtin" &&
        valid_animation_id(record.animation_id),
        "invalid projection subject")
    validate_text(record.locale_tag, "projection locale", 35, false)
    validate_text(record.edition_id, "projection edition", 64, false)
    validate_text(record.display_name, "projection name", 256, false)
    validate_text(record.hierarchy_path, "projection hierarchy", 2048, false)
    validate_text(record.semantic_text, "projection semantic text", 8192, true)
    require(len(record.aliases) <= 16, "projection alias count exceeds capacity")
    for alias, index in record.aliases {
        validate_text(alias, "projection alias", 128, false)
        for prior in record.aliases[:index] {
            require(prior != alias, "duplicate search alias")
        }
    }
}

// Validate subject identities, localized names, and edition declarations.
validate_content_record :: proc(record: Content_Record) {
    switch record.kind {
    case 6:
        validate_text(record.source_namespace, "subject namespace", 64, false)
        require(record.source_namespace == "builtin" &&
            valid_animation_id(record.animation_id),
            "invalid content subject identity")
    case 7:
        validate_catalog_node(record)
    case 8:
        validate_text(record.source_namespace, "catalogue name namespace", 64, false)
        require(record.source_namespace == "builtin" &&
            valid_animation_id(record.animation_id),
            "invalid catalogue name identity")
        validate_text(record.locale_tag, "catalogue name locale", 35, false)
        validate_text(record.display_name, "catalogue display name", 256, false)
    case 9:
        validate_text(record.edition_id, "edition ID", 64, false)
        validate_text(record.unique_name, "edition name", 256, false)
        validate_text(record.text_language_tag, "edition language tag", 35, false)
        validate_text(record.description, "edition description", 1024, false)
    case 10:
        validate_text(record.source_namespace, "availability namespace", 64, false)
        require(record.source_namespace == "builtin" &&
            valid_animation_id(record.animation_id),
            "invalid availability subject")
        validate_text(record.locale_tag, "availability locale", 35, false)
        validate_text(record.edition_id, "availability edition", 64, false)
    case 11:
        validate_projection(record)
    }
}

// Validate the versioned envelope before routing to bounded payload validation.
validate_record :: proc(record: Content_Record) {
    require(record.schema == CONTENT_CORPUS_SCHEMA_VERSION,
        "unsupported content corpus schema")
    require(record.kind >= 1 && record.kind <= 11,
        "unknown content record kind")
    if record.kind <= 5 {
        validate_ui_record(record)
    } else {
        validate_content_record(record)
    }
}

// Bind one value and execute the named reusable insert statement.
insert_done :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement, operation: string) {
    require_step(database, statement, .Done, operation)
    reset_statement(database, statement)
}

// Insert a metadata key/value pair into the normalized declaration table.
insert_metadata :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    key, value: string, operation: string) {
    bind_text(database, statement, 1, key)
    bind_text(database, statement, 2, value)
    insert_done(database, statement, operation)
}

// Return the nullable text as SQL NULL or bind the supplied string.
bind_optional_text :: proc(
    database: ^Builder_Database, statement: ^sqlite.Statement,
    index: int, value: Content_Optional_String, operation: string) {
    text, present := optional_string_value(value)
    if present {
        bind_text(database, statement, index, text)
    } else {
        bind_null(database, statement, index, operation)
    }
}

// Join aliases into the unchanged newline-delimited search token stream.
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

// Insert one normalized locale record.
insert_locale :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.locale
    bind_text(database, statement, 1, record.tag)
    bind_i32(database, statement, 2, int(record.is_default), "locale default binding")
    insert_done(database, statement, "locale insertion")
}

// Insert one message record and initialize its signature accumulator.
insert_message :: proc(
    database: ^Builder_Database, record: Content_Record,
    signatures: ^Message_Signatures) {
    _, exists := find_message_signature(signatures, record.message_key)
    require(!exists && signatures.count < len(signatures.entries),
        "duplicate or excessive UI message signatures")
    statement := &database.statements.message
    bind_text(database, statement, 1, record.message_key)
    bind_i32(database, statement, 2, record.native_message_id, "native message ID binding")
    bind_text(database, statement, 3, record.developer_context)
    insert_done(database, statement, "message insertion")
    signatures.entries[signatures.count] = Message_Entry{
        key = record.message_key,
        signature = {},
    }
    signatures.count += 1
}

// Insert one ordered typed argument and update its message signature.
insert_argument :: proc(
    database: ^Builder_Database, record: Content_Record,
    signatures: ^Message_Signatures) {
    index, exists := find_message_signature(signatures, record.message_key)
    signature := signatures.entries[index].signature
    require(exists && record.ordinal == signature.count,
        "argument records are missing or out of order")
    require(signature.count < len(signature.names), "too many message arguments")
    signature.names[record.ordinal] = record.argument_name
    signature.count += 1
    signatures.entries[index].signature = signature
    statement := &database.statements.argument
    bind_text(database, statement, 1, record.message_key)
    bind_i32(database, statement, 2, record.ordinal, "argument ordinal binding")
    bind_text(database, statement, 3, record.argument_name)
    bind_text(database, statement, 4, record.argument_type)
    insert_done(database, statement, "argument insertion")
}

// Insert one validated locale/message translation.
insert_translation :: proc(
    database: ^Builder_Database, record: Content_Record,
    signatures: ^Message_Signatures) {
    validate_translation_signature(record, signatures)
    statement := &database.statements.translation
    bind_text(database, statement, 1, record.locale_tag)
    bind_text(database, statement, 2, record.message_key)
    bind_text(database, statement, 3, record.template)
    insert_done(database, statement, "translation insertion")
}

// Insert one content-subject identity.
insert_subject :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.subject
    bind_text(database, statement, 1, record.source_namespace)
    bind_text(database, statement, 2, record.animation_id)
    insert_done(database, statement, "subject insertion")
}

// Insert one catalogue node while deferring checked parent references.
insert_catalog_node :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.node
    bind_text(database, statement, 1, record.source_namespace)
    bind_text(database, statement, 2, record.animation_id)
    bind_optional_text(database, statement, 3, record.parent_animation_id, "parent binding")
    bind_i32(database, statement, 4, record.node_kind, "node kind binding")
    bind_i32(database, statement, 5, record.sibling_order, "sibling order binding")
    bind_i32(database, statement, 6, record.catalog_order, "catalogue order binding")
    bind_optional_text(database, statement, 7, record.implementation_path,
        "implementation path binding")
    insert_done(database, statement, "catalogue node insertion")
}

// Insert one locale-scoped catalogue display name.
insert_catalog_name :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.name
    bind_text(database, statement, 1, record.source_namespace)
    bind_text(database, statement, 2, record.animation_id)
    bind_text(database, statement, 3, record.locale_tag)
    bind_text(database, statement, 4, record.display_name)
    insert_done(database, statement, "catalogue name insertion")
}

// Insert one edition declaration with authored provenance.
insert_edition :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.edition
    bind_text(database, statement, 1, record.edition_id)
    bind_text(database, statement, 2, record.unique_name)
    bind_text(database, statement, 3, record.text_language_tag)
    bind_text(database, statement, 4, record.description)
    insert_done(database, statement, "edition insertion")
}

// Insert one subject/locale/edition availability declaration.
insert_availability :: proc(database: ^Builder_Database, record: Content_Record) {
    statement := &database.statements.availability
    bind_text(database, statement, 1, record.source_namespace)
    bind_text(database, statement, 2, record.animation_id)
    bind_text(database, statement, 3, record.locale_tag)
    bind_text(database, statement, 4, record.edition_id)
    bind_i32(database, statement, 5, int(record.is_default),
        "availability default binding")
    insert_done(database, statement, "availability insertion")
}

// Insert one search projection plus its exact historical FTS vocabulary input.
insert_projection :: proc(
    database: ^Builder_Database, record: Content_Record, projection_id: int) {
    aliases := joined_aliases(record.aliases)
    statement := &database.statements.projection
    bind_i32(database, statement, 1, projection_id, "projection ID binding")
    bind_text(database, statement, 2, record.source_namespace)
    bind_text(database, statement, 3, record.animation_id)
    bind_text(database, statement, 4, record.locale_tag)
    bind_text(database, statement, 5, record.edition_id)
    bind_text(database, statement, 6, record.display_name)
    bind_text(database, statement, 7, record.hierarchy_path)
    bind_text(database, statement, 8, record.semantic_text)
    bind_text(database, statement, 9, aliases)
    insert_done(database, statement, "search projection insertion")

    plain := &database.statements.plain
    vocabulary := fmt.tprintf("%s\n%s\n%s\n%s", record.display_name,
        record.hierarchy_path, aliases, record.semantic_text)
    bind_text(database, plain, 1, vocabulary)
    insert_done(database, plain, "spellfix vocabulary insertion")
}

// Insert metadata and UI declarations through their signature-aware statements.
insert_ui_record :: proc(
    database: ^Builder_Database, record: Content_Record,
    signatures: ^Message_Signatures) {
    switch record.kind {
    case 1:
        require(record.key != "content_fingerprint" &&
            record.key != "generation_identity" &&
            record.key != "record_count" &&
            record.key != "table_counts" &&
            record.key != "catalog_projection_schema_version" &&
            record.key != "projection_count",
            "corpus contains a builder-owned metadata key")
        insert_metadata(database, &database.statements.metadata,
            record.key, record.value, "source metadata insertion")
    case 2: insert_locale(database, record)
    case 3: insert_message(database, record, signatures)
    case 4: insert_argument(database, record, signatures)
    case 5: insert_translation(database, record, signatures)
    }
}

// Insert content declarations and projections through their named statements.
insert_content_record :: proc(database: ^Builder_Database, record: Content_Record) {
    switch record.kind {
    case 6: insert_subject(database, record)
    case 7: insert_catalog_node(database, record)
    case 8: insert_catalog_name(database, record)
    case 9: insert_edition(database, record)
    case 10: insert_availability(database, record)
    case 11:
        insert_projection(database, record, database.counts[11] + 1)
    }
}

// Validate and insert one declaration, then advance its kind's retained count.
insert_record :: proc(
    database: ^Builder_Database, record: Content_Record,
    signatures: ^Message_Signatures) {
    validate_record(record)
    if record.kind <= 5 {
        insert_ui_record(database, record, signatures)
    } else {
        insert_content_record(database, record)
    }
    database.counts[record.kind] += 1
}

// Prepare every fixed insertion statement once for the complete transaction.
prepare_builder_statements :: proc(database: ^Builder_Database) {
    statements := &database.statements
    prepare_statement(database, &statements.metadata, cstring(METADATA_INSERT_SQL))
    prepare_statement(database, &statements.locale, cstring(LOCALE_INSERT_SQL))
    prepare_statement(database, &statements.message, cstring(MESSAGE_INSERT_SQL))
    prepare_statement(database, &statements.argument, cstring(ARGUMENT_INSERT_SQL))
    prepare_statement(database, &statements.translation, cstring(TRANSLATION_INSERT_SQL))
    prepare_statement(database, &statements.subject, cstring(SUBJECT_INSERT_SQL))
    prepare_statement(database, &statements.node, cstring(NODE_INSERT_SQL))
    prepare_statement(database, &statements.name, cstring(NAME_INSERT_SQL))
    prepare_statement(database, &statements.edition, cstring(EDITION_INSERT_SQL))
    prepare_statement(database, &statements.availability,
        cstring(AVAILABILITY_INSERT_SQL))
    prepare_statement(database, &statements.projection, cstring(PROJECTION_INSERT_SQL))
    prepare_statement(database, &statements.plain, cstring(PLAIN_INSERT_SQL))
}

// Finalize all fixed insertion statements after the source stream is consumed.
finalize_builder_statements :: proc(database: ^Builder_Database) {
    statements := &database.statements
    finalize_statement(database, &statements.metadata)
    finalize_statement(database, &statements.locale)
    finalize_statement(database, &statements.message)
    finalize_statement(database, &statements.argument)
    finalize_statement(database, &statements.translation)
    finalize_statement(database, &statements.subject)
    finalize_statement(database, &statements.node)
    finalize_statement(database, &statements.name)
    finalize_statement(database, &statements.edition)
    finalize_statement(database, &statements.availability)
    finalize_statement(database, &statements.projection)
    finalize_statement(database, &statements.plain)
}

// Decode one bounded declaration and enforce canonical field layout.
parse_content_record :: proc(line: string) -> Content_Record {
    require(len(line) <= CONTENT_LINE_MAX_BYTES,
        "content record exceeds line capacity")
    record: Content_Record
    require(json.unmarshal_string(
        line, &record, allocator=context.temp_allocator) == nil,
        "invalid content record JSON")
    validate_record_shape(line, record.kind)
    return record
}

// Parse and insert each bounded JSONL declaration in strict canonical order.
insert_content_records :: proc(
    database: ^Builder_Database, source: string) -> int {
    signatures: Message_Signatures
    prepare_builder_statements(database)
    count := 0
    previous_kind := 0
    previous_identity := ""
    line_start := 0
    source_bytes := transmute([]u8)source
    for line_end := 0; line_end <= len(source_bytes); line_end += 1 {
        if line_end < len(source_bytes) && source_bytes[line_end] != '\n' {
            continue
        }
        line := source[line_start:line_end]
        line_start = line_end + 1
        if len(line) == 0 {
            continue
        }
        record := parse_content_record(line)
        identity := record_identity(record)
        require(record.kind > previous_kind ||
            record.kind == previous_kind &&
            strings.compare(previous_identity, identity) < 0,
            "content records are not in canonical kind/identity order")
        insert_record(database, record, &signatures)
        previous_kind = record.kind
        previous_identity = identity
        count += 1
        require(count <= 4096, "content record count exceeds capacity")
    }
    finalize_builder_statements(database)
    return count
}

// Require one metadata value to match its frozen builder contract.
require_metadata_value :: proc(
    database: ^Builder_Database, key, expected: string) {
    statement := prepare_temporary_statement(database,
        "SELECT value FROM content_metadata WHERE key = ?1")
    bind_text(database, &statement, 1, key)
    require_step(database, &statement, .Row, "metadata validation")
    value: [512]u8
    count := column_text(database, &statement, 0, value[:], "metadata read")
    require(string(value[:count]) == expected,
        fmt.tprintf("content metadata %s is inconsistent", key))
    require_step(database, &statement, .Done, "metadata uniqueness check")
    finalize_statement(database, &statement)
}

// Require one scalar SQL count to equal its declared completeness bound.
require_query_count :: proc(
    database: ^Builder_Database, sql: cstring, expected: int, operation: string) {
    statement := prepare_temporary_statement(database, sql)
    require_step(database, &statement, .Row, operation)
    actual := column_i32(database, &statement, 0, operation)
    require(actual == i32(expected),
        fmt.tprintf("%s mismatch: expected %d, got %d", operation, expected, actual))
    finalize_statement(database, &statement)
}

// Return a deterministic semicolon-separated table count summary.
table_counts_value :: proc(counts: [12]int) -> string {
    return fmt.tprintf("1=%d;2=%d;3=%d;4=%d;5=%d;6=%d;7=%d;8=%d;9=%d;10=%d;11=%d",
        counts[1], counts[2], counts[3], counts[4], counts[5], counts[6],
        counts[7], counts[8], counts[9], counts[10], counts[11])
}

// Insert builder-derived metadata after declaration counts are frozen.
insert_derived_metadata :: proc(
    database: ^Builder_Database, fingerprint: string, record_count: int) {
    statement := &database.statements.metadata
    prepare_statement(database, statement, cstring(METADATA_INSERT_SQL))
    insert_metadata(database, statement, "content_fingerprint", fingerprint,
        "content fingerprint metadata")
    insert_metadata(database, statement, "generation_identity", fingerprint,
        "generation metadata")
    insert_metadata(database, statement, "record_count",
        fmt.tprintf("%d", record_count), "record count metadata")
    insert_metadata(database, statement, "table_counts",
        table_counts_value(database.counts), "table count metadata")
    insert_metadata(database, statement, "catalog_projection_schema_version", "2",
        "search projection metadata")
    insert_metadata(database, statement, "projection_count",
        fmt.tprintf("%d", database.counts[11]), "projection count metadata")
    finalize_statement(database, statement)
}

// Validate required source metadata and its correspondence with locale rows.
validate_source_metadata :: proc(database: ^Builder_Database) {
    require_query_count(database,
        "SELECT count(*) FROM content_metadata", SOURCE_METADATA_COUNT,
        "source metadata count")
    require_metadata_value(database, "schema_version", "3")
    require_metadata_value(database, "tool_compatibility",
        "euclid-content-builder-v1")
    require_metadata_value(database, "sqlite_version", "3.53.4")
    require_metadata_value(database, "tokenizer_version",
        "porter-unicode61-v1")
    require_metadata_value(database, "query_contract_version", "1")
    require_metadata_value(database, "default_locale", "en-US")
    require_query_count(database,
        "SELECT count(*) FROM locale WHERE tag='en-US' AND is_default=1",
        1, "default locale metadata")
}

// Require SQLite to report no foreign-key violations.
validate_foreign_keys :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database, "PRAGMA foreign_key_check")
    require_step(database, &statement, .Done, "foreign-key check")
    finalize_statement(database, &statement)
}

// Require exact shipped declaration counts and complete localized UI/name coverage.
validate_declaration_coverage :: proc(database: ^Builder_Database) {
    counts := database.counts
    require(counts[1] == SOURCE_METADATA_COUNT, "metadata record count mismatch")
    require(counts[2] == EXPECTED_LOCALE_COUNT, "locale record count mismatch")
    require(counts[3] == EXPECTED_MESSAGE_COUNT, "UI message count mismatch")
    require(counts[4] <= 32, "UI argument count exceeds capacity")
    require(counts[5] == EXPECTED_TRANSLATION_COUNT,
        "UI translation count mismatch")
    require(counts[6] == EXPECTED_SUBJECT_COUNT, "subject count mismatch")
    require(counts[7] == EXPECTED_CATALOG_NODE_COUNT, "catalogue node count mismatch")
    require(counts[8] == EXPECTED_CATALOG_NAME_COUNT, "catalogue name count mismatch")
    require(counts[9] == EXPECTED_EDITION_COUNT, "edition count mismatch")
    require(counts[10] == EXPECTED_AVAILABILITY_COUNT, "availability count mismatch")
    require(counts[11] == EXPECTED_PROJECTION_COUNT, "search projection count mismatch")
    require_query_count(database,
        "SELECT count(*) FROM ui_message m CROSS JOIN locale l " +
        "LEFT JOIN ui_translation t ON t.message_key=m.message_key " +
        "AND t.locale_tag=l.tag WHERE t.message_key IS NULL",
        0, "translation coverage")
    require_query_count(database,
        "SELECT count(*) FROM catalog_node n CROSS JOIN locale l " +
        "LEFT JOIN catalog_name c ON c.source_namespace=n.source_namespace " +
        "AND c.animation_id=n.animation_id AND c.locale_tag=l.tag " +
        "WHERE c.animation_id IS NULL",
        0, "catalogue name coverage")
}

// Require complete subject availability with one default per subject and locale.
validate_availability_coverage :: proc(database: ^Builder_Database) {
    require_query_count(database,
        "SELECT count(*) FROM content_subject s CROSS JOIN locale l " +
        "LEFT JOIN availability a ON a.source_namespace=s.source_namespace " +
        "AND a.animation_id=s.animation_id AND a.locale_tag=l.tag " +
        "WHERE a.animation_id IS NULL",
        0, "availability coverage")
    require_query_count(database,
        "SELECT count(*) FROM content_subject s LEFT JOIN catalog_node n " +
        "ON n.source_namespace=s.source_namespace AND n.animation_id=s.animation_id " +
        "WHERE n.animation_id IS NULL AND s.source_namespace='builtin' " +
        "AND s.animation_id='00000000-0000-0000-0000-000000000000'",
        1, "reserved adapter subject")
    require_query_count(database,
        "SELECT count(*) FROM content_subject s LEFT JOIN catalog_node n " +
        "ON n.source_namespace=s.source_namespace AND n.animation_id=s.animation_id " +
        "WHERE n.animation_id IS NULL",
        1, "non-catalogue subject count")
    require_query_count(database,
        "SELECT count(*) FROM (SELECT source_namespace, animation_id, locale_tag " +
        "FROM availability GROUP BY source_namespace, animation_id, locale_tag " +
        "HAVING sum(is_default) != 1)",
        0, "default availability coverage")
}

// Require complete default projections and agreement with catalogue node semantics.
validate_catalog_coverage :: proc(database: ^Builder_Database) {
    require_query_count(database,
        "SELECT count(*) FROM catalog_node n CROSS JOIN locale l " +
        "LEFT JOIN search_projection p ON p.source_namespace=n.source_namespace " +
        "AND p.animation_id=n.animation_id AND p.locale_tag=l.tag " +
        "WHERE p.projection_id IS NULL",
        0, "search projection coverage")
    require_query_count(database,
        "SELECT count(*) FROM search_projection p LEFT JOIN availability a " +
        "ON a.source_namespace=p.source_namespace AND a.animation_id=p.animation_id " +
        "AND a.locale_tag=p.locale_tag AND a.edition_id=p.edition_id " +
        "WHERE a.is_default IS NULL OR a.is_default!=1",
        0, "default search projection coverage")
    require_query_count(database,
        "SELECT count(*) FROM (SELECT n.source_namespace, n.parent_animation_id, " +
        "c.locale_tag, c.display_name FROM catalog_node n JOIN catalog_name c " +
        "ON c.source_namespace=n.source_namespace AND c.animation_id=n.animation_id " +
        "GROUP BY n.source_namespace, n.parent_animation_id, c.locale_tag, c.display_name " +
        "HAVING count(*) > 1)",
        0, "catalogue sibling name uniqueness")
    require_query_count(database,
        "SELECT count(*) FROM catalog_node WHERE node_kind=3 " +
        "AND implementation_path IS NULL",
        1, "Terminal node count")
    require_query_count(database,
        "SELECT count(*) FROM search_projection p JOIN catalog_node n " +
        "ON n.source_namespace=p.source_namespace AND n.animation_id=p.animation_id " +
        "WHERE (n.node_kind=3 AND (length(p.semantic_text)>0 OR length(p.aliases)>0)) " +
        "OR (n.node_kind!=3 AND length(p.semantic_text)=0)",
        0, "node/search projection consistency")
}

// Validate authored completeness across localized declarations and content bindings.
validate_content_coverage :: proc(database: ^Builder_Database) {
    validate_declaration_coverage(database)
    validate_availability_coverage(database)
    validate_catalog_coverage(database)
}

// Validate the generated search indexes and their original query projection.
validate_search_indexes :: proc(database: ^Builder_Database) {
    execute_sql(database,
        "INSERT INTO animation_search(animation_search, rank) " +
        "VALUES('integrity-check', 1)")
    require_query_count(database,
        "SELECT count(*) > 0 FROM animation_search " +
        "WHERE animation_search MATCH 'geometry'",
        1, "representative FTS query")
    require_query_count(database,
        "SELECT count(*) > 0 FROM search_terms",
        1, "spellfix vocabulary")
    require_query_count(database,
        "SELECT count(*) > 0 FROM search_terms " +
        "WHERE word MATCH 'geomtry' AND word='geometry'",
        1, "representative spellfix correction")
    require_query_count(database,
        "SELECT count(*) FROM animation_catalog",
        EXPECTED_PROJECTION_COUNT, "legacy search projection view")
    require_query_count(database,
        "SELECT count(*) FROM search_metadata WHERE key='schema_version' " +
        "AND value='2'",
        1, "legacy search metadata view")
}

// Validate SQLite integrity, relationships, declarations, and search indexes.
validate_database :: proc(database: ^Builder_Database) {
    statement := prepare_temporary_statement(database,
        "SELECT integrity_check FROM pragma_integrity_check")
    require_step(database, &statement, .Row, "database integrity check")
    integrity: [16]u8
    integrity_count := column_text(
        database, &statement, 0, integrity[:], "integrity result read")
    require(string(integrity[:integrity_count]) == "ok",
        "content database integrity check failed")
    finalize_statement(database, &statement)
    validate_foreign_keys(database)
    validate_content_coverage(database)
    validate_search_indexes(database)
}

// Insert declarations, derive the indexes, and freeze complete metadata.
build_database :: proc(
    database: ^Builder_Database, source, fingerprint: string) {
    require_sqlite(database,
        sqlite.connection_register_spellfix(&database.connection),
        "spellfix registration")
    execute_sql(database, cstring(SCHEMA_SQL))
    execute_sql(database, "BEGIN IMMEDIATE")
    total_records := insert_content_records(database, source)
    validate_source_metadata(database)
    execute_sql(database,
        "INSERT INTO animation_search(animation_search) VALUES('rebuild')")
    execute_sql(database,
        "INSERT INTO search_terms(word, rank) " +
        "SELECT term, 1000000 - min(cnt, 999999) " +
        "FROM plain_search_vocabulary ORDER BY term")
    insert_derived_metadata(database, fingerprint, total_records)
    execute_sql(database,
        "DROP TABLE plain_search_vocabulary; DROP TABLE plain_search")
    execute_sql(database, "COMMIT")
    validate_database(database)
    execute_sql(database, "VACUUM")
}

// Build one validated SQLite database from a canonical content record stream.
main :: proc() {
    require(len(os.args) == 4,
        "usage: content_builder INPUT.jsonl OUTPUT.sqlite3 FINGERPRINT")
    source_bytes, read_error := os.read_entire_file(os.args[1], context.allocator)
    require(read_error == nil, "could not read canonical content records")
    defer delete(source_bytes)
    require(len(source_bytes) <= CONTENT_MAX_BYTES,
        "content corpus exceeds aggregate capacity")
    require(valid_content_fingerprint(transmute(string)source_bytes, os.args[3]),
        "content fingerprint does not match the canonical record stream")
    _ = os.remove(os.args[2])
    database: Builder_Database
    open_failure := sqlite.connection_open(
        &database.connection, os.args[2], .Readwrite_Create, context.temp_allocator)
    require(open_failure.validation == .None && open_failure.result == .Ok,
        "could not create content database")
    build_database(&database, transmute(string)source_bytes, os.args[3])
    require_sqlite(&database, sqlite.connection_close(&database.connection), "close")
}
