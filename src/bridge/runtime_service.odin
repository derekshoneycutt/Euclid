package bridge

import "base:runtime"
import "../core"
import dyncore "../dynview/core"
import "../julialib"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "core:fmt"
import "core:log"
import "core:os"
import "core:thread"
import "core:time"

// Julia_Runtime_Service is a single-owner command processor around the embedded Julia
// runtime. The display thread submits bounded requests and consumes typed events; only
// the persistent worker may call Julia. Snapshot and tick slots retain payloads outside
// the channels so event draining never determines whether completed data survives.

JULIA_REQUEST_CAPACITY :: core.JULIA_REQUEST_CAPACITY
JULIA_EVENT_CAPACITY :: core.JULIA_EVENT_CAPACITY
JULIA_REQUEST_LINK_POOL_CAPACITY :: core.JULIA_REQUEST_LINK_POOL_CAPACITY
JULIA_EVENT_LINK_POOL_CAPACITY :: core.JULIA_EVENT_LINK_POOL_CAPACITY
JULIA_EVIDENCE_HANDOFF_CAPACITY :: core.JULIA_EVIDENCE_HANDOFF_CAPACITY
SCRATCHPAD_ASYNC_SLOT_COUNT :: core.SCRATCHPAD_ASYNC_SLOT_COUNT
SCRATCHPAD_ASYNC_TEXT_CAPACITY :: core.SCRATCHPAD_ASYNC_TEXT_CAPACITY
VIEW_SNAPSHOT_SLOT_COUNT :: core.VIEW_SNAPSHOT_SLOT_COUNT
VIEW_SNAPSHOT_TEXT_CAPACITY :: core.VIEW_SNAPSHOT_TEXT_CAPACITY
ANIMATION_TICK_SLOT_COUNT :: core.ANIMATION_TICK_SLOT_COUNT
MAX_ACCUMULATED_ANIMATION_DT :: f32(0.25)

// Stack-local Julia host handle retained by the worker's persistent GC frame.
Julia_Runtime_Host :: struct {
    runtime: ^julialib.jl_value_t,
}

// One-root Julia GC frame installed for the complete initialized worker lifetime.
Julia_Runtime_Gc_Frame :: struct {
    encoded_root_count: uintptr,
    previous: ^julialib.jl_gcframe_t,
    root: rawptr,
}

//   Dispatch table mapping each Julia event kind to its completion handler.
//   Initialized and Invoke_Complete need no handler and map to nil.
JULIA_EVENT_HANDLERS ::
    [Julia_Event_Kind]proc(service: ^Julia_Runtime_Service, event: Julia_Event){
    .Initialized = nil,
    .Invoke_Complete = nil,
    .Scratchpad_Complete = julia_event_on_scratchpad,
    .Animation_Tick_Complete = julia_event_on_animation_tick,
    .Shutdown_Complete = julia_event_on_shutdown,
}

// Core owns service storage because Euclid_General_State holds a concrete service pointer.
// This package owns queue policy, worker behavior, publication, and lifecycle transitions.
Julia_Request_Kind :: core.Julia_Request_Kind
Julia_Event_Kind :: core.Julia_Event_Kind
Animation_Tick_Slot_State :: core.Animation_Tick_Slot_State
Animation_Tick_Slot :: core.Animation_Tick_Slot

View_Snapshot_Slot_State :: core.View_Snapshot_Slot_State
View_Snapshot :: core.View_Snapshot

View_Snapshot_Record_Payloads :: struct {
    commands: []core.Dynview_Command,
    math_programs: []core.Dynview_Math_Program,
    math_commands: []core.Dynview_Command,
    math_nodes: []core.Dynview_Math_Node,
    math_table_descriptors: []core.Dynview_Math_Table_Descriptor,
    document_text: []u8,
    documents: []core.Dynview_Document,
    document_blocks: []core.Dynview_Document_Block,
    document_inlines: []core.Dynview_Document_Inline,
    document_display_rows: []core.Dynview_Document_Display_Row,
}

View_Snapshot_Sealed_Records :: struct {
    commands: []core.Dynview_Command,
    programs: []core.Dynview_Math_Program,
    descriptors: []core.Dynview_Math_Table_Descriptor,
    math_commands: []core.Dynview_Command,
    nodes: []core.Dynview_Math_Node,
    document_text: []u8,
    documents: []core.Dynview_Document,
    document_blocks: []core.Dynview_Document_Block,
    document_inlines: []core.Dynview_Document_Inline,
    document_display_rows: []core.Dynview_Document_Display_Row,
}

// Presentation_Snapshot_Request groups one current canonical materialization request.
Presentation_Snapshot_Request :: struct {
    content: core.View_Content_Ready,
    source: string,
    mode: Presentation_Source_Mode,
    document: ^dyncore.Dynview_Document,
}

Scratchpad_Async_Kind :: core.Scratchpad_Async_Kind
Scratchpad_Async_Slot_State :: core.Scratchpad_Async_Slot_State
Scratchpad_Async_Slot :: core.Scratchpad_Async_Slot
Scratchpad_Input_Mode :: core.Scratchpad_Input_Mode
Julia_Lifecycle_State :: core.Julia_Lifecycle_State
Julia_Reload_State :: core.Julia_Reload_State
Julia_Task_Proc :: core.Julia_Task_Proc
Julia_Request :: core.Julia_Request
Julia_Event :: core.Julia_Event
Julia_Runtime_Service :: core.Julia_Runtime_Service

// Display-safe service diagnostics contain copied scalar state only. They never expose
// worker-owned Julia handles or require a Julia call to inspect service health.
Julia_Runtime_Diagnostics :: struct {
    lifecycle: Julia_Lifecycle_State,
    active_request_id: u64,
    active_request_kind: Julia_Request_Kind,
    failed_request_count: u64,
    last_failed_request_id: u64,
    last_failed_request_kind: Julia_Request_Kind,
    request_saturation_count: u64,
    reload_state: Julia_Reload_State,
    runtime_generation: u64,
}

//   Preserve bounded elapsed time while one replaceable tick is in flight.
// The cap prevents a delayed worker from replaying an unbounded simulation interval when
// it next accepts a tick.
coalesce_animation_tick :: proc(service: ^Julia_Runtime_Service, dt: f32) {
    service^.animation_accumulated_dt = min(
        service^.animation_accumulated_dt + dt, MAX_ACCUMULATED_ANIMATION_DT)
    service^.animation_ticks_coalesced += 1
}

//   Submit one fully prepared animation tick slot and finalize request bookkeeping.
submit_animation_tick_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot,
    slot_index: int, total_dt: f32) -> bool {
    request_id, sent := try_submit_julia_request(
        service, .Animation_Tick, generate_animation_tick_task,
        rawptr(slot), i32(slot_index))
    if !sent {
        rollback_animation_tick_slot(service, slot, total_dt)
        return false
    }
    assert(slot^.request_id == request_id)
    service^.animation_tick_pending = true
    service^.animation_ticks_submitted += 1
    service^.animation_queue_high_water = max(
        service^.animation_queue_high_water, u64(1))
    return true
}

//   Submit one bounded animation tick without blocking the display thread.
// The display thread snapshots query state before submission. On saturation, the slot is
// recycled and elapsed time is retained for the next request instead of partially lost.
try_request_animation_tick :: proc(state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    if service^.animation_tick_pending {
        coalesce_animation_tick(service, dt)
        return false
    }
    slot_index := reserve_animation_tick_slot(service)
    if slot_index < 0 {
        service^.animation_ticks_dropped += 1
        return false
    }

    total_dt := min(dt + service^.animation_accumulated_dt, MAX_ACCUMULATED_ANIMATION_DT)
    service^.animation_accumulated_dt = 0
    service^.animation_tick_sequence += 1
    fill_animation_tick_slot(
        service, &service^.animation_tick_slots[slot_index], state, total_dt)
    slot := &service^.animation_tick_slots[slot_index]
    return submit_animation_tick_slot(service, slot, slot_index, total_dt)
}

//   Populate one animation tick slot and snapshot its query state for the request.
fill_animation_tick_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot,
    state: ^core.Euclid_General_State, total_dt: f32) {

    slot^ = Animation_Tick_Slot{
        state = .Pending,
        request_id = service^.next_request_id,
        generation = service^.animation_generation,
        sequence = service^.animation_tick_sequence,
        host_state = state,
        animation = state^.julia_interface^.current_animation,
        dt = total_dt,
        submitted_at = time.tick_now(),
    }
    capture_animation_query_snapshot(state, &slot^.query_snapshot)
}

//   Recycle a tick slot and retain its elapsed time after a failed submission.
rollback_animation_tick_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot, total_dt: f32) {

    slot^.state = .Free
    service^.animation_accumulated_dt = total_dt
    service^.animation_ticks_dropped += 1
}

//   Commit one completed generation-matched animation batch at a frame boundary.
// Event draining updates service metadata, while completed slot storage remains authoritative.
// Every completed slot is recycled after selecting and attempting the newest valid batch.
publish_available_animation_tick :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    for {
        _, ok := try_receive_julia_event(service)
        if !ok {
            break
        }
    }
    slot_index := newest_completed_animation_tick_index(service)
    if slot_index < 0 {
        return false
    }
    slot := &service^.animation_tick_slots[slot_index]
    matches_current := animation_tick_matches_current(state, service, slot)
    committed := false
    reject_reason := ""
    if !matches_current {
        reject_reason = animation_tick_reject_reason(state, service, slot)
    } else if !commit_scene_command_batch(state, &slot^.scene_batch) {
        reject_reason = "invalid_command_batch"
    } else {
        committed = true
    }
    record_animation_tick_outcome(state, service, slot, committed, reject_reason)
    release_completed_animation_ticks(service)
    return committed
}

