package ui

import core "../../core"
import viewmodel "model"
import viewmessages "../messages"
import uiaccordion "layout/accordion"
import contentdata "../../core/content"
import preferencesmodel "../preferences/model"

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
    sections := uiaccordion.accordion_section_descriptors(mode, view_title, labels)
    if state != nil && (state^.preferences_runtime.user_data_failure_unresolved ||
        state^.ui_runtime.settings_save_status ==
            preferencesmodel.Settings_Save_Status.Failed ||
        state^.ui_runtime.settings_save_status ==
            preferencesmodel.Settings_Save_Status.Unavailable) {
        settings_index := 2
        if mode == .Portrait {
            settings_index = 3
        }
        status_message := contentdata.Content_Message_Id.Settings_Save_Failed
        if state^.ui_runtime.settings_save_status ==
            preferencesmodel.Settings_Save_Status.Unavailable {
            status_message = .Settings_Save_Unavailable
        }
        sections.items[settings_index].error_indicator = true
        sections.items[settings_index].accessible_value =
            viewmessages.shell_message(state, status_message)
    }
    return sections
}
