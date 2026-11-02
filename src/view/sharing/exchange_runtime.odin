package viewsharing

import sharingmodel "./model"
import core "../../core"
import collections "../../collections"
import userdata "../../persistence/userdata"
import taskpool "../../taskpool"
import viewpreferences "../preferences"
import storage "../../core/storage"
import viewuserdata "../userdata"
import "core:encoding/uuid"
import "core:log"
import "core:strings"
import "core:sync"

EXCHANGE_FILE_EXTENSION :: ".euclid"

// Retrieve the runtime without allocating when reporting or releasing state.
exchange_runtime_get :: proc(
    state: ^core.Euclid_General_State) -> ^sharingmodel.Exchange_Runtime {
    if state == nil {
        return nil
    }
    opaque := state^.ui_runtime.sharing.exchange_runtime
    return cast(^sharingmodel.Exchange_Runtime)opaque
}

// Expose the arena owner to display-side allocation evidence without exposing its layout.
exchange_runtime_arena :: proc(
    state: ^core.Euclid_General_State) -> ^storage.Arena_Owner {
    exchange := exchange_runtime_ensure(state)
    if exchange == nil {
        return nil
    }
    return &exchange.arena
}

// Allocate exchange state once and retain it in the UI-owned opaque slot.
exchange_runtime_ensure :: proc(
    state: ^core.Euclid_General_State) -> ^sharingmodel.Exchange_Runtime {
    exchange := exchange_runtime_get(state)
    if exchange != nil {
        return exchange
    }
    if state == nil {
        return nil
    }
    owner := &state^.ui_runtime.sharing.exchange_state_storage
    if !owner.initialized && !storage.arena_owner_init(owner) {
        log.error("sharing_exchange_state_storage_init_failed")
        return nil
    }
    allocator := storage.arena_owner_allocator(owner)
    exchange = new(sharingmodel.Exchange_Runtime, allocator)
    if exchange == nil {
        storage.arena_owner_destroy(owner)
        log.error("sharing_exchange_state_allocation_failed")
        return nil
    }
    state^.ui_runtime.sharing.exchange_runtime = exchange
    return exchange
}

// Queue an export and retain its selection while pending saves drain.
exchange_runtime_request_export :: proc(
    state: ^core.Euclid_General_State, selected_ids: []uuid.Identifier,
    path: string) -> sharingmodel.Exchange_Request_Result {
    if state == nil || len(selected_ids) == 0 ||
        len(selected_ids) > sharingmodel.EXCHANGE_SELECTION_CAPACITY ||
        !exchange_runtime_path_valid(path, true) ||
        state^.preferences_runtime.settings_store == nil {
        return .Invalid_Request
    }
    exchange := exchange_runtime_ensure(state)
    if exchange == nil {
        return .Failed
    }
    if exchange.phase != .Idle {
        return .Busy
    }
    if !exchange_runtime_copy_export_path(&exchange.payload, path) ||
        !exchange_runtime_copy_selection(
            &exchange.payload, &state^.preferences_runtime.collections_state,
            selected_ids) {
        exchange.payload = {}
        return .Invalid_Request
    }
    exchange.payload.kind = .Export
    exchange.payload.store = state^.preferences_runtime.settings_store
    exchange.phase = .Draining_For_Export
    return .Started
}

// Begin bounded parsing from the selected path, replacing only an idle or staged import.
exchange_runtime_request_import :: proc(
    state: ^core.Euclid_General_State, path: string) ->
    sharingmodel.Exchange_Request_Result {
    if state == nil || state^.simulation_executor == nil ||
        !exchange_runtime_path_valid(path, false) {
        return .Invalid_Request
    }
    exchange := exchange_runtime_ensure(state)
    if exchange == nil {
        return .Failed
    }
    if exchange.phase == .Staged {
        if !exchange_memory_destroy(exchange) {
            return .Failed
        }
        exchange.phase = .Idle
    }
    if exchange.phase != .Idle {
        return .Busy
    }
    exchange.payload = {}
    if !exchange_runtime_copy_path(&exchange.payload, path) ||
        !exchange_memory_prepare_import(exchange) {
        exchange_runtime_finish(state, exchange)
        return .Failed
    }
    exchange.payload.kind = .Parse_Import
    if !exchange_runtime_submit(state, exchange, &state^.simulation_executor^.pool) {
        exchange_memory_destroy(exchange)
        exchange_runtime_finish(state, exchange)
        return .Failed
    }
    exchange.phase = .Parsing
    return .Started
}

