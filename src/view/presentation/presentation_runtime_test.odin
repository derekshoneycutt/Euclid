package viewpresentation

import bridgemodel "../../bridge/model"
import dynviewmodel "../../dynview/model"
import animation_model "../../core/animation"
import presentation_model "../../bridge/presentation"
import bridge "../../bridge"
import core "../../core"
import taskpool "../../taskpool"
import runtime "base:runtime"
import testing "core:testing"
import thread "core:thread"
import viewfont "../font"
import geometry "../../core/geometry"
import uidust "../../particles/ui_dust"
import uipresentation "../ui/presentation"

// Presentation_Test_Fixture owns the heap-backed state used by Phase 4 tests.
Presentation_Test_Fixture :: struct {
    state: ^core.Euclid_General_State,
    service: ^bridgemodel.Julia_Runtime_Service,
    presentation: ^Presentation_Runtime,
}

//   Allocate the minimal typed state needed to exercise presentation admission.
presentation_test_fixture_create :: proc(t: ^testing.T) -> Presentation_Test_Fixture {
    state := new(core.Euclid_General_State, context.allocator)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    presentation := create_presentation_runtime()
    testing.expect(t, state != nil && service != nil && presentation != nil)
    link_error := bridge.init_julia_runtime_channels(service)
    testing.expect_value(t, link_error, runtime.Allocator_Error.None)
    state^.julia_runtime_service = service
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    state^.simulation_executor = new(core.Simulation_Executor, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    testing.expect(t, bridge.animation_storage_init(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents))
    testing.expect_value(t, bridge.animation_storage_begin_generation(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents, 3), animation_model.Animation_Memory_Status.Ok)
    testing.expect(t, taskpool.task_pool_init(
        &state^.simulation_executor^.pool, 1, 2))
    testing.expect(t, bridge.view_snapshot_slots_init(service))
    service^.runtime_generation = 3
    service^.animation_generation = 5
    service^.lifecycle = .Ready
    service^.reload_state = .Idle
    service^.published_view_snapshot_index = 0
    service^.view_snapshots[0].state = .Published
    state^.dynview.content.commands = []dynviewmodel.Dynview_Command{{
        kind = .Divider,
    }}
    return {
        state = state,
        service = service,
        presentation = presentation,
    }
}

//   Release all test-owned transport and runtime storage after returned envelopes drain.
presentation_test_fixture_destroy :: proc(
    fixture: Presentation_Test_Fixture) {
    state := fixture.state
    service := fixture.service
    presentation := fixture.presentation
    quiesce_presentation_runtime(state, presentation)
    for {
        message, returned := bridge.communication_link_try_take_return(
            &service^.event_link)
        if !returned {
            break
        }
        free(message)
    }
    destroy_presentation_runtime(presentation)
    taskpool.task_pool_destroy(&state^.simulation_executor^.pool)
    free(state^.simulation_executor)
    bridge.view_snapshot_slots_destroy(service)
    bridge.destroy_julia_runtime_channels(service)
    bridge.animation_storage_destroy(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents)
    free(state^.julia_interface)
    free(service, context.allocator)
    free(state)
}

//   Allocate one test envelope whose source bytes outlive presentation admission.
presentation_test_message :: proc(
    state: ^core.Euclid_General_State,
    generation: u64,
    bytes: []u8) -> ^bridgemodel.Julia_Host_Egress {
    message := new(bridgemodel.Julia_Host_Egress, context.allocator)
    message^ = bridgemodel.Julia_Host_Egress(bridgemodel.View_Content_Ready{
        runtime_generation = 3,
        animation_generation = 5,
        presentation_generation = generation,
        animation = state^.julia_interface^.current_animation,
        content = {
            mime = .Text_Latex,
            bytes = bytes,
        },
    })
    return message
}

//   Compare exact bytes without treating embedded zero as a terminator.
presentation_test_bytes_equal :: proc(left, right: []u8) -> bool {
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

//   Advance nonblocking polls until one test operation joins or the bound expires.
presentation_test_wait_for_idle :: proc(
    state: ^core.Euclid_General_State,
    presentation: ^Presentation_Runtime) {
    for _ in 0..<100000 {
        presentation_poll_active(state, presentation)
        if !presentation^.active.submitted {
            return
        }
        thread.yield()
    }
}

//   Verify literal staging preserves embedded zero bytes for visible text.
@(test)
presentation_literal_staging_preserves_exact_bytes :: proc(t: ^testing.T) {
    staging := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(staging)
    staging^.enabled = true
    source_bytes: []u8 = {'a', 0, '\\', 'b'}
    source := transmute(string)source_bytes

    testing.expect(t, bridge.stage_presentation_snapshot(staging, {
        source = source,
        mode = .Plain,
    }))
    testing.expect_value(t, staging^.command_buffer.command_count, 3)
    text_command := staging^.command_buffer.commands[1]
    testing.expect_value(t, text_command.kind, dynviewmodel.Dynview_Command_Kind.Text_Run)
    testing.expect(t, presentation_test_bytes_equal(
        staging^.command_buffer.text_bytes[
            text_command.text_offset:text_command.text_offset+text_command.text_len],
        source_bytes))
}

//   Verify admission retains only the newest message and clears published aliases.
@(test)
presentation_admission_is_bounded_and_clears_visible_state :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    first_bytes: []u8 = {'$', 'x', '$'}
    second_bytes: []u8 = {'$', 'y', '$'}
    first := presentation_test_message(state, 11, first_bytes)
    second := presentation_test_message(state, 12, second_bytes)

    first_content, _ := first^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, first, first_content)
    testing.expect(t, presentation^.pending == first)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)

    second_content, _ := second^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, second, second_content)
    testing.expect(t, presentation^.pending == second)
    testing.expect_value(t, presentation^.newest_generation, u64(12))
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == first)
    free(returned)
}

