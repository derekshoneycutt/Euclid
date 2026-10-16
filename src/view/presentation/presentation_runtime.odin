package viewpresentation

import bridgemodel "../../bridge/model"
import dynviewmodel "../../dynview/model"
import presentation_model "../../bridge/presentation"
import bridge "../../bridge"
import core "../../core"
import dyncore "../../dynview/core"
import dynparse "../../dynview/parse"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import observe "../../evidence/observe"
import taskpool "../../taskpool"
import terminalservice "../terminal/service"
import viewfont "../font"
import uidust "../../particles/ui_dust"
import uipresentation "../ui/presentation"
import uiterminal "../ui/terminal"
import geometry "../../core/geometry"
import log "core:log"

// Presentation_Operation retains one producer envelope through parse task join.
Presentation_Operation :: struct {
    message: ^bridgemodel.Julia_Host_Egress,
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
    state: ^core.Euclid_General_State,
    active: Presentation_Operation,
    pending: ^bridgemodel.Julia_Host_Egress,
    newest_generation: u64,
    observed_runtime_generation: u64,
    observed_animation_generation: u64,
    observed_animation: rawptr,
    lifecycle_observed: bool,
    suppress_next_departure: bool,
    staging: ^dynviewmodel.Dynview_System,
    dust: uidust.Ui_Dust_System,
    // Ink publication serial at arrival start; later frames supply falling targets.
    arrival_ink_serial: u64,
    // Debug-scenario arrival override; nil uses the fixed product style.
    arrival_style: Maybe(uidust.Ui_Dust_Arrival_Style),
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
    presentation_generation: u64,
    origin: evidence_trace.Identity = {}) {

    correlation_kind := evidence_trace.Correlation_Kind.Animation
    correlation := animation_generation
    generation := animation_generation
    if origin.kind != .None {
        correlation_kind = origin.kind
        correlation = origin.id
        generation = origin.generation
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = kind,
            correlation_kind = correlation_kind,
            correlation = correlation,
            generation = generation,
            revision = presentation_generation,
            flags = {.Required},
        })
}

//   Record successful semantic publication under its originating action identity.
presentation_record_semantic_published :: proc(
    state: ^core.Euclid_General_State,
    content: bridgemodel.View_Content_Ready) {
    correlation_kind := evidence_trace.Correlation_Kind.Animation
    correlation := content.animation_generation
    generation := content.animation_generation
    if content.origin.kind != .None {
        correlation_kind = content.origin.kind
        correlation = content.origin.id
        generation = content.origin.generation
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Presentation_Semantic_Published,
            correlation_kind = correlation_kind,
            correlation = correlation,
            generation = generation,
            revision = content.presentation_generation,
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
    runtime^.staging = new(dynviewmodel.Dynview_System, context.allocator)
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
    content: presentation_model.Presented_Text,
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

//   Drain Julia egress and advance presentation work without blocking a frame.
service_presentation_runtime :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if state == nil || runtime == nil || state^.julia_runtime_service == nil ||
        state^.simulation_executor == nil {
        return
    }
    service := state^.julia_runtime_service
    presentation_sync_lifecycle(state, runtime)
    _ = bridge.drain_julia_egress(service)
    terminalservice.terminal_tick_publish(state)
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
        runtime^.observed_animation = presentation_current_animation(state)
        runtime^.lifecycle_observed = true
        return
    }
    if runtime^.observed_runtime_generation == service^.runtime_generation &&
        runtime^.observed_animation_generation == service^.animation_generation {
        return
    }
    presentation_lifecycle_effects(state, runtime)
    bridge.release_published_view_snapshot(state, service)
    superseded := runtime^.newest_generation != 0
    preserve_pending := presentation_pending_matches_current(state, runtime)
    if runtime^.pending != nil && !preserve_pending {
        _ = bridge.return_julia_egress(service, runtime^.pending)
        runtime^.pending = nil
    }
    presentation_cancel_active(state, runtime)
    if preserve_pending {
        return
    }
    if superseded {
        presentation_record_event(state, .Presentation_Superseded,
            service^.animation_generation, runtime^.newest_generation)
    }
    runtime^.newest_generation = 0
}

