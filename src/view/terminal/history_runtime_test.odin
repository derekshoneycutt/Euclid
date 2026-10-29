#+test
package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../terminal/history/store"
import protocol "../../core/protocol"
import sqlite "../../sqlite"
import taskpool "../../taskpool"
import viewuserdata "../userdata"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

History_Runtime_Test_Path :: struct {
    directory: string,
    filename: string,
}

// History_Runtime_Test_Fixture groups the resources owned by one runtime test.
History_Runtime_Test_Fixture :: struct {
    history: ^historyruntime.History_Runtime,
    connection: ^sqlite.Connection,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    create_persistent_table: bool,
}

// History_Runtime_Test_Startup selects the file-backed runtime's initial policy.
History_Runtime_Test_Startup :: struct {
    generation: u64,
    create_schema: bool,
    persist: bool,
}

// History_Runtime_Test_Read_Input bundles a browse request and its copy-out buffer.
History_Runtime_Test_Read_Input :: struct {
    request: historyruntime.History_Read_Request,
    destination: []u8,
}

// Create a private SQLite fixture path for read-only connection tests.
history_runtime_test_path :: proc(t: ^testing.T) -> History_Runtime_Test_Path {
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return {}
    }
    directory, _ := filepath.join(
        []string{temporary_directory, fmt.tprintf("euclid-history-%x", uintptr(t))},
        context.temp_allocator)
    if len(directory) == 0 || os.make_directory_all(directory) != nil {
        return {}
    }
    filename, _ := filepath.join(
        []string{directory, "history.sqlite3"}, context.temp_allocator)
    return {directory, filename}
}

// Remove one isolated SQLite fixture after all connection users have closed.
history_runtime_test_path_destroy :: proc(path: History_Runtime_Test_Path) {
    if len(path.directory) > 0 {
        _ = os.remove_all(path.directory)
    }
}

// Open an in-memory connection and initialize the asynchronous history service.
history_runtime_test_start :: proc(
    t: ^testing.T,
    fixture: History_Runtime_Test_Fixture) -> bool {
    failure := sqlite.connection_open(
        fixture.connection, ":memory:", .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect(t, fixture.connection.handle != nil)
    if fixture.create_persistent_table {
        _ = sqlite.connection_exec(fixture.connection,
            "CREATE TABLE user_terminal_history (" +
            "entry_id INTEGER PRIMARY KEY, source TEXT NOT NULL, mode INTEGER NOT NULL, " +
            "submitted_at_unix_ms INTEGER NOT NULL, terminal_generation INTEGER NOT NULL, " +
            "source_revision INTEGER NOT NULL);")
    }
    testing.expect(t, taskpool.task_pool_init(fixture.pool, 1, 3))
    history_runtime_start(fixture.history, fixture.connection)
    history_runtime_service(
        fixture.history, fixture.admission, fixture.pool, false)
    testing.expect(t, history_runtime_test_wait_task(
        fixture.history, fixture.admission, fixture.pool))
    testing.expect_value(t, fixture.history^.status,
        historyruntime.History_Runtime_Status.Ready)
    return fixture.history^.status == .Ready
}

// Bundle the resources shared by the default in-memory runtime test setup.
history_runtime_test_make_fixture :: proc(
    history: ^historyruntime.History_Runtime,
    connection: ^sqlite.Connection,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) -> History_Runtime_Test_Fixture {
    return {
        history = history,
        connection = connection,
        admission = admission,
        pool = pool,
    }
}

// Join the active history task by polling only after worker completion notification.
history_runtime_test_wait_task :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) -> bool {
    for _ in 0..<100 {
        if !history^.task_active {
            return true
        }
        taskpool.task_pool_wait_for_progress(pool)
        history_runtime_service(history, admission, pool, false)
    }
    return !history^.task_active
}

// Drain accepted writes and finalize the TEMP store before its connection closes.
history_runtime_test_shutdown :: proc(
    t: ^testing.T,
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) -> bool {
    viewuserdata.connection_admission_begin_drain(admission)
    history_runtime_begin_shutdown(history)
    for _ in 0..<64 {
        if history_runtime_shutdown_step(history, admission, pool, false) {
            return true
        }
        taskpool.task_pool_wait_for_progress(pool)
    }
    testing.expect_value(t, history^.status, historyruntime.History_Runtime_Status.Closed)
    return false
}