//   Record the commit/reject bookkeeping and trace event for one completed tick.
record_animation_tick_outcome :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot, committed: bool, reject_reason: string) {

    if committed {
        service^.animation_ticks_committed += 1
        service^.animation_last_committed_sequence = slot^.sequence
        latency_ms := time.duration_seconds(time.tick_since(slot^.submitted_at)) * 1000
        service^.animation_last_latency_ms = latency_ms
        service^.animation_max_latency_ms =
            max(service^.animation_max_latency_ms, latency_ms)
        _ = evidence_session.session_record(
            &state^.evidence_session, &state^.evidence_ring, {
                lane = .Transport,
                kind = .Animation_Tick_Committed,
                correlation_kind = .Animation_Tick,
                correlation = slot^.sequence,
                generation = service^.animation_generation,
                tick = state^.fixed_step,
                flags = {.Required},
            })
        return
    }
    service^.animation_ticks_stale += 1
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Transport,
            kind = .Animation_Tick_Rejected,
            correlation_kind = .Animation_Tick,
            correlation = slot^.sequence,
            generation = service^.animation_generation,
            tick = state^.fixed_step,
            flags = {.Failure},
        })
}

//   Classify why one completed tick was not committed against canonical state.
//
// Parameters:
//   - state: Global runtime state containing current animation selection.
//   - service: Julia runtime service with lifecycle counters.
//   - slot: Completed animation tick slot under evaluation.
//
// Returns:
//   - reason: Stable rejection reason token for trace payload.
animation_tick_reject_reason :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> string {

    if slot == nil || state == nil || state^.julia_interface == nil {
        return "invalid_command_batch"
    }
    if slot^.generation != service^.animation_generation {
        return "stale_generation"
    }
    if slot^.sequence <= service^.animation_last_committed_sequence {
        return "stale_sequence"
    }
    if state^.julia_interface^.pending_animation_reset {
        return "reset_pending"
    }
    if slot^.animation != state^.julia_interface^.current_animation ||
        slot^.animation != state^.julia_interface^.selected_animation {
        return "selection_mismatch"
    }
    return "invalid_command_batch"
}

//   Match one result against current lifecycle generation and selection identity.
// This prevents callbacks started before reset, reload, or selection changes from mutating
// the newly active canonical scene.
animation_tick_matches_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> bool {

    return slot^.generation == service^.animation_generation &&
        slot^.sequence > service^.animation_last_committed_sequence &&
        !state^.julia_interface^.pending_animation_reset &&
        slot^.animation == state^.julia_interface^.current_animation &&
        slot^.animation == state^.julia_interface^.selected_animation
}

//   Reserve free fixed storage for one worker-produced animation result.
// Slots are service-owned and recycled in place; no animation-tick allocation is permitted.
reserve_animation_tick_slot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Find the newest worker completion without relying on event payload retention.
// Older completed sequences may be superseded because only the latest canonical intent is
// useful at the next fixed-step publication boundary.
newest_completed_animation_tick_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_sequence: u64
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Complete && (newest_index < 0 ||
            slot.sequence > newest_sequence) {
            newest_index = slot_index
            newest_sequence = slot.sequence
        }
    }
    return newest_index
}

//   Release all consumed or superseded animation completion slots.
// Pending slots remain worker-owned and must not be recycled by the display thread.
release_completed_animation_ticks :: proc(service: ^Julia_Runtime_Service) {
    for &slot in service^.animation_tick_slots {
        if slot.state == .Complete {
            slot.state = .Free
        }
    }
}

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
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Dynview_Published,
            correlation_kind = .Animation,
            correlation = slot^.animation_generation,
            generation = slot^.animation_generation,
            revision = u64(slot^.generation),
            flags = {.Required},
        })
    record_scratchpad_completed(state, slot)
}

//   Publish the newest valid complete snapshot and recycle superseded storage.
publish_available_view_snapshot :: proc(
    state: ^core.Euclid_General_State, drain_events: bool = true) -> bool {
    if state == nil || state^.julia_runtime_service == nil {
        return false
    }
    service := state^.julia_runtime_service
    if drain_events {
        for {
            _, ok := try_receive_julia_event(service)
            if !ok {
                break
            }
        }
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
        record_scratchpad_completed(state, slot)
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
    staging: ^core.Dynview_System,
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
    slot^.request_id = request.content.request_id
    slot^.generation = service^.view_snapshot_generation
    slot^.runtime_generation = request.content.runtime_generation
    slot^.animation_generation = request.content.animation_generation
    slot^.scratchpad_request_id = request.content.scratchpad_request_id
    slot^.scratchpad_runtime_generation = request.content.runtime_generation
    slot^.host_state = state
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
    staging: ^core.Dynview_System,
    request: Presentation_Snapshot_Request) -> bool {
    block_id := i32(0)
    if dynview_push_command(staging, {
        kind = .Begin_Block,
        block_id = block_id,
        style_id = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
    }) != BRIDGE_STATUS_OK {
        return false
    }
    staging^.command_buffer.stream_open_block = true
    staging^.command_buffer.stream_open_block_id = block_id
    status := stage_presentation_content(staging, request, block_id)
    if status != BRIDGE_STATUS_OK || dynview_push_command(staging, {
        kind = .End_Block,
        block_id = block_id,
    }) != BRIDGE_STATUS_OK {
        return false
    }
    staging^.command_buffer.stream_open_block = false
    staging^.command_buffer.stream_open_block_id = -1
    return true
}

//   Stage semantic content when available, otherwise preserve exact literal bytes.
stage_presentation_content :: proc(
    staging: ^core.Dynview_System,
    request: Presentation_Snapshot_Request,
    block_id: i32) -> i32 {
    if request.document != nil && request.mode == .Math {
        return dynview_native_import_math(
            staging, request.document, dynview_native_document_styles(
                BRIDGE_DYNVIEW_STYLE_OUTPUT))
    }
    if request.document != nil && request.mode == .Document {
        return dynview_native_replay_document(
            staging, request.document, BRIDGE_DYNVIEW_STYLE_OUTPUT)
    }
    return stage_presentation_text_command(staging, request.source, block_id)
}

//   Append exact bytes and one text-bearing command without a C-string conversion.
stage_presentation_text_command :: proc(
    staging: ^core.Dynview_System,
    source: string,
    block_id: i32) -> i32 {
    offset, count: int
    status := dynview_append_text_payload(staging, source, &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    command := core.Dynview_Command{
        kind = .Text_Run,
        block_id = block_id,
        style_id = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        text_offset = offset,
        text_len = count,
    }
    return dynview_push_command(staging, command)
}

//   Record an accepted Scratchpad request only after its semantic view is visible.
record_scratchpad_completed :: proc(
    state: ^core.Euclid_General_State,
    slot: ^View_Snapshot) {

    if slot^.scratchpad_request_id == 0 ||
        slot^.scratchpad_runtime_generation != slot^.runtime_generation {
        return
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Scratchpad_Completed,
            correlation_kind = .Runtime_Request,
            correlation = slot^.scratchpad_request_id,
            generation = slot^.scratchpad_runtime_generation,
            revision = u64(slot^.generation),
            flags = {.Required},
        })
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

//   Clear worker-only Scratchpad completion state at a lifecycle boundary.
clear_scratchpad_completion_watermark :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    service^.worker_scratchpad_completed_request_id = 0
    service^.worker_scratchpad_completed_runtime_generation = 0
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

//   Validate all semantic bounds and require a closed, error-free command stream.
// Sealed aliases are checked before any copy into display-owned storage.
view_snapshot_is_valid :: proc(slot: ^View_Snapshot) -> bool {
    if slot == nil || !view_snapshot_text_payload_is_valid(
        &slot^.presentation_builder, slot^.presentation_bytes,
        VIEW_SNAPSHOT_TEXT_CAPACITY) || !view_snapshot_text_payload_is_valid(
        &slot^.command_text_builder, slot^.command_text,
        core.DYNVIEW_MAX_TEXT_BYTES) || !view_snapshot_text_payload_is_valid(
        &slot^.document_text_builder, slot^.document_text,
        core.DYNVIEW_MAX_DOCUMENT_BYTES) {
        return false
    }
    if !view_snapshot_record_payloads_are_valid(slot) {
        return false
    }
    if slot^.stream_has_error || slot^.stream_open_block {
        return false
    }
    for command in slot^.commands {
        if !view_snapshot_command_text_spans_valid(command, len(slot^.command_text)) {
            return false
        }
    }
    for command in slot^.math_commands {
        if !view_snapshot_command_text_spans_valid(command, len(slot^.command_text)) ||
            !view_snapshot_math_command_semantics_are_valid(command) ||
            (command.kind == .Matrix && (command.table_descriptor_index < 0 ||
            int(command.table_descriptor_index) >= len(slot^.math_table_descriptors))) {
            return false
        }
    }
    for descriptor in slot^.math_table_descriptors {
        if !view_snapshot_math_table_descriptor_is_valid(descriptor) {
            return false
        }
    }
    return view_snapshot_math_records_are_valid(slot) &&
        view_snapshot_documents_are_valid(slot)
}

//   Validate one sealed native table descriptor at the publication boundary.
view_snapshot_math_table_descriptor_is_valid :: proc(
    descriptor: core.Dynview_Math_Table_Descriptor) -> bool {
    return core.dynview_math_table_descriptor_is_valid(descriptor)
}

//   Validate atom and explicit-glue metadata before snapshot publication.
view_snapshot_math_command_semantics_are_valid :: proc(
    command: core.Dynview_Command) -> bool {

    atom := i32(command.math_atom_class)
    glue := i32(command.math_glue_kind)
    if atom < i32(core.Dynview_Math_Atom_Class.None) ||
        atom > i32(core.Dynview_Math_Atom_Class.Inner) ||
        glue < i32(core.Dynview_Math_Glue_Kind.None) ||
        glue > i32(core.Dynview_Math_Glue_Kind.Thin) {
        return false
    }
    if command.math_glue_kind != .None {
        return command.math_atom_class == .None
    }
    return command.math_atom_class != .None
}

//   Require every record slice to be the populated prefix of its sealed builder.
view_snapshot_record_payloads_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    return view_snapshot_record_payload_is_valid(
        &slot^.command_builder, slot^.commands, core.DYNVIEW_MAX_COMMANDS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_program_builder,
            slot^.math_programs, core.DYNVIEW_MAX_MATH_PROGRAMS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_table_descriptor_builder,
            slot^.math_table_descriptors, core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_command_builder,
            slot^.math_commands, core.DYNVIEW_MAX_MATH_COMMANDS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_node_builder,
            slot^.math_nodes, core.DYNVIEW_MAX_MATH_NODES) &&
        view_snapshot_record_payload_is_valid(&slot^.document_builder,
            slot^.documents, core.DYNVIEW_MAX_DOCUMENTS) &&
        view_snapshot_record_payload_is_valid(&slot^.document_block_builder,
            slot^.document_blocks, core.DYNVIEW_MAX_DOCUMENT_BLOCKS) &&
        view_snapshot_record_payload_is_valid(&slot^.document_inline_builder,
            slot^.document_inlines, core.DYNVIEW_MAX_DOCUMENT_INLINES) &&
        view_snapshot_record_payload_is_valid(&slot^.document_display_row_builder,
            slot^.document_display_rows, core.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS)
}

//   Require one record slice to alias its sealed builder's populated prefix.
view_snapshot_record_payload_is_valid :: proc(
    builder: ^$Builder/core.Bounded_Element_Builder($Element),
    payload: []Element, max_count: int) -> bool {

    if builder == nil || !builder.sealed || builder.count != len(payload) ||
        len(payload) > max_count {
        return false
    }
    return len(payload) == 0 || raw_data(payload) == raw_data(builder.storage)
}

//   Require one published byte slice to be the populated prefix of its sealed builder.
view_snapshot_text_payload_is_valid :: proc(
    builder: ^core.Bounded_Byte_Builder, payload: []u8, max_count: int) -> bool {

    if builder == nil || !builder.sealed || builder.count != len(payload) ||
        len(payload) > max_count {
        return false
    }
    return len(payload) == 0 || raw_data(payload) == raw_data(builder.storage)
}

//   Validate every text-bearing span in one semantic command against the sealed blob.
view_snapshot_command_text_spans_valid :: proc(
    command: core.Dynview_Command, text_count: int) -> bool {

    spans := [5][2]int{
        {command.text_offset, command.text_len},
        {command.script_base_text_offset, command.script_base_text_len},
        {command.script_sup_text_offset, command.script_sup_text_len},
        {command.script_sub_text_offset, command.script_sub_text_len},
        {command.radical_index_text_offset, command.radical_index_text_len},
    }
    for span in spans {
        if span[0] < 0 || span[1] < 0 || span[1] > text_count ||
            span[0] > text_count - span[1] {
            return false
        }
    }
    return true
}

//   Validate math program ranges and node-local text and child spans.
view_snapshot_math_records_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    for node in slot^.math_nodes {
        if !view_snapshot_span_is_valid(
            node.text_offset, node.text_len, len(slot^.command_text)) {
            return false
        }
    }
    for program in slot^.math_programs {
        if !view_snapshot_math_program_is_valid(slot, program) {
            return false
        }
        for node in slot^.math_nodes[
            program.node_start:program.node_start + program.node_count] {
            if !view_snapshot_math_node_is_valid(node, program) {
                return false
            }
        }
    }
    return true
}

