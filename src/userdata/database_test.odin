#+test
package userdata

import raw "../../libs/sqlite3"
import sqlite "../sqlite"
import settings "../settings"
import collections "../collections"
import uuid "core:encoding/uuid"

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Userdata_Test_Path :: struct {
    directory: string,
    path: string,
    valid: bool,
}

// Create a deterministic nonzero UUID for collection persistence fixtures.
userdata_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Build a placement identity for a prospective Favorites root.
userdata_test_favorite_identity :: proc(
    entry_id: uuid.Identifier) -> collections.Placement_Identity {
    return {
        collection_id = collections.FAVORITES_COLLECTION_ID,
        entry_id = entry_id,
    }
}

// Build an immutable Favorites addition with explicit placement scope.
userdata_test_add_favorite :: proc(
    entry_id, animation_id: uuid.Identifier) -> collections.Mutation {
    return {
        kind = .Add_Favorite,
        placement = userdata_test_favorite_identity(entry_id),
        entry_id = entry_id,
        animation_id = animation_id,
    }
}

// Encode an integer as a stable UUID suffix for large persistence fixtures.
userdata_test_index_id :: proc(value: u32) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[12] = byte(value >> 24)
    identifier[13] = byte(value >> 16)
    identifier[14] = byte(value >> 8)
    identifier[15] = byte(value)
    return identifier
}

// Create a genuine v1 settings-only database for migration tests.
userdata_test_create_v1 :: proc(path: string) -> bool {
    connection: sqlite.Connection
    failure := userdata_test_open_sqlite(path, &connection)
    if !store_sqlite_error_is_clear(failure) {
        return false
    }
    failure = sqlite.connection_exec(&connection,
        strings.clone_to_cstring(USER_SETTING_SCHEMA_SQL, context.temp_allocator))
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.connection_exec(&connection,
            "INSERT INTO user_setting VALUES ('migration', 'kept', 'integer', 7, NULL)")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.connection_exec(
            &connection, "PRAGMA application_id=1163215701; PRAGMA user_version=1")
    }
    close_error := sqlite.connection_close(&connection)
    return store_sqlite_error_is_clear(failure) &&
        store_sqlite_error_is_clear(close_error)
}

// Create a unique temporary directory and database path for isolated tests.
userdata_test_path :: proc(t: ^testing.T) -> Userdata_Test_Path {
    result: Userdata_Test_Path
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return result
    }
    directory_name := fmt.tprintf("euclid-userdata-%x", uintptr(t))
    result.directory, _ = filepath.join(
        []string{temporary_directory, directory_name}, context.temp_allocator)
    if len(result.directory) == 0 ||
        os.make_directory_all(result.directory) != nil {
        return result
    }
    result.path, _ = filepath.join(
        []string{result.directory, DATABASE_FILENAME}, context.temp_allocator)
    result.valid = len(result.path) > 0
    return result
}

// Open a direct SQLite connection to construct or inspect a test fixture.
userdata_test_open_sqlite :: proc(
    path: string, connection: ^sqlite.Connection) -> sqlite.Error {
    return sqlite.connection_open(
        connection, path, .Readwrite_Create, context.temp_allocator)
}

