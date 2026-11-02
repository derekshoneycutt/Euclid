package viewpreferences

import taskpool "../../taskpool"
import setting_model "../../settings"
import user_data "../../persistence/userdata"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import log "core:log"
import sync "core:sync"
import uuid "core:encoding/uuid"
import preferencesmodel "model"
import core "../../core"
import collections "../../collections"
import viewmodel "../ui/model"
import viewuserdata "../userdata"
import animation_model "../../core/animation"

SETTINGS_SAVE_MAX_ATTEMPTS :: 3
SETTINGS_SAVE_RETRY_DELAY_FRAMES :: 60

// Commit one immutable preference payload on a shared worker.
settings_save_worker :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    _ = token
    task := cast(^preferencesmodel.Settings_Save_Task_Payload)payload
    task^.worker_thread_id = sync.current_thread_id()
    switch task^.kind {
    case .User_Data_Batch:
        task^.result = user_data.store_commit_user_data(
            task^.store, task^.changes, task^.mutations[:task^.mutation_count])
    case .Collection_Note_Read:
        task^.note_read_result, task^.note_failure =
            user_data.store_read_collection_note(
                task^.store, task^.note_identity, task^.note_text[:])
    case .Collection_Note_Write:
        task^.note_failure = user_data.store_write_collection_note(
            task^.store, task^.note_identity,
            string(task^.note_text[:task^.note_text_length]),
            task^.note_notes_on_top)
    }
    if task^.kind != .User_Data_Batch {
        outcome := user_data.Commit_Outcome.Not_Committed
        if user_data.store_error_is_clear(task^.note_failure) {
            outcome = .Committed
        }
        task^.result = {
            outcome = outcome,
            failure = task^.note_failure,
        }
    }
    return .Succeeded if task^.result.outcome == .Committed else .Failed
}

// Treat settings and collection edits as one outstanding persistence batch.
settings_save_has_pending :: proc(
    runtime: ^preferencesmodel.Settings_Save_Runtime) -> bool {
    return runtime^.settings_pending.count > 0 ||
        runtime^.collection_mutation_count > 0 ||
        runtime^.note_request_kind != .None
}

// Report whether a save can currently compete for the shared connection.
settings_save_ready :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return false
    }
    runtime := &state^.preferences_runtime
    status := state^.ui_runtime.preferences.save_status
    sharing := &state^.ui_runtime.sharing
    return runtime^.settings_store != nil && !runtime^.settings_save_active &&
        !sharing.exchange_task_active && !sharing.collection_edit_locked &&
        settings_save_has_pending(runtime) && runtime^.settings_retry_frames == 0 &&
        (status != .Unavailable && status != .Failed ||
            runtime^.note_request_kind == .Read)
}

// Record an accepted user-data edit and preserve unresolved failure context.
settings_save_note_edit :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    runtime := &state^.preferences_runtime
    runtime^.user_data_revision += 1
    if runtime^.settings_store == nil {
        state^.ui_runtime.preferences.save_status = .Unavailable
        return
    }
    if runtime^.settings_save_active {
        state^.ui_runtime.preferences.save_status = .Saving
        return
    }
    if runtime^.user_data_failure_unresolved {
        state^.ui_runtime.preferences.save_status = .Pending
        return
    }
    if (state^.ui_runtime.preferences.save_status == .Unavailable ||
        state^.ui_runtime.preferences.save_status == .Failed) &&
        runtime^.note_request_kind != .Read {
        runtime^.settings_failure_count = 0
        runtime^.settings_retry_frames = 0
    }
    state^.ui_runtime.preferences.save_status = .Pending
}

// Request an identity-qualified note read for the selected collection placement.
settings_save_collection_note_load :: proc(
    state: ^core.Euclid_General_State,
    identity: collections.Placement_Identity,
    request_edit := false) -> bool {
    if state == nil || state^.ui_runtime.sharing.edit_admission_blocked ||
        state^.ui_runtime.sharing.collection_edit_locked {
        return false
    }
    note := &state^.ui_runtime.library.collection_note
    generation := state^.animation_memory.generation
    if state^.preferences_runtime.settings_store == nil || generation == 0 {
        settings_save_collection_note_mark_load_failed(state, identity, generation)
        log.error("collection_note_load_unavailable")
        return false
    }
    animation_id, eligible := settings_save_collection_note_eligible_animation(
        &state^.preferences_runtime.collections_state, identity)
    if !eligible {
        settings_save_collection_note_mark_load_failed(state, identity, generation)
        log.error("collection_note_load_rejected_ineligible_placement")
        return false
    }
    if settings_save_collection_note_owner_matches(note, identity, generation) {
        return settings_save_collection_note_load_current(
            state, identity, request_edit)
    }
    if note^.dirty {
        _ = settings_save_collection_note_queue_write(state)
        log.warn("collection_note_selection_waiting_for_save")
        return false
    }
    settings_save_collection_note_start_read(
        state, identity, animation_id, generation, request_edit)
    return true
}

