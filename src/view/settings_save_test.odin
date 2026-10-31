#+test
package view

import preferencesmodel "preferences/model"
import app_core "../core"
import protocol "../core/protocol"
import setting_model "../settings"
import taskpool "../taskpool"
import user_data "../persistence/userdata"
import collections "../collections"
import bridgemodel "../bridge/model"
import uuid "core:encoding/uuid"
import font "font"
import fmt "core:fmt"
import os "core:os"
import filepath "core:path/filepath"
import sync "core:sync"
import testing "core:testing"
import thread "core:thread"
import time "core:time"
import viewpreferences "preferences"
import viewuserdata "userdata"
import uilibrary "ui/library"
import viewmodel "ui/model"

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

// Create a deterministic nonzero identity for collection save tests.
settings_save_test_id :: proc(value: int) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[14] = u8(value >> 8)
    identifier[15] = u8(value)
    return identifier
}

// Build an immutable Favorites addition with its qualified root placement.
settings_save_test_add_favorite :: proc(
    entry_id, animation_id: uuid.Identifier) -> collections.Mutation {
    return collections.Mutation{
        kind = .Add_Favorite,
        placement = {
            collection_id = collections.FAVORITES_COLLECTION_ID,
            entry_id = entry_id,
        },
        entry_id = entry_id,
        animation_id = animation_id,
    }
}

// Build an immutable removal against the current Favorites placement identity.
settings_save_test_remove_favorite :: proc(
    state: ^app_core.Euclid_General_State,
    entry_id: uuid.Identifier) -> collections.Mutation {
    identity, failure := collections.placement_identity_for_entry(
        &state^.preferences_runtime.collections_state, entry_id)
    assert(failure == .None)
    return collections.Mutation{
        kind = .Remove_Favorite,
        placement = identity,
        entry_id = entry_id,
    }
}

// Build a reorder against the current placement scope in the test state.
settings_save_test_move :: proc(
    state: ^app_core.Euclid_General_State,
    entry_id: uuid.Identifier,
    direction: collections.Move_Direction) -> (
        collections.Mutation, collections.Policy_Error) {
    identity, failure := collections.placement_identity_for_entry(
        &state^.preferences_runtime.collections_state, entry_id)
    if failure != .None {
        return {}, failure
    }
    return collections.make_placement_move(
        &state^.preferences_runtime.collections_state, identity, direction)
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

// Destroy an owned collection snapshot before freeing its test owner record.
settings_save_test_destroy_set :: proc(snapshot: ^collections.Set) {
    collections.destroy(snapshot)
    free(snapshot, context.allocator)
}

// Destroy the runtime-owned Library before freeing a settings test state.
settings_save_test_destroy_state :: proc(
    state: ^app_core.Euclid_General_State) {
    viewmodel.ui_tree_projection_destroy(&state^.ui_runtime.library.tree.projection)
    collections.destroy(&state^.preferences_runtime.collections_state)
    free(state, context.allocator)
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
        viewpreferences.settings_save_service(state, pool)
        if !state^.preferences_runtime.settings_save_active &&
            state^.ui_runtime.preferences.save_status != .Saving {
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

// Assert one persisted Favorites placement name from a committed store.
settings_save_test_expect_entry_name :: proc(
    t: ^testing.T, store: ^user_data.Store, expected: string) {
    snapshot := new(collections.Set, context.allocator)
    defer settings_save_test_destroy_set(snapshot)
    testing.expect_value(t, user_data.store_load_collections(store, snapshot).kind,
        user_data.Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.entries[0].custom_name_length, len(expected))
    testing.expect_value(t,
        string(snapshot^.entries[0].custom_name[:len(expected)]), expected)
}

// Assert that one newer name edit remains owned and unadmitted after an older save.
settings_save_test_expect_dirty_entry_name :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State,
    entry_id: uuid.Identifier, revision: u64) {
    draft := &state^.ui_runtime.library.entry_name
    testing.expect(t, draft^.active && draft^.dirty)
    testing.expect_value(t, draft^.entry_id, entry_id)
    testing.expect_value(t, draft^.revision, revision)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 0)
}

// Prepare a named pending save before orderly display shutdown.
settings_save_test_prepare_named_shutdown :: proc(
    t: ^testing.T, store: ^user_data.Store) -> (
        ^app_core.Euclid_General_State, ^app_core.Simulation_Executor) {
    state := settings_save_test_state()
    executor := new(app_core.Simulation_Executor, context.allocator)
    state^.simulation_executor = executor
    testing.expect(t, taskpool.task_pool_init(&executor^.pool, 1, 3))
    state^.preferences_runtime.settings_store = store
    state^.ui_runtime.preferences.store_available = true
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(71)
    add := settings_save_test_add_favorite(entry_id, settings_save_test_id(72))
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, add),
        collections.Mutation_Error.None)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Start here"))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1400))
    return state, executor
}

