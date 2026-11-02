#+test
package viewsharing

import sharingmodel "../../view/sharing/model"
import core "../../core"
import collections "../../collections"
import userdata "../../persistence/userdata"
import taskpool "../../taskpool"
import viewuserdata "../userdata"
import "core:encoding/uuid"
import "core:fmt"
import "core:os"
import filepath "core:path/filepath"
import "core:testing"

Exchange_Runtime_Test_Path :: struct {
    directory: string,
    filename: string,
    valid: bool,
}

Exchange_Runtime_Failed_Commit_Fixture :: struct {
    display: collections.Set,
    fresh: collections.Set,
    attempted_collections: [1]userdata.Import_Plan_Collection,
    attempted_entries: [2]userdata.Import_Plan_Entry,
    attempted_plan: userdata.Collection_Import_Plan,
}

// Verify exports add the format extension without duplicating an existing one.
@(test)
exchange_runtime_export_path_adds_extension :: proc(t: ^testing.T) {
    payload: sharingmodel.Exchange_Task_Payload
    testing.expect(t, exchange_runtime_copy_export_path(&payload, "collections"))
    testing.expect_value(t, string(payload.path[:payload.path_length]),
        "collections.euclid")

    testing.expect(t,
        exchange_runtime_copy_export_path(&payload, "collections.EUCLID"))
    testing.expect_value(t, string(payload.path[:payload.path_length]),
        "collections.EUCLID")
}

// Destroy collection Sets owned by a failed-commit fixture.
exchange_runtime_test_destroy_failed_commit_fixture :: proc(
    fixture: ^Exchange_Runtime_Failed_Commit_Fixture) {
    collections.destroy(&fixture.display)
    collections.destroy(&fixture.fresh)
}

// Create a deterministic local database path for exchange runtime tests.
exchange_runtime_test_path :: proc(t: ^testing.T) -> Exchange_Runtime_Test_Path {
    result: Exchange_Runtime_Test_Path
    temporary, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
        return result
    }
    result.directory, _ = filepath.join(
        []string{temporary, fmt.tprintf("euclid-exchange-%x", uintptr(t))},
        context.temp_allocator)
    if len(result.directory) == 0 ||
        os.make_directory_all(result.directory) != nil {
        return result
    }
    result.filename, _ = filepath.join(
        []string{result.directory, "sharing.sqlite3"}, context.temp_allocator)
    result.valid = len(result.filename) > 0
    return result
}

// Remove an isolated database fixture after its connection is closed.
exchange_runtime_test_path_destroy :: proc(path: Exchange_Runtime_Test_Path) {
    if len(path.directory) > 0 {
        _ = os.remove_all(path.directory)
    }
}

// Create a deterministic nonzero identifier for plan fixtures.
exchange_runtime_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Populate one collection and one root animation in caller-owned plan buffers.
exchange_runtime_test_plan :: proc(
    plan: ^userdata.Collection_Import_Plan,
    collection_rows: []userdata.Import_Plan_Collection,
    entry_rows: []userdata.Import_Plan_Entry,
    id_base: u8) {
    collection_rows[0] = {
        id = exchange_runtime_test_id(id_base),
        name = "Imported",
    }
    entry_rows[0] = {
        collection = 0,
        parent = -1,
        id = exchange_runtime_test_id(id_base + 1),
        animation_id = exchange_runtime_test_id(id_base + 2),
        sibling_order = 0,
        name = "Parent",
    }
    entry_rows[1] = {
        collection = 0,
        parent = 0,
        id = exchange_runtime_test_id(id_base + 3),
        animation_id = exchange_runtime_test_id(id_base + 4),
        sibling_order = 0,
    }
    plan^ = {
        collections = collection_rows[:],
        entries = entry_rows[:],
    }
}