// Confirm the checked staged import and stop accepting edits before save drain.
exchange_runtime_confirm_import :: proc(
    state: ^core.Euclid_General_State,
    selected: []bool) -> sharingmodel.Exchange_Request_Result {
    if state == nil {
        return .Invalid_Request
    }
    exchange := exchange_runtime_ensure(state)
    if exchange == nil {
        return .Failed
    }
    if exchange.phase != .Staged || exchange.payload.staged == nil ||
        len(selected) != exchange.resolved_collection_count ||
        len(selected) > len(exchange.selected_import_collections) {
        return .Busy
    }
    if !exchange_runtime_select_import_collections(exchange, selected) {
        return .Invalid_Request
    }
    if !exchange_runtime_flush_import_note(state, exchange) {
        return .Failed
    }
    exchange.edit_admission_blocked = true
    state^.ui_runtime.sharing.edit_admission_blocked = true
    exchange.phase = .Draining_For_Commit
    return .Started
}

// Flush accepted note edits before locking import admission, retaining edit restoration.
exchange_runtime_flush_import_note :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) -> bool {
    note := &state^.ui_runtime.library.collection_note
    if note^.dirty && note^.save_failed {
        return false
    }
    was_editing := note^.editing || note^.edit_requested
    if note^.dirty || note^.editing || note^.edit_requested {
        flush_accepted :=
            viewpreferences.settings_save_collection_note_flush(state)
        if !flush_accepted &&
            !state^.preferences_runtime.settings_save_active &&
            state^.preferences_runtime.note_request_kind == .None {
            return false
        }
        note^.editing = false
        note^.edit_requested = false
    }
    exchange.restore_note_editing = was_editing
    return true
}

// Copy accepted checklist bits into the exchange-owned fixed-capacity selection.
exchange_runtime_select_import_collections :: proc(
    exchange: ^sharingmodel.Exchange_Runtime, selected: []bool) -> bool {
    exchange.selected_import_count = 0
    exchange.selected_import_collections = {}
    for checked, index in selected {
        if checked && exchange.resolved_collections[index].importable {
            exchange.selected_import_collections[index] = true
            exchange.selected_import_count += 1
        }
    }
    return exchange.selected_import_count > 0
}

// Cancel a staged operation; running tasks retain all storage until joined.
exchange_runtime_cancel :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) -> bool {
    if state == nil || pool == nil {
        return false
    }
    exchange := exchange_runtime_get(state)
    if exchange == nil {
        return false
    }
    if exchange.task_active {
        if exchange.phase != .Committing {
            sync.atomic_store_explicit(
                &exchange.payload.cancel_requested, 1, .Release)
            _ = taskpool.task_pool_cancel(pool, exchange.handle)
        }
        return true
    }
    if exchange.phase == .Staged {
        exchange_runtime_discard_stage(state, exchange)
        return true
    }
    if exchange.phase == .Draining_For_Export ||
        exchange.phase == .Draining_For_Commit {
        exchange_runtime_restore_note_editing(state, exchange)
        exchange_runtime_discard_stage(state, exchange)
        return true
    }
    return false
}

// Poll joined work and advance save-drain phases on the display owner.
exchange_runtime_service :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool,
    is_installed: Exchange_Installed_Proc, catalog: rawptr,
    history_ready: bool = false) {
    if state == nil || pool == nil {
        return
    }
    exchange := exchange_runtime_get(state)
    if exchange == nil {
        return
    }
    if exchange.task_active {
        exchange_runtime_poll_task(state, pool, is_installed, catalog)
    }
    if exchange.phase == .Draining_For_Export &&
        exchange_runtime_saves_drained(state, history_ready) {
        exchange.phase = .Exporting
        if !exchange_runtime_submit(state, exchange, pool) {
            exchange_runtime_finish(state, exchange)
        }
    } else if exchange.phase == .Draining_For_Commit &&
        exchange_runtime_saves_drained(state, history_ready) {
        exchange_runtime_begin_commit(state, exchange, pool)
    }
}

