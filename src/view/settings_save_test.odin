#+test
package view

import app_core "../core"
import setting_model "../settings"
import taskpool "../taskpool"
import user_data "../userdata"
import viewmodel "model"
import font "font"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

Settings_Save_Test_Gate :: struct {
    mutex: sync.Mutex,
    changed: sync.Cond,
    worker_started: bool,
    worker_released: bool,
}

Settings_Save_Test_Path :: struct {
    directory: string,
    filename: string,
    valid: bool,
}

// Create an isolated temporary database path for settings task tests.
settings_save_test_path :: proc(t: ^testing.T) -> Settings_Save_Test_Path {
    result: Settings_Save_Test_Path
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return result
    }
    result.directory, _ = filepath.join(
        []string{temporary_directory, fmt.tprintf("euclid-save-%x", uintptr(t))},
        context.temp_allocator)
    if len(result.directory) == 0 ||
        os.make_directory_all(result.directory) != nil {
        return result
    }
    result.filename, _ = filepath.join(
        []string{result.directory, "settings.sqlite3"}, context.temp_allocator)
    result.valid = len(result.filename) > 0
    return result
}

// Remove the isolated fixture after all store users have joined.
settings_save_test_path_destroy :: proc(path: Settings_Save_Test_Path) {
    if len(path.directory) > 0 {
        _ = os.remove_all(path.directory)
    }
}

// Initialize a minimal settings runtime without creating unrelated view state.
settings_save_test_state :: proc() -> ^app_core.Euclid_General_State {
    return new(app_core.Euclid_General_State, context.allocator)
}

// Block a worker until the test releases its synchronization gate.
settings_save_test_block_worker :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    gate := cast(^Settings_Save_Test_Gate)payload
    sync.mutex_lock(&gate.mutex)
    gate^.worker_started = true
    sync.cond_broadcast(&gate.changed)
    for !gate^.worker_released {
        sync.cond_wait(&gate.changed, &gate.mutex)
    }
    sync.mutex_unlock(&gate.mutex)
    return .Succeeded
}

// Wait until the single test worker enters its blocking fixture.
settings_save_test_wait_worker :: proc(gate: ^Settings_Save_Test_Gate) -> bool {
    deadline := time.tick_since({}) + 5 * time.Second
    for time.tick_since({}) < deadline {
        sync.mutex_lock(&gate.mutex)
        started := gate^.worker_started
        sync.mutex_unlock(&gate.mutex)
        if started {
            return true
        }
        thread.yield()
    }
    return false
}

// Release the gated worker before consuming its task handle.
settings_save_test_release_worker :: proc(gate: ^Settings_Save_Test_Gate) {
    sync.mutex_lock(&gate.mutex)
    gate^.worker_released = true
    sync.cond_broadcast(&gate.changed)
    sync.mutex_unlock(&gate.mutex)
}

// Run frame-like polls until a save reaches any terminal non-pending status.
settings_save_test_wait_terminal :: proc(
    state: ^app_core.Euclid_General_State, pool: ^taskpool.Task_Pool) -> bool {
    deadline := time.tick_since({}) + 5 * time.Second
    for time.tick_since({}) < deadline {
        settings_save_service(state, pool)
        if !state^.ui_runtime.settings_save_active &&
            state^.ui_runtime.settings_save_status != .Saving {
            return true
        }
        thread.yield()
    }
    return false
}

// Assert the final dust limit was committed before its store is closed.
settings_save_test_expect_dust_limit :: proc(
    t: ^testing.T, store: ^user_data.Store) {
    preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(store, &preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect_value(t, preferences.drawing.dust_limit, 1400)
}

// Verify the saved batch retains rendering and both interface preferences.
settings_save_expect_committed_preferences :: proc(
    t: ^testing.T, store: ^user_data.Store) {
    preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(store, &preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect(t, .Rendering_Vsync in preferences.present)
    testing.expect(t, !preferences.rendering.vsync)
    testing.expect(t, preferences.interface.display_fps)
    testing.expect(t, preferences.interface.reduce_motion)
}

// Verify edits coalesce by setting and commit one batch on a worker.
@(test)
settings_save_coalesces_and_commits_worker_batch :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    state := settings_save_test_state()
    defer free(state, context.allocator)
    state^.ui_runtime.settings_store = &store
    state^.ui_runtime.settings_store_available = true
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Interface_Display_Fps, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Interface_Reduce_Motion, setting_model.boolean_value(true))

    settings_save_service(state, &pool)
    testing.expect_value(t, state^.ui_runtime.settings_pending.count, 0)
    testing.expect(t, state^.ui_runtime.settings_save_active)
    testing.expect(t, settings_save_test_wait_terminal(state, &pool))
    testing.expect_value(t, state^.ui_runtime.settings_save_status,
        viewmodel.Settings_Save_Status.Saved)
    settings_save_expect_committed_preferences(t, &store)
    settings_save_shutdown(state, &pool)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify pool saturation retains the coalesced batch until worker capacity frees.
@(test)
settings_save_retains_pending_batch_when_pool_is_full :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    gate: Settings_Save_Test_Gate
    blocker, outcome := taskpool.task_pool_submit(
        &pool, settings_save_test_block_worker, &gate, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, settings_save_test_wait_worker(&gate))
    state := settings_save_test_state()
    defer free(state, context.allocator)
    state^.ui_runtime.settings_store = &store
    state^.ui_runtime.settings_store_available = true
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1200))

    settings_save_service(state, &pool)
    testing.expect_value(t, state^.ui_runtime.settings_pending.count, 1)
    testing.expect(t, !state^.ui_runtime.settings_save_active)
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    settings_save_service(state, &pool)
    testing.expect(t, settings_save_test_wait_terminal(state, &pool))
    settings_save_shutdown(state, &pool)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify newer edits survive an in-flight save and shutdown joins accepted work.
