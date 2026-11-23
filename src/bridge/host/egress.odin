package julia_host

import transport "../transport"
import bridgemodel "../model"
import presentation_model "../presentation"
import "../../core"
import evidence_session "../../evidence/session"
import "core:log"

// Borrow one display-inbox envelope until dispatch ends; retained payloads must be copied.
try_receive_julia_egress :: proc(
    service: ^Julia_Runtime_Service) -> (^bridgemodel.Julia_Host_Egress, bool) {
    if service == nil {
        return nil, false
    }
    return transport.consumer_mailbox_try_recv(&service^.display_inbox)
}

// End one transient display-owner borrow and recycle exhausted local batch storage.
release_julia_egress :: proc(
    service: ^Julia_Runtime_Service,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    if service == nil || message == nil {
        return false
    }
    transport.consumer_mailbox_release(&service.display_inbox, message)
    return true
}

//   Retain only the newest presentation until the display can validate its generation.
retain_display_view_content :: proc(
    service: ^Julia_Runtime_Service,
    message: ^bridgemodel.Julia_Host_Egress) {
    content, ok := message^.(bridgemodel.View_Content_Ready)
    if ok && owned_view_content_store(&service.display_pending_view_storage, content) {
        service.display_pending_view_content =
            &service.display_pending_view_storage.message
    }
}

//   Route one retained presentation after its owning lifecycle boundary commits.
route_retained_display_view_content :: proc(service: ^Julia_Runtime_Service) {
    message := service^.display_pending_view_content
    service^.display_pending_view_content = nil
    if message != nil {
        if service.display_egress_dispatch != nil {
            service.display_egress_dispatch(service.display_egress_user_data, message)
            owned_view_content_clear(&service.display_pending_view_storage)
        } else {
            service.display_pending_view_content = message
        }
    }
}

//   Normalize one typed completion envelope for display-owned metadata handling.
decode_julia_completion :: proc(
    message: ^bridgemodel.Julia_Host_Egress) -> (Julia_Event, bool) {
    if completed, ok := message^.(bridgemodel.Runtime_Initialized); ok {
        return julia_event_from_completion(
            completed.completion, .Initialize, .Initialized), true
    }
    if completed, ok := message^.(bridgemodel.Runtime_Content_Initialized); ok {
        return julia_event_from_completion(
            completed.completion, .Invoke, .Invoke_Complete), true
    }
    if completed, ok := message^.(bridgemodel.Harness_Scenario_Completed); ok {
        return julia_event_from_completion(
            completed.completion, .Invoke, .Invoke_Complete), true
    }
    if completed, ok := message^.(bridgemodel.Runtime_Shutdown_Completed); ok {
        return julia_event_from_completion(
            completed.completion, .Shutdown, .Shutdown_Complete), true
    }
    return {}, false
}

//   Resolve whether one completion owns the exact worker-completed slot incarnation.
animation_tick_completion_owns_slot :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Tick_Completed) -> bool {
    index := int(completed.handle.index)
    if index < 0 || index >= len(service^.animation_tick_slots) {
        return false
    }
    slot := &service^.animation_tick_slots[index]
    return slot^.state == .Complete &&
        slot^.reservation_generation == completed.handle.reservation_generation &&
        slot^.request_id == completed.completion.request_id &&
        slot^.generation == completed.animation_generation &&
        slot^.sequence == completed.sequence
}

//   Match one exact slot completion against the active request and current animation.
animation_tick_completion_matches :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Tick_Completed) -> bool {
    return animation_tick_completion_owns_slot(service, completed) &&
        completed.completion.request_id == service^.active_request_id &&
        service^.active_request_kind == .Animation_Tick &&
        completed.animation_generation == service^.animation_generation
}

//   Recycle a rejected completion only when its handle owns the exact completed slot.
recycle_rejected_animation_tick :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Tick_Completed) {
    if animation_tick_completion_owns_slot(service, completed) {
        service^.animation_tick_slots[completed.handle.index].state = .Free
    }
}

//   Validate and normalize one checked tick completion.
accept_animation_tick_completion :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Tick_Completed) -> (Julia_Event, bool) {
    if !animation_tick_completion_matches(service, completed) {
        owns_active_slot := animation_tick_completion_owns_slot(service, completed) &&
            completed.completion.request_id == service^.active_request_id &&
            service^.active_request_kind == .Animation_Tick
        recycle_rejected_animation_tick(service, completed)
        if owns_active_slot {
            event := julia_event_from_completion(
                completed.completion, .Animation_Tick, .Animation_Tick_Complete)
            accept_julia_event(service, event)
        }
        return {}, false
    }
    service^.animation_tick_slots[completed.handle.index].state = .Accepted
    event := julia_event_from_completion(
        completed.completion, .Animation_Tick, .Animation_Tick_Complete)
    event.slot_index = completed.handle.index
    accept_julia_event(service, event)
    return event, true
}

