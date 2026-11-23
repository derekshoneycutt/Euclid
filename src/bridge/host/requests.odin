package julia_host

import transport "../transport"
import bridgemodel "../model"
import presentation_model "../presentation"
import "../../core"
import protocol "../../core/protocol"
import "core:log"
import "core:thread"
import "core:time"

//   Submit typed runtime initialization while retaining shared admission bookkeeping.
try_submit_runtime_initialize :: proc(
    service: ^Julia_Runtime_Service) -> (u64, bool) {
    if service == nil {
        return 0, false
    }
    request_id := service^.next_request_id
    outcome := send_julia_ingress_control(service,
        bridgemodel.Runtime_Initialize_Requested{
            request_id = request_id,
        })
    if !finish_julia_request_submission(
        service, request_id, .Initialize, outcome) {
        return 0, false
    }
    return request_id, true
}

//   Submit typed content initialization with one lifetime-stable native binding.
try_submit_runtime_content_initialize :: proc(
    service: ^Julia_Runtime_Service,
    native_state: ^core.Euclid_General_State) -> (u64, bool) {
    if service == nil || native_state == nil {
        return 0, false
    }
    request_id := service^.next_request_id
    outcome := send_julia_ingress_control(service,
        bridgemodel.Runtime_Content_Initialize_Requested{
            request_id = request_id,
            native_state = native_state,
        })
    if !finish_julia_request_submission(service, request_id, .Invoke, outcome) {
        return 0, false
    }
    return request_id, true
}

//   Submit one typed animation tick carrying checked slot identity.
try_submit_animation_tick :: proc(
    service: ^Julia_Runtime_Service,
    submission: Julia_Animation_Tick_Submission) -> (u64, bool) {
    if service == nil {
        return 0, false
    }
    request_id := service^.next_request_id
    outcome := send_julia_ingress_control(service, bridgemodel.Animation_Tick_Requested{
        request_id = request_id,
        handle = submission.handle,
        animation_generation = submission.animation_generation,
        sequence = submission.sequence,
    })
    if !finish_julia_request_submission(
        service, request_id, .Animation_Tick, outcome) {
        return 0, false
    }
    return request_id, true
}

//   Submit one typed animation lifecycle transaction through its compatibility handler.
try_submit_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service,
    handle: bridgemodel.Animation_Lifecycle_Slot_Handle,
    runtime_generation, animation_generation: u64) -> (u64, bool) {
    if service == nil {
        return 0, false
    }
    request_id := service^.next_request_id
    outcome := send_julia_ingress_control(
        service, bridgemodel.Animation_Lifecycle_Requested{
            request_id = request_id,
            handle = handle,
            runtime_generation = runtime_generation,
            animation_generation = animation_generation,
        })
    if !finish_julia_request_submission(service, request_id, .Invoke, outcome) {
        return 0, false
    }
    return request_id, true
}

when core.HARNESS_ENABLED {
    //   Submit one typed harness request with receiver-owned scenario-name bytes.
    try_submit_harness_scenario :: proc(
        service: ^Julia_Runtime_Service, scenario_name: string,
        step_count: i64) -> (u64, bool) {
        if service == nil || len(scenario_name) == 0 ||
            len(scenario_name) > bridgemodel.HARNESS_SCENARIO_NAME_CAPACITY ||
            step_count < 0 {
            return 0, false
        }
        request_id := service^.next_request_id
        request: bridgemodel.Harness_Scenario_Requested = {
            request_id = request_id,
            scenario_name = scenario_name,
            step_count = step_count,
        }
        outcome := send_julia_ingress_control(service, request)
        if !finish_julia_request_submission(service, request_id, .Invoke, outcome) {
            return 0, false
        }
        return request_id, true
    }
}

//   Submit typed runtime shutdown and close admission to later control work.
try_submit_runtime_shutdown :: proc(
    service: ^Julia_Runtime_Service) -> (u64, bool) {
    if service == nil {
        return 0, false
    }
    request_id := service^.next_request_id
    outcome := send_julia_ingress_control(service,
        bridgemodel.Runtime_Shutdown_Requested{
            request_id = request_id,
        })
    if !finish_julia_request_submission(service, request_id, .Shutdown, outcome) {
        return 0, false
    }
    return request_id, true
}

//   Retry typed shutdown admission while routing egress to relieve bounded pressure.
submit_runtime_shutdown_until :: proc(
    service: ^Julia_Runtime_Service, started_at: time.Tick,
    timeout_seconds: f64) -> (u64, bool) {
    if service == nil || timeout_seconds < 0 {
        return 0, false
    }
    for {
        if request_id, sent := try_submit_runtime_shutdown(service); sent {
            return request_id, true
        }
        _, _ = try_route_julia_egress(service)
        if time.duration_seconds(time.tick_since(started_at)) >= timeout_seconds {
            return 0, false
        }
        thread.yield()
    }
}

//   Route egress until the exact typed shutdown completion arrives or time expires.
wait_runtime_shutdown_completion :: proc(
    service: ^Julia_Runtime_Service, request_id: u64,
    started_at: time.Tick, timeout_seconds: f64) -> bool {
    if service == nil || request_id == 0 || timeout_seconds < 0 {
        return false
    }
    for {
        event, accepted := try_route_julia_egress(
            service, request_id, .Shutdown_Complete)
        if accepted && event.request_id == request_id &&
            event.kind == .Shutdown_Complete {
            return event.succeeded
        }
        if time.duration_seconds(time.tick_since(started_at)) >= timeout_seconds {
            return false
        }
        thread.yield()
    }
}

