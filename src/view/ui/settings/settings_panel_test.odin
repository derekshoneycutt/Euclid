#+test
package uisettings

import core "../../../core"
import historyruntime "../../../terminal/history/runtime"
import setting_model "../../../settings"
import viewmodel "../model"
import uisemantics "../semantics"
import theme "../theme"
import uiwidgets "../widgets"
import native "../../native"
import "core:testing"

// Both keyboard and accessibility toggle commands reach the enabled localized checkbox.
@(test)
increased_contrast_checkbox_registers_and_consumes_toggle :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    id := uisemantics.semantic_control_id(.Settings_Control, 4007)
    semantic^.commands[0] = {
        target = id,
        kind = .Toggle,
    }
    semantic^.command_count = 1
    owner: viewmodel.Ui_Press_Owner_State
    ctx: Settings_View_Context = {
        panel = {0, 0, 600, 700},
        semantic_focus = semantic,
        press_owner = &owner,
        preferences = setting_model.default_preferences(),
        platform_increased_contrast = true,
        labels = {
            increased_contrast = "Increased contrast",
        },
    }
    rows: Settings_View_Rows = {
        simd_y = 20,
        gpu_dust_y = 50,
        reduce_motion_y = 80,
        increased_contrast_y = 110,
    }
    prepared: Settings_View_Preparation
    prepare_settings_optional_controls(ctx, rows, false, &prepared)
    testing.expect(t, !prepared.increased_contrast.checked_out)
    testing.expect(t, !prepared.increased_contrast.toggled)
    prepare_settings_optional_controls(ctx, rows, true, &prepared)
    testing.expect(t, prepared.increased_contrast.toggled)
    testing.expect(t, prepared.increased_contrast.checked_out)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, id)]
    testing.expect_value(t, node.id, id)
    testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Checkbox)
    testing.expect_value(t, node.traversal_order, u32(2))
    testing.expect(t, .Enabled in node.states && .Checked in node.states)
    testing.expect(t, .Toggle in node.actions && .Focus in node.actions)
    testing.expect_value(t, node.clip_bounds, ctx.panel)
}

// Persistence remains a normal accessible checkbox and consumes semantic toggles.
@(test)
persist_history_checkbox_registers_and_consumes_toggle :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    id := uisemantics.semantic_control_id(.Settings_Control, 4008)
    semantic^.commands[0] = {
        target = id,
        kind = .Toggle,
    }
    semantic^.command_count = 1
    owner: viewmodel.Ui_Press_Owner_State
    ctx: Settings_View_Context = {
        panel = {0, 0, 600, 700},
        semantic_focus = semantic,
        press_owner = &owner,
        preferences = setting_model.default_preferences(),
        labels = {
            persist_history = "Persist Terminal History",
        },
    }
    rows: Settings_View_Rows = {
        persist_history_y = 120,
    }
    prepared: Settings_View_Preparation
    prepare_settings_optional_controls(ctx, rows, false, &prepared)
    testing.expect(t, !prepared.persist_history.checked_out)
    prepare_settings_optional_controls(ctx, rows, true, &prepared)
    testing.expect(t, prepared.persist_history.toggled)
    testing.expect(t, prepared.persist_history.checked_out)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, id)]
    testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Checkbox)
    testing.expect_value(t, node.traversal_order, u32(6))
    testing.expect(t, .Enabled in node.states && .Checked in node.states)
    testing.expect(t, .Toggle in node.actions && .Focus in node.actions)
}

