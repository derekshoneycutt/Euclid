package viewpresentation

import animation_model "../../core/animation"
import bridge "../../bridge"
import bridgemodel "../../bridge/model"
import presentation_model "../../bridge/presentation"
import core "../../core"
import dyncore "../../dynview/core"
import taskpool "../../taskpool"
import uipresentation "../ui/presentation"
import uiterminal "../ui/terminal"
import log "core:log"

#assert(presentation_model.PRESENTATION_MAX_COMPOSED_SOURCE_BYTES >=
    presentation_model.PRESENTATION_MAX_SOURCE_BYTES+
    animation_model.ANIMATION_NOTE_BUFFER_CAPACITY+2)

// Display-owned note identity excludes save acknowledgments and transient input geometry.
Presentation_Note_Revision :: struct {
    request_id, revision, generation: u64,
    ready, editing, on_top: bool,
}

// Immutable bounded body bytes and parser outputs outlive their shared-pool operation.
Presentation_Composition_Work :: struct {
    bytes: [presentation_model.PRESENTATION_MAX_COMPOSED_SOURCE_BYTES]u8,
    count: int,
    sources: [2]string,
    parses: [2]Presentation_Parse_Request,
    statuses: [2]dyncore.Dynview_Document_Status,
    results: [2]dyncore.Dynview_Parse_Result,
    body_count: int,
    has_notes: bool,
    revision, store_generation: u64,
    content: bridgemodel.View_Content_Ready,
    handle: taskpool.Task_Handle,
    submitted: bool,
}

// Native presentation owner retains producer bytes after the Julia envelope is returned.
Presentation_Composition :: struct {
    producer_bytes: [presentation_model.PRESENTATION_MAX_SOURCE_BYTES]u8,
    producer_count: int,
    producer: bridgemodel.View_Content_Ready,
    producer_present, producer_ready: bool,
    semantic_event_pending: bool,
    departure_pending: bool,
    note_revision: Presentation_Note_Revision,
    revision: u64,
    dirty: bool,
    work: Presentation_Composition_Work,
}

// Reading borrows only the current placement's note; authoring keeps the original-only pane.
presentation_composition_note_text :: proc(
    state: ^core.Euclid_General_State) -> string {
    if uiterminal.is_terminal_selected(state) ||
        state^.ui_runtime.library.collection_note.editing {
        return ""
    }
    return uipresentation.presentation_note_text(state)
}

// Copy accepted producer input before its transport envelope or visible slot is released.
presentation_composition_accept :: proc(
    runtime: ^Presentation_Runtime, content: bridgemodel.View_Content_Ready) {
    composition := &runtime^.composition
    assert(len(content.content.bytes) <= len(composition^.producer_bytes))
    copy(composition^.producer_bytes[:], content.content.bytes)
    composition^.producer_count = len(content.content.bytes)
    composition^.producer = content
    composition^.producer.content.bytes = nil
    composition^.producer_present = true
    composition^.producer_ready = false
    composition^.semantic_event_pending = false
    composition^.departure_pending = false
    composition^.revision += 1
}

// Retire native input identity without reclaiming a still-running worker's immutable bytes.
presentation_composition_retire :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    composition := &runtime^.composition
    composition^.producer_present = false
    composition^.producer_ready = false
    composition^.producer_count = 0
    composition^.semantic_event_pending = false
    composition^.note_revision = {}
    composition^.revision += 1
    composition^.dirty = true
    composition^.departure_pending = true
    if composition^.work.submitted {
        _ = taskpool.task_pool_cancel(
            &state^.simulation_executor^.pool, composition^.work.handle)
    }
}

// Identify presentation inputs independently of save acknowledgments and input geometry.
presentation_note_revision :: proc(
    state: ^core.Euclid_General_State) -> Presentation_Note_Revision {
    note := &state^.ui_runtime.library.collection_note
    return {
        note^.request_id, 0 if note^.editing else note^.revision, note^.generation,
        uipresentation.presentation_note_is_current(state),
        note^.editing, !note^.editing && note^.notes_on_top,
    }
}

// Observe unpublished owner work and note changes, rather than only Julia request completion.
presentation_composition_is_pending :: proc(runtime: ^Presentation_Runtime) -> bool {
    composition := &runtime^.composition
    return runtime^.active.submitted || runtime^.pending != nil ||
        composition^.work.submitted || composition^.dirty ||
        composition^.producer_present && !composition^.producer_ready ||
        runtime^.state != nil &&
            (presentation_note_revision(runtime^.state) != composition^.note_revision ||
             runtime^.state^.dynview.cache_access_state != .Display_Readable)
}

