#+test
package ui

import testing "core:testing"
import capturemodel "../capture/model"
import viewmodel "model"
import uisharing "sharing"
import sharinglayout "layout/sharing"
import uigif "gif"
import uiwidgets "widgets"
import uisemantics "semantics"
import viewmessages "../messages"
import geometry "../../core/geometry"

// Verify Sharing uses distinct navigation prose while preserving the GIF action label.
@(test)
sharing_navigation_does_not_rename_gif_action :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    sections := accordion_sections_for_layout(.Landscape, "", state)
    testing.expect_value(t, sections.items[1].label, "Sharing")
    testing.expect_value(t, viewmessages.shell_message(state, .Gif_Save), "Save GIF")
    testing.expect_value(t, viewmessages.shell_message(state, .Png_Save), "Save PNG")
}

// Verify both sections remain ordered and short viewports have enough scroll range.
@(test)
sharing_layout_scales_and_scrolls_both_path_fields :: proc(t: ^testing.T) {
    panel: geometry.Rectangle = {10, 20, 320, 300}
    percents := [?]int{100, 150, 200}
    for text_percent in percents {
        for control_percent in percents {
            layout := sharinglayout.sharing_layout(
                panel, text_percent, control_percent, 0)
            height := uisharing.sharing_content_height(
                panel, text_percent, control_percent)
            testing.expect(t, layout.png_heading_y < layout.button.y)
            testing.expect(t, layout.button.y < layout.path.y)
            testing.expect(t, layout.path.y + layout.path.height < layout.gif_heading_y)
            testing.expect(t, height > panel.height)
            scrolled := sharinglayout.sharing_layout(panel,
                text_percent, control_percent, height - panel.height)
            field := uigif.gif_path_input_rect_for_panel(
                scrolled.gif_panel, text_percent, control_percent)
            testing.expect(t, field.y + field.height <= panel.y + panel.height)
            testing.expect(t, scrolled.path.y < layout.path.y)
        }
    }
}

// Verify both textboxes reuse read-only selection mechanics but never share cursor storage.
@(test)
sharing_path_params_are_independent_read_only_controls :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    copy(state.png_capture_status.last_path[:], "/tmp/current.png")
    state.png_capture_status.path_len = len("/tmp/current.png")
    state.png_capture_status.path_revision = 3
    png := uisharing.png_path_params(state, {0, 0, 100, 24}, {}, "/tmp/current.png")
    gif := uigif.gif_path_input_params(state, {0, 30, 100, 24}, {}, "/tmp/animation.gif")
    testing.expect(t, png.descriptor.mode == .Read_Only)
    testing.expect(t, png.state != gif.state)
    testing.expect(t, png.descriptor.id != gif.descriptor.id)
    testing.expect(t, png.descriptor.traversal_order < gif.descriptor.traversal_order)
    testing.expect_value(t, png.descriptor.content_revision, u64(3))
    testing.expect_value(t, png.descriptor.label, "Saved PNG path")
    testing.expect_value(t, png.controls, viewmodel.Ui_Node_Id{})
    testing.expect(t, uisharing.png_button_params(state, {}, {}, {}).enabled)
    state.gif_capture_status.save_gif_requested = true
    testing.expect(t, !uisharing.png_button_params(state, {}, {}, {}).enabled)
    testing.expect(t, !capturemodel.png_capture_request(&state.png_capture_status,
        capturemodel.gif_capture_view(&state.gif_capture_status)))
}

// Verify ordinary pointer routing selects the PNG field and releases it when hidden.
@(test)
sharing_png_path_routes_focus_and_releases_capture :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State = {
        layout = make_baseline_layout_state(),
        sharing = {
            png_path_available = true,
        },
    }
    runtime.layout.active_accordion_section = .Save_Gif
    field := uisharing.png_path_input_rect(&runtime)
    routed := ui_reconcile_focus(&runtime, {
        window_focused = true,
        mouse_position = {field.x + 1, field.y + 1},
        mouse_pressed = {.Left},
    }, false)
    testing.expect_value(t, routed.logical_focus.id, uisharing.PNG_PATH_INPUT_ID)
    runtime.layout.active_accordion_section = .Library
    hidden := ui_reconcile_focus(&runtime, {
        window_focused = true,
    }, false)
    testing.expect_value(t, hidden.logical_focus.kind, viewmodel.Ui_Focus_Kind.None)
    owner := ui_valid_capture_owner(&runtime,
        {
            kind = .Input_Box,
            id = uisharing.PNG_PATH_INPUT_ID,
            active = true,
        }, {})
    testing.expect(t, !owner.active)
}

// Verify PNG path publication exposes immutable text and read-only accessibility state.
@(test)
sharing_png_path_publishes_selection_without_edit_authority :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    state.ui_runtime.semantic_focus = &state.semantic_focus
    testing.expect(t, uisemantics.semantic_begin(&state.semantic_focus))
    params := uisharing.png_path_params(state, {0, 0, 200, 24}, {}, "/tmp/frame.png")
    params.clip_rect = params.rect
    _ = uiwidgets.input_box_prepare(params, &state.ui_runtime.input.press_owner)
    snapshot := uisemantics.semantic_staging_snapshot(&state.semantic_focus)
    index := uisemantics.semantic_node_index(snapshot, params.descriptor.id)
    testing.expect(t, index >= 0)
    if index >= 0 {
        testing.expect(t, .Read_Only in snapshot.nodes[index].states)
    }
}
