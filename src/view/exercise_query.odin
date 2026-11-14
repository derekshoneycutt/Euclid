package view

import bridgemodel "../bridge/model"
import core "../core"
import contentdata "../core/content"
import exerciseheader "../core/exercise_header"
import viewcontent "content"

import "core:log"
import "core:sync"

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
        if !exerciseheader.show(&state.exercise_header,
            result.instructions[:result.instructions_length]) {
            log.error("exercise_load_text_rejected")
            finish_exercise_query(operation, .Database_Failed)
            return
        }
        state.exercise_header.last_request_id = operation.intent.header_request_id
    }
    operation.result = result^
    operation.state = .Ready
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
