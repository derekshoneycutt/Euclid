package view

import taskpool "../taskpool"
import setting_model "../settings"
import user_data "../userdata"
import viewmodel "model"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"

import "core:log"
import "core:sync"

SETTINGS_SAVE_MAX_ATTEMPTS :: 3
SETTINGS_SAVE_RETRY_DELAY_FRAMES :: 60

// Commit one immutable preference payload on a shared worker.
settings_save_worker :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    _ = token
    task := cast(^viewmodel.Settings_Save_Task_Payload)payload
    task^.worker_thread_id = sync.current_thread_id()
    task^.result = user_data.store_commit_batch(task^.store, task^.changes)
    return .Succeeded if task^.result.outcome == .Committed else .Failed
}

// Poll and join a completed save before its fixed payload can be reused.
settings_save_poll :: proc(
    state: ^Euclid_General_State,
    pool: ^taskpool.Task_Pool) {
    runtime := &state^.ui_runtime
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
    state: ^Euclid_General_State,
    task_result: taskpool.Task_Result) {
    runtime := &state^.ui_runtime
    committed := task_result == .Succeeded &&
        runtime^.settings_save_payload.result.outcome == .Committed
    settings_save_record_result(state, committed)
    if committed {
        runtime^.settings_failure_count = 0
        runtime^.settings_retry_frames = 0
        runtime^.settings_save_status =
            .Saved if runtime^.settings_pending.count == 0 else .Pending
        return
    }
    settings_save_requeue(state, runtime^.settings_save_payload.changes)
    failure := runtime^.settings_save_payload.result.failure.kind
    status := settings_save_failure_status(failure, runtime^.settings_failure_count)
    state^.ui_runtime.settings_save_status = status
    if status == .Unavailable {
        log.errorf("settings_save_permanent_failure error=%d", int(failure))
        return
    }
    if status == .Failed {
        log.errorf("settings_save_retry_exhausted error=%d", int(failure))
        return
    }
    runtime^.settings_retry_frames = SETTINGS_SAVE_RETRY_DELAY_FRAMES
    log.warnf("settings_save_retry_scheduled attempt=%d error=%d",
        runtime^.settings_failure_count, int(failure))
}

// Map one commit failure and attempt count to its durable UI state.
settings_save_failure_status :: proc(
    failure: user_data.Store_Error_Kind,
    attempts: int) -> viewmodel.Settings_Save_Status {
    if failure == .Unusable || failure == .Closed || failure == .Not_Writable ||
        failure == .Invalid_Batch {
        return .Unavailable
    }
    return .Failed if attempts >= SETTINGS_SAVE_MAX_ATTEMPTS else .Pending
}

// Requeue failed values while newer pending edits retain precedence.
settings_save_requeue :: proc(
    state: ^Euclid_General_State, failed: setting_model.Change_Set) {
    merged := failed
    pending := state^.ui_runtime.settings_pending
    for change in pending.changes[:pending.count] {
        if change.kind == .Set {
            _ = setting_model.change_set_set(&merged, change.id, change.value)
        } else {
            _ = setting_model.change_set_reset(&merged, change.id)
        }
    }
    state^.ui_runtime.settings_pending = merged
}

// Submit one pending batch without allowing owner-help execution of its SQLite IO.
settings_save_service :: proc(
    state: ^Euclid_General_State,
    pool: ^taskpool.Task_Pool) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.ui_runtime
    settings_save_poll(state, pool)
    if runtime^.settings_store == nil {
        state^.ui_runtime.settings_save_status = .Unavailable
        return
    }
    if runtime^.settings_save_status == .Unavailable ||
        runtime^.settings_save_status == .Failed {
        return
    }
    if runtime^.settings_save_active || runtime^.settings_pending.count == 0 {
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
    state: ^Euclid_General_State,
    pool: ^taskpool.Task_Pool) {
    runtime := &state^.ui_runtime
    runtime^.settings_save_payload = {
        store = runtime^.settings_store,
        changes = state^.ui_runtime.settings_pending,
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
    state^.ui_runtime.settings_pending = {}
    state^.ui_runtime.settings_save_status = .Saving
    settings_save_record_event(state, .Settings_Save_Submitted)
}

// Publish joined durability and executor evidence without reading a live worker payload.
settings_save_record_result :: proc(state: ^Euclid_General_State, committed: bool) {
    runtime := &state^.ui_runtime
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
    state: ^Euclid_General_State, kind: evidence_trace.Kind) {
    runtime := &state^.ui_runtime
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
                u32(runtime^.settings_save_payload.changes.count), detail}},
        })
}

// Join accepted saves and make a bounded final flush before pool teardown.
settings_save_shutdown :: proc(
    state: ^Euclid_General_State, pool: ^taskpool.Task_Pool) {
    if state == nil || pool == nil {
        return
    }
    runtime := &state^.ui_runtime
    for {
        if runtime^.settings_save_active {
            result, joined := taskpool.task_pool_wait(
                pool, runtime^.settings_save_handle)
            if joined != .Joined {
                log.error("settings_save_shutdown_join_failed")
                runtime^.settings_save_status = .Failed
                return
            }
            runtime^.settings_save_active = false
            settings_save_apply_result(state, result)
        }
        if runtime^.settings_pending.count == 0 {
            return
        }
        if runtime^.settings_store == nil ||
            runtime^.settings_save_status == .Unavailable ||
            runtime^.settings_save_status == .Failed {
            return
        }
        runtime^.settings_retry_frames = 0
        settings_save_submit(state, pool)
        if !runtime^.settings_save_active {
            log.error("settings_save_shutdown_admission_failed")
            runtime^.settings_save_status = .Failed
            return
        }
    }
}