// Observe note-only changes and join immutable parses before scheduling newest composition.
presentation_service_composition :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    composition := &runtime^.composition
    revision := presentation_note_revision(state)
    if revision != composition^.note_revision {
        composition^.note_revision = revision
        composition^.revision += 1
        composition^.dirty = true
        composition^.departure_pending = true
    }
    presentation_composition_poll(state, runtime)
    if composition^.work.submitted || !composition^.dirty ||
        uiterminal.is_terminal_selected(state) ||
        state^.julia_runtime_service^.lifecycle != .Ready ||
        state^.julia_runtime_service^.reload_state != .Idle ||
        state^.julia_interface^.pending_animation_reset ||
        composition^.producer_present && !composition^.producer_ready {
        return
    }
    if !composition^.producer_present && presentation_composition_note_text(state) == "" &&
        !composition^.work.has_notes {
        composition^.dirty = false
        return
    }
    presentation_composition_prepare(state, runtime)
}

// Snapshot both ordered bodies into owner-bound storage before any asynchronous parse.
presentation_composition_prepare :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    composition := &runtime^.composition
    work := &composition^.work
    note := presentation_composition_note_text(state)
    producer := string(composition^.producer_bytes[:composition^.producer_count])
    work^.count = 0
    work^.body_count = 0
    work^.has_notes = len(note) > 0
    work^.revision = composition^.revision
    work^.store_generation = state^.dynview_documents.generation
    work^.content = composition^.producer
    if !composition^.producer_present {
        work^.content = {
            runtime_generation = state^.julia_runtime_service^.runtime_generation,
            animation_generation = state^.julia_runtime_service^.animation_generation,
            animation = state^.julia_interface^.current_animation,
            content = {
                mime = .Text_Latex,
            },
        }
    }
    if state^.ui_runtime.library.collection_note.notes_on_top {
        presentation_composition_append(work, note, .Text_Latex)
        presentation_composition_append(work, producer, work^.content.content.mime)
    } else {
        presentation_composition_append(work, producer, work^.content.content.mime)
        presentation_composition_append(work, note, .Text_Latex)
    }
    presentation_composition_schedule(state, runtime)
}

// Append exact body bytes with a copy separator, keeping TeX interpretations independent.
presentation_composition_append :: proc(
    work: ^Presentation_Composition_Work, source: string,
    mime: presentation_model.Presentation_Mime) {
    if len(source) == 0 {
        return
    }
    if work^.body_count > 0 {
        copy(work^.bytes[work^.count:], "\n\n")
        work^.count += 2
    }
    start := work^.count
    copy(work^.bytes[start:], transmute([]u8)source)
    work^.count += len(source)
    index := work^.body_count
    work^.sources[index] = string(work^.bytes[start:work^.count])
    work^.parses[index] = presentation_parse_key(
        {mime, transmute([]u8)work^.sources[index]}, work^.store_generation,
        work^.has_notes)
    work^.body_count += 1
}

// Resolve cached bodies first; submit at most one task for all missing body parses.
presentation_composition_schedule :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    work := &runtime^.composition.work
    missing := false
    for index in 0..<work^.body_count {
        parse := work^.parses[index]
        work^.statuses[index] = .Rejected
        if parse.valid {
            _, status := dyncore.document_store_lookup_keyed(
                &state^.dynview_documents, parse.source, parse.key)
            work^.statuses[index] = status
            missing = missing || status == .Not_Found
        }
    }
    if !missing {
        presentation_composition_publish(state, runtime)
        return
    }
    handle, outcome := taskpool.task_pool_submit(
        &state^.simulation_executor^.pool, presentation_composition_task, rawptr(work))
    if outcome == .Queued {
        work^.handle = handle
        work^.submitted = true
        runtime^.composition.dirty = false
    }
}

// Parse missing independent bodies without entering Julia or mutating the document store.
presentation_composition_task :: proc(
    payload: rawptr, token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    work := cast(^Presentation_Composition_Work)payload
    for index in 0..<work^.body_count {
        if taskpool.task_cancellation_requested(token) {
            return .Cancelled
        }
        if work^.statuses[index] != .Not_Found {
            continue
        }
        parse := work^.parses[index]
        work^.statuses[index] = dyncore.dynview_parse_build_keyed(
            parse.source, parse.key, work^.store_generation, &work^.results[index])
        if work^.statuses[index] != .Ok && work^.statuses[index] != .Rejected {
            return .Failed
        }
    }
    return .Succeeded
}