// Build valid stable record metadata for a bounded in-memory write.
history_runtime_test_record :: proc(
    id, generation: u64) -> termhiststore.History_Record {
    return {
        submission_id = id,
        mode = .Normal,
        submitted_at_unix_ms = i64(id),
        terminal_generation = generation,
        source_revision = 1,
    }
}

// Exercise the per-source and fixed-slot bounds without allocating a production mirror.
history_runtime_test_enqueue_full_queue :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime) -> int {
    source: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    for index in 0..<len(source) {
        source[index] = 'x'
    }
    oversized: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES + 1]u8
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(99, 1), string(oversized[:])),
        historyruntime.History_Runtime_Enqueue_Result.Source_Too_Large)
    for index in 0..<historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY {
        result := history_runtime_enqueue_insert(
            history, history_runtime_test_record(u64(index + 1), 1),
            string(source[:]))
        testing.expect_value(t,
            result, historyruntime.History_Runtime_Enqueue_Result.Queued)
    }
    testing.expect_value(t, history^.mutation_count,
        historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY)
    testing.expect_value(t, history^.queued_source_bytes,
        historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY * len(source))
    testing.expect(t, history^.queued_source_bytes <
        historyruntime.HISTORY_RUNTIME_MUTATION_SOURCE_BUDGET)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(100, 1), "overflow"),
        historyruntime.History_Runtime_Enqueue_Result.Queue_Full)
    return len(source)
}

// Complete one test-only worker without touching the SQLite connection.
history_runtime_test_save_worker :: proc(
    _: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    return .Succeeded
}

// Admit exactly eight maximum-sized sources and release waiting-byte accounting on transfer.
@(test)
history_runtime_admits_eight_max_sources_and_releases_waiting_bytes :: proc(
    t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    testing.expect(t, history_runtime_test_start(t, {
        history = history,
        connection = &connection,
        admission = &admission,
        pool = &pool,
    }))
    source_length := history_runtime_test_enqueue_full_queue(t, history)

    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history.task_active)
    testing.expect_value(t, history.mutation_count, 7)
    testing.expect_value(t, history.queued_source_bytes, 7 * source_length)
    testing.expect_value(t, history.active_mutation.source_length, source_length)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect_value(t, history.queued_source_bytes, 0)
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    testing.expect(t, viewuserdata.connection_admission_drain_complete(&admission))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// TEMP history remains writable when the admitted main database is read-only.
@(test)
history_runtime_initializes_temp_store_on_read_only_connection :: proc(t: ^testing.T) {
    path := history_runtime_test_path(t)
    testing.expect(t, len(path.filename) > 0)
    if len(path.filename) == 0 {
        return
    }
    history_runtime_test_create_persistent_fixture(t, path)
    history_runtime_test_readonly_write_fallback(t, path)
    history_runtime_test_path_destroy(path)
}

// Create the main tables before opening the fixture read-only.
history_runtime_test_create_persistent_fixture :: proc(
    t: ^testing.T, path: History_Runtime_Test_Path) {
    connection: sqlite.Connection
    open_failure := sqlite.connection_open(
        &connection, path.filename, .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, open_failure.validation, sqlite.Validation_Error.None)
    _ = sqlite.connection_exec(&connection, "CREATE TABLE persistent_probe (id INTEGER);")
    _ = sqlite.connection_exec(&connection,
        "CREATE TABLE user_terminal_history (" +
        "entry_id INTEGER PRIMARY KEY, source TEXT NOT NULL, mode INTEGER NOT NULL, " +
        "submitted_at_unix_ms INTEGER NOT NULL, terminal_generation INTEGER NOT NULL, " +
        "source_revision INTEGER NOT NULL);")
    _ = sqlite.connection_close(&connection)
}

