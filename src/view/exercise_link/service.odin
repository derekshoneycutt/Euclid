package exercise_link

import bridge_exercise "../../bridge/exercise"

import bridge "../../bridge/host"
import bridgemodel "../../bridge/model"
import core "../../core"
import contentdata "../../core/content"
import userdata "../../persistence/userdata"
import termhyperlink "../../terminal/hyperlink"
import terminalview "../terminal"

import "core:encoding/uuid"
import "core:log"
import "core:sync"

// Accept an internal OSC 8 target and resolve it through its owning database.
exercise_link_activate :: proc(
    state: ^core.Euclid_General_State, uri: string) -> bool {
    target, valid := termhyperlink.hyperlink_exercise_target_parse(uri)
    if !valid || state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil ||
        state^.julia_interface^.current_animation !=
            state^.julia_interface^.selected_animation ||
        state^.julia_interface^.selected_animation == nil {
        return false
    }
    source_animation := state^.julia_interface^.selected_animation
    exercise_link_cancel(state, "")
    request_id := bridgemodel.exercise_header_request_next(
        &state^.julia_runtime_service.exercise_header_request_sequence)
    bridgemodel.exercise_header_invalidate_requests(
        &state^.julia_runtime_service.exercise_header_request_sequence,
        &state^.exercise_header.last_request_id)
    token, queued := terminal_exercise_link_queue_resolution(state, target)
    if !queued {
        terminal_exercise_link_report(state, "Exercise link could not be resolved.")
        return false
    }
    source_id: [36]u8
    _ = uuid.to_string(source_animation^.stable_id, source_id[:])
    state^.exercise_link = {
        phase = .Resolving,
        user_namespace = target.user_namespace,
        token = token,
        source_animation_generation = state^.julia_runtime_service.animation_generation,
        source_animation_id = source_id,
        header_request_id = request_id,
    }
    return true
}

// Queue one alias or UUID resolution using the selected namespace's existing owner.
terminal_exercise_link_queue_resolution :: proc(
    state: ^core.Euclid_General_State,
    target: termhyperlink.Exercise_Link_Target) -> (u64, bool) {
    target_identity := target.identity
    identity := string(target_identity[:target.identity_byte_count])
    if target.user_namespace {
        return terminal_exercise_link_queue_user(
            state, target, userdata.User_Exercise_Operation.Read_Reference,
            userdata.User_Exercise_Operation.Read_Identity)
    }
    kind := contentdata.Exercise_Query_Kind.Resolve_Alias
    if target.uuid_identity {
        kind = .Resolve_Uuid
    }
    query, valid := contentdata.exercise_query_request_make(
        0, kind, "", identity, {})
    if !valid {
        return 0, false
    }
    token: u64
    accepted := bridge_exercise.enqueue_exercise_query(state, query, false, &token) ==
        bridgemodel.BRIDGE_STATUS_OK
    return token, accepted
}

// Queue one bounded user-store identity or reference read.
terminal_exercise_link_queue_user :: proc(
    state: ^core.Euclid_General_State, target: termhyperlink.Exercise_Link_Target,
    reference_operation: userdata.User_Exercise_Operation,
    identity_operation: userdata.User_Exercise_Operation) -> (u64, bool) {
    target_identity := target.identity
    task: userdata.User_Exercise_Task = {}
    if target.uuid_identity {
        identity, failure := uuid.read(
            string(target_identity[:target.identity_byte_count]))
        if failure != .None {
            return 0, false
        }
        task.operation = identity_operation
        task.identity = identity
    } else {
        task.operation = reference_operation
        task.reference_length = u8(target.identity_byte_count)
        copy(task.reference[:], target_identity[:target.identity_byte_count])
    }
    token: u64
    accepted := bridge_exercise.enqueue_user_exercise_operation(
        state, task, false, &token) == bridgemodel.BRIDGE_STATUS_OK
    return token, accepted
}

// Advance resolution and fresh-session loading without borrowing Terminal storage.
exercise_link_service :: proc(state: ^core.Euclid_General_State) {
    link := &state^.exercise_link
    if link^.phase == .Idle {
        return
    }
    if !terminal_exercise_link_intent_is_current(state) {
        exercise_link_cancel(state, "Exercise link cancelled.")
        return
    }
    if link^.phase == .Resolving {
        terminal_exercise_link_service_resolution(state)
    }
    if link^.phase == .Awaiting_Reset {
        terminal_exercise_link_observe_reset(state)
    }
    if link^.phase == .Awaiting_Ready {
        terminal_exercise_link_observe_ready(state)
    }
    if link^.phase == .Reading {
        terminal_exercise_link_service_read(state)
    }
}

