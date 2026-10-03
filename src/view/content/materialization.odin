package content

import sqlite "../../sqlite"
import contentdata "../../core/content"

import "core:encoding/uuid"
import "core:strings"

// Append one required text column into the generation's stable packed owner.
content_admission_append_column :: proc(
    statement: ^sqlite.Statement, column: int, capacity: int,
    generation: ^Content_Generation, reference: ^contentdata.Content_Text_Ref) -> bool {
    storage: [CONTENT_SEMANTIC_TEXT_CAPACITY]u8
    bounded_capacity := min(capacity, len(storage))
    count, ok := content_admission_copy_text(
        statement, column, storage[:], bounded_capacity, false)
    return ok && contentdata.content_generation_append_text(
        generation, string(storage[:count]), capacity, reference) == .Ok
}

// Append a possibly empty schema text column into packed generation storage.
content_admission_append_optional_text :: proc(
    statement: ^sqlite.Statement, column: int, capacity: int,
    generation: ^Content_Generation,
    reference: ^contentdata.Content_Text_Ref) -> bool {
    storage: [CONTENT_SEMANTIC_TEXT_CAPACITY]u8
    count, ok := content_admission_copy_text(
        statement, column, storage[:], min(capacity, len(storage)), true)
    return ok && contentdata.content_generation_append_text(
        generation, string(storage[:count]), capacity, reference) == .Ok
}

// Finish a bounded row scan only when its exact metadata count agrees.
content_admission_finish_rows :: proc(
    statement: ^sqlite.Statement, actual, expected: int) -> bool {
    return actual == expected && search_statement_reset(statement)
}

// Decode locale declarations, requiring exact SQLite integer booleans.
content_admission_read_locales :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.locale_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_LOCALE_CAPACITY ||
           !content_admission_read_locale_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[2]))
}

// Copy one locale and its default flag into the candidate generation.
content_admission_read_locale_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    tag_storage: [CONTENT_LOCALE_TAG_CAPACITY]u8
    tag_count, tag_ok := content_admission_copy_text(
        statement, 0, tag_storage[:], len(tag_storage), false)
    default_value, default_ok := search_column_i64(statement, 1)
    tag := string(tag_storage[:tag_count])
    if !tag_ok || !content_admission_locale_tag_is_valid(tag) || !default_ok ||
       (default_value != 0 && default_value != 1) {
        return false
    }
    reference: contentdata.Content_Text_Ref
    if contentdata.content_generation_append_text(
        generation, tag, CONTENT_LOCALE_TAG_CAPACITY, &reference) != .Ok {
        return false
    }
    generation.data.locales[index] = contentdata.Content_Locale{
        tag = reference, is_default = default_value == 1,
    }
    generation.data.locale_count += 1
    return true
}

// Decode stable shipped UI declarations with exact native-ID/key identities.
content_admission_read_messages :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.message_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_MESSAGE_CAPACITY ||
           !content_admission_read_message_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[3]))
}

// Copy one localized message declaration and enforce exact stable identity.
content_admission_read_message_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    key_storage: [CONTENT_MESSAGE_KEY_CAPACITY]u8
    key_count, key_ok := content_admission_copy_text(
        statement, 0, key_storage[:], len(key_storage), false)
    native_id, id_ok := search_column_i64(statement, 1)
    key := string(key_storage[:key_count])
    if !key_ok || !id_ok || native_id < 1 || native_id > i64(max(u16)) ||
       !content_admission_message_identity_is_shipped(u16(native_id), key) {
        return false
    }
    message := &generation.data.messages[index]
    message.native_id = u16(native_id)
    if contentdata.content_generation_append_text(
        generation, key, CONTENT_MESSAGE_KEY_CAPACITY, &message.key) != .Ok ||
       !content_admission_append_column(
           statement, 2, CONTENT_CONTEXT_CAPACITY, generation,
           &message.developer_context) {
        return false
    }
    generation.data.message_count += 1
    return true
}

// Decode bounded, ordinal-preserving message argument signatures.
content_admission_read_arguments :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.argument_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_ARGUMENT_CAPACITY ||
           !content_admission_read_argument_row(statement, generation) {
            return false
        }
        count += 1
    }
    generation.data.argument_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[4]))
}