// Monochrome remains an accessible persisted intent toggle without applying recoloring.
@(test)
monochrome_checkbox_registers_and_consumes_toggle :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    id := uisemantics.semantic_control_id(.Settings_Control, 4009)
    semantic^.commands[0] = {
        target = id,
        kind = .Toggle,
    }
    semantic^.command_count = 1
    owner: viewmodel.Ui_Press_Owner_State
    ctx: Settings_View_Context = {
        panel = {0, 0, 600, 700},
        semantic_focus = semantic,
        press_owner = &owner,
        preferences = setting_model.default_preferences(),
        labels = {
            monochrome = "Monochrome",
        },
    }
    rows: Settings_View_Rows = {
        monochrome_y = 120,
    }
    prepared: Settings_View_Preparation
    prepare_settings_optional_controls(ctx, rows, false, &prepared)
    testing.expect(t, !prepared.monochrome.checked_out)
    prepare_settings_optional_controls(ctx, rows, true, &prepared)
    testing.expect(t, prepared.monochrome.toggled)
    testing.expect(t, prepared.monochrome.checked_out)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, id)]
    testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Checkbox)
    testing.expect_value(t, node.traversal_order, u32(4))
    testing.expect(t, .Toggle in node.actions && .Focus in node.actions)
}

// Armed deletion exposes its confirmation name and state to assistive technology.
@(test)
history_delete_button_publishes_confirmation_state :: proc(t: ^testing.T) {
    panel: viewmodel.Ui_Settings_Panel_State = {
        history_delete_status = .Armed,
        history_delete_armed_at_seconds = 1,
    }
    owner: viewmodel.Ui_Press_Owner_State
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    ctx: Settings_View_Context = {
        panel = {0, 0, 500, 300},
        mouse_input = {
            sample_time_seconds = 1.1,
        },
        settings_panel = &panel,
        press_owner = &owner,
        semantic_focus = semantic,
        preferences = setting_model.default_preferences(),
        labels = {
            delete_history = "Delete Terminal History",
            confirm_delete_history = "Confirm Delete",
            confirm_delete_history_value =
                "Confirmation required; activate again to delete Terminal history.",
        },
    }
    params := settings_history_delete_button_params(ctx, {
        delete_history_y = 40,
    })
    testing.expect_value(t, params.label, "Confirm Delete")
    testing.expect_value(t, params.semantics.label, "Confirm Delete")
    testing.expect_value(t, params.semantics.value,
        "Confirmation required; activate again to delete Terminal history.")
    testing.expect(t, .Selected in params.semantics.states)
    testing.expect(t, .Enabled in params.semantics.states)
}

// Match GIF button padding at each scale and reserve a separate status row.
@(test)
history_delete_button_uses_padded_panel_geometry :: proc(t: ^testing.T) {
    panel: viewmodel.Ui_Settings_Panel_State
    ctx: Settings_View_Context = {
        panel = {10, 20, 400, 900},
        settings_panel = &panel,
        preferences = setting_model.default_preferences(),
    }
    stops := [?]int{100, 125, 150, 175}
    for percent in stops {
        ctx.preferences.interface.text_size_percent = percent
        rows := settings_view_layout_rows(ctx.panel, percent)
        params := settings_history_delete_button_params(ctx, rows)
        testing.expect_value(t, params.rect.x,
            ctx.panel.x + theme.SETTINGS_PANEL_INSET)
        testing.expect_value(t, params.rect.width,
            ctx.panel.width - 2 * theme.SETTINGS_PANEL_INSET)
        testing.expect_value(t, params.rect.height,
            theme.ui_panel_button_height(percent))
        testing.expect(t, params.rect.height >=
            theme.ui_font_size(percent) + 8 * theme.ui_text_scale_factor(percent))
        testing.expect(t,
            rows.history_delete_status_y > params.rect.y + params.rect.height)
    }
}