// Reject pending link work after navigation or a newer header request.
terminal_exercise_link_intent_is_current :: proc(
    state: ^core.Euclid_General_State) -> bool {
    link := &state^.exercise_link
    service := state^.julia_runtime_service
    if service == nil || state^.julia_interface == nil ||
        bridgemodel.exercise_header_request_latest(
        &service^.exercise_header_request_sequence) != link^.header_request_id {
        return false
    }
    selected := state^.julia_interface^.selected_animation
    if link^.phase == .Resolving {
        if selected == nil || state^.julia_interface^.current_animation != selected {
            return false
        }
        source_id: [36]u8
        _ = uuid.to_string(selected^.stable_id, source_id[:])
        return source_id == link^.source_animation_id &&
            service^.animation_generation == link^.source_animation_generation
    }
    return selected != nil && selected^.name == bridge.TERMINAL_ANIMATION_NAME
}

// Consume the completed namespace resolution and request the ordinary Terminal reset.
terminal_exercise_link_service_resolution :: proc(
    state: ^core.Euclid_General_State) {
    link := &state^.exercise_link
    identity, ready := terminal_exercise_link_take_resolution(state)
    if !ready {
        return
    }
    if !contentdata.exercise_uuid_is_valid(string(identity[:])) {
        exercise_link_cancel(state, "Exercise link target is unavailable.")
        return
    }
    link^.identity = identity
    terminal := terminal_exercise_link_find_terminal(state)
    if terminal == nil || !bridge.select_animation_programmatically(state, terminal) {
        exercise_link_cancel(state, "Terminal is unavailable.")
        return
    }
    link^.phase = .Awaiting_Reset
    if terminal == state^.julia_interface^.current_animation {
        state^.julia_interface^.pending_animation_reset = true
    }
}

// Find the registered Terminal animation without matching a display label elsewhere.
terminal_exercise_link_find_terminal :: proc(
    state: ^core.Euclid_General_State) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if state == nil || state^.julia_interface == nil {
        return nil
    }
    for animation := state^.julia_interface^.animation_head; animation != nil;
        animation = animation^.next_in_registry {
        if animation^.name == bridge.TERMINAL_ANIMATION_NAME {
            return animation
        }
    }
    return nil
}

// Observe the committed generation change before waiting for a ready session.
terminal_exercise_link_observe_reset :: proc(
    state: ^core.Euclid_General_State) {
    link := &state^.exercise_link
    if !state^.terminal.initialized ||
        state^.terminal.animation_generation == link^.source_animation_generation {
        return
    }
    link^.terminal_generation = state^.terminal.animation_generation
    link^.phase = .Awaiting_Ready
}

// Start the second identity read only after the new Terminal session is ready.
terminal_exercise_link_observe_ready :: proc(
    state: ^core.Euclid_General_State) {
    link := &state^.exercise_link
    term := &state^.terminal
    if !term^.initialized || term^.animation_generation != link^.terminal_generation {
        return
    }
    if !term^.julia_session_ready {
        return
    }
    if !terminal_exercise_link_queue_read(state) {
        exercise_link_cancel(state, "Exercise link could not be loaded.")
    }
}

// Queue the post-reset UUID read through the established content or user-store path.
terminal_exercise_link_queue_read :: proc(
    state: ^core.Euclid_General_State) -> bool {
    link := &state^.exercise_link
    if link^.user_namespace {
        return terminal_exercise_link_queue_user_read(state)
    }
    identity := string(link^.identity[:])
    query, valid := contentdata.exercise_query_request_make(
        0, .Read_Uuid, "", identity, {})
    if !valid {
        return false
    }
    token: u64
    if bridge_exercise.enqueue_exercise_query(state, query, true, &token) !=
        bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    link^.token = token
    link^.phase = .Reading
    sync.mutex_lock(&state^.julia_runtime_service.exercise_operation.mutex)
    link^.header_request_id =
        state^.julia_runtime_service.exercise_operation.intent.header_request_id
    sync.mutex_unlock(&state^.julia_runtime_service.exercise_operation.mutex)
    return true
}