// Finish one save, verify acknowledgement, and return its persisted collections.
settings_save_test_finish_collection_save :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    pool: ^taskpool.Task_Pool,
    store: ^user_data.Store,
    expected_count: int) -> ^collections.Set {
    viewpreferences.settings_save_service(state, pool)
    testing.expect(t, settings_save_test_wait_terminal(state, pool))
    testing.expect_value(t, state^.preferences_runtime.collection_mutation_count, 0)
    settings_save_expect_committed_preferences(t, store)
    viewpreferences.settings_save_shutdown(state, pool)
    snapshot := new(collections.Set, context.allocator)
    testing.expect_value(t,
        user_data.store_load_collections(store, snapshot).kind,
        user_data.Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.entry_count, expected_count)
    return snapshot
}

// Assert Favorites placement identity in authoritative sibling order.
settings_save_test_expect_favorites_order :: proc(
    t: ^testing.T, snapshot: ^collections.Set,
    expected: []uuid.Identifier) {
    indexes: [collections.ENTRY_INDEX_BUFFER_CAPACITY]int
    count, failure := collections.ordered_siblings(
        snapshot, collections.FAVORITES_COLLECTION_ID, {}, indexes[:])
    testing.expect_value(t, failure, collections.Policy_Error.None)
    testing.expect_value(t, count, len(expected))
    if count != len(expected) {
        return
    }
    for position in 0..<count {
        testing.expect_value(t, snapshot.entries[indexes[position]].id,
            expected[position])
    }
}

// Reopen the committed store and verify its Favorites sibling order.
settings_save_test_reopen_favorites :: proc(
    t: ^testing.T,
    store: ^user_data.Store,
    path: string,
    expected: []uuid.Identifier) {
    testing.expect_value(t, user_data.store_close(store).kind,
        user_data.Store_Error_Kind.None)
    testing.expect_value(t, user_data.store_open(store, path).kind,
        user_data.Store_Error_Kind.None)
    reopened := new(collections.Set, context.allocator)
    defer settings_save_test_destroy_set(reopened)
    testing.expect_value(t, user_data.store_load_collections(store, reopened).kind,
        user_data.Store_Error_Kind.None)
    settings_save_test_expect_favorites_order(t, reopened, expected)
    testing.expect_value(t, user_data.store_close(store).kind,
        user_data.Store_Error_Kind.None)
}

// Queue a first Favorites edit behind a blocked worker and return its handle.
settings_save_test_start_blocked_collection_save :: proc(
    t: ^testing.T,
    store: ^user_data.Store,
    pool: ^taskpool.Task_Pool,
    gate: ^Settings_Save_Test_Gate,
    state: ^app_core.Euclid_General_State) -> (
        taskpool.Task_Handle, collections.Mutation) {
    blocker, outcome := taskpool.task_pool_submit(
        pool, settings_save_test_block_worker, gate, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, settings_save_test_wait_worker(gate))
    state^.preferences_runtime.settings_store = store
    state^.ui_runtime.preferences.store_available = true
    collections.initialize(&state^.preferences_runtime.collections_state)
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Display_Fps, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Reduce_Motion, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Increased_Contrast, setting_model.boolean_value(true))
    first := settings_save_test_add_favorite(
        settings_save_test_id(11), settings_save_test_id(12))
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, first),
        collections.Mutation_Error.None)
    viewpreferences.settings_save_service(state, pool)
    testing.expect(t, state^.preferences_runtime.settings_save_active)
    testing.expect_value(t,
        state^.preferences_runtime.settings_save_payload.mutation_count, 1)
    return blocker, first
}

// Stage add, move, and remove operations while retaining expected identities.
settings_save_test_enqueue_ordered_mutations :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State) -> (
        uuid.Identifier, uuid.Identifier) {
    first := settings_save_test_add_favorite(
        settings_save_test_id(2), settings_save_test_id(1))
    second := settings_save_test_add_favorite(
        settings_save_test_id(3), settings_save_test_id(4))
    third := settings_save_test_add_favorite(
        settings_save_test_id(5), settings_save_test_id(6))
    additions: []collections.Mutation = {first, second, third}
    for mutation in additions {
        testing.expect_value(t,
            viewpreferences.settings_save_collection_mutation(state, mutation),
            collections.Mutation_Error.None)
    }
    settings_save_test_finish_ordered_mutations(t, state, first, second)
    return first.entry_id, third.entry_id
}

