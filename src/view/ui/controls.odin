package ui

import capturemodel "../capture/model"

import view_font "../font"
import input "../input"
import core "../../core"
import geometry "../../core/geometry"
import viewmodel "model"
import viewmessages "../messages"
import uisemantics "semantics"
import uiwidgets "widgets"
import uisplitter "layout/splitter"
import uianimation "animation"
import uiaccordion "layout/accordion"
import uisettings "settings"
import uigif "gif"
import uilibrary "library"
import uipresentation "presentation"
import uiregions "layout/regions"
import uiterminal "terminal"
import uioverlay "overlay"

// Fixed frame-local control results prepared before services and rendering.
Ui_Control_Preparation :: struct {
    animation_controls: uianimation.Animation_Control_Preparation,
    accordion: uiaccordion.Accordion_Preparation,
    settings: uisettings.Settings_View_Preparation,
    gif: uigif.Gif_View_Preparation,
    tree: uilibrary.Tree_List_Preparation,
    library_search: uilibrary.Library_Search_Preparation,
}

// Post-layout interaction results prepared after Dynview compilation completes.
Ui_Layout_Interaction_Preparation :: struct {
    presentation: uipresentation.Presentation_Preparation,
}

// Resolve static UI targets after authoritative panel geometry is available.
prepare_ui_static_interaction :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame,
    capture: viewmodel.Ui_Press_Owner_State) {
    _ = ui_route_interaction_frame(&state^.ui_runtime, {
        frame = frame,
        terminal_present = uiterminal.is_terminal_selected(state),
        animation_favorite_eligible =
            uianimation.animation_favorite_eligible(state^.julia_interface),
        capture = capture,
        capture_view = capturemodel.gif_capture_view(&state^.gif_capture_status),
    })
    if uiwidgets.input_frame_left_pressed(frame) && !capture.active {
        uisemantics.semantic_clear_pointer_focus(state^.ui_runtime.semantic_focus)
    }
}

// Return a frame copy containing only pointer fields routed to the accordion.
ui_accordion_input_frame :: proc(
    frame: input.Input_Frame,
    routed: viewmodel.Ui_Surface_Interaction) -> input.Input_Frame {
    if routed.pointer && routed.wheel {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels, .Wheel})
    }
    if routed.pointer {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels})
    }
    if routed.wheel {
        return input.input_frame_filter_pointer(frame, {.Screen_Position, .Wheel})
    }
    return input.input_frame_filter_pointer(frame, {.Screen_Position})
}

// Return pointer input only when the animation overlay owns this frame.
ui_animation_control_input_frame :: proc(
    frame: input.Input_Frame,
    routed: viewmodel.Ui_Interaction_Frame) -> input.Input_Frame {
    target := routed.pointer_target
    if target.kind == .Control && uianimation.animation_control_id(target.id) {
        return input.input_frame_filter_pointer(frame, {
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels})
    }
    return input.input_frame_filter_pointer(frame, {.Screen_Position})
}

// ui_input_box_keyboard_frame restores events only for the focused input owner.
ui_input_box_keyboard_frame :: proc(
    focus: viewmodel.Ui_Focus_Target,
    filtered, complete: input.Input_Frame,
    id: int) -> input.Input_Frame {
    result := filtered
    if focus.kind == .Input_Box && focus.id == id {
        result.events = complete.events
    }
    return result
}

// prepare_active_accordion_controls resolves controls for one selected section.
prepare_active_accordion_controls :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    routed: input.Input_Frame, content: geometry.Rectangle,
    result: ^Ui_Control_Preparation) {
    switch state^.ui_runtime.layout.active_accordion_section {
    case .View:
    case .Library:
        prepare_active_library_controls(state, frame, routed, content, result)
    case .Save_Gif:
        gif_frame := ui_input_box_keyboard_frame(
            state^.ui_runtime.input.interaction_frame.effective_focus,
            routed, frame, uigif.GIF_PATH_INPUT_BOX_ID)
        result^.gif = uigif.prepare_gif_view(state, content, gif_frame)
    case .Settings:
        result^.settings = uisettings.prepare_settings_view(state, content, routed)
    }
}