// Verify accepted replacement copies the last presented samples into owned dust.
@(test)
presentation_admission_starts_bounded_departure :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    viewfont.cache_ink_capture_begin(&state^.font_cache)
    viewfont.cache_ink_capture_sample(
        &state^.font_cache, {20, 30}, {70, 130, 180, 255}, 255, true)
    viewfont.cache_ink_capture_sample(
        &state^.font_cache, {40, 50}, {80, 160, 240, 255}, 192)
    viewfont.cache_ink_capture_mark_drawn(&state^.font_cache)
    viewfont.cache_ink_capture_publish(&state^.font_cache)
    bytes: []u8 = {'$', 'x', '$'}
    message := presentation_test_message(state, 13, bytes)
    content, _ := message^.(bridgemodel.View_Content_Ready)

    presentation_admit(state, presentation, message, content)

    testing.expect_value(t, presentation^.dust.particle_count, 2)
    testing.expect_value(t, presentation^.dust.particles.pos_x[0], f32(20))
    testing.expect_value(t, presentation^.dust.particles.pos_y[0], f32(30))
    testing.expect_value(t, presentation^.dust.particles.color[0],
        dynviewmodel.Color{70, 130, 180, 255})
    style := presentation^.dust.particles.ink_style[0]
    testing.expect(t, style.authored)
    testing.expect_value(t, style.monochrome, dynviewmodel.Color{185, 185, 185, 255})
    testing.expect_value(t, style.increased, dynviewmodel.Color{212, 212, 212, 255})
    testing.expect(t, !presentation^.dust.particles.ink_style[1].authored)
    state^.ui_runtime.preferences.values.interface.reduce_motion = true
    next := presentation_test_message(state, 14, bytes)
    next_content, _ := next^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, next, next_content)
    testing.expect_value(t, presentation^.dust.particle_count, 0)
    testing.expect(t, !presentation^.dust.incoming_active)
}