//   Validate one math program and its root against populated snapshot records.
view_snapshot_math_program_is_valid :: proc(
    slot: ^View_Snapshot, program: core.Dynview_Math_Program) -> bool {

    if !program.valid || !view_snapshot_range_is_valid(
        program.command_start, program.command_count, len(slot^.math_commands)) ||
        !view_snapshot_range_is_valid(
            program.node_start, program.node_count, len(slot^.math_nodes)) ||
        !view_snapshot_span_is_valid(
            program.copy_text_offset, program.copy_text_len,
            len(slot^.command_text)) {
        return false
    }
    return program.node_count == 0 || view_snapshot_node_index_is_valid(
        program.root_node_index, program, false)
}

//   Validate one node's contiguous and kind-specific child references.
view_snapshot_math_node_is_valid :: proc(
    node: core.Dynview_Math_Node, program: core.Dynview_Math_Program) -> bool {

    if node.child_count < 0 || (node.child_count > 0 &&
        (!view_snapshot_node_index_is_valid(node.first_child, program, false) ||
        node.child_count > program.node_start + program.node_count -
            node.first_child)) {
        return false
    }
    switch node.kind {
    case .None, .Sequence, .Glyph_Run:
        return true
    case .Script:
        return view_snapshot_node_index_is_valid(node.base_child, program, false) &&
            view_snapshot_node_index_is_valid(
                node.superscript_child, program, true) &&
            view_snapshot_node_index_is_valid(node.subscript_child, program, true)
    case .Radical:
        return view_snapshot_node_index_is_valid(node.radicand_child, program, false) &&
            view_snapshot_node_index_is_valid(node.index_child, program, true)
    case .Fraction:
        return view_snapshot_node_index_is_valid(node.numerator_child, program, false) &&
            view_snapshot_node_index_is_valid(node.denominator_child, program, false)
    case .Stretch_Delimiter:
        return view_snapshot_node_index_is_valid(node.base_child, program, false)
    }
    return false
}

//   Validate a required or optional node index within one program-owned range.
view_snapshot_node_index_is_valid :: proc(
    index: int, program: core.Dynview_Math_Program, optional: bool) -> bool {

    if optional && index == -1 {
        return true
    }
    return index >= program.node_start &&
        index < program.node_start + program.node_count
}

//   Validate one nonnegative offset/count pair without overflowing its upper bound.
view_snapshot_span_is_valid :: proc(offset, count, total: int) -> bool {
    return offset >= 0 && count >= 0 && count <= total && offset <= total - count
}

//   Validate one record range; empty ranges permit the canonical zero start.
view_snapshot_range_is_valid :: proc(start, count, total: int) -> bool {
    return view_snapshot_span_is_valid(start, count, total)
}

//   Validate all semantic document ownership ranges and inline references.
view_snapshot_documents_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    for document in slot^.documents {
        if !view_snapshot_document_is_valid(slot, document) {
            return false
        }
        blocks := slot^.document_blocks[
            document.block_start:document.block_start + document.block_count]
        for block in blocks {
            if !view_snapshot_document_block_is_valid(document, block) {
                return false
            }
        }
        items := slot^.document_inlines[
            document.inline_start:document.inline_start + document.inline_count]
        for item in items {
            if !view_snapshot_document_inline_is_valid(slot, document, item) {
                return false
            }
        }
        rows := slot^.document_display_rows[document.display_row_start:
            document.display_row_start + document.display_row_count]
        for row in rows {
            if !view_snapshot_document_display_row_is_valid(slot, document, row) {
                return false
            }
        }
    }
    return true
}

//   Validate one document descriptor before slicing any child records.
view_snapshot_document_is_valid :: proc(
    slot: ^View_Snapshot, document: core.Dynview_Document) -> bool {

    return view_snapshot_span_is_valid(
        document.source_offset, document.source_count, len(slot^.document_text)) &&
        view_snapshot_span_is_valid(
            document.text_offset, document.text_count, len(slot^.document_text)) &&
        view_snapshot_range_is_valid(document.block_start, document.block_count,
            len(slot^.document_blocks)) &&
        view_snapshot_range_is_valid(document.inline_start, document.inline_count,
            len(slot^.document_inlines)) &&
        view_snapshot_range_is_valid(document.display_row_start,
            document.display_row_count, len(slot^.document_display_rows))
}

//   Validate one block's kind, source, and child range within its document.
view_snapshot_document_block_is_valid :: proc(
    document: core.Dynview_Document,
    block: core.Dynview_Document_Block) -> bool {

    kind := int(block.kind)
    alignment := int(block.alignment)
    return kind >= int(core.Dynview_Document_Block_Kind.Paragraph) &&
        kind <= int(core.Dynview_Document_Block_Kind.Display) &&
        alignment >= int(core.Dynview_Document_Alignment.Left) &&
        alignment <= int(core.Dynview_Document_Alignment.Right) &&
        view_snapshot_subspan_is_valid(document.source_offset,
            document.source_count, block.source_offset, block.source_count) &&
        view_snapshot_subspan_is_valid(document.inline_start,
            document.inline_count, block.inline_start, block.inline_count) &&
        view_snapshot_subspan_is_valid(document.display_row_start,
            document.display_row_count, block.display_row_start,
            block.display_row_count)
}