// Build and submit the staged import after every competing save has drained.
exchange_runtime_begin_commit :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime,
    pool: ^taskpool.Task_Pool) {
    exchange.collection_edit_locked = true
    state^.ui_runtime.sharing.collection_edit_locked = true
    if !exchange_runtime_build_plan(
        exchange, &state^.preferences_runtime.collections_state) {
        log.error("sharing_exchange_plan_build_failed")
        exchange_runtime_restore_note_editing(state, exchange)
        exchange_runtime_discard_stage(state, exchange)
        return
    }
    exchange.payload.kind = .Commit_Import
    exchange.payload.store = state^.preferences_runtime.settings_store
    exchange.phase = .Committing
    if !exchange_runtime_submit(state, exchange, pool) {
        exchange_runtime_discard_stage(state, exchange)
    }
}

// Join one completed worker before observing its task-owned payload.
exchange_runtime_poll_task :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool,
    is_installed: Exchange_Installed_Proc, catalog: rawptr) {
    exchange := exchange_runtime_get(state)
    if exchange == nil {
        log.error("sharing_exchange_task_state_missing")
        return
    }
    if taskpool.task_pool_poll(pool, exchange.handle) == .Pending {
        return
    }
    _, joined := taskpool.task_pool_wait(pool, exchange.handle)
    if joined != .Joined {
        log.error("sharing_exchange_task_join_failed")
        return
    }
    if !exchange_runtime_release_admission_after_join(state, exchange) {
        log.error("sharing_exchange_admission_release_failed")
        exchange.payload.result.kind = .Persistence_Failed
    }
    exchange.task_active = false
    state^.ui_runtime.sharing.exchange_task_active = false
    exchange.handle = {}
    if exchange.payload.result.kind == .Succeeded {
        exchange_runtime_task_succeeded(
            state, exchange, is_installed, catalog)
    } else {
        exchange_runtime_task_failed(state, exchange)
    }
}

// Dispatch a joined result by the phase whose task just completed.
exchange_runtime_task_succeeded :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime,
    is_installed: Exchange_Installed_Proc, catalog: rawptr) {
    #partial switch exchange.phase {
    case .Exporting:
        exchange.exported_collection_count = exchange.payload.selected_count
        exchange_runtime_finish(state, exchange)
    case .Parsing:
        exchange_runtime_resolve_stage(
            state, exchange, is_installed, catalog)
    case .Committing:
        exchange.imported_collection_count = len(exchange.payload.plan.collections)
        state^.ui_runtime.sharing.last_import_omitted_entry_count =
            exchange.left_out_entry_count
        state^.ui_runtime.sharing.import_left_out_entries =
            exchange.left_out_entry_count > 0
        state^.ui_runtime.sharing.import_selection_initialized = false
        if exchange_runtime_apply_plan_to_set(
            &state^.preferences_runtime.collections_state,
            exchange.payload.plan) {
            state^.preferences_runtime.collection_revision += 1
            state^.ui_runtime.library.tree.projection.valid = false
        } else {
            log.error("sharing_exchange_display_apply_failed")
            if !exchange_runtime_reload_collections(state) {
                log.error("sharing_exchange_display_reload_failed")
            }
        }
        exchange.restore_note_editing = false
        exchange_runtime_discard_stage(state, exchange)
    case:
        exchange_runtime_discard_stage(state, exchange)
    }
}

