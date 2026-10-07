#+test
package ui

import viewmodel "../model"
import input "../input"
import geometry "../../core/geometry"
import "../../core"
import "core:testing"
import "core:math"

// accordion_transition_test_context supplies a fixed full-height panel and injected time.
accordion_transition_test_context :: proc(
    transition: ^viewmodel.Ui_Accordion_Transition) -> Accordion_Context {
    return {panel = {10, 20, 300, 700}, transition = transition}
}

// accordion_test_height_sum measures the conservation contract across all four sections.
accordion_test_height_sum :: proc(transition: viewmodel.Ui_Accordion_Transition) -> f32 {
    total: f32
    for height in transition.heights {
        total += height
    }
    return total
}

// A single progress curve transfers height while child layout stays full-size.
@(test)
accordion_transition_conserves_height_and_finishes_at_180_ms :: proc(t: ^testing.T) {
    transition: viewmodel.Ui_Accordion_Transition
    ctx := accordion_transition_test_context(&transition)
    sections := accordion_landscape_sections()
    initial := accordion_transition_layout(ctx, sections, .Library)
    height := initial.content.height
    _ = accordion_transition_layout(ctx, sections, .Settings)
    testing.expect(t, transition.running)
    previous := height
    test_milliseconds := []f64{20, 40, 70, 100, 140, 160, 179, 180, 200}
    for milliseconds in test_milliseconds {
        ctx.mouse_input.sample_time_seconds = milliseconds / 1000
        layout := accordion_transition_layout(ctx, sections, .Settings)
        testing.expect_value(t, transition.running, milliseconds < 180)
        testing.expect(t,
            math.abs(accordion_test_height_sum(transition) - height) < 0.001)
        testing.expect(t,
            transition.heights[int(viewmodel.Ui_Accordion_Section.Library)] <= previous)
        previous = transition.heights[int(viewmodel.Ui_Accordion_Section.Library)]
        testing.expect_value(t, layout.content.height, height)
        testing.expect_value(t,
            layout.contents[int(viewmodel.Ui_Accordion_Section.Library)].height, height)
        for index in 0..<sections.count {
            testing.expect_value(t,
                layout.headers[index].height, ACCORDION_HEADER_HEIGHT)
        }
    }
    testing.expect(t, !transition.running)
    testing.expect_value(t,
        transition.heights[int(viewmodel.Ui_Accordion_Section.Settings)], height)
    endpoint := accordion_layout(ctx.panel, sections, .Settings)
    testing.expect_value(t,
        transition.contents[int(viewmodel.Ui_Accordion_Section.Settings)],
        viewmodel.Rectangle(endpoint.content))
}

// Third and fourth selections preserve current geometry rather than queuing obsolete targets.
@(test)
accordion_transition_retargets_all_partially_visible_sections :: proc(t: ^testing.T) {
    transition: viewmodel.Ui_Accordion_Transition
    ctx := accordion_transition_test_context(&transition)
    sections := accordion_portrait_sections("")
    _ = accordion_transition_layout(ctx, sections, .View)
    _ = accordion_transition_layout(ctx, sections, .Library)
    ctx.mouse_input.sample_time_seconds = 0.03
    before := accordion_transition_layout(ctx, sections, .Library)
    after := accordion_transition_layout(ctx, sections, .Settings)
    testing.expect_value(t, before.headers, after.headers)
    testing.expect_value(t, before.clips, after.clips)
    ctx.mouse_input.sample_time_seconds = 0.05
    _ = accordion_transition_layout(ctx, sections, .Save_Gif)
    ctx.mouse_input.sample_time_seconds = 0.07
    _ = accordion_transition_layout(ctx, sections, .View)
    testing.expect(t,
        transition.heights[int(viewmodel.Ui_Accordion_Section.Library)] > 0)
    testing.expect(t,
        transition.heights[int(viewmodel.Ui_Accordion_Section.Save_Gif)] > 0)
    testing.expect(t,
        transition.heights[int(viewmodel.Ui_Accordion_Section.Settings)] > 0)
    ctx.mouse_input.sample_time_seconds = 0.07 + ACCORDION_TRANSITION_SECONDS
    _ = accordion_transition_layout(ctx, sections, .View)
    testing.expect(t, !transition.running)
    testing.expect_value(t, transition.heights[int(viewmodel.Ui_Accordion_Section.View)],
        accordion_test_height_sum(transition))
}

// Same-section activation does not reset the clock or prolong an in-flight transition.
@(test)
accordion_transition_selected_section_is_not_restarted :: proc(t: ^testing.T) {
    transition: viewmodel.Ui_Accordion_Transition
    ctx := accordion_transition_test_context(&transition)
    sections := accordion_landscape_sections()
    _ = accordion_transition_layout(ctx, sections, .Library)
    ctx.mouse_input.sample_time_seconds = 1
    _ = accordion_transition_layout(ctx, sections, .Save_Gif)
    ctx.mouse_input.sample_time_seconds = 1.07
    _ = accordion_transition_layout(ctx, sections, .Save_Gif)
    testing.expect_value(t, transition.start_seconds, f64(1))
    ctx.mouse_input.sample_time_seconds = 1 + ACCORDION_TRANSITION_SECONDS
    _ = accordion_transition_layout(ctx, sections, .Save_Gif)
    testing.expect(t, !transition.running)
}