//   Enqueue one already-owned typed control value without blocking the display thread.
send_julia_ingress_control :: proc(
    service: ^Julia_Runtime_Service,
    value: bridgemodel.Julia_Host_Ingress) -> bridgemodel.Communication_Send_Outcome {
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(&service.julia_inbox, value)
}

//   Apply common request identity, saturation, and lifecycle bookkeeping.
finish_julia_request_submission :: proc(
    service: ^Julia_Runtime_Service, request_id: u64,
    kind: Julia_Request_Kind,
    outcome: bridgemodel.Communication_Send_Outcome) -> bool {
    if outcome != .Sent {
        service^.request_saturation_count += 1
        if diagnostic_occurrence_should_log(service^.request_saturation_count) {
            log.warnf("julia_request_saturated kind=%d outcome=%d count=%d",
                int(kind), int(outcome), service^.request_saturation_count)
        }
        return false
    }
    service^.next_request_id += 1
    service^.active_request_id = request_id
    service^.active_request_kind = kind
    if kind == .Initialize {
        service^.lifecycle = .Starting
    } else if kind == .Shutdown {
        service^.lifecycle = .Shutdown_Requested
    }
    return true
}

//   Identify dynamic ingress payloads that require validated publication helpers.
terminal_ingress_has_dynamic_payload :: proc(
    value: bridgemodel.Julia_Host_Ingress) -> bool {
    #partial switch _ in value {
    case protocol.Evaluation_Requested:
        return true
    case protocol.Completion_Requested:
        return true
    case protocol.Highlight_Requested:
        return true
    }
    return false
}

//   Clone and enqueue one typed Terminal ingress message without blocking.
send_terminal_ingress :: proc(
    service: ^Julia_Runtime_Service,
    value: bridgemodel.Julia_Host_Ingress) -> bridgemodel.Communication_Send_Outcome {
    if service == nil || service^.lifecycle == .Shutdown_Requested ||
        service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    if terminal_ingress_has_dynamic_payload(value) {
        return .Allocation_Failed
    }
    return transport.consumer_mailbox_publish(&service.julia_inbox, value)
}

//   Copy bounded evaluation source into Julia-inbox storage.
send_terminal_evaluation :: proc(
    service: ^Julia_Runtime_Service,
    request: protocol.Evaluation_Requested) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
        len(request.code) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Allocation_Failed
    }
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(
        &service.julia_inbox, bridgemodel.Julia_Host_Ingress(request))
}

//   Copy bounded scenario presentation source into Julia-inbox storage.
send_scenario_view_content :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Scenario_View_Content_Requested) ->
        bridgemodel.Communication_Send_Outcome {
    if service == nil || service^.lifecycle != .Ready {
        return .Runtime_Stopping
    }
    if len(request.source) > presentation_model.PRESENTATION_MAX_SOURCE_BYTES {
        return .Allocation_Failed
    }
    return transport.consumer_mailbox_publish(
        &service.julia_inbox, bridgemodel.Julia_Host_Ingress(request))
}

//   Copy bounded completion source into Julia-inbox storage.
send_terminal_completion_request :: proc(
    service: ^Julia_Runtime_Service,
    request: protocol.Completion_Requested) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
        len(request.code) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Allocation_Failed
    }
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(
        &service.julia_inbox, bridgemodel.Julia_Host_Ingress(request))
}

//   Identify dynamic egress payloads that require validated publication helpers.
terminal_egress_has_dynamic_payload :: proc(
    value: bridgemodel.Julia_Host_Egress) -> bool {
    #partial switch _ in value {
    case protocol.Terminal_Output_Batch:
        return true
    case protocol.Completion_Result:
        return true
    case protocol.Highlight_Result:
        return true
    case protocol.Terminal_Session_Ready:
        return true
    }
    return false
}

//   Enqueue one typed worker-owned Terminal result without blocking.
send_terminal_egress :: proc(
    service: ^Julia_Runtime_Service,
    value: bridgemodel.Julia_Host_Egress) -> bridgemodel.Communication_Send_Outcome {
    if service == nil || service^.lifecycle == .Shutdown_Requested ||
        service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    if terminal_egress_has_dynamic_payload(value) {
        return .Allocation_Failed
    }
    return transport.consumer_mailbox_publish(&service.display_inbox, value)
}

//   Copy ordered Terminal bytes into the display-owned inbox.
send_terminal_output :: proc(
    service: ^Julia_Runtime_Service,
    output: protocol.Terminal_Output_Batch) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
        len(output.bytes) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Allocation_Failed
    }
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(output))
}

//   Copy completion insertion into the display-owned inbox.
send_terminal_completion_result :: proc(
    service: ^Julia_Runtime_Service,
    result: protocol.Completion_Result) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
        len(result.insertion) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Allocation_Failed
    }
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(result))
}

//   Copy Julia's startup banner into the display-owned inbox.
send_terminal_session_ready :: proc(
    service: ^Julia_Runtime_Service,
    ready: protocol.Terminal_Session_Ready) -> bridgemodel.Communication_Send_Outcome {
    if service == nil ||
        len(ready.banner) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Allocation_Failed
    }
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    return transport.consumer_mailbox_publish(
        &service.display_inbox, bridgemodel.Julia_Host_Egress(ready))
}
