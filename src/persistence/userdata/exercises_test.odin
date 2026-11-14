#+test
package userdata

import raw "../../../libs/sqlite3"
import uuid "core:encoding/uuid"
import os "core:os"
import testing "core:testing"

// Build one exercise draft with a stable nonzero animation association.
userdata_test_exercise_draft :: proc(
    reference, title, instructions: string) -> User_Exercise_Draft {
    return {
        animation_id = userdata_test_id(91),
        reference = reference,
        title = title,
        instructions = instructions,
    }
}

// Create, rename, delete, and reopen an exercise while retaining retirement guarantees.
@(test)
userdata_user_exercise_crud_preserves_identity_and_retires_references :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)

    created, create_error := store_user_exercise_create(
        &store, userdata_test_exercise_draft(
            "triangle-basic", "Triangle", "Construct a triangle."))
    testing.expect_value(t, create_error.kind, Store_Error_Kind.None)
    testing.expect(t, created.id != (uuid.Identifier{}))
    testing.expect_value(t, created.animation_id, userdata_test_id(91))

    duplicate, duplicate_error := store_user_exercise_create(
        &store, userdata_test_exercise_draft(
            "triangle-basic", "Another title", "Another prompt."))
    _ = duplicate
    testing.expect_value(t, duplicate_error.kind, Store_Error_Kind.Reference_Collision)

    userdata_test_exercise_verify_active_lookup(t, &store, created)
    userdata_test_exercise_rename_and_retire(t, &store, created.id)

    userdata_test_exercise_reopen_and_delete(
        t, &store, fixture.path, created.id)
}

// Browse duplicate-title records in deterministic bounded pages by animation.
@(test)
userdata_user_exercise_lists_paged_animation_records :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)

    animation_id := userdata_test_id(93)
    userdata_test_exercise_create_for_animation(
        t, &store, animation_id, "first", "Same title")
    userdata_test_exercise_create_for_animation(
        t, &store, animation_id, "second", "Same title")
    first, first_error := store_user_exercise_list(&store, animation_id, 0, 1)
    testing.expect_value(t, first_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, first.returned_count, u16(1))
    testing.expect_value(t, first.total_count, u32(2))
    testing.expect(t, first.more_available)
    second, second_error := store_user_exercise_list(&store, animation_id, 1, 1)
    testing.expect_value(t, second_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, second.returned_count, u16(1))
    testing.expect(t, !second.more_available)
    testing.expect(t,
        string(first.exercises[0].reference[:first.exercises[0].reference_length]) !=
        string(second.exercises[0].reference[:second.exercises[0].reference_length]))
    all, all_error := store_user_exercise_list(&store, {}, 0, 16)
    testing.expect_value(t, all_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, all.total_count, u32(2))
    testing.expect_value(t, all.returned_count, u16(2))
}

// Create one exercise with the supplied association and duplicate display title.
userdata_test_exercise_create_for_animation :: proc(
    t: ^testing.T, store: ^Store, animation_id: uuid.Identifier,
    reference, title: string) {
    draft := userdata_test_exercise_draft(reference, title, "Instructions")
    draft.animation_id = animation_id
    _, failure := store_user_exercise_create(store, draft)
    testing.expect_value(t, failure.kind, Store_Error_Kind.None)
}

// Rename the exercise and prove its former alias remains reserved.
userdata_test_exercise_rename_and_retire :: proc(
    t: ^testing.T, store: ^Store, identity: uuid.Identifier) {
    updated, update_error := store_user_exercise_update(
        store, identity, userdata_test_exercise_draft(
            "equilateral", "Triangle", "Construct an equilateral triangle."))
    testing.expect_value(t, update_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, updated.id, identity)
    _, old_reference_error := store_user_exercise_read_by_reference(
        store, "triangle-basic")
    testing.expect_value(t, old_reference_error.kind, Store_Error_Kind.Reference_Retired)
    _, old_reference_create_error := store_user_exercise_create(
        store, userdata_test_exercise_draft(
            "triangle-basic", "Reused", "Must not reuse the retired alias."))
    testing.expect_value(t, old_reference_create_error.kind,
        Store_Error_Kind.Reference_Retired)
}