// Verify outgoing dust remains active while replacement content is blank.
@(test)
presentation_departure_survives_blank_frame_and_scroll_reset :: proc(
    t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    state^.ui_runtime.presentation.visible = true
    viewport: geometry.Rectangle = {10, 20, 200, 120}
    uidust.ui_dust_validate_context(&presentation^.dust, {
        visible = true,
        viewport = viewport,
        scroll_y = 40,
        visual_signature = 1,
    })
    uidust.ui_dust_begin_departure(&presentation^.dust, 23)
    testing.expect(t, uidust.ui_dust_emit(
        &presentation^.dust, {30, 50}, {240, 160, 80, 255}, 255, 1))
    blank_frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = viewport,
            scroll_y_out = 0,
        },
    }

    presentation_effects_update(state, presentation, 0.016, blank_frame, 1)

    testing.expect_value(t, presentation^.dust.particle_count, 1)
    testing.expect(t, presentation^.dust.particles.pos_y[0] > 50)
}

// Publish one drawn ink frame so the visible-ink serial advances.
presentation_test_publish_ink :: proc(
    state: ^core.Euclid_General_State, positions: []geometry.Vector2) {
    viewfont.cache_ink_capture_begin(&state^.font_cache)
    for position in positions {
        viewfont.cache_ink_capture_sample(
            &state^.font_cache, position, {80, 160, 240, 255}, 255)
    }
    viewfont.cache_ink_capture_mark_drawn(&state^.font_cache)
    viewfont.cache_ink_capture_publish(&state^.font_cache)
}

// Verify falling ink waits for new samples, targets them, and retains ink.
@(test)
presentation_formation_targets_first_new_ink :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    presentation_test_publish_ink(state, {{5, 5}})
    state^.ui_runtime.presentation.visible = true
    uidust.ui_dust_begin_arrival(&presentation^.dust, 50, .Falling_Ink)
    presentation^.arrival_ink_serial =
        viewfont.cache_visible_ink_serial(&state^.font_cache)
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 200, 120},
        },
    }

    presentation_effects_update(state, presentation, 0.016, frame, 1)
    testing.expect(t, uidust.ui_dust_arrival_awaiting_targets(&presentation^.dust))
    testing.expect_value(t, presentation^.dust.arrival_count, 0)

    presentation_test_publish_ink(state, {{30, 40}, {60, 70}})
    presentation_effects_update(state, presentation, 0.016, frame, 1)
    testing.expect(t, !uidust.ui_dust_arrival_awaiting_targets(&presentation^.dust))
    testing.expect_value(t, presentation^.dust.arrival_count, 2)
    testing.expect_value(t, presentation^.dust.particles.target_x[0], f32(30))
    testing.expect_value(t, presentation^.dust.particles.target_y[1], f32(70))
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 2)
}

// Verify draw-in bins new ink into reveal rows and emits contact accents.
@(test)
presentation_formation_draws_in_first_new_ink :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    state^.ui_runtime.presentation.visible = true
    uidust.ui_dust_begin_arrival(&presentation^.dust, 52, .Draw_In)
    presentation^.arrival_ink_serial =
        viewfont.cache_visible_ink_serial(&state^.font_cache)
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 200, 120},
        },
    }

    presentation_effects_update(state, presentation, 0.016, frame, 1)
    testing.expect_value(t, uidust.ui_dust_incoming_alpha(&presentation^.dust), f32(0))
    presentation_test_publish_ink(state, {{30, 20}, {90, 20}, {40, 80}})
    presentation_effects_update(state, presentation, 0.016, frame, 1)

    testing.expect(t, uidust.ui_dust_reveal_active(&presentation^.dust))
    testing.expect_value(t, presentation^.dust.reveal_row_count, 2)
    testing.expect_value(t, presentation^.dust.reveal_rows[0].right, f32(90))
    testing.expect_value(t, presentation^.dust.arrival_count, 3)
    testing.expect_value(t, uidust.ui_dust_incoming_alpha(&presentation^.dust), f32(1))
}

// Verify content without visible ink degrades falling ink to the fade.
@(test)
presentation_formation_without_ink_uses_fade :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    state^.ui_runtime.presentation.visible = true
    uidust.ui_dust_begin_arrival(&presentation^.dust, 51, .Falling_Ink)
    presentation^.arrival_ink_serial =
        viewfont.cache_visible_ink_serial(&state^.font_cache)
    presentation_test_publish_ink(state, {})
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 200, 120},
        },
    }

    presentation_effects_update(state, presentation, 0.016, frame, 1)

    testing.expect_value(t, presentation^.dust.incoming_style,
        uidust.Ui_Dust_Arrival_Style.Fade)
    testing.expect_value(t, presentation^.dust.arrival_count, 0)
    testing.expect(t, uidust.ui_dust_incoming_alpha(&presentation^.dust) > 0)
}