// Join and commit only a current composition; stale task storage is reused after join.
presentation_composition_poll :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    composition := &runtime^.composition
    work := &composition^.work
    if !work^.submitted {
        return
    }
    if work^.revision != composition^.revision {
        _ = taskpool.task_pool_cancel(&state^.simulation_executor^.pool, work^.handle)
    }
    if taskpool.task_pool_poll(
        &state^.simulation_executor^.pool, work^.handle) != .Ready {
        return
    }
    result, joined := taskpool.task_pool_wait(
        &state^.simulation_executor^.pool, work^.handle)
    work^.submitted = false
    if joined != .Joined || result == .Failed {
        log.error("collection_presentation_parse_failed")
        return
    }
    if result != .Succeeded || work^.revision != composition^.revision ||
        work^.store_generation != state^.dynview_documents.generation {
        return
    }
    for index in 0..<work^.body_count {
        if work^.parses[index].valid && work^.results[index].ready &&
            work^.results[index].key == work^.parses[index].key &&
            work^.results[index].generation == work^.store_generation {
            _, work^.statuses[index] = dyncore.document_store_commit(
                &state^.dynview_documents, work^.parses[index].source,
                &work^.results[index])
        }
    }
    presentation_composition_publish(state, runtime)
}

// Publish all bodies through one bounded native snapshot, with visible per-body parse fallback.
presentation_composition_publish :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    composition := &runtime^.composition
    work := &composition^.work
    documents: [2]dyncore.Dynview_Document
    bodies: [2]bridge.Presentation_Snapshot_Body
    for index in 0..<work^.body_count {
        bodies[index].source = work^.sources[index]
        parse := work^.parses[index]
        if parse.valid {
            handle, status := dyncore.document_store_lookup_keyed(
                &state^.dynview_documents, parse.source, parse.key)
            if status == .Ok {
                documents[index], status = dyncore.document_store_resolve(
                    &state^.dynview_documents, handle)
                bodies[index].document = &documents[index]
            }
            if status != .Ok && status != .Rejected {
                log.errorf(
                    "collection_presentation_document_unavailable status=%v", status)
                composition^.dirty = false
                return
            }
            if status == .Rejected {
                log.warn("collection_presentation_tex_rejected_rendering_literal")
            }
        }
    }
    presentation_composition_commit(state, runtime, bodies[:work^.body_count])
}

// Commit source and semantics together and retain producer event provenance separately.
presentation_composition_commit :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    bodies: []bridge.Presentation_Snapshot_Body) {
    composition := &runtime^.composition
    work := &composition^.work
    request: bridge.Presentation_Snapshot_Request = {
        content = work^.content,
        source = string(work^.bytes[:work^.count]),
        bodies = bodies,
    }
    if !work^.has_notes {
        request.bodies = nil
        if work^.body_count > 0 {
            request.mode = work^.parses[0].mode
            request.document = bodies[0].document
        } else {
            request.mode = .Plain
        }
    } else {
        request.content.content.mime = .Text_Latex
    }
    if !bridge.publish_presentation_snapshot(state, runtime^.staging, request) {
        log.error("collection_presentation_snapshot_capacity_or_publication_failed")
        composition^.dirty = false
        return
    }
    composition^.dirty = false
    if composition^.departure_pending && presentation_document_effects_visible(state) {
        presentation_effects_begin_departure(state, runtime, composition^.revision)
    }
    composition^.departure_pending = false
    presentation_document_arrival(state, runtime, work^.content.presentation_generation)
    if composition^.semantic_event_pending {
        presentation_record_semantic_published(state, work^.content)
        composition^.semantic_event_pending = false
    }
}

// Join composition work before presentation storage or its shared pool is destroyed.
presentation_composition_quiesce :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    work := &runtime^.composition.work
    if work^.submitted {
        _ = taskpool.task_pool_cancel(&state^.simulation_executor^.pool, work^.handle)
        _, joined := taskpool.task_pool_wait(
            &state^.simulation_executor^.pool, work^.handle)
        assert(joined == .Joined)
        work^.submitted = false
    }
}