// Resolve only animation placements owned by a user collection.
settings_save_collection_note_eligible_animation :: proc(
    snapshot: ^collections.Set,
    identity: collections.Placement_Identity) -> (uuid.Identifier, bool) {
    placement, policy := collections.placement_resolve(snapshot, identity)
    collection_index := collections.find_collection(snapshot, identity.collection_id)
    eligible := policy == .None && placement.kind == .Animation &&
        collection_index >= 0 && snapshot^.collections[collection_index].role == .User
    return placement.animation_id, eligible
}

// Match every placement and generation component before accepting a cached note.
settings_save_collection_note_owner_matches :: proc(
    note: ^viewmodel.Ui_Library_Collection_Note,
    identity: collections.Placement_Identity, generation: u64) -> bool {
    return note^.generation == generation &&
        note^.identity.collection_id == identity.collection_id &&
        note^.identity.entry_id == identity.entry_id &&
        note^.identity.parent_entry_id == identity.parent_entry_id
}

// Reuse a current owner or restart only its failed, clean read.
settings_save_collection_note_load_current :: proc(
    state: ^core.Euclid_General_State,
    identity: collections.Placement_Identity, request_edit: bool) -> bool {
    note := &state^.ui_runtime.library.collection_note
    note^.edit_requested = note^.edit_requested || request_edit
    if note^.status == .Ready {
        note^.editing = note^.editing || request_edit
        return true
    }
    if note^.status == .Loading {
        return true
    }
    if note^.status == .Failed && !note^.dirty {
        note^.request_id += 1
        note^.status = .Loading
        settings_save_collection_note_schedule_read(
            state, identity, note^.generation, note^.request_id)
        return true
    }
    return false
}

// Initialize one new placement owner and schedule its bounded read.
settings_save_collection_note_start_read :: proc(
    state: ^core.Euclid_General_State,
    identity: collections.Placement_Identity,
    animation_id: uuid.Identifier,
    generation: u64,
    request_edit: bool) {
    note := &state^.ui_runtime.library.collection_note
    request_id := note^.request_id + 1
    split_ratio := note^.split_ratio
    if split_ratio <= 0 || split_ratio >= 1 {
        split_ratio = 0.5
    }
    note^ = {
        identity = identity,
        animation_id = animation_id,
        generation = generation,
        request_id = request_id,
        split_ratio = split_ratio,
        status = .Loading,
        edit_requested = request_edit,
    }
    settings_save_collection_note_schedule_read(
        state, identity, generation, request_id)
}

// Publish one identity-qualified read request to the shared save owner.
settings_save_collection_note_schedule_read :: proc(
    state: ^core.Euclid_General_State,
    identity: collections.Placement_Identity,
    generation: u64,
    request_id: u64) {
    runtime := &state^.preferences_runtime
    runtime^.note_request_kind = .Read
    runtime^.note_identity = identity
    runtime^.note_generation = generation
    runtime^.note_request_id = request_id
    runtime^.note_revision = 0
    runtime^.note_text_length = 0
    runtime^.note_notes_on_top = false
}

// Publish an explicit failed load owner without retiring an unsaved draft.
settings_save_collection_note_mark_load_failed :: proc(
    state: ^core.Euclid_General_State,
    identity: collections.Placement_Identity, generation: u64) {
    note := &state^.ui_runtime.library.collection_note
    if note^.dirty {
        return
    }
    request_id := note^.request_id + 1
    split_ratio := note^.split_ratio
    note^ = {
        identity = identity,
        generation = generation,
        request_id = request_id,
        split_ratio = split_ratio,
        status = .Failed,
    }
}

// Coalesce a dirty note revision into the shared bounded user-data worker.
settings_save_collection_note_queue_write :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil ||
        state^.ui_runtime.sharing.collection_edit_locked {
        return false
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.status != .Ready || !note^.dirty ||
        !note^.editing || note^.generation != state^.animation_memory.generation {
        return false
    }
    if note^.save_failed {
        return false
    }
    runtime := &state^.preferences_runtime
    runtime^.note_request_kind = .Write
    runtime^.note_identity = note^.identity
    runtime^.note_generation = note^.generation
    runtime^.note_request_id = note^.request_id
    runtime^.note_revision = note^.revision
    runtime^.note_text_length = note^.text_length
    runtime^.note_notes_on_top = note^.notes_on_top
    return true
}