// Query one scalar integer from a direct test connection.
userdata_test_integer_query :: proc(
    connection: ^sqlite.Connection, sql: string) -> (i64, bool) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare(
        connection, &statement, strings.clone_to_cstring(sql, context.temp_allocator))
    if !store_sqlite_error_is_clear(failure) {
        return 0, false
    }
    status, step_error := sqlite.statement_step(&statement)
    failure = step_error
    if !store_sqlite_error_is_clear(failure) || status != .Row {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    value, column_error := sqlite.column_i64(&statement, 0)
    failure = column_error
    if !store_sqlite_error_is_clear(failure) {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    status, failure = sqlite.statement_step(&statement)
    if !store_sqlite_error_is_clear(failure) || status != .Done {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    failure = sqlite.statement_finalize(&statement)
    return value, store_sqlite_error_is_clear(failure)
}

// Require a rejected row to preserve the schema's SQLite constraint result.
userdata_expect_constraint :: proc(
    t: ^testing.T, store: ^Store, sql: string) {
    testing.expect_value(t, store_exec(store, sql).result, raw.Result.Constraint)
}

// Verify the store's durable identity and schema version through SQLite.
userdata_expect_database_identity :: proc(
    t: ^testing.T, connection: ^sqlite.Connection) {
    application_id, app_valid := userdata_test_integer_query(
        connection, "PRAGMA application_id")
    schema_version, version_valid := userdata_test_integer_query(
        connection, "PRAGMA user_version")
    history_table_count, history_table_valid := userdata_test_integer_query(
        connection,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name='user_terminal_history'")
    testing.expect(t, app_valid && version_valid && history_table_valid)
    testing.expect_value(t, application_id, i64(DATABASE_APPLICATION_ID))
    testing.expect_value(t, schema_version, i64(DATABASE_SCHEMA_VERSION))
    testing.expect_value(t, history_table_count, i64(1))
}

// Resolve stable default and explicit paths without creating database files.
@(test)
userdata_paths_are_durable_bounded_and_absolute :: proc(t: ^testing.T) {
    default_path, default_error := default_database_path(context.temp_allocator)
    testing.expect_value(t, default_error, Path_Error.None)
    testing.expect(t, filepath.is_abs(default_path))
    testing.expect_value(t, filepath.base(default_path), DATABASE_FILENAME)

    relative_path, relative_error := resolve_database_path(
        ".build/settings.sqlite3", context.temp_allocator)
    testing.expect_value(t, relative_error, Path_Error.None)
    testing.expect(t, filepath.is_abs(relative_path))
    testing.expect(t, strings.has_suffix(relative_path, "settings.sqlite3"))

    _, empty_error := resolve_database_path("", context.temp_allocator)
    testing.expect_value(t, empty_error, Path_Error.Invalid)
    nul_path := strings.concatenate(
        {"settings", "\x00", ".sqlite3"}, context.temp_allocator)
    _, nul_error := resolve_database_path(nul_path, context.temp_allocator)
    testing.expect_value(t, nul_error, Path_Error.Invalid)
    long_path := make([]u8, DATABASE_PATH_MAX_BYTES + 1, context.temp_allocator)
    for index in 0..<len(long_path) {
        long_path[index] = 'x'
    }
    _, long_error := resolve_database_path(
        string(long_path), context.temp_allocator)
    testing.expect_value(t, long_error, Path_Error.Too_Long)
}

// Retain only the returned path allocation and release it through the same owner.
@(test)
userdata_paths_release_intermediates_and_return_owned_strings :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    allocator := mem.tracking_allocator(&tracker)
    default_path, default_error := default_database_path(allocator)
    testing.expect_value(t, default_error, Path_Error.None)
    testing.expect_value(t, len(tracker.allocation_map), 1)
    testing.expect_value(t, tracker.current_memory_allocated, i64(len(default_path)))
    relative_path, relative_error := resolve_database_path(
        ".build/settings.sqlite3", allocator)
    testing.expect_value(t, relative_error, Path_Error.None)
    testing.expect_value(t, len(tracker.allocation_map), 2)
    absolute_path, absolute_error := resolve_database_path(relative_path, allocator)
    testing.expect_value(t, absolute_error, Path_Error.None)
    testing.expect_value(t, absolute_path, relative_path)
    testing.expect_value(t, len(tracker.allocation_map), 3)
    delete(absolute_path, allocator)
    delete(relative_path, allocator)
    delete(default_path, allocator)
    testing.expect_value(t, len(tracker.allocation_map), 0)
    testing.expect_value(t, tracker.current_memory_allocated, i64(0))
    testing.expect_value(t, len(tracker.bad_free_array), 0)
}

// Release joined paths rejected only after adding the working-directory prefix.
@(test)
userdata_rejected_paths_leave_no_allocations :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    allocator := mem.tracking_allocator(&tracker)
    filename := make([]u8, DATABASE_PATH_MAX_BYTES, context.temp_allocator)
    for index in 0..<len(filename) {
        filename[index] = 'x'
    }
    path, failure := resolve_database_path(string(filename), allocator)
    testing.expect_value(t, failure, Path_Error.Too_Long)
    testing.expect_value(t, path, "")
    _, empty_error := resolve_database_path("", allocator)
    testing.expect_value(t, empty_error, Path_Error.Invalid)
    testing.expect_value(t, len(tracker.allocation_map), 0)
    testing.expect_value(t, tracker.current_memory_allocated, i64(0))
    testing.expect_value(t, len(tracker.bad_free_array), 0)
}

// Preserve user-controlled rows while changing known settings.
@(test)
userdata_store_creates_identity_and_preserves_unknown_rows :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    failure := store_open(&store, fixture.path)
    testing.expect_value(t, failure.kind, Store_Error_Kind.None)
    testing.expect_value(t, store.status, Store_Status.Ready)
    testing.expect(t, store.collection_replay_workspace.initialized)
    testing.expect(t, len(string(store.path[:store.path_length])) > 0)
    testing.expect_value(t,
        store_exec(&store,
            "INSERT INTO user_setting VALUES ('future', 'retained', 'text', NULL, 'keep')").
            result,
        raw.Result.Ok)

    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Window_Mode, settings.window_mode_value(.Resizable)))
    testing.expect_value(t, store_commit_batch(&store, changes).outcome,
        Commit_Outcome.Committed)
    retained, retained_valid := userdata_test_integer_query(
        &store.connection,
        "SELECT COUNT(*) FROM user_setting WHERE namespace='future' AND key='retained'")
    testing.expect(t, retained_valid)
    testing.expect_value(t, retained, i64(1))
    userdata_expect_database_identity(t, &store.connection)
    testing.expect_value(t,
        store_close(&store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store.status, Store_Status.Closed)
    testing.expect(t, !store.collection_replay_workspace.initialized)
}

