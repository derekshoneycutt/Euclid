package ui

import viewmodel "../model"
import input "../input"
import geometry "../../core/geometry"

import "core:testing"

TOOLTIP_TEST_WINDOW :: geometry.Rectangle{0, 0, 400, 300}

// tooltip_test_offer constructs one bounded offer for an animation-control owner.
tooltip_test_offer :: proc(
    local_id: u64, source: viewmodel.Ui_Tooltip_Source,
    text: string = "Restart animation") -> Tooltip_Offer {
    return {
        owner = semantic_test_id(.Animation_Control, local_id),
        source = source,
        anchor = {100, 100, 24, 24},
        text = text,
    }
}

// tooltip_test_frame runs one focused, unsuppressed prepare pass carrying at most one
// offer; callers override gates through `facts`, whose time is replaced by `now_seconds`.
tooltip_test_frame :: proc(
    tooltip: ^viewmodel.Ui_Tooltip_State, offer: Maybe(Tooltip_Offer),
    now_seconds: f64, facts: Tooltip_Frame_Facts = {window_focused = true}) {
    tooltip_frame_begin(tooltip)
    if value, present := offer.?; present {
        tooltip_offer(tooltip, value)
    }
    resolved := facts
    resolved.now_seconds = now_seconds
    tooltip_frame_resolve(tooltip, resolved)
}

// Verify placement prefers below, flips above near the bottom, and clamps horizontally.
@(test)
tooltip_place_prefers_below_and_flips_above :: proc(t: ^testing.T) {
    size := geometry.Vector2{80, 22}
    below := tooltip_place({100, 100, 24, 24}, size, TOOLTIP_TEST_WINDOW)
    testing.expect_value(t, below, geometry.Rectangle{72, 130, 80, 22})

    above := tooltip_place({100, 270, 24, 24}, size, TOOLTIP_TEST_WINDOW)
    testing.expect_value(t, above, geometry.Rectangle{72, 242, 80, 22})

    left := tooltip_place({0, 100, 24, 24}, size, TOOLTIP_TEST_WINDOW)
    testing.expect_value(t, left.x, TOOLTIP_WINDOW_MARGIN)
    right := tooltip_place({390, 100, 10, 24}, size, TOOLTIP_TEST_WINDOW)
    testing.expect_value(t, right.x, f32(400) - TOOLTIP_WINDOW_MARGIN - 80)
}

// Verify an anchor with no room on either side clamps into the window margins.
@(test)
tooltip_place_clamps_when_neither_side_fits :: proc(t: ^testing.T) {
    window := geometry.Rectangle{0, 0, 200, 60}
    box := tooltip_place({10, 10, 20, 40}, {40, 22}, window)
    testing.expect(t, box.y >= TOOLTIP_WINDOW_MARGIN)
    testing.expect(t, box.y + box.height <= 60 - TOOLTIP_WINDOW_MARGIN)

    oversized := tooltip_place({10, 10, 20, 20}, {500, 22}, window)
    testing.expect_value(t, oversized.x, TOOLTIP_WINDOW_MARGIN)
}

// Verify bounded text storage never splits a UTF-8 codepoint.
@(test)
tooltip_text_truncates_at_codepoint_boundary :: proc(t: ^testing.T) {
    text: [viewmodel.UI_TOOLTIP_TEXT_CAPACITY + 1]u8
    for index in 0 ..< len(text) - 2 {
        text[index] = 'a'
    }
    text[len(text) - 2] = 0xC3
    text[len(text) - 1] = 0xA9
    content: viewmodel.Ui_Tooltip_Content
    tooltip_copy_text(&content, string(text[:]))
    testing.expect_value(t, content.text_length, viewmodel.UI_TOOLTIP_TEXT_CAPACITY - 1)
}