// Resolve imported animation identities only after parsing has joined.
exchange_runtime_resolve_stage :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime,
    is_installed: Exchange_Installed_Proc, catalog: rawptr) {
    if is_installed == nil || exchange.payload.staged == nil {
        exchange.payload.result.kind = .Invalid_Document
        exchange_runtime_discard_stage(state, exchange)
        return
    }
    resolved, ok := exchange_resolve(
        exchange.payload.staged, is_installed, catalog,
        exchange.resolved_collections, exchange.resolved_entries)
    if !ok {
        exchange.payload.result.kind = .Invalid_Document
        exchange_runtime_discard_stage(state, exchange)
        return
    }
    exchange.resolved_collection_count = resolved.collection_count
    exchange.resolved_entry_count = resolved.entry_count
    exchange.left_out_entry_count = resolved.omitted_entry_count
    exchange.phase = .Staged
}

// Build a fresh-identity persistence plan in the staged arena.
exchange_runtime_build_plan :: proc(
    exchange: ^sharingmodel.Exchange_Runtime, set: ^collections.Set) -> bool {
    if exchange == nil || set == nil || exchange.payload.staged == nil ||
        exchange.resolved_collection_count == 0 {
        return false
    }
    return exchange_runtime_allocate_plan(exchange) &&
        exchange_runtime_fill_plan(exchange, set)
}

// Allocate exact plan storage from the arena that owns staged strings.
exchange_runtime_allocate_plan :: proc(
    exchange: ^sharingmodel.Exchange_Runtime) -> bool {
    allocator := storage.arena_owner_allocator(&exchange.arena)
    collection_count := 0
    entry_count := 0
    for collection in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if collection.importable &&
            exchange.selected_import_collections[collection.source_index] {
            collection_count += 1
            entry_count += collection.resolved_entry_count
        }
    }
    if collection_count == 0 || entry_count == 0 {
        return false
    }
    plan := new(userdata.Collection_Import_Plan, allocator)
    plan_collections, collection_error := make(
        []userdata.Import_Plan_Collection, collection_count, allocator)
    plan_entries, entry_error := make(
        []userdata.Import_Plan_Entry, entry_count, allocator)
    if plan == nil || collection_error != nil || entry_error != nil {
        return false
    }
    plan^ = {
        collections = plan_collections,
        entries = plan_entries,
    }
    exchange.payload.plan = plan
    return true
}

// Populate plan entries in source order and assign new local identities.
exchange_runtime_fill_plan :: proc(
    exchange: ^sharingmodel.Exchange_Runtime, set: ^collections.Set) -> bool {
    document := exchange.payload.staged
    plan := exchange.payload.plan
    for index in 0..<exchange.resolved_entry_count {
        exchange.resolved_entry_to_plan[index] = -1
    }
    plan_collection_index := 0
    plan_entry_index := 0
    for resolved in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if !resolved.importable ||
            !exchange.selected_import_collections[resolved.source_index] {
            continue
        }
        source := document.collections[resolved.source_index]
        collection_id, collection_ok := exchange_runtime_new_collection_id(
            set, plan, plan_collection_index)
        if !collection_ok {
            return false
        }
        plan.collections[plan_collection_index] = {
            id = collection_id,
            name = source.name,
        }
        if !exchange_runtime_fill_collection_entries(
            exchange, set, plan_collection_index, resolved.source_index,
            &plan_entry_index) {
            return false
        }
        plan_collection_index += 1
    }
    return plan_entry_index == len(plan.entries)
}

// Append one collection's resolved entries with promoted parent identities.
exchange_runtime_fill_collection_entries :: proc(
    exchange: ^sharingmodel.Exchange_Runtime, set: ^collections.Set,
    plan_collection, source_collection: int, plan_entry_index: ^int) -> bool {
    document := exchange.payload.staged
    plan := exchange.payload.plan
    for resolved_index in 0..<exchange.resolved_entry_count {
        resolved := exchange.resolved_entries[resolved_index]
        if resolved.collection_index != source_collection {
            continue
        }
        source := document.collections[source_collection].entries[
            resolved.source_entry_index]
        entry_id, entry_ok := exchange_runtime_new_entry_id(
            set, plan, plan_entry_index^)
        if !entry_ok {
            return false
        }
        parent := -1
        if resolved.parent_entry_index >= 0 {
            parent = exchange.resolved_entry_to_plan[
                resolved.parent_entry_index]
            if parent < 0 {
                return false
            }
        }
        plan.entries[plan_entry_index^] = {
            collection = plan_collection,
            parent = parent,
            id = entry_id,
            animation_id = source.animation_id,
            sibling_order = resolved.sibling_order,
            name = source.name,
            note = source.note,
            has_note = source.has_note,
            notes_on_top = source.notes_on_top,
        }
        exchange.resolved_entry_to_plan[resolved_index] = plan_entry_index^
        plan_entry_index^ += 1
    }
    return true
}