// Keep TEMP history writable when the user database cannot accept durable writes.
history_runtime_test_readonly_write_fallback :: proc(
    t: ^testing.T, path: History_Runtime_Test_Path) {
    connection: sqlite.Connection
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    readonly_failure := sqlite.connection_open(
        &connection, path.filename, .Readonly, context.temp_allocator)
    testing.expect_value(t, readonly_failure.validation, sqlite.Validation_Error.None)
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    history_runtime_start(history, &connection)
    _ = history_runtime_set_persistence(history, true)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect_value(t, history.status, historyruntime.History_Runtime_Status.Ready)
    testing.expect(t, history.store.durable_available)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(1, 1), "temporary"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    history_runtime_test_expect_persistence_fallback(t, history)
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// Confirm a failed durable insert still commits only its session representation.
history_runtime_test_expect_persistence_fallback :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime) {
    testing.expect_value(t, history^.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Stored)
    testing.expect(t, history^.last_write_result.persistence_failed)
    testing.expect_value(t, history^.last_write_result.persistent_entry_id, u64(0))
    testing.expect_value(t, history^.persistence_status,
        historyruntime.History_Persistence_Status.Failed)
}

// Initialize one file-backed history runtime with an optional durable schema.
history_runtime_test_start_durable :: proc(
    t: ^testing.T, path: History_Runtime_Test_Path,
    fixture: History_Runtime_Test_Fixture,
    startup: History_Runtime_Test_Startup) -> bool {
    failure := sqlite.connection_open(
        fixture.connection, path.filename, .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    if startup.create_schema {
        _ = sqlite.connection_exec(fixture.connection,
            "CREATE TABLE user_terminal_history (" +
            "entry_id INTEGER PRIMARY KEY, source TEXT NOT NULL, mode INTEGER NOT NULL, " +
            "submitted_at_unix_ms INTEGER NOT NULL, terminal_generation INTEGER NOT NULL, " +
            "source_revision INTEGER NOT NULL);")
    }
    testing.expect(t, taskpool.task_pool_init(fixture.pool, 1, 3))
    _ = history_runtime_set_persistence(fixture.history, startup.persist)
    history_runtime_start(fixture.history, fixture.connection)
    history_runtime_service(fixture.history, fixture.admission, fixture.pool, false)
    if !history_runtime_test_wait_task(
        fixture.history, fixture.admission, fixture.pool) ||
       fixture.history^.status != .Ready || !fixture.history^.store.durable_available {
        return false
    }
    history_runtime_attach_generation(fixture.history, startup.generation)
    return true
}

// Join every accepted mutation in order before testing a browse result.
history_runtime_test_drain_mutations :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) {
    for _ in 0..<8 {
        if !history^.task_active && history^.mutation_count == 0 {
            break
        }
        taskpool.task_pool_wait_for_progress(pool)
        history_runtime_service(history, admission, pool, false)
    }
}

// Read one request through the production worker and copy-out path.
history_runtime_test_read :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool, request: historyruntime.History_Read_Request,
    destination: []u8) -> (termhiststore.History_Read_Result, bool) {
    if !history_runtime_request_read(history, request) {
        return {}, false
    }
    history_runtime_service(history, admission, pool, false)
    if !history_runtime_test_wait_task(history, admission, pool) {
        return {}, false
    }
    completion, consumed := history_runtime_consume_read_result(history, destination)
    return completion.result, consumed
}

