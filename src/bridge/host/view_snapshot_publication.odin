package julia_host

import presentation_importer "../../view/presentation/importer"
import bridgemodel "../model"
import dynviewmodel "../../dynview/model"
import "../../core"
import dyncore "../../dynview/core"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"

//   Publish the latest complete semantic snapshot into display-owned dynview.
// Publication copies validated semantic spans, then recycles the previous published slot.
// Invalid or stale generations clear selection-incompatible display content.
publish_view_snapshot_slot :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot_index: int) {
    slot := &service^.view_snapshots[slot_index]
    install_view_snapshot_content(slot, &state^.dynview)
    if service^.published_view_snapshot_index >= 0 {
        previous := &service^.view_snapshots[service^.published_view_snapshot_index]
        previous^.state = .Free
    }
    slot^.state = .Published
    service^.published_view_snapshot_index = slot_index
    correlation_kind := evidence_trace.Correlation_Kind.Animation
    correlation := slot^.animation_generation
    correlation_generation := slot^.animation_generation
    if slot^.origin.kind != .None {
        correlation_kind = slot^.origin.kind
        correlation = slot^.origin.id
        correlation_generation = slot^.origin.generation
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Dynview_Published,
            correlation_kind = correlation_kind,
            correlation = correlation,
            generation = correlation_generation,
            revision = u64(slot^.generation),
            flags = {.Required},
        })
}

//   Publish the newest valid complete snapshot and recycle superseded storage.
publish_available_view_snapshot :: proc(
    state: ^core.Euclid_General_State, drain_events: bool = true) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := state^.julia_runtime_service
    if drain_events {
        _ = drain_julia_egress(service)
    }
    slot_index := newest_completed_view_snapshot_index(service)
    if slot_index < 0 {
        clear_stale_published_view(state, service)
        return false
    }

    slot := &service^.view_snapshots[slot_index]
    assert(slot^.state == .Complete)
    release_superseded_completed_view_snapshots(service, slot_index)
    if !view_snapshot_matches_current(state, service, slot) ||
        !view_snapshot_is_valid(slot) {
        slot^.state = .Free
        clear_stale_published_view(state, service)
        return false
    }
    if published_view_snapshot_equals(service, slot) {
        slot^.state = .Free
        return false
    }
    publish_view_snapshot_slot(state, service, slot_index)
    return true
}

//   Materialize one canonical presentation through the existing snapshot publisher.
// The caller owns staging and guarantees that any semantic document remains borrowed
// until this procedure returns.
publish_presentation_snapshot :: proc(
    state: ^core.Euclid_General_State,
    staging: ^dynviewmodel.Dynview_System,
    request: Presentation_Snapshot_Request) -> bool {
    if state == nil || staging == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := state^.julia_runtime_service
    slot_index := reserve_view_candidate(service)
    if slot_index < 0 {
        return false
    }
    slot := &service^.view_snapshots[slot_index]
    service^.view_snapshot_generation += 1
    slot^.state = .Pending
    slot^.origin = request.content.origin
    slot^.request_id = request.content.request_id
    slot^.generation = service^.view_snapshot_generation
    slot^.runtime_generation = request.content.runtime_generation
    slot^.animation_generation = request.content.animation_generation
    slot^.animation = request.content.animation
    slot^.presentation_mime = request.content.content.mime
    reset_view_snapshot_staging(staging)
    staging^.enabled = true
    if !stage_presentation_snapshot(staging, request) ||
        !build_generated_view_snapshot_payloads(slot, staging, request.source) ||
        !view_snapshot_is_valid(slot) {
        slot^.state = .Free
        return false
    }
    slot^.candidate_committed = true
    slot^.state = .Complete
    publish_view_snapshot_slot(state, service, slot_index)
    return true
}

//   Stage one output block whose canonical source is owned separately by the snapshot.
stage_presentation_snapshot :: proc(
    staging: ^dynviewmodel.Dynview_System,
    request: Presentation_Snapshot_Request) -> bool {
    block_id := i32(0)
    if presentation_importer.dynview_push_command(staging, {
        kind = .Begin_Block,
        block_id = block_id,
        style_id = dyncore.DYNVIEW_BLOCK_OUTPUT,
    }) != bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    staging^.command_buffer.stream_open_block = true
    staging^.command_buffer.stream_open_block_id = block_id
    status := stage_presentation_content(staging, request, block_id)
    if status != bridgemodel.BRIDGE_STATUS_OK ||
        presentation_importer.dynview_push_command(staging, {
            kind = .End_Block,
            block_id = block_id,
        }) != bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    staging^.command_buffer.stream_open_block = false
    staging^.command_buffer.stream_open_block_id = -1
    return true
}