// prepare_active_library_controls prepares search and its dependent tree panel.
prepare_active_library_controls :: proc(
    state: ^core.Euclid_General_State, frame, routed: input.Input_Frame,
    content: geometry.Rectangle, result: ^Ui_Control_Preparation) {
    search_frame := ui_input_box_keyboard_frame(
        state^.ui_runtime.input.interaction_frame.effective_focus,
        routed, frame, uilibrary.LIBRARY_SEARCH_INPUT_ID)
    result^.library_search = uilibrary.prepare_library_search(
        state, content, search_frame)
    tree_frame := ui_input_box_keyboard_frame(
        state^.ui_runtime.input.interaction_frame.effective_focus,
        routed, frame, uilibrary.TREE_ENTRY_NAME_INPUT_ID)
    uilibrary.prepare_tree_list_panel({
        label = viewmessages.shell_message(state, .Library_Tree_Accessible_Label),
        general_state = state,
        ji = state^.julia_interface,
        collections = &state^.preferences_runtime.collections_state,
        collections_revision = state^.preferences_runtime.collection_revision,
        ui_runtime = &state^.ui_runtime,
        list_panel = result^.library_search.layout.tree,
        mouse_input = tree_frame,
        scroll_y = &state^.ui_runtime.library.tree.scroll_y,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        visibility = {search = &state^.ui_runtime.library.search},
        reduce_motion = uiaccordion.ui_reduced_motion(
            state^.ui_runtime.preferences.values.interface.reduce_motion,
            state^.ui_runtime.platform_reduce_motion),
    }, &result^.tree)
    if result^.tree.cancel_geometry_capture {
        ui_release_geometry_capture(&state^.ui_runtime)
    }
}

// Resolve geometry-known controls and commit their actions before services run.
prepare_ui_controls :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame,
    splitters: uisplitter.Splitter_Preparation,
    result: ^Ui_Control_Preparation) {
    _ = uisemantics.semantic_begin(state^.ui_runtime.semantic_focus)
    uioverlay.tooltip_frame_begin(&state^.ui_runtime.tooltip)
    uisplitter.register_splitter_semantics(state^.ui_runtime.semantic_focus, splitters)
    resolved_frame := ui_guard_library_entry_name_focus(state, frame)
    animation_frame := ui_animation_control_input_frame(
        resolved_frame, state^.ui_runtime.input.interaction_frame)
    routed_frame := ui_accordion_input_frame(
        resolved_frame, state^.ui_runtime.input.interaction_frame.accordion)
    result^.animation_controls = uianimation.prepare_animation_controls(
        state, animation_frame)
    accordion_panel := state^.ui_runtime.layout.ui_regions.accordion_rect
    result^.accordion = prepare_accordion_view(
        state, geometry.Rectangle(accordion_panel), routed_frame)
    child_frame := ui_clip_accordion_child_frame(&state^.ui_runtime, routed_frame)
    prepare_active_accordion_controls(state, resolved_frame, child_frame,
        geometry.Rectangle(result^.accordion.layout.content), result)
    prepare_outgoing_accordion_controls(state, result)
    if state^.ui_runtime.layout.current_layout_mode == .Portrait {
        state^.ui_runtime.layout.ui_regions.text_rect = geometry.Rectangle(
            uiaccordion.accordion_content_rect(
                &state^.ui_runtime.layout, .View))
        state^.ui_runtime.layout.ui_regions.terminal_rect =
            uiregions.layout_terminal_rect(state^.ui_runtime.layout.ui_regions.text_rect)
    }
    uioverlay.tooltip_frame_resolve(&state^.ui_runtime.tooltip, {
        now_seconds = resolved_frame.sample_time_seconds,
        window_focused = resolved_frame.window_focused,
        suppressed = state^.gif_capture_status.gif_capture_phase == .Recording ||
            state^.ui_runtime.context_menu.active,
        dismiss = uioverlay.tooltip_escape_pressed(resolved_frame),
    })
}