// Write session-only and durable entries, then check their combined ordering.
history_runtime_test_first_persistent_launch :: proc(
    t: ^testing.T, path: History_Runtime_Test_Path) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    fixture: History_Runtime_Test_Fixture = {
        history = history,
        connection = &connection,
        admission = &admission,
        pool = &pool,
    }
    testing.expect(t, history_runtime_test_start_durable(
        t, path, fixture, {
            generation = 1,
            create_schema = true,
        }))
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(1, 1), "begin"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect_value(t, history.last_write_result.persistent_entry_id, u64(0))
    testing.expect(t, history_runtime_set_persistence(history, true))
    history_runtime_test_write_persistent_revision(t, history, &admission, &pool)
    history_runtime_test_browse_session_union(t, history, &admission, &pool)
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// Persist an insertion and its already-queued continuation revision atomically.
history_runtime_test_write_persistent_revision :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) {
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(2, 1), "persisted"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    testing.expect_value(t, history_runtime_enqueue_update(history, {
        submission_id = 2,
        expected_revision = 1,
        new_revision = 2,
        mode = .Pkg,
        source = "persisted\n    end",
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(history, admission, pool, false)
    history_runtime_test_drain_mutations(history, admission, pool)
    testing.expect_value(t, history^.mutation_count, 0)
    testing.expect_value(t, history^.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Updated)
    history_runtime_test_persistent_highlight_read(t, history, admission, pool)
}

// Persistent explorer candidates use the admitted keyed read without session-ID lookup.
history_runtime_test_persistent_highlight_read :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) {
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    persistent_id := history^.last_write_result.persistent_entry_id
    result, consumed := history_runtime_test_read(history, admission, pool, {
        kind = .By_Id,
        priority = .Speculative,
        target = .Highlighting,
        submission_id = persistent_id,
        source_scope = .Persistent,
        request_id = 77,
        terminal_generation = history^.terminal_generation,
        source_revision = 2,
        face_generation = 1,
    }, destination[:])
    testing.expect(t, consumed)
    testing.expect_value(t, result.outcome, termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t, result.record.scope,
        termhiststore.History_Record_Scope.Persistent)
    testing.expect_value(t, result.record.source_id, persistent_id)
    testing.expect_value(t, result.record.source_revision, u64(2))
    testing.expect_value(t, result.record.mode, protocol.Evaluation_Mode.Pkg)
    testing.expect_value(t, string(destination[:result.source_length]),
        "persisted\n    end")
}

// Confirm newly persisted and session-only records share one ordered browse.
history_runtime_test_browse_session_union :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) {
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    latest, consumed := history_runtime_test_read(history, admission, pool, {
        kind = .Latest,
        priority = .Interactive,
        request_id = 1,
        terminal_generation = 1,
    }, destination[:])
    testing.expect(t, consumed)
    testing.expect_value(t, latest.outcome, termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t, latest.record.submission_id, u64(2))
    testing.expect_value(t,
        latest.record.scope, termhiststore.History_Record_Scope.Session)
    cursor: termhiststore.History_Browse_Cursor = {
        submitted_at_unix_ms = latest.record.submitted_at_unix_ms,
        scope = latest.record.scope,
        source_id = latest.record.source_id,
    }
    older, older_consumed := history_runtime_test_read(history, admission, pool, {
        kind = .Older,
        priority = .Interactive,
        request_id = 2,
        terminal_generation = 1,
        cursor = cursor,
        cursor_valid = true,
    }, destination[:])
    testing.expect(t, older_consumed)
    testing.expect_value(t, older.outcome, termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t,
        older.record.scope, termhiststore.History_Record_Scope.Session)
    testing.expect_value(t, older.record.submission_id, u64(1))
    testing.expect_value(t, string(destination[:older.source_length]), "begin")
}

// Reopen the database and verify stale-read retirement, visibility toggles, and mode.
history_runtime_test_reopened_persistent_history :: proc(
    t: ^testing.T, path: History_Runtime_Test_Path) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    fixture: History_Runtime_Test_Fixture = {
        history = history,
        connection = &connection,
        admission = &admission,
        pool = &pool,
    }
    testing.expect(t, history_runtime_test_start_durable(
        t, path, fixture, {
            generation = 2,
            persist = true,
        }))
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    latest: historyruntime.History_Read_Request = {
        kind = .Latest,
        priority = .Interactive,
        request_id = 3,
        terminal_generation = 2,
    }
    testing.expect(t, history_runtime_request_read(history, latest))
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_set_persistence(history, false))
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect(t, !history.read_result_ready)
    history_runtime_test_verify_persistence_toggle(t, history, &admission, &pool, {
        request = latest,
        destination = destination[:],
    })
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// Verify disabled browsing hides saved rows and re-enabled browsing restores them.
history_runtime_test_verify_persistence_toggle :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool, read_input: History_Runtime_Test_Read_Input) {
    request := read_input.request
    request.request_id = 4
    off_result, consumed := history_runtime_test_read(
        history, admission, pool, request, read_input.destination)
    testing.expect(t, consumed)
    testing.expect_value(t, off_result.outcome,
        termhiststore.History_Read_Outcome.Boundary)
    testing.expect(t, history_runtime_set_persistence(history, true))
    request.request_id = 5
    saved: termhiststore.History_Read_Result
    saved, consumed = history_runtime_test_read(
        history, admission, pool, request, read_input.destination)
    testing.expect(t, consumed)
    testing.expect_value(t, saved.outcome, termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t, saved.record.submission_id, u64(0))
    testing.expect_value(t, saved.record.scope,
        termhiststore.History_Record_Scope.Persistent)
    testing.expect_value(t, saved.record.source_revision, u64(2))
    testing.expect_value(t, saved.record.mode, protocol.Evaluation_Mode.Pkg)
    testing.expect_value(t,
        string(read_input.destination[:saved.source_length]), "persisted\n    end")
}