// Mark one accepted editor or reading-order change for debounced persistence.
settings_save_collection_note_edit :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.ui_runtime.sharing.edit_admission_blocked ||
        state^.ui_runtime.sharing.collection_edit_locked {
        return false
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.status != .Ready || !note^.editing ||
        note^.generation != state^.animation_memory.generation {
        return false
    }
    note^.revision += 1
    note^.dirty = true
    note^.save_failed = false
    note^.debounce_remaining_seconds = 0.4
    settings_save_note_edit(state)
    return true
}

// Flush the current note revision before the editor can be retired.
settings_save_collection_note_flush :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return true
    }
    note := &state^.ui_runtime.library.collection_note
    if !note^.dirty {
        note^.editing = false
        note^.edit_requested = false
        return true
    }
    if note^.save_failed {
        return false
    }
    note^.leave_editing_after_save = true
    note^.debounce_remaining_seconds = 0
    active := &state^.preferences_runtime.settings_save_payload
    if state^.preferences_runtime.settings_save_active &&
        active^.kind == .Collection_Note_Write &&
        active^.note_revision == note^.revision &&
        active^.note_request_id == note^.request_id &&
        active^.note_generation == note^.generation &&
        active^.note_identity.collection_id == note^.identity.collection_id &&
        active^.note_identity.entry_id == note^.identity.entry_id {
        return false
    }
    return settings_save_collection_note_queue_write(state)
}

// Retire an unedited note owner while invalidating any pending stale read.
settings_save_collection_note_clear :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return true
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.dirty {
        _ = settings_save_collection_note_queue_write(state)
        return false
    }
    request_id := note^.request_id + 1
    if state^.preferences_runtime.note_request_kind == .Read {
        state^.preferences_runtime.note_request_kind = .None
    }
    note^ = {
        request_id = request_id,
    }
    return true
}

// Accept one locally prepared collection edit and retain its immutable durable replay.
settings_save_collection_mutation :: proc(
    state: ^core.Euclid_General_State,
    mutation: collections.Mutation,
    canonical_name: string = "") -> collections.Mutation_Error {
    if state == nil {
        return .Invalid_Entry
    }
    if state^.ui_runtime.sharing.edit_admission_blocked ||
        state^.ui_runtime.sharing.collection_edit_locked {
        return .Policy
    }
    if settings_save_note_mutation_retires_owner(state, mutation) &&
       state^.ui_runtime.library.collection_note.dirty {
        log.warn("collection_note_mutation_blocked_by_dirty_revision")
        return .Policy
    }
    runtime := &state^.preferences_runtime
    if !settings_save_collection_mutation_has_capacity(runtime) {
        return .Capacity
    }
    projection := &state^.ui_runtime.library.tree.projection
    prepare_error := viewmodel.ui_tree_projection_prepare_mutation(
        projection, mutation, canonical_name)
    if prepare_error != .None {
        return prepare_error
    }
    mutation_error := collections.apply_mutation(
        &runtime^.collections_state, mutation)
    if mutation_error != .None {
        viewmodel.ui_tree_projection_abort_mutation(projection)
        return mutation_error
    }
    settings_save_publish_collection_mutation(state, mutation)
    return .None
}

// Identify collection operations that remove the currently borrowed note placement.
settings_save_note_mutation_retires_owner :: proc(
    state: ^core.Euclid_General_State, mutation: collections.Mutation) -> bool {
    note := &state^.ui_runtime.library.collection_note
    if note^.status == .Idle {
        return false
    }
    #partial switch mutation.kind {
    case .Delete_Collection:
        return mutation.collection_id == note^.identity.collection_id
    case .Remove_Collection_Animation:
        return mutation.entry_id == note^.identity.entry_id
    }
    return false
}

// Publish an accepted mutation to the display projection and ordered save queue.
settings_save_publish_collection_mutation :: proc(
    state: ^core.Euclid_General_State,
    mutation: collections.Mutation) {
    runtime := &state^.preferences_runtime
    projection := &state^.ui_runtime.library.tree.projection
    if mutation.kind == .Remove_Favorite &&
        state^.ui_runtime.library.entry_name.active &&
        state^.ui_runtime.library.entry_name.entry_id == mutation.entry_id {
        state^.ui_runtime.library.entry_name = {}
    }
    runtime^.collection_revision += 1
    if !viewmodel.ui_tree_projection_commit_mutation(
        &state^.ui_runtime, &runtime^.collections_state, mutation,
        runtime^.collection_revision) {
        log.error("library_projection_mutation_commit_failed")
        projection.valid = false
    }
    if runtime^.settings_store != nil {
        runtime^.collection_mutations[runtime^.collection_mutation_count] = mutation
        runtime^.collection_mutation_count += 1
    }
    if settings_save_note_mutation_retires_owner(state, mutation) {
        _ = settings_save_collection_note_clear(state)
    }
    settings_save_note_edit(state)
}