// Move one placement down twice, then remove the original first sibling.
settings_save_test_finish_ordered_mutations :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    first, second: collections.Mutation) {
    move_second, second_error := settings_save_test_move(
        state, first.entry_id, .Down)
    testing.expect_value(t, second_error, collections.Policy_Error.None)
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, move_second),
        collections.Mutation_Error.None)
    move_third, third_error := settings_save_test_move(
        state, first.entry_id, .Down)
    testing.expect_value(t, third_error, collections.Policy_Error.None)
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, move_third),
        collections.Mutation_Error.None)
    remove := settings_save_test_remove_favorite(state, second.entry_id)
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, remove),
        collections.Mutation_Error.None)
}

// Accept two additions and repeated moves while a worker payload is outstanding.
settings_save_test_enqueue_in_flight_moves :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    first: collections.Mutation) -> (uuid.Identifier, uuid.Identifier) {
    second := settings_save_test_add_favorite(
        settings_save_test_id(13), settings_save_test_id(14))
    third := settings_save_test_add_favorite(
        settings_save_test_id(15), settings_save_test_id(16))
    additions: []collections.Mutation = {second, third}
    for mutation in additions {
        testing.expect_value(t,
            viewpreferences.settings_save_collection_mutation(state, mutation),
            collections.Mutation_Error.None)
    }
    for _ in 0..<2 {
        move, failure := settings_save_test_move(state, first.entry_id, .Down)
        testing.expect_value(t, failure, collections.Policy_Error.None)
        testing.expect_value(t,
            viewpreferences.settings_save_collection_mutation(state, move),
            collections.Mutation_Error.None)
    }
    testing.expect_value(t,
        state^.preferences_runtime.collection_mutation_count, 4)
    return second.entry_id, third.entry_id
}

// Verify ordered Favorites mutations share one durable settings save lifecycle.
@(test)
settings_save_commits_ordered_collection_mutations :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    collections.initialize(&state^.preferences_runtime.collections_state)
    state^.ui_runtime.preferences.store_available = true
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Display_Fps, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Reduce_Motion, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Interface_Increased_Contrast, setting_model.boolean_value(true))
    first_id, third_id := settings_save_test_enqueue_ordered_mutations(t, state)
    snapshot := settings_save_test_finish_collection_save(
        t, state, &pool, &store, 2)
    defer settings_save_test_destroy_set(snapshot)
    settings_save_test_expect_favorites_order(
        t, snapshot, []uuid.Identifier{third_id, first_id})
    taskpool.task_pool_destroy(&pool)
    settings_save_test_reopen_favorites(
        t, &store, path.filename, []uuid.Identifier{third_id, first_id})
}

// Preserve edits accepted while the immutable worker payload is outstanding.
@(test)
settings_save_retains_newer_collection_edits_until_acknowledged :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    gate: Settings_Save_Test_Gate
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    blocker, first := settings_save_test_start_blocked_collection_save(
        t, &store, &pool, &gate, state)
    second_id, third_id := settings_save_test_enqueue_in_flight_moves(
        t, state, first)
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    snapshot := settings_save_test_finish_collection_save(
        t, state, &pool, &store, 3)
    defer settings_save_test_destroy_set(snapshot)
    settings_save_test_expect_favorites_order(t, snapshot, []uuid.Identifier{
        second_id, third_id, first.entry_id,
    })
    testing.expect_value(t,
        state^.preferences_runtime.collection_mutation_count, 0)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify the joined saved batch retains rendering and all interface preferences.
