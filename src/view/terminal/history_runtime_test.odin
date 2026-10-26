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
    history: ^historyruntime.History_Runtime,
    connection: ^sqlite.Connection,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) -> bool {
    failure := sqlite.connection_open(
        connection, ":memory:", .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect(t, connection.handle != nil)
    testing.expect(t, taskpool.task_pool_init(pool, 1, 3))
    history_runtime_start(history, connection)
    history_runtime_service(history, admission, pool, false)
    testing.expect(t, history_runtime_test_wait_task(history, admission, pool))
    testing.expect_value(t, history^.status, historyruntime.History_Runtime_Status.Ready)
    return history^.status == .Ready
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
    history: historyruntime.History_Runtime
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    testing.expect(t, history_runtime_test_start(
        t, &history, &connection, &admission, &pool))
    source_length := history_runtime_test_enqueue_full_queue(t, &history)

    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history.task_active)
    testing.expect_value(t, history.mutation_count, 7)
    testing.expect_value(t, history.queued_source_bytes, 7 * source_length)
    testing.expect_value(t, history.active_mutation.source_length, source_length)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
    testing.expect_value(t, history.queued_source_bytes, 0)
    testing.expect(t, history_runtime_test_shutdown(
        t, &history, &admission, &pool))
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
    connection: sqlite.Connection
    open_failure := sqlite.connection_open(
        &connection, path.filename, .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, open_failure.validation, sqlite.Validation_Error.None)
    _ = sqlite.connection_exec(&connection, "CREATE TABLE persistent_probe (id INTEGER);")
    _ = sqlite.connection_close(&connection)

    history: historyruntime.History_Runtime
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    readonly_failure := sqlite.connection_open(
        &connection, path.filename, .Readonly, context.temp_allocator)
    testing.expect_value(t, readonly_failure.validation, sqlite.Validation_Error.None)
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    history_runtime_start(&history, &connection)
    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
    testing.expect_value(t, history.status, historyruntime.History_Runtime_Status.Ready)
    testing.expect_value(t, history_runtime_enqueue_insert(
        &history, history_runtime_test_record(1, 1), "temporary"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    testing.expect(t, history_runtime_test_shutdown(
        t, &history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
    history_runtime_test_path_destroy(path)
}

// No database leaves history explicitly unavailable without blocking ordinary use.
@(test)
history_runtime_without_connection_is_unavailable :: proc(t: ^testing.T) {
    history: historyruntime.History_Runtime
    history_runtime_start(&history, nil)
    testing.expect_value(t,
        history.status, historyruntime.History_Runtime_Status.Unavailable)
    testing.expect_value(t, history.initialization_failure.kind,
        termhiststore.History_Store_Error_Kind.Invalid_State)
    testing.expect_value(t, history_runtime_enqueue_insert(
        &history, history_runtime_test_record(1, 1), "source"),
        historyruntime.History_Runtime_Enqueue_Result.Not_Ready)
}

// A conflicting connection-local table reports initialization failure without affecting saves.
@(test)
history_runtime_reports_temp_initialization_failure :: proc(t: ^testing.T) {
    history: historyruntime.History_Runtime
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
    history_runtime_start(&history, &connection)
    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
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
    history: historyruntime.History_Runtime
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    if !history_runtime_test_start(
        t, &history, &connection, &admission, &pool) {
        return
    }
    invalid := history_runtime_test_record(0, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        &history, invalid, "invalid"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
    testing.expect_value(t, history.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Failed)
    testing.expect_value(t, history.last_write_result.failure.kind,
        termhiststore.History_Store_Error_Kind.Invalid_Argument)
    testing.expect_value(t, history.status, historyruntime.History_Runtime_Status.Ready)
    testing.expect(t, history_runtime_test_shutdown(
        t, &history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// A generation replacement retires an in-flight UI read but preserves its stored row.
@(test)
history_runtime_generation_retires_reads_without_resetting_records :: proc(
    t: ^testing.T) {
    history: historyruntime.History_Runtime
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    if !history_runtime_test_start(
        t, &history, &connection, &admission, &pool) {
        return
    }
    history_runtime_attach_generation(&history, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        &history, history_runtime_test_record(1, 1), "retained"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history.task_active)
    history_runtime_attach_generation(&history, 2)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
    testing.expect(t, !history.read_result_ready)
    testing.expect(t, history_runtime_request_read(&history, {
        kind = .By_Id,
        priority = .Interactive,
        submission_id = 1,
        request_id = 1,
        terminal_generation = 2,
    }))
    history_runtime_service(&history, &admission, &pool, false)
    testing.expect(t, history_runtime_test_wait_task(&history, &admission, &pool))
    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    completion, consumed := history_runtime_consume_read_result(
        &history, destination[:])
    testing.expect(t, consumed)
    testing.expect_value(t, completion.result.outcome,
        termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t,
        string(destination[:completion.result.source_length]), "retained")
    testing.expect(t, history_runtime_test_shutdown(
        t, &history, &admission, &pool))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}

// A settings lease prevents history work until its owner joins and releases admission.
@(test)
history_runtime_waits_for_settings_join_and_drains_before_shutdown :: proc(
    t: ^testing.T) {
    history: historyruntime.History_Runtime
    connection: sqlite.Connection
    admission: protocol.User_Data_Connection_Admission
    pool: taskpool.Task_Pool
    if !history_runtime_test_start(
        t, &history, &connection, &admission, &pool) {
        return
    }
    history_runtime_attach_generation(&history, 1)
    testing.expect_value(t, history_runtime_enqueue_insert(
        &history, history_runtime_test_record(1, 1), "save-overlap"),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    testing.expect(t, viewuserdata.connection_admission_claim(
        &admission, .Settings_Save, true, false))
    handle, outcome := taskpool.task_pool_submit(
        &pool, history_runtime_test_save_worker, nil, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, viewuserdata.connection_admission_mark_submitted(
        &admission, .Settings_Save))
    history_runtime_service(&history, &admission, &pool, true)
    testing.expect(t, !history.task_active)
    testing.expect_value(t,
        admission.owner, protocol.User_Data_Connection_Client.Settings_Save)
    _, joined := taskpool.task_pool_wait(&pool, handle)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    testing.expect(t, viewuserdata.connection_admission_release_joined(
        &admission, .Settings_Save))
    testing.expect(t, history_runtime_test_shutdown(
        t, &history, &admission, &pool))
    testing.expect(t, viewuserdata.connection_admission_drain_complete(&admission))
    taskpool.task_pool_destroy(&pool)
    _ = sqlite.connection_close(&connection)
}
