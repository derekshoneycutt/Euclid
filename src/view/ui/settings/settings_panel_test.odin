#+test
package uisettings

import core "../../../core"
import setting_model "../../../settings"
import viewmodel "../model"
import uisemantics "../semantics"
import theme "../theme"
import "core:testing"

// Both keyboard and accessibility toggle commands reach the enabled localized checkbox.
@(test)
increased_contrast_checkbox_registers_and_consumes_toggle :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    id := uisemantics.semantic_control_id(.Settings_Control, 4007)
    semantic^.commands[0] = {target = id, kind = .Toggle}
    semantic^.command_count = 1
    owner: viewmodel.Ui_Press_Owner_State
    ctx := Settings_View_Context{panel = {0, 0, 600, 700},
        semantic_focus = semantic, press_owner = &owner,
        preferences = setting_model.default_preferences(),
        platform_increased_contrast = true,
        labels = {increased_contrast = "Increased contrast"}}
    rows := Settings_View_Rows{simd_y = 20, gpu_dust_y = 50,
        reduce_motion_y = 80, increased_contrast_y = 110}
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
    testing.expect_value(t, node.traversal_order, u32(7))
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