// presentation_lifecycle_effects records a lifecycle commit and applies its dust policy.
// Selection breaks the last drawn text into dust; reset and reload retire every effect
// and the retained ink, and suppress the next admitted replacement.
presentation_lifecycle_effects :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    service := state^.julia_runtime_service
    animation := presentation_current_animation(state)
    selected := runtime^.observed_runtime_generation == service^.runtime_generation &&
        animation != runtime^.observed_animation
    runtime^.observed_runtime_generation = service^.runtime_generation
    runtime^.observed_animation_generation = service^.animation_generation
    runtime^.observed_animation = animation
    if selected {
        presentation_effects_begin_departure(
            state, runtime, service^.animation_generation)
    } else {
        presentation_effects_retire(state, runtime)
    }
}

// presentation_effects_retire drops dust, the incoming fade, and retained ink so the
// next admitted replacement appears without breaking stale text.
presentation_effects_retire :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    runtime^.suppress_next_departure = true
    uidust.ui_dust_settle(&runtime^.dust)
    viewfont.cache_ink_capture_discard(&state^.font_cache)
}

// presentation_current_animation returns the selected animation identity, or nil.
presentation_current_animation :: proc(state: ^core.Euclid_General_State) -> rawptr {
    if state == nil || state^.julia_interface == nil {
        return nil
    }
    return state^.julia_interface^.current_animation
}

//   Report whether pre-completion lifecycle content became current at generation commit.
presentation_pending_matches_current :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime) -> bool {
    if runtime^.pending == nil {
        return false
    }
    content, ok := runtime^.pending^.(bridgemodel.View_Content_Ready)
    return ok && presentation_content_matches(state, content)
}

//   Retain only the newest current presentation and cancel superseded active work.
presentation_admit :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    message: ^bridgemodel.Julia_Host_Egress,
    content: bridgemodel.View_Content_Ready) {
    service := state^.julia_runtime_service
    if content.presentation_generation <= runtime^.newest_generation ||
        !presentation_content_matches(state, content) {
        _ = bridge.return_julia_egress(service, message)
        return
    }
    superseded := runtime^.newest_generation != 0
    runtime^.newest_generation = content.presentation_generation
    if runtime^.suppress_next_departure {
        uidust.ui_dust_cancel_arrival(&runtime^.dust)
        runtime^.suppress_next_departure = false
    } else {
        presentation_effects_begin_departure(
            state, runtime, content.presentation_generation)
    }
    bridge.release_published_view_snapshot(state, service)
    presentation_record_event(state, .Presentation_Cleared,
        content.animation_generation, content.presentation_generation, content.origin)
    if runtime^.pending != nil {
        _ = bridge.return_julia_egress(service, runtime^.pending)
    }
    runtime^.pending = message
    presentation_cancel_active(state, runtime)
    if superseded {
        presentation_record_event(state, .Presentation_Superseded,
            content.animation_generation, content.presentation_generation, content.origin)
    }
}

//   Start the newest pending value through a cache hit or one shared-pool task.
presentation_start_pending :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if runtime^.active.submitted || runtime^.pending == nil {
        return
    }
    message := runtime^.pending
    content, ok := message^.(bridgemodel.View_Content_Ready)
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
    message: ^bridgemodel.Julia_Host_Egress,
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
    content, has_content := message^.(bridgemodel.View_Content_Ready)
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
    content: bridgemodel.View_Content_Ready) {
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
        published := bridge.publish_presentation_snapshot(
            state, runtime^.staging, request)
        if published && request.document != nil {
            if presentation_reduced_motion_enabled(state) {
                uidust.ui_dust_settle(&runtime^.dust)
            } else {
                uidust.ui_dust_begin_arrival(
                    &runtime^.dust, request.content.presentation_generation,
                    presentation_arrival_style(runtime))
                runtime^.arrival_ink_serial =
                    viewfont.cache_visible_ink_serial(&state^.font_cache)
            }
            presentation_record_semantic_published(state, request.content)
        } else if published {
            uidust.ui_dust_cancel_arrival(&runtime^.dust)
        }
    }
}

