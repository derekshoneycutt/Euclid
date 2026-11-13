package uianimation

import geometry "../../../core/geometry"
import dyncore "../../../dynview/core"
import theme "../theme"

EXERCISE_HEADER_PANEL_ID :: 2107
EXERCISE_HEADER_CLOSE_BUTTON_ID :: 2108
EXERCISE_HEADER_DISCLOSURE_BUTTON_ID :: 2109
EXERCISE_HEADER_SCROLLBAR_ID :: 2110
EXERCISE_HEADER_PROMPT_ID :: EXERCISE_HEADER_PANEL_ID

Exercise_Header_Slots :: struct {
    panel: geometry.Rectangle,
    text: geometry.Rectangle,
    disclosure: geometry.Rectangle,
    close: geometry.Rectangle,
    scroll: geometry.Rectangle,
    content: geometry.Rectangle,
}

Exercise_Header_Layout :: struct {
    slots: Exercise_Header_Slots,
    overflow: bool,
    expanded: bool,
    preview_rows: int,
    content_rows: int,
    preview_length: int,
    content_height: f32,
}

Exercise_Header_Metrics :: struct {
    scale: f32,
    padding: f32,
    requested_button: f32,
    gap: f32,
    edge: f32,
    wrap_advance: f32,
    text_size_percent: int,
}

Exercise_Header_Row_Slots :: struct {
    close: geometry.Rectangle,
    disclosure: geometry.Rectangle,
    text: geometry.Rectangle,
}

Exercise_Header_Layout_Request :: struct {
    world: geometry.Rectangle,
    source: string,
    requested_expanded: bool,
    overflow: bool,
    preview_rows: int,
    metrics: Exercise_Header_Metrics,
}

// Measure wrapping and place the bounded prompt overlay within the board.
exercise_header_layout :: proc(
    world: geometry.Rectangle, source: string,
    expanded: bool,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT,
    text_size_percent := theme.TEXT_SIZE_DEFAULT_PERCENT) -> Exercise_Header_Layout {
    metrics := exercise_header_metrics(control_size_percent, text_size_percent)
    preview_row_height := exercise_header_row_height(world, metrics)
    preview_button := exercise_header_button_size(
        preview_row_height, metrics.padding, metrics.requested_button)
    preview_panel := exercise_header_panel(
        world, metrics, preview_row_height, preview_button)
    no_disclosure := exercise_header_row_slots(
        preview_panel, metrics.padding, preview_button, metrics.gap, false)
    max_preview_chars := dyncore.chars_per_text_row(
        max(f32(0), no_disclosure.text.width), metrics.wrap_advance)
    preview_rows := dyncore.count_wrapped_text_rows(source, max_preview_chars)
    overflow := preview_rows > 1
    return exercise_header_finish_layout({
        world = world,
        source = source,
        requested_expanded = expanded,
        overflow = overflow,
        preview_rows = preview_rows,
        metrics = metrics,
    })
}

// Resolve expanded geometry after the measured preview decides disclosure visibility.
exercise_header_finish_layout :: proc(
    request: Exercise_Header_Layout_Request) -> Exercise_Header_Layout {
    world := request.world
    metrics := request.metrics
    expanded := request.requested_expanded && request.overflow
    height_limit := max(f32(0), world.height-metrics.edge)
    if expanded {
        height_limit = min(height_limit, max(f32(0), world.height/3))
    }
    row_height := min(metrics.requested_button+metrics.padding*2, height_limit)
    button_size := exercise_header_button_size(
        row_height, metrics.padding, metrics.requested_button)
    panel := exercise_header_panel(world, metrics, row_height, button_size)
    row_slots := exercise_header_row_slots(
        panel, metrics.padding, button_size, metrics.gap, request.overflow)
    span := dyncore.next_wrapped_text_span(
        request.source, 0, dyncore.chars_per_text_row(
            row_slots.text.width, metrics.wrap_advance))
    result: Exercise_Header_Layout = {
        slots = {
            panel = panel,
            text = row_slots.text,
            disclosure = row_slots.disclosure,
            close = row_slots.close,
        },
        overflow = request.overflow,
        expanded = expanded,
        preview_rows = request.preview_rows,
        preview_length = span.line_end,
    }
    if !expanded {
        return result
    }
    exercise_header_expand_layout(world, request.source, metrics, &result)
    return result
}