//   Stage semantic content when available, otherwise preserve exact literal bytes.
stage_presentation_content :: proc(
    staging: ^dynviewmodel.Dynview_System,
    request: Presentation_Snapshot_Request,
    block_id: i32) -> i32 {
    if len(request.bodies) > 0 {
        for body in request.bodies {
            document_start := staging^.compile_cache.document_count
            status := presentation_importer.dynview_native_replay_document(
                staging, body.document, dyncore.DYNVIEW_STYLE_OUTPUT) if
                body.document != nil else
                presentation_importer.dynview_native_import_literal_document(
                    staging, body.source)
            if status != bridgemodel.BRIDGE_STATUS_OK {
                return status
            }
            for &document in staging^.compile_cache.documents[
                document_start:staging^.compile_cache.document_count] {
                document.separated_body = document_start > 0
            }
        }
        return bridgemodel.BRIDGE_STATUS_OK
    }
    if request.document != nil && request.mode == .Math {
        return presentation_importer.dynview_native_import_math(staging, request.document,
            presentation_importer.dynview_native_document_styles(
                dyncore.DYNVIEW_STYLE_OUTPUT))
    }
    if request.document != nil && request.mode == .Document {
        return presentation_importer.dynview_native_replay_document(
            staging, request.document, dyncore.DYNVIEW_STYLE_OUTPUT)
    }
    return stage_presentation_text_command(staging, request.source, block_id)
}

//   Append exact bytes and one text-bearing command without a C-string conversion.
stage_presentation_text_command :: proc(
    staging: ^dynviewmodel.Dynview_System,
    source: string,
    block_id: i32) -> i32 {
    offset, count: int
    status := presentation_importer.dynview_append_text_payload(
        staging, source, &offset, &count)
    if status != bridgemodel.BRIDGE_STATUS_OK {
        return status
    }
    command: dynviewmodel.Dynview_Command = {
        kind = .Text_Run,
        block_id = block_id,
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        text_offset = offset,
        text_len = count,
    }
    return presentation_importer.dynview_push_command(staging, command)
}

//   Find the newest completed slot without relying on event ordering or retention.
// Slot generation is authoritative because completion events only trigger display metadata.
newest_completed_view_snapshot_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_generation: u64
    for &slot, slot_index in service^.view_snapshots {
        if slot.state != .Complete {
            continue
        }
        if newest_index < 0 || slot.generation > newest_generation {
            newest_index = slot_index
            newest_generation = slot.generation
        }
    }
    return newest_index
}

//   Release older complete generations after selecting the newest publication.
// Pending and currently published slots retain their ownership states unchanged.
release_superseded_completed_view_snapshots :: proc(
    service: ^Julia_Runtime_Service, newest_index: int) {

    for &slot, slot_index in service^.view_snapshots {
        if slot_index != newest_index && slot.state == .Complete {
            slot.state = .Free
        }
    }
}

//   Keep previous semantic commands from appearing under a new selection.
// The old slot and display staging are released together so presentation and semantic content
// cannot refer to different animations.
clear_stale_published_view :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service) {

    published_index := service^.published_view_snapshot_index
    if published_index < 0 || state^.julia_interface == nil {
        return
    }
    published := &service^.view_snapshots[published_index]
    if view_snapshot_matches_current(state, service, published) {
        return
    }
    release_published_view_snapshot(state, service)
}

//   Clear display aliases before releasing the slot that owns their storage.
release_published_view_snapshot :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service) {

    if state == nil || service == nil {
        return
    }
    published_index := service^.published_view_snapshot_index
    reset_view_snapshot_staging(&state^.dynview)
    service^.published_view_snapshot_index = -1
    if published_index >= 0 {
        service^.view_snapshots[published_index].state = .Free
    }
}

//   Match one view snapshot against the active interface generation and animation.
// Runtime generation prevents recycled double-buffer addresses from validating stale work.
view_snapshot_matches_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^View_Snapshot) -> bool {

    return state != nil && service != nil && slot != nil &&
        state^.julia_interface != nil &&
        slot^.runtime_generation == service^.runtime_generation &&
        slot^.animation_generation == service^.animation_generation &&
        slot^.animation == state^.julia_interface^.current_animation
}
