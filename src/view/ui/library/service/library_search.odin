package libraryservice

import bridgemodel "../../../../bridge/model"
import core "../../../../core"
import evidence_session "../../../../evidence/session"
import evidence_trace "../../../../evidence/trace"
import viewcontent "../../../content"
import contentstore "../../../../persistence/content"
import uuid "core:encoding/uuid"
import viewmodel "../../model"
import log "core:log"

Library_Search_Result_Acceptance :: enum {
    Rejected,
    Invalid_Query,
    Ready,
    Allocation_Failed,
}

// library_search_record_commit publishes one accepted display-owned search result.
library_search_record_commit :: proc(
    state: ^core.Euclid_General_State, returned_count, total_count: u32,
    more_available, suggestion_available: bool) {
    search := &state^.ui_runtime.library.search
    flags: evidence_trace.Flags
    correlation_kind := evidence_trace.Correlation_Kind.None
    if search^.scenario_correlation != 0 {
        flags += {.Required}
    }
    if search^.scenario_correlation != 0 {
        correlation_kind = .Scenario_Action
    }
    if more_available {
        flags += {.Truncated}
    }
    if suggestion_available {
        flags += {.Suggested}
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Library_Search_Committed,
            correlation_kind = correlation_kind,
            correlation = search^.scenario_correlation,
            generation = search^.scenario_correlation_generation,
            tick = search^.generation,
            revision = search^.index_generation,
            flags = flags,
            payload = {
                counts = {
                    first = returned_count,
                    second = total_count,
                },
            },
        })
    search^.committed_generation = search^.generation
    search^.scenario_correlation = 0
    search^.scenario_correlation_generation = 0
}

// library_search_record_clear_commit publishes immediate restoration of the full tree.
library_search_record_clear_commit :: proc(state: ^core.Euclid_General_State) {
    library_search_record_commit(state, 0, 0, false, false)
}

// library_search_add_visible_id appends one unique UUID to staged visibility.
library_search_add_visible_id :: proc(
    search: ^viewmodel.Library_Search_State,
    stable_id: uuid.Identifier) -> bool {
    for index in 0..<search^.staged_visible_id_count {
        if search^.staged_visible_ids[index] == stable_id {
            return true
        }
    }
    if !viewmodel.library_search_reserve_ids(
        search, true, search^.staged_visible_id_count + 1) {
        return false
    }
    search^.staged_visible_ids[search^.staged_visible_id_count] = stable_id
    search^.staged_visible_id_count += 1
    return true
}

// library_search_find_node resolves one built-in UUID against the current registry.
library_search_find_node :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    stable_id: uuid.Identifier) -> ^bridgemodel.Euclid_Julia_Animation_Interface {
    if ji == nil {
        return nil
    }
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        if node^.stable_id == stable_id {
            return node
        }
    }
    return nil
}

// library_search_add_result_path resolves one key and retains its complete ancestry.
library_search_add_result_path :: proc(
    search: ^viewmodel.Library_Search_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    key: ^viewcontent.Search_Document_Key) -> bool {
    if key == nil || key^.source_namespace != .Builtin {
        return true
    }
    stable_id, read_error := uuid.read(string(key^.document_id.bytes[:]))
    if read_error != .None {
        return true
    }
    node := library_search_find_node(ji, stable_id)
    for steps := 0; node != nil && steps < ji^.animation_count; steps += 1 {
        if !library_search_add_visible_id(search, node^.stable_id) {
            return false
        }
        node = node^.parent
    }
    return true
}

// library_search_accept_result updates only search and catalogue-owned state.
library_search_accept_result :: proc(
    search: ^viewmodel.Library_Search_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    result: ^viewcontent.Search_Query_Result) -> Library_Search_Result_Acceptance {
    if search == nil || result == nil ||
        result^.generation != search^.generation ||
        result^.index_generation != search^.index_generation {
        return .Rejected
    }
    if result^.status == .Invalid_Query {
        viewmodel.library_search_clear_results(search)
        search^.invalid_query = true
        return .Invalid_Query
    }
    if result^.status != .Ready {
        return .Rejected
    }
    search^.staged_visible_id_count = 0
    for index in 0..<int(result^.returned_count) {
        if !library_search_add_result_path(
            search, ji, &result^.document_keys[index]) {
            return .Allocation_Failed
        }
    }
    accepted_ids := search^.visible_ids
    search^.visible_ids = search^.staged_visible_ids
    search^.staged_visible_ids = accepted_ids
    search^.visible_id_count = search^.staged_visible_id_count
    search^.staged_visible_id_count = 0
    search^.active = search^.query_length > 0
    search^.invalid_query = false
    search^.total_match_count = result^.total_match_count
    search^.more_available = result^.more_available
    library_search_accept_suggestion(search, result)
    return .Ready
}