// Enforce scalar types, NULL exclusion, byte caps, and composite-key uniqueness.
@(test)
userdata_schema_rejects_invalid_scalar_rows :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(
        t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    valid_sql := "INSERT INTO user_setting VALUES " +
        "('rendering', 'vsync', 'boolean', 1, NULL)"
    testing.expect_value(t, store_exec(&store, valid_sql).result, raw.Result.Ok)
    userdata_expect_constraint(t, &store, valid_sql)
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_setting VALUES ('x', 'bad-bool', 'boolean', 2, NULL)")
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_setting VALUES ('x', 'bad-null', 'boolean', NULL, NULL)")
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_setting VALUES ('x', 'bad-dual', 'integer', 1, 'x')")
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_setting VALUES ('x', 'long-text', 'text', NULL, "+
        "printf('%065d', 0))")
    long_key := fmt.tprintf("%065d", 0)
    long_key_sql := fmt.tprintf(
        "INSERT INTO user_setting VALUES ('x', '%s', 'integer', 1, NULL)",
        long_key)
    userdata_expect_constraint(t, &store, long_key_sql)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Insert malformed known values only after disabling SQLite CHECK constraints.
userdata_insert_malformed_known_values :: proc(t: ^testing.T, store: ^Store) {
    testing.expect_value(
        t, store_exec(store, "PRAGMA ignore_check_constraints=ON").result,
        raw.Result.Ok)
    userdata_expect_constraint_disabled_insert(t, store,
        "INSERT INTO user_setting VALUES ('rendering', 'vsync', 'boolean', 2, NULL)")
    userdata_expect_constraint_disabled_insert(t, store,
        "INSERT INTO user_setting VALUES ('window', 'mode', 'text', NULL, 'fluid')")
    userdata_expect_constraint_disabled_insert(t, store,
        "INSERT INTO user_setting VALUES ('window', 'layout', 'text', 1, 'auto')")
}

// Insert one deliberately invalid row while preserving the test's SQL error.
userdata_expect_constraint_disabled_insert :: proc(
    t: ^testing.T, store: ^Store, sql: string) {
    testing.expect_value(t, store_exec(store, sql).result, raw.Result.Ok)
}

// Assert invalid rows are reported without changing defaults or stored values.
userdata_expect_invalid_snapshot :: proc(
    t: ^testing.T,
    result: Load_Result,
    preferences: settings.Preferences) {
    testing.expect_value(t, result.failure.kind, Store_Error_Kind.None)
    testing.expect_value(t, result.invalid_count, 3)
    testing.expect_value(t, preferences.window.width, 900)
    testing.expect_value(t, preferences.window.mode, settings.Window_Mode.Fixed)
    testing.expect_value(t, preferences.window.layout, settings.Layout_Preference.Auto)
    testing.expect(t, settings.Setting_Id.Window_Width in preferences.present)
    testing.expect(t, settings.Setting_Id.Rendering_Vsync not_in preferences.present)
    testing.expect(t, settings.Setting_Id.Window_Mode not_in preferences.present)
    testing.expect(t, settings.Setting_Id.Window_Layout not_in preferences.present)
}

// Load typed known values, report corrupt rows, and preserve their stored data.
@(test)
userdata_load_validates_known_rows_and_keeps_invalid_values_defaulted :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(
        t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_exec(&store,
            "INSERT INTO user_setting VALUES ('window', 'width', 'integer', 900, NULL)").
            result,
        raw.Result.Ok)
    userdata_insert_malformed_known_values(t, &store)
    preferences := settings.default_preferences()
    result := store_load_settings(&store, &preferences)
    userdata_expect_invalid_snapshot(t, result, preferences)
    stored_invalid_value, stored_invalid_value_valid := userdata_test_integer_query(
        &store.connection,
        "SELECT integer_value FROM user_setting WHERE namespace='rendering' AND key='vsync'")
    testing.expect(t, stored_invalid_value_valid)
    testing.expect_value(t, stored_invalid_value, i64(2))
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Read committed rows from only known keys and clear a setting through deletion.
@(test)
userdata_commit_load_and_reset_use_atomic_known_key_batches :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(
        t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Window_Width, settings.integer_value(1440)))
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    testing.expect(t, settings.change_set_set(
        &changes, .Window_Mode, settings.window_mode_value(.Resizable)))
    testing.expect_value(t, store_commit_batch(&store, changes).outcome,
        Commit_Outcome.Committed)

    preferences := settings.default_preferences()
    loaded := store_load_settings(&store, &preferences)
    testing.expect_value(t, loaded.failure.kind, Store_Error_Kind.None)
    testing.expect_value(t, preferences.window.width, 1440)
    testing.expect_value(t, preferences.window.mode, settings.Window_Mode.Resizable)
    testing.expect(t, !preferences.rendering.vsync && preferences.present ==
        settings.Setting_Set{.Window_Width, .Window_Mode, .Rendering_Vsync})

    reset: settings.Change_Set
    testing.expect(t, settings.change_set_reset(&reset, .Rendering_Vsync))
    testing.expect_value(t, store_commit_batch(&store, reset).outcome,
        Commit_Outcome.Committed)
    preferences = settings.default_preferences()
    loaded = store_load_settings(&store, &preferences)
    testing.expect_value(t, loaded.failure.kind, Store_Error_Kind.None)
    testing.expect(t, preferences.rendering.vsync)
    testing.expect(t, .Rendering_Vsync not_in preferences.present)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Roll back all writes when a later operation in the same batch fails.
@(test)
userdata_failed_batch_rolls_back_every_setting :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(
        t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Window_Width, settings.integer_value(1500)))
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    result := store_commit_batch_internal(&store, changes, 1)
    testing.expect_value(t, result.outcome, Commit_Outcome.Not_Committed)
    testing.expect_value(t, result.failure.kind, Store_Error_Kind.Write)
    testing.expect_value(t, store.status, Store_Status.Ready)

    preferences := settings.default_preferences()
    loaded := store_load_settings(&store, &preferences)
    testing.expect_value(t, loaded.failure.kind, Store_Error_Kind.None)
    testing.expect_value(t, loaded.invalid_count, 0)
    testing.expect_value(t, preferences.window.width, 1280)
    testing.expect(t, preferences.rendering.vsync)
    testing.expect(t, preferences.present == {})
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Report an actual failed rollback as unusable instead of claiming no commit.
@(test)
userdata_rollback_failure_marks_store_unusable :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    testing.expect_value(
        t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_exec(&store,
            "CREATE TRIGGER rollback_injection AFTER INSERT ON user_setting "+
            "WHEN NEW.key='vsync' BEGIN "+
            "SELECT RAISE(ROLLBACK, 'injected rollback failure'); END").result,
        raw.Result.Ok)
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    result := store_commit_batch(&store, changes)
    testing.expect_value(t, result.outcome, Commit_Outcome.Store_Unusable)
    testing.expect_value(t, store.status, Store_Status.Unusable)
    testing.expect(t, result.failure.cleanup_error.result != raw.Result.Ok)
    testing.expect_value(t, result.failure.kind, Store_Error_Kind.Write)
    testing.expect_value(t,
        store_commit_batch(&store, changes).failure.kind, Store_Error_Kind.Unusable)
    preferences := settings.default_preferences()
    testing.expect_value(t, store_load_settings(&store, &preferences).failure.kind,
        Store_Error_Kind.Unusable)
    cleanup := store_close(&store)
    testing.expect_value(t, store.status, Store_Status.Closed)
    testing.expect_value(t, cleanup.kind, Store_Error_Kind.None)
}

