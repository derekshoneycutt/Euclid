package sharinglayout

import geometry "../../../../core/geometry"
import viewmodel "../../model"
import theme "../../theme"
import uiaccordion "../accordion"

// Sharing_Layout keeps both sections and the saved-path hit target in one coordinate system.
Sharing_Layout :: struct {
    png_heading_y: f32,
    description_y: f32,
    button: geometry.Rectangle,
    status_y: f32,
    path: geometry.Rectangle,
    gif_heading_y: f32,
    gif_panel: geometry.Rectangle,
}

// Resolve stable section rows, reserving path space so successful saves do not move GIF.
sharing_layout :: proc(
    panel: geometry.Rectangle, text_percent, control_percent: int,
    scroll_y: f32) -> Sharing_Layout {
    inset := theme.ui_control_size_metric(theme.SETTINGS_PANEL_INSET, control_percent)
    gap := theme.ui_control_size_metric(10, control_percent)
    font := theme.ui_font_size(text_percent)
    row := font + gap
    width := max(f32(0), panel.width - inset * 2 -
        theme.ui_control_size_metric(theme.SCROLLBAR_WIDTH, control_percent))
    y := panel.y + inset - scroll_y
    button_height := max(font + gap * 2,
        theme.ui_control_size_metric(32, control_percent))
    path_height := max(font + gap, theme.ui_control_size_metric(24, control_percent))
    label_width := theme.ui_scaled_metric(42, text_percent)
    gif_y := y + row * 4 + button_height + path_height + gap
    return {
        png_heading_y = y,
        description_y = y + row,
        button = {panel.x + inset, y + row * 2, width, button_height},
        status_y = y + row * 2 + button_height + gap,
        path = {panel.x + inset + label_width,
            y + row * 3 + button_height + gap,
            max(f32(0), width - label_width), path_height},
        gif_heading_y = gif_y,
        gif_panel = {panel.x, gif_y + row, width + inset * 2, panel.height},
    }
}

// Resolve the same scrolled geometry before pointer routing and widget preparation.
sharing_layout_for_runtime :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> Sharing_Layout {
    preferences := runtime.preferences.values.interface
    return sharing_layout(
        uiaccordion.accordion_content_rect(&runtime.layout, .Save_Gif),
        preferences.text_size_percent, preferences.control_size_percent,
        runtime.sharing.scroll_y)
}