// Validate one display row's source range, programs, alignment, and number.
view_snapshot_document_display_row_is_valid :: proc(
    slot: ^View_Snapshot, document: core.Dynview_Document,
    row: core.Dynview_Document_Display_Row) -> bool {

    alignment := int(row.alignment)
    return view_snapshot_subspan_is_valid(document.source_offset,
        document.source_count, row.source_offset, row.source_count) &&
        row.primary_program_id >= 0 &&
        row.primary_program_id < len(slot^.math_programs) &&
        (row.secondary_program_id == -1 ||
            row.secondary_program_id >= 0 &&
            row.secondary_program_id < len(slot^.math_programs)) &&
        alignment >= int(core.Dynview_Document_Alignment.Left) &&
        alignment <= int(core.Dynview_Document_Alignment.Right) &&
        row.number >= 0
}

//   Validate one inline's semantic kind, byte spans, and optional math program.
view_snapshot_document_inline_is_valid :: proc(
    slot: ^View_Snapshot,
    document: core.Dynview_Document,
    item: core.Dynview_Document_Inline) -> bool {

    kind := int(item.kind)
    if kind < int(core.Dynview_Document_Inline_Kind.Text) ||
        kind > int(core.Dynview_Document_Inline_Kind.Forced_Break) ||
        !view_snapshot_subspan_is_valid(document.source_offset,
            document.source_count, item.source_offset, item.source_count) ||
        !view_snapshot_subspan_is_valid(document.text_offset,
            document.text_count, item.text_offset, item.text_count) {
        return false
    }
    if item.kind == .Math {
        root_style := int(item.root_style)
        return item.math_program_id >= 0 &&
            item.math_program_id < len(slot^.math_programs) &&
            root_style >= int(core.Dynview_Math_Style_Level.Display) &&
            root_style <= int(core.Dynview_Math_Style_Level.Text)
    }
    if item.math_program_id != -1 {
        return false
    }
    if item.kind == .Space {
        space_kind := int(item.space_kind)
        return space_kind >= int(core.Dynview_Document_Space_Kind.Breakable) &&
            space_kind <= int(core.Dynview_Document_Space_Kind.Controlled)
    }
    return item.kind != .Shape || item.shape.present
}

//   Require one child range to be fully contained by its owner range.
view_snapshot_subspan_is_valid :: proc(
    owner_start, owner_count, child_start, child_count: int) -> bool {

    if owner_start < 0 || owner_count < 0 || child_start < owner_start ||
        child_count < 0 {
        return false
    }
    relative_start := child_start-owner_start
    return child_count <= owner_count && relative_start <= owner_count-child_count
}

//   Return canonical presentation text only when it belongs to the active animation.
// The returned string aliases service-owned published slot storage until replacement.
current_view_snapshot_text :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return ""
    }
    service := state^.julia_runtime_service
    slot_index := service^.published_view_snapshot_index
    if slot_index < 0 {
        return ""
    }
    slot := &service^.view_snapshots[slot_index]
    if !view_snapshot_matches_current(state, service, slot) {
        return ""
    }
    return string(slot^.presentation_bytes)
}

//   Return a free snapshot slot that is neither pending nor displayed.
// Published slots are intentionally unavailable even after their semantic data is copied,
// because presentation bytes still alias the slot.
reserve_view_snapshot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.view_snapshots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Reserve one snapshot slot for lazy preparation by request-owned Julia work.
reserve_view_candidate :: proc(service: ^Julia_Runtime_Service) -> int {
    slot_index := reserve_view_snapshot(service)
    if slot_index < 0 {
        return -1
    }
    slot := &service^.view_snapshots[slot_index]
    if !prepare_view_snapshot_slot(slot) {
        return -1
    }
    slot^.state = .Reserved
    return slot_index
}

//   Compare complete semantic payloads without relying on hashes or generations.
published_view_snapshot_equals :: proc(
    service: ^Julia_Runtime_Service, candidate: ^View_Snapshot) -> bool {

    published_index := service^.published_view_snapshot_index
    if published_index < 0 {
        return false
    }
    published := &service^.view_snapshots[published_index]
    if published == candidate || published^.state != .Published {
        return false
    }
    return view_snapshot_slice_equal(
        published^.presentation_bytes, candidate^.presentation_bytes) &&
        published^.presentation_mime == candidate^.presentation_mime &&
        view_snapshot_slice_equal(published^.command_text, candidate^.command_text) &&
        view_snapshot_slice_equal(published^.commands, candidate^.commands) &&
        view_snapshot_slice_equal(published^.math_programs, candidate^.math_programs) &&
        view_snapshot_slice_equal(published^.math_table_descriptors,
            candidate^.math_table_descriptors) &&
        view_snapshot_slice_equal(published^.math_commands, candidate^.math_commands) &&
        view_snapshot_slice_equal(published^.math_nodes, candidate^.math_nodes) &&
        view_snapshot_slice_equal(published^.document_text, candidate^.document_text) &&
        view_snapshot_slice_equal(published^.documents, candidate^.documents) &&
        view_snapshot_slice_equal(
            published^.document_blocks, candidate^.document_blocks) &&
        view_snapshot_slice_equal(
            published^.document_inlines, candidate^.document_inlines) &&
        view_snapshot_slice_equal(published^.document_display_rows,
            candidate^.document_display_rows)
}

//   Return true when two payload slices have identical values in identical order.
view_snapshot_slice_equal :: proc(left, right: []$Element) -> bool {
    if len(left) != len(right) {
        return false
    }
    for value, index in left {
        if value != right[index] {
            return false
        }
    }
    return true
}

//   Clear generation payload metadata without copying the slot-owned arena owner.
reset_view_snapshot_slot_payload :: proc(slot: ^View_Snapshot) {
    slot^.candidate_committed = false
    slot^.request_id = 0
    slot^.generation = 0
    slot^.runtime_generation = 0
    slot^.animation_generation = 0
    slot^.scratchpad_request_id = 0
    slot^.scratchpad_runtime_generation = 0
    slot^.host_state = nil
    slot^.animation = nil
    slot^.presentation_mime = .Text_Plain
    slot^.presentation_bytes = nil
    slot^.command_text = nil
    slot^.command_revision = 0
    slot^.stream_has_error = false
    slot^.stream_open_block = false
    slot^.stream_open_block_id = 0
    slot^.commands = nil
    slot^.math_programs = nil
    slot^.math_table_descriptors = nil
    slot^.math_commands = nil
    slot^.math_nodes = nil
    slot^.document_text = nil
    slot^.documents = nil
    slot^.document_blocks = nil
    slot^.document_inlines = nil
    slot^.document_display_rows = nil
}

//   Initialize every future arena-backed payload builder for one free slot generation.
prepare_view_snapshot_builders :: proc(slot: ^View_Snapshot) -> bool {
    statuses := [12]core.Bounded_Builder_Status{
        core.bounded_byte_builder_init(
            &slot^.presentation_builder, VIEW_SNAPSHOT_TEXT_CAPACITY, &slot^.arena),
        core.bounded_byte_builder_init(
            &slot^.command_text_builder, core.DYNVIEW_MAX_TEXT_BYTES, &slot^.arena),
        core.bounded_byte_builder_init(
            &slot^.document_text_builder, core.DYNVIEW_MAX_DOCUMENT_BYTES, &slot^.arena),
        core.bounded_element_builder_init(
            &slot^.command_builder, core.DYNVIEW_MAX_COMMANDS, &slot^.arena),
        core.bounded_element_builder_init(
            &slot^.math_program_builder, core.DYNVIEW_MAX_MATH_PROGRAMS, &slot^.arena),
        core.bounded_element_builder_init(&slot^.math_table_descriptor_builder,
            core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS, &slot^.arena),
        core.bounded_element_builder_init(
            &slot^.math_command_builder, core.DYNVIEW_MAX_MATH_COMMANDS, &slot^.arena),
        core.bounded_element_builder_init(
            &slot^.math_node_builder, core.DYNVIEW_MAX_MATH_NODES, &slot^.arena),
        core.bounded_element_builder_init(
            &slot^.document_builder, core.DYNVIEW_MAX_DOCUMENTS, &slot^.arena),
        core.bounded_element_builder_init(&slot^.document_block_builder,
            core.DYNVIEW_MAX_DOCUMENT_BLOCKS, &slot^.arena),
        core.bounded_element_builder_init(&slot^.document_inline_builder,
            core.DYNVIEW_MAX_DOCUMENT_INLINES, &slot^.arena),
        core.bounded_element_builder_init(&slot^.document_display_row_builder,
            core.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS, &slot^.arena),
    }
    for status in statuses {
        if status != .Ok {
            return false
        }
    }
    return true
}

//   Reset and prepare arena storage only after the slot has returned to Free.
prepare_view_snapshot_slot :: proc(slot: ^View_Snapshot) -> bool {
    if slot == nil || slot^.state != .Free || !slot^.arena.initialized {
        return false
    }
    core.arena_owner_reset(&slot^.arena)
    reset_view_snapshot_slot_payload(slot)
    if prepare_view_snapshot_builders(slot) {
        return true
    }
    core.arena_owner_reset(&slot^.arena)
    slot^.presentation_builder = {}
    slot^.command_text_builder = {}
    slot^.command_builder = {}
    slot^.math_program_builder = {}
    slot^.math_table_descriptor_builder = {}
    slot^.math_command_builder = {}
    slot^.math_node_builder = {}
    slot^.document_text_builder = {}
    slot^.document_builder = {}
    slot^.document_block_builder = {}
    slot^.document_inline_builder = {}
    slot^.document_display_row_builder = {}
    return false
}