settings_save_expect_committed_preferences :: proc(
    t: ^testing.T, store: ^user_data.Store) {
    preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(store, &preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect(t, .Rendering_Vsync in preferences.present)
    testing.expect(t, !preferences.rendering.vsync)
    testing.expect(t, preferences.interface.display_fps)
    testing.expect(t, preferences.interface.reduce_motion)
    testing.expect(t, preferences.interface.increased_contrast)
    testing.expect(t, .Interface_Increased_Contrast in preferences.present)
}

// Verify high setting identifiers survive an immutable worker save snapshot.
settings_save_expect_animation_style_preferences :: proc(
    t: ^testing.T, store: ^user_data.Store) {
    preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(store, &preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect_value(t, preferences.animation.scale_percent, 155)
    testing.expect(t, preferences.animation.monochrome)
    testing.expect(t, .Animation_Scale_Percent in preferences.present)
    testing.expect(t, .Animation_Monochrome in preferences.present)
}

// Populate one coalesced settings batch with repeated and independent edits.
settings_save_test_set_coalesced_changes :: proc(
    state: ^app_core.Euclid_General_State) {
    pending := &state^.preferences_runtime.settings_pending
    _ = setting_model.change_set_set(
        pending, .Rendering_Vsync, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(
        pending, .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(
        pending, .Interface_Display_Fps, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(
        pending, .Interface_Reduce_Motion, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(
        pending, .Interface_Increased_Contrast, setting_model.boolean_value(true))
    _ = setting_model.change_set_set(
        pending, .Animation_Scale_Percent, setting_model.integer_value(155))
    _ = setting_model.change_set_set(
        pending, .Animation_Monochrome, setting_model.boolean_value(true))
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
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    state^.ui_runtime.preferences.store_available = true
    settings_save_test_set_coalesced_changes(state)

    viewpreferences.settings_save_service(state, &pool)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 0)
    testing.expect(t, state^.preferences_runtime.settings_save_active)
    testing.expect_value(t, state^.user_data_admission.owner,
        protocol.User_Data_Connection_Client.Settings_Save)
    testing.expect_value(t, state^.user_data_admission.phase,
        protocol.User_Data_Connection_Admission_Phase.Submitted)
    testing.expect(t, settings_save_test_wait_terminal(state, &pool))
    testing.expect_value(t, state^.ui_runtime.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Saved)
    settings_save_expect_committed_preferences(t, &store)
    settings_save_expect_animation_style_preferences(t, &store)
    testing.expect(t, viewuserdata.connection_admission_is_idle(
        &state^.user_data_admission))
    viewpreferences.settings_save_shutdown(state, &pool)
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
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    state^.ui_runtime.preferences.store_available = true
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1200))

    viewpreferences.settings_save_service(state, &pool)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 1)
    testing.expect(t, !state^.preferences_runtime.settings_save_active)
    testing.expect(t, viewuserdata.connection_admission_is_idle(
        &state^.user_data_admission))
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    viewpreferences.settings_save_service(state, &pool)
    testing.expect(t, settings_save_test_wait_terminal(state, &pool))
    viewpreferences.settings_save_shutdown(state, &pool)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify settings waits until another borrower has joined and released its connection lease.
@(test)
settings_save_waits_for_other_borrower_join_before_admission :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    testing.expect(t, path.valid)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 2))
    gate: Settings_Save_Test_Gate
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    blocker := settings_save_test_hold_history_lease(t, state, &pool, &gate)
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    viewpreferences.settings_save_service(state, &pool, true)
    testing.expect(t, !state^.preferences_runtime.settings_save_active)
    testing.expect(t, viewuserdata.connection_admission_release_joined(
        &state^.user_data_admission, .Terminal_History))
    viewpreferences.settings_save_service(state, &pool)
    testing.expect(t, state^.preferences_runtime.settings_save_active)
    testing.expect(t, settings_save_test_wait_terminal(state, &pool))
    viewpreferences.settings_save_shutdown(state, &pool)
    testing.expect(t, viewuserdata.connection_admission_drain_complete(
        &state^.user_data_admission))
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Hold a history lease through worker completion to prove settings waits for owner join.
settings_save_test_hold_history_lease :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State,
    pool: ^taskpool.Task_Pool, gate: ^Settings_Save_Test_Gate) -> taskpool.Task_Handle {
    testing.expect(t, viewuserdata.connection_admission_claim(
        &state^.user_data_admission, .Terminal_History, false, false))
    blocker, outcome := taskpool.task_pool_submit(
        pool, settings_save_test_block_worker, gate, .Worker_Only)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, viewuserdata.connection_admission_mark_submitted(
        &state^.user_data_admission, .Terminal_History))
    testing.expect(t, settings_save_test_wait_worker(gate))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1250))
    viewpreferences.settings_save_service(state, pool, true)
    testing.expect(t, !state^.preferences_runtime.settings_save_active)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 1)
    testing.expect_value(t, state^.user_data_admission.owner,
        protocol.User_Data_Connection_Client.Terminal_History)
    return blocker
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
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    state^.ui_runtime.preferences.store_available = true
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1200))
    viewpreferences.settings_save_service(state, &pool)
    testing.expect(t, state^.preferences_runtime.settings_save_active)
    testing.expect(t, !taskpool.task_pool_help_once(&pool))
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Drawing_Dust_Limit, setting_model.integer_value(1400))
    settings_save_test_release_worker(&gate)
    _, joined := taskpool.task_pool_wait(&pool, blocker)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    viewpreferences.settings_save_shutdown(state, &pool)
    testing.expect(t, !state^.preferences_runtime.settings_save_active)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 0)
    settings_save_test_expect_dust_limit(t, &store)
    taskpool.task_pool_destroy(&pool)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify retry requeue preserves newer values over failed snapshots.
