package contentstore

import contentdata "../../core/content"
import sqlite "../../sqlite"

import "core:encoding/uuid"
import "core:strings"
import "core:unicode/utf8"

// Validate the built-in exercise rows without retaining their instruction text.
content_admission_validate_exercises :: proc(
    database: ^Content_Database,
    generation: ^contentdata.Content_Generation) -> bool {
    return content_admission_validate_exercise_rows(database, generation) &&
        content_admission_validate_retired_exercise_rows(database)
}

// Validate each exercise identity, catalogue association, and bounded plain-text field.
content_admission_validate_exercise_rows :: proc(
    database: ^Content_Database,
    generation: ^contentdata.Content_Generation) -> bool {
    statement := &database.statements.exercise_validation_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.EXERCISE_RECORD_CAPACITY ||
           !content_admission_validate_exercise_row(statement, generation) {
            return false
        }
        count += 1
    }
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[12]))
}

// Validate one row and verify that its animation UUID names a catalogue animation.
content_admission_validate_exercise_row :: proc(
    statement: ^sqlite.Statement,
    generation: ^contentdata.Content_Generation) -> bool {
    exercise_id, exercise_ok := content_admission_read_uuid(statement, 0)
    animation_id, animation_ok := content_admission_read_uuid(statement, 1)
    reference_ok := content_admission_exercise_reference(statement, 2)
    title_ok := content_admission_exercise_title(statement, 3)
    order, order_ok := search_column_i64(statement, 4)
    instructions_ok := content_admission_exercise_instructions(statement, 5)
    return exercise_ok && animation_ok && exercise_id != (uuid.Identifier{}) &&
        animation_id != (uuid.Identifier{}) &&
        reference_ok && title_ok && order_ok && order >= 0 &&
        order <= i64(max(i32)) &&
        instructions_ok && content_admission_animation_exists(generation, animation_id)
}

// Validate a friendly reference within its fixed byte bound.
content_admission_exercise_reference :: proc(
    statement: ^sqlite.Statement, column: int) -> bool {
    storage: [contentdata.EXERCISE_REFERENCE_BYTE_CAPACITY]u8
    count, valid := content_admission_copy_text(
        statement, column, storage[:], len(storage), false)
    reference := string(storage[:count])
    return valid && content_admission_exercise_reference_valid(reference)
}

// Require a bounded, nonblank title without retaining database-owned bytes.
content_admission_exercise_title :: proc(
    statement: ^sqlite.Statement, column: int) -> bool {
    storage: [contentdata.EXERCISE_TITLE_BYTE_CAPACITY]u8
    count, valid := content_admission_copy_text(
        statement, column, storage[:], len(storage), false)
    return valid && len(strings.trim_space(string(storage[:count]))) > 0
}

// Validate the full instruction source in bounded scratch storage, then discard it.
content_admission_exercise_instructions :: proc(
    statement: ^sqlite.Statement, column: int) -> bool {
    storage: [contentdata.EXERCISE_INSTRUCTIONS_BYTE_CAPACITY]u8
    count, valid := content_admission_copy_text(
        statement, column, storage[:], len(storage), false)
    text := string(storage[:count])
    return valid && utf8.valid_string(text) && len(strings.trim_space(text)) > 0
}

// Accept exactly the authored lowercase ASCII friendly-reference grammar.
content_admission_exercise_reference_valid :: proc(reference: string) -> bool {
    if len(reference) < 1 ||
       len(reference) > contentdata.EXERCISE_REFERENCE_BYTE_CAPACITY {
        return false
    }
    for byte in transmute([]u8)reference {
        if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') &&
           byte != '-' && byte != '_' {
            return false
        }
    }
    return true
}

// Require an association to an admitted invocable animation node.
content_admission_animation_exists :: proc(
    generation: ^contentdata.Content_Generation,
    animation_id: uuid.Identifier) -> bool {
    for record in generation.records[:generation.record_count] {
        if record.stable_id == animation_id {
            return record.node_kind == .Animation
        }
    }
    return false
}

// Validate tombstones and reject aliases or deleted identities that were reused.
content_admission_validate_retired_exercise_rows :: proc(
    database: ^Content_Database) -> bool {
    statement := &database.statements.retired_exercise_validation_rows
    count := 0
    for {
        status := search_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || count >= contentdata.EXERCISE_RECORD_CAPACITY ||
           !content_admission_validate_retired_exercise_row(statement) {
            return false
        }
        count += 1
    }
    return content_admission_finish_rows(
        statement, count, int(database.expected_table_counts[13]))
}

// Validate one retired alias and its retained stable-identity policy.
content_admission_validate_retired_exercise_row :: proc(
    statement: ^sqlite.Statement) -> bool {
    exercise_id, id_ok := content_admission_read_uuid(statement, 0)
    reference_ok := content_admission_exercise_reference(statement, 1)
    retired, retired_ok := search_column_i64(statement, 2)
    identity_live, identity_ok := search_column_i64(statement, 3)
    reference_live, reference_live_ok := search_column_i64(statement, 4)
    return id_ok && exercise_id != (uuid.Identifier{}) && reference_ok &&
        retired_ok && (retired == 0 || retired == 1) &&
        identity_ok && identity_live == 1-retired &&
        reference_live_ok && reference_live == 0
}
