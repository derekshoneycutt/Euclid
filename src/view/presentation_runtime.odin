package view

import bridge "../bridge"
import "../core"
import dyncore "../dynview/core"
import dynparse "../dynview/parse"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../taskpool"


// Presentation_Operation retains one producer envelope through parse task join.
Presentation_Operation :: struct {
    message: ^core.Julia_Host_Egress,
    handle: taskpool.Task_Handle,
    key: dyncore.Dynview_Document_Key,
    parse_source: string,
    mode: bridge.Presentation_Source_Mode,
    result: ^dyncore.Dynview_Parse_Result,
    store_generation: u64,
    submitted: bool,
    cancellation_requested: bool,
}

// Presentation_Runtime owns one active parse and one newest bounded replacement.
Presentation_Runtime :: struct {
    active: Presentation_Operation,
    pending: ^core.Julia_Host_Egress,
    newest_generation: u64,
    observed_runtime_generation: u64,
    observed_animation_generation: u64,
    lifecycle_observed: bool,
    staging: ^core.Dynview_System,
}

// Presentation_Parse_Request retains one classified exact parse operation.
Presentation_Parse_Request :: struct {
    source: string,
    key: dyncore.Dynview_Document_Key,
    mode: bridge.Presentation_Source_Mode,
    valid: bool,
}

//   Record one required display-owned presentation lifecycle transition.
presentation_record_event :: proc(
    state: ^core.Euclid_General_State,
    kind: evidence_trace.Kind,
    animation_generation: u64,
    presentation_generation: u64) {

    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = kind,
            correlation_kind = .Animation,
            correlation = animation_generation,
            generation = animation_generation,
            revision = presentation_generation,
            flags = {.Required},
        })
}

//   Allocate durable parser output storage that remains valid across display frames.
create_presentation_runtime :: proc() -> ^Presentation_Runtime {
    runtime := new(Presentation_Runtime, context.allocator)
    if runtime == nil {
        return nil
    }
    runtime^.active.result = new(dyncore.Dynview_Parse_Result, context.allocator)
    if runtime^.active.result == nil {
        free(runtime)
        return nil
    }
    runtime^.staging = new(core.Dynview_System, context.allocator)
    if runtime^.staging == nil {
        free(runtime^.active.result)
        free(runtime)
        return nil
    }
    runtime^.staging.enabled = true
    return runtime
}

//   Release an idle presentation runtime after all shared-pool work has joined.
destroy_presentation_runtime :: proc(runtime: ^Presentation_Runtime) {
    if runtime == nil {
        return
    }
    assert(!runtime^.active.submitted)
    assert(runtime^.active.message == nil)
    assert(runtime^.pending == nil)
    free(runtime^.staging)
    free(runtime^.active.result)
    free(runtime)
}

//   Derive the parser key while retaining exact envelope bytes separately.
presentation_parse_key :: proc(
    content: core.Presented_Text,
    generation: u64) -> Presentation_Parse_Request {
    source := bridge.presentation_literal_source(content)
    mode := bridge.presentation_source_mode(content.mime, source)
    parse_mode := dynparse.Tex_Source_Mode.Document
    root_style := dynparse.Tex_Math_Root_Style.Display
    parse_source := source
    if mode == .Math {
        whole := dynparse.tex_document_whole_math(dynparse.tex_document_trim(source))
        if !whole.present {
            return {mode = mode}
        }
        parse_mode = .Math
        root_style = whole.style
        parse_source = whole.content
    } else if mode != .Document {
        return {mode = mode}
    }
    key := dyncore.document_store_key(parse_source,
        dyncore.DYNVIEW_DOCUMENT_SEMANTIC_PROFILE_DEFAULT, parse_mode, root_style,
        dyncore.document_store_source_hash(parse_source))
    return {source = parse_source, key = key, mode = mode, valid = generation != 0}
}

//   Drain one borrowed Julia egress message into its display-owned destination.
presentation_drain_julia_egress :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    service: ^core.Julia_Runtime_Service) {
    for {
        message, received := bridge.try_receive_julia_egress(service)
        if !received {
            return
        }
        if event, is_event := message^.(core.Julia_Event); is_event {
            bridge.accept_julia_event(service, event)
            _ = bridge.return_julia_egress(service, message)
            continue
        }
        if content, is_content := message^.(core.View_Content_Ready); is_content {
            presentation_admit(state, runtime, message, content)
            continue
        }
        _ = terminal_service_dispatch_egress(state, message)
        _ = bridge.return_julia_egress(service, message)
    }
}

//   Admit one presentation envelope deferred by an event-only consumer.
presentation_admit_deferred_view :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    service: ^core.Julia_Runtime_Service) {
    if deferred := bridge.take_deferred_view_content(service); deferred != nil {
        if content, ok := deferred^.(core.View_Content_Ready); ok {
            presentation_admit(state, runtime, deferred, content)
        } else {
            _ = bridge.return_julia_egress(service, deferred)
        }
    }
}