// Publish committed SQLite topology through the existing display-owned load path.
exchange_runtime_reload_collections :: proc(
    state: ^core.Euclid_General_State) -> bool {
    store := state^.preferences_runtime.settings_store
    if store == nil || !userdata.store_error_is_clear(
        userdata.store_load_collections(
            store, &state^.preferences_runtime.collections_state)) {
        return false
    }
    state^.preferences_runtime.collection_revision += 1
    state^.ui_runtime.library.tree.projection.valid = false
    return true
}

// Atomically add imported topology to the display Set using its persisted identities.
exchange_runtime_apply_plan_to_set :: proc(
    destination: ^collections.Set,
    plan: ^userdata.Collection_Import_Plan) -> bool {
    if destination == nil || plan == nil || len(plan.collections) == 0 ||
        len(plan.entries) == 0 {
        return false
    }
    staged: collections.Set
    if !collections.clone(&staged, destination) {
        return false
    }
    defer collections.destroy(&staged)
    next_order := collections.maximum_collection_order(&staged)
    if next_order == max(i64) {
        return false
    }
    next_order += 1
    for imported, index in plan.collections {
        if next_order > max(i64)-i64(index) {
            return false
        }
        name := transmute([]u8)imported.name
        if collections.append_collection(&staged, {
            id = imported.id,
            role = .User,
            name = name,
            name_length = len(name),
            order = next_order+i64(index),
        }) != .None {
            return false
        }
    }
    if !exchange_runtime_append_plan_entries(&staged, plan) ||
        collections.validate(&staged) != .None {
        return false
    }
    return collections.clone(destination, &staged)
}

// Append depth-first plan entries after mapping parent indexes to stable IDs.
exchange_runtime_append_plan_entries :: proc(
    destination: ^collections.Set,
    plan: ^userdata.Collection_Import_Plan) -> bool {
    for imported, index in plan.entries {
        if imported.collection < 0 ||
            imported.collection >= len(plan.collections) ||
            imported.parent >= index || imported.parent < -1 {
            return false
        }
        parent_id: uuid.Identifier = {}
        if imported.parent >= 0 {
            parent_id = plan.entries[imported.parent].id
        }
        name := transmute([]u8)imported.name
        if collections.append_entry(destination, {
            id = imported.id,
            collection_id = plan.collections[imported.collection].id,
            parent_entry_id = parent_id,
            sibling_order = i64(imported.sibling_order),
            kind = .Animation,
            animation_id = imported.animation_id,
            custom_name = name,
            custom_name_length = len(name),
        }) != .None {
            return false
        }
    }
    return true
}

// Wait for every settings and note write before a store-using exchange task starts.
exchange_runtime_saves_drained :: proc(
    state: ^core.Euclid_General_State, history_ready: bool) -> bool {
    return !state^.preferences_runtime.settings_save_active &&
        !viewpreferences.settings_save_has_pending(
            &state^.preferences_runtime) &&
        !state^.ui_runtime.library.collection_note.dirty &&
        !history_ready &&
        viewuserdata.connection_admission_is_idle(&state^.user_data_admission)
}

