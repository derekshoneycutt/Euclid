package ui

import rl "vendor:raylib"

Stack_Axis :: enum {
    X,
    Y,
}

Stack_Panel_Cursor :: struct {
    offset: f32,
    segment_index: int,
    has_used_rect: bool,
    used_rect: rl.Rectangle,
}

Stack_Panel_Params :: struct {
    origin_x: f32,
    origin_y: f32,
    axis: Stack_Axis,
    direction_sign: int,
    rect: rl.Rectangle,
    can_expand: bool,
    segment_size_is_set: bool,
    segment_size: f32,
    segment_extent: f32,
    cursor_in: Stack_Panel_Cursor,
}

Stack_Panel_Result :: struct {
    segment_rect: rl.Rectangle,
    cursor_out: Stack_Panel_Cursor,
    stack_used_rect: rl.Rectangle,
}

//   Create a zeroed stack cursor for the first placement in a stack sequence.
stack_panel_cursor_zero :: #force_inline proc() -> Stack_Panel_Cursor {
    return Stack_Panel_Cursor{}
}

//   Normalize direction to +1 or -1 for deterministic stack placement.
stack_panel_direction_sign :: #force_inline proc(direction_sign: int) -> f32 {
    if direction_sign < 0 {
        return -1
    }
    return 1
}

//   Clamp rectangle on Y axis against bounds using intersection semantics.
stack_panel_clamp_y :: #force_inline proc(rect, bounds: rl.Rectangle) -> rl.Rectangle {
    top := max(rect.y, bounds.y)
    bottom := min(rect.y + rect.height, bounds.y + bounds.height)
    return rl.Rectangle{rect.x, top, rect.width, max(0.0, bottom - top)}
}

//   Clamp rectangle on X axis against bounds using intersection semantics.
stack_panel_clamp_x :: #force_inline proc(rect, bounds: rl.Rectangle) -> rl.Rectangle {
    left := max(rect.x, bounds.x)
    right := min(rect.x + rect.width, bounds.x + bounds.width)
    return rl.Rectangle{left, rect.y, max(0.0, right - left), rect.height}
}

//   Resolve the segment size from optional fixed size or caller-provided extent.
stack_panel_segment_size :: #force_inline proc(params: Stack_Panel_Params) -> f32 {
    size := params.segment_extent
    if params.segment_size_is_set {
        size = params.segment_size
    }
    return max(0.0, size)
}

//   Expand used geometry to include the latest segment rectangle.
stack_panel_accumulate_used_rect :: #force_inline proc(
    cursor_in: Stack_Panel_Cursor,
    segment_rect: rl.Rectangle) -> (bool, rl.Rectangle) {

    if !cursor_in.has_used_rect {
        return true, segment_rect
    }

    prev := cursor_in.used_rect
    left := min(prev.x, segment_rect.x)
    top := min(prev.y, segment_rect.y)
    right := max(prev.x + prev.width, segment_rect.x + segment_rect.width)
    bottom := max(prev.y + prev.height, segment_rect.y + segment_rect.height)
    return true, rl.Rectangle{left, top, max(0.0, right - left), max(0.0, bottom - top)}
}

//   Resolve one stack segment placement and advance cursor state.
stack_panel_place_segment :: proc(params: Stack_Panel_Params) -> Stack_Panel_Result {
    bounds := clamp_non_negative_rect(params.rect)
    direction := stack_panel_direction_sign(params.direction_sign)
    segment_size := stack_panel_segment_size(params)

    segment_rect := rl.Rectangle{}
    switch params.axis {
    case .Y:
        segment_rect.x = params.origin_x
        segment_rect.width = bounds.width
        segment_rect.height = segment_size
        if direction > 0 {
            segment_rect.y = params.origin_y + params.cursor_in.offset
        } else {
            segment_rect.y = params.origin_y - params.cursor_in.offset - segment_size
        }

        segment_rect = stack_panel_clamp_x(segment_rect, bounds)
        if !params.can_expand {
            segment_rect = stack_panel_clamp_y(segment_rect, bounds)
        }

    case .X:
        segment_rect.y = params.origin_y
        segment_rect.height = bounds.height
        segment_rect.width = segment_size
        if direction > 0 {
            segment_rect.x = params.origin_x + params.cursor_in.offset
        } else {
            segment_rect.x = params.origin_x - params.cursor_in.offset - segment_size
        }

        segment_rect = stack_panel_clamp_y(segment_rect, bounds)
        if !params.can_expand {
            segment_rect = stack_panel_clamp_x(segment_rect, bounds)
        }
    }

    segment_rect = clamp_non_negative_rect(segment_rect)
    has_used_rect, used_rect := stack_panel_accumulate_used_rect(params.cursor_in, segment_rect)

    cursor_out := Stack_Panel_Cursor{
        offset = params.cursor_in.offset + segment_size,
        segment_index = params.cursor_in.segment_index + 1,
        has_used_rect = has_used_rect,
        used_rect = used_rect,
    }

    return Stack_Panel_Result{
        segment_rect = segment_rect,
        cursor_out = cursor_out,
        stack_used_rect = used_rect,
    }
}