// presentation_arrival_style returns the style the next accepted document uses.
presentation_arrival_style :: proc(
    runtime: ^Presentation_Runtime) -> uidust.Ui_Dust_Arrival_Style {
    if runtime == nil {
        return uidust.UI_DUST_ARRIVAL_STYLE
    }
    return runtime^.arrival_style.? or_else uidust.UI_DUST_ARRIVAL_STYLE
}

// presentation_set_arrival_style overrides the arrival style for later documents.
// Any active arrival is cancelled so its content appears whole immediately; the
// current document is not replayed and outgoing dust continues undisturbed.
presentation_set_arrival_style :: proc(
    runtime: ^Presentation_Runtime, style: uidust.Ui_Dust_Arrival_Style) {
    if runtime == nil {
        return
    }
    runtime^.arrival_style = style
    uidust.ui_dust_cancel_arrival(&runtime^.dust)
}

// presentation_effects_observe copies pointer-free dust facts for display evidence.
presentation_effects_observe :: proc(
    runtime: ^Presentation_Runtime) -> observe.Presentation_Effects {
    if runtime == nil {
        return {arrival_selection = uidust.UI_DUST_ARRIVAL_STYLE}
    }
    dust := &runtime^.dust
    return {
        arrival_selection = presentation_arrival_style(runtime),
        arrival_style = dust.incoming_style,
        arrival_active = dust.incoming_active,
        arrival_awaiting_targets = dust.incoming_awaiting_targets,
        arrival_particle_count = dust.arrival_count,
        departure_particle_count = dust.particle_count,
    }
}

// presentation_effects_begin_departure breaks the last drawn ink into dust.
// Samples are evenly strided across the bounded snapshot and then consumed so the
// same ink never departs twice; without samples, any dust already falling
// continues and only the incoming fade is cancelled.
presentation_effects_begin_departure :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    generation: u64) {
    if presentation_reduced_motion_enabled(state) {
        uidust.ui_dust_settle(&runtime^.dust)
        viewfont.cache_ink_capture_discard(&state^.font_cache)
        return
    }
    samples := viewfont.cache_visible_ink_samples(&state^.font_cache)
    if len(samples) == 0 {
        uidust.ui_dust_cancel_arrival(&runtime^.dust)
        return
    }
    visible_alpha := uidust.ui_dust_incoming_alpha(&runtime^.dust)
    uidust.ui_dust_begin_departure(&runtime^.dust, generation)
    count := min(len(samples), uidust.UI_DUST_MAX_PARTICLES)
    for index in 0..<count {
        sample := samples[((2*index + 1)*len(samples))/(2*count)]
        _ = uidust.ui_dust_emit(&runtime^.dust, sample.position,
            sample.color, sample.coverage, visible_alpha)
    }
    viewfont.cache_ink_capture_discard(&state^.font_cache)
    log.debugf("dynview_dust_departure samples=%d particles=%d",
        len(samples), runtime^.dust.particle_count)
}

// presentation_effects_begin_formation seeds falling ink or draw-in from the first
// presented frame of newly published content. Draw-in bins every sample into its
// reveal rows before emitting sparse accents. The retained ink stays published for
// a later departure; content without visible ink degrades to the fade.
presentation_effects_begin_formation :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    if !uidust.ui_dust_arrival_awaiting_targets(&runtime^.dust) ||
        viewfont.cache_visible_ink_serial(&state^.font_cache) ==
            runtime^.arrival_ink_serial {
        return
    }
    samples := viewfont.cache_visible_ink_samples(&state^.font_cache)
    if len(samples) == 0 {
        uidust.ui_dust_arrival_use_fade(&runtime^.dust)
        return
    }
    for sample in samples {
        uidust.ui_dust_reveal_include(&runtime^.dust, sample.position)
    }
    uidust.ui_dust_begin_formation(&runtime^.dust)
    count := min(len(samples), uidust.ui_dust_arrival_budget(&runtime^.dust))
    for index in 0..<count {
        sample := samples[((2*index + 1)*len(samples))/(2*count)]
        _ = uidust.ui_dust_emit_arrival(
            &runtime^.dust, sample.position, sample.color, sample.coverage)
    }
}