// Verify both supported identities resolve the same active exercise row.
userdata_test_exercise_verify_active_lookup :: proc(
    t: ^testing.T, store: ^Store, created: User_Exercise_Record) {
    by_id, id_error := store_user_exercise_read_by_identity(store, created.id)
    testing.expect_value(t, id_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, by_id.id, created.id)
    by_reference, reference_error := store_user_exercise_read_by_reference(
        store, "triangle-basic")
    testing.expect_value(t, reference_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, by_reference.title_length, u16(len("Triangle")))
}

// Reopen a renamed exercise, delete it, and verify retirement survives reopening.
userdata_test_exercise_reopen_and_delete :: proc(
    t: ^testing.T, store: ^Store, path: string, identity: uuid.Identifier) {
    testing.expect_value(t, store_close(store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_open(store, path).kind, Store_Error_Kind.None)
    reopened, reopened_error := store_user_exercise_read_by_reference(
        store, "equilateral")
    testing.expect_value(t, reopened_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, reopened.id, identity)
    testing.expect_value(t, string(reopened.title[:reopened.title_length]), "Triangle")
    testing.expect_value(t,
        string(reopened.instructions[:reopened.instructions_length]),
        "Construct an equilateral triangle.")

    testing.expect_value(t,
        store_user_exercise_delete(store, identity).kind, Store_Error_Kind.None)
    _, deleted_identity_error := store_user_exercise_read_by_identity(
        store, identity)
    testing.expect_value(t, deleted_identity_error.kind, Store_Error_Kind.Not_Found)
    _, deleted_reference_error := store_user_exercise_read_by_reference(
        store, "equilateral")
    testing.expect_value(t, deleted_reference_error.kind,
        Store_Error_Kind.Reference_Retired)
    _, deleted_reference_create_error := store_user_exercise_create(
        store, userdata_test_exercise_draft(
            "equilateral", "Reused", "Must remain reserved after deletion."))
    testing.expect_value(t, deleted_reference_create_error.kind,
        Store_Error_Kind.Reference_Retired)
    testing.expect_value(t, store_close(store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_open(store, path).kind, Store_Error_Kind.None)
    _, reopened_deleted_reference_error := store_user_exercise_read_by_reference(
        store, "equilateral")
    testing.expect_value(t, reopened_deleted_reference_error.kind,
        Store_Error_Kind.Reference_Retired)
}

// Accept exact byte capacities and reject invalid required fields before any write.
@(test)
userdata_user_exercise_enforces_exact_text_capacities :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    userdata_test_exercise_schema_constraints(t, &store)
    title: [USER_EXERCISE_TITLE_MAX_BYTES]u8
    instructions: [USER_EXERCISE_INSTRUCTIONS_MAX_BYTES]u8
    for index in 0..<len(title) {
        title[index] = 'T'
    }
    for index in 0..<len(instructions) {
        instructions[index] = 'I'
    }
    maximum, maximum_error := store_user_exercise_create(&store, {
        animation_id = userdata_test_id(92),
        reference = "abcdefghijklmnop",
        title = string(title[:]),
        instructions = string(instructions[:]),
    })
    testing.expect_value(t, maximum_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, maximum.reference_length,
        u8(USER_EXERCISE_REFERENCE_MAX_BYTES))
    testing.expect_value(t, maximum.title_length,
        u16(USER_EXERCISE_TITLE_MAX_BYTES))
    testing.expect_value(t, maximum.instructions_length,
        u32(USER_EXERCISE_INSTRUCTIONS_MAX_BYTES))

    userdata_test_exercise_reject_invalid_drafts(t, &store)
}

// Assert the fresh schema rejects zero UUIDs, invalid aliases, and oversized text.
userdata_test_exercise_schema_constraints :: proc(t: ^testing.T, store: ^Store) {
    userdata_expect_constraint(t, store,
        "INSERT INTO user_exercise VALUES ("+
        "X'00000000000000000000000000000001', "+
        "X'00000000000000000000000000000000', "+
        "'constraint-test', 'Title', 'Text')")
    userdata_expect_constraint(t, store,
        "INSERT INTO user_exercise VALUES ("+
        "X'00000000000000000000000000000001', "+
        "X'00000000000000000000000000000002', "+
        "'Uppercase', 'Title', 'Text')")
    userdata_expect_constraint(t, store,
        "INSERT INTO user_exercise VALUES ("+
        "X'00000000000000000000000000000001', "+
        "X'00000000000000000000000000000002', "+
        "'too-long-title', printf('%0257d', 0), 'Text')")
    userdata_expect_constraint(t, store,
        "INSERT INTO user_exercise VALUES ("+
        "X'00000000000000000000000000000001', "+
        "X'00000000000000000000000000000002', "+
        "'too-long-prompt', 'Title', printf('%032769d', 0))")
}

// Reject malformed UTF-8, NUL text, missing fields, and oversized drafts.
userdata_test_exercise_reject_invalid_drafts :: proc(t: ^testing.T, store: ^Store) {
    invalid_drafts: [6]User_Exercise_Draft = {
        {
            animation_id = userdata_test_id(92),
            reference = "Invalid",
            title = "Title",
            instructions = "Text",
        },
        {
            animation_id = userdata_test_id(92),
            reference = "too-long-reference",
            title = "Title",
            instructions = "Text",
        },
        {
            animation_id = userdata_test_id(92),
            reference = "blank-title",
            title = " \t",
            instructions = "Text",
        },
        {
            animation_id = userdata_test_id(92),
            reference = "empty-prompt",
            title = "Title",
        },
        {
            reference = "missing-animation",
            title = "Title",
            instructions = "Text",
        },
        {
            animation_id = userdata_test_id(92),
            reference = "Bad",
            title = "Title",
            instructions = "Text",
        },
    }
    for draft in invalid_drafts {
        _, invalid_error := store_user_exercise_create(store, draft)
        testing.expect_value(t, invalid_error.kind, Store_Error_Kind.Invalid_Exercise)
    }
    invalid_utf8: [1]u8 = {0xff}
    _, invalid_utf8_error := store_user_exercise_create(store, {
        animation_id = userdata_test_id(92),
        reference = "invalid-utf8",
        title = "Title",
        instructions = string(invalid_utf8[:]),
    })
    testing.expect_value(t, invalid_utf8_error.kind, Store_Error_Kind.Invalid_Exercise)
    _, nul_text_error := store_user_exercise_create(store, {
        animation_id = userdata_test_id(92),
        reference = "nul-text",
        title = "Title",
        instructions = "Text\x00with NUL",
    })
    testing.expect_value(t, nul_text_error.kind, Store_Error_Kind.Invalid_Exercise)

    oversized_title: [USER_EXERCISE_TITLE_MAX_BYTES + 1]u8
    for index in 0..<len(oversized_title) {
        oversized_title[index] = 'T'
    }
    _, oversized_title_error := store_user_exercise_create(store, {
        animation_id = userdata_test_id(92),
        reference = "oversized-title",
        title = string(oversized_title[:]),
        instructions = "Text",
    })
    testing.expect_value(t, oversized_title_error.kind, Store_Error_Kind.Invalid_Exercise)

    oversized_instructions: [USER_EXERCISE_INSTRUCTIONS_MAX_BYTES + 1]u8
    for index in 0..<len(oversized_instructions) {
        oversized_instructions[index] = 'I'
    }
    _, oversized_instructions_error := store_user_exercise_create(store, {
        animation_id = userdata_test_id(92),
        reference = "oversized-text",
        title = "Title",
        instructions = string(oversized_instructions[:]),
    })
    testing.expect_value(t, oversized_instructions_error.kind,
        Store_Error_Kind.Invalid_Exercise)
}

// Verify a rejected update rolls back the row and alias retirement together.
userdata_test_exercise_failed_update_is_atomic :: proc(
    t: ^testing.T, store: ^Store, identity: uuid.Identifier) {
    testing.expect_value(t, store_exec(store,
        "CREATE TRIGGER test_fail_user_exercise_update "+
        "BEFORE UPDATE ON user_exercise BEGIN "+
        "SELECT RAISE(ABORT, 'test update failure'); END").result,
        raw.Result.Ok)
    _, update_error := store_user_exercise_update(
        store, identity, userdata_test_exercise_draft(
            "replacement", "Replacement", "Replacement instructions."))
    testing.expect_value(t, update_error.kind, Store_Error_Kind.Write)
    _, original_after_update := store_user_exercise_read_by_reference(
        store, "original")
    testing.expect_value(t, original_after_update.kind, Store_Error_Kind.None)
    _, replacement_after_update := store_user_exercise_read_by_reference(
        store, "replacement")
    testing.expect_value(t, replacement_after_update.kind, Store_Error_Kind.Not_Found)
    testing.expect_value(t, store_exec(store,
        "DROP TRIGGER test_fail_user_exercise_update").result, raw.Result.Ok)
}

// Verify a rejected delete leaves the active row and alias intact.
userdata_test_exercise_failed_delete_is_atomic :: proc(
    t: ^testing.T, store: ^Store, identity: uuid.Identifier) {
    testing.expect_value(t, store_exec(store,
        "CREATE TRIGGER test_fail_user_exercise_delete "+
        "BEFORE DELETE ON user_exercise BEGIN "+
        "SELECT RAISE(ABORT, 'test delete failure'); END").result,
        raw.Result.Ok)
    delete_error := store_user_exercise_delete(store, identity)
    testing.expect_value(t, delete_error.kind, Store_Error_Kind.Write)
    active_after_delete, active_after_delete_error :=
        store_user_exercise_read_by_reference(store, "original")
    testing.expect_value(t, active_after_delete_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, active_after_delete.id, identity)
    testing.expect_value(t, store_exec(store,
        "DROP TRIGGER test_fail_user_exercise_delete").result, raw.Result.Ok)
}

// Roll back alias retirement and row changes together when a write trigger aborts.
@(test)
userdata_user_exercise_failed_updates_and_deletes_are_atomic :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    created, create_error := store_user_exercise_create(
        &store, userdata_test_exercise_draft(
            "original", "Original title", "Original instructions."))
    testing.expect_value(t, create_error.kind, Store_Error_Kind.None)
    userdata_test_exercise_failed_update_is_atomic(t, &store, created.id)
    userdata_test_exercise_failed_delete_is_atomic(t, &store, created.id)
    testing.expect_value(t,
        store_user_exercise_delete(&store, created.id).kind, Store_Error_Kind.None)
}