// Check pending and active batches against the bounded replay capacity.
settings_save_collection_mutation_has_capacity :: proc(
    runtime: ^preferencesmodel.Settings_Save_Runtime) -> bool {
    if runtime == nil || runtime^.settings_store == nil {
        return runtime != nil
    }
    in_flight_mutation_count := 0
    if runtime^.settings_save_active {
        in_flight_mutation_count = runtime^.settings_save_payload.mutation_count
    }
    return runtime^.collection_mutation_count + in_flight_mutation_count <
        collections.MUTATION_CAPACITY
}

// Restore failed operations ahead of edits accepted during the worker transaction.
settings_save_requeue_mutations :: proc(state: ^core.Euclid_General_State) {
    runtime := &state^.preferences_runtime
    failed := &runtime^.settings_save_payload
    pending_count := runtime^.collection_mutation_count
    for index := pending_count; index > 0; index -= 1 {
        runtime^.collection_mutations[index + failed.mutation_count - 1] =
            runtime^.collection_mutations[index - 1]
    }
    for index in 0..<failed.mutation_count {
        runtime^.collection_mutations[index] = failed.mutations[index]
    }
    runtime^.collection_mutation_count += failed.mutation_count
}

// Poll and join a completed save before its fixed payload can be reused.
settings_save_poll :: proc(
    state: ^core.Euclid_General_State,
    pool: ^taskpool.Task_Pool) {
    runtime := &state^.preferences_runtime
    if !runtime^.settings_save_active {
        return
    }
    poll := taskpool.task_pool_poll(pool, runtime^.settings_save_handle)
    if poll == .Pending {
        return
    }
    if poll == .Stale_Handle {
        log.error("settings_save_handle_stale")
        state^.ui_runtime.preferences.save_status = .Failed
        return
    }
    result, joined := taskpool.task_pool_wait(pool, runtime^.settings_save_handle)
    if joined != .Joined {
        log.error("settings_save_join_failed")
        state^.ui_runtime.preferences.save_status = .Failed
        return
    }
    runtime^.settings_save_active = false
    settings_save_apply_result(state, result)
    if !viewuserdata.connection_admission_release_joined(
        &state^.user_data_admission, .Settings_Save) {
        log.error("settings_save_admission_release_failed")
        state^.ui_runtime.preferences.save_status = .Failed
    }
}

// Update visible status and bounded retry state for one joined result.
settings_save_apply_result :: proc(
    state: ^core.Euclid_General_State,
    task_result: taskpool.Task_Result) {
    runtime := &state^.preferences_runtime
    if runtime^.settings_save_payload.kind != .User_Data_Batch {
        settings_save_apply_note_result(state, task_result)
        return
    }
    committed := task_result == .Succeeded &&
        runtime^.settings_save_payload.result.outcome == .Committed
    settings_save_record_result(state, committed)
    if committed {
        settings_save_apply_committed_result(state, runtime)
        return
    }
    settings_save_apply_failed_result(state, runtime)
}

// Publish a joined placement-note read or save only to its matching owner.
settings_save_apply_note_result :: proc(
    state: ^core.Euclid_General_State,
    task_result: taskpool.Task_Result) {
    runtime := &state^.preferences_runtime
    task := &runtime^.settings_save_payload
    note := &state^.ui_runtime.library.collection_note
    current := settings_save_note_owner_matches(state, task, note)
    if task^.kind == .Collection_Note_Read {
        settings_save_apply_note_read(state, task, note, current, task_result)
        return
    }
    committed := task_result == .Succeeded &&
        task^.result.outcome == .Committed
    if !committed {
        settings_save_note_record_failure(state, task, note, current)
        return
    }
    if current {
        settings_save_note_acknowledge_revision(note, task^.note_revision)
    }
    if runtime^.note_failure_unresolved &&
        task^.note_revision >= runtime^.note_failure_revision {
        runtime^.note_failure_unresolved = false
        runtime^.note_failure_revision = 0
    }
    if !runtime^.note_failure_unresolved &&
        state^.ui_runtime.preferences.save_status == .Saving {
        state^.ui_runtime.preferences.save_status =
            .Saved if !settings_save_has_pending(runtime) else .Pending
    }
}