//   Match one lifecycle completion to the exact completed transaction and active request.
animation_lifecycle_completion_matches :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Lifecycle_Completed) -> bool {
    slot := &service^.animation_lifecycle_slot
    expected_success := slot^.outcome == .Committed
    return completed.handle.index == 0 && slot^.state == .Complete &&
        slot^.reservation_generation == completed.handle.reservation_generation &&
        slot^.request_id == completed.completion.request_id &&
        slot^.runtime_generation == completed.runtime_generation &&
        slot^.animation_generation == completed.animation_generation &&
        completed.completion.request_id == service^.active_request_id &&
        service^.active_request_kind == .Invoke &&
        completed.completion.succeeded == expected_success
}

//   Apply lifecycle completion metadata without classifying rollback as transport failure.
accept_animation_lifecycle_event :: proc(
    service: ^Julia_Runtime_Service,
    event: Julia_Event) {
    if service^.evidence_session != nil {
        for evidence_index in 0..<event.evidence_count {
            evidence := event.evidence[evidence_index]
            evidence_session.session_accept_event(
                service^.evidence_session, evidence)
        }
    }
    service^.active_request_id = 0
}

//   Accept one exact lifecycle completion and release its bounded transaction slot.
accept_animation_lifecycle_completion :: proc(
    service: ^Julia_Runtime_Service,
    completed: bridgemodel.Animation_Lifecycle_Completed) -> (Julia_Event, bool) {
    if !animation_lifecycle_completion_matches(service, completed) {
        log.warnf(
            "animation_lifecycle_completion_rejected request_id=%d slot_generation=%d runtime_generation=%d animation_generation=%d",
            completed.completion.request_id,
            completed.handle.reservation_generation,
            completed.runtime_generation,
            completed.animation_generation)
        return {}, false
    }
    event := julia_event_from_completion(
        completed.completion, .Invoke, .Invoke_Complete)
    event.slot_index = completed.handle.index
    accept_animation_lifecycle_event(service, event)
    service^.animation_lifecycle_slot.state = .Free
    return event, true
}

//   Route checked animation tick and lifecycle completions to their slot owners.
route_animation_egress_completion :: proc(
    service: ^Julia_Runtime_Service,
    message: ^bridgemodel.Julia_Host_Egress) -> Animation_Egress_Route_Result {
    if completed, is_tick := message^.(bridgemodel.Animation_Tick_Completed); is_tick {
        event, accepted := accept_animation_tick_completion(service, completed)
        _ = release_julia_egress(service, message)
        return {
            event = event,
            accepted = accepted,
            handled = true,
        }
    }
    if completed, is_lifecycle := message^.(
        bridgemodel.Animation_Lifecycle_Completed); is_lifecycle {
        event, accepted := accept_animation_lifecycle_completion(service, completed)
        _ = release_julia_egress(service, message)
        return {
            event = event,
            accepted = accepted,
            handled = true,
        }
    }
    return {}
}

//   Route one borrowed egress envelope and return any accepted Julia event.
route_julia_egress_message :: proc(
    service: ^Julia_Runtime_Service,
    message: ^bridgemodel.Julia_Host_Egress) -> (Julia_Event, bool) {
    if service == nil || message == nil {
        return {}, false
    }
    animation_result := route_animation_egress_completion(service, message)
    if animation_result.handled {
        return animation_result.event, animation_result.accepted
    }
    if event, completed := decode_julia_completion(message); completed {
        _ = release_julia_egress(service, message)
        accept_julia_event(service, event)
        return event, true
    }
    if service^.display_egress_dispatch != nil {
        service^.display_egress_dispatch(
            service^.display_egress_user_data, message)
        _ = release_julia_egress(service, message)
        return {}, false
    }
    if _, is_content := message^.(bridgemodel.View_Content_Ready); is_content &&
        service^.lifecycle != .Shutdown_Requested &&
        service^.lifecycle != .Stopped {
        retain_display_view_content(service, message)
        _ = release_julia_egress(service, message)
        return {}, false
    }
    _ = release_julia_egress(service, message)
    return {}, false
}

// Route the full accepted batch, retaining the first matching completion before reset.
try_route_julia_egress :: proc(
    service: ^Julia_Runtime_Service, request_id: u64 = 0,
    expected: bridgemodel.Julia_Event_Kind = .Initialized,
    defer_content := false) -> (Julia_Event, bool) {
    result := route_julia_egress_batch(
        service, request_id, expected, defer_content)
    return result.event, result.matched
}

// Dispatch every accepted envelope and reset the display inbox before returning.
drain_julia_egress :: proc(service: ^Julia_Runtime_Service) -> int {
    result := route_julia_egress_batch(service, 0, .Initialized, false)
    return result.count
}

