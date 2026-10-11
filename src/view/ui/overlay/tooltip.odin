package uioverlay

import view_font "../../font"
import input "../../input"
import native "../../native"
import core "../../../core"
import geometry "../../../core/geometry"
import viewmodel "../model"
import viewtext "../text"
import theme "../theme"

TOOLTIP_HOVER_DELAY_SECONDS :: f64(0.5)
TOOLTIP_WARM_SECONDS :: f64(0.35)
TOOLTIP_ANCHOR_GAP :: f32(6)
TOOLTIP_WINDOW_MARGIN :: f32(4)
TOOLTIP_PADDING_X :: f32(6)
TOOLTIP_HEIGHT :: f32(theme.TEXT_ROW_HEIGHT)

// Tooltip_Offer borrows one control's tooltip text for the current preparation pass.
Tooltip_Offer :: struct {
    owner: viewmodel.Ui_Node_Id,
    source: viewmodel.Ui_Tooltip_Source,
    anchor: geometry.Rectangle,
    text: string,
}

// Tooltip_Frame_Facts carries the frame-level inputs that gate tooltip visibility.
Tooltip_Frame_Facts :: struct {
    now_seconds: f64,
    window_focused: bool,
    suppressed: bool,
    dismiss: bool,
}

// tooltip_frame_begin clears the previous frame's offer before controls prepare.
tooltip_frame_begin :: proc(tooltip: ^viewmodel.Ui_Tooltip_State) {
    tooltip^.offer = {}
}

// tooltip_copy_text copies UTF-8 into bounded storage, truncating at a codepoint boundary.
tooltip_copy_text :: proc(content: ^viewmodel.Ui_Tooltip_Content, text: string) {
    length := min(len(text), len(content^.text))
    for length > 0 && length < len(text) && (text[length] & 0xC0) == 0x80 {
        length -= 1
    }
    copy(content^.text[:], text[:length])
    content^.text_length = length
}

// tooltip_offer proposes one tooltip; a pointer offer supersedes a keyboard offer.
tooltip_offer :: proc(tooltip: ^viewmodel.Ui_Tooltip_State, offer: Tooltip_Offer) {
    if offer.source == .None || len(offer.text) == 0 {
        return
    }
    if tooltip^.offer.source == .Pointer && offer.source != .Pointer {
        return
    }
    tooltip^.offer.owner = offer.owner
    tooltip^.offer.source = offer.source
    tooltip^.offer.anchor = geometry.Rectangle(offer.anchor)
    tooltip_copy_text(&tooltip^.offer, offer.text)
}

// tooltip_dismiss hides one owner's tooltip until a different owner is offered.
tooltip_dismiss :: proc(
    tooltip: ^viewmodel.Ui_Tooltip_State, owner: viewmodel.Ui_Node_Id) {
    tooltip^.dismissed_owner = owner
}

// tooltip_control_source reports whether pointer routing or keyboard focus reaches a control.
//
// Pointer reach uses the routed pointer target, so captures owned by other surfaces
// suppress hover. Keyboard reach matches the visible focus-outline rule.
tooltip_control_source :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    owner: viewmodel.Ui_Node_Id, control_id: int) -> viewmodel.Ui_Tooltip_Source {
    target := runtime^.interaction_frame.pointer_target
    if target.kind == .Control && target.id == control_id {
        return .Pointer
    }
    semantic := runtime^.semantic_focus
    if semantic != nil && semantic^.window_focused &&
        semantic^.focus_origin == .Keyboard && semantic^.logical_focus == owner {
        return .Keyboard
    }
    return .None
}

// tooltip_escape_pressed reports whether the frame carries an Escape key press.
tooltip_escape_pressed :: proc(frame: input.Input_Frame) -> bool {
    for event in frame.events {
        if event.kind == input.Input_Event_Kind.Press && event.key == .Escape {
            return true
        }
    }
    return false
}