// library_search_accept_suggestion copies the bounded worker suggestion.
library_search_accept_suggestion :: proc(
    search: ^viewmodel.Library_Search_State,
    result: ^viewcontent.Search_Query_Result) {
    search^.suggestion_length = min(
        int(result^.suggestion_length), len(search^.suggestion))
    copy(search^.suggestion[:search^.suggestion_length],
        result^.suggestion_bytes[:search^.suggestion_length])
}

// library_search_commit_result accepts current worker output and records ready evidence.
library_search_commit_result :: proc(
    state: ^core.Euclid_General_State,
    result: ^viewcontent.Search_Query_Result) -> bool {
    if state == nil {
        return false
    }
    search := &state^.ui_runtime.library.search
    accepted := library_search_accept_result(
        search, state^.julia_interface, result)
    if accepted == .Ready {
        library_search_record_commit(state, u32(result^.returned_count),
            result^.total_match_count, result^.more_available,
            result^.suggestion_length > 0)
    } else if accepted == .Allocation_Failed {
        log.error("library_search_visibility_allocation_failed")
        return false
    }
    return accepted != .Rejected
}

// library_search_drain_results commits only current worker publications.
library_search_drain_results :: proc(
    state: ^core.Euclid_General_State, service: ^viewcontent.Content_Service) {
    for {
        result, received := viewcontent.content_service_try_receive(service)
        if !received {
            return
        }
        _ = library_search_commit_result(state, &result)
    }
}

// library_search_submit_current validates and nonblockingly submits current intent.
library_search_submit_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^viewcontent.Content_Service) -> bool {
    search := &state^.ui_runtime.library.search
    source := string(search^.query[:search^.query_length])
    compiled := contentstore.search_query_compile(source)
    if compiled.status != .Success {
        search^.invalid_query = true
        search^.query_dirty = false
        search^.submit_requested = false
        return false
    }
    request, valid := viewcontent.search_query_request_make(
        search^.generation, 0, source)
    if !valid || !viewcontent.content_service_try_submit(service, request) {
        return false
    }
    search^.invalid_query = false
    search^.query_dirty = false
    search^.submit_requested = false
    return true
}

// library_search_debounce_ready advances pending input and reports submission timing.
library_search_debounce_ready :: proc(
    search: ^viewmodel.Library_Search_State, frame_dt: f32) -> bool {
    if search == nil || !search^.query_dirty || search^.query_length == 0 {
        return false
    }
    search^.debounce_remaining_seconds = max(
        f32(0), search^.debounce_remaining_seconds - max(frame_dt, f32(0)))
    return search^.submit_requested || search^.debounce_remaining_seconds <= 0
}

// service_library_search advances debounce, submission, and result commitment.
service_library_search :: proc(
    state: ^core.Euclid_General_State,
    service: ^viewcontent.Content_Service,
    frame_dt: f32) {
    if state == nil || service == nil {
        return
    }
    search := &state^.ui_runtime.library.search
    search^.worker_available = true
    library_search_content_generation_changed(
        search, viewcontent.content_service_index_generation(service))
    library_search_drain_results(state, service)
    if library_search_debounce_ready(search, frame_dt) {
        _ = library_search_submit_current(state, service)
    }
}

// Requery retained intent against new content without accepting retired-index results.
library_search_content_generation_changed :: proc(
    search: ^viewmodel.Library_Search_State, generation: u64) {
    if search^.index_generation != 0 && search^.index_generation != generation {
        viewmodel.library_search_query_changed(search, 0)
    }
    search^.index_generation = generation
}