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
import viewinput "../input"
import geometry "../../core/geometry"
import theme "theme"

// Keep section spacing uniform and both save actions on the standard button metrics.
@(test)
sharing_sections_use_consistent_control_spacing :: proc(t: ^testing.T) {
    percents := [?]int{100, 150, 200}
    for text_percent in percents {
        for control_percent in percents {
            layout := sharinglayout.sharing_layout(
                {0, 0, 320, 600}, {
                    text_percent = text_percent,
                    control_percent = control_percent,
                })
            inset := theme.ui_control_size_metric(
                theme.SETTINGS_PANEL_INSET, control_percent)
            header := theme.ui_control_size_metric(
                theme.SETTINGS_HEADER_TOP_OFFSET, control_percent)
            rows := uigif.gif_view_layout_rows({
                layout.gif_panel.x + inset, layout.gif_panel.y + header,
                layout.gif_panel.width - inset * 2, layout.gif_panel.height},
                text_percent, control_percent)
            testing.expect_value(t, layout.button.height,
                uigif.gif_save_button_height(text_percent, control_percent))
            testing.expect_value(t, layout.status_y - layout.button.y,
                uigif.gif_save_button_segment_size(text_percent, control_percent))
            testing.expect_value(t, rows.sliders.downsample_y - layout.gif_heading_y,
                layout.description_y - layout.png_heading_y)
            testing.expect_value(t, rows.sliders.downsample_y,
                layout.gif_panel.y + header)
        }
    }
}

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
                panel, {
                    text_percent = text_percent,
                    control_percent = control_percent,
                })
            height := uisharing.sharing_content_height(
                panel, text_percent, control_percent)
            testing.expect(t, layout.png_heading_y < layout.button.y)
            testing.expect(t, layout.button.y < layout.path.y)
            testing.expect(t, layout.path.y + layout.path.height < layout.gif_heading_y)
            testing.expect(t, height > panel.height)
            scrolled := sharinglayout.sharing_layout(panel,
                {
                    text_percent = text_percent,
                    control_percent = control_percent,
                    scroll_y = height - panel.height,
                })
            field := uigif.gif_path_input_rect_for_panel(
                scrolled.gif_panel, text_percent, control_percent)
            testing.expect(t, field.y + field.height <= panel.y + panel.height)
            testing.expect(t, scrolled.path.y < layout.path.y)
        }
    }
}

// Keep collection controls below the measured GIF path row within the same scroll range.
@(test)
sharing_collection_layout_follows_gif_and_contributes_to_scroll_height :: proc(
    t: ^testing.T) {
    panel: geometry.Rectangle = {10, 20, 320, 300}
    counts: uisharing.Share_Collection_Counts = {
        export_count = 2,
        importable_count = 1,
        warning_count = 1,
        non_importable_count = 1,
        has_import = true,
    }
    layout := uisharing.sharing_layout_for_content(panel, 100, 100, 0, counts)
    inset := theme.ui_control_size_metric(theme.SETTINGS_PANEL_INSET, 100)
    header := theme.ui_control_size_metric(theme.SETTINGS_HEADER_TOP_OFFSET, 100)
    gif_inset: geometry.Rectangle = {
        layout.gif_panel.x + inset,
        layout.gif_panel.y + header,
        layout.gif_panel.width - inset * 2,
        layout.gif_panel.height,
    }
    rows := uigif.gif_view_layout_rows(gif_inset, 100, 100)
    gif_end_y := rows.status_y +
        uigif.gif_path_input_top_offset(100, 100) +
        uigif.gif_path_input_height(100, 100) + inset
    testing.expect(t, layout.collections_heading_y > gif_end_y)
    testing.expect(t, layout.export_list.height > 0)
    testing.expect(t, layout.import_list.height > 0)
    testing.expect(t, layout.not_importable_list.height > 0)
    height := uisharing.sharing_content_height(panel, 100, 100, counts)
    testing.expect(t,
        height > layout.collections_status_y - panel.y + theme.ui_font_size(100))
}