//   Initialize all fixed snapshot-slot arena owners in place.
view_snapshot_slots_init :: proc(service: ^Julia_Runtime_Service) -> bool {
    if service == nil {
        return false
    }
    for &slot, slot_index in service^.view_snapshots {
        if core.arena_owner_init(
            &slot.arena, core.VIEW_SNAPSHOT_ARENA_RESERVATION) {
            continue
        }
        for initialized_index in 0..<slot_index {
            core.arena_owner_destroy(&service^.view_snapshots[initialized_index].arena)
        }
        return false
    }
    return true
}

//   Destroy every snapshot-slot arena after Julia worker ownership has ended.
view_snapshot_slots_destroy :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    for &slot in service^.view_snapshots {
        core.arena_owner_destroy(&slot.arena)
    }
}

//   Generate canonical presentation and semantic data into snapshot-owned storage.
// The completed slot contains self-owned copies of all populated spans and can be
// published without consulting Julia.
build_generated_view_snapshot_payloads :: proc(
    slot: ^View_Snapshot,
    staging: ^core.Dynview_System,
    presentation: string) -> bool {
    if !build_view_snapshot_text_payloads(slot, presentation,
        staging^.command_buffer.text_bytes[:staging^.command_buffer.text_bytes_len]) {
        return false
    }
    slot^.command_revision = staging^.command_buffer.revision
    slot^.stream_has_error = staging^.command_buffer.has_stream_error
    slot^.stream_open_block = staging^.command_buffer.stream_open_block
    slot^.stream_open_block_id = staging^.command_buffer.stream_open_block_id
    cache := &staging^.compile_cache
    return build_view_snapshot_record_payloads(slot, {
        commands = staging^.command_buffer.commands[
            :staging^.command_buffer.command_count],
        math_programs = cache^.math_programs[:cache^.math_program_count],
        math_commands = cache^.math_commands[:cache^.math_command_count],
        math_nodes = cache^.math_nodes[:cache^.math_node_count],
        math_table_descriptors = cache^.math_table_descriptors[
            :cache^.math_table_descriptor_count],
        document_text = cache^.document_text[:cache^.document_text_count],
        documents = cache^.documents[:cache^.document_count],
        document_blocks = cache^.document_blocks[:cache^.document_block_count],
        document_inlines = cache^.document_inlines[:cache^.document_inline_count],
        document_display_rows = cache^.document_display_rows[
            :cache^.document_display_row_count],
    })
}

//   Copy and seal canonical presentation and semantic text as one snapshot candidate.
build_view_snapshot_text_payloads :: proc(
    slot: ^View_Snapshot, presentation: string, command_text: []u8) -> bool {

    presentation_count := min(len(presentation), VIEW_SNAPSHOT_TEXT_CAPACITY)
    presentation_status := core.bounded_byte_builder_append(
        &slot^.presentation_builder,
        transmute([]u8)presentation[:presentation_count])
    command_status := core.bounded_byte_builder_append(
        &slot^.command_text_builder, command_text)
    if presentation_status != .Ok || command_status != .Ok {
        return false
    }
    presentation_payload, presentation_seal_status :=
        core.bounded_byte_builder_seal(&slot^.presentation_builder)
    command_payload, command_seal_status :=
        core.bounded_byte_builder_seal(&slot^.command_text_builder)
    if presentation_seal_status != .Ok || command_seal_status != .Ok {
        return false
    }
    slot^.presentation_bytes = presentation_payload
    slot^.command_text = command_payload
    return true
}

//   Copy and seal all semantic record families as one complete snapshot candidate.
build_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Payloads) -> bool {

    if !append_view_snapshot_record_payloads(slot, payloads) {
        return false
    }
    sealed, ok := seal_view_snapshot_record_payloads(slot)
    if !ok {
        return false
    }
    slot^.commands = sealed.commands
    slot^.math_programs = sealed.programs
    slot^.math_table_descriptors = sealed.descriptors
    slot^.math_commands = sealed.math_commands
    slot^.math_nodes = sealed.nodes
    slot^.document_text = sealed.document_text
    slot^.documents = sealed.documents
    slot^.document_blocks = sealed.document_blocks
    slot^.document_inlines = sealed.document_inlines
    slot^.document_display_rows = sealed.document_display_rows
    return true
}

//   Append every semantic payload family before any builder is sealed.
append_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Payloads) -> bool {

    statuses := [10]core.Bounded_Builder_Status{
        core.bounded_byte_builder_append(
            &slot^.document_text_builder, payloads.document_text),
        core.bounded_element_builder_append(
            &slot^.command_builder, payloads.commands),
        core.bounded_element_builder_append(
            &slot^.math_program_builder, payloads.math_programs),
        core.bounded_element_builder_append(
            &slot^.math_table_descriptor_builder, payloads.math_table_descriptors),
        core.bounded_element_builder_append(
            &slot^.math_command_builder, payloads.math_commands),
        core.bounded_element_builder_append(
            &slot^.math_node_builder, payloads.math_nodes),
        core.bounded_element_builder_append(
            &slot^.document_builder, payloads.documents),
        core.bounded_element_builder_append(
            &slot^.document_block_builder, payloads.document_blocks),
        core.bounded_element_builder_append(
            &slot^.document_inline_builder, payloads.document_inlines),
        core.bounded_element_builder_append(&slot^.document_display_row_builder,
            payloads.document_display_rows),
    }
    for status in statuses {
        if status != .Ok {
            return false
        }
    }
    return true
}

//   Seal every appended semantic record family as one immutable payload set.
seal_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot) -> (View_Snapshot_Sealed_Records, bool) {

    commands, command_status :=
        core.bounded_element_builder_seal(&slot^.command_builder)
    programs, program_status :=
        core.bounded_element_builder_seal(&slot^.math_program_builder)
    descriptors, descriptor_status :=
        core.bounded_element_builder_seal(&slot^.math_table_descriptor_builder)
    math_commands, math_command_status :=
        core.bounded_element_builder_seal(&slot^.math_command_builder)
    nodes, node_status :=
        core.bounded_element_builder_seal(&slot^.math_node_builder)
    document_text, document_text_status :=
        core.bounded_byte_builder_seal(&slot^.document_text_builder)
    documents, document_status :=
        core.bounded_element_builder_seal(&slot^.document_builder)
    document_blocks, block_status :=
        core.bounded_element_builder_seal(&slot^.document_block_builder)
    document_inlines, inline_status :=
        core.bounded_element_builder_seal(&slot^.document_inline_builder)
    document_display_rows, row_status :=
        core.bounded_element_builder_seal(&slot^.document_display_row_builder)
    if command_status != .Ok || program_status != .Ok || descriptor_status != .Ok ||
        math_command_status != .Ok || node_status != .Ok ||
        document_text_status != .Ok || document_status != .Ok ||
        block_status != .Ok || inline_status != .Ok || row_status != .Ok {
        return {}, false
    }
    return {commands, programs, descriptors, math_commands, nodes,
        document_text, documents, document_blocks, document_inlines,
        document_display_rows}, true
}

//   Reset worker-only semantic emission storage for one generation.
// Capacity remains allocated; only populated lengths, errors, and cache validity are reset.
reset_view_snapshot_staging :: proc(staging: ^core.Dynview_System) {
    staging^.content = {}
    staging^.command_buffer.command_count = 0
    staging^.command_buffer.text_bytes_len = 0
    staging^.command_buffer.command_view = nil
    staging^.command_buffer.text_view = nil
    staging^.command_buffer.has_stream_error = false
    staging^.command_buffer.stream_open_block = false
    staging^.command_buffer.stream_open_block_id = -1
    staging^.command_buffer.revision += 1
    staging^.compile_cache.math_program_count = 0
    staging^.compile_cache.math_table_descriptor_count = 0
    staging^.compile_cache.math_command_count = 0
    staging^.compile_cache.math_node_count = 0
    staging^.compile_cache.document_text_count = 0
    staging^.compile_cache.document_count = 0
    staging^.compile_cache.document_block_count = 0
    staging^.compile_cache.document_inline_count = 0
    staging^.compile_cache.document_display_row_count = 0
    staging^.compile_cache.last_error_code = 0
    staging^.compile_cache.is_valid = false
}

//   Install immutable snapshot aliases before invalidating display compilation caches.
// The display thread retains the published slot until replacement or invalidation.
install_view_snapshot_content :: proc(
    slot: ^View_Snapshot, runtime: ^core.Dynview_System) {

    install_view_snapshot_aliases(slot, runtime)
    install_view_snapshot_buffer(slot, &runtime^.command_buffer)
    install_view_snapshot_cache_counts(slot, &runtime^.compile_cache)
    runtime^.pending_invalidation_mask |= 1
}

// Install immutable semantic aliases from one published snapshot.
install_view_snapshot_aliases :: proc(
    slot: ^View_Snapshot, runtime: ^core.Dynview_System) {

    runtime^.content = {
        revision = slot^.command_revision,
        presentation_mime = slot^.presentation_mime,
        presentation_bytes = slot^.presentation_bytes,
        has_stream_error = slot^.stream_has_error,
        stream_open_block = slot^.stream_open_block,
        stream_open_block_id = slot^.stream_open_block_id,
        commands = slot^.commands,
        text_bytes = slot^.command_text,
        math_programs = slot^.math_programs,
        math_table_descriptors = slot^.math_table_descriptors,
        math_commands = slot^.math_commands,
        math_nodes = slot^.math_nodes,
        document_text = slot^.document_text,
        documents = slot^.documents,
        document_blocks = slot^.document_blocks,
        document_inlines = slot^.document_inlines,
        document_display_rows = slot^.document_display_rows,
    }
}