// Durable writes pair continuation revisions and expose saved history after restart.
@(test)
history_runtime_persists_updates_and_retires_stale_visibility_reads :: proc(
    t: ^testing.T) {
    path := history_runtime_test_path(t)
    testing.expect(t, len(path.filename) > 0)
    if len(path.filename) == 0 {
        return
    }
    defer history_runtime_test_path_destroy(path)
    history_runtime_test_first_persistent_launch(t, path)
    history_runtime_test_reopened_persistent_history(t, path)
}

// No database leaves history explicitly unavailable without blocking ordinary use.
@(test)
history_runtime_without_connection_is_unavailable :: proc(t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    history_runtime_start(history, nil)
    testing.expect_value(t,
        history.status, historyruntime.History_Runtime_Status.Unavailable)
    testing.expect_value(t, history.initialization_failure.kind,
        termhiststore.History_Store_Error_Kind.Invalid_State)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(1, 1), "source"),
        historyruntime.History_Runtime_Enqueue_Result.Not_Ready)
}

// A conflicting connection-local table reports initialization failure without affecting saves.
@(test)
history_runtime_reports_temp_initialization_failure :: proc(t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    failure := sqlite.connection_open(
        &connection, ":memory:", .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect(t, connection.handle != nil)
    _ = sqlite.connection_exec(&connection,
        "CREATE TEMP TABLE terminal_history (conflict INTEGER);")
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 2))
    history_runtime_start(history, &connection)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect_value(t, history.status,
        historyruntime.History_Runtime_Status.Unavailable)
    testing.expect_value(t, history.initialization_failure.kind,
        termhiststore.History_Store_Error_Kind.Sqlite)
    testing.expect(t, viewuserdata.connection_admission_is_idle(&admission))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// A joined domain failure remains explicit and does not corrupt later history tasks.