// presentation_effects_update advances visual effects under the effective motion policy.
presentation_effects_update :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    delta_seconds: f32, presentation: uipresentation.Presentation_Preparation,
    visual_signature: u64) {
    if state == nil || runtime == nil {
        return
    }
    resetting := state^.julia_interface != nil &&
        state^.julia_interface^.pending_animation_reset
    reloading := state^.julia_runtime_service != nil &&
        state^.julia_runtime_service^.reload_state != .Idle
    if resetting || reloading {
        presentation_effects_retire(state, runtime)
        return
    }
    presentation_effects_begin_formation(state, runtime)
    visual_presentation := presentation
    if visual_presentation.scroll.view_rect.width <= 0 ||
        visual_presentation.scroll.view_rect.height <= 0 {
        panel := geometry.Rectangle(state^.ui_runtime.layout.ui_regions.text_rect)
        visual_presentation = uipresentation.prepare_presentation_visual(state, panel)
    }
    visible := state^.ui_runtime.presentation.visible &&
        !uiterminal.is_terminal_selected(state)
    viewport := geometry.Rectangle(visual_presentation.scroll.view_rect)
    uidust.ui_dust_validate_context(
        &runtime^.dust, {
            visible = visible,
            reduced_motion = presentation_reduced_motion_enabled(state),
            viewport = viewport,
            scroll_y = presentation.scroll.scroll_y_out,
            visual_signature = visual_signature,
        })
    uidust.ui_dust_advance(&runtime^.dust, delta_seconds)
}

// presentation_reduced_motion_enabled combines the user and platform policies.
presentation_reduced_motion_enabled :: #force_inline proc(
    state: ^core.Euclid_General_State) -> bool {
    return state != nil &&
        (state^.ui_runtime.preferences.values.interface.reduce_motion ||
         state^.ui_runtime.platform_reduce_motion)
}

//   Match producer identities against the current display-owned runtime selection.
presentation_content_matches :: proc(
    state: ^core.Euclid_General_State,
    content: bridgemodel.View_Content_Ready) -> bool {
    service := state^.julia_runtime_service
    if service == nil || state^.julia_interface == nil {
        return false
    }
    if content.runtime_generation == service^.runtime_generation &&
        content.animation_generation == service^.animation_generation &&
        content.animation == state^.julia_interface^.current_animation {
        return true
    }
    slot := &service^.animation_lifecycle_slot
    return slot^.state == .Complete && slot^.outcome == .Committed &&
        content.request_id == slot^.request_id &&
        content.runtime_generation == service^.runtime_generation &&
        content.animation_generation == slot^.animation_generation + 1 &&
        content.animation == state^.julia_interface^.current_animation
}

//   Require the newest presentation and a quiescent current runtime generation.
presentation_content_is_current :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^Presentation_Runtime,
    content: bridgemodel.View_Content_Ready) -> bool {
    service := state^.julia_runtime_service
    return presentation_content_matches(state, content) &&
        content.presentation_generation == runtime^.newest_generation &&
        service^.lifecycle == .Ready && service^.reload_state == .Idle &&
        !state^.julia_interface^.pending_animation_reset
}

//   Cooperatively cancel active work once a newer or invalid generation exists.
presentation_cancel_stale_active :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    content, ok := runtime^.active.message^.(bridgemodel.View_Content_Ready)
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