// Install immutable command aliases from one published snapshot.
install_view_snapshot_buffer :: proc(
    slot: ^View_Snapshot, buffer: ^core.Dynview_Command_Buffer) {

    buffer^.revision = slot^.command_revision
    buffer^.command_count = len(slot^.commands)
    buffer^.text_bytes_len = len(slot^.command_text)
    buffer^.has_stream_error = slot^.stream_has_error
    buffer^.stream_open_block = slot^.stream_open_block
    buffer^.stream_open_block_id = slot^.stream_open_block_id
    buffer^.command_view = slot^.commands
    buffer^.text_view = slot^.command_text
}

// Install semantic family counts and invalidate derived cache state.
install_view_snapshot_cache_counts :: proc(
    slot: ^View_Snapshot, cache: ^core.Dynview_Compile_Cache) {

    cache^.math_program_count = len(slot^.math_programs)
    cache^.math_table_descriptor_count = len(slot^.math_table_descriptors)
    cache^.math_command_count = len(slot^.math_commands)
    cache^.math_node_count = len(slot^.math_nodes)
    cache^.document_text_count = len(slot^.document_text)
    cache^.document_count = len(slot^.documents)
    cache^.document_block_count = len(slot^.document_blocks)
    cache^.document_inline_count = len(slot^.document_inlines)
    cache^.document_display_row_count = len(slot^.document_display_rows)
    cache^.is_valid = false
    cache^.layout_is_valid = false
    cache^.copy_hit_target_count = 0
}

//   Return display-owned lifecycle, failure, and backpressure diagnostics.
// This is a scalar snapshot and does not synchronize with or invoke the Julia owner thread.
julia_runtime_diagnostics :: proc(
    service: ^Julia_Runtime_Service) -> Julia_Runtime_Diagnostics {
    if service == nil {
        return {}
    }
    return Julia_Runtime_Diagnostics{
        lifecycle = service^.lifecycle,
        active_request_id = service^.active_request_id,
        active_request_kind = service^.active_request_kind,
        failed_request_count = service^.failed_request_count,
        last_failed_request_id = service^.last_failed_request_id,
        last_failed_request_kind = service^.last_failed_request_kind,
        request_saturation_count = service^.request_saturation_count,
        reload_state = service^.reload_state,
        runtime_generation = service^.runtime_generation,
    }
}

//   Create both directional links, rolling back request ownership on event-link failure.
init_julia_runtime_channels :: proc(
    service: ^Julia_Runtime_Service) -> runtime.Allocator_Error {
    request_err := communication_link_init(
        &service^.request_link, JULIA_REQUEST_CAPACITY,
        JULIA_REQUEST_LINK_POOL_CAPACITY)
    if request_err != .None {
        return request_err
    }
    event_err := communication_link_init(
        &service^.event_link, JULIA_EVENT_CAPACITY,
        JULIA_EVENT_LINK_POOL_CAPACITY)
    if event_err != .None {
        communication_link_destroy(&service^.request_link)
        return event_err
    }
    return .None
}

//   Initialize display-independent state before starting the Julia owner worker.
initialize_julia_runtime_state :: proc(
    service: ^Julia_Runtime_Service,
    profile_path: string) {
    service^.next_request_id = 1
    service^.lifecycle = .Not_Started
    service^.published_view_snapshot_index = -1
    if len(profile_path) > 0 &&
        !evidence_profile.init_spall(&service^.profile, profile_path) {
        fmt.eprintln("Failed to initialize Julia worker profile output.")
        log.warn("julia_worker_profile_init_failed")
    }
}

//   Create the bounded channels, staging storage, and persistent Julia owner worker.
// On partial failure, resources are released in reverse construction order. The caller owns
// the returned service and must stop Julia before destroy_julia_runtime_service.
create_julia_runtime_service :: proc(profile_path: string = "") -> (
    ^Julia_Runtime_Service, runtime.Allocator_Error) {
    service := new(Julia_Runtime_Service)
    evidence_trace.ring_init(&service^.evidence_ring, .Julia_Host)
    channel_error := init_julia_runtime_channels(service)
    if channel_error != .None {
        free(service)
        return nil, channel_error
    }
    if !view_snapshot_slots_init(service) {
        communication_link_destroy(&service^.event_link)
        communication_link_destroy(&service^.request_link)
        free(service)
        return nil, .Out_Of_Memory
    }

    initialize_julia_runtime_state(service, profile_path)
    service^.worker =
        thread.create_and_start_with_data(rawptr(service), julia_runtime_worker)
    if service^.worker == nil {
        evidence_profile.destroy(&service^.profile)
        view_snapshot_slots_destroy(service)
        communication_link_destroy(&service^.event_link)
        communication_link_destroy(&service^.request_link)
        free(service)
        return nil, .Out_Of_Memory
    }

    log.infof("julia_service_created request_capacity=%d event_capacity=%d",
        JULIA_REQUEST_CAPACITY, JULIA_EVENT_CAPACITY)
    return service, .None
}

//   Report whether one cumulative occurrence count is a power of two.
// This bounds repeated diagnostics while retaining increasing pressure visibility.
diagnostic_occurrence_should_log :: proc(count: u64) -> bool {
    return count > 0 && count & (count - 1) == 0
}

//   Borrow one available Julia-owned egress envelope without blocking.
// The display owner must return every successful receive exactly once after all aliases
// into the envelope, including nested presentation bytes, are no longer in use.
try_receive_julia_egress :: proc(
    service: ^Julia_Runtime_Service) -> (^core.Julia_Host_Egress, bool) {
    if service == nil {
        return nil, false
    }
    return communication_link_try_recv(&service^.event_link)
}

//   Return one consumed Julia-owned egress envelope to its producer for reclamation.
return_julia_egress :: proc(
    service: ^Julia_Runtime_Service,
    message: ^core.Julia_Host_Egress) -> bool {
    return service != nil && message != nil &&
        communication_link_return(&service^.event_link, message)
}

//   Receive one available worker event without blocking the display thread.
// Successful receives also apply lifecycle and slot-completion metadata exactly once.
try_receive_julia_event :: proc(
    service: ^Julia_Runtime_Service) -> (Julia_Event, bool) {
    for {
        event_message, ok := try_receive_julia_egress(service)
        if !ok {
            return {}, false
        }
        event, is_event := event_message^.(Julia_Event)
        if is_event {
            _ = return_julia_egress(service, event_message)
            accept_julia_event(service, event)
            return event, true
        }
        defer_view_content(service, event_message)
    }
}

//   Retain only the newest presentation encountered by an event-only consumer.
defer_view_content :: proc(
    service: ^Julia_Runtime_Service,
    message: ^core.Julia_Host_Egress) {
    if service^.display_deferred_view_content != nil {
        _ = return_julia_egress(
            service, service^.display_deferred_view_content)
    }
    service^.display_deferred_view_content = message
}

//   Transfer the newest presentation deferred by an event-only display consumer.
take_deferred_view_content :: proc(
    service: ^Julia_Runtime_Service) -> ^core.Julia_Host_Egress {
    if service == nil {
        return nil
    }
    message := service^.display_deferred_view_content
    service^.display_deferred_view_content = nil
    return message
}

//   Destroy one Julia-owned egress envelope and any nested pool allocation.
destroy_julia_egress_message :: proc(
    service: ^Julia_Runtime_Service, message: ^core.Julia_Host_Egress) {
    content, is_content := message^.(core.View_Content_Ready)
    if is_content {
        communication_link_free_bytes(&service^.event_link, content.content.bytes)
    }
    message^ = {}
    communication_link_free(&service^.event_link, message)
}

//   Reclaim returned Julia egress envelopes on their producer thread.
drain_julia_egress_returns :: proc(service: ^Julia_Runtime_Service) -> int {
    count := 0
    for {
        message, ok := communication_link_try_take_return(&service^.event_link)
        if !ok {
            return count
        }
        destroy_julia_egress_message(service, message)
        count += 1
    }
}

//   Clone canonical presentation bytes into the Julia-owned egress pool.
allocate_view_content_message :: proc(
    state: ^core.Euclid_General_State, mime: core.Presentation_Mime,
    source: []u8) -> (^core.Julia_Host_Egress, runtime.Allocator_Error) {
    service := state^.julia_runtime_service
    message, message_error := communication_link_alloc(&service^.event_link)
    if message_error != .None {
        return nil, message_error
    }
    bytes, bytes_error := communication_link_alloc_bytes(
        &service^.event_link, len(source))
    if bytes_error != .None {
        communication_link_free(&service^.event_link, message)
        return nil, bytes_error
    }
    copy(bytes, source)
    generation := service^.presentation_generation + 1
    animation_generation := service^.animation_generation
    if service^.presentation_animation_generation_override != 0 {
        animation_generation = service^.presentation_animation_generation_override
    }
    animation := state^.julia_interface^.current_animation
    if service^.presentation_animation_override != nil {
        animation = service^.presentation_animation_override
    }
    message^ = core.Julia_Host_Egress(core.View_Content_Ready{
        request_id = service^.active_request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = animation_generation,
        presentation_generation = generation,
        animation = animation,
        scratchpad_request_id = service^.worker_scratchpad_completed_request_id,
        content = {mime = mime, bytes = bytes},
    })
    service^.presentation_generation = generation
    return message, .None
}