// Keep the omission indicator until a press or activation is accepted inside Sharing.
@(test)
sharing_omission_indicator_clears_only_on_in_panel_activation :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    state^.ui_runtime.semantic_focus = &state^.semantic_focus
    state^.ui_runtime.sharing.import_left_out_entries = true
    panel: geometry.Rectangle = {10, 20, 200, 120}
    uisharing.share_clear_omission_indicator(state, panel, {
        mouse_position = {20, 30},
        mouse_wheel_delta = 1,
    })
    testing.expect(t, state^.ui_runtime.sharing.import_left_out_entries)
    uisharing.share_clear_omission_indicator(state, panel, {
        mouse_position = {250, 30},
        mouse_pressed = {.Left},
    })
    testing.expect(t, state^.ui_runtime.sharing.import_left_out_entries)
    uisharing.share_clear_omission_indicator(state, panel, {
        mouse_position = {20, 30},
        mouse_pressed = {.Left},
    })
    testing.expect(t, !state^.ui_runtime.sharing.import_left_out_entries)
    state^.ui_runtime.sharing.import_left_out_entries = true
    state^.semantic_focus.logical_focus.domain = .Sharing_Control
    events: [1]viewinput.Input_Event = {
        {
            kind = .Press,
            key = .Enter,
        },
    }
    frame: viewinput.Input_Frame = {
        events = events[:],
    }
    uisharing.share_clear_omission_indicator(state, panel, frame)
    testing.expect(t, !state^.ui_runtime.sharing.import_left_out_entries)
    state^.ui_runtime.sharing.import_left_out_entries = true
    state^.semantic_focus.logical_focus.domain = .Animation_Control
    uisharing.share_clear_omission_indicator(state, panel, frame)
    testing.expect(t, state^.ui_runtime.sharing.import_left_out_entries)
}

// Publish omission feedback on the actual Sharing descriptor, not a positional index.
@(test)
sharing_omission_indicator_publishes_accessible_value :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    state^.ui_runtime.sharing.import_left_out_entries = true
    state^.ui_runtime.sharing.last_import_omitted_entry_count = 2
    sections := accordion_sections_for_layout(.Landscape, "", state)
    found := false
    for index in 0..<sections.count {
        if sections.items[index].section != .Save_Gif {
            continue
        }
        found = true
        testing.expect(t, sections.items[index].error_indicator)
        testing.expect_value(t, sections.items[index].accessible_value,
            "Last import left out 2 entries")
    }
    testing.expect(t, found)
}

// Keep export disabled without a selected collection while import remains actionable.
@(test)
sharing_collection_buttons_publish_enabled_accessible_states :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    state^.ui_runtime.semantic_focus = &state^.semantic_focus
    testing.expect(t, uisemantics.semantic_begin(&state^.semantic_focus))
    panel: geometry.Rectangle = {10, 20, 320, 500}
    layout := sharinglayout.sharing_layout(panel, {
        text_percent = 100,
        control_percent = 100,
        collections_start_y = 120,
    })
    prepared := uisharing.prepare_share_collections(
        state, panel, layout, {}, true)
    snapshot := uisemantics.semantic_staging_snapshot(&state^.semantic_focus)
    export_id := uisemantics.semantic_control_id(
        .Sharing_Control, uisharing.SHARE_EXPORT_BUTTON_ID)
    import_id := uisemantics.semantic_control_id(
        .Sharing_Control, uisharing.SHARE_IMPORT_BUTTON_ID)
    export_index := uisemantics.semantic_node_index(snapshot, export_id)
    import_index := uisemantics.semantic_node_index(snapshot, import_id)
    testing.expect(t, export_index >= 0 && import_index >= 0)
    testing.expect(t, !prepared.export_enabled && prepared.import_enabled)
    indexes := [?]int{export_index, import_index}
    labels := [?]string{"Export…", "Import…"}
    for index, position in indexes {
        if index < 0 {
            continue
        }
        node := snapshot^.nodes[index]
        testing.expect_value(t, node.role, viewmodel.Ui_Node_Role.Button)
        testing.expect_value(t, .Enabled in node.states, position == 1)
        testing.expect_value(t, uisemantics.semantic_node_text(
            snapshot, node.label_offset, node.label_length), labels[position])
        testing.expect_value(t, uisemantics.semantic_node_text(
            snapshot, node.value_offset, node.value_length), labels[position])
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
