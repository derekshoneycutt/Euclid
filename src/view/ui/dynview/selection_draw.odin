package ui_dynview

import core "../../../core"
import geometry "../../../core/geometry"
import native "../../native"
import viewmodel "../model"
import theme "../theme"

// Presentation_Selection_Draw borrows one sealed presentation for clipped selection repainting.
Presentation_Selection_Draw :: struct {
    state: ^core.Euclid_General_State,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    fallback: Fallback_Text_Content,
    params: Presentation_Draw_Params,
}

// draw_presentation_selection_fragment repaints one visible selection without changing text layout.
draw_presentation_selection_fragment :: proc(
    user_data: rawptr, rect: geometry.Rectangle) {
    draw := cast(^Presentation_Selection_Draw)user_data
    if !geometry.rectangles_intersect(rect, draw^.params.panel) {
        return
    }
    encoder := draw^.params.encoder
    _ = native.draw_encoder_push_scissor(encoder, rect)
    defer native.draw_encoder_pop_scissor(encoder)
    _ = native.draw_encoder_rectangle(
        encoder, rect, theme.draw_color(encoder, .Text_Selection_Background))
    params := draw^.params
    params.selected_text = true
    params.selection_clip = rect
    draw_presentation_styled_or_fallback(
        draw^.state, draw^.ui_runtime, draw^.fallback, params)
}

// draw_presentation_selection reuses semantic selection geometry for fill-only bright text overlays.
draw_presentation_selection :: proc(
    draw: ^Presentation_Selection_Draw, selection: Dynview_Selection_Draw) {
    fragments := selection
    fragments.user_data = draw
    fragments.draw_fragment = draw_presentation_selection_fragment
    dynview_draw_selection(fragments)
}