// Retire editing only when the committed snapshot covers the live note revision.
settings_save_note_acknowledge_revision :: proc(
    note: ^viewmodel.Ui_Library_Collection_Note, revision: u64) {
    note^.saved_revision = max(note^.saved_revision, revision)
    if note^.revision > revision {
        return
    }
    note^.dirty = false
    note^.save_failed = false
    if note^.leave_editing_after_save {
        note^.editing = false
        note^.edit_requested = false
        note^.leave_editing_after_save = false
    }
}

// Reject stale worker output before allocating or publishing active note bytes.
settings_save_apply_note_read :: proc(
    state: ^core.Euclid_General_State,
    task: ^preferencesmodel.Settings_Save_Task_Payload,
    note: ^viewmodel.Ui_Library_Collection_Note,
    current: bool,
    task_result: taskpool.Task_Result) {
    if !current {
        return
    }
    if task_result != .Succeeded ||
        !user_data.store_error_is_clear(task^.note_failure) {
        note^.status = .Failed
        log.errorf("collection_note_load_failed error=%d sqlite_result=%d",
            int(task^.note_failure.kind), int(task^.note_failure.sqlite_error.result))
        return
    }
    buffer, available := animation_model.animation_memory_note_buffer(
        &state^.animation_memory)
    if !available {
        note^.status = .Failed
        log.error("collection_note_buffer_allocation_failed")
        return
    }
    text_length := task^.note_read_result.text_length if
        task^.note_read_result.found else 0
    copy(buffer[:text_length], task^.note_text[:text_length])
    note^.text_length = text_length
    note^.notes_on_top = task^.note_read_result.notes_on_top
    note^.status = .Ready
    if note^.edit_requested {
        note^.editing = true
        note^.edit_requested = false
    }
}

// Retain failure feedback while blocking only a failure that covers the live revision.
settings_save_note_record_failure :: proc(
    state: ^core.Euclid_General_State,
    task: ^preferencesmodel.Settings_Save_Task_Payload,
    note: ^viewmodel.Ui_Library_Collection_Note,
    current: bool) {
    runtime := &state^.preferences_runtime
    runtime^.note_failure_unresolved = true
    runtime^.note_failure_revision = max(
        runtime^.note_failure_revision, task^.note_revision)
    if current {
        note^.dirty = true
        if settings_save_note_failure_covers_current_revision(
            note^.revision, task^.note_revision) {
            note^.save_failed = true
        }
    }
    state^.ui_runtime.preferences.save_status = .Failed
    log.errorf("collection_note_save_failed revision=%d error=%d sqlite_result=%d",
        task^.note_revision, int(task^.note_failure.kind),
        int(task^.note_failure.sqlite_error.result))
}

// Only a failure at or beyond the live revision can block its retry.
settings_save_note_failure_covers_current_revision :: proc(
    current_revision, failed_revision: u64) -> bool {
    return current_revision <= failed_revision
}

// Match placement, request, and animation generation before consuming note results.
settings_save_note_owner_matches :: proc(
    state: ^core.Euclid_General_State,
    task: ^preferencesmodel.Settings_Save_Task_Payload,
    note: ^viewmodel.Ui_Library_Collection_Note) -> bool {
    return state^.animation_memory.generation == task^.note_generation &&
        note^.generation == task^.note_generation &&
        note^.request_id == task^.note_request_id &&
        note^.identity.collection_id == task^.note_identity.collection_id &&
        note^.identity.entry_id == task^.note_identity.entry_id &&
        note^.identity.parent_entry_id == task^.note_identity.parent_entry_id
}

// Publish aggregate status after a committed batch resolves covered errors.
settings_save_apply_committed_result :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^preferencesmodel.Settings_Save_Runtime) {
    settings_save_resolve_failure(runtime)
    if runtime^.user_data_failure_unresolved || runtime^.note_failure_unresolved {
        state^.ui_runtime.preferences.save_status = .Failed
        return
    }
    state^.ui_runtime.preferences.save_status =
        .Saved if !settings_save_has_pending(runtime) else .Pending
}

// Retain and report a failed transaction before its bounded retry policy.
settings_save_apply_failed_result :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^preferencesmodel.Settings_Save_Runtime) {
    settings_save_requeue(state, runtime^.settings_save_payload.changes)
    settings_save_requeue_mutations(state)
    failure := runtime^.settings_save_payload.result.failure
    settings_save_remember_failure(
        runtime, runtime^.settings_save_payload.user_data_revision, failure)
    status := settings_save_failure_status(
        failure.kind, runtime^.settings_failure_count)
    state^.ui_runtime.preferences.save_status = status
    if status == .Unavailable {
        settings_save_log_failure(
            "user_data_save_unavailable", runtime^.settings_failure_count, failure)
        return
    }
    if status == .Failed {
        settings_save_log_failure(
            "user_data_save_retry_exhausted", runtime^.settings_failure_count, failure)
        return
    }
    runtime^.settings_retry_frames = SETTINGS_SAVE_RETRY_DELAY_FRAMES
    settings_save_log_failure(
        "user_data_save_retry_scheduled", runtime^.settings_failure_count, failure)
}