// Verify the arrival override defaults to the product style, cancels an active
// arrival without disturbing departure dust, and is reported by observation.
@(test)
presentation_arrival_style_override_cancels_active_arrival :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation := fixture.presentation
    testing.expect_value(t, presentation_arrival_style(presentation),
        uidust.UI_DUST_ARRIVAL_STYLE)
    testing.expect_value(t, presentation_arrival_style(nil),
        uidust.Ui_Dust_Arrival_Style.Falling_Ink)
    for index in 0..<3 {
        testing.expect(t, uidust.ui_dust_emit(&presentation^.dust,
            {f32(index), 10}, {20, 40, 60, 255}, 255, 1))
    }
    uidust.ui_dust_begin_arrival(&presentation^.dust, 53, .Falling_Ink)
    testing.expect(t, presentation_effects_observe(presentation).arrival_active)

    presentation_set_arrival_style(presentation, .Draw_In)

    effects := presentation_effects_observe(presentation)
    testing.expect_value(t, presentation_arrival_style(presentation),
        uidust.Ui_Dust_Arrival_Style.Draw_In)
    testing.expect_value(t, effects.arrival_selection,
        uidust.Ui_Dust_Arrival_Style.Draw_In)
    testing.expect(t, !effects.arrival_active)
    testing.expect_value(t, effects.departure_particle_count, 3)
    testing.expect_value(t, uidust.ui_dust_incoming_alpha(&presentation^.dust), f32(1))
}

// Verify selection and reset consume drawn ink once while runtime reload settles it.
@(test)
presentation_selection_and_reset_depart_reload_settles :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    presentation_sync_lifecycle(state, presentation)
    selected: bridgemodel.Euclid_Julia_Animation_Interface
    state^.julia_interface^.current_animation = &selected
    for cycle in 0..<2 {
        presentation_test_publish_ink(state, {{20, 30}})
        service^.animation_generation += 1
        presentation_sync_lifecycle(state, presentation)
        testing.expect_value(t, presentation^.dust.particle_count, cycle + 1)
        testing.expect(t, !presentation^.suppress_next_departure)
        testing.expect_value(t,
            len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 0)
        presentation^.dust.particles.pos_y[0] = 40
        presentation_sync_lifecycle(state, presentation)
        testing.expect_value(t, presentation^.dust.particles.pos_y[0], f32(40))
    }
    presentation_test_publish_ink(state, {{20, 30}})
    service^.runtime_generation += 1
    presentation_sync_lifecycle(state, presentation)
    testing.expect_value(t, presentation^.dust.particle_count, 0)
    testing.expect(t, presentation^.suppress_next_departure)
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 0)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
}

// Verify a pending refresh keeps ink and advances effects, unlike runtime reload.
@(test)
presentation_pending_reset_preserves_ink_and_effects :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, presentation := fixture.state, fixture.presentation
    testing.expect(t, viewfont.cache_ink_capture_init(
        &state^.font_cache, context.allocator))
    defer viewfont.cache_ink_capture_destroy(
        &state^.font_cache, context.allocator)
    presentation_test_publish_ink(state, {{30, 40}})
    state^.ui_runtime.presentation.visible = true
    uidust.ui_dust_begin_departure(&presentation^.dust, 23)
    testing.expect(t, uidust.ui_dust_emit(
        &presentation^.dust, {30, 50}, {240, 160, 80, 255}, 255, 1))
    uidust.ui_dust_begin_arrival(&presentation^.dust, 24, .Fade)
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 200, 120},
        },
    }
    state^.julia_interface^.pending_animation_reset = true

    presentation_effects_update(state, presentation, 0.016, frame, 1)

    testing.expect_value(t, presentation^.dust.particle_count, 1)
    testing.expect(t, presentation^.dust.particles.pos_y[0] > 50)
    testing.expect(t, presentation^.dust.incoming_active)
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 1)
    testing.expect(t, !presentation^.suppress_next_departure)
    fixture.service^.reload_state = .Quiescing
    presentation_effects_update(state, presentation, 0.016, frame, 1)
    testing.expect_value(t, presentation^.dust.particle_count, 0)
    testing.expect(t, !presentation^.dust.incoming_active)
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 0)
    testing.expect(t, presentation^.suppress_next_departure)
}