// Geometry changes and reduced motion settle the selected panel without reflow animation.
@(test)
accordion_transition_settles_for_geometry_and_policy_changes :: proc(t: ^testing.T) {
    transition: viewmodel.Ui_Accordion_Transition
    ctx := accordion_transition_test_context(&transition)
    sections := accordion_landscape_sections()
    _ = accordion_transition_layout(ctx, sections, .Library)
    _ = accordion_transition_layout(ctx, sections, .Settings)
    ctx.panel.width += 1
    _ = accordion_transition_layout(ctx, sections, .Settings)
    testing.expect(t, !transition.running)
    _ = accordion_transition_layout(ctx, sections, .Library)
    ctx.reduce_motion = true
    _ = accordion_transition_layout(ctx, sections, .Library)
    testing.expect(t, !transition.running)
    testing.expect_value(t,
        transition.heights[int(viewmodel.Ui_Accordion_Section.Settings)], f32(0))
    ctx.reduce_motion = false
    _ = accordion_transition_layout(ctx, accordion_portrait_sections(""), .View)
    testing.expect(t, !transition.running)
    ctx.panel.height = 0
    _ = accordion_transition_layout(ctx, sections, .Settings)
    testing.expect_value(t, accordion_test_height_sum(transition), f32(0))
}

// Either user intent or platform policy disables only interface animation.
@(test)
accordion_reduced_motion_policy_is_an_or :: proc(t: ^testing.T) {
    runtime := new(viewmodel.Euclid_Ui_Runtime_State, context.allocator)
    defer free(runtime, context.allocator)
    testing.expect(t, !ui_reduced_motion(runtime))
    runtime^.settings_preferences.interface.reduce_motion = true
    testing.expect(t, ui_reduced_motion(runtime))
    runtime^.settings_preferences.interface.reduce_motion = false
    runtime^.platform_reduce_motion = true
    testing.expect(t, ui_reduced_motion(runtime))
    testing.expect(t, !runtime^.simulation_paused && !runtime^.animation_policy_paused)
}