@(test)
history_runtime_surfaces_worker_write_failure :: proc(t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    fixture := history_runtime_test_make_fixture(
        history, &connection, &admission, &pool)
    if !history_runtime_test_start(t, fixture) {
        return
    }
    invalid := history_runtime_test_record(0, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, invalid, "invalid"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect_value(t, history.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Failed)
    testing.expect_value(t, history.last_write_result.failure.kind,
        termhiststore.History_Store_Error_Kind.Invalid_Argument)
    testing.expect_value(t, history.status, historyruntime.History_Runtime_Status.Ready)
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// The serialized clear transaction removes both scopes and retires queued reads.
@(test)
history_runtime_clears_all_scopes_and_retires_reads_after_commit :: proc(
    t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    if !history_runtime_test_start(t, {
        history = history,
        connection = &connection,
        admission = &admission,
        pool = &pool,
        create_persistent_table = true,
    }) {
        return
    }
    fixture: History_Runtime_Test_Fixture = {
        history = history,
        connection = &connection,
        admission = &admission,
        pool = &pool,
    }
    testing.expect(t, history_runtime_test_seed_clear_scopes(t, fixture))
    testing.expect(t, history_runtime_request_read(history, {
        kind = .Latest,
        priority = .Interactive,
        request_id = 1,
        terminal_generation = 1,
    }))
    testing.expect_value(t, history_runtime_enqueue_clear(history),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    epoch_before_clear := history^.visibility_epoch
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    history_runtime_test_expect_clear_result(t, history, epoch_before_clear)

    testing.expect(t, history_runtime_set_persistence(history, true))
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    latest := termhiststore.history_store_combined_latest(
        &history^.store, destination[:])
    testing.expect_value(t, latest.outcome,
        termhiststore.History_Read_Outcome.Not_Found)
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// Seed one durable and one session-only row for the all-scope clear test.
history_runtime_test_seed_clear_scopes :: proc(
    t: ^testing.T, fixture: History_Runtime_Test_Fixture) -> bool {
    history_runtime_attach_generation(fixture.history, 1)
    _ = history_runtime_set_persistence(fixture.history, true)
    if !history_runtime_test_store_clear_record(
        t, fixture, 1, "durable") {
        return false
    }
    _ = history_runtime_set_persistence(fixture.history, false)
    return history_runtime_test_store_clear_record(
        t, fixture, 2, "session")
}

// Store and join one clear-fixture record under the requested persistence mode.
history_runtime_test_store_clear_record :: proc(
    t: ^testing.T, fixture: History_Runtime_Test_Fixture,
    id: u64, source: string) -> bool {
    queued := history_runtime_enqueue_insert(
        fixture.history, history_runtime_test_record(id, 1), source)
    testing.expect_value(t, queued,
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    if queued != .Queued {
        return false
    }
    history_runtime_service(
        fixture.history, fixture.admission, fixture.pool, false)
    if !history_runtime_test_wait_task(
        fixture.history, fixture.admission, fixture.pool) {
        return false
    }
    testing.expect_value(t, fixture.history^.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Stored)
    return fixture.history^.last_write_result.outcome == .Stored
}

// Assert that clear publishes only after commit and retires outstanding reads.
history_runtime_test_expect_clear_result :: proc(
    t: ^testing.T, history: ^historyruntime.History_Runtime,
    previous_visibility_epoch: u64) {
    testing.expect_value(t, history^.last_clear_result.outcome,
        termhiststore.History_Clear_Outcome.Cleared)
    testing.expect_value(t, history^.clear_completion_serial, 1)
    testing.expect(t, history^.visibility_epoch != previous_visibility_epoch)
    testing.expect_value(t, history^.interactive_read_count, 0)
    testing.expect(t, !history^.read_result_ready)
}

// A generation replacement retires an in-flight UI read but preserves its stored row.
@(test)
history_runtime_generation_retires_reads_without_resetting_records :: proc(
    t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    fixture := history_runtime_test_make_fixture(
        history, &connection, &admission, &pool)
    if !history_runtime_test_start(t, fixture) {
        return
    }
    history_runtime_attach_generation(history, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(1, 1), "retained"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history.task_active)
    history_runtime_attach_generation(history, 2)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    testing.expect(t, !history.read_result_ready)
    testing.expect(t, history_runtime_request_read(history, {
        kind = .By_Id,
        priority = .Interactive,
        submission_id = 1,
        request_id = 1,
        terminal_generation = 2,
    }))
    history_runtime_service(history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, &admission, &pool))
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    completion, consumed := history_runtime_consume_read_result(
        history, destination[:])
    testing.expect(t, consumed)
    testing.expect_value(t, completion.result.outcome,
        termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t,
        string(destination[:completion.result.source_length]), "retained")
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// A settings lease prevents history work until its owner joins and releases admission.
@(test)
history_runtime_waits_for_settings_join_and_drains_before_shutdown :: proc(
    t: ^testing.T) {
    history := new(historyruntime.History_Runtime, context.allocator)
    defer free(history, context.allocator)
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    fixture := history_runtime_test_make_fixture(
        history, &connection, &admission, &pool)
    if !history_runtime_test_start(t, fixture) {
        return
    }
    history_runtime_attach_generation(history, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        history, history_runtime_test_record(1, 1), "save-overlap"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    testing.expect(t, viewuserdata.connection_admission_claim(
        &admission, .Settings_Save, true, false))
    handle, outcome := taskpool.task_pool_submit(
        &pool, history_runtime_test_save_worker, nil, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, viewuserdata.connection_admission_mark_submitted(
        &admission, .Settings_Save))
    history_runtime_service(history, &admission, &pool, true)
    testing.expect(t, !history.task_active)
    testing.expect_value(t,
        admission.owner, protocol.User_Data_Connection_Client.Settings_Save)
    _, joined := taskpool.task_pool_wait(&pool, handle)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    testing.expect(t, viewuserdata.connection_admission_release_joined(
        &admission, .Settings_Save))
    testing.expect(t, history_runtime_test_shutdown(
        t, history, &admission, &pool))
    testing.expect(t, viewuserdata.connection_admission_drain_complete(&admission))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}