// Retain only the newest unresolved transaction failure.
settings_save_remember_failure :: proc(
    runtime: ^preferencesmodel.Settings_Save_Runtime,
    revision: u64,
    failure: user_data.Store_Error) {
    if !runtime^.user_data_failure_unresolved ||
        revision >= runtime^.user_data_failure_revision {
        runtime^.user_data_failure = failure
        runtime^.user_data_failure_revision = revision
        runtime^.user_data_failure_unresolved = true
    }
}

// Resolve an error only when a committed batch covers its failed revision.
settings_save_resolve_failure :: proc(
    runtime: ^preferencesmodel.Settings_Save_Runtime) {
    if runtime^.user_data_failure_unresolved &&
        runtime^.settings_save_payload.user_data_revision <
            runtime^.user_data_failure_revision {
        return
    }
    runtime^.user_data_failure = {}
    runtime^.user_data_failure_revision = 0
    runtime^.user_data_failure_unresolved = false
    runtime^.settings_failure_count = 0
    runtime^.settings_retry_frames = 0
}

// Log structured SQLite and store error details without discarding them from state.
settings_save_log_failure :: proc(
    event: string, attempt: int, failure: user_data.Store_Error) {
    if event == "user_data_save_retry_scheduled" {
        log.warnf(
            "%s attempt=%d error=%d sqlite_operation=%d sqlite_result=%d sqlite_extended=%d sqlite_validation=%d cleanup_result=%d",
            event, attempt, int(failure.kind),
            int(failure.sqlite_error.operation), int(failure.sqlite_error.result),
            int(failure.sqlite_error.extended_result),
            int(failure.sqlite_error.validation), int(failure.cleanup_error.result))
        return
    }
    log.errorf(
        "%s attempt=%d error=%d sqlite_operation=%d sqlite_result=%d sqlite_extended=%d sqlite_validation=%d cleanup_result=%d",
        event, attempt, int(failure.kind),
        int(failure.sqlite_error.operation), int(failure.sqlite_error.result),
        int(failure.sqlite_error.extended_result),
        int(failure.sqlite_error.validation), int(failure.cleanup_error.result))
}

// Map one commit failure and attempt count to its durable UI state.
settings_save_failure_status :: proc(
    failure: user_data.Store_Error_Kind,
    attempts: int) -> preferencesmodel.Settings_Save_Status {
    if failure == .Unusable || failure == .Closed || failure == .Not_Writable ||
        failure == .Invalid_Batch {
        return .Unavailable
    }
    return .Failed if attempts >= SETTINGS_SAVE_MAX_ATTEMPTS else .Pending
}

// Requeue failed values while newer pending edits retain precedence.
settings_save_requeue :: proc(
    state: ^core.Euclid_General_State, failed: setting_model.Change_Set) {
    merged := failed
    pending := state^.preferences_runtime.settings_pending
    for change in pending.changes[:pending.count] {
        if change.kind == .Set {
            _ = setting_model.change_set_set(&merged, change.id, change.value)
        } else {
            _ = setting_model.change_set_reset(&merged, change.id)
        }
    }
    state^.preferences_runtime.settings_pending = merged
}

// Submit one pending batch without allowing owner-help execution of its SQLite IO.
settings_save_service :: proc(
    state: ^core.Euclid_General_State,
    pool: ^taskpool.Task_Pool, history_ready: bool = false) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.preferences_runtime
    settings_save_poll(state, pool)
    if runtime^.settings_store == nil {
        state^.ui_runtime.preferences.save_status = .Unavailable
        return
    }
    if state^.ui_runtime.preferences.save_status == .Unavailable ||
        state^.ui_runtime.preferences.save_status == .Failed {
        return
    }
    sharing := &state^.ui_runtime.sharing
    if sharing.exchange_task_active || sharing.collection_edit_locked {
        return
    }
    if runtime^.settings_save_active || !settings_save_has_pending(runtime) {
        return
    }
    if runtime^.settings_retry_frames > 0 {
        runtime^.settings_retry_frames -= 1
        return
    }
    settings_save_submit(state, pool, false, history_ready)
}