// Submit one worker-only task and publish its owned phase only on admission.
exchange_runtime_submit :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime,
    pool: ^taskpool.Task_Pool) -> bool {
    uses_store := exchange.payload.kind == .Export ||
        exchange.payload.kind == .Commit_Import
    admission := &state^.user_data_admission
    if uses_store && !viewuserdata.connection_admission_claim(
        admission, .Collection_Exchange, false, false) {
        exchange.payload.result.kind = .Persistence_Failed
        return false
    }
    exchange.payload.result = {}
    sync.atomic_store_explicit(&exchange.payload.cancel_requested, 0, .Release)
    handle, outcome := taskpool.task_pool_submit(
        pool, exchange_task_run, &exchange.payload, .Worker_Only)
    if outcome != .Queued {
        exchange.payload.result.kind = .Persistence_Failed
        if uses_store && !viewuserdata.connection_admission_release_rejected(
            admission, .Collection_Exchange) {
            log.error("sharing_exchange_rejected_admission_release_failed")
        }
        return false
    }
    if uses_store && !viewuserdata.connection_admission_mark_submitted(
        admission, .Collection_Exchange) {
        log.error("sharing_exchange_admission_submit_transition_failed")
    }
    exchange.handle = handle
    exchange.task_active = true
    state^.ui_runtime.sharing.exchange_task_active = true
    return true
}

// Release SQLite ownership only after the exchange worker has joined.
exchange_runtime_release_admission_after_join :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) -> bool {
    if exchange.payload.kind != .Export &&
        exchange.payload.kind != .Commit_Import {
        return true
    }
    admission := &state^.user_data_admission
    if admission.phase == .Submitted {
        return viewuserdata.connection_admission_release_joined(
            admission, .Collection_Exchange)
    }
    return viewuserdata.connection_admission_release_rejected(
        admission, .Collection_Exchange)
}

// Preserve a previously active note editor when import admission is abandoned.
exchange_runtime_restore_note_editing :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    if exchange.restore_note_editing {
        note := &state^.ui_runtime.library.collection_note
        if note.status == .Ready && !note.save_failed {
            note.editing = true
            note.edit_requested = true
        }
    }
    exchange.restore_note_editing = false
}

// Retire failed worker output while always releasing the commit edit lock.
exchange_runtime_task_failed :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    if exchange.phase == .Exporting {
        exchange_runtime_finish(state, exchange)
        return
    }
    exchange_runtime_restore_note_editing(state, exchange)
    exchange_runtime_discard_stage(state, exchange)
}

// Release staged storage and both edit-admission guards after an operation ends.
exchange_runtime_discard_stage :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    _ = exchange_memory_destroy(exchange)
    exchange_runtime_finish(state, exchange)
}

// Return to Idle while preserving the last joined result for UI feedback.
exchange_runtime_finish :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    result := exchange.payload.result
    exchange.payload = {
        result = result,
    }
    exchange.phase = .Idle
    exchange.task_active = false
    exchange.edit_admission_blocked = false
    exchange.collection_edit_locked = false
    exchange.restore_note_editing = false
    if state != nil {
        state^.ui_runtime.sharing.exchange_task_active = false
        state^.ui_runtime.sharing.edit_admission_blocked = false
        state^.ui_runtime.sharing.collection_edit_locked = false
    }
}

// Validate file paths against fixed storage and export suffix requirements.
exchange_runtime_path_valid :: proc(path: string, exporting: bool) -> bool {
    extension := 0
    suffix := 0
    if exporting {
        if !exchange_runtime_path_has_extension(path) {
            extension = len(EXCHANGE_FILE_EXTENSION)
        }
        suffix = 4
    }
    return len(path) > 0 &&
        len(path)+extension+suffix < sharingmodel.EXCHANGE_PATH_CAPACITY &&
        !strings.contains(path, "\x00")
}

// Detect the format extension without allocating and regardless of ASCII case.
exchange_runtime_path_has_extension :: proc(path: string) -> bool {
    extension := EXCHANGE_FILE_EXTENSION
    if len(path) < len(extension) {
        return false
    }
    suffix := path[len(path)-len(extension):]
    for index in 0..<len(extension) {
        character := suffix[index]
        if character >= 'A' && character <= 'Z' {
            character += 'a' - 'A'
        }
        if character != extension[index] {
            return false
        }
    }
    return true
}

// Copy an export destination and add the format extension when it is missing.
exchange_runtime_copy_export_path :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload, path: string) -> bool {
    if payload == nil || !exchange_runtime_path_valid(path, true) {
        return false
    }
    payload.path_length = len(path)
    copy(payload.path[:payload.path_length], transmute([]u8)path)
    if !exchange_runtime_path_has_extension(path) {
        copy(payload.path[payload.path_length:
            payload.path_length+len(EXCHANGE_FILE_EXTENSION)],
            EXCHANGE_FILE_EXTENSION)
        payload.path_length += len(EXCHANGE_FILE_EXTENSION)
    }
    return true
}

