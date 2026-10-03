package content

import sqlite "../../sqlite"
import contentdata "../../core/content"

import "core:strings"
import "core:unicode/utf8"

CONTENT_METADATA_ROW_COUNT :: 12
CONTENT_SHIPPED_MESSAGE_COUNT :: contentdata.CONTENT_SHIPPED_MESSAGE_COUNT
CONTENT_SOURCE_NAMESPACE :: "builtin"
CONTENT_LOCALE_TAG_CAPACITY :: 35
CONTENT_MESSAGE_KEY_CAPACITY :: 64
CONTENT_CONTEXT_CAPACITY :: 256
CONTENT_ARGUMENT_NAME_CAPACITY :: 32
CONTENT_TEMPLATE_CAPACITY :: 128
CONTENT_EDITION_ID_CAPACITY :: 64
CONTENT_EDITION_NAME_CAPACITY :: 256
CONTENT_EDITION_LANGUAGE_CAPACITY :: 35
CONTENT_EDITION_DESCRIPTION_CAPACITY :: 1024
CONTENT_HIERARCHY_PATH_CAPACITY :: 2048
CONTENT_SEMANTIC_TEXT_CAPACITY :: 8192
CONTENT_ALIAS_COUNT_CAPACITY :: 16
CONTENT_ALIAS_BYTE_CAPACITY :: 128
CONTENT_ALIASES_CAPACITY :: CONTENT_ALIAS_COUNT_CAPACITY * CONTENT_ALIAS_BYTE_CAPACITY +
    CONTENT_ALIAS_COUNT_CAPACITY - 1
CONTENT_UUID_BYTE_COUNT :: 36

// Fixed-value or derived metadata rule for one schema-3 metadata key.
Content_Metadata_Key :: struct {
    key: string,
    fixed_value: string,
    rule: Content_Metadata_Rule,
}

// Validation responsibility for one schema-3 metadata value.
Content_Metadata_Rule :: enum u8 {
    Fixed,
    Fingerprint,
    Table_Counts,
    Record_Count,
    Projection_Count,
}

// Frozen schema-3 metadata vocabulary; each index is one coverage bit.
CONTENT_METADATA_KEYS :: [CONTENT_METADATA_ROW_COUNT]Content_Metadata_Key{
    {"schema_version", "3", .Fixed},
    {"tool_compatibility", "euclid-content-builder-v1", .Fixed},
    {"sqlite_version", "3.53.4", .Fixed},
    {"tokenizer_version", "porter-unicode61-v1", .Fixed},
    {"query_contract_version", "1", .Fixed},
    {"default_locale", "en-US", .Fixed},
    {"content_fingerprint", "", .Fingerprint},
    {"generation_identity", "", .Fingerprint},
    {"record_count", "", .Record_Count},
    {"table_counts", "", .Table_Counts},
    {"catalog_projection_schema_version", "2", .Fixed},
    {"projection_count", "", .Projection_Count},
}

// One stable native UI message identity required in every admitted database.
Content_Required_Message :: contentdata.Content_Required_Message

// Exact native ID/key contract for the shipped localized UI catalogue.
CONTENT_REQUIRED_MESSAGES :: contentdata.CONTENT_REQUIRED_MESSAGES

// Admit only the exact shipped key/native-ID pairs from ui_messages.jl.
content_admission_message_identity_is_shipped :: proc(id: u16, key: string) -> bool {
    required := CONTENT_REQUIRED_MESSAGES
    for message in required {
        if message.native_id == id && message.key == key {
            return true
        }
    }
    return false
}

// Copy an exact SQLite TEXT value and validate its bounded UTF-8 contract.
content_admission_copy_text :: proc(
    statement: ^sqlite.Statement, column: int, destination: []u8,
    capacity: int, allow_empty: bool) -> (int, bool) {
    if search_column_type(statement, column) != .Text || capacity > len(destination) {
        return 0, false
    }
    count, copied := search_copy_column(statement, column, destination[:capacity])
    if !copied || (!allow_empty && count == 0) {
        return 0, false
    }
    text := string(destination[:count])
    return count, utf8.valid_string(text) && !strings.contains(text, "\x00") &&
        content_admission_text_has_content(text)
}