// Preserve pending edits when the shared pool cannot admit save work.
settings_save_submit :: proc(
    state: ^core.Euclid_General_State,
    pool: ^taskpool.Task_Pool,
    drain_work: bool = false,
    history_ready: bool = false) {
    sharing := &state^.ui_runtime.sharing
    if sharing.exchange_task_active || sharing.collection_edit_locked {
        return
    }
    admission := &state^.user_data_admission
    if !viewuserdata.connection_admission_claim(
        admission, .Settings_Save, history_ready, drain_work) {
        return
    }
    if !settings_save_prepare_payload(state) {
        if !viewuserdata.connection_admission_release_rejected(
            admission, .Settings_Save) {
            log.error("settings_save_invalid_payload_admission_release_failed")
        }
        return
    }
    settings_save_submit_claimed(state, pool)
}

// Snapshot pending edits into the stable payload before task-pool admission.
settings_save_prepare_payload :: proc(state: ^core.Euclid_General_State) -> bool {
    runtime := &state^.preferences_runtime
    if runtime^.note_request_kind == .None {
        runtime^.settings_save_payload = {
            kind = .User_Data_Batch,
            store = runtime^.settings_store,
            changes = runtime^.settings_pending,
            mutations = runtime^.collection_mutations,
            mutation_count = runtime^.collection_mutation_count,
            user_data_revision = runtime^.user_data_revision,
            owner_thread_id = sync.current_thread_id(),
        }
        return true
    }
    return settings_save_prepare_note_payload(state)
}

// Snapshot the current placement read or write into its stable worker payload.
settings_save_prepare_note_payload :: proc(
    state: ^core.Euclid_General_State) -> bool {
    runtime := &state^.preferences_runtime
    note := &state^.ui_runtime.library.collection_note
    if runtime^.note_identity != note^.identity ||
        runtime^.note_request_id != note^.request_id ||
        runtime^.note_generation != note^.generation {
        log.error("collection_note_request_lost_owner")
        runtime^.note_request_kind = .None
        return false
    }
    task_kind := preferencesmodel.Settings_Save_Task_Kind.Collection_Note_Write
    if runtime^.note_request_kind == .Read {
        task_kind = .Collection_Note_Read
    }
    payload := &runtime^.settings_save_payload
    payload^ = {}
    payload^.kind = task_kind
    payload^.store = runtime^.settings_store
    payload^.user_data_revision = runtime^.user_data_revision
    payload^.note_identity = runtime^.note_identity
    payload^.note_request_id = runtime^.note_request_id
    payload^.note_generation = runtime^.note_generation
    payload^.note_revision = runtime^.note_revision
    payload^.note_text_length = runtime^.note_text_length
    payload^.note_notes_on_top = runtime^.note_notes_on_top
    payload^.owner_thread_id = sync.current_thread_id()
    if payload^.kind == .Collection_Note_Write {
        return settings_save_snapshot_note_bytes(state, payload)
    }
    return true
}

// Copy active-generation note bytes into the immutable worker-owned save snapshot.
settings_save_snapshot_note_bytes :: proc(
    state: ^core.Euclid_General_State,
    payload: ^preferencesmodel.Settings_Save_Task_Payload) -> bool {
    buffer, available := animation_model.animation_memory_note_buffer(
        &state^.animation_memory)
    if !available || payload^.note_text_length < 0 ||
        payload^.note_text_length > len(buffer) {
        log.error("collection_note_save_buffer_unavailable")
        return false
    }
    copy(payload^.note_text[:payload^.note_text_length],
        buffer[:payload^.note_text_length])
    return true
}
// Submit a previously claimed immutable batch and release admission on rejection.
settings_save_submit_claimed :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) {
    runtime := &state^.preferences_runtime
    admission := &state^.user_data_admission
    handle, outcome := taskpool.task_pool_submit(
        pool, settings_save_worker, &runtime^.settings_save_payload, .Worker_Only)
    if outcome != .Queued {
        if !viewuserdata.connection_admission_release_rejected(
            admission, .Settings_Save) {
            log.error("settings_save_rejected_admission_release_failed")
        }
        state^.ui_runtime.preferences.save_status = .Pending
        return
    }
    if !viewuserdata.connection_admission_mark_submitted(admission, .Settings_Save) {
        log.error("settings_save_admission_submit_transition_failed")
    }
    runtime^.settings_save_handle = handle
    runtime^.settings_save_active = true
    settings_save_publish_submission(state)
}

// Publish the accepted immutable batch and its existing durable-save status.
settings_save_publish_submission :: proc(state: ^core.Euclid_General_State) {
    runtime := &state^.preferences_runtime
    if runtime^.settings_save_payload.kind == .User_Data_Batch {
        runtime^.settings_failure_count += 1
        runtime^.settings_pending = {}
        runtime^.collection_mutation_count = 0
        state^.ui_runtime.preferences.save_status = .Saving
        settings_save_record_event(state, .Settings_Save_Submitted)
    } else {
        runtime^.note_request_kind = .None
        if runtime^.settings_save_payload.kind == .Collection_Note_Write {
            state^.ui_runtime.preferences.save_status = .Saving
        }
    }
}