// Shake follows the armed envelope; both reduced-motion policies keep the target still.
@(test)
history_delete_button_shakes_only_while_armed_without_reduced_motion :: proc(
    t: ^testing.T) {
    panel: viewmodel.Ui_Settings_Panel_State = {
        history_delete_status = .Armed,
        history_delete_armed_at_seconds = 1,
    }
    ctx: Settings_View_Context = {
        panel = {10, 20, 400, 900},
        settings_panel = &panel,
        mouse_input = {
            sample_time_seconds = 1.025,
        },
        preferences = setting_model.default_preferences(),
    }
    base_x := ctx.panel.x + theme.SETTINGS_PANEL_INSET
    shaken := settings_history_delete_button_params(ctx, {})
    testing.expect(t, shaken.rect.x > base_x && shaken.rect.x <= base_x + 5)
    ctx.preferences.interface.reduce_motion = true
    testing.expect_value(t, settings_history_delete_button_params(ctx, {}).rect.x, base_x)
    ctx.preferences.interface.reduce_motion = false
    ctx.platform_reduce_motion = true
    testing.expect_value(t, settings_history_delete_button_params(ctx, {}).rect.x, base_x)
    ctx.platform_reduce_motion = false
    ctx.mouse_input.sample_time_seconds = 1 + SETTINGS_HISTORY_DELETE_SHAKE_SECONDS
    testing.expect_value(t, settings_history_delete_button_params(ctx, {}).rect.x, base_x)
    panel.history_delete_status = .Pending
    pending := settings_history_delete_button_params(ctx, {})
    testing.expect(t, !pending.enabled && .Busy in pending.semantics.states)
    testing.expect_value(t, pending.rect.x, base_x)
}

// The idle and armed states both render a filled, bordered button at prepared bounds.
@(test)
history_delete_button_encodes_background_and_confirmation_border :: proc(t: ^testing.T) {
    vertices: [12]native.Draw_Vertex
    indices: [30]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    prepared: Settings_View_Preparation = {
        delete_history = {
            control_geometry = {
                bounds = {12, 24, 200, 30},
            },
        },
    }
    states := [?]bool{false, true}
    for armed in states {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {400, 300}, {400, 300}))
        prepared.history_delete_armed = armed
        draw_encoded_settings_history_button_geometry(&encoder, prepared)
        testing.expect_value(t, encoder.vertex_count, 12)
        testing.expect_value(t, encoder.index_count, 30)
        testing.expect_value(t, vertices[0].position.x, f32(12))
        testing.expect_value(t, vertices[0].position.y, f32(24))
        testing.expect_value(t, vertices[0].color, theme.UI_COMPONENT_BACKGROUND_COLOR)
        border := theme.draw_color(&encoder, .Error_Text) if armed else
            theme.draw_color(&encoder, .Control_Border)
        testing.expect_value(t, vertices[4].color, border)
    }
}

// Programmatic settings edits share the ordinary coalesced joined-save path.
@(test)
increased_contrast_programmatic_edit_queues_persisted_value :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values = setting_model.default_preferences()
    testing.expect(t, settings_apply_control_edit(state,
        .Interface_Increased_Contrast, setting_model.boolean_value(true)))
    testing.expect(t, state^.ui_runtime.preferences.values.interface.increased_contrast)
    pending := &state^.preferences_runtime.settings_pending
    testing.expect_value(t, pending^.count, 1)
    testing.expect_value(t, pending^.changes[0].id,
        setting_model.Setting_Id.Interface_Increased_Contrast)
    testing.expect(t, pending^.changes[0].value.boolean)
    testing.expect(t, settings_apply_control_edit(state,
        .Interface_Increased_Contrast, setting_model.boolean_value(false)))
    testing.expect(t, !state^.ui_runtime.preferences.values.interface.increased_contrast)
    testing.expect_value(t, pending^.count, 1)
    testing.expect(t, !pending^.changes[0].value.boolean)
    testing.expect(t, !settings_apply_control_edit(state,
        .Interface_Increased_Contrast, setting_model.integer_value(1)))
}

// The history preference uses the same typed coalesced persistence queue.
@(test)
persist_history_programmatic_edit_queues_typed_value :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values = setting_model.default_preferences()
    testing.expect(t, settings_apply_control_edit(state,
        .Persist_Terminal_History, setting_model.boolean_value(true)))
    testing.expect(t, state^.ui_runtime.preferences.values.terminal.persist_history)
    pending := &state^.preferences_runtime.settings_pending
    testing.expect_value(t, pending^.count, 1)
    testing.expect_value(t, pending^.changes[0].id,
        setting_model.Setting_Id.Persist_Terminal_History)
    testing.expect(t, pending^.changes[0].value.boolean)
}