// Verify pointer hover waits for the delay, then neighbours switch while warm.
@(test)
tooltip_pointer_hover_delay_and_warm_switching :: proc(t: ^testing.T) {
    tooltip: viewmodel.Ui_Tooltip_State
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Pointer), 1.0)
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Pointer), 1.49)
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Pointer), 1.5)
    testing.expect(t, tooltip.visible)

    tooltip_test_frame(&tooltip, tooltip_test_offer(2, .Pointer, "Pause"), 1.6)
    testing.expect(t, tooltip.visible)
    testing.expect_value(t, string(tooltip.shown.text[:tooltip.shown.text_length]),
        "Pause")

    tooltip_test_frame(&tooltip, nil, 1.7)
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Pointer), 2.5)
    testing.expect(t, !tooltip.visible)
}

// Verify keyboard offers show immediately and a pointer offer takes precedence.
@(test)
tooltip_keyboard_immediate_and_pointer_precedence :: proc(t: ^testing.T) {
    tooltip: viewmodel.Ui_Tooltip_State
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.0)
    testing.expect(t, tooltip.visible)

    tooltip_frame_begin(&tooltip)
    tooltip_offer(&tooltip, tooltip_test_offer(2, .Pointer, "Pause"))
    tooltip_offer(&tooltip, tooltip_test_offer(1, .Keyboard))
    testing.expect_value(t, tooltip.offer.source, viewmodel.Ui_Tooltip_Source.Pointer)
    testing.expect_value(t, tooltip.offer.owner,
        semantic_test_id(.Animation_Control, 2))
}

// Verify dismissal persists for the same owner and clears when the owner changes.
@(test)
tooltip_dismissal_persists_until_owner_changes :: proc(t: ^testing.T) {
    tooltip: viewmodel.Ui_Tooltip_State
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.0,
        {window_focused = true, dismiss = true})
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.1)
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(2, .Keyboard), 1.2)
    testing.expect(t, tooltip.visible)

    tooltip_frame_begin(&tooltip)
    tooltip_dismiss(&tooltip, semantic_test_id(.Animation_Control, 2))
    tooltip_offer(&tooltip, tooltip_test_offer(2, .Pointer))
    tooltip_frame_resolve(&tooltip, {now_seconds = 1.3, window_focused = true})
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, nil, 1.4)
    tooltip_test_frame(&tooltip, tooltip_test_offer(2, .Keyboard), 1.5)
    testing.expect(t, tooltip.visible)
}

// Verify GIF suppression and lost window focus hide an otherwise ready tooltip.
@(test)
tooltip_suppression_and_unfocused_window_hide :: proc(t: ^testing.T) {
    tooltip: viewmodel.Ui_Tooltip_State
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.0,
        {window_focused = true, suppressed = true})
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.1, {})
    testing.expect(t, !tooltip.visible)
    tooltip_test_frame(&tooltip, tooltip_test_offer(1, .Keyboard), 1.2)
    testing.expect(t, tooltip.visible)
}

// Verify control source detection follows the routed pointer and keyboard focus rule.
@(test)
tooltip_control_source_follows_pointer_and_keyboard_focus :: proc(t: ^testing.T) {
    owner := semantic_test_id(.Animation_Control, 7)
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    focus^.window_focused = true
    focus^.logical_focus = owner
    focus^.focus_origin = .Keyboard
    runtime: viewmodel.Euclid_Ui_Runtime_State
    runtime.semantic_focus = focus
    testing.expect_value(t, tooltip_control_source(&runtime, owner, 7),
        viewmodel.Ui_Tooltip_Source.Keyboard)

    focus^.focus_origin = .Pointer
    testing.expect_value(t, tooltip_control_source(&runtime, owner, 7),
        viewmodel.Ui_Tooltip_Source.None)

    runtime.interaction_frame.pointer_target = {kind = .Control, id = 7}
    testing.expect_value(t, tooltip_control_source(&runtime, owner, 7),
        viewmodel.Ui_Tooltip_Source.Pointer)
}

// Verify only an Escape press requests tooltip dismissal.
@(test)
tooltip_escape_press_requests_dismissal :: proc(t: ^testing.T) {
    events := [?]input.Input_Event{{kind = .Release, key = .Escape}}
    testing.expect(t, !tooltip_escape_pressed({events = events[:]}))
    events[0].kind = .Press
    testing.expect(t, tooltip_escape_pressed({events = events[:]}))
}