// Queue a post-reset user-store identity read through its joined worker lane.
terminal_exercise_link_queue_user_read :: proc(
    state: ^core.Euclid_General_State) -> bool {
    link := &state^.exercise_link
    identity, failure := uuid.read(string(link^.identity[:]))
    if failure != .None {
        return false
    }
    task: userdata.User_Exercise_Task = {
        operation = .Read_Identity,
        identity = identity,
    }
    token: u64
    if bridge_exercise.enqueue_user_exercise_operation(state, task, true, &token) !=
        bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    link^.token = token
    link^.phase = .Reading
    sync.mutex_lock(&state^.julia_runtime_service.user_exercise_operation.mutex)
    link^.header_request_id =
        state^.julia_runtime_service.user_exercise_operation.intent.header_request_id
    sync.mutex_unlock(&state^.julia_runtime_service.user_exercise_operation.mutex)
    return true
}

// Consume the final read completion after its owner has attempted header publication.
terminal_exercise_link_service_read :: proc(
    state: ^core.Euclid_General_State) {
    link := &state^.exercise_link
    ready, succeeded := terminal_exercise_link_take_read(state)
    if !ready {
        return
    }
    if !succeeded {
        terminal_exercise_link_report(
            state, "Exercise link target is no longer available.")
    }
    link^ = {}
}

// Copy and release a resolved record identity from its owning operation slot.
terminal_exercise_link_take_resolution :: proc(
    state: ^core.Euclid_General_State) -> ([36]u8, bool) {
    if state^.exercise_link.user_namespace {
        return terminal_exercise_link_take_user_resolution(state)
    }
    operation := &state^.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Ready || operation.intent.token != state^.exercise_link.token {
        return {}, false
    }
    result := operation.result
    operation.state = .Idle
    if result.status != .Ready ||
        !contentdata.exercise_uuid_is_valid(string(result.exercise.exercise_id[:])) {
        return {}, true
    }
    return result.exercise.exercise_id, true
}

// Copy and release a resolved user identity from its joined operation result.
terminal_exercise_link_take_user_resolution :: proc(
    state: ^core.Euclid_General_State) -> ([36]u8, bool) {
    operation := &state^.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Ready ||
       operation.intent.request_id != state^.exercise_link.token {
        return {}, false
    }
    status := operation.status
    identity := operation.result.result.id
    operation.state = .Idle
    if status != .Ready {
        return {}, true
    }
    buffer: [36]u8
    _ = uuid.to_string(identity, buffer[:])
    return buffer, true
}

// Consume a final completion without exposing partial data or retaining its slot.
terminal_exercise_link_take_read :: proc(
    state: ^core.Euclid_General_State) -> (bool, bool) {
    link := &state^.exercise_link
    if link^.user_namespace {
        return terminal_exercise_link_take_user_read(state)
    }
    operation := &state^.julia_runtime_service.exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Ready || operation.intent.token != link^.token {
        return false, false
    }
    succeeded := operation.result.status == .Ready
    operation.state = .Idle
    return true, succeeded
}

// Consume a final user-store completion only after joined work has returned.
terminal_exercise_link_take_user_read :: proc(
    state: ^core.Euclid_General_State) -> (bool, bool) {
    operation := &state^.julia_runtime_service.user_exercise_operation
    sync.mutex_lock(&operation.mutex)
    defer sync.mutex_unlock(&operation.mutex)
    if operation.state != .Ready ||
        operation.intent.request_id != state^.exercise_link.token {
        return false, false
    }
    succeeded := operation.status == .Ready
    operation.state = .Idle
    return true, succeeded
}

// Abandon one link operation and invalidate any late header publication.
exercise_link_cancel :: proc(
    state: ^core.Euclid_General_State, message: string) {
    link := &state^.exercise_link
    if link^.phase == .Idle {
        return
    }
    if link^.phase == .Resolving || link^.phase == .Reading {
        if link^.user_namespace {
            bridge_exercise.cancel_user_exercise_operation(state, link^.token)
        } else {
            bridge_exercise.cancel_exercise_query(state, link^.token)
        }
    }
    _ = bridgemodel.exercise_header_request_next(
        &state^.julia_runtime_service.exercise_header_request_sequence)
    bridgemodel.exercise_header_invalidate_requests(
        &state^.julia_runtime_service.exercise_header_request_sequence,
        &state^.exercise_header.last_request_id)
    link^ = {}
    if len(message) > 0 {
        terminal_exercise_link_report(state, message)
    }
}

// Report rejected link operations both visibly and in diagnostics.
terminal_exercise_link_report :: proc(
    state: ^core.Euclid_General_State, message: string) {
    log.warnf("%s", message)
    if state != nil && state^.terminal.initialized {
        terminalview.terminal_append_output_line(&state^.terminal, message)
    }
}
