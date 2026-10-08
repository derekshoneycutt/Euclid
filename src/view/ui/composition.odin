package ui

import core "../../core"
import geometry "../../core/geometry"
import view_font "../font"
import input "../input"
import uiterminal "terminal"
import uipresentation "presentation"
import uiaccordion "layout/accordion"
import uilibrary "library"
import uilayout "layout"

// Frame-local prepared values consumed by accordion child drawing.
Accordion_Draw_Preparation :: struct {
    controls: Ui_Control_Preparation,
    terminal: uiterminal.Terminal_Prepared_Frame,
    presentation: uipresentation.Presentation_Preparation,
}

// Prepare accordion headers and commit one active section before child updates.
prepare_accordion_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame) -> uiaccordion.Accordion_Preparation {
    ui_runtime := &state^.ui_runtime
    active_before := ui_runtime^.active_accordion_section
    sections := accordion_sections_for_layout(
        ui_runtime^.current_layout_mode, uilibrary.selected_animation_title(state), state)
    prepared := uiaccordion.prepare_accordion(uiaccordion.Accordion_Context{
        panel = geometry.Rectangle(panel),
        mouse_input = mouse_input,
        press_owner = &ui_runtime^.ui_press_owner,
        semantic_focus = ui_runtime^.semantic_focus,
        active = ui_runtime^.active_accordion_section,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        transition = &ui_runtime^.accordion_transition,
        reduce_motion = uiaccordion.ui_reduced_motion(ui_runtime),
    }, sections, &ui_runtime^.active_accordion_section)
    if active_before != ui_runtime^.active_accordion_section {
        uilayout.ui_release_geometry_capture(ui_runtime)
        ui_runtime^.tooltip = {}
        ui_runtime^.context_menu.active = false
        _ = uipresentation.ui_publish_presentation_visibility(ui_runtime)
    }
    return prepared
}