// Add a one-third-height scrolling viewport and measure its wrapped content.
exercise_header_expand_layout :: proc(
    world: geometry.Rectangle, source: string, metrics: Exercise_Header_Metrics,
    layout: ^Exercise_Header_Layout) {
    panel := layout^.slots.panel
    row_height := panel.height
    max_view_height := max(f32(0), min(world.height/3, world.height-(panel.y-world.y)))
    scrollbar_width := theme.SCROLLBAR_WIDTH * metrics.scale
    body_width := max(f32(0), panel.width-metrics.padding*2)
    text_width := max(f32(0), body_width-scrollbar_width)
    body_text_rect: geometry.Rectangle = {
        panel.x+metrics.padding, panel.y+row_height+metrics.padding, text_width, 0,
    }
    max_chars := dyncore.chars_per_text_row(
        max(f32(0), body_text_rect.width-metrics.padding*2), metrics.wrap_advance)
    rows := dyncore.count_wrapped_text_rows(source, max_chars)
    row_height_text := theme.ui_scaled_metric(
        theme.TEXT_ROW_HEIGHT, metrics.text_size_percent)
    content_height := f32(rows)*row_height_text+metrics.padding*2
    max_text_height := max(
        f32(0), max_view_height-row_height-metrics.padding*2)
    viewport_height := min(content_height, max_text_height)
    layout^.slots.panel.height = row_height + metrics.padding*2 + viewport_height
    layout^.slots.scroll = {
        panel.x+metrics.padding, panel.y+row_height+metrics.padding,
        body_width, viewport_height,
    }
    layout^.slots.content = body_text_rect
    layout^.slots.content.height = viewport_height
    layout^.content_rows = rows
    layout^.content_height = content_height
}

// Keep the preview text area clear of its disclosure and close buttons.
exercise_header_row_slots :: proc(
    panel: geometry.Rectangle, padding, button_size, gap: f32,
    overflow: bool) -> Exercise_Header_Row_Slots {
    result: Exercise_Header_Row_Slots = {
        close = {
            panel.x+max(0, panel.width-padding-button_size),
            panel.y+(panel.height-button_size)*0.5,
            min(button_size, max(0, panel.width-padding)),
            button_size,
        },
    }
    text_x := panel.x+padding
    if overflow {
        result.disclosure = {text_x, panel.y+(panel.height-button_size)*0.5,
            button_size, button_size}
        text_x += button_size+gap
    }
    result.text = {
        text_x, panel.y,
        max(0, result.close.x-gap-text_x), panel.height,
    }
    return result
}

// Derive display scale and measured text metrics from the current preferences.
exercise_header_metrics :: proc(
    control_size_percent, text_size_percent: int) -> Exercise_Header_Metrics {
    scale := theme.ui_control_size_scale(control_size_percent)
    return {
        scale = scale,
        padding = theme.ANIMATION_CONTROL_PADDING * scale,
        requested_button = theme.ANIMATION_CONTROL_BUTTON_SIZE * scale,
        gap = theme.ANIMATION_CONTROL_BUTTON_GAP * scale,
        edge = theme.ANIMATION_CONTROL_EDGE_INSET * scale,
        wrap_advance = theme.ui_scaled_metric(
            theme.TEXT_WRAP_ADVANCE, text_size_percent),
        text_size_percent = text_size_percent,
    }
}

// Place a row before or after disclosure visibility is known.
exercise_header_panel :: proc(
    world: geometry.Rectangle, metrics: Exercise_Header_Metrics,
    row_height, button_size: f32) -> geometry.Rectangle {
    panel_width := max(
        f32(0), world.width-metrics.edge*2-button_size-metrics.gap)
    return {
        world.x+metrics.edge, world.y+metrics.edge, panel_width, row_height,
    }
}

// Compute a safe square button size for compact board heights.
exercise_header_button_size :: #force_inline proc(
    row_height, padding, requested: f32) -> f32 {
    return max(f32(0), min(requested, row_height-padding*2))
}

// Compute the collapsed row's board-clipped height before overflow is known.
exercise_header_row_height :: #force_inline proc(
    world: geometry.Rectangle, metrics: Exercise_Header_Metrics) -> f32 {
    available := max(f32(0), world.height-metrics.edge)
    return min(metrics.requested_button+metrics.padding*2, available)
}

// Build the text span used before a header has a measured source layout.
exercise_header_layout_slots :: proc(
    world: geometry.Rectangle,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> Exercise_Header_Slots {
    empty := exercise_header_layout(
        world, " ", false, control_size_percent)
    return empty.slots
}