// ui_guard_library_entry_name_focus rejects a blur whose pending name cannot be saved.
ui_guard_library_entry_name_focus :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame) -> input.Input_Frame {
    runtime := &state^.ui_runtime
    draft := &runtime^.library.entry_name
    semantic := runtime^.semantic_focus
    if !draft^.active || !draft^.dirty || semantic == nil {
        return frame
    }
    editor_id := viewmodel.Ui_Node_Id{
        domain = .Library_Action, local_id = uilibrary.TREE_ENTRY_NAME_INPUT,
        stable_id = draft^.entry_id,
        generation = state^.julia_interface.content_generation,
    }
    pointer_pressed := uiwidgets.input_frame_left_pressed(frame)
    mouse := uiwidgets.input_frame_mouse_position(frame)
    pointer_inside := pointer_pressed &&
        geometry.rectangle_contains(draft^.rect, mouse) &&
        geometry.rectangle_contains(draft^.clip_rect, mouse)
    pointer_blur := pointer_pressed && !pointer_inside
    focus_blur := semantic^.logical_focus != editor_id && !pointer_inside
    if !pointer_blur && !focus_blur {
        return frame
    }
    if uilibrary.library_entry_name_flush(state, draft^.entry_id) {
        return frame
    }
    return ui_retain_library_entry_name_focus(state, frame)
}

// Keep a rejected dirty edit focused until its save can be admitted.
ui_retain_library_entry_name_focus :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame) -> input.Input_Frame {
    runtime := &state^.ui_runtime
    semantic := runtime^.semantic_focus
    draft := &runtime^.library.entry_name
    editor_id := viewmodel.Ui_Node_Id{
        domain = .Library_Action, local_id = uilibrary.TREE_ENTRY_NAME_INPUT,
        stable_id = draft^.entry_id,
        generation = state^.julia_interface.content_generation,
    }
    semantic^.logical_focus = editor_id
    semantic^.focus_origin = .Keyboard
    semantic^.last_region = .Accordion_Content
    semantic^.last_traversal_order =
        uilibrary.LIBRARY_ENTRY_NAME_INPUT_TRAVERSAL_ORDER
    semantic^.command_count = 0
    runtime^.input.interaction.logical_focus = {
        kind = .Input_Box, id = uilibrary.TREE_ENTRY_NAME_INPUT_ID}
    runtime^.input.interaction_frame.logical_focus = {
        kind = .Input_Box, id = uilibrary.TREE_ENTRY_NAME_INPUT_ID}
    runtime^.input.interaction_frame.effective_focus = {
        kind = .Input_Box, id = uilibrary.TREE_ENTRY_NAME_INPUT_ID}
    filtered := input.input_frame_filter_pointer(frame, {.Screen_Position})
    filtered.events = frame.events[:0]
    ui_apply_semantic_focus(runtime, filtered, uiterminal.is_terminal_selected(state))
    return filtered
}

// ui_accordion_child_owns_capture excludes header, splitter, and landscape View captures.
ui_accordion_child_owns_capture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    owner := runtime^.input.press_owner
    #partial switch owner.kind {
    case .List_Item, .Input_Box, .Checkbox, .Slider:
        return true
    case .Text_Button:
        return !uianimation.animation_control_id(owner.id) &&
            (owner.id < uiaccordion.ACCORDION_HEADER_ID_BASE ||
                owner.id >= uiaccordion.ACCORDION_HEADER_ID_BASE +
                    uiaccordion.ACCORDION_MAX_SECTION_COUNT)
    case .Scrollbar:
        if owner.id == uilibrary.UI_TREE_SCROLLBAR_ID || owner.id == 6102 {
            return true
        }
    }
    return runtime^.layout.current_layout_mode == .Portrait &&
        runtime^.layout.active_accordion_section == .View &&
        uipresentation.ui_presentation_owns_capture(owner)
}

// ui_clip_accordion_child_frame cancels released captures without activating hidden content.
ui_clip_accordion_child_frame :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: input.Input_Frame) -> input.Input_Frame {
    clip := uiaccordion.accordion_content_clip(
        &runtime^.layout, runtime^.layout.active_accordion_section)
    if clip.width > 0 && clip.height > 0 &&
        geometry.rectangle_contains(clip, uiwidgets.input_frame_mouse_position(frame)) {
        return frame
    }
    if uiwidgets.input_frame_left_released(frame) && runtime^.input.press_owner.active &&
        ui_accordion_child_owns_capture(runtime) {
        ui_release_geometry_capture(runtime)
    }
    filtered := input.input_frame_filter_pointer(frame, {.Screen_Position})
    filtered.mouse_position = {-1, -1}
    return filtered
}