// Append one argument in its declared ordinal and admit only known wire kinds.
content_admission_read_argument_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation) -> bool {
    key_storage: [CONTENT_MESSAGE_KEY_CAPACITY]u8
    key_count, key_ok := content_admission_copy_text(
        statement, 0, key_storage[:], len(key_storage), false)
    ordinal, ordinal_ok := search_column_i64(statement, 1)
    message_index := content_admission_find_message(
        generation, string(key_storage[:key_count]))
    if !key_ok || !ordinal_ok || message_index < 0 || ordinal < 0 || ordinal > 1 {
        return false
    }
    message := &generation.data.messages[message_index]
    if ordinal != i64(message.argument_count) {
        return false
    }
    argument := &message.arguments[int(ordinal)]
    if !content_admission_append_column(
        statement, 2, CONTENT_ARGUMENT_NAME_CAPACITY, generation, &argument.name) {
        return false
    }
    kind, kind_ok := content_admission_argument_kind(statement, 3)
    if !kind_ok {
        return false
    }
    argument.kind = kind
    message.argument_count += 1
    return true
}

// Parse one wire argument kind without SQLite text coercion.
content_admission_argument_kind :: proc(
    statement: ^sqlite.Statement,
    column: int) -> (contentdata.Content_Argument_Kind, bool) {
    storage: [16]u8
    count, ok := content_admission_copy_text(
        statement, column, storage[:], len(storage), false)
    if !ok {
        return .Text, false
    }
    switch string(storage[:count]) {
    case "text": return .Text, true
    case "uint32": return .Uint32, true
    case "int64": return .Int64, true
    case "float32_1dp": return .Float32_One_Decimal, true
    }
    return .Text, false
}

// Decode one complete locale/message translation row.
content_admission_read_translations :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.translation_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_TRANSLATION_CAPACITY ||
           !content_admission_read_translation_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    generation.data.translation_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[5]))
}

// Resolve and pack one translation's locale, message, and template references.
content_admission_read_translation_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    locale_storage: [CONTENT_LOCALE_TAG_CAPACITY]u8
    key_storage: [CONTENT_MESSAGE_KEY_CAPACITY]u8
    locale_count, locale_ok := content_admission_copy_text(
        statement, 0, locale_storage[:], len(locale_storage), false)
    key_count, key_ok := content_admission_copy_text(
        statement, 1, key_storage[:], len(key_storage), false)
    locale_index := content_admission_find_locale(
        generation, string(locale_storage[:locale_count]))
    message_index := content_admission_find_message(
        generation, string(key_storage[:key_count]))
    row := &generation.data.translations[index]
    if !locale_ok || !key_ok || locale_index < 0 || message_index < 0 ||
       !content_admission_append_column(
           statement, 2, CONTENT_TEMPLATE_CAPACITY, generation, &row.template) {
        return false
    }
    row.locale_index = u16(locale_index)
    row.message_index = u16(message_index)
    return true
}

// Find one locale by comparing its packed tag before the candidate is sealed.
content_admission_find_locale :: proc(
    generation: ^Content_Generation, tag: string) -> int {
    for index in 0..<int(generation.data.locale_count) {
        if content_admission_ref_equals(
            generation, generation.data.locales[index].tag, tag) {
            return index
        }
    }
    return -1
}

// Find one UI message by its stable key in the candidate text owner.
content_admission_find_message :: proc(
    generation: ^Content_Generation, key: string) -> int {
    for index in 0..<int(generation.data.message_count) {
        if content_admission_ref_equals(
            generation, generation.data.messages[index].key, key) {
            return index
        }
    }
    return -1
}

// Compare a packed reference against one temporary SQLite value.
content_admission_ref_equals :: proc(
    generation: ^Content_Generation, reference: contentdata.Content_Text_Ref,
    expected: string) -> bool {
    start := int(reference.offset)
    finish := start + int(reference.length)
    return finish <= generation.text_builder.count &&
        string(generation.text_builder.storage[start:finish]) == expected
}

// Parse a lowercase canonical UUID string while SQLite row storage is live.
content_admission_read_uuid :: proc(
    statement: ^sqlite.Statement, column: int) -> (uuid.Identifier, bool) {
    storage: [CONTENT_UUID_BYTE_COUNT]u8
    count, ok := content_admission_copy_text(
        statement, column, storage[:], len(storage), false)
    if !ok || count != CONTENT_UUID_BYTE_COUNT {
        return {}, false
    }
    for index in 0..<count {
        byte := storage[index]
        if index == 8 || index == 13 || index == 18 || index == 23 {
            if byte != '-' {
                return {}, false
            }
        } else if !(byte >= '0' && byte <= '9') && !(byte >= 'a' && byte <= 'f') {
            return {}, false
        }
    }
    identifier, failure := uuid.read(string(storage[:count]))
    return identifier, failure == .None
}

// Require the builtin namespace and parse its source-local UUID.
content_admission_read_source_uuid :: proc(
    statement: ^sqlite.Statement,
    namespace_column, id_column: int) -> (uuid.Identifier, bool) {
    namespace_storage: [len(CONTENT_SOURCE_NAMESPACE)]u8
    namespace_count, namespace_ok := content_admission_copy_text(
        statement, namespace_column, namespace_storage[:], len(namespace_storage), false)
    namespace := string(namespace_storage[:namespace_count])
    if !namespace_ok || namespace != CONTENT_SOURCE_NAMESPACE {
        return {}, false
    }
    return content_admission_read_uuid(statement, id_column)
}