// Prove a collection replay error rolls back an earlier settings write.
userdata_test_expect_combined_rollback :: proc(
    t: ^testing.T, store: ^Store, changes: settings.Change_Set) {
    invalid: collections.Mutation = {
        kind = .Remove_Favorite,
        placement = userdata_test_favorite_identity(userdata_test_id(71)),
        entry_id = userdata_test_id(71),
    }
    failed := store_commit_user_data(
        store, changes, []collections.Mutation{invalid})
    testing.expect_value(t, failed.outcome, Commit_Outcome.Not_Committed)
    testing.expect_value(t, store^.status, Store_Status.Ready)
    preferences := settings.default_preferences()
    loaded := store_load_settings(store, &preferences)
    testing.expect_value(t, loaded.failure.kind, Store_Error_Kind.None)
    testing.expect(t, preferences.rendering.vsync)
}

// Roll back settings when ordered collection replay fails in the shared transaction.
@(test)
userdata_combined_commit_is_atomic_for_settings_and_collections :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    userdata_test_expect_combined_rollback(t, &store, changes)

    add_mutation := userdata_test_add_favorite(
        userdata_test_id(72), userdata_test_id(73))
    committed := store_commit_user_data(
        &store, changes, []collections.Mutation{add_mutation})
    testing.expect_value(t, committed.outcome, Commit_Outcome.Committed)
    preferences := settings.default_preferences()
    testing.expect_value(t, store_load_settings(&store, &preferences).failure.kind,
        Store_Error_Kind.None)
    testing.expect(t, !preferences.rendering.vsync)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect_value(t, store_load_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.entry_count, 1)
    testing.expect_value(t, snapshot^.entries[0].id, add_mutation.entry_id)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Assert persisted Favorites identity and animation order without assuming row order.
userdata_test_expect_favorites_order :: proc(
    t: ^testing.T, snapshot: ^collections.Set,
    expected_entries, expected_animations: []uuid.Identifier) {
    testing.expect_value(t, len(expected_entries), len(expected_animations))
    indexes: [collections.ENTRY_INDEX_BUFFER_CAPACITY]int
    count, failure := collections.ordered_siblings(
        snapshot, collections.FAVORITES_COLLECTION_ID, {}, indexes[:])
    testing.expect_value(t, failure, collections.Policy_Error.None)
    testing.expect_value(t, count, len(expected_entries))
    if count != len(expected_entries) || count != len(expected_animations) {
        return
    }
    for position in 0..<count {
        entry := snapshot.entries[indexes[position]]
        testing.expect_value(t, entry.id, expected_entries[position])
        testing.expect_value(t, entry.animation_id, expected_animations[position])
    }
}

// Seed a durable Favorites sequence and return its immutable add operations.
userdata_test_seed_favorites :: proc(
    t: ^testing.T, store: ^Store) -> [3]collections.Mutation {
    additions: [3]collections.Mutation = {
        userdata_test_add_favorite(userdata_test_id(31), userdata_test_id(41)),
        userdata_test_add_favorite(userdata_test_id(32), userdata_test_id(42)),
        userdata_test_add_favorite(userdata_test_id(33), userdata_test_id(43)),
    }
    initial := store_commit_user_data(
        store, {}, additions[:])
    testing.expect_value(t, initial.outcome, Commit_Outcome.Committed)
    return additions
}

// Verify a rejected transaction preserved saved order and preferences.
userdata_test_expect_failed_reorder_unchanged :: proc(
    t: ^testing.T, store: ^Store, additions: [3]collections.Mutation) {
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect_value(t, store_load_collections(store, snapshot).kind,
        Store_Error_Kind.None)
    userdata_test_expect_favorites_order(t, snapshot,
        []uuid.Identifier{
            additions[0].entry_id, additions[1].entry_id, additions[2].entry_id,
        },
        []uuid.Identifier{
            additions[0].animation_id,
            additions[1].animation_id,
            additions[2].animation_id,
        })
    preferences := settings.default_preferences()
    testing.expect_value(t, store_load_settings(store, &preferences).failure.kind,
        Store_Error_Kind.None)
    testing.expect(t, preferences.rendering.vsync)
}

// Roll back settings and an earlier valid swap when later replay is stale.
@(test)
userdata_collection_mutation_rollback_is_atomic :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    additions := userdata_test_seed_favorites(t, &store)
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    move: collections.Mutation = {
        kind = .Reorder_Siblings,
        placement = additions[0].placement,
        entry_id = additions[0].entry_id,
        sibling_entry_id = additions[1].entry_id,
        direction = .Down,
    }
    rollback := store_commit_user_data(
        &store, changes, []collections.Mutation{move, move})
    testing.expect_value(t, rollback.outcome, Commit_Outcome.Not_Committed)
    userdata_test_expect_failed_reorder_unchanged(t, &store, additions)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Commit a mixed settings and structural batch that leaves a deliberate order.
userdata_test_commit_reordered_favorites :: proc(
    t: ^testing.T, store: ^Store, additions: [3]collections.Mutation) {
    a, b, c := additions[0], additions[1], additions[2]
    changes: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &changes, .Rendering_Vsync, settings.boolean_value(false)))
    d := userdata_test_add_favorite(
        userdata_test_id(34), userdata_test_id(44))
    move_a_down_b: collections.Mutation = {
        kind = .Reorder_Siblings,
        placement = a.placement,
        entry_id = a.entry_id,
        sibling_entry_id = b.entry_id,
        direction = .Down,
    }
    move_a_down_c: collections.Mutation = {
        kind = .Reorder_Siblings,
        placement = a.placement,
        entry_id = a.entry_id,
        sibling_entry_id = c.entry_id,
        direction = .Down,
    }
    remove_b: collections.Mutation = {
        kind = .Remove_Favorite,
        placement = b.placement,
        entry_id = b.entry_id,
    }
    committed := store_commit_user_data(store, changes,
        []collections.Mutation{d, move_a_down_b, move_a_down_c, remove_b})
    testing.expect_value(t, committed.outcome, Commit_Outcome.Committed)
}

