package ui

import core "../../core"
import viewmodel "model"
import viewmessages "../messages"
import uiaccordion "layout/accordion"

// Resolve application-owned labels before constructing borrowed section descriptors.
accordion_sections_for_layout :: proc(
    mode: viewmodel.Ui_Layout_Mode, title: string,
    state: ^core.Euclid_General_State = nil) -> uiaccordion.Accordion_Section_Set {
    labels: [3]string
    view_title := title
    if state != nil {
        labels = {viewmessages.shell_message(state, .Navigation_Library),
            viewmessages.shell_message(state, .Gif_Save),
            viewmessages.shell_message(state, .Navigation_Settings)}
        if mode == .Portrait && len(view_title) == 0 {
            view_title = viewmessages.shell_message(state, .Animation_Default_Title)
        }
    }
    return uiaccordion.accordion_section_descriptors(mode, view_title, labels)
}
