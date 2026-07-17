package view_tests

import "core:testing"

import app_core "../../src/core"
import app_ui "../../src/view/ui"

import rl "vendor:raylib"

@(test)
ui_regions_baseline_is_valid_and_consistent :: proc(t: ^testing.T) {
    regions := app_ui.compute_ui_regions(.Baseline)

    testing.expect(t, app_ui.validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, app_ui.VIEW_WIDTH)
    testing.expect_value(t, regions.world_rect.height, app_ui.VIEW_HEIGHT)
    testing.expect_value(t, regions.tree_rect.x, app_ui.VIEW_WIDTH + app_ui.TREE_PANEL_PADDING)
    testing.expect_value(t, regions.text_rect.y, app_ui.VIEW_HEIGHT + app_ui.TREE_PANEL_PADDING)
    testing.expect_value(t, regions.settings_rect.width, regions.gif_rect.width)
    testing.expect_value(t, regions.settings_rect.height, regions.gif_rect.height)
    testing.expect(t, regions.scratchpad_rect.width >= 0)
    testing.expect(t, regions.scratchpad_rect.height >= 0)
}

@(test)
validate_ui_regions_rejects_negative_dimensions :: proc(t: ^testing.T) {
    regions := app_core.Ui_Regions{}
    regions.world_rect = rl.Rectangle{0, 0, -1, 10}

    testing.expect(t, !app_ui.validate_ui_regions(regions))

    regions.world_rect = rl.Rectangle{0, 0, 1, 10}
    regions.tree_rect = rl.Rectangle{0, 0, 10, -1}
    testing.expect(t, !app_ui.validate_ui_regions(regions))
}

@(test)
scrollbar_thumb_math_clamps_and_positions_correctly :: proc(t: ^testing.T) {
    thumb_h := app_ui.scrollbar_thumb_height(100, 1000, 24)
    testing.expect(t, thumb_h >= 24)
    testing.expect(t, thumb_h <= 100)

    y_top := app_ui.scrollbar_thumb_y(50, 100, thumb_h, 0, 300)
    y_bottom := app_ui.scrollbar_thumb_y(50, 100, thumb_h, 300, 300)
    testing.expect_value(t, y_top, f32(50))
    testing.expect_value(t, y_bottom, f32(150) - thumb_h)

    panel := rl.Rectangle{10, 20, 200, 120}
    track, thumb, built_thumb_h, has_scrollbar := app_ui.build_vertical_scrollbar(
        panel, 480, 60, 360, 8, 24)
    testing.expect(t, has_scrollbar)
    testing.expect_value(t, track.x, panel.x + panel.width - 8)
    testing.expect_value(t, built_thumb_h, thumb.height)
}

@(test)
text_wrapping_helpers_handle_empty_and_long_tokens :: proc(t: ^testing.T) {
    testing.expect_value(t, app_ui.chars_per_text_row(0, 8), 1)
    testing.expect_value(t, app_ui.count_wrapped_text_rows("", 20), 1)

    text := "supercalifragilistic"
    line_start, line_end, next_start := app_ui.next_wrapped_text_span(text, 0, 4)

    testing.expect_value(t, line_start, 0)
    testing.expect(t, line_end > line_start)
    testing.expect(t, next_start > line_start)

    rows := app_ui.count_wrapped_text_rows("aaaa bbbb cccc", 4)
    testing.expect(t, rows >= 3)
}

seed_tree_node :: proc(
    ji: ^app_core.Euclid_Julia_Interface,
    id: int,
    parent_id: int,
    first_child_id: int,
    next_sibling: int,
    expanded: bool) {
    ji.animations[id].parent_id = parent_id
    ji.animations[id].first_child_id = first_child_id
    ji.animations[id].next_sibling = next_sibling
    ji.animations[id].is_expanded = expanded
}

@(test)
tree_row_count_respects_expansion_state :: proc(t: ^testing.T) {
    ji := app_core.Euclid_Julia_Interface{}
    ji.next_animation_index = 3

    // root(0) -> child(1) -> sibling(2)
    seed_tree_node(&ji, 0, -1, 1, -1, true)
    seed_tree_node(&ji, 1, 0, -1, 2, false)
    seed_tree_node(&ji, 2, 0, -1, -1, false)

    count_expanded := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_expanded, 3)

    ji.animations[0].is_expanded = false
    count_collapsed := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_collapsed, 1)

    testing.expect_value(t, app_ui.expanded_first_child_id(false, 1), -1)
    testing.expect_value(t, app_ui.expanded_first_child_id(true, 1), 1)
}

@(test)
build_tree_view_panels_clamps_small_panels :: proc(t: ^testing.T) {
    panel := rl.Rectangle{0, 0, 8, 8}
    toolbar, list := app_ui.build_tree_view_panels(panel)

    testing.expect(t, toolbar.height == app_ui.TREE_TOOLBAR_HEIGHT)
    testing.expect(t, list.width >= 0)
    testing.expect(t, list.height >= 0)
}
