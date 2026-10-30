package magnifier

import geometry "../../core/geometry"
import viewmodel "../ui/model"

MAGNIFIER_LENS_WIDTH :: 240.0
MAGNIFIER_LENS_HEIGHT :: 160.0
MAGNIFIER_LENS_GAP :: 16.0
MAGNIFIER_EDGE_PADDING :: 8.0
MAGNIFIER_ZOOM :: 2.5
MAGNIFIER_MOTION_RATE :: 14.0

// Magnifier_Frame_Input groups the bounded observations for one display frame.
Magnifier_Frame_Input :: struct {
    enabled: bool,
    input_lock: bool,
    caret_anchor: geometry.Rectangle,
    caret_clip: geometry.Rectangle,
    caret_valid: bool,
    window_focused: bool,
    reduce_motion: bool,
    pointer: geometry.Vector2,
    width: f32,
    height: f32,
    delta_seconds: f32,
}

// Magnifier_Anchor contains one validated source point and its requested lens bounds.
Magnifier_Anchor :: struct {
    valid: bool,
    source: geometry.Vector2,
    lens_rect: geometry.Rectangle,
}

// Prepare the selected pointer- or caret-anchored lens in logical display coordinates.
magnifier_prepare :: proc(
    state: ^viewmodel.Ui_Magnifier_State, frame: Magnifier_Frame_Input) ->
        viewmodel.Ui_Magnifier_Presentation {
    if !frame.enabled || !frame.window_focused ||
        frame.width <= 0 || frame.height <= 0 {
        state^ = {}
        return {}
    }
    anchor := magnifier_resolve_anchor(frame)
    if !anchor.valid {
        state^ = {}
        return {}
    }
    desired := anchor.lens_rect
    if !state^.initialized || frame.reduce_motion ||
        state^.lens_rect.width != desired.width ||
        state^.lens_rect.height != desired.height {
        state^.lens_rect = desired
        state^.initialized = true
    } else {
        progress := clamp(frame.delta_seconds, f32(0), f32(0.05)) *
            MAGNIFIER_MOTION_RATE
        state^.lens_rect.x += (desired.x - state^.lens_rect.x) * progress
        state^.lens_rect.y += (desired.y - state^.lens_rect.y) * progress
    }
    return {true, anchor.source, state^.lens_rect}
}

// Resolve either the pointer or a visible caret without cross-mode fallback.
magnifier_resolve_anchor :: proc(frame: Magnifier_Frame_Input) -> Magnifier_Anchor {
    if frame.input_lock {
        caret, visible := magnifier_visible_caret(frame)
        if !frame.caret_valid || !visible {
            return {}
        }
        source: geometry.Vector2 = {
            caret.x + caret.width * 0.5,
            caret.y + caret.height * 0.5,
        }
        return {
            valid = true,
            source = source,
            lens_rect = magnifier_input_desired_rect(
                source, frame.width, frame.height),
        }
    }
    source := frame.pointer
    if source.x < 0 || source.y < 0 ||
        source.x >= frame.width || source.y >= frame.height {
        return {}
    }
    return {
        valid = true,
        source = source,
        lens_rect = magnifier_desired_rect(
            source, frame.width, frame.height),
    }
}

// Restrict an input caret to its prepared clip and the visible window.
magnifier_visible_caret :: proc(frame: Magnifier_Frame_Input) ->
    (geometry.Rectangle, bool) {
    caret := magnifier_intersection(frame.caret_anchor, frame.caret_clip)
    visible := magnifier_intersection(
        caret, {0, 0, frame.width, frame.height})
    return visible, visible.width > 0 && visible.height > 0
}

// Return the positive-area intersection of two prepared rectangles.
magnifier_intersection :: #force_inline proc(
    first, second: geometry.Rectangle) -> geometry.Rectangle {
    left := max(first.x, second.x)
    top := max(first.y, second.y)
    right := min(first.x + first.width, second.x + second.width)
    bottom := min(first.y + first.height, second.y + second.height)
    return {left, top, max(f32(0), right - left), max(f32(0), bottom - top)}
}

// Place above the pointer, flip below when necessary, then clamp inside the window.
magnifier_desired_rect :: proc(
    pointer: geometry.Vector2, width, height: f32) -> geometry.Rectangle {
    lens_width := min(MAGNIFIER_LENS_WIDTH, width)
    lens_height := min(MAGNIFIER_LENS_HEIGHT, height)
    max_x := max(f32(0), width - lens_width)
    max_y := max(f32(0), height - lens_height)
    x := clamp(pointer.x - lens_width * 0.5, f32(0), max_x)
    y := pointer.y - lens_height - MAGNIFIER_LENS_GAP
    if y < 0 {
        y = pointer.y + MAGNIFIER_LENS_GAP
    }
    y = clamp(y, f32(0), max_y)
    if x < MAGNIFIER_EDGE_PADDING && max_x >= MAGNIFIER_EDGE_PADDING {
        x = MAGNIFIER_EDGE_PADDING
    } else if x > max_x - MAGNIFIER_EDGE_PADDING &&
              max_x >= MAGNIFIER_EDGE_PADDING {
        x = max_x - MAGNIFIER_EDGE_PADDING
    }
    return {x, y, lens_width, lens_height}
}

// Place the caret lens on the side with room, then clamp it to the window.
magnifier_input_desired_rect :: proc(
    source: geometry.Vector2, width, height: f32) -> geometry.Rectangle {
    lens_width := min(MAGNIFIER_LENS_WIDTH, width)
    lens_height := min(MAGNIFIER_LENS_HEIGHT, height)
    max_x := max(f32(0), width - lens_width)
    max_y := max(f32(0), height - lens_height)
    x := clamp(source.x - lens_width * 0.5, f32(0), max_x)
    above_space := source.y - MAGNIFIER_LENS_GAP
    below_space := height - source.y - MAGNIFIER_LENS_GAP
    y := source.y - lens_height - MAGNIFIER_LENS_GAP
    if above_space < lens_height && below_space > above_space {
        y = source.y + MAGNIFIER_LENS_GAP
    }
    return {x, clamp(y, f32(0), max_y), lens_width, lens_height}
}
