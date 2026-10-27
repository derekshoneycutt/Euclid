package ui

import core "../../core"
import geometry "../../core/geometry"
import view_font "../font"
import input "../input"
import viewmodel "model"
import uiterminal "terminal"
import uipresentation "presentation"
import uiaccordion "layout/accordion"
import uilibrary "library"
import uisettings "settings"
import uisplitter "layout/splitter"
import contentdata "../../core/content"
import viewmessages "../messages"
import preferencesmodel "../preferences/model"

// Frame-local prepared values consumed by accordion child drawing.
Accordion_Draw_Preparation :: struct {
    controls: Ui_Control_Preparation,
    terminal: uiterminal.Terminal_Prepared_Frame,
    presentation: uipresentation.Presentation_Preparation,
}

// ui_composition_presentation_visible resolves the View surface from layout intent.
ui_composition_presentation_visible :: #force_inline proc(
    layout: ^viewmodel.Ui_Layout_State) -> bool {
    return layout^.current_layout_mode == .Landscape ||
        layout^.active_accordion_section == .View
}

// ui_hide_presentation_interaction reconciles all owners when View becomes hidden.
ui_hide_presentation_interaction :: proc(
    shared: ^viewmodel.Ui_Shared_Interaction_State,
    presentation: ^viewmodel.Ui_Presentation_Interaction_State,
    terminal: ^viewmodel.Ui_Terminal_Interaction_State) {
    if uipresentation.ui_presentation_owns_capture(shared^.press_owner) {
        shared^.press_owner = {}
    }
    uipresentation.presentation_cancel_geometry_capture(presentation)
    uiterminal.terminal_cancel_geometry_capture(terminal)
    focus := shared^.interaction.logical_focus.kind
    if focus == .Terminal || focus == .Presentation {
        shared^.interaction.logical_focus = {}
    }
    was_terminal_focused := shared^.interaction_frame.terminal_focused ||
        shared^.interaction.terminal_effectively_focused
    shared^.interaction_frame.logical_focus = shared^.interaction.logical_focus
    shared^.interaction_frame.effective_focus = shared^.interaction.logical_focus
    shared^.interaction_frame.terminal_focused = false
    shared^.interaction_frame.terminal_focus_changed = was_terminal_focused
    shared^.interaction_frame.terminal = {}
    shared^.interaction_frame.presentation = {}
    shared^.interaction.terminal_effectively_focused = false
}

// ui_release_geometry_capture coordinates owner-local cancellation after invalidation.
ui_release_geometry_capture :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    runtime^.input.press_owner = {}
    uilibrary.tree_cancel_geometry_capture(&runtime^.library.tree)
    uisettings.settings_cancel_geometry_capture(&runtime^.settings_panel)
    uipresentation.presentation_cancel_geometry_capture(&runtime^.presentation)
    uiterminal.terminal_cancel_geometry_capture(&runtime^.terminal)
    uisplitter.splitter_cancel_geometry_capture(&runtime^.layout)
}

// ui_publish_presentation_visibility reconciles hidden interaction after layout changes.
ui_publish_presentation_visibility :: proc(
    layout: ^viewmodel.Ui_Layout_State,
    presentation: ^viewmodel.Ui_Presentation_Interaction_State,
    shared: ^viewmodel.Ui_Shared_Interaction_State,
    terminal: ^viewmodel.Ui_Terminal_Interaction_State) -> bool {
    visible := ui_composition_presentation_visible(layout)
    if presentation^.visible == visible {
        return false
    }
    presentation^.visible = visible
    if !visible {
        ui_hide_presentation_interaction(shared, presentation, terminal)
    }
    return true
}

// accordion_sections_for_layout resolves application labels and save feedback.
accordion_sections_for_layout :: proc(
    mode: viewmodel.Ui_Layout_Mode, title: string,
    state: ^core.Euclid_General_State) -> uiaccordion.Accordion_Section_Set {
    labels: [3]string = {
        viewmessages.shell_message(state, .Navigation_Library),
        viewmessages.shell_message(state, .Gif_Save),
        viewmessages.shell_message(state, .Navigation_Settings),
    }
    view_title := title
    if mode == .Portrait && len(view_title) == 0 {
        view_title = viewmessages.shell_message(state, .Animation_Default_Title)
    }
    sections := uiaccordion.accordion_section_descriptors(mode, view_title, labels)
    status := state^.ui_runtime.preferences.save_status
    failed := state^.preferences_runtime.user_data_failure_unresolved ||
        status == .Failed || status == .Unavailable
    if failed {
        settings_index := 2
        if mode == .Portrait {
            settings_index = 3
        }
        status_message := contentdata.Content_Message_Id.Settings_Save_Failed
        if status == preferencesmodel.Settings_Save_Status.Unavailable {
            status_message = .Settings_Save_Unavailable
        }
        sections.items[settings_index].error_indicator = true
        sections.items[settings_index].accessible_value =
            viewmessages.shell_message(state, status_message)
    }
    return sections
}

// Prepare accordion headers and commit one active section before child updates.
prepare_accordion_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame) -> uiaccordion.Accordion_Preparation {
    ui_runtime := &state^.ui_runtime
    active_before := ui_runtime^.layout.active_accordion_section
    sections := accordion_sections_for_layout(
        ui_runtime^.layout.current_layout_mode,
        uilibrary.selected_animation_title(state), state)
    prepared := uiaccordion.prepare_accordion(uiaccordion.Accordion_Context{
        panel = geometry.Rectangle(panel),
        mouse_input = mouse_input,
        press_owner = &ui_runtime^.input.press_owner,
        semantic_focus = ui_runtime^.semantic_focus,
        active = ui_runtime^.layout.active_accordion_section,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        transition = &ui_runtime^.layout.accordion_transition,
        reduce_motion = uiaccordion.ui_reduced_motion(
            ui_runtime^.preferences.values.interface.reduce_motion,
            ui_runtime^.platform_reduce_motion),
    }, sections, &ui_runtime^.layout.active_accordion_section)
    if active_before != ui_runtime^.layout.active_accordion_section {
        ui_release_geometry_capture(ui_runtime)
        if active_before == .Settings &&
           ui_runtime^.layout.active_accordion_section != .Settings {
            uisettings.settings_cancel_history_confirmation(
                &ui_runtime^.settings_panel)
        }
        ui_runtime^.tooltip = {}
        ui_runtime^.context_menu.active = false
        _ = ui_publish_presentation_visibility(
            &ui_runtime^.layout, &ui_runtime^.presentation,
            &ui_runtime^.input, &ui_runtime^.terminal)
    }
    return prepared
}