// Publish joined durability and executor evidence without reading a live worker payload.
settings_save_record_result :: proc(
    state: ^core.Euclid_General_State, committed: bool) {
    runtime := &state^.preferences_runtime
    task := &runtime^.settings_save_payload
    if task^.worker_thread_id != 0 &&
        task^.worker_thread_id == task^.owner_thread_id {
        runtime^.settings_save_owner_execution_count += 1
    }
    if committed {
        runtime^.settings_save_commit_count += 1
    } else {
        runtime^.settings_save_failure_count += 1
    }
    settings_save_record_event(state,
        .Settings_Save_Committed if committed else .Settings_Save_Failed)
}

// Record an accepted task identity, batch size, and joined error or owner-execution bit.
settings_save_record_event :: proc(
    state: ^core.Euclid_General_State, kind: evidence_trace.Kind) {
    runtime := &state^.preferences_runtime
    detail: u32
    flags: evidence_trace.Flags = {.Required}
    if kind == .Settings_Save_Failed {
        detail = u32(runtime^.settings_save_payload.result.failure.kind)
        flags += {.Failure}
    } else if kind == .Settings_Save_Committed {
        task := &runtime^.settings_save_payload
        detail = u32(task^.worker_thread_id == task^.owner_thread_id)
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = kind,
            flags = flags,
            correlation_kind = .Task,
            correlation = u64(runtime^.settings_save_handle.index + 1),
            generation = runtime^.settings_save_handle.generation,
            payload = {
                counts = {
                    u32(runtime^.settings_save_payload.changes.count +
                        runtime^.settings_save_payload.mutation_count),
                    detail,
                },
            },
        })
}

// Join accepted saves and make a bounded final flush before pool teardown.
settings_save_shutdown :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.preferences_runtime
    viewuserdata.connection_admission_begin_drain(&state^.user_data_admission)
    if runtime^.note_request_kind == .Read {
        runtime^.note_request_kind = .None
    }
    _ = settings_save_collection_note_queue_write(state)
    for {
        if runtime^.settings_save_active &&
           !settings_save_shutdown_join_active(state, pool) {
            return
        }
        if !settings_save_has_pending(runtime) {
            return
        }
        if !settings_save_shutdown_can_retry(state, runtime) {
            return
        }
        runtime^.settings_retry_frames = 0
        settings_save_submit(state, pool, true)
        if !runtime^.settings_save_active {
            log.error("settings_save_shutdown_admission_failed")
            state^.ui_runtime.preferences.save_status = .Failed
            return
        }
    }
}

// Advance one save-drain step while allowing the other connection borrower to finish.
settings_save_shutdown_step :: proc(
    state: ^core.Euclid_General_State,
    pool: ^taskpool.Task_Pool,
    history_ready: bool) -> bool {
    if state == nil || pool == nil {
        return true
    }
    runtime := &state^.preferences_runtime
    if runtime^.note_request_kind == .Read {
        runtime^.note_request_kind = .None
    }
    _ = settings_save_collection_note_queue_write(state)
    if runtime^.settings_save_active {
        if !settings_save_shutdown_join_active(state, pool) {
            return false
        }
    }
    if !settings_save_has_pending(runtime) ||
       !settings_save_shutdown_can_retry(state, runtime) {
        return true
    }
    runtime^.settings_retry_frames = 0
    settings_save_submit(state, pool, true, history_ready)
    return false
}

// Join, consume, and release the connection for one shutdown-owned save task.
settings_save_shutdown_join_active :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) -> bool {
    runtime := &state^.preferences_runtime
    result, joined := taskpool.task_pool_wait(pool, runtime^.settings_save_handle)
    if joined != .Joined {
        log.error("settings_save_shutdown_join_failed")
        state^.ui_runtime.preferences.save_status = .Failed
        return false
    }
    runtime^.settings_save_active = false
    settings_save_apply_result(state, result)
    if !viewuserdata.connection_admission_release_joined(
        &state^.user_data_admission, .Settings_Save) {
        log.error("settings_save_shutdown_admission_release_failed")
        state^.ui_runtime.preferences.save_status = .Failed
        return false
    }
    return true
}

// Continue shutdown retries only while durable settings remain eligible to save.
settings_save_shutdown_can_retry :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^preferencesmodel.Settings_Save_Runtime) -> bool {
    return runtime^.settings_store != nil &&
        state^.ui_runtime.preferences.save_status != .Unavailable &&
        state^.ui_runtime.preferences.save_status != .Failed
}