// Reject required strings that contain only ASCII whitespace.
content_admission_text_has_content :: proc(text: string) -> bool {
    for byte in transmute([]u8)text {
        if byte != ' ' && byte != '\t' && byte != '\n' && byte != '\r' {
            return true
        }
    }
    return len(text) == 0
}

// Validate a BCP-47-shaped locale tag using its bounded ASCII grammar.
content_admission_locale_tag_is_valid :: proc(tag: string) -> bool {
    if len(tag) < 2 || len(tag) > CONTENT_LOCALE_TAG_CAPACITY {
        return false
    }
    segment_start := 0
    segment_index := 0
    for index in 0..=len(tag) {
        if index < len(tag) && tag[index] != '-' {
            continue
        }
        segment_length := index - segment_start
        if segment_length == 0 || segment_length > 8 ||
           (segment_index == 0 && segment_length < 2) {
            return false
        }
        for offset in segment_start..<index {
            byte := tag[offset]
            alpha := (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z')
            digit := byte >= '0' && byte <= '9'
            if !alpha && !(segment_index > 0 && digit) {
                return false
            }
        }
        segment_start = index + 1
        segment_index += 1
    }
    return true
}

// Parse a canonical bounded unsigned decimal metadata value.
content_admission_parse_u32 :: proc(value: string) -> (u32, bool) {
    if len(value) == 0 || (len(value) > 1 && value[0] == '0') {
        return 0, false
    }
    result: u32
    for byte in transmute([]u8)value {
        if byte < '0' || byte > '9' {
            return 0, false
        }
        digit := u32(byte - '0')
        if result > (max(u32) - digit) / 10 {
            return 0, false
        }
        result = result * 10 + digit
    }
    return result, true
}

// Parse the builder's exact semicolon-delimited normalized table count value.
content_admission_parse_table_counts :: proc(
    value: string, counts: ^[12]u16) -> bool {
    cursor := 0
    for table_index in 1..=11 {
        if !content_admission_expect_table_label(value, &cursor, table_index) {
            return false
        }
        parsed, valid := content_admission_take_count(value, &cursor)
        if !valid {
            return false
        }
        counts[table_index] = parsed
        if table_index < 11 && !content_admission_expect_byte(value, &cursor, ';') {
            return false
        }
    }
    return cursor == len(value)
}

// Consume one exact decimal table label followed by '='.
content_admission_expect_table_label :: proc(
    value: string, cursor: ^int, table_index: int) -> bool {
    if table_index >= 10 &&
       !content_admission_expect_byte(value, cursor, byte('0' + table_index / 10)) {
        return false
    }
    return content_admission_expect_byte(value, cursor, byte('0' + table_index % 10)) &&
        content_admission_expect_byte(value, cursor, '=')
}

// Consume one exact byte at the cursor.
content_admission_expect_byte :: proc(
    value: string, cursor: ^int, expected: byte) -> bool {
    if cursor^ >= len(value) || value[cursor^] != expected {
        return false
    }
    cursor^ += 1
    return true
}

// Consume one canonical decimal count that fits a u16 table cardinality.
content_admission_take_count :: proc(value: string, cursor: ^int) -> (u16, bool) {
    start := cursor^
    for cursor^ < len(value) && value[cursor^] >= '0' && value[cursor^] <= '9' {
        cursor^ += 1
    }
    parsed, valid := content_admission_parse_u32(value[start:cursor^])
    if !valid || parsed > u32(max(u16)) {
        return 0, false
    }
    return u16(parsed), true
}

// Verify all schema-3 and builder-derived metadata before reading table rows.
content_admission_validate_metadata :: proc(
    database: ^Content_Database, expected_fingerprint: string) -> bool {
    if !content_admission_fingerprint_is_valid(expected_fingerprint) {
        return false
    }
    statement := &database.statements.raw_metadata_rows
    seen: u16
    row_count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || row_count >= CONTENT_METADATA_ROW_COUNT ||
           !content_admission_read_metadata_row(
               database, statement, expected_fingerprint, &seen) {
            return false
        }
        row_count += 1
    }
    if !search_statement_reset(statement) || row_count != CONTENT_METADATA_ROW_COUNT ||
       seen != 0x0fff {
        return false
    }
    return content_admission_metadata_counts_are_valid(database)
}

