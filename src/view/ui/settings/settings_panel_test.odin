#+test
package uisettings

import core "../../../core"
import setting_model "../../../settings"
import viewmodel "../model"
import uisemantics "../semantics"
import theme "../theme"
import uiwidgets "../widgets"
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
    nodes := uisemantics.semantic_staging_snapshot(semantic)^.nodes
    node := nodes[3]
    testing.expect_value(t, node.id, id)
    testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Checkbox)
    testing.expect_value(t, node.traversal_order, u32(2))
    testing.expect(t, .Enabled in node.states && .Checked in node.states)
    testing.expect(t, .Toggle in node.actions && .Focus in node.actions)
    testing.expect_value(t, node.clip_bounds, ctx.panel)
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