// Text-size edits use the existing typed override and joined-save queue.
@(test)
text_size_programmatic_edit_queues_persisted_value :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values = setting_model.default_preferences()
    testing.expect(t, settings_apply_control_edit(state,
        .Interface_Text_Size, setting_model.integer_value(150)))
    testing.expect_value(t,
        state^.ui_runtime.preferences.values.interface.text_size_percent, 150)
    pending := &state^.preferences_runtime.settings_pending
    testing.expect_value(t, pending^.count, 1)
    testing.expect_value(t, pending^.changes[0].id,
        setting_model.Setting_Id.Interface_Text_Size)
    testing.expect_value(t, pending^.changes[0].value.integer, 150)
    testing.expect(t, !settings_apply_control_edit(state,
        .Interface_Text_Size, setting_model.integer_value(110)))
}

// Animation scale and monochrome intent use the ordinary typed save queue.
@(test)
animation_accessibility_edits_queue_persisted_values :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values = setting_model.default_preferences()
    testing.expect(t, settings_apply_control_edit(state,
        .Animation_Scale_Percent, setting_model.integer_value(155)))
    testing.expect_value(t,
        state^.ui_runtime.preferences.values.animation.scale_percent, 155)
    testing.expect(t, settings_apply_control_edit(state,
        .Animation_Monochrome, setting_model.boolean_value(true)))
    testing.expect(t, state^.ui_runtime.preferences.values.animation.monochrome)
    pending := &state^.preferences_runtime.settings_pending
    testing.expect_value(t, pending^.count, 2)
    testing.expect_value(t, pending^.changes[0].id,
        setting_model.Setting_Id.Animation_Scale_Percent)
    testing.expect_value(t, pending^.changes[0].value.integer, 155)
    testing.expect_value(t, pending^.changes[1].id,
        setting_model.Setting_Id.Animation_Monochrome)
    testing.expect(t, pending^.changes[1].value.boolean)
    testing.expect(t, !settings_apply_control_edit(state,
        .Animation_Scale_Percent, setting_model.integer_value(151)))
}

// Contrast stays next to reduced motion without overlapping either platform notice.
@(test)
increased_contrast_layout_and_platform_notices_are_independent :: proc(t: ^testing.T) {
    rows := settings_view_layout_rows({0, 0, 600, 700})
    testing.expect_value(t, rows.increased_contrast_y - rows.reduce_motion_y,
        f32(theme.SETTINGS_TOGGLE_ROW_GAP))
    baseline := settings_scroll_content_height(false, false)
    testing.expect_value(t, settings_scroll_content_height(false, true) - baseline,
        f32(theme.SETTINGS_TOGGLE_ROW_GAP))
    testing.expect_value(t, settings_scroll_content_height(true, false) - baseline,
        f32(theme.SETTINGS_TOGGLE_ROW_GAP))
    testing.expect_value(t, settings_scroll_content_height(true, true) - baseline,
        f32(2 * theme.SETTINGS_TOGGLE_ROW_GAP))
}

// Every discrete text-size stop keeps controls below labels and sections nonoverlapping.
@(test)
text_size_layout_scales_and_preserves_short_viewport_scrolling :: proc(t: ^testing.T) {
    stops: [4]int = {100, 125, 150, 175}
    for percent in stops {
        rows := settings_view_layout_rows({0, 0, 600, 700}, percent, true, true)
        row_gap := settings_scaled_row_gap(percent)
        track := uiwidgets.slider_track_rect(
            {0, 0, 400, 1000}, rows.text_size_y, percent)
        testing.expect(t,
            rows.accessibility_header_y < rows.particles_header_y)
        testing.expect(t, rows.accessibility_header_y < rows.history_header_y)
        testing.expect(t, rows.history_header_y < rows.particles_header_y)
        testing.expect(t, rows.persist_history_y > rows.history_header_y)
        testing.expect(t, rows.delete_history_y > rows.persist_history_y)
        testing.expect(t,
            rows.history_delete_status_y > rows.delete_history_y)
        testing.expect(t, rows.particles_header_y < rows.other_header_y)
        testing.expect(t, rows.reduce_motion_y > rows.accessibility_header_y)
        testing.expect(t, rows.increased_contrast_y > rows.reduce_motion_y)
        testing.expect(t, rows.text_size_y > rows.system_contrast_y)
        testing.expect(t, rows.slider_label_y > rows.particles_header_y)
        testing.expect(t, rows.gpu_dust_y > rows.slider_label_y)
        testing.expect(t, rows.gpu_dust_y < rows.stats_y)
        testing.expect(t,
            rows.other_header_y >= rows.stats_y + 4 * row_gap)
        testing.expect(t, rows.animation_entries_y > rows.other_header_y)
        testing.expect(t, rows.fps_y > rows.animation_entries_y)
        testing.expect(t, track.y >= rows.text_size_y + theme.ui_font_size(percent))
        height := settings_scroll_content_height(true, true, percent)
        scroll := uiwidgets.scroll_container_visual(
            {0, 0, 220, 180}, height, 0, row_gap)
        testing.expect(t, scroll.scrollbar.has_scrollbar)
        testing.expect(t, scroll.maximum > 0)
    }
}