@(test)
settings_save_shutdown_joins_and_flushes_newer_pending_edits :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    gate: Settings_Save_Test_Gate
    blocker, outcome := taskpool.task_pool_submit(
        &pool, settings_save_test_block_worker, &gate, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, settings_save_test_wait_worker(&gate))
    state := settings_save_test_state()
    defer free(state, context.allocator)
    state^.ui_runtime.settings_store = &store
    state^.ui_runtime.settings_store_available = true
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1200))
    settings_save_service(state, &pool)
    testing.expect(t, state^.ui_runtime.settings_save_active)
    testing.expect(t, !taskpool.task_pool_help_once(&pool))
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1400))
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    settings_save_shutdown(state, &pool)
    testing.expect(t, !state^.ui_runtime.settings_save_active)
    testing.expect_value(t, state^.ui_runtime.settings_pending.count, 0)
    settings_save_test_expect_dust_limit(t, &store)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify retry requeue preserves newer values over failed snapshots.
@(test)
settings_save_retry_merges_latest :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer free(state, context.allocator)
    runtime := &state^.ui_runtime
    runtime^.settings_failure_count = 1
    runtime^.settings_save_payload.changes.count = 1
    runtime^.settings_save_payload.changes.changes[0] = {
        id = .Rendering_Vsync,
        kind = .Set,
        value = setting_model.boolean_value(true),
    }
    _ = setting_model.change_set_set(&runtime^.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(&runtime^.settings_pending,
        .Interface_Display_Fps, setting_model.boolean_value(true))
    runtime^.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Not_Committed,
        failure = {kind = .Write},
    }
    settings_save_apply_result(state, .Failed)
    testing.expect_value(t, runtime^.settings_pending.count, 2)
    vsync_index := setting_model.change_index(
        &runtime^.settings_pending, .Rendering_Vsync)
    fps_index := setting_model.change_index(
        &runtime^.settings_pending, .Interface_Display_Fps)
    testing.expect(t, vsync_index >= 0 && fps_index >= 0)
    if vsync_index >= 0 && fps_index >= 0 {
        testing.expect(t,
            !runtime^.settings_pending.changes[vsync_index].value.boolean)
        testing.expect(t,
            runtime^.settings_pending.changes[fps_index].value.boolean)
    }
    testing.expect_value(t, runtime^.settings_retry_frames,
        SETTINGS_SAVE_RETRY_DELAY_FRAMES)
    testing.expect_value(t, runtime^.settings_save_status,
        viewmodel.Settings_Save_Status.Pending)
}

// Verify permanent store faults bypass retries while transient faults are capped.
@(test)
settings_save_failure_policy_separates_permanent_and_transient :: proc(t: ^testing.T) {
    testing.expect_value(t, settings_save_failure_status(.Write, 1),
        viewmodel.Settings_Save_Status.Pending)
    testing.expect_value(t, settings_save_failure_status(.Write,
        SETTINGS_SAVE_MAX_ATTEMPTS), viewmodel.Settings_Save_Status.Failed)
    testing.expect_value(t, settings_save_failure_status(.Not_Writable, 1),
        viewmodel.Settings_Save_Status.Unavailable)
    testing.expect_value(t, settings_save_failure_status(.Invalid_Batch, 1),
        viewmodel.Settings_Save_Status.Unavailable)
}

// Verify intentional no-database mode never queues a settings task.
@(test)
settings_save_without_store_is_memory_only :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 2))
    state := settings_save_test_state()
    defer free(state, context.allocator)
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    settings_save_service(state, &pool)
    testing.expect(t, !state^.ui_runtime.settings_save_active)
    testing.expect_value(t, state^.ui_runtime.settings_pending.count, 1)
    testing.expect_value(t, state^.ui_runtime.settings_save_status,
        viewmodel.Settings_Save_Status.Unavailable)
    taskpool.task_pool_destroy(&pool)
}

// Verify final settings admission precedes optional-font shared-pool shutdown.
@(test)
settings_save_window_shutdown_flushes_before_font_pool_teardown :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    defer user_data.store_close(&store)
    state := settings_save_test_state()
    defer free(state, context.allocator)
    executor := new(Simulation_Executor, context.allocator)
    defer free(executor, context.allocator)
    state^.simulation_executor = executor
    testing.expect(t, taskpool.task_pool_init(&executor^.pool, 1, 3))
    defer taskpool.task_pool_destroy(&executor^.pool)
    state^.ui_runtime.settings_store = &store
    state^.ui_runtime.settings_store_available = true
    _ = setting_model.change_set_set(&state^.ui_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1400))
    testing.expect(t, font.cache_request(&state^.font_cache, .Bold))
    testing.expect_value(t, shutdown_window_runtime({state = state}), 0)
    testing.expect_value(t, state^.ui_runtime.settings_pending.count, 0)
    testing.expect_value(t, state^.ui_runtime.settings_save_commit_count, u64(1))
    testing.expect_value(t, state^.ui_runtime.settings_save_owner_execution_count, u64(0))
    testing.expect(t, state^.ui_runtime.settings_save_payload.worker_thread_id !=
        state^.ui_runtime.settings_save_payload.owner_thread_id)
    settings_save_test_expect_dust_limit(t, &store)
}