// Decode exact content subjects, retaining the legitimate all-zero adapter UUID.
content_admission_read_subjects :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.subject_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_SUBJECT_CAPACITY {
            return false
        }
        identifier, valid := content_admission_read_source_uuid(statement, 0, 1)
        if !valid {
            return false
        }
        generation.data.subjects[count] = identifier
        count += 1
    }
    generation.data.subject_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[6]))
}

// Decode locale-scoped catalogue labels into stable record/locale indexes.
content_admission_read_names :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.name_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_NAME_CAPACITY ||
           !content_admission_read_name_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    generation.data.name_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[8]))
}

// Resolve one localized name against a catalogue node and admitted locale.
content_admission_read_name_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    identifier, identity_ok := content_admission_read_source_uuid(statement, 0, 1)
    locale_storage: [CONTENT_LOCALE_TAG_CAPACITY]u8
    locale_count, locale_ok := content_admission_copy_text(
        statement, 2, locale_storage[:], len(locale_storage), false)
    record_index := content_admission_find_catalog(generation, identifier)
    locale_index := content_admission_find_locale(
        generation, string(locale_storage[:locale_count]))
    if !identity_ok || !locale_ok || record_index < 0 || locale_index < 0 {
        return false
    }
    row := &generation.data.names[index]
    row.locale_index = u16(locale_index)
    row.record_index = u16(record_index)
    return content_admission_append_column(
        statement, 3, CATALOG_NAME_BYTE_CAPACITY, generation, &row.display_name)
}

// Decode each bounded edition and its independent text-language provenance.
content_admission_read_editions :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.edition_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_EDITION_CAPACITY ||
           !content_admission_read_edition_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    generation.data.edition_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[9]))
}

// Copy the identity, display name, language tag, and description of an edition.
content_admission_read_edition_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    row := &generation.data.editions[index]
    if !content_admission_append_column(
        statement, 0, CONTENT_EDITION_ID_CAPACITY, generation, &row.id) ||
       !content_admission_append_column(
           statement, 1, CONTENT_EDITION_NAME_CAPACITY, generation, &row.name) ||
       !content_admission_append_column(
           statement, 2, CONTENT_EDITION_LANGUAGE_CAPACITY, generation, &row.language) ||
       !content_admission_append_column(
           statement, 3, CONTENT_EDITION_DESCRIPTION_CAPACITY,
           generation, &row.description) {
        return false
    }
    language := content_admission_builder_text(generation, row.language)
    return content_admission_locale_tag_is_valid(language)
}

// Decode subject/locale edition availability with exact boolean storage.
content_admission_read_availability :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.availability_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CONTENT_AVAILABILITY_CAPACITY ||
           !content_admission_read_availability_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    generation.data.availability_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[10]))
}

// Resolve one edition availability tuple into compact indexes.
content_admission_read_availability_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    identifier, identity_ok := content_admission_read_source_uuid(statement, 0, 1)
    locale_storage: [CONTENT_LOCALE_TAG_CAPACITY]u8
    edition_storage: [CONTENT_EDITION_ID_CAPACITY]u8
    locale_count, locale_ok := content_admission_copy_text(
        statement, 2, locale_storage[:], len(locale_storage), false)
    edition_count, edition_ok := content_admission_copy_text(
        statement, 3, edition_storage[:], len(edition_storage), false)
    flag, flag_ok := search_column_i64(statement, 4)
    subject_index := content_admission_find_subject(generation, identifier)
    locale_index := content_admission_find_locale(
        generation, string(locale_storage[:locale_count]))
    edition_index := content_admission_find_edition(
        generation, string(edition_storage[:edition_count]))
    if !identity_ok || !locale_ok || !edition_ok || !flag_ok ||
       (flag != 0 && flag != 1) || subject_index < 0 ||
       locale_index < 0 || edition_index < 0 {
        return false
    }
    generation.data.availability[index] = contentdata.Content_Availability{
        subject_index = u16(subject_index),
        locale_index = u16(locale_index),
        edition_index = u16(edition_index),
        is_default = flag == 1,
    }
    return true
}

// Decode every normalized search projection and its exact foreign identities.
content_admission_read_projections :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    statement := &database.statements.projection_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.CATALOG_RECORD_CAPACITY ||
           !content_admission_read_projection_row(statement, generation, count) {
            return false
        }
        count += 1
    }
    generation.data.projection_count = u16(count)
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[11]))
}