// Persist add, repeated move, and remove operations through close and reopen.
@(test)
userdata_collection_mutation_moves_round_trip_after_reopen :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    additions := userdata_test_seed_favorites(t, &store)
    a, b, c := additions[0], additions[1], additions[2]
    d: collections.Mutation = {
        entry_id = userdata_test_id(34),
        animation_id = userdata_test_id(44),
    }
    userdata_test_commit_reordered_favorites(t, &store, additions)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)

    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    reopened := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(reopened)
    testing.expect_value(t, store_load_collections(&store, reopened).kind,
        Store_Error_Kind.None)
    userdata_test_expect_favorites_order(t, reopened,
        []uuid.Identifier{c.entry_id, a.entry_id, d.entry_id},
        []uuid.Identifier{c.animation_id, a.animation_id, d.animation_id})
    preferences := settings.default_preferences()
    testing.expect_value(t, store_load_settings(&store, &preferences).failure.kind,
        Store_Error_Kind.None)
    testing.expect(t, !preferences.rendering.vsync)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Open a test database and add one Favorites placement for entry-name persistence tests.
userdata_test_open_favorites_entry :: proc(
    t: ^testing.T, store: ^Store, path: string, entry_id: uuid.Identifier) {
    testing.expect_value(t, store_open(store, path).kind, Store_Error_Kind.None)
    add := userdata_test_add_favorite(entry_id, userdata_test_id(82))
    testing.expect_value(t,
        store_commit_user_data(store, {}, []collections.Mutation{add}).outcome,
        Commit_Outcome.Committed)
}

// Assert whether a persisted placement name is represented by SQL NULL.
userdata_test_expect_entry_name_null :: proc(
    t: ^testing.T, store: ^Store, expected_null: bool) {
    stored_null, valid := userdata_test_integer_query(
        &store^.connection,
        "SELECT custom_name IS NULL FROM user_collection_entry "+
        "WHERE entry_id=X'00000000000000000000000000000051'")
    testing.expect(t, valid)
    testing.expect_value(t, stored_null, i64(expected_null ? 1 : 0))
}

// Persist a maximum-length Unicode name across close and reopen.
@(test)
userdata_collection_entry_name_round_trip :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    entry_id := userdata_test_id(81)
    store: Store
    userdata_test_open_favorites_entry(t, &store, fixture.path, entry_id)
    name_bytes: [collections.ENTRY_NAME_MAX_BYTES]u8
    for index in 0..<254 {
        name_bytes[index] = 'x'
    }
    name_bytes[254] = 0xc3
    name_bytes[255] = 0xa9
    name := string(name_bytes[:])
    identity := userdata_test_favorite_identity(entry_id)
    set_name, name_error := collections.make_placement_name_mutation(
        identity, name)
    testing.expect_value(t, name_error, collections.Mutation_Error.None)
    testing.expect_value(t,
        store_commit_user_data(&store, {}, []collections.Mutation{set_name}).outcome,
        Commit_Outcome.Committed)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)

    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, loaded^.entries[0].id, entry_id)
    testing.expect_value(t, loaded^.entries[0].custom_name_length,
        collections.ENTRY_NAME_MAX_BYTES)
    testing.expect_value(t, string(loaded^.entries[0].custom_name[:]), name)
    userdata_test_expect_entry_name_null(t, &store, false)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Clear a persisted placement name and verify SQL stores absence as NULL.
@(test)
userdata_collection_entry_name_clear_stores_null :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    entry_id := userdata_test_id(81)
    store: Store
    userdata_test_open_favorites_entry(t, &store, fixture.path, entry_id)
    identity := userdata_test_favorite_identity(entry_id)
    set_name, _ := collections.make_placement_name_mutation(identity, "Custom")
    testing.expect_value(t,
        store_commit_user_data(&store, {}, []collections.Mutation{set_name}).outcome,
        Commit_Outcome.Committed)
    clear_name, clear_error := collections.make_placement_name_mutation(identity, "")
    testing.expect_value(t, clear_error, collections.Mutation_Error.None)
    testing.expect_value(t,
        store_commit_user_data(&store, {}, []collections.Mutation{clear_name}).outcome,
        Commit_Outcome.Committed)
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, loaded^.entries[0].custom_name_length, 0)
    userdata_test_expect_entry_name_null(t, &store, true)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Reject malformed stored UTF-8 while preserving the validated snapshot boundary.
@(test)
userdata_collection_entry_name_rejects_invalid_stored_utf8 :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    userdata_test_open_favorites_entry(
        t, &store, fixture.path, userdata_test_id(81))
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_exec(&store,
        "UPDATE user_collection_entry SET custom_name=CAST(X'FF' AS TEXT) "+
        "WHERE entry_id=X'00000000000000000000000000000051'").result,
        raw.Result.Ok)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.Read)
    testing.expect_value(t, store_exec(&store,
        "UPDATE user_collection_entry SET custom_name=NULL "+
        "WHERE entry_id=X'00000000000000000000000000000051'").result,
        raw.Result.Ok)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Roll back every operation when a later mutation in the same batch is invalid.
@(test)
userdata_collection_entry_name_batch_rolls_back_atomically :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    entry_id := userdata_test_id(81)
    store: Store
    userdata_test_open_favorites_entry(t, &store, fixture.path, entry_id)
    identity := userdata_test_favorite_identity(entry_id)
    set_name, _ := collections.make_placement_name_mutation(identity, "Custom")
    invalid: collections.Mutation = {
        kind = .Remove_Favorite,
        placement = userdata_test_favorite_identity(userdata_test_id(99)),
        entry_id = userdata_test_id(99),
    }
    rollback := store_commit_user_data(
        &store, {}, []collections.Mutation{set_name, invalid})
    testing.expect_value(t, rollback.outcome, Commit_Outcome.Not_Committed)
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, loaded^.entries[0].custom_name_length, 0)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Reject wrong application IDs and future schema versions without rewriting them.
@(test)
userdata_admission_preserves_wrong_and_future_databases :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    userdata_rejects_wrong_application(t, fixture.directory)
    userdata_rejects_future_schema(t, fixture.directory)
}