@(test)
settings_save_retry_merges_latest :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    runtime := &state^.ui_runtime
    saves := &state^.preferences_runtime
    saves.settings_failure_count = 1
    saves.settings_save_payload.changes.count = 1
    saves.settings_save_payload.changes.changes[0] = {
        id = .Rendering_Vsync,
        kind = .Set,
        value = setting_model.boolean_value(true),
    }
    _ = setting_model.change_set_set(&saves.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    _ = setting_model.change_set_set(&saves.settings_pending,
        .Interface_Display_Fps, setting_model.boolean_value(true))
    saves.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Not_Committed,
        failure = {
            kind = .Write,
        },
    }
    viewpreferences.settings_save_apply_result(state, .Failed)
    testing.expect_value(t, saves.settings_pending.count, 2)
    vsync_index := setting_model.change_index(&saves.settings_pending, .Rendering_Vsync)
    fps_index := setting_model.change_index(
        &saves.settings_pending, .Interface_Display_Fps)
    testing.expect(t, vsync_index >= 0 && fps_index >= 0)
    if vsync_index >= 0 && fps_index >= 0 {
        testing.expect(t, !saves.settings_pending.changes[vsync_index].value.boolean)
        testing.expect(t, saves.settings_pending.changes[fps_index].value.boolean)
    }
    testing.expect_value(t, saves.settings_retry_frames,
        viewpreferences.SETTINGS_SAVE_RETRY_DELAY_FRAMES)
    testing.expect_value(t, runtime^.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Pending)
}

// Create retained failed writes for revision-aware save tests.
settings_save_test_with_write_failure :: proc() ->
    ^app_core.Euclid_General_State {
    state := settings_save_test_state()
    saves := &state^.preferences_runtime
    saves.user_data_revision = 10
    saves.settings_save_payload.user_data_revision = 10
    saves.settings_save_payload.changes.count = 1
    saves.settings_save_payload.changes.changes[0] = {
        id = .Rendering_Vsync,
        kind = .Set,
        value = setting_model.boolean_value(true),
    }
    saves.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Not_Committed,
        failure = {
            kind = .Write,
        },
    }
    saves.settings_failure_count = 1
    viewpreferences.settings_save_apply_result(state, .Failed)
    return state
}

// An older success must leave a newer unresolved failure and its status intact.
@(test)
settings_save_older_success_does_not_clear_user_data_failure :: proc(t: ^testing.T) {
    state := settings_save_test_with_write_failure()
    defer settings_save_test_destroy_state(state)
    saves := &state^.preferences_runtime
    testing.expect(t, saves.user_data_failure_unresolved)
    testing.expect_value(t, saves.user_data_failure.kind,
        user_data.Store_Error_Kind.Write)
    testing.expect_value(t, saves.user_data_failure_revision, u64(10))
    testing.expect_value(t, state^.ui_runtime.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Pending)

    saves.settings_save_payload.user_data_revision = 9
    saves.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Committed,
    }
    viewpreferences.settings_save_apply_result(state, .Succeeded)
    testing.expect(t, saves.user_data_failure_unresolved)
    testing.expect_value(t, saves.user_data_failure.kind,
        user_data.Store_Error_Kind.Write)
    testing.expect_value(t, saves.user_data_failure_revision, u64(10))
    testing.expect_value(t, state^.ui_runtime.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Failed)
}

// A retry that contains newer edits resolves the failed write atomically.
@(test)
settings_save_retry_success_clears_covered_failure :: proc(t: ^testing.T) {
    state := settings_save_test_with_write_failure()
    defer settings_save_test_destroy_state(state)
    saves := &state^.preferences_runtime
    store: user_data.Store
    saves.settings_store = &store
    viewpreferences.settings_save_note_edit(state)
    testing.expect_value(t, saves.user_data_revision, u64(11))
    testing.expect(t, saves.user_data_failure_unresolved)
    saves.settings_save_payload.user_data_revision = 11
    saves.settings_save_payload.changes = saves.settings_pending
    saves.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Committed,
    }
    saves.settings_pending = {}
    viewpreferences.settings_save_apply_result(state, .Succeeded)
    testing.expect(t, !saves.user_data_failure_unresolved)
    testing.expect_value(t, saves.user_data_failure.kind,
        user_data.Store_Error_Kind.None)
    testing.expect_value(t, state^.ui_runtime.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Saved)
}