// Compare collection IDs, orders, entry parents, and sibling positions.
exchange_runtime_test_sets_equal :: proc(
    first, second: ^collections.Set) -> bool {
    if first.collection_count != second.collection_count ||
        first.entry_count != second.entry_count ||
        collections.validate(first) != .None ||
        collections.validate(second) != .None {
        return false
    }
    for collection in first.collections[:first.collection_count] {
        index := collections.find_collection(second, collection.id)
        if index < 0 {
            return false
        }
        other := second.collections[index]
        if collection.role != other.role || collection.order != other.order ||
            string(collection.name[:collection.name_length]) !=
                string(other.name[:other.name_length]) {
            return false
        }
    }
    for entry in first.entries[:first.entry_count] {
        index := collections.find_entry(second, entry.id)
        if index < 0 {
            return false
        }
        other := second.entries[index]
        if entry.collection_id != other.collection_id ||
            entry.parent_entry_id != other.parent_entry_id ||
            entry.sibling_order != other.sibling_order ||
            entry.animation_id != other.animation_id {
            return false
        }
    }
    return true
}

// Verify the display Set matches a fresh database load after importing the same plan.
@(test)
exchange_runtime_imported_set_matches_fresh_database_load :: proc(t: ^testing.T) {
    path := exchange_runtime_test_path(t)
    defer exchange_runtime_test_path_destroy(path)
    testing.expect(t, path.valid)
    if !path.valid {
        return
    }
    store: userdata.Store
    testing.expect_value(t, userdata.store_open(&store, path.filename).kind,
        userdata.Store_Error_Kind.None)
    defer userdata.store_close(&store)
    display: collections.Set
    fresh: collections.Set
    defer collections.destroy(&display)
    defer collections.destroy(&fresh)
    testing.expect(t, collections.initialize(&display))
    testing.expect(t, collections.initialize(&fresh))
    testing.expect_value(t,
        userdata.store_load_collections(&store, &display).kind,
        userdata.Store_Error_Kind.None)
    collection_rows: [1]userdata.Import_Plan_Collection
    entry_rows: [2]userdata.Import_Plan_Entry
    plan: userdata.Collection_Import_Plan
    exchange_runtime_test_plan(&plan, collection_rows[:], entry_rows[:], 31)
    testing.expect_value(t,
        userdata.store_import_collections(&store, &plan).kind,
        userdata.Store_Error_Kind.None)
    testing.expect(t, exchange_runtime_apply_plan_to_set(&display, &plan))
    testing.expect_value(t,
        userdata.store_load_collections(&store, &fresh).kind,
        userdata.Store_Error_Kind.None)
    testing.expect(t, exchange_runtime_test_sets_equal(&display, &fresh))
}

// Join one exchange task through the normal owner service path.
exchange_runtime_test_join_task :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) {
    exchange := exchange_runtime_get(state)
    for exchange.task_active {
        taskpool.task_pool_wait_for_progress(pool)
        exchange_runtime_service(state, pool, nil, nil)
    }
}

// Prepare persisted topology and prove an interrupted transaction rolls back.
exchange_runtime_test_prepare_failed_commit :: proc(
    t: ^testing.T,
    store: ^userdata.Store,
    fixture: ^Exchange_Runtime_Failed_Commit_Fixture) -> bool {
    if !collections.initialize(&fixture.display) ||
        !collections.initialize(&fixture.fresh) {
        return false
    }
    base_collections: [1]userdata.Import_Plan_Collection
    base_entries: [2]userdata.Import_Plan_Entry
    base_plan: userdata.Collection_Import_Plan
    exchange_runtime_test_plan(
        &base_plan, base_collections[:], base_entries[:], 41)
    if !userdata.store_error_is_clear(
        userdata.store_import_collections(store, &base_plan)) ||
        !userdata.store_error_is_clear(
            userdata.store_load_collections(store, &fixture.display)) {
        return false
    }
    exchange_runtime_test_plan(&fixture.attempted_plan,
        fixture.attempted_collections[:], fixture.attempted_entries[:], 51)
    failure := userdata.store_import_collections_internal(
        store, &fixture.attempted_plan, 1)
    testing.expect(t, !userdata.store_error_is_clear(failure))
    if !userdata.store_error_is_clear(
        userdata.store_load_collections(store, &fixture.fresh)) {
        return false
    }
    return exchange_runtime_test_sets_equal(
        &fixture.display, &fixture.fresh)
}