// Reject a foreign application identity without rewriting its schema.
userdata_rejects_wrong_application :: proc(
    t: ^testing.T, directory: string) {
    wrong_path, _ := filepath.join(
        []string{directory, "wrong.sqlite3"}, context.temp_allocator)
    wrong: sqlite.Connection
    testing.expect_value(t,
        userdata_test_open_sqlite(wrong_path, &wrong).result, raw.Result.Ok)
    testing.expect_value(t,
        sqlite.connection_exec(&wrong,
            "CREATE TABLE preserved(value INTEGER); PRAGMA application_id=1").
            result,
        raw.Result.Ok)
    testing.expect_value(t, sqlite.connection_close(&wrong).result, raw.Result.Ok)
    rejected: Store
    wrong_result := store_open(&rejected, wrong_path)
    testing.expect_value(t, wrong_result.kind, Store_Error_Kind.Wrong_Application)
    inspect_wrong: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&inspect_wrong, wrong_path, .Readonly,
            context.temp_allocator).result,
        raw.Result.Ok)
    count, count_valid := userdata_test_integer_query(
        &inspect_wrong, "SELECT COUNT(*) FROM preserved")
    testing.expect(t, count_valid)
    testing.expect_value(t, count, i64(0))
    testing.expect_value(t, sqlite.connection_close(&inspect_wrong).result,
        raw.Result.Ok)
}

// Reject a future schema version while preserving its recorded version.
userdata_rejects_future_schema :: proc(
    t: ^testing.T, directory: string) {
    future_path, _ := filepath.join(
        []string{directory, "future.sqlite3"}, context.temp_allocator)
    future: Store
    testing.expect_value(
        t, store_open(&future, future_path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_close(&future).kind, Store_Error_Kind.None)
    update: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&update, future_path, .Readwrite,
            context.temp_allocator).result,
        raw.Result.Ok)
    testing.expect_value(t,
        sqlite.connection_exec(&update, "PRAGMA user_version=3").result,
        raw.Result.Ok)
    testing.expect_value(t, sqlite.connection_close(&update).result,
        raw.Result.Ok)
    rejected: Store
    future_result := store_open(&rejected, future_path)
    testing.expect_value(t, future_result.kind, Store_Error_Kind.Future_Schema)
    testing.expect_value(t, future_result.schema_version, i64(3))
}

// Roll back partially initialized schema and identity after migration failure.
@(test)
userdata_initial_migration_failure_leaves_empty_database :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    store: Store
    failure := store_open_internal(&store, fixture.path, true, false)
    testing.expect_value(t, failure.kind, Store_Error_Kind.Migration)
    inspect: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&inspect, fixture.path, .Readonly,
            context.temp_allocator).result,
        raw.Result.Ok)
    application_id, app_valid := userdata_test_integer_query(
        &inspect, "PRAGMA application_id")
    version, version_valid := userdata_test_integer_query(
        &inspect, "PRAGMA user_version")
    objects, objects_valid := userdata_test_integer_query(
        &inspect,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")
    testing.expect(t, app_valid && version_valid && objects_valid)
    testing.expect_value(t, application_id, i64(0))
    testing.expect_value(t, version, i64(0))
    testing.expect_value(t, objects, i64(0))
    testing.expect_value(t, sqlite.connection_close(&inspect).result,
        raw.Result.Ok)
}

// Admit valid databases read-only and reject writes without changing saved rows.
@(test)
userdata_read_only_admission_loads_without_writing :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    writable: Store
    testing.expect_value(
        t, store_open(&writable, fixture.path).kind, Store_Error_Kind.None)
    initial: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &initial, .Window_Width, settings.integer_value(1000)))
    testing.expect_value(t, store_commit_batch(&writable, initial).outcome,
        Commit_Outcome.Committed)
    testing.expect_value(t, store_close(&writable).kind, Store_Error_Kind.None)

    readonly: Store
    testing.expect_value(t,
        store_open_internal(&readonly, fixture.path, false, true).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, readonly.status, Store_Status.Read_Only)
    preferences := settings.default_preferences()
    result := store_load_settings(&readonly, &preferences)
    testing.expect_value(t, result.failure.kind, Store_Error_Kind.None)
    testing.expect_value(t, preferences.window.width, 1000)
    change: settings.Change_Set
    testing.expect(t, settings.change_set_set(
        &change, .Window_Width, settings.integer_value(1100)))
    testing.expect_value(t, store_commit_batch(&readonly, change).failure.kind,
        Store_Error_Kind.Not_Writable)
    testing.expect_value(t, store_close(&readonly).kind, Store_Error_Kind.None)
}

// Require the bundled SQLite build to support exclusive sequential handoff.
@(test)
userdata_sqlite_build_is_mutex_enabled :: proc(t: ^testing.T) {
    testing.expect(t, sqlite.threading_supported())
}

