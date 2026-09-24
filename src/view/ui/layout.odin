package ui

import viewmodel "../model"
import geometry "../../core/geometry"

AUTO_PORTRAIT_ASPECT_THRESHOLD :: f32(0.9)
AUTO_LANDSCAPE_ASPECT_THRESHOLD :: f32(1.1)

//   Resolve the first layout deterministically from preference and startup extent.
resolve_initial_layout_mode :: proc(
    preference: viewmodel.Layout_Preference,
    width, height: f32) -> viewmodel.Ui_Layout_Mode {
    if preference == .Landscape { return .Landscape }
    if preference == .Portrait { return .Portrait }
    if width / max(height, f32(1)) < AUTO_PORTRAIT_ASPECT_THRESHOLD {
        return .Portrait
    }
    return .Landscape
}

//   Resolve forced layout or apply automatic orientation hysteresis.
resolve_layout_mode :: proc(
    preference: viewmodel.Layout_Preference,
    current: viewmodel.Ui_Layout_Mode,
    width, height: f32) -> viewmodel.Ui_Layout_Mode {
    if preference == .Landscape { return .Landscape }
    if preference == .Portrait { return .Portrait }
    aspect := width / max(height, f32(1))
    if current == .Landscape && aspect < AUTO_PORTRAIT_ASPECT_THRESHOLD {
        return .Portrait
    }
    if current == .Portrait && aspect > AUTO_LANDSCAPE_ASPECT_THRESHOLD {
        return .Landscape
    }
    return current
}

//   Clamp one split against preferred minima or the available compact extent.
layout_clamp_split :: #force_inline proc(
    value, extent, first_minimum, second_minimum: f32) -> f32 {
    if extent >= first_minimum + second_minimum {
        return clamp(value, first_minimum, extent - second_minimum)
    }
    return clamp(value, f32(0), max(f32(0), extent))
}

//   Build the non-negative Terminal content rectangle inside the text panel.
layout_terminal_rect :: proc(text_rect: viewmodel.Rectangle) -> viewmodel.Rectangle {
    return viewmodel.Rectangle(clamp_non_negative_rect({
        text_rect.x + 6,
        text_rect.y + 6,
        text_rect.width - 12,
        text_rect.height - 12,
    }))
}

//   Fill landscape-specific world, accordion, and presentation rectangles.
layout_landscape_regions :: proc(
    regions: ^viewmodel.Ui_Regions, width, height, split_x, split_y: f32) {
    regions^.world_rect = {0, 0, split_x, split_y}
    regions^.accordion_rect = viewmodel.Rectangle(clamp_non_negative_rect({
        split_x + TREE_PANEL_PADDING, TREE_PANEL_PADDING,
        width - split_x - TREE_PANEL_PADDING * 2,
        height - TREE_PANEL_PADDING * 2}))
    regions^.text_rect = viewmodel.Rectangle(clamp_non_negative_rect({
        TREE_PANEL_PADDING, split_y + TREE_PANEL_PADDING,
        split_x - TREE_PANEL_PADDING * 2,
        height - split_y - TREE_PANEL_PADDING * 2}))
    regions^.terminal_rect = layout_terminal_rect(regions^.text_rect)
}

//   Compute UI regions from the active layout's clamped split coordinates.
compute_ui_regions :: proc(
    mode: viewmodel.Ui_Layout_Mode,
    window_width, window_height: f32,
    vertical_split_x, horizontal_split_y: f32) -> viewmodel.Ui_Regions {
    regions := viewmodel.Ui_Regions{}
    width := max(f32(0), window_width)
    height := max(f32(0), window_height)
    split_y := layout_clamp_split(horizontal_split_y, height,
        WORLD_MIN_HEIGHT, BOTTOM_PANEL_MIN_HEIGHT)

    switch mode {
    case .Landscape:
        split_x := layout_clamp_split(vertical_split_x, width,
            WORLD_MIN_WIDTH, RIGHT_PANEL_MIN_WIDTH)
        layout_landscape_regions(&regions, width, height, split_x, split_y)
    case .Portrait:
        regions.world_rect = viewmodel.Rectangle{0, 0, width, split_y}
        regions.accordion_rect = viewmodel.Rectangle(clamp_non_negative_rect({
            TREE_PANEL_PADDING,
            split_y + TREE_PANEL_PADDING,
            width - TREE_PANEL_PADDING * 2,
            height - split_y - TREE_PANEL_PADDING * 2,
        }))
        sections := accordion_portrait_sections("")
        view_layout := accordion_layout(
            geometry.Rectangle(regions.accordion_rect), sections, .View)
        regions.text_rect = viewmodel.Rectangle(view_layout.content)
        regions.terminal_rect = layout_terminal_rect(regions.text_rect)
    }

    return regions
}

//   Validate region geometry before draw dispatch.
//   Report whether one rectangle has non-negative dimensions.
ui_rect_valid :: #force_inline proc(rect: viewmodel.Rectangle) -> bool {
    return rect.width >= 0 && rect.height >= 0
}

//   Validate that every UI region has non-negative dimensions.
validate_ui_regions :: proc(regions: viewmodel.Ui_Regions) -> bool {
    rects := [?]viewmodel.Rectangle{
        regions.world_rect,
        regions.accordion_rect,
        regions.text_rect,
        regions.terminal_rect,
    }
    for rect in rects {
        if !ui_rect_valid(rect) {
            return false
        }
    }

    return true
}
