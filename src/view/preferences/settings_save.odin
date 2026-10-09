package viewpreferences

import taskpool "../../taskpool"
import setting_model "../../settings"
import user_data "../../userdata"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import log "core:log"
import sync "core:sync"
import preferencesmodel "model"
import core "../../core"
import collections "../../collections"

SETTINGS_SAVE_MAX_ATTEMPTS :: 3
SETTINGS_SAVE_RETRY_DELAY_FRAMES :: 60

// Commit one immutable preference payload on a shared worker.
settings_save_worker :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    _ = token
    task := cast(^preferencesmodel.Settings_Save_Task_Payload)payload
    task^.worker_thread_id = sync.current_thread_id()
    task^.result = user_data.store_commit_user_data(
        task^.store, task^.changes, task^.mutations[:task^.mutation_count])
    return .Succeeded if task^.result.outcome == .Committed else .Failed
}

// Treat settings and collection edits as one outstanding persistence batch.
settings_save_has_pending :: proc(
    runtime: ^preferencesmodel.Settings_Save_Runtime) -> bool {
    return runtime^.settings_pending.count > 0 ||
        runtime^.collection_mutation_count > 0
}

// Record an accepted user-data edit and preserve unresolved failure context.
settings_save_note_edit :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    runtime := &state^.preferences_runtime
    runtime^.user_data_revision += 1
    if runtime^.settings_store == nil {
        state^.ui_runtime.settings_save_status = .Unavailable
        return
    }
    if runtime^.settings_save_active {
        state^.ui_runtime.settings_save_status = .Saving
        return
    }
    if runtime^.user_data_failure_unresolved {
        state^.ui_runtime.settings_save_status = .Pending
        return
    }
    if state^.ui_runtime.settings_save_status == .Unavailable ||
        state^.ui_runtime.settings_save_status == .Failed {
        runtime^.settings_failure_count = 0
        runtime^.settings_retry_frames = 0
    }
    state^.ui_runtime.settings_save_status = .Pending
}

// Accept one in-memory Favorites edit and retain it for ordered durable replay.
settings_save_collection_mutation :: proc(
    state: ^core.Euclid_General_State,
    mutation: collections.Mutation) -> collections.Mutation_Error {
    if state == nil {
        return .Invalid_Entry
    }
    runtime := &state^.preferences_runtime
    staged := runtime^.collections_state
    mutation_error := collections.apply_mutation(&staged, mutation)
    if mutation_error != .None {
        return mutation_error
    }
    if runtime^.settings_store != nil &&
        runtime^.collection_mutation_count +
            runtime^.settings_save_payload.mutation_count >=
                collections.MUTATION_CAPACITY {
        return .Capacity
    }
    runtime^.collections_state = staged
    runtime^.collection_revision += 1
    if runtime^.settings_store != nil {
        runtime^.collection_mutations[runtime^.collection_mutation_count] = mutation
        runtime^.collection_mutation_count += 1
    }
    settings_save_note_edit(state)
    return .None
}

// Restore failed operations ahead of edits accepted during the worker transaction.
settings_save_requeue_mutations :: proc(state: ^core.Euclid_General_State) {
    runtime := &state^.preferences_runtime
    failed := runtime^.settings_save_payload
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
        state^.ui_runtime.settings_save_status = .Failed
        return
    }
    result, joined := taskpool.task_pool_wait(pool, runtime^.settings_save_handle)
    if joined != .Joined {
        log.error("settings_save_join_failed")
        state^.ui_runtime.settings_save_status = .Failed
        runtime^.settings_save_active = false
        return
    }
    runtime^.settings_save_active = false
    settings_save_apply_result(state, result)
}

// Update visible status and bounded retry state for one joined result.
settings_save_apply_result :: proc(
    state: ^core.Euclid_General_State,
    task_result: taskpool.Task_Result) {
    runtime := &state^.preferences_runtime
    committed := task_result == .Succeeded &&
        runtime^.settings_save_payload.result.outcome == .Committed
    settings_save_record_result(state, committed)
    if committed {
        settings_save_apply_committed_result(state, runtime)
        return
    }
    settings_save_apply_failed_result(state, runtime)
}