// Restore a failed operation batch ahead of newer optimistic Favorites edits.
settings_save_test_apply_failed_collection_batch :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    saves: ^preferencesmodel.Settings_Save_Runtime,
    failed: []collections.Mutation,
    newer: collections.Mutation) {
    saves^.collection_mutations[0] = newer
    saves^.collection_mutation_count = 1
    for mutation, index in failed {
        saves^.settings_save_payload.mutations[index] = mutation
    }
    saves^.settings_save_payload.mutation_count = len(failed)
    saves^.settings_save_payload.result = {
        outcome = user_data.Commit_Outcome.Not_Committed,
        failure = {
            kind = .Write,
        },
    }
    saves^.settings_failure_count = 1
    viewpreferences.settings_save_apply_result(state, .Failed)
    testing.expect_value(t, saves^.collection_mutation_count, len(failed) + 1)
    for mutation, index in failed {
        testing.expect_value(t, saves^.collection_mutations[index], mutation)
    }
    testing.expect_value(t,
        saves^.collection_mutations[len(failed)], newer)
}

// Verify retries put failed moves before newer dependent edits.
@(test)
settings_save_retry_requeues_collection_operations_in_order :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    saves := &state^.preferences_runtime
    failed := settings_save_test_add_favorite(
        settings_save_test_id(21), settings_save_test_id(22))
    following := settings_save_test_add_favorite(
        settings_save_test_id(23), settings_save_test_id(24))
    move: collections.Mutation = {
        kind = .Reorder_Siblings,
        placement = failed.placement,
        entry_id = failed.entry_id,
        sibling_entry_id = following.entry_id,
        direction = .Down,
    }
    newer: collections.Mutation = {
        kind = .Remove_Favorite,
        placement = following.placement,
        entry_id = following.entry_id,
    }
    failed_batch: []collections.Mutation = {failed, following, move}
    settings_save_test_apply_failed_collection_batch(
        t, state, saves, failed_batch, newer)
    settings_save_test_expect_replay(
        t, saves.collection_mutations[:saves.collection_mutation_count],
        failed.entry_id)
}

// Replay an ordered mutation queue and assert its final placement identity.
settings_save_test_expect_replay :: proc(
    t: ^testing.T, mutations: []collections.Mutation,
    expected_entry: uuid.Identifier) {
    replay := new(collections.Set, context.allocator)
    defer settings_save_test_destroy_set(replay)
    collections.initialize(replay)
    for mutation in mutations {
        testing.expect_value(t,
            collections.apply_mutation(replay, mutation),
            collections.Mutation_Error.None)
    }
    testing.expect_value(t, replay^.entry_count, 1)
    testing.expect_value(t, replay^.entries[0].id, expected_entry)
}

// Fill the queue with one active operation and the remaining pending edits.
settings_save_test_fill_active_collection_queue :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State,
    store: ^user_data.Store) -> collections.Mutation {
    runtime := &state^.preferences_runtime
    runtime.settings_store = store
    collections.initialize(&runtime.collections_state)
    first := settings_save_test_add_favorite(
        settings_save_test_id(1), settings_save_test_id(1001))
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, first),
        collections.Mutation_Error.None)
    runtime.settings_save_payload.mutations[0] = first
    runtime.settings_save_payload.mutation_count = 1
    runtime.collection_mutation_count = 0
    runtime.settings_save_active = true
    for value in 2..=collections.MUTATION_CAPACITY {
        addition := settings_save_test_add_favorite(
            settings_save_test_id(value), settings_save_test_id(value + 1000))
        testing.expect_value(t,
            viewpreferences.settings_save_collection_mutation(state, addition),
            collections.Mutation_Error.None)
    }
    return first
}

// Enforce pending plus active batch capacity without publishing rejected moves.
@(test)
settings_save_collection_capacity_counts_only_active_payloads :: proc(
    t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    store: user_data.Store
    runtime := &state^.preferences_runtime
    first := settings_save_test_fill_active_collection_queue(t, state, &store)
    testing.expect_value(t, runtime.collection_mutation_count,
        collections.MUTATION_CAPACITY - 1)
    move, move_error := settings_save_test_move(state, first.entry_id, .Down)
    testing.expect_value(t, move_error, collections.Policy_Error.None)
    settings_save_test_expect_active_capacity_rejection(
        t, state, first.entry_id, move)

    runtime.settings_save_active = false
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, move),
        collections.Mutation_Error.None)
    testing.expect_value(t, runtime.collection_mutation_count,
        collections.MUTATION_CAPACITY)
    next_move, next_error := settings_save_test_move(state, first.entry_id, .Down)
    testing.expect_value(t, next_error, collections.Policy_Error.None)
    revision_at_capacity := runtime.collection_revision
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, next_move),
        collections.Mutation_Error.Capacity)
    testing.expect_value(t, runtime.collection_revision, revision_at_capacity)
}

