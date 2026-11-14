package view

import bridgemodel "../bridge/model"
import core "../core"
import contentdata "../core/content"
import exerciseheader "../core/exercise_header"
import userdata "../persistence/userdata"
import viewcontent "content"
import viewpreferences "preferences"

import "core:log"
import "core:sync"
import uuid "core:encoding/uuid"

// Admit an egress intent at the display boundary without touching the current attempt.
admit_exercise_query :: proc(
    state: ^core.Euclid_General_State, intent: bridgemodel.Exercise_Query_Intent) {
    operation := &state.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Queued || operation.intent.token != intent.token {
        return
    }
    operation.index_generation = viewcontent.content_service_index_generation(
        state.content_service)
    if !exercise_query_intent_current(state, operation) {
        finish_exercise_query(operation, .Superseded)
    } else {
        operation.state = .Admitted
        submit_admitted_exercise_query(state, operation)
    }
}

// Admit one user exercise intent into the existing joined user-store worker lane.
admit_user_exercise_operation :: proc(
    state: ^core.Euclid_General_State, intent: bridgemodel.User_Exercise_Intent) {
    operation := &state^.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Queued ||
       operation.intent.request_id != intent.request_id {
        return
    }
    outcome := viewpreferences.settings_save_user_exercise_request(
        state, operation.task)
    switch outcome {
    case .Accepted:
        operation.state = .Waiting
    case .Invalid_Request:
        finish_user_exercise_operation(
            operation, .Invalid_Request, operation.task)
    case .Busy:
        finish_user_exercise_operation(operation, .Busy, operation.task)
    case .Unavailable:
        finish_user_exercise_operation(operation, .Unavailable, operation.task)
    }
}

// Complete a user operation only after the joined persistence task is consumed.
service_user_exercise_operations :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_runtime_service == nil {
        return
    }
    operation := &state^.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if state^.preferences_runtime.user_exercise_request_state != .Complete {
        return
    }
    task, received := viewpreferences.settings_save_user_exercise_take_result(state)
    if !received {
        return
    }
    if operation.state != .Waiting {
        return
    }
    status := user_exercise_status_from_store_error(task.failure)
    if task.request_id != operation.intent.request_id {
        log.error("user_exercise_result_identity_mismatch")
        status = .Invalid_Request
    }
    if status == .Ready {
        user_exercise_mark_association_availability(state, operation, &task)
    }
    if status == .Ready && operation.intent.load {
        status = user_exercise_load_result(state, operation, &task)
    }
    finish_user_exercise_operation(operation, status, task)
}

// Report deleted or unavailable animation links without mutating stored records.
user_exercise_mark_association_availability :: proc(
    state: ^core.Euclid_General_State,
    operation: ^bridgemodel.User_Exercise_Operation,
    task: ^userdata.User_Exercise_Task) {
    operation^.animation_available = false
    operation^.page_animation_available = {}
    if task^.operation == .List {
        for index in 0..<int(task^.page.returned_count) {
            operation^.page_animation_available[index] =
                user_exercise_animation_exists(
                    state, task^.page.exercises[index].animation_id)
        }
        return
    }
    if task^.operation != .Delete {
        operation^.animation_available =
            user_exercise_animation_exists(state, task^.result.animation_id)
    }
}

// Publish loaded instructions only while their animation and header request remain current.
user_exercise_load_result :: proc(
    state: ^core.Euclid_General_State,
    operation: ^bridgemodel.User_Exercise_Operation,
    task: ^userdata.User_Exercise_Task) -> bridgemodel.User_Exercise_Result_Status {
    intent := &operation.intent
    if !user_exercise_load_is_current(state, intent) {
        return .Superseded
    }
    if !user_exercise_animation_exists(state, task^.result.animation_id) {
        return .Missing_Animation
    }
    text := task^.result.instructions[:task^.result.instructions_length]
    if !exercise_header_commit_load(
        state, intent.animation_generation, intent.header_request_id, text) {
        log.error("user_exercise_header_publication_failed")
        return .Database_Failed
    }
    return .Ready
}

// Reject a load after runtime replacement, hide, or a newer header request.
user_exercise_load_is_current :: proc(
    state: ^core.Euclid_General_State,
    intent: ^bridgemodel.User_Exercise_Intent) -> bool {
    service := state^.julia_runtime_service
    return state^.terminal.initialized &&
        service^.animation_generation == intent^.animation_generation &&
        intent^.header_request_id > state^.exercise_header.last_request_id &&
        intent^.header_request_id == bridgemodel.exercise_header_request_latest(
            &service^.exercise_header_request_sequence)
}

// Check the stored association against the active immutable content generation.
user_exercise_animation_exists :: proc(
    state: ^core.Euclid_General_State, animation_id: uuid.Identifier) -> bool {
    generation := viewcontent.content_service_generation(state^.content_service)
    buffer: [contentdata.EXERCISE_UUID_BYTE_COUNT]u8
    identity := uuid.to_string(animation_id, buffer[:])
    return contentdata.exercise_animation_exists(generation, identity)
}

// Copy one joined result and expose only a complete status/result pair.
finish_user_exercise_operation :: proc(
    operation: ^bridgemodel.User_Exercise_Operation,
    status: bridgemodel.User_Exercise_Result_Status,
    result: userdata.User_Exercise_Task) {
    operation.status = status
    operation.result = result
    operation.state = .Ready
}