// Publish aggregate status after a committed batch resolves covered errors.
settings_save_apply_committed_result :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^preferencesmodel.Settings_Save_Runtime) {
    settings_save_resolve_failure(runtime)
    if runtime^.user_data_failure_unresolved {
        state^.ui_runtime.settings_save_status = .Failed
        return
    }
    state^.ui_runtime.settings_save_status =
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
    state^.ui_runtime.settings_save_status = status
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
    pool: ^taskpool.Task_Pool) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.preferences_runtime
    settings_save_poll(state, pool)
    if runtime^.settings_store == nil {
        state^.ui_runtime.settings_save_status = .Unavailable
        return
    }
    if state^.ui_runtime.settings_save_status == .Unavailable ||
        state^.ui_runtime.settings_save_status == .Failed {
        return
    }
    if runtime^.settings_save_active || !settings_save_has_pending(runtime) {
        return
    }
    if runtime^.settings_retry_frames > 0 {
        runtime^.settings_retry_frames -= 1
        return
    }
    settings_save_submit(state, pool)
}

// Preserve pending edits when the shared pool cannot admit save work.
settings_save_submit :: proc(
    state: ^core.Euclid_General_State,
    pool: ^taskpool.Task_Pool) {
    runtime := &state^.preferences_runtime
    runtime^.settings_save_payload = {
        store = runtime^.settings_store,
        changes = state^.preferences_runtime.settings_pending,
        mutations = state^.preferences_runtime.collection_mutations,
        mutation_count = state^.preferences_runtime.collection_mutation_count,
        user_data_revision = runtime^.user_data_revision,
        owner_thread_id = sync.current_thread_id(),
    }
    handle, outcome := taskpool.task_pool_submit(
        pool, settings_save_worker, &runtime^.settings_save_payload, .Worker_Only)
    if outcome != .Queued {
        state^.ui_runtime.settings_save_status = .Pending
        return
    }
    runtime^.settings_save_handle = handle
    runtime^.settings_save_active = true
    runtime^.settings_failure_count += 1
    state^.preferences_runtime.settings_pending = {}
    state^.preferences_runtime.collection_mutation_count = 0
    state^.ui_runtime.settings_save_status = .Saving
    settings_save_record_event(state, .Settings_Save_Submitted)
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
            lane = .Domain, kind = kind, flags = flags,
            correlation_kind = .Task,
            correlation = u64(runtime^.settings_save_handle.index + 1),
            generation = runtime^.settings_save_handle.generation,
            payload = {counts = {
                u32(runtime^.settings_save_payload.changes.count +
                    runtime^.settings_save_payload.mutation_count), detail}},
        })
}

// Join accepted saves and make a bounded final flush before pool teardown.
settings_save_shutdown :: proc(
    state: ^core.Euclid_General_State, pool: ^taskpool.Task_Pool) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.preferences_runtime
    for {
        if runtime^.settings_save_active {
            result, joined := taskpool.task_pool_wait(
                pool, runtime^.settings_save_handle)
            if joined != .Joined {
                log.error("settings_save_shutdown_join_failed")
                state^.ui_runtime.settings_save_status = .Failed
                return
            }
            runtime^.settings_save_active = false
            settings_save_apply_result(state, result)
        }
        if !settings_save_has_pending(runtime) {
            return
        }
        if runtime^.settings_store == nil ||
            state^.ui_runtime.settings_save_status == .Unavailable ||
            state^.ui_runtime.settings_save_status == .Failed {
            return
        }
        runtime^.settings_retry_frames = 0
        settings_save_submit(state, pool)
        if !runtime^.settings_save_active {
            log.error("settings_save_shutdown_admission_failed")
            state^.ui_runtime.settings_save_status = .Failed
            return
        }
    }
}