//   Enqueue canonical view content without blocking, retaining only the newest retry.
send_presented_text :: proc(
    state: ^core.Euclid_General_State, mime: core.Presentation_Mime,
    source: []u8) -> core.Communication_Send_Outcome {
    service := state^.julia_runtime_service
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    _ = drain_julia_egress_returns(service)
    message, allocation_error := allocate_view_content_message(state, mime, source)
    if allocation_error != .None {
        return .Allocation_Failed
    }
    if communication_link_try_send(&service^.event_link, message) {
        return .Sent
    }
    if service^.pending_view_content != nil {
        destroy_julia_egress_message(service, service^.pending_view_content)
    }
    service^.pending_view_content = message
    return .Queue_Full
}

//   Reliably transfer one retained presentation before its request completion event.
flush_pending_view_content :: proc(
    service: ^Julia_Runtime_Service) -> core.Communication_Send_Outcome {
    message := service^.pending_view_content
    if message == nil {
        return .Sent
    }
    if !communication_link_send(&service^.event_link, message) {
        destroy_julia_egress_message(service, message)
        service^.pending_view_content = nil
        return .Channel_Closed
    }
    service^.pending_view_content = nil
    return .Sent
}

//   Allocate and nonblockingly send one display-owned request envelope.
send_julia_request :: proc(
    service: ^Julia_Runtime_Service,
    request: Julia_Request) -> core.Communication_Send_Outcome {
    if service^.lifecycle == .Shutdown_Requested ||
        service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    _ = communication_link_drain_returns(&service^.request_link)
    message, allocation_error := communication_link_alloc(&service^.request_link)
    if allocation_error != .None {
        return .Allocation_Failed
    }
    message^ = core.Julia_Host_Ingress(request)
    if !communication_link_try_send(&service^.request_link, message) {
        communication_link_free(&service^.request_link, message)
        return .Queue_Full
    }
    return .Sent
}

//   Submit one lifecycle or compatibility request without blocking the caller.
// Request IDs advance only after successful queue insertion. Saturation is observable through
// diagnostics and leaves caller-owned task payloads untouched for retry or cleanup.
try_submit_julia_request :: proc(
    service: ^Julia_Runtime_Service, kind: Julia_Request_Kind,
    task: Julia_Task_Proc = nil, data: rawptr = nil,
    slot_index: i32 = -1) -> (u64, bool) {

    if service == nil {
        return 0, false
    }

    request_id := service^.next_request_id
    request := Julia_Request{
        kind = kind,
        request_id = request_id,
        task = task,
        data = data,
        slot_index = slot_index,
    }
    send_outcome := send_julia_request(service, request)
    if send_outcome != .Sent {
        service^.request_saturation_count += 1
        if diagnostic_occurrence_should_log(service^.request_saturation_count) {
            log.warnf("julia_request_saturated kind=%d outcome=%d count=%d",
                int(kind), int(send_outcome), service^.request_saturation_count)
        }
        return 0, false
    }

    service^.next_request_id += 1
    service^.active_request_id = request_id
    service^.active_request_kind = kind
    switch kind {
    case .Initialize:
        service^.lifecycle = .Starting
    case .Shutdown:
        service^.lifecycle = .Shutdown_Requested
    case .Invoke, .Scratchpad, .Animation_Tick:
    }
    return request_id, true
}

//   Apply one worker event to display-owned lifecycle and completion metadata.
// Scratchpad completions enter a bounded FIFO; view and animation events release their
// single-pending submission guards while payload slots retain the completed data.
accept_julia_event :: proc(service: ^Julia_Runtime_Service, event: Julia_Event) {
    if service^.evidence_session != nil {
        for evidence_index in 0..<event.evidence_count {
            evidence_session.session_accept_event(
                service^.evidence_session, event.evidence[evidence_index])
        }
    }
    if !event.succeeded {
        record_julia_event_failure(service, event)
    }
    if event.request_id == service^.active_request_id {
        service^.active_request_id = 0
    }

    handlers := JULIA_EVENT_HANDLERS
    handler := handlers[event.kind]
    if handler != nil {
        handler(service, event)
    }
}

//   Mark the service stopped when a shutdown completes successfully.
julia_event_on_shutdown :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    if event.succeeded {
        service^.lifecycle = .Stopped
        log.infof("julia_service_stopped request_id=%d generation=%d",
            event.request_id, service^.runtime_generation)
    }
}

//   Record a completed scratchpad slot for the polling consumer.
julia_event_on_scratchpad :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    record_completed_scratchpad_slot(service, event.slot_index)
}

//   Clear the animation-tick pending flag.
julia_event_on_animation_tick :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.animation_tick_pending = false
}

//   Record a failed Julia event and fail the lifecycle on terminal events.
record_julia_event_failure :: proc(
    service: ^Julia_Runtime_Service, event: Julia_Event) {
    service^.failed_request_count += 1
    service^.last_failed_request_id = event.request_id
    service^.last_failed_request_kind = event.request_kind
    log.errorf(
        "julia_request_failed request_id=%d request_kind=%d event_kind=%d generation=%d count=%d",
        event.request_id, int(event.request_kind), int(event.kind),
        service^.runtime_generation, service^.failed_request_count)
    if event.kind == .Initialized || event.kind == .Shutdown_Complete {
        service^.lifecycle = .Failed
    }
}

//   Enqueue one completed scratchpad slot for the polling consumer.
record_completed_scratchpad_slot :: proc(
    service: ^Julia_Runtime_Service, slot_index: i32) {
    completed_index := (service^.completed_scratchpad_head +
        service^.completed_scratchpad_count) % SCRATCHPAD_ASYNC_SLOT_COUNT
    assert(service^.completed_scratchpad_count < SCRATCHPAD_ASYNC_SLOT_COUNT)
    service^.completed_scratchpad_slots[completed_index] = slot_index
    service^.completed_scratchpad_count += 1
}

//   Publish readiness after startup registration and priming have completed.
// Initialization alone is insufficient: the display may submit normal work only after this.
mark_julia_runtime_ready :: proc(service: ^Julia_Runtime_Service) {
    assert(service != nil && service^.lifecycle == .Starting)
    service^.lifecycle = .Ready
    log.infof("julia_service_ready generation=%d", service^.runtime_generation)
}

//   Assert that Julia work is executing on the persistent owner thread.
// Call this at externally reachable task boundaries before invoking Julia or Julia-backed helpers.
assert_julia_runtime_owner :: proc(state: ^core.Euclid_General_State) {
    assert(state != nil && state^.julia_runtime_service != nil)
    service := state^.julia_runtime_service
    assert(os.get_current_thread_id() == service^.owner_thread_id,
        "Julia C API operation executed outside the Julia owner thread")
}

//   Run one temporary serialized bridge operation on the Julia owner thread.
// Calls made by the owner execute directly; all others block while consuming events until the
// correlated completion arrives. Unrelated events are still accepted during that wait.
invoke_julia_compatibility_task :: proc(
    state: ^core.Euclid_General_State, task: Julia_Task_Proc, data: rawptr) -> bool {

    if state == nil || state^.julia_runtime_service == nil || task == nil {
        return false
    }
    service := state^.julia_runtime_service
    if os.get_current_thread_id() == service^.owner_thread_id {
        return task(data)
    }

    request_id, sent := try_submit_julia_request(service, .Invoke, task, data)
    if !sent {
        return false
    }
    for {
        event_message, ok := communication_link_recv(&service^.event_link)
        if !ok {
            return false
        }
        event, is_event := event_message^.(Julia_Event)
        if !is_event {
            defer_view_content(service, event_message)
            continue
        }
        _ = communication_link_return(&service^.event_link, event_message)
        accept_julia_event(service, event)
        if event.kind == .Invoke_Complete && event.request_id == request_id {
            return event.succeeded
        }
    }
}

//   Join the stopped worker and release service-owned channels and staging storage.
// The shutdown request must already have completed; destroying a live worker would violate
// Julia ownership and may leave queued payloads unprocessed.
destroy_julia_runtime_service :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    if service^.worker != nil {
        thread.destroy(service^.worker)
    }
    evidence_profile.destroy(&service^.profile)
    view_snapshot_slots_destroy(service)
    _ = communication_link_drain_returns(&service^.request_link)
    _ = drain_julia_egress_returns(service)
    if service^.display_deferred_view_content != nil {
        destroy_julia_egress_message(
            service, service^.display_deferred_view_content)
    }
    if service^.pending_view_content != nil {
        destroy_julia_egress_message(service, service^.pending_view_content)
    }
    communication_link_destroy(&service^.event_link)
    communication_link_destroy(&service^.request_link)
    free(service)
}

//   Resolve Julia callbacks and register content into unpublished host state.
// This owner-thread task publishes no Ready lifecycle state; startup priming controls that step.
initialize_julia_state_task :: proc(data: rawptr) -> bool {
    state := cast(^core.Euclid_General_State)data
    assert_julia_runtime_owner(state)
    state^.saved_context = context
    prepare_julia_interface_generation(state^.julia_interface)
    if !julia_interface_handles_valid(state^.julia_interface) {
        clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    if !init_euclid_scripts(state) {
        clean_julia_interface_instance(state^.julia_interface)
        return false
    }
    return true
}

//   Construct the Julia-defined runtime host after the stable script is loaded.
//
// Returns:
//   - The unrooted host value, which the caller must root before another Julia allocation.
create_julia_runtime_host :: proc(
    state: ^core.Euclid_General_State) -> ^julialib.jl_value_t {

    if state == nil {
        return nil
    }
    constructor := julialib.jl_get_function(
        julialib.julia_main_module(), "create_euclid_runtime_host")
    if constructor == nil {
        return nil
    }
    host := julialib.jl_call1(
        constructor, julialib.jl_box_voidpointer(state))
    if host == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("create_euclid_runtime_host")
        return nil
    }
    return host
}