// Convert persistence errors to stable, typed Julia-facing operation outcomes.
user_exercise_status_from_store_error :: proc(
    failure: userdata.Store_Error) -> bridgemodel.User_Exercise_Result_Status {
    switch failure.kind {
    case .None:
        return .Ready
    case .Not_Found, .Identity_Retired:
        return .Not_Found
    case .Reference_Retired:
        return .Retired
    case .Invalid_Exercise, .Invalid_Reference, .Invalid_State:
        return .Invalid_Request
    case .Reference_Collision:
        return .Reference_Collision
    case .Identity_Collision:
        return .Identity_Collision
    case .Not_Writable:
        return .Read_Only
    case .Closed, .Unusable, .Read, .Write, .Finalize, .Close:
        return .Database_Failed
    case .Invalid_Path, .Path_Resolution, .Directory, .Open,
         .Sqlite_Threading, .Wrong_Application, .Unsupported_Schema,
         .Future_Schema, .Invalid_Schema, .Schema, .Allocation,
         .Invalid_Batch:
        return .Database_Failed
    }
    return .Database_Failed
}

// Keep at most one worker request outstanding, even when newer loads supersede it.
submit_admitted_exercise_query :: proc(
    state: ^core.Euclid_General_State, operation: ^bridgemodel.Exercise_Operation) {
    if operation.inflight_token != 0 || operation.state != .Admitted {
        return
    }
    if !viewcontent.content_service_try_submit_exercise(
        state.content_service, operation.intent.query) {
        log.error("exercise_query_submission_failed")
        finish_exercise_query(operation, .Unavailable)
    } else {
        operation.inflight_token = operation.intent.token
        operation.state = .Waiting
    }
}

// Reject older loads after hide, newer show/load, navigation, reset, or content replacement.
exercise_query_intent_current :: proc(
    state: ^core.Euclid_General_State,
    operation: ^bridgemodel.Exercise_Operation) -> bool {
    service := state.julia_runtime_service
    intent := &operation.intent
    if !state.terminal.initialized ||
        intent.animation_generation != service.animation_generation ||
        operation.index_generation != viewcontent.content_service_index_generation(
            state.content_service) {
        return false
    }
    if !intent.load {
        return true
    }
    return intent.header_request_id > state.exercise_header.last_request_id &&
        intent.header_request_id == bridgemodel.exercise_header_request_latest(
            &service.exercise_header_request_sequence)
}

// Complete explicitly without exposing partial rows or retaining instruction borrowers.
finish_exercise_query :: proc(
    operation: ^bridgemodel.Exercise_Operation,
    status: contentdata.Exercise_Query_Status) {
    operation.result = {
        generation = operation.intent.token,
        status = status,
        kind = operation.intent.query.kind,
        index_generation = operation.index_generation,
    }
    operation.state = .Ready
}

// Drain replies every frame, including abandoned tokens, before accepting current work.
service_exercise_queries :: proc(state: ^core.Euclid_General_State) {
    if state.julia_runtime_service == nil {
        return
    }
    operation := &state.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if (operation.state == .Waiting || operation.state == .Admitted) &&
        !exercise_query_intent_current(state, operation) {
        finish_exercise_query(operation, .Superseded)
    }
    for {
        result, received := viewcontent.content_service_try_receive_exercise(
            state.content_service)
        if !received {
            break
        }
        if result.generation == operation.inflight_token {
            operation.inflight_token = 0
        }
        if operation.state == .Waiting && result.generation == operation.intent.token {
            accept_exercise_query_result(state, operation, &result)
        }
    }
    submit_admitted_exercise_query(state, operation)
}

// Resolve aliases first, then read the UUID through the same bounded content owner.
accept_exercise_query_result :: proc(
    state: ^core.Euclid_General_State, operation: ^bridgemodel.Exercise_Operation,
    result: ^contentdata.Exercise_Query_Result) {
    if result.index_generation != operation.index_generation ||
        !exercise_query_intent_current(state, operation) {
        finish_exercise_query(operation, .Superseded)
        return
    }
    if operation.intent.load && result.status == .Ready {
        if result.kind != .Read_Uuid {
            continue_exercise_load(state, operation, result)
            return
        }
        if !exercise_header_commit_load(
            state, operation.intent.animation_generation,
            operation.intent.header_request_id,
            result.instructions[:result.instructions_length]) {
            log.error("exercise_load_text_rejected")
            finish_exercise_query(operation, .Database_Failed)
            return
        }
    }
    operation.result = result^
    operation.state = .Ready
}

// Commit both built-in and user instruction snapshots through the same display buffer.
exercise_header_commit_load :: proc(
    state: ^core.Euclid_General_State, animation_generation, header_request_id: u64,
    text: []u8) -> bool {
    service := state^.julia_runtime_service
    if !state^.terminal.initialized ||
       service^.animation_generation != animation_generation ||
       header_request_id <= state^.exercise_header.last_request_id ||
       header_request_id != bridgemodel.exercise_header_request_latest(
            &service^.exercise_header_request_sequence) ||
       !exerciseheader.show(&state^.exercise_header, text) {
        return false
    }
    state^.exercise_header.last_request_id = header_request_id
    return true
}

// Keep the original load intent while replacing its worker phase with an exact UUID read.
continue_exercise_load :: proc(
    state: ^core.Euclid_General_State, operation: ^bridgemodel.Exercise_Operation,
    result: ^contentdata.Exercise_Query_Result) {
    identity := string(result.exercise.exercise_id[:result.exercise.exercise_id_length])
    query, valid := contentdata.exercise_query_request_make(
        operation.intent.token, .Read_Uuid, "", identity, {})
    if !valid || !viewcontent.content_service_try_submit_exercise(
        state.content_service, query) {
        log.error("exercise_load_read_submission_failed")
        finish_exercise_query(operation, .Unavailable)
    } else {
        operation.inflight_token = operation.intent.token
    }
}