// Upgrade v1 atomically, retain user settings, and seed exactly one editable Favorites role.
@(test)
userdata_v1_migration_preserves_settings_and_seeds_favorites :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    testing.expect(t, userdata_test_create_v1(fixture.path))

    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect_value(t, store_load_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.collection_count, 1)
    testing.expect_value(t, snapshot^.collections[0].role, collections.Role.Favorites)
    testing.expect_value(t,
        snapshot^.collections[0].id, collections.FAVORITES_COLLECTION_ID)
    testing.expect(t, !snapshot^.collections[0].is_read_only)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)

    inspect: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&inspect, fixture.path, .Readonly,
            context.temp_allocator).result,
        raw.Result.Ok)
    version, version_valid := userdata_test_integer_query(&inspect, "PRAGMA user_version")
    history_table_count, history_table_valid := userdata_test_integer_query(
        &inspect,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name='user_terminal_history'")
    preserved, preserved_valid := userdata_test_integer_query(
        &inspect, "SELECT integer_value FROM user_setting WHERE namespace='migration'")
    testing.expect(t, version_valid && preserved_valid && history_table_valid)
    testing.expect_value(t, version, i64(2))
    testing.expect_value(t, preserved, i64(7))
    testing.expect_value(t, history_table_count, i64(1))
    testing.expect_value(t, sqlite.connection_close(&inspect).result, raw.Result.Ok)
}

// Keep a read-only v1 database untouched and report that in-place migration is unavailable.
@(test)
userdata_read_only_v1_migration_is_rejected_without_mutation :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    testing.expect(t, userdata_test_create_v1(fixture.path))

    store: Store
    result := store_open_internal(&store, fixture.path, false, true)
    testing.expect_value(t, result.kind, Store_Error_Kind.Not_Writable)
    testing.expect_value(t, result.schema_version, i64(1))
    inspect: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&inspect, fixture.path, .Readonly,
            context.temp_allocator).result,
        raw.Result.Ok)
    version, version_valid := userdata_test_integer_query(&inspect, "PRAGMA user_version")
    collections_count, collections_valid := userdata_test_integer_query(
        &inspect,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name='user_collection'")
    testing.expect(t, version_valid && collections_valid)
    testing.expect_value(t, version, i64(1))
    testing.expect_value(t, collections_count, i64(0))
    testing.expect_value(t, sqlite.connection_close(&inspect).result, raw.Result.Ok)
}

// Roll back a failed v1 migration without damaging its prior settings schema.
@(test)
userdata_failed_v1_migration_rolls_back_schema_and_version :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    testing.expect(t, userdata_test_create_v1(fixture.path))

    store: Store
    result := store_open_internal(&store, fixture.path, true, false)
    testing.expect_value(t, result.kind, Store_Error_Kind.Migration)
    inspect: sqlite.Connection
    testing.expect_value(t,
        sqlite.connection_open(&inspect, fixture.path, .Readonly,
            context.temp_allocator).result,
        raw.Result.Ok)
    version, version_valid := userdata_test_integer_query(&inspect, "PRAGMA user_version")
    collection_tables, tables_valid := userdata_test_integer_query(
        &inspect,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name LIKE 'user_collection%'")
    preserved, preserved_valid := userdata_test_integer_query(
        &inspect, "SELECT integer_value FROM user_setting WHERE namespace='migration'")
    testing.expect(t, version_valid && tables_valid && preserved_valid)
    testing.expect_value(t, version, i64(1))
    testing.expect_value(t, collection_tables, i64(0))
    testing.expect_value(t, preserved, i64(7))
    testing.expect_value(t, sqlite.connection_close(&inspect).result, raw.Result.Ok)
}

// Build a bounded persistence fixture with Favorites and a nested read-only group.
userdata_test_free_collection_set :: proc(snapshot: ^collections.Set) {
    collections.destroy(snapshot)
    free(snapshot, context.allocator)
}

// Build a bounded persistence fixture with Favorites and a nested read-only group.
userdata_test_collection_snapshot :: proc(t: ^testing.T) -> ^collections.Set {
    snapshot := new(collections.Set, context.allocator)
    testing.expect(t, collections.initialize(snapshot))
    userdata_test_collection_records(t, snapshot)
    userdata_test_collection_entries(t, snapshot)
    return snapshot
}

// Add Favorites and named collection metadata to the persistence fixture.
userdata_test_collection_records :: proc(t: ^testing.T, snapshot: ^collections.Set) {
    name: [4]u8 = {'W', 'o', 'r', 'k'}
    testing.expect_value(t, collections.append_collection(snapshot, {
        id = userdata_test_id(41),
        role = .User,
        name = name[:],
        name_length = 4,
        order = 1,
        is_read_only = true,
    }), collections.Policy_Error.None)
}

// Add a nested group placement and its Favorites animation placement.
userdata_test_collection_entries :: proc(t: ^testing.T, snapshot: ^collections.Set) {
    root_id := userdata_test_id(42)
    nested_id := userdata_test_id(43)
    animation_id := userdata_test_id(44)
    testing.expect_value(t, collections.append_entry(snapshot, {
        id = root_id,
        collection_id = userdata_test_id(41),
        kind = .Group,
    }), collections.Policy_Error.None)
    testing.expect_value(t, collections.append_entry(snapshot, {
        id = nested_id,
        collection_id = userdata_test_id(41),
        parent_entry_id = root_id,
        kind = .Animation,
        animation_id = animation_id,
    }), collections.Policy_Error.None)
    testing.expect_value(t, collections.append_entry(snapshot, {
        id = userdata_test_id(45),
        collection_id = collections.FAVORITES_COLLECTION_ID,
        sibling_order = 0,
        kind = .Animation,
        animation_id = animation_id,
    }), collections.Policy_Error.None)
}