// Accessibility slider and checkbox rows remain separated and scroll into reach.
@(test)
animation_scale_layout_reserves_slider_and_checkbox_rows :: proc(t: ^testing.T) {
    stops: [3]int = {100, 150, 200}
    for percent in stops {
        rows := settings_view_layout_rows({0, 0, 600, 700}, percent, true, true)
        track := uiwidgets.slider_track_rect(
            {0, 0, 400, 1000}, rows.animation_scale_y, percent)
        testing.expect(t, rows.animation_scale_y > rows.system_contrast_y)
        testing.expect(t,
            rows.monochrome_y > track.y + theme.SETTINGS_TRACK_HEIGHT)
        testing.expect(t, rows.text_size_y > rows.monochrome_y)
        height := settings_scroll_content_height(true, true, percent)
        scroll := uiwidgets.scroll_container_visual(
            {0, 0, 220, 180}, height, 0, settings_scaled_row_gap(percent))
        testing.expect(t, scroll.scrollbar.has_scrollbar && scroll.maximum > 0)
    }
}

// Confirmation is bounded, cancelable, and queues only its second activation.
@(test)
history_delete_confirmation_requires_two_current_activations :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal_history_runtime.status = .Ready
    settings_history_delete_activate(state, 2)
    panel := &state^.ui_runtime.settings_panel
    testing.expect_value(t, panel^.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Armed)
    testing.expect_value(t, state^.terminal_history_runtime.mutation_count, 0)
    settings_history_delete_activate(state, 2.2)
    testing.expect_value(t, panel^.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Pending)
    testing.expect_value(t, state^.terminal_history_runtime.mutation_count, 1)
    clear_kind: historyruntime.History_Mutation_Kind = .Clear
    testing.expect_value(t,
        state^.terminal_history_runtime.queued_mutations[0].kind, clear_kind)
}

// A rejected clear is reported as failure rather than a successful deletion.
@(test)
history_delete_rejection_reports_failure :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal_history_runtime.status = .Unavailable
    settings_history_delete_activate(state, 1)
    settings_history_delete_activate(state, 1.1)
    testing.expect_value(t, state^.ui_runtime.settings_panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Failed)
    testing.expect_value(t, state^.terminal_history_runtime.mutation_count, 0)
}

// Stale confirmation expires or cancels without enqueuing a delete.
@(test)
history_delete_confirmation_expires_and_cancels :: proc(t: ^testing.T) {
    panel: viewmodel.Ui_Settings_Panel_State = {
        history_delete_status = .Armed,
        history_delete_armed_at_seconds = 1,
    }
    settings_history_delete_expire(
        &panel, 1 + SETTINGS_HISTORY_DELETE_TIMEOUT_SECONDS)
    testing.expect_value(t, panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Idle)
    panel.history_delete_status = .Armed
    settings_cancel_history_confirmation(&panel)
    testing.expect_value(t, panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Idle)
}