// Reject every mutation on an admitted read-only store while preserving reads.
@(test)
userdata_user_exercise_read_only_store_rejects_mutations :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    writable: Store
    testing.expect_value(t, store_open(&writable, fixture.path).kind,
        Store_Error_Kind.None)
    defer store_close(&writable)
    created, create_error := store_user_exercise_create(
        &writable, userdata_test_exercise_draft(
            "read-only", "Readable", "Stored before read-only admission."))
    testing.expect_value(t, create_error.kind, Store_Error_Kind.None)
    testing.expect_value(t, store_close(&writable).kind, Store_Error_Kind.None)

    readonly: Store
    testing.expect_value(t,
        store_open_internal(&readonly, fixture.path, false, true).kind,
        Store_Error_Kind.None)
    defer store_close(&readonly)
    _, read_error := store_user_exercise_read_by_identity(&readonly, created.id)
    testing.expect_value(t, read_error.kind, Store_Error_Kind.None)
    _, update_error := store_user_exercise_update(
        &readonly, created.id, userdata_test_exercise_draft(
            "changed", "Changed", "Must not persist."))
    testing.expect_value(t, update_error.kind, Store_Error_Kind.Not_Writable)
    testing.expect_value(t,
        store_user_exercise_delete(&readonly, created.id).kind,
        Store_Error_Kind.Not_Writable)
    _, create_readonly_error := store_user_exercise_create(
        &readonly, userdata_test_exercise_draft(
            "new-read-only", "New", "Must not persist."))
    testing.expect_value(t, create_readonly_error.kind, Store_Error_Kind.Not_Writable)
}