// Assert the worker failure unlocks edits and leaves persisted topology unchanged.
exchange_runtime_test_expect_failed_commit :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime,
    store: ^userdata.Store,
    fixture: ^Exchange_Runtime_Failed_Commit_Fixture) {
    testing.expect(t,
        !exchange.collection_edit_locked &&
            !state^.ui_runtime.sharing.collection_edit_locked)
    testing.expect_value(t, exchange.phase, sharingmodel.Exchange_Phase.Idle)
    testing.expect_value(t, exchange.payload.result.kind,
        sharingmodel.Exchange_Task_Result_Kind.Persistence_Failed)
    testing.expect(t,
        viewuserdata.connection_admission_is_idle(&state^.user_data_admission))
    testing.expect_value(t,
        userdata.store_load_collections(store, &fixture.fresh).kind,
        userdata.Store_Error_Kind.None)
    testing.expect(t,
        exchange_runtime_test_sets_equal(&fixture.display, &fixture.fresh))
}

// Verify a failed transactional commit preserves the Set and releases its edit lock.
@(test)
exchange_runtime_failed_commit_keeps_set_and_unlocks :: proc(t: ^testing.T) {
    path := exchange_runtime_test_path(t)
    defer exchange_runtime_test_path_destroy(path)
    testing.expect(t, path.valid)
    if !path.valid {
        return
    }
    store: userdata.Store
    testing.expect_value(t, userdata.store_open(&store, path.filename).kind,
        userdata.Store_Error_Kind.None)
    defer userdata.store_close(&store)
    fixture: Exchange_Runtime_Failed_Commit_Fixture
    defer exchange_runtime_test_destroy_failed_commit_fixture(&fixture)
    prepared := exchange_runtime_test_prepare_failed_commit(t, &store, &fixture)
    testing.expect(t, prepared)
    if !prepared {
        return
    }

    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 3))
    defer taskpool.task_pool_destroy(&pool)
    defer _ = exchange_runtime_shutdown(state, &pool)
    exchange := exchange_runtime_ensure(state)
    exchange.phase = .Committing
    exchange.collection_edit_locked = true
    state^.ui_runtime.sharing.collection_edit_locked = true
    exchange.payload.kind = .Commit_Import
    exchange.payload.store = &store
    exchange.payload.plan = &fixture.attempted_plan
    store.status = .Read_Only
    testing.expect(t, exchange_runtime_submit(state, exchange, &pool))
    exchange_runtime_test_join_task(state, &pool)
    exchange_runtime_test_expect_failed_commit(
        t, state, exchange, &store, &fixture)
}

// Verify an outstanding settings edit holds commit admission in the drain phase.
@(test)
exchange_runtime_commit_waits_for_pending_save :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    pool: taskpool.Task_Pool
    exchange := exchange_runtime_ensure(state)
    defer _ = exchange_runtime_shutdown(state, &pool)
    state^.preferences_runtime.settings_pending.count = 1
    exchange.phase = .Draining_For_Commit
    exchange_runtime_service(state, &pool, nil, nil)
    testing.expect_value(t, exchange.phase,
        sharingmodel.Exchange_Phase.Draining_For_Commit)
    testing.expect(t, !exchange.task_active)
    testing.expect(t, !exchange.collection_edit_locked)
    state^.preferences_runtime.settings_pending.count = 0
    state^.ui_runtime.library.collection_note.dirty = true
    exchange_runtime_service(state, &pool, nil, nil)
    testing.expect_value(t, exchange.phase,
        sharingmodel.Exchange_Phase.Draining_For_Commit)
    testing.expect(t, !exchange.collection_edit_locked)
}
