package bridge

import bridgemodel "model"
import "../core"
import contentdata "../core/content"
import content "../view/content"

import "core:encoding/uuid"
import "core:log"

// Exact callback identity supplied by the host; padding matches the Julia isbits ABI.
Animation_Content_Invocation :: struct {
    animation_identity: uuid.Identifier,
    runtime_generation: u64,
    animation_generation: u64,
    operation: bridgemodel.Animation_Operation,
}

#assert(size_of(Animation_Content_Invocation) == 40)
#assert(offset_of(Animation_Content_Invocation, runtime_generation) == 16)
#assert(offset_of(Animation_Content_Invocation, animation_generation) == 24)
#assert(offset_of(Animation_Content_Invocation, operation) == 32)

// Prepare the entering value while retaining the active value for Exit and rollback Enter.
prepare_animation_content_specification :: proc(
    state: ^core.Euclid_General_State,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    reloading: bool) -> bool {
    service := state^.julia_runtime_service
    generation := content.content_service_generation(state^.content_service)
    runtime_generation := service^.runtime_generation
    if reloading {
        generation = content.content_service_staged_generation(state^.content_service)
        runtime_generation += 1
    }
    status := contentdata.resolve_animation_content_specification(
        generation, animation^.stable_id, runtime_generation,
        &service^.active_content_specification, &service^.pending_content_specification)
    if status != .Ok {
        log.errorf("animation_content_resolution_failed status=%v", status)
    }
    return status == .Ok
}

// Select an invocation-owned value, never resolving from mutable selection during Exit.
animation_content_invocation_value :: proc(
    state: ^core.Euclid_General_State, operation: bridgemodel.Animation_Operation) ->
        (^contentdata.Animation_Content_Specification, u64) {
    service := state^.julia_runtime_service
    if snapshot := state^.animation_query_snapshot_target; snapshot != nil {
        if operation != .Tick && operation != .Presentation_Selection_Changed {
            return nil, 0
        }
        return &snapshot^.content_specification, snapshot^.animation_generation
    }
    if service^.animation_lifecycle_slot.state == .Pending {
        if operation == .Enter {
            return &service^.pending_content_specification,
                service^.animation_generation + 1
        }
        if operation == .Exit {
            return &service^.active_content_specification, service^.animation_generation
        }
        if operation == .Presentation_Selection_Changed {
            return &service^.active_content_specification, service^.animation_generation
        }
    }
    if service^.lifecycle == .Shutdown_Requested && operation == .Exit {
        return &service^.active_content_specification, service^.animation_generation
    }
    return nil, 0
}

// Copy one validated callback value to Julia-owned storage; failed queries leave it unchanged.
@(export)
copy_animation_content_specification :: proc "c" (
    state: ^core.Euclid_General_State, invocation: Animation_Content_Invocation,
    output: ^contentdata.Animation_Content_Specification) -> u32 {
    if output == nil {
        return u32(contentdata.Animation_Content_Status.Invalid_Output)
    }
    if state == nil || state^.julia_runtime_service == nil {
        return u32(contentdata.Animation_Content_Status.Missing_Invocation_Context)
    }
    context = state^.saved_context
    service := state^.julia_runtime_service
    value, expected_generation := animation_content_invocation_value(
        state, invocation.operation)
    // A rejected replacement may re-enter the old program before leaving the transaction.
    active := &service^.active_content_specification
    if invocation.operation == .Enter && value != nil &&
        invocation.animation_identity == active^.animation_identity &&
        invocation.runtime_generation == active^.runtime_generation_identity &&
        invocation.animation_generation == service^.animation_generation {
        value = active
        expected_generation = invocation.animation_generation
    }
    if value == nil {
        return u32(contentdata.Animation_Content_Status.Missing_Invocation_Context)
    }
    if value^.selection_revision == 0 {
        return u32(contentdata.Animation_Content_Status.Missing_Default)
    }
    if invocation.runtime_generation != value^.runtime_generation_identity ||
        invocation.animation_generation != expected_generation {
        return u32(contentdata.Animation_Content_Status.Stale_Generation)
    }
    if invocation.animation_identity != value^.animation_identity {
        return u32(contentdata.Animation_Content_Status.Identity_Mismatch)
    }
    output^ = value^
    return u32(contentdata.Animation_Content_Status.Ok)
}