// prepare_outgoing_accordion_controls borrows draw facts without actions or semantics.
prepare_outgoing_accordion_controls :: proc(
    state: ^core.Euclid_General_State, result: ^Ui_Control_Preparation) {
    if state^.ui_runtime.layout.active_accordion_section != .Library {
        state^.ui_runtime.library.motion = {}
    }
    sections := result^.accordion.sections
    for index in 0..<sections.count {
        section := sections.items[index].section
        if section == state^.ui_runtime.layout.active_accordion_section ||
            result^.accordion.layout.clips[int(section)].height <= 0 {
            continue
        }
        prepare_outgoing_accordion_section(
            state, section, result^.accordion.layout.contents[int(section)], result)
    }
}

// prepare_outgoing_accordion_section prepares visuals without interaction side effects.
prepare_outgoing_accordion_section :: proc(
    state: ^core.Euclid_General_State,
    section: viewmodel.Ui_Accordion_Section,
    content: geometry.Rectangle,
    result: ^Ui_Control_Preparation) {
    switch section {
    case .Settings:
        result^.settings = uisettings.prepare_settings_view(state, content, {}, false)
    case .Save_Gif:
        result^.gif = uigif.prepare_gif_view(state, content, {}, false)
    case .Library:
        result^.library_search =
            uilibrary.prepare_library_search_visual(state, content)
        uilibrary.prepare_tree_visual({
            general_state = state,
            ji = state^.julia_interface,
            collections = &state^.preferences_runtime.collections_state,
            collections_revision = state^.preferences_runtime.collection_revision,
            ui_runtime = &state^.ui_runtime,
            list_panel = result^.library_search.layout.tree,
            scroll_y = &state^.ui_runtime.library.tree.scroll_y,
            visibility = {search = &state^.ui_runtime.library.search},
            reduce_motion = uiaccordion.ui_reduced_motion(
                state^.ui_runtime.preferences.values.interface.reduce_motion,
                state^.ui_runtime.platform_reduce_motion)},
            &result^.tree)
    case .View:
    }
}

// finish_ui_semantics atomically publishes all geometry and layout registrations.
finish_ui_semantics :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    _ = uisemantics.semantic_publish(state^.ui_runtime.semantic_focus)
}

// prepare_and_finish_ui_layout resolves layout interaction and publishes semantics.
prepare_and_finish_ui_layout :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame,
    terminal: uiterminal.Terminal_Prepared_Frame) -> Ui_Layout_Interaction_Preparation {
    result := prepare_ui_layout_interaction(state, frame, terminal)
    uioverlay.context_menu_prepare(state)
    finish_ui_semantics(state)
    return result
}

// Resolve layout-dependent presentation interaction before drawing begins.
prepare_ui_layout_interaction :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame,
    terminal: uiterminal.Terminal_Prepared_Frame) -> Ui_Layout_Interaction_Preparation {
    if !uipresentation.ui_presentation_is_visible(
        &state^.ui_runtime.presentation) {
        state^.ui_runtime.presentation.text_scroll_max = 0
        return {}
    }
    if uiterminal.is_terminal_selected(state) {
        bounds := uiterminal.terminal_content_panel(
            state^.ui_runtime.layout.ui_regions.text_rect)
        if terminal.available {
            bounds = terminal.bounds
            state^.ui_runtime.context_menu.keyboard_anchor =
                terminal.editable_geometry.caret
        }
        uiterminal.register_terminal_semantics(state, bounds, terminal.scroll)
        return {}
    }
    state^.ui_runtime.terminal.semantic_focus_initialized = false
    routed := state^.ui_runtime.input.interaction_frame.presentation
    presentation_frame := input.input_frame_filter_pointer(frame,
        routed.pointer ? input.Input_Pointer_Fields{
            .Screen_Position, .Motion, .Press_Edges, .Release_Edges, .Levels,
            .Wheel} : input.Input_Pointer_Fields{.Screen_Position})
    if !routed.wheel {
        presentation_frame.mouse_wheel_delta = 0
    }
    if state^.ui_runtime.layout.current_layout_mode == .Portrait {
        presentation_frame = ui_clip_accordion_child_frame(
            &state^.ui_runtime, presentation_frame)
    }
    return {presentation = uipresentation.prepare_presentation_interaction(state,
        state^.ui_runtime.layout.ui_regions.text_rect, presentation_frame,
        routed.keyboard)}
}