// tooltip_offer_ready advances hover timing and reports whether the offer may show.
//
// Keyboard offers show immediately. Pointer offers wait for the hover delay unless a
// tooltip was visible recently, which lets adjacent controls switch without delay.
tooltip_offer_ready :: proc(
    tooltip: ^viewmodel.Ui_Tooltip_State, now_seconds: f64) -> bool {
    offer := tooltip^.offer
    if offer.source != .Pointer {
        tooltip^.hover_owner = {}
        return offer.source == .Keyboard
    }
    if offer.owner != tooltip^.hover_owner {
        tooltip^.hover_owner = offer.owner
        tooltip^.hover_started_seconds = now_seconds
    }
    return now_seconds <= tooltip^.warm_until_seconds ||
        now_seconds - tooltip^.hover_started_seconds >= TOOLTIP_HOVER_DELAY_SECONDS
}

// tooltip_frame_resolve commits this frame's visible tooltip from its offer and gates.
tooltip_frame_resolve :: proc(
    tooltip: ^viewmodel.Ui_Tooltip_State, facts: Tooltip_Frame_Facts) {
    if !facts.window_focused || facts.suppressed {
        tooltip^.offer = {}
    }
    offer := &tooltip^.offer
    if offer^.owner != tooltip^.dismissed_owner {
        tooltip^.dismissed_owner = {}
    }
    if facts.dismiss && offer^.source != .None {
        tooltip^.dismissed_owner = offer^.owner
    }
    ready := tooltip_offer_ready(tooltip, facts.now_seconds)
    tooltip^.visible = ready && offer^.source != .None &&
        offer^.owner != tooltip^.dismissed_owner
    if tooltip^.visible {
        tooltip^.shown = offer^
        tooltip^.warm_until_seconds = facts.now_seconds + TOOLTIP_WARM_SECONDS
    }
}

// tooltip_place positions a tooltip below its anchor, flipping above and clamping
// so the result stays inside the window margins whenever it fits.
tooltip_place :: proc(
    anchor: geometry.Rectangle, size: geometry.Vector2,
    window: geometry.Rectangle) -> geometry.Rectangle {
    left_limit := window.x + TOOLTIP_WINDOW_MARGIN
    right_limit := window.x + window.width - TOOLTIP_WINDOW_MARGIN - size.x
    x := anchor.x + (anchor.width - size.x) * 0.5
    x = max(left_limit, min(x, right_limit))
    top_limit := window.y + TOOLTIP_WINDOW_MARGIN
    bottom_limit := window.y + window.height - TOOLTIP_WINDOW_MARGIN
    below := anchor.y + anchor.height + TOOLTIP_ANCHOR_GAP
    above := anchor.y - TOOLTIP_ANCHOR_GAP - size.y
    y := below
    if below + size.y > bottom_limit {
        y = above
        if above < top_limit {
            room_below := bottom_limit - below
            room_above := anchor.y - TOOLTIP_ANCHOR_GAP - top_limit
            y = room_below >= room_above ? below : above
            y = max(top_limit, min(y, bottom_limit - size.y))
        }
    }
    return {x, y, size.x, size.y}
}

// draw_encoded_tooltip encodes the visible tooltip above all other UI content.
draw_encoded_tooltip :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    tooltip := &state^.ui_runtime.tooltip
    if !tooltip^.visible || tooltip^.shown.text_length == 0 {
        return
    }
    text := string(tooltip^.shown.text[:tooltip^.shown.text_length])
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    width, measured := viewtext.ui_text_measure_monospace(
        text, face, theme.TREE_FONT_SIZE, 0)
    if !measured {
        return
    }
    window := state^.ui_runtime.window
    box := tooltip_place(geometry.Rectangle(tooltip^.shown.anchor),
        {width + TOOLTIP_PADDING_X * 2, TOOLTIP_HEIGHT},
        {0, 0, f32(window.width), f32(window.height)})
    _ = native.draw_encoder_rectangle(encoder, box, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder, box, 1, theme.UI_BORDER_COLOR)
    viewtext.draw_encoded_label(
        &state^.font_cache, encoder, text, box.x + TOOLTIP_PADDING_X,
        box.y + (box.height - theme.TREE_FONT_SIZE) * 0.5)
}