// Only an observed newer database completion changes deletion status.
@(test)
history_delete_status_reports_only_completed_outcome :: proc(t: ^testing.T) {
    panel: viewmodel.Ui_Settings_Panel_State = {
        history_delete_status = .Pending,
        history_delete_completion_serial = 4,
    }
    testing.expect(t,
        !settings_history_delete_observe_completion(&panel, 4, true))
    testing.expect_value(t, panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Pending)
    testing.expect(t,
        !settings_history_delete_observe_completion(&panel, 5, false))
    testing.expect_value(t, panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Failed)
    panel.history_delete_status = .Pending
    panel.history_delete_completion_serial = 5
    testing.expect(t,
        settings_history_delete_observe_completion(&panel, 6, true))
    testing.expect_value(t, panel.history_delete_status,
        viewmodel.Ui_History_Delete_Status.Cleared)
}

// The text-size slider exposes only four keyboard and pointer values.
@(test)
text_size_slider_snaps_to_supported_stops :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    preferences := setting_model.default_preferences()
    preferences.interface.text_size_percent = 150
    ctx: Settings_View_Context = {
        panel = {0, 0, 400, 300},
        press_owner = &owner,
        preferences = preferences,
        labels = {
            text_size = "Text size",
        },
    }
    params := settings_text_size_params(ctx, 40)
    result := uiwidgets.prepare_integer_slider(params, false)
    testing.expect_value(t, result.minimum, 100)
    testing.expect_value(t, result.maximum, 175)
    testing.expect_value(t, result.step, 25)
    testing.expect_value(t, result.value, 150)
}

// Animation scale slider exposes saved values and accessible range actions.
@(test)
animation_scale_slider_registers_discrete_accessible_range :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    owner: viewmodel.Ui_Press_Owner_State
    preferences := setting_model.default_preferences()
    id := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_ANIMATION_SCALE_SLIDER_ID)
    semantic^.commands[0] = {
        target = id,
        kind = .Increment,
    }
    semantic^.command_count = 1
    preferences.animation.scale_percent = 100
    ctx: Settings_View_Context = {
        panel = {0, 0, 400, 300},
        semantic_focus = semantic,
        press_owner = &owner,
        preferences = preferences,
        labels = {
            animation_scale = "Animation scale",
            animation_scale_tooltip = "Scales animation ink.",
        },
    }
    result := uiwidgets.prepare_integer_slider(
        settings_animation_scale_params(ctx, 40), true)
    testing.expect_value(t, result.minimum, 50)
    testing.expect_value(t, result.maximum, 200)
    testing.expect_value(t, result.step, 5)
    testing.expect_value(t, result.value, 105)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, id)]
    testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Slider)
    testing.expect_value(t, node.traversal_order, u32(3))
    testing.expect_value(t, node.numeric_range.minimum, f64(50))
    testing.expect_value(t, node.numeric_range.maximum, f64(200))
    testing.expect_value(t, node.numeric_range.step, f64(5))
    testing.expect_value(t, uisemantics.semantic_node_text(
        snapshot, node.value_offset, node.value_length), "105%")
}

// An offscreen animation-scale row has no semantic target and releases its capture.
@(test)
animation_scale_slider_loses_focus_when_clipped :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    owner: viewmodel.Ui_Press_Owner_State
    owner.active = true
    owner.kind = .Slider
    owner.id = SETTINGS_ANIMATION_SCALE_SLIDER_ID
    ctx: Settings_View_Context = {
        panel = {0, 0, 400, 300},
        semantic_focus = semantic,
        press_owner = &owner,
        preferences = setting_model.default_preferences(),
        labels = {
            animation_scale = "Animation scale",
        },
    }
    result := settings_prepare_integer_slider(
        ctx, settings_animation_scale_params(ctx, 500), true)
    id := uisemantics.semantic_control_id(
        .Settings_Control, SETTINGS_ANIMATION_SCALE_SLIDER_ID)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    testing.expect_value(t, uisemantics.semantic_node_index(snapshot, id), -1)
    testing.expect(t, !owner.active)
    testing.expect_value(t, owner.kind, viewmodel.Ui_Press_Owner_Kind.None)
    testing.expect_value(t, owner.id, -1)
    testing.expect(t, !result.changed)
}