// Prove active-batch capacity rejects a move without changing the live tree.
settings_save_test_expect_active_capacity_rejection :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    entry_id: uuid.Identifier,
    move: collections.Mutation) {
    runtime := &state^.preferences_runtime
    ji: bridgemodel.Euclid_Julia_Interface
    ji.content_generation = 1
    tree_params: uilibrary.Tree_List_Params = {
        general_state = state,
        ji = &ji,
        collections = &runtime.collections_state,
        collections_revision = runtime.collection_revision,
        ui_runtime = &state^.ui_runtime,
        visibility = {
            search = &state^.ui_runtime.library.search,
        },
    }
    testing.expect(t, uilibrary.tree_projection_prepare(tree_params))
    projection := &state^.ui_runtime.library.tree.projection
    first_index := uilibrary.tree_projection_find(projection, entry_id)
    stable_node := projection.items[first_index]
    original_topology_revision := projection.topology_revision
    original_build_count := projection.build_count
    original_revision := runtime.collection_revision
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, move),
        collections.Mutation_Error.Capacity)
    testing.expect_value(t, runtime.collection_revision, original_revision)
    testing.expect_value(t, runtime.collections_state.entries[0].sibling_order, i64(0))
    testing.expect_value(t, runtime.collections_state.entries[1].sibling_order, i64(1))
    testing.expect_value(t, projection.items[
        uilibrary.tree_projection_find(projection, entry_id)], stable_node)
    testing.expect_value(t, projection.topology_revision, original_topology_revision)
    testing.expect_value(t, projection.build_count, original_build_count)
}

// Verify permanent store faults bypass retries while transient faults are capped.
@(test)
settings_save_failure_policy_separates_permanent_and_transient :: proc(t: ^testing.T) {
    testing.expect_value(t, viewpreferences.settings_save_failure_status(.Write, 1),
        preferencesmodel.Settings_Save_Status.Pending)
    testing.expect_value(t,
        viewpreferences.settings_save_failure_status(.Write,
            viewpreferences.SETTINGS_SAVE_MAX_ATTEMPTS),
        preferencesmodel.Settings_Save_Status.Failed)
    testing.expect_value(t,
        viewpreferences.settings_save_failure_status(.Not_Writable, 1),
        preferencesmodel.Settings_Save_Status.Unavailable)
    testing.expect_value(t,
        viewpreferences.settings_save_failure_status(.Invalid_Batch, 1),
        preferencesmodel.Settings_Save_Status.Unavailable)
}

// Verify intentional no-database mode never queues a settings task.
@(test)
settings_save_without_store_is_memory_only :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 2))
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    viewpreferences.settings_save_service(state, &pool)
    testing.expect(t, !state^.preferences_runtime.settings_save_active)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 1)
    testing.expect_value(t, state^.ui_runtime.preferences.save_status,
        preferencesmodel.Settings_Save_Status.Unavailable)
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
    state, executor := settings_save_test_prepare_named_shutdown(t, &store)
    defer settings_save_test_destroy_state(state)
    defer free(executor, context.allocator)
    defer taskpool.task_pool_destroy(&executor^.pool)
    testing.expect(t, font.cache_request(&state^.font_cache, .Bold))
    testing.expect_value(t, shutdown_window_runtime({
        state = state,
    }), 0)
    testing.expect_value(t, state^.preferences_runtime.settings_pending.count, 0)
    testing.expect_value(t,
        state^.preferences_runtime.settings_save_commit_count, u64(1))
    testing.expect_value(t,
        state^.preferences_runtime.settings_save_owner_execution_count, u64(0))
    testing.expect(t,
        state^.preferences_runtime.settings_save_payload.worker_thread_id !=
            state^.preferences_runtime.settings_save_payload.owner_thread_id)
    settings_save_test_expect_dust_limit(t, &store)
    settings_save_test_expect_entry_name(t, &store, "Start here")
}

// Verify an older joined batch cannot clear a newer unadmitted name draft.
@(test)
settings_save_completion_preserves_newer_entry_name_draft :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    defer user_data.store_close(&store)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 2))
    defer taskpool.task_pool_destroy(&pool)
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(81)
    add := settings_save_test_add_favorite(entry_id, settings_save_test_id(82))
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, add),
        collections.Mutation_Error.None)
    _ = setting_model.change_set_set(&state^.preferences_runtime.settings_pending,
        .Rendering_Vsync, setting_model.boolean_value(false))
    viewpreferences.settings_save_service(state, &pool)
    testing.expect(t, state^.preferences_runtime.settings_save_active)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Newer"))
    viewpreferences.settings_save_service(state, &pool)
    settings_save_test_expect_dirty_entry_name(t, state, entry_id, u64(2))
    testing.expect(t, uilibrary.library_entry_name_flush(state))
    viewpreferences.settings_save_shutdown(state, &pool)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 5)
    settings_save_test_expect_entry_name(t, &store, "Newer")
}