// Validate one raw metadata key/value pair and retain declared table counts.
content_admission_read_metadata_row :: proc(
    database: ^Content_Database, statement: ^sqlite.Statement,
    fingerprint: string, seen: ^u16) -> bool {
    key_bytes: [64]u8
    value_bytes: [512]u8
    key_count, key_ok := content_admission_copy_text(
        statement, 0, key_bytes[:], len(key_bytes), false)
    value_count, value_ok := content_admission_copy_text(
        statement, 1, value_bytes[:], len(value_bytes), false)
    if !key_ok || !value_ok {
        return false
    }
    key := string(key_bytes[:key_count])
    bit, valid_key := content_admission_metadata_key_bit(key)
    if !valid_key || seen^ & bit != 0 {
        return false
    }
    seen^ |= bit
    return content_admission_metadata_value_is_valid(
        database, key, string(value_bytes[:value_count]), fingerprint)
}

// Map the frozen schema-3 metadata vocabulary to one coverage bit.
content_admission_metadata_key_bit :: proc(key: string) -> (u16, bool) {
    keys := CONTENT_METADATA_KEYS
    for entry, index in keys {
        if entry.key == key {
            return u16(1) << uint(index), true
        }
    }
    return 0, false
}

// Check fixed schema metadata and decode builder counts into the database owner.
content_admission_metadata_value_is_valid :: proc(
    database: ^Content_Database, key, value, fingerprint: string) -> bool {
    keys := CONTENT_METADATA_KEYS
    for entry in keys {
        if entry.key == key {
            return content_admission_metadata_rule_accepts(
                database, entry, value, fingerprint)
        }
    }
    return false
}

// Apply one metadata rule, retaining decoded builder counts on the database.
content_admission_metadata_rule_accepts :: proc(
    database: ^Content_Database, entry: Content_Metadata_Key,
    value, fingerprint: string) -> bool {
    switch entry.rule {
    case .Fixed: return value == entry.fixed_value
    case .Fingerprint: return value == fingerprint
    case .Table_Counts:
        return content_admission_parse_table_counts(
            value, &database.expected_table_counts)
    case .Record_Count:
        parsed, valid := content_admission_parse_u32(value)
        database.expected_record_count = parsed
        return valid
    case .Projection_Count:
        parsed, valid := content_admission_parse_u32(value)
        return valid && parsed == u32(CATALOG_RECORD_CAPACITY)
    }
    return false
}

// Validate frozen shipped cardinalities and total-record metadata.
content_admission_metadata_counts_are_valid :: proc(
    database: ^Content_Database) -> bool {
    counts := database.expected_table_counts
    if counts[1] != 6 || counts[2] != 1 || counts[3] != CONTENT_SHIPPED_MESSAGE_COUNT ||
       counts[4] > contentdata.CONTENT_ARGUMENT_CAPACITY ||
       counts[5] != CONTENT_SHIPPED_MESSAGE_COUNT ||
       counts[6] != contentdata.CONTENT_SUBJECT_CAPACITY ||
       counts[7] != contentdata.CATALOG_RECORD_CAPACITY ||
       counts[8] != contentdata.CATALOG_RECORD_CAPACITY ||
       counts[9] == 0 || counts[9] > contentdata.CONTENT_EDITION_CAPACITY ||
       counts[10] < counts[6] ||
       counts[10] > contentdata.CONTENT_AVAILABILITY_CAPACITY ||
       counts[11] != contentdata.CATALOG_RECORD_CAPACITY {
        return false
    }
    total: u32
    for index in 1..=11 {
        total += u32(counts[index])
    }
    return total == database.expected_record_count
}

// Require a lowercase SHA-256 hex fingerprint for the schema-3 identity.
content_admission_fingerprint_is_valid :: proc(fingerprint: string) -> bool {
    if len(fingerprint) != contentdata.SEARCH_FINGERPRINT_BYTE_COUNT {
        return false
    }
    for byte in transmute([]u8)fingerprint {
        if !(byte >= '0' && byte <= '9') && !(byte >= 'a' && byte <= 'f') {
            return false
        }
    }
    return true
}