// Keep correlated results by value while routing the tail of a paused-admission batch.
route_julia_egress_batch :: proc(
    service: ^Julia_Runtime_Service, request_id: u64,
    expected: bridgemodel.Julia_Event_Kind,
    defer_content: bool) -> (result: Julia_Egress_Batch_Result) {
    if service == nil {
        return
    }
    budget := transport.consumer_mailbox_batch_count(&service.display_inbox)
    for result.count < budget {
        message, received := try_receive_julia_egress(service)
        assert(received)
        if _, content := message^.(bridgemodel.View_Content_Ready);
           defer_content && content {
            retain_display_view_content(service, message)
            _ = release_julia_egress(service, message)
        } else {
            event, accepted := route_julia_egress_message(service, message)
            if accepted && !result.matched &&
                (request_id == 0 || (event.request_id == request_id &&
                    event.kind == expected)) {
                result.event, result.matched = event, true
            }
        }
        result.count += 1
    }
    return
}

//   Install the sole normal-runtime non-event destination and route startup content.
configure_julia_egress_dispatch :: proc(
    service: ^Julia_Runtime_Service,
    dispatch: bridgemodel.Julia_Egress_Dispatch_Proc,
    user_data: rawptr) {
    assert(service != nil && dispatch != nil)
    assert(service^.display_egress_dispatch == nil)
    service^.display_egress_dispatch = dispatch
    service^.display_egress_user_data = user_data
    pending := service^.display_pending_view_content
    service^.display_pending_view_content = nil
    if pending != nil {
        dispatch(user_data, pending)
        owned_view_content_clear(&service.display_pending_view_storage)
    }
}

//   Remove the normal-runtime destination and clear any unclaimed display-owned content.
clear_julia_egress_dispatch :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    service^.display_egress_dispatch = nil
    service^.display_egress_user_data = nil
    if service^.display_pending_view_content != nil {
        owned_view_content_clear(&service.display_pending_view_storage)
        service^.display_pending_view_content = nil
    }
}

// Build a borrowed canonical presentation value; publication or retention copies its bytes.
make_view_content :: proc(
    state: ^core.Euclid_General_State, mime: presentation_model.Presentation_Mime,
    source: []u8) -> bridgemodel.View_Content_Ready {
    service := state^.julia_runtime_service
    generation := service^.presentation_generation + 1
    animation_generation := service^.animation_generation
    if service^.presentation_animation_generation_override != 0 {
        animation_generation = service^.presentation_animation_generation_override
    }
    animation := state^.julia_interface^.current_animation
    if service^.presentation_animation_override != nil {
        animation = service^.presentation_animation_override
    }
    return {
        request_id = service^.active_request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = animation_generation,
        presentation_generation = generation,
        animation = animation,
        content = {
            mime = mime,
            bytes = source,
        },
    }
}

// Build correlated debug presentation without retaining its ingress batch.
make_scenario_view_content :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Scenario_View_Content_Requested) ->
    bridgemodel.View_Content_Ready {
    generation := service^.presentation_generation + 1
    return {
        origin = request.origin,
        request_id = request.request_id,
        runtime_generation = request.runtime_generation,
        animation_generation = request.animation_generation,
        presentation_generation = generation,
        animation = request.animation,
        content = {
            mime = request.mime,
            bytes = request.source,
        },
    }
}

//   Publish scenario content from the Julia owner, retaining the newest retry.
send_scenario_presented_text :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Scenario_View_Content_Requested) ->
        bridgemodel.Communication_Send_Outcome {
    return publish_or_retain_view_content(
        service, make_scenario_view_content(service, request))
}

//   Enqueue canonical view content without blocking, retaining only the newest retry.
send_presented_text :: proc(
    state: ^core.Euclid_General_State, mime: presentation_model.Presentation_Mime,
    source: []u8) -> bridgemodel.Communication_Send_Outcome {
    service := state^.julia_runtime_service
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return publish_or_retain_view_content(service, make_view_content(state, mime, source))
}

// Preserve the newest domain-owned retry only for recoverable count/storage pressure.
publish_or_retain_view_content :: proc(
    service: ^Julia_Runtime_Service,
    content: bridgemodel.View_Content_Ready) -> bridgemodel.Communication_Send_Outcome {
    if len(content.content.bytes) > presentation_model.PRESENTATION_MAX_SOURCE_BYTES {
        return .Allocation_Failed
    }
    outcome := transport.consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(content))
    if outcome == .Sent {
        owned_view_content_clear(&service.pending_view_storage)
        service.pending_view_content = nil
    } else if outcome == .Queue_Full || outcome == .Storage_Full {
        if !owned_view_content_store(&service.pending_view_storage, content) {
            return .Allocation_Failed
        }
        service.pending_view_content = &service.pending_view_storage.message
    } else {
        return outcome
    }
    service.presentation_generation = content.presentation_generation
    return outcome
}

//   Reliably transfer one retained presentation before its request completion event.
flush_pending_view_content :: proc(
    service: ^Julia_Runtime_Service) -> bridgemodel.Communication_Send_Outcome {
    message := service^.pending_view_content
    if message == nil {
        return .Sent
    }
    outcome := transport.consumer_mailbox_send(&service.display_inbox, message^)
    if outcome != .Sent {
        return outcome
    }
    owned_view_content_clear(&service.pending_view_storage)
    service^.pending_view_content = nil
    return .Sent
}