// Pointer edges and wheel cannot reach full-size controls behind an unrevealed clip.
@(test)
accordion_child_input_is_clipped_without_discarding_keyboard :: proc(t: ^testing.T) {
    runtime := new(viewmodel.Euclid_Ui_Runtime_State, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.active_accordion_section = .Library
    ctx := accordion_transition_test_context(&runtime^.accordion_transition)
    _ = accordion_transition_layout(ctx, accordion_landscape_sections(), .Library)
    clip_index := int(viewmodel.Ui_Accordion_Section.Library)
    runtime^.accordion_transition.clips[clip_index].height = 10
    clip := accordion_content_clip(runtime, .Library)
    events := [1]input.Input_Event{{kind = .Press, key = .Tab}}
    frame := Input_Frame{mouse_position = {clip.x + 1, clip.y + 20},
        mouse_pressed = {.Left}, mouse_down = {.Left}, mouse_wheel_delta = 1,
        events = events[:]}
    hidden := ui_clip_accordion_child_frame(runtime, frame)
    testing.expect(t, !input_frame_left_pressed(hidden))
    testing.expect_value(t, hidden.mouse_wheel_delta, f32(0))
    testing.expect_value(t, hidden.events[0].key, input.Input_Key.Tab)
    testing.expect(t, hidden.mouse_position.x < 0 && hidden.mouse_position.y < 0)
    frame.mouse_position.y = clip.y + 5
    shown := ui_clip_accordion_child_frame(runtime, frame)
    testing.expect(t, input_frame_left_pressed(shown))
    testing.expect_value(t, shown.mouse_wheel_delta, f32(1))
    runtime^.accordion_transition.clips[clip_index].height = 0
    testing.expect(t, !ui_accordion_pointer_is_revealed(
        runtime, .Library, {clip.x, clip.y}))
}

// Releasing outside a reveal cancels child capture without admitting a hidden activation.
@(test)
accordion_hidden_release_cancels_only_child_capture :: proc(t: ^testing.T) {
    runtime := new(viewmodel.Euclid_Ui_Runtime_State, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.active_accordion_section = .Library
    ctx := accordion_transition_test_context(&runtime^.accordion_transition)
    _ = accordion_transition_layout(ctx, accordion_landscape_sections(), .Library)
    runtime^.accordion_transition.clips[int(viewmodel.Ui_Accordion_Section.Library)] = {}
    runtime^.ui_press_owner = {active = true, kind = .Checkbox, id = 4006}
    frame := Input_Frame{mouse_released = {.Left}}
    released := ui_clip_accordion_child_frame(runtime, frame)
    testing.expect(t, !runtime^.ui_press_owner.active)
    testing.expect(t, !input_frame_left_released(released))
    runtime^.ui_press_owner = {active = true, kind = .Splitter, id = 1}
    _ = ui_clip_accordion_child_frame(runtime, frame)
    testing.expect(t, runtime^.ui_press_owner.active)
}

// Outgoing controls neither consume queued actions nor publish operable semantics.
@(test)
accordion_visual_checkbox_preserves_actions_and_press_ownership :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    testing.expect(t, semantic_begin(semantic))
    id := semantic_control_id(.Settings_Control, 4006)
    semantic^.commands[0] = {target = id, kind = .Toggle}
    semantic^.command_count = 1
    owner := viewmodel.Ui_Press_Owner_State{active = true, kind = .Checkbox, id = 4006}
    before := owner
    params := Checkbox_Params{id = 4006, rect = {0, 0, 20, 20},
        enabled = true, interaction_enabled = true, semantic_focus = semantic,
        semantic_domain = .Settings_Control, semantic_clip = {0, 0, 100, 100},
        interaction_space_rect = {0, 0, 100, 100},
        mouse = {mouse_released = {.Left}, mouse_position = {5, 5}}}
    drawn := prepare_checkbox(params, &owner, false)
    testing.expect(t, !drawn.toggled && !drawn.checked_out)
    testing.expect_value(t, owner, before)
    testing.expect_value(t, semantic_staging_snapshot(semantic)^.node_count, 0)
    testing.expect(t, semantic_command_requested(semantic, id, .Toggle))
}

// Partial semantic bounds share the reveal, while wholly hidden children cannot focus.
@(test)
accordion_semantic_children_respect_the_selected_reveal :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    testing.expect(t, semantic_begin(semantic))
    semantic^.staging_accordion_clip_set = true
    semantic^.staging_accordion_clip = {0, 0, 100, 10}
    for index in 0..<2 {
        testing.expect_value(t, semantic_register_control(semantic, {
            id = semantic_control_id(.Settings_Control, 4006 + index), role = .Checkbox,
            states = {.Visible, .Enabled, .Focusable, .Tab_Stop}, actions = {.Focus},
            region = .Accordion_Content, bounds = {0, f32(index * 20), 20, 20},
            clip_bounds = {0, 0, 100, 100},
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    snapshot := semantic_staging_snapshot(semantic)
    testing.expect_value(t, snapshot^.nodes[0].clip_bounds,
        viewmodel.Rectangle{0, 0, 100, 10})
    testing.expect(t, semantic_node_is_tab_stop(snapshot^.nodes[0]))
    testing.expect(t, !semantic_node_is_focus_candidate(snapshot^.nodes[1]))
    testing.expect(t, .Visible not_in snapshot^.nodes[1].states)
}

// Short Settings viewports retain scroll and reveal the new row through keyboard paging.
@(test)
accordion_settings_scroll_is_retained_and_visual_preparation_is_pure :: proc(
    t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    testing.expect(t, semantic_begin(semantic))
    semantic^.commands[0] = {target = semantic_control_id(.Settings_Control, 6102),
        kind = .Scroll_Page, amount = 1}
    semantic^.command_count = 1
    command, amount := semantic_command_for_event(
        {role = .Panel, actions = {.Scroll}},
        {kind = .Press, key = .Page_Down})
    testing.expect_value(t, command, viewmodel.Ui_Focus_Command_Kind.Scroll_Page)
    testing.expect_value(t, amount, i32(1))
    panel := geometry.Rectangle{0, 0, 600, 290}
    visual := prepare_settings_scroll(state, panel, {}, false)
    testing.expect(t, visual.scrollbar.has_scrollbar)
    testing.expect_value(t, state^.ui_runtime.settings_scroll_y, f32(0))
    testing.expect_value(t, semantic_staging_snapshot(semantic)^.node_count, 0)
    selected := prepare_settings_scroll(state, panel, {}, true)
    testing.expect_value(t, selected.scroll_y_out, selected.maximum)
    rows := settings_view_layout_rows({SETTINGS_PANEL_INSET,
        SETTINGS_HEADER_TOP_OFFSET - selected.scroll_y_out,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET})
    testing.expect(t, rows.reduce_motion_y + SETTINGS_CHECKBOX_SIZE < panel.height)
    retained := prepare_settings_scroll(state, panel, {}, false)
    testing.expect_value(t, retained.scroll_y_out, selected.scroll_y_out)
    testing.expect_value(t, state^.ui_runtime.settings_scroll_y, selected.scroll_y_out)
    testing.expect_value(t, settings_scroll_content_height(true) -
        settings_scroll_content_height(false), f32(SETTINGS_TOGGLE_ROW_GAP))
}
