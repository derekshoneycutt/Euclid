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
    collections_heading_y: f32,
    export_list: geometry.Rectangle,
    export_buttons: geometry.Rectangle,
    import_heading_y: f32,
    import_list: geometry.Rectangle,
    not_importable_heading_y: f32,
    not_importable_list: geometry.Rectangle,
    import_buttons: geometry.Rectangle,
    collections_status_y: f32,
    collection_row_height: f32,
}

// Sharing_Layout_Options carries one consistent viewport and collection snapshot.
Sharing_Layout_Options :: struct {
    text_percent: int,
    control_percent: int,
    scroll_y: f32,
    export_count: int,
    importable_count: int,
    warning_count: int,
    non_importable_count: int,
    has_import: bool,
    collections_start_y: f32,
}

Sharing_Layout_Metrics :: struct {
    inset: f32,
    gap: f32,
    row: f32,
    button_height: f32,
    width: f32,
}

// Resolve stable section rows, reserving path space so successful saves do not move GIF.
sharing_layout :: proc(
    panel: geometry.Rectangle,
    options: Sharing_Layout_Options) -> Sharing_Layout {
    metrics := sharing_layout_metrics(panel, options)
    y := panel.y + metrics.inset - options.scroll_y
    path_height := metrics.button_height
    status_gap := theme.ui_control_scaled_metric(
        theme.SETTINGS_PANEL_INSET * 0.75,
        options.text_percent, options.control_percent)
    label_width := theme.ui_scaled_metric(42, options.text_percent)
    status_y := y + metrics.row * 2 + metrics.button_height + status_gap
    path_y := status_y + metrics.row
    gif_y := path_y + path_height + metrics.row
    layout: Sharing_Layout = {
        png_heading_y = y,
        description_y = y + metrics.row,
        button = {
            panel.x + metrics.inset, y + metrics.row * 2,
            metrics.width, metrics.button_height,
        },
        status_y = status_y,
        path = {
            panel.x + metrics.inset + label_width,
            path_y,
            max(f32(0), metrics.width - label_width),
            path_height,
        },
        gif_heading_y = gif_y,
        gif_panel = {
            panel.x,
            gif_y + metrics.row - theme.ui_control_size_metric(
                theme.SETTINGS_HEADER_TOP_OFFSET, options.control_percent),
            metrics.width + metrics.inset * 2,
            panel.height,
        },
    }
    sharing_layout_collections(panel, options, metrics, &layout)
    return layout
}

// Resolve the bounded rows below GIF without coupling layout to the GIF package.
sharing_layout_collections :: proc(
    panel: geometry.Rectangle, options: Sharing_Layout_Options,
    metrics: Sharing_Layout_Metrics, layout: ^Sharing_Layout) {
    collection_x := panel.x + metrics.inset
    layout^.collections_heading_y = options.collections_start_y
    layout^.collection_row_height = max(metrics.row,
        theme.ui_control_size_metric(24, options.control_percent))
    layout.export_list = {
        collection_x, layout^.collections_heading_y + metrics.row,
        metrics.width, f32(options.export_count) * layout^.collection_row_height,
    }
    layout^.export_buttons = {
        collection_x,
        layout^.export_list.y + layout^.export_list.height + metrics.gap,
        metrics.width, metrics.button_height,
    }
    if !options.has_import {
        layout^.collections_status_y =
            layout^.export_buttons.y + metrics.button_height + metrics.gap
        return
    }
    layout^.import_heading_y =
        layout^.export_buttons.y + metrics.button_height + metrics.gap
    layout^.import_list = {
        collection_x, layout^.import_heading_y + metrics.row, metrics.width,
        f32(options.importable_count + options.warning_count) *
            layout^.collection_row_height,
    }
    next_y := layout^.import_list.y + layout^.import_list.height + metrics.gap
    if options.non_importable_count > 0 {
        layout^.not_importable_heading_y = next_y
        layout^.not_importable_list = {
            collection_x, next_y + metrics.row, metrics.width,
            f32(options.non_importable_count) *
                layout^.collection_row_height * 2,
        }
        next_y = layout^.not_importable_list.y +
            layout^.not_importable_list.height + metrics.gap
    }
    layout^.import_buttons = {
        collection_x, next_y, metrics.width, metrics.button_height,
    }
    layout^.collections_status_y =
        layout^.import_buttons.y + metrics.button_height + metrics.gap
}

// Resolve shared spacing and button metrics once for the complete Sharing surface.
sharing_layout_metrics :: proc(
    panel: geometry.Rectangle,
    options: Sharing_Layout_Options) -> Sharing_Layout_Metrics {
    inset := theme.ui_control_size_metric(
        theme.SETTINGS_PANEL_INSET, options.control_percent)
    gap := theme.ui_control_size_metric(10, options.control_percent)
    row := theme.ui_font_size(options.text_percent) + gap
    width := max(f32(0), panel.width - inset * 2 -
        theme.ui_control_size_metric(theme.SCROLLBAR_WIDTH, options.control_percent))
    return {
        inset = inset,
        gap = gap,
        row = row,
        button_height = theme.ui_panel_button_height(
            options.text_percent, options.control_percent),
        width = width,
    }
}

// Resolve the same scrolled geometry before pointer routing and widget preparation.
sharing_layout_for_runtime :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> Sharing_Layout {
    preferences := runtime.preferences.values.interface
    return sharing_layout(
        uiaccordion.accordion_content_rect(&runtime.layout, .Save_Gif), {
            text_percent = preferences.text_size_percent,
            control_percent = preferences.control_size_percent,
            scroll_y = runtime.sharing.scroll_y,
        })
}