//   Initialize Julia and install an empty worker-lifetime runtime-host root.
initialize_julia_worker_host :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    frame: ^Julia_Runtime_Gc_Frame) -> bool {

    if !initiate_julia() {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    frame^ = Julia_Runtime_Gc_Frame{
        encoded_root_count = (1 << 2) | 1,
        previous = gc_stack^,
        root = rawptr(&host^.runtime),
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(frame)
    return true
}

//   Construct and validate the rooted runtime host after native state exists.
initialize_julia_runtime_host :: proc(
    service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host,
    state: ^core.Euclid_General_State) -> bool {

    if service == nil || host == nil || state == nil || host^.runtime != nil {
        return false
    }
    host^.runtime = create_julia_runtime_host(state)
    if host^.runtime == nil {
        return false
    }
    julialib.jl_gc_collect(.JL_GC_FULL)
    validator := julialib.jl_get_function(
        julialib.julia_main_module(), "is_euclid_runtime_host")
    valid_host := validator != nil &&
        julialib.jl_unbox_bool(julialib.jl_call1(validator, host^.runtime)) != 0 &&
        julialib.jl_exception_occurred() == nil
    if !valid_host {
        print_julia_exception("is_euclid_runtime_host")
        host^.runtime = nil
        return false
    }
    service^.runtime_host = host^.runtime
    return true
}

//   Remove the worker host root before shutting down Julia.
finalize_julia_worker_host :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    frame: ^Julia_Runtime_Gc_Frame) {

    service^.runtime_host = nil
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack != nil {
        gc_stack^ = frame^.previous
    }
    host^.runtime = nil
}

//   Ensure a non-initialize request has a constructed runtime host when eligible.
prepare_julia_request_host :: proc(
    service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host,
    request: Julia_Request) -> bool {

    if host^.runtime != nil {
        return true
    }
    if request.kind != .Invoke {
        return false
    }
    return initialize_julia_runtime_host(
        service, host, cast(^core.Euclid_General_State)request.data)
}

//   Select the completion kind for a request rejected before host construction.
reject_julia_request_without_host :: proc(
    request: Julia_Request, event: ^Julia_Event) {

    event^.succeeded = false
    switch request.kind {
    case .Invoke:
        event^.kind = .Invoke_Complete
    case .Scratchpad:
        event^.kind = .Scratchpad_Complete
    case .Animation_Tick:
        event^.kind = .Animation_Tick_Complete
    case .Initialize, .Shutdown:
    }
}

//   Execute one serialized worker request while borrowing the persistent host root.
execute_julia_worker_request :: proc(
    service: ^Julia_Runtime_Service, request: Julia_Request,
    host: ^Julia_Runtime_Host, frame: ^Julia_Runtime_Gc_Frame,
    initialized: ^bool) -> (Julia_Event, bool) {
    event := Julia_Event{
        request_kind = request.kind,
        request_id = request.request_id,
        slot_index = request.slot_index,
        succeeded = true,
    }
    evidence_profile.zone_begin(&service^.profile, "julia_request")
    shutting_down := false
    if request.kind == .Initialize {
        event.kind = .Initialized
        event.succeeded = !initialized^ &&
            initialize_julia_worker_host(service, host, frame)
        initialized^ = event.succeeded
    } else {
        host_ready := prepare_julia_request_host(service, host, request)
        if host_ready || request.kind == .Shutdown {
            shutting_down = dispatch_julia_request(service, request, &event)
        } else {
            reject_julia_request_without_host(request, &event)
        }
    }
    evidence_profile.zone_end(&service^.profile)
    return event, shutting_down
}

//   Allocate and reliably send one worker-owned event envelope.
send_julia_event :: proc(
    service: ^Julia_Runtime_Service,
    event: Julia_Event) -> core.Communication_Send_Outcome {
    _ = drain_julia_egress_returns(service)
    pending_outcome := flush_pending_view_content(service)
    if pending_outcome != .Sent {
        return pending_outcome
    }
    message, allocation_error := communication_link_alloc(&service^.event_link)
    if allocation_error != .None {
        return .Allocation_Failed
    }
    message^ = core.Julia_Host_Egress(event)
    if !communication_link_send(&service^.event_link, message) {
        destroy_julia_egress_message(service, message)
        return .Channel_Closed
    }
    return .Sent
}

//   Own the rooted Julia host stack frame and serialized requests until shutdown.
// The returned shutdown event is published only after this stack frame is gone.
julia_runtime_worker_run_host :: proc(
    service: ^Julia_Runtime_Service) -> (Julia_Event, bool) {

    worker_context := context
    host: Julia_Runtime_Host
    host_frame: Julia_Runtime_Gc_Frame
    initialized := false
    for {
        request_message, ok := communication_link_recv(&service^.request_link)
        if !ok {
            return {}, false
        }
        request, is_request := request_message^.(Julia_Request)
        if !is_request {
            _ = communication_link_return(&service^.request_link, request_message)
            return {}, false
        }

        event, shutting_down := execute_julia_worker_request(
            service, request, &host, &host_frame, &initialized)
        _ = communication_link_return(&service^.request_link, request_message)
        if shutting_down {
            attach_julia_request_evidence(service, request, &event)
            finalize_julia_worker_host(service, &host, &host_frame)
            end_julia()
            return event, true
        }
        attach_julia_request_evidence(service, request, &event)
        if send_julia_event(service, event) != .Sent {
            return {}, false
        }
        context = worker_context
        free_all(context.temp_allocator)
    }
}

//   Own Julia lifecycle and publish termination only after the rooted host frame is gone.
julia_runtime_worker :: proc(data: rawptr) {
    service := cast(^Julia_Runtime_Service)data
    service^.owner_thread_id = os.get_current_thread_id()
    evidence_profile.thread_name(&service^.profile, "julia-worker")
    log.info("julia_worker_started")
    shutdown_event, shutting_down := julia_runtime_worker_run_host(service)
    if !shutting_down {
        log.error("julia_worker_requests_closed_before_shutdown")
        return
    }
    if send_julia_event(service, shutdown_event) != .Sent {
        log.error("julia_worker_shutdown_event_send_failed")
        return
    }
    log.info("julia_worker_stopped")
}

//   Build one animation-tick completion event for the Julia channel handoff.
animation_tick_request_evidence :: proc(
    service: ^Julia_Runtime_Service, request: Julia_Request,
    event: ^Julia_Event) -> evidence_trace.Event {
    return {
            lane = .Transport,
            kind = event.succeeded ? .Animation_Tick_Accepted : .Animation_Tick_Rejected,
            correlation_kind = .Runtime_Request,
            correlation = request.request_id,
            generation = service.animation_generation,
            flags = event.succeeded ? {} : {.Failure},
            payload = {request = {
                status = event.succeeded ? 1 : 0,
                slot = u32(max(request.slot_index, 0)),
            }},
        }
}

//   Attach one owner-recorded Julia completion event to its channel handoff.
attach_julia_request_evidence :: proc(
    service: ^Julia_Runtime_Service, request: Julia_Request, event: ^Julia_Event) {
    if service == nil || event == nil || service.evidence_session == nil {
        return
    }
    evidence: evidence_trace.Event
    record_completion := true
    switch request.kind {
    case .Animation_Tick:
        evidence = animation_tick_request_evidence(service, request, event)
    case .Shutdown:
        evidence = {
            lane = .Lifecycle,
            kind = .Runtime_Shutdown_Complete,
            correlation_kind = .Runtime_Request,
            correlation = request.request_id,
            generation = service.runtime_generation,
            flags = {.Required},
        }
    case .Invoke:
        record_completion = false
    case .Initialize, .Scratchpad:
        return
    }
    if !record_completion || evidence_session.session_record(
        service.evidence_session, &service.evidence_ring, evidence) {
        event.evidence_count = evidence_trace.ring_drain(
            &service.evidence_ring, event.evidence[:])
    }
    if service.evidence_ring.count > 0 {
        evidence_session.session_mark_incomplete(service.evidence_session)
    }
}

//   Execute one worker request, filling its completion event.
//
// Returns:
//   - true when the request is Shutdown and the worker must exit after sending the event.
dispatch_julia_request :: proc(
    service: ^Julia_Runtime_Service,
    request: Julia_Request, event: ^Julia_Event) -> bool {

    switch request.kind {
    case .Initialize:
        event^.kind = .Initialized
    case .Invoke:
        event^.kind = .Invoke_Complete
        event^.succeeded = run_julia_request_task(request)
    case .Scratchpad:
        event^.kind = .Scratchpad_Complete
        event^.succeeded = run_julia_request_task(request)
    case .Animation_Tick:
        event^.kind = .Animation_Tick_Complete
        event^.succeeded = run_julia_request_task(request)
    case .Shutdown:
        assert(os.get_current_thread_id() == service^.owner_thread_id)
        clear_scratchpad_completion_watermark(service)
        event^.kind = .Shutdown_Complete
        return true
    }
    return false
}

//   Run a request's task callback when present, preserving the prior success state.
run_julia_request_task :: proc(request: Julia_Request) -> bool {
    if request.task == nil {
        return true
    }
    return request.task(request.data)
}