// Copy one already validated path into the task's stable bounded storage.
exchange_runtime_copy_path :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload, path: string) -> bool {
    if payload == nil || !exchange_runtime_path_valid(path, false) {
        return false
    }
    payload.path_length = len(path)
    copy(payload.path[:payload.path_length], transmute([]u8)path)
    return true
}

// Copy distinct user collection IDs before the persistence worker starts.
exchange_runtime_copy_selection :: proc(
    payload: ^sharingmodel.Exchange_Task_Payload, set: ^collections.Set,
    selected_ids: []uuid.Identifier) -> bool {
    if payload == nil || set == nil || len(selected_ids) == 0 ||
        len(selected_ids) > len(payload.selected_ids) {
        return false
    }
    for identifier, index in selected_ids {
        collection_index := collections.find_collection(set, identifier)
        if collection_index < 0 ||
            set.collections[collection_index].role != .User {
            return false
        }
        for previous in 0..<index {
            if selected_ids[previous] == identifier {
                return false
            }
        }
        payload.selected_ids[index] = identifier
    }
    payload.selected_count = len(selected_ids)
    return true
}

// Generate a collection UUID distinct from persisted and planned collection IDs.
exchange_runtime_new_collection_id :: proc(
    set: ^collections.Set, plan: ^userdata.Collection_Import_Plan,
    planned_count: int) -> (uuid.Identifier, bool) {
    for _ in 0..<8 {
        candidate := uuid.generate_v4()
        if candidate == (uuid.Identifier{}) ||
            candidate == collections.FAVORITES_COLLECTION_ID ||
            collections.find_collection(set, candidate) >= 0 {
            continue
        }
        duplicate := false
        for previous in plan.collections[:planned_count] {
            duplicate = duplicate || previous.id == candidate
        }
        if !duplicate {
            return candidate, true
        }
    }
    return {}, false
}

// Generate an entry UUID distinct from persisted and earlier plan entries.
exchange_runtime_new_entry_id :: proc(
    set: ^collections.Set, plan: ^userdata.Collection_Import_Plan,
    planned_count: int) -> (uuid.Identifier, bool) {
    for _ in 0..<8 {
        candidate := uuid.generate_v4()
        if candidate == (uuid.Identifier{}) ||
           collections.find_entry(set, candidate) >= 0 {
            continue
        }
        duplicate := false
        for previous in plan.entries[:planned_count] {
            duplicate = duplicate || previous.id == candidate
        }
        if !duplicate {
            return candidate, true
        }
    }
    return {}, false
}

// Join active exchange work, then release its arena before shared SQLite teardown.
exchange_runtime_shutdown :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) -> bool {
    if state == nil || pool == nil {
        return false
    }
    exchange := exchange_runtime_get(state)
    if exchange == nil {
        storage.arena_owner_destroy(
            &state^.ui_runtime.sharing.exchange_state_storage)
        return true
    }
    if exchange.task_active {
        if exchange.phase != .Committing {
            sync.atomic_store_explicit(
                &exchange.payload.cancel_requested, 1, .Release)
            _ = taskpool.task_pool_cancel(pool, exchange.handle)
        }
        _, joined := taskpool.task_pool_wait(pool, exchange.handle)
        if joined != .Joined {
            log.error("sharing_exchange_shutdown_join_failed")
            return false
        }
        if !exchange_runtime_release_admission_after_join(state, exchange) {
            log.error("sharing_exchange_shutdown_admission_release_failed")
            return false
        }
        exchange.task_active = false
        state^.ui_runtime.sharing.exchange_task_active = false
        exchange.handle = {}
    }
    exchange_runtime_discard_stage(state, exchange)
    state^.ui_runtime.sharing.exchange_runtime = nil
    storage.arena_owner_destroy(
        &state^.ui_runtime.sharing.exchange_state_storage)
    return true
}