// Copy one search projection's indexed fields after resolving all references.
content_admission_read_projection_row :: proc(
    statement: ^sqlite.Statement, generation: ^Content_Generation, index: int) -> bool {
    projection_id, projection_ok := search_column_i64(statement, 0)
    identifier, identity_ok := content_admission_read_source_uuid(statement, 1, 2)
    locale_storage: [CONTENT_LOCALE_TAG_CAPACITY]u8
    edition_storage: [CONTENT_EDITION_ID_CAPACITY]u8
    locale_count, locale_ok := content_admission_copy_text(
        statement, 3, locale_storage[:], len(locale_storage), false)
    edition_count, edition_ok := content_admission_copy_text(
        statement, 4, edition_storage[:], len(edition_storage), false)
    record_index := content_admission_find_catalog(generation, identifier)
    locale_index := content_admission_find_locale(
        generation, string(locale_storage[:locale_count]))
    edition_index := content_admission_find_edition(
        generation, string(edition_storage[:edition_count]))
    if !projection_ok || projection_id < 1 || projection_id > i64(max(u32)) ||
       !identity_ok || !locale_ok || !edition_ok || record_index < 0 ||
       locale_index < 0 || edition_index < 0 {
        return false
    }
    row := &generation.data.projections[index]
    row.projection_id = u32(projection_id)
    row.record_index = u16(record_index)
    row.locale_index = u16(locale_index)
    row.edition_index = u16(edition_index)
    return content_admission_append_column(
        statement, 5, CATALOG_NAME_BYTE_CAPACITY, generation, &row.display_name) &&
        content_admission_append_column(
            statement, 6, CONTENT_HIERARCHY_PATH_CAPACITY,
            generation, &row.hierarchy_path) &&
        content_admission_append_optional_text(
            statement, 7, CONTENT_SEMANTIC_TEXT_CAPACITY,
            generation, &row.semantic_text) &&
        content_admission_append_aliases(statement, 8, generation, &row.aliases)
}

// Append newline-joined aliases after enforcing per-alias size, count, and uniqueness.
content_admission_append_aliases :: proc(
    statement: ^sqlite.Statement, column: int,
    generation: ^Content_Generation,
    reference: ^contentdata.Content_Text_Ref) -> bool {
    storage: [CONTENT_ALIASES_CAPACITY]u8
    count, ok := content_admission_copy_text(
        statement, column, storage[:], len(storage), true)
    aliases := string(storage[:count])
    return ok && content_admission_aliases_are_valid(aliases) &&
        contentdata.content_generation_append_text(
            generation, aliases, CONTENT_ALIASES_CAPACITY, reference) == .Ok
}

// Require at most 16 distinct, nonempty, 128-byte-bounded newline-joined aliases.
content_admission_aliases_are_valid :: proc(aliases: string) -> bool {
    if len(aliases) == 0 {
        return true
    }
    entries: [CONTENT_ALIAS_COUNT_CAPACITY]string
    entry_count := 0
    remaining := aliases
    for {
        end := strings.index_byte(remaining, '\n')
        alias := remaining if end < 0 else remaining[:end]
        if entry_count == len(entries) || len(alias) == 0 ||
           len(alias) > CONTENT_ALIAS_BYTE_CAPACITY {
            return false
        }
        for prior in entries[:entry_count] {
            if prior == alias {
                return false
            }
        }
        entries[entry_count] = alias
        entry_count += 1
        if end < 0 {
            return true
        }
        remaining = remaining[end + 1:]
    }
}

// Find one catalogue row by its source-local identity.
content_admission_find_catalog :: proc(
    generation: ^Content_Generation, identifier: uuid.Identifier) -> int {
    for index in 0..<int(generation.record_count) {
        if generation.records[index].stable_id == identifier {
            return index
        }
    }
    return -1
}

// Find one subject identity, including the reserved all-zero adapter.
content_admission_find_subject :: proc(
    generation: ^Content_Generation, identifier: uuid.Identifier) -> int {
    for index in 0..<int(generation.data.subject_count) {
        if generation.data.subjects[index] == identifier {
            return index
        }
    }
    return -1
}

// Find an edition using its packed stable ID.
content_admission_find_edition :: proc(
    generation: ^Content_Generation, id: string) -> int {
    for index in 0..<int(generation.data.edition_count) {
        edition := &generation.data.editions[index]
        if content_admission_ref_equals(generation, edition.id, id) {
            return index
        }
    }
    return -1
}

// Resolve one packed reference into the current unsealed text builder.
content_admission_builder_text :: proc(
    generation: ^Content_Generation, reference: contentdata.Content_Text_Ref) -> string {
    start := int(reference.offset)
    finish := start + int(reference.length)
    return string(generation.text_builder.storage[start:finish])
}