// Save one snapshot and reopen the same store path for durability assertions.
userdata_test_save_and_reopen :: proc(
    t: ^testing.T, path: string, snapshot: ^collections.Set, reopened: ^Store) {
    store: Store
    testing.expect_value(t, store_open(&store, path).kind, Store_Error_Kind.None)
    foreign_keys, foreign_keys_valid := userdata_test_integer_query(
        &store.connection, "PRAGMA foreign_keys")
    testing.expect(t, foreign_keys_valid)
    testing.expect_value(t, foreign_keys, i64(1))
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_collection_entry VALUES (" +
        "X'00000000000000000000000000000099', " +
        "X'00000000000000000000000000000098', NULL, 0, 'group', NULL, NULL)")
    userdata_expect_constraint(t, &store,
        "UPDATE user_collection SET is_read_only=1 WHERE system_role='favorites'")
    testing.expect_value(t, store_replace_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    userdata_expect_constraint(t, &store,
        "UPDATE user_collection_entry SET custom_name='' "+
        "WHERE entry_id=X'0000000000000000000000000000002D'")
    userdata_expect_constraint(t, &store,
        "UPDATE user_collection_entry SET custom_name=printf('%0257d', 0) "+
        "WHERE entry_id=X'0000000000000000000000000000002D'")
    userdata_expect_constraint(t, &store,
        "UPDATE user_collection_entry SET custom_name='a'||char(0)||'b' "+
        "WHERE entry_id=X'0000000000000000000000000000002D'")
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_open(reopened, path).kind, Store_Error_Kind.None)
}

// Verify reopened collection, placement, parent, order, and read-only fields.
userdata_test_expect_collection_snapshot :: proc(
    t: ^testing.T, loaded: ^collections.Set,
    root_id, animation_id: uuid.Identifier) {
    testing.expect_value(t, loaded^.collection_count, 2)
    testing.expect_value(t, loaded^.collections[1].id, userdata_test_id(41))
    testing.expect_value(t, loaded^.collections[1].name_length, 4)
    testing.expect_value(t, string(loaded^.collections[1].name[:4]), "Work")
    testing.expect(t, loaded^.collections[1].is_read_only)
    testing.expect_value(t, loaded^.entry_count, 3)
    testing.expect_value(t, loaded^.entries[0].id, root_id)
    testing.expect_value(t, loaded^.entries[1].parent_entry_id, root_id)
    testing.expect_value(t, loaded^.entries[1].sibling_order, i64(0))
    testing.expect_value(t, loaded^.entries[2].animation_id, animation_id)
    testing.expect_value(t, loaded^.entries[2].sibling_order, i64(0))
    testing.expect_value(t,
        collections.validate(loaded), collections.Validation_Error.None)
}

// Round-trip ordered entries, nested parentage, and read-only metadata through SQLite.
@(test)
userdata_collection_snapshot_round_trips_after_reopen :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    root_id := userdata_test_id(42)
    animation_id := userdata_test_id(44)
    reopened: Store
    userdata_test_save_and_reopen(t, fixture.path, snapshot, &reopened)
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_load_collections(&reopened, loaded).kind,
        Store_Error_Kind.None)
    userdata_test_expect_collection_snapshot(t, loaded, root_id, animation_id)
    testing.expect_value(t, store_close(&reopened).kind, Store_Error_Kind.None)
}

// Persist and reload more than the retired fixed-capacity row count.
@(test)
userdata_collection_snapshot_round_trips_more_than_512_entries :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    userdata_test_fill_large_favorites(t, snapshot)
    testing.expect_value(t, collections.validate(snapshot),
        collections.Validation_Error.None)
    store: Store
    userdata_test_replace_and_reopen_collections(t, fixture.path, snapshot, &store)
    loaded := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(loaded)
    testing.expect_value(t, store_load_collections(&store, loaded).kind,
        Store_Error_Kind.None)
    userdata_test_expect_large_collection_round_trip(t, loaded)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
}

// Build 1,024 Favorites rows with sparse optional names and unavailable targets.
userdata_test_fill_large_favorites :: proc(
    t: ^testing.T, snapshot: ^collections.Set) {
    for index in 0..<1024 {
        custom_name: []u8
        custom_name_length := 0
        if index == 256 {
            custom_label := "Saved offline label"
            custom_name = transmute([]u8)custom_label
            custom_name_length = len(custom_name)
        }
        entry: collections.Entry = {
            id = userdata_test_index_id(u32(index + 1)),
            collection_id = collections.FAVORITES_COLLECTION_ID,
            sibling_order = i64(index),
            kind = .Animation,
            animation_id = userdata_test_index_id(u32(index + 10000)),
            custom_name = custom_name,
            custom_name_length = custom_name_length,
        }
        testing.expect_value(t, collections.append_entry(snapshot, entry),
            collections.Policy_Error.None)
    }
}

// Persist a Set, close the database, and reopen it for replay assertions.
userdata_test_replace_and_reopen_collections :: proc(
    t: ^testing.T, path: string, snapshot: ^collections.Set, store: ^Store) {
    testing.expect_value(t, store_open(store, path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_replace_collections(store, snapshot).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, store_close(store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_open(store, path).kind, Store_Error_Kind.None)
}

// Compare every persisted identity, order, target, and optional name after reload.
userdata_test_expect_large_collection_round_trip :: proc(
    t: ^testing.T, loaded: ^collections.Set) {
    testing.expect_value(t, loaded^.entry_count, 1024)
    testing.expect_value(t, loaded^.entries[0].id, userdata_test_index_id(1))
    testing.expect_value(t, loaded^.entries[1023].id, userdata_test_index_id(1024))
    for index in 0..<1024 {
        entry_id := userdata_test_index_id(u32(index + 1))
        testing.expect_value(t, collections.find_entry(loaded, entry_id), index)
        testing.expect_value(t, loaded^.entries[index].id, entry_id)
        testing.expect_value(t,
            loaded^.entries[index].animation_id,
            userdata_test_index_id(u32(index + 10000)))
        testing.expect_value(t, loaded^.entries[index].sibling_order, i64(index))
        if index == 256 {
            testing.expect_value(t, loaded^.entries[index].custom_name_length, 19)
            testing.expect_value(t,
                string(loaded^.entries[index].custom_name), "Saved offline label")
        } else {
            testing.expect_value(t, loaded^.entries[index].custom_name_length, 0)
            testing.expect_value(t, len(loaded^.entries[index].custom_name), 0)
        }
    }
    testing.expect_value(t, collections.validate(loaded),
        collections.Validation_Error.None)
}