//   Drain Julia egress and advance presentation work without blocking a frame.
service_presentation_runtime :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if state == nil || runtime == nil || state^.julia_runtime_service == nil ||
        state^.simulation_executor == nil {
        return
    }
    service := state^.julia_runtime_service
    presentation_sync_lifecycle(state, runtime)
    if deferred := bridge.take_deferred_terminal_egress(service); deferred != nil {
        _ = terminal_service_dispatch_egress(state, deferred)
        _ = bridge.return_julia_egress(service, deferred)
    }
    presentation_admit_deferred_view(state, runtime, service)
    presentation_drain_julia_egress(state, runtime, service)
    terminal_tick_publish(state)
    presentation_poll_active(state, runtime)
    presentation_start_pending(state, runtime)
}

//   Cancel stale work and clear visible content after an accepted lifecycle transition.
presentation_sync_lifecycle :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    service := state^.julia_runtime_service
    if !runtime^.lifecycle_observed {
        runtime^.observed_runtime_generation = service^.runtime_generation
        runtime^.observed_animation_generation = service^.animation_generation
        runtime^.lifecycle_observed = true
        return
    }
    if runtime^.observed_runtime_generation == service^.runtime_generation &&
        runtime^.observed_animation_generation == service^.animation_generation {
        return
    }
    runtime^.observed_runtime_generation = service^.runtime_generation
    runtime^.observed_animation_generation = service^.animation_generation
    bridge.release_published_view_snapshot(state, service)
    superseded := runtime^.newest_generation != 0
    if runtime^.pending != nil {
        _ = bridge.return_julia_egress(service, runtime^.pending)
        runtime^.pending = nil
    }
    presentation_cancel_active(state, runtime)
    if superseded {
        presentation_record_event(state, .Presentation_Superseded,
            service^.animation_generation, runtime^.newest_generation)
    }
    runtime^.newest_generation = 0
}

//   Retain only the newest current presentation and cancel superseded active work.
presentation_admit :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    message: ^core.Julia_Host_Egress,
    content: core.View_Content_Ready) {
    service := state^.julia_runtime_service
    if content.presentation_generation <= runtime^.newest_generation ||
        !presentation_content_matches(state, content) {
        _ = bridge.return_julia_egress(service, message)
        return
    }
    superseded := runtime^.newest_generation != 0
    runtime^.newest_generation = content.presentation_generation
    bridge.release_published_view_snapshot(state, service)
    presentation_record_event(state, .Presentation_Cleared,
        content.animation_generation, content.presentation_generation)
    if runtime^.pending != nil {
        _ = bridge.return_julia_egress(service, runtime^.pending)
    }
    runtime^.pending = message
    presentation_cancel_active(state, runtime)
    if superseded {
        presentation_record_event(state, .Presentation_Superseded,
            content.animation_generation, content.presentation_generation)
    }
}

//   Start the newest pending value through a cache hit or one shared-pool task.
presentation_start_pending :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if runtime^.active.submitted || runtime^.pending == nil {
        return
    }
    message := runtime^.pending
    content, ok := message^.(core.View_Content_Ready)
    if !ok || !presentation_content_is_current(state, runtime, content) {
        runtime^.pending = nil
        _ = bridge.return_julia_egress(state^.julia_runtime_service, message)
        return
    }
    source := bridge.presentation_literal_source(content.content)
    parse := presentation_parse_key(
        content.content, state^.dynview_documents.generation)
    request := bridge.Presentation_Snapshot_Request{
        content = content, source = source, mode = parse.mode,
    }
    if parse.mode == .Plain || !parse.valid {
        presentation_materialize(state, runtime, request)
        presentation_release_pending(state, runtime)
        return
    }
    if presentation_resolve_cached(state, runtime, request, parse) {
        presentation_release_pending(state, runtime)
        return
    }
    presentation_submit_parse(state, runtime, message, parse)
}

//   Materialize a positive or negative cache hit and report a true cache decision.
presentation_resolve_cached :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    request: bridge.Presentation_Snapshot_Request,
    parse: Presentation_Parse_Request) -> bool {
    handle, lookup := dyncore.document_store_lookup_keyed(
        &state^.dynview_documents, parse.source, parse.key)
    if lookup == .Not_Found {
        return false
    }
    if lookup == .Ok {
        document, resolved := dyncore.document_store_resolve(
            &state^.dynview_documents, handle)
        if resolved == .Ok {
            semantic_request := request
            semantic_request.document = &document
            presentation_materialize(state, runtime, semantic_request)
            return true
        }
    }
    presentation_materialize(state, runtime, request)
    return true
}

//   Return the pending envelope after all source borrows and materialization end.
presentation_release_pending :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    message := runtime^.pending
    runtime^.pending = nil
    _ = bridge.return_julia_egress(state^.julia_runtime_service, message)
}

//   Submit one parser operation while preserving its envelope and exact source borrow.
presentation_submit_parse :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    message: ^core.Julia_Host_Egress,
    parse: Presentation_Parse_Request) {
    result := runtime^.active.result
    runtime^.active = {
        message = message,
        key = parse.key,
        parse_source = parse.source,
        mode = parse.mode,
        result = result,
        store_generation = state^.dynview_documents.generation,
    }
    handle, outcome := taskpool.task_pool_submit(
        &state^.simulation_executor^.pool,
        presentation_parse_task, rawptr(&runtime^.active))
    if outcome != .Queued {
        runtime^.active = {result = result}
        return
    }
    runtime^.pending = nil
    runtime^.active.handle = handle
    runtime^.active.submitted = true
}

