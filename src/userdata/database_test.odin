#+test
package userdata

import raw "../../libs/sqlite3"
import sqlite "../sqlite"
import settings "../settings"

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
    testing.expect(t, app_valid && version_valid)
    testing.expect_value(t, application_id, i64(DATABASE_APPLICATION_ID))
    testing.expect_value(t, schema_version, i64(DATABASE_SCHEMA_VERSION))
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
        sqlite.connection_exec(&update, "PRAGMA user_version=2").result,
        raw.Result.Ok)
    testing.expect_value(t, sqlite.connection_close(&update).result,
        raw.Result.Ok)
    rejected: Store
    future_result := store_open(&rejected, future_path)
    testing.expect_value(t, future_result.kind, Store_Error_Kind.Future_Schema)
    testing.expect_value(t, future_result.schema_version, i64(2))
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