// Verify edits debounce exactly once and are normalized before admission.
@(test)
library_entry_name_debounce_normalizes_and_admits :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(31)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, entry_id,
        settings_save_test_id(32)), collections.Policy_Error.None)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id,
        "\tStart here\u2003"))
    uilibrary.library_entry_name_service(state, 0.399)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 0)
    testing.expect(t, state^.ui_runtime.library.entry_name.dirty)
    uilibrary.library_entry_name_service(state, 0.001)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 10)
    testing.expect_value(t,
        string(state^.preferences_runtime.collections_state.entries[0].custom_name[:10]),
        "Start here")
    testing.expect(t, !state^.ui_runtime.library.entry_name.dirty)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(1))
}

// Opening without edits is inert; explicitly matching canonical text is still an override.
@(test)
library_entry_name_untouched_and_explicit_canonical_override :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(41)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, entry_id,
        settings_save_test_id(42)), collections.Policy_Error.None)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    uilibrary.library_entry_name_service(state, 1)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(0))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_flush(state))
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 5)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(1))
}

// A full save queue retains the rejected draft rather than rebinding its owner.
@(test)
library_entry_name_admission_failure_retains_draft :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    defer user_data.store_close(&store)
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    state^.preferences_runtime.settings_store = &store
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(51)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, entry_id,
        settings_save_test_id(52)), collections.Policy_Error.None)
    second_entry_id := settings_save_test_id(53)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, second_entry_id,
        settings_save_test_id(54)), collections.Policy_Error.None)
    state^.preferences_runtime.collection_mutation_count = collections.MUTATION_CAPACITY
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Start"))
    testing.expect(t, !uilibrary.library_entry_name_flush(state))
    testing.expect(t, state^.ui_runtime.library.entry_name.active)
    testing.expect(t, state^.ui_runtime.library.entry_name.dirty)
    state^.ui_runtime.library.actions.drawer = {
        entry_id = entry_id,
        open = true,
    }
    testing.expect(t, !uilibrary.tree_actions_close_context(&state^.ui_runtime, state))
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t,
        state^.ui_runtime.library.entry_name.last_admission_error,
        collections.Mutation_Error.Capacity)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 0)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(0))
    testing.expect(t, !uilibrary.library_entry_name_begin(state, second_entry_id, "Other"))
    testing.expect_value(t, state^.ui_runtime.library.entry_name.entry_id, entry_id)
}

// Closing the drawer admits the draft before retiring its editor context.
@(test)
library_entry_name_context_close_flushes_before_retirement :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(55)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, entry_id,
        settings_save_test_id(56)), collections.Policy_Error.None)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Start"))
    state^.ui_runtime.library.actions.drawer = {
        entry_id = entry_id,
        open = true,
    }
    testing.expect(t, uilibrary.tree_actions_close_context(&state^.ui_runtime, state))
    testing.expect(t, !state^.ui_runtime.library.entry_name.active)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entries[0].custom_name_length, 5)
    testing.expect_value(t,
        string(state^.preferences_runtime.collections_state.entries[0].custom_name[:5]),
        "Start")
    testing.expect(t, !state^.ui_runtime.library.actions.drawer.open)
}

// Removing an edited Favorite discards its unaccepted draft without a rename mutation.
@(test)
library_entry_name_removed_owner_is_retired :: proc(t: ^testing.T) {
    state := settings_save_test_state()
    defer settings_save_test_destroy_state(state)
    collections.initialize(&state^.preferences_runtime.collections_state)
    entry_id := settings_save_test_id(61)
    testing.expect_value(t, collections.favorites_add(
        &state^.preferences_runtime.collections_state, entry_id,
        settings_save_test_id(62)), collections.Policy_Error.None)
    testing.expect(t, uilibrary.library_entry_name_begin(state, entry_id, "Point"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, "Start"))
    mutation := settings_save_test_remove_favorite(state, entry_id)
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, mutation),
        collections.Mutation_Error.None)
    testing.expect(t, !state^.ui_runtime.library.entry_name.active)
    testing.expect_value(t,
        state^.preferences_runtime.collections_state.entry_count, 0)
}