//   Build one parser result without touching display-owned document-store state.
presentation_parse_task :: proc(
    payload: rawptr,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    operation := cast(^Presentation_Operation)payload
    if operation == nil || taskpool.task_cancellation_requested(token) {
        return .Cancelled
    }
    status := dyncore.dynview_parse_build_keyed(
        operation^.parse_source, operation^.key,
        operation^.store_generation, operation^.result)
    if taskpool.task_cancellation_requested(token) {
        return .Cancelled
    }
    return .Succeeded if status == .Ok || status == .Rejected else .Failed
}

//   Join one ready operation, then commit and publish only if it is still current.
presentation_poll_active :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    operation := &runtime^.active
    if !operation^.submitted {
        return
    }
    presentation_cancel_stale_active(state, runtime)
    if taskpool.task_pool_poll(
        &state^.simulation_executor^.pool, operation^.handle) != .Ready {
        return
    }
    task_result, joined := taskpool.task_pool_wait(
        &state^.simulation_executor^.pool, operation^.handle)
    message := operation^.message
    content, has_content := message^.(core.View_Content_Ready)
    if joined == .Joined && task_result == .Succeeded && has_content &&
        presentation_content_is_current(state, runtime, content) {
        presentation_commit_joined(state, runtime, content)
    }
    _ = bridge.return_julia_egress(state^.julia_runtime_service, message)
    result := operation^.result
    operation^ = {result = result}
}

//   Commit one current joined result and publish semantics or the exact literal source.
presentation_commit_joined :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    content: core.View_Content_Ready) {
    operation := &runtime^.active
    request := bridge.Presentation_Snapshot_Request{
        content = content,
        source = bridge.presentation_literal_source(content.content),
        mode = operation^.mode,
    }
    handle, commit := dyncore.document_store_commit(
        &state^.dynview_documents, operation^.parse_source, operation^.result)
    if commit == .Ok {
        document, resolved := dyncore.document_store_resolve(
            &state^.dynview_documents, handle)
        if resolved == .Ok {
            request.document = &document
            presentation_materialize(state, runtime, request)
            return
        }
    }
    presentation_materialize(state, runtime, request)
}

//   Publish one current semantic document or exact literal fallback.
presentation_materialize :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    request: bridge.Presentation_Snapshot_Request) {
    if presentation_content_is_current(state, runtime, request.content) {
        _ = bridge.publish_presentation_snapshot(
            state, runtime^.staging, request)
    }
}

//   Match producer identities against the current display-owned runtime selection.
presentation_content_matches :: proc(
    state: ^core.Euclid_General_State,
    content: core.View_Content_Ready) -> bool {
    service := state^.julia_runtime_service
    return service != nil && state^.julia_interface != nil &&
        content.runtime_generation == service^.runtime_generation &&
        content.animation_generation == service^.animation_generation &&
        content.animation == state^.julia_interface^.current_animation
}

//   Require the newest presentation and a quiescent current runtime generation.
presentation_content_is_current :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    content: core.View_Content_Ready) -> bool {
    service := state^.julia_runtime_service
    return presentation_content_matches(state, content) &&
        content.presentation_generation == runtime^.newest_generation &&
        service^.lifecycle == .Ready && service^.reload_state == .Idle &&
        !state^.julia_interface^.pending_animation_reset
}

//   Cooperatively cancel active work once a newer or invalid generation exists.
presentation_cancel_stale_active :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    content, ok := runtime^.active.message^.(core.View_Content_Ready)
    if ok && presentation_content_is_current(state, runtime, content) {
        return
    }
    presentation_cancel_active(state, runtime)
}

//   Request cancellation exactly once while preserving ownership through join.
presentation_cancel_active :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if !runtime^.active.submitted || runtime^.active.cancellation_requested {
        return
    }
    outcome := taskpool.task_pool_cancel(
        &state^.simulation_executor^.pool, runtime^.active.handle)
    runtime^.active.cancellation_requested = outcome != .Stale_Handle
}

//   Cancel and join all parser work before its shared pool or producer is destroyed.
quiesce_presentation_runtime :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if state == nil || runtime == nil || state^.julia_runtime_service == nil {
        return
    }
    service := state^.julia_runtime_service
    if runtime^.active.submitted {
        presentation_cancel_active(state, runtime)
        _, joined := taskpool.task_pool_wait(
            &state^.simulation_executor^.pool, runtime^.active.handle)
        assert(joined == .Joined)
        _ = bridge.return_julia_egress(service, runtime^.active.message)
        result := runtime^.active.result
        runtime^.active = {result = result}
    }
    if runtime^.pending != nil {
        _ = bridge.return_julia_egress(service, runtime^.pending)
        runtime^.pending = nil
    }
}