//   Verify a miss publishes after poll/join and its exact repeat uses the cache.
@(test)
presentation_parse_miss_then_cache_hit_publishes :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    source_bytes: []u8 = {'$', 'x', '^', '2', '$'}
    first := presentation_test_message(state, 21, source_bytes)
    first_content, _ := first^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, first, first_content)
    presentation_start_pending(state, presentation)
    testing.expect(t, presentation^.active.submitted)

    presentation_test_wait_for_idle(state, presentation)
    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    testing.expect(t, state^.dynview.compile_cache.math_program_count > 0)
    testing.expect(t, presentation^.dust.incoming_active)
    testing.expect_value(t, presentation^.dust.incoming_generation, u64(21))
    returned, first_returned := bridge.communication_link_try_take_return(
        &service^.event_link)
    testing.expect(t, first_returned && returned == first)
    free(returned)

    second := presentation_test_message(state, 22, source_bytes)
    second_content, _ := second^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, second, second_content)
    presentation_start_pending(state, presentation)
    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, presentation^.pending == nil)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    second_returned: bool
    returned, second_returned = bridge.communication_link_try_take_return(
        &service^.event_link)
    testing.expect(t, second_returned && returned == second)
    free(returned)
}

//   Verify a current rejected document publishes its exact source as visible text.
@(test)
presentation_rejected_tex_publishes_exact_literal :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    source_bytes: []u8 = {'\\', 't', 'e', 'x', 't', 'b', 'f', '{', 'x'}
    message := presentation_test_message(state, 31, source_bytes)
    content, _ := message^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, message, content)
    presentation_start_pending(state, presentation)
    presentation_test_wait_for_idle(state, presentation)

    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    commands := state^.dynview.content.commands
    testing.expect_value(t, len(commands), 3)
    literal := commands[1]
    testing.expect_value(t, literal.kind, dynviewmodel.Dynview_Command_Kind.Text_Run)
    testing.expect_value(t, state^.dynview.content.presentation_mime,
        presentation_model.Presentation_Mime.Text_Latex)
    testing.expect(t, !presentation^.dust.incoming_active)
    testing.expect(t, presentation_test_bytes_equal(
        state^.dynview.content.presentation_bytes, source_bytes))
    testing.expect(t, presentation_test_bytes_equal(
        state^.dynview.content.text_bytes[
            literal.text_offset:literal.text_offset+literal.text_len],
        source_bytes))
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == message)
    free(returned)
}

//   Verify a lifecycle generation change clears content and retires stale parse work.
@(test)
presentation_lifecycle_change_cancels_stale_parse :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    presentation_sync_lifecycle(state, presentation)
    uidust.ui_dust_begin_arrival(&presentation^.dust, 40, .Fade)
    source_bytes: []u8 = {
        '$', '\\', 'f', 'r', 'a', 'c', '{', '1', '}', '{', '2', '}', '$'}
    message := presentation_test_message(state, 41, source_bytes)
    content, _ := message^.(bridgemodel.View_Content_Ready)
    presentation_admit(state, presentation, message, content)
    presentation_start_pending(state, presentation)
    testing.expect(t, presentation^.active.submitted)

    service^.animation_generation += 1
    presentation_sync_lifecycle(state, presentation)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)
    testing.expect(t, presentation^.active.cancellation_requested)
    testing.expect(t, !presentation^.dust.incoming_active)
    testing.expect_value(t, presentation^.dust.particle_count, 0)
    testing.expect_value(t, presentation^.newest_generation, 0)
    presentation_test_wait_for_idle(state, presentation)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == message)
    free(returned)
}
