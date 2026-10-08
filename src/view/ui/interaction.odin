package ui

import capturemodel "../capture/model"

import geometry "../../core/geometry"
import input "../input"
import viewmodel "model"
import uiwidgets "widgets"
import uisemantics "semantics"
import uianimation "animation"
import uipresentation "presentation"
import uiterminal "terminal"
import uiaccordion "layout/accordion"
import uisplitter "layout/splitter"
import uigif "gif"
import uilibrary "library"

// Inputs needed to resolve one immutable device frame against current UI geometry.
Ui_Interaction_Route_Input :: struct {
    frame: input.Input_Frame,
    terminal_present: bool,
    capture: viewmodel.Ui_Press_Owner_State,
    capture_view: capturemodel.Gif_Capture_View,
}
// Classify icon-button capture between the world overlay and tree controls.
ui_icon_button_capture_target :: proc(
    capture: viewmodel.Ui_Press_Owner_State) -> viewmodel.Ui_Interaction_Target {
    if uianimation.animation_control_id(capture.id) {
        return viewmodel.ui_interaction_target(.Control, id = capture.id)
    }
    return viewmodel.ui_interaction_target(.Control, .Accordion, capture.id)
}

// ui_scrollbar_capture_target classifies one scrollbar by its owning surface.
ui_scrollbar_capture_target :: proc(
    capture: viewmodel.Ui_Press_Owner_State) -> viewmodel.Ui_Interaction_Target {
    focus := viewmodel.Ui_Focus_Kind.Accordion
    if capture.id == uipresentation.UI_PRESENTATION_SCROLLBAR_ID {
        focus = .Presentation
    }
    if capture.id == uiterminal.UI_TERMINAL_SCROLLBAR_ID {
        focus = .Terminal
    }
    return viewmodel.ui_interaction_target(.Scrollbar, focus, capture.id)
}

// Classify legacy singleton capture until widget call sites register with the router.
ui_capture_target :: proc(
    capture: viewmodel.Ui_Press_Owner_State) -> viewmodel.Ui_Interaction_Target {
    if !capture.active {
        return {}
    }
    switch capture.kind {
    case .Splitter:
        return viewmodel.ui_interaction_target(.Splitter, id = capture.id)
    case .Scrollbar:
        return ui_scrollbar_capture_target(capture)
    case .Dynview_Selection:
        return viewmodel.ui_interaction_target(.Control, .Presentation, capture.id)
    case .Icon_Button:
        return ui_icon_button_capture_target(capture)
    case .Input_Box:
        return viewmodel.ui_interaction_target(.Control, .Input_Box, capture.id)
    case .None:
        return {}
    case .List_Item, .Text_Button, .Checkbox, .Slider:
        return viewmodel.ui_interaction_target(.Control, .Accordion, capture.id)
    }
    return {}
}






// Resolve a visible Presentation or Terminal target.
ui_presentation_target :: proc(
    mouse: geometry.Vector2, regions: viewmodel.Ui_Regions,
    terminal_present: bool) -> viewmodel.Ui_Interaction_Target {
    if terminal_present &&
        geometry.rectangle_contains(
            geometry.Rectangle(regions.terminal_rect), mouse) {
        return viewmodel.ui_interaction_target(.Panel_Content, .Terminal)
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(regions.text_rect), mouse) {
        return viewmodel.ui_interaction_target(.Panel_Content, .Presentation)
    }
    return {}
}

// ui_accordion_pointer_is_revealed admits only positive-area visible child bounds.
ui_accordion_pointer_is_revealed :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    section: viewmodel.Ui_Accordion_Section, mouse: geometry.Vector2) -> bool {
    clip := uiaccordion.accordion_content_clip(runtime, section)
    return clip.width > 0 && clip.height > 0 &&
        geometry.rectangle_contains(clip, mouse)
}

// Resolve the topmost static target under the current pointer sample.
ui_world_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse: geometry.Vector2,
    phase: capturemodel.Gif_Capture_Phase) -> viewmodel.Ui_Interaction_Target {
    control_id, over_control := uianimation.animation_control_hit_test(
        geometry.Rectangle(runtime^.ui_regions.world_rect),
        phase, mouse)
    if over_control {
        return viewmodel.ui_interaction_target(.Control, id = control_id)
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(runtime^.ui_regions.world_rect), mouse) {
        return viewmodel.ui_interaction_target(.World)
    }
    return {}
}

// ui_splitter_hover_target resolves one unlocked splitter under the pointer.
ui_splitter_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse: geometry.Vector2,
    phase: capturemodel.Gif_Capture_Phase) -> viewmodel.Ui_Interaction_Target {
    if uisplitter.splitters_locked_for_gif(phase) {
        return {}
    }
    axis, hovered := uisplitter.splitter_hovered_axis(mouse,
        runtime^.current_layout_mode,
        runtime^.vertical_split_x, runtime^.horizontal_split_y,
        runtime^.window)
    if !hovered {
        return {}
    }
    id := uisplitter.SPLITTER_VERTICAL_PRESS_ID
    if axis == .Horizontal {
        id = uisplitter.SPLITTER_HORIZONTAL_PRESS_ID
    }
    return viewmodel.ui_interaction_target(.Splitter, id = id)
}

// Resolve the topmost static target under the current pointer sample.
ui_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: input.Input_Frame,
    terminal_present: bool,
    capture_view: capturemodel.Gif_Capture_View = {}) -> viewmodel.Ui_Interaction_Target {
    mouse := uiwidgets.input_frame_mouse_position(frame)
    splitter := ui_splitter_hover_target(runtime, mouse, capture_view.phase)
    if splitter.kind != .None {
        return splitter
    }
    regions := runtime^.ui_regions
    if uipresentation.ui_presentation_is_visible(runtime) &&
        (runtime^.current_layout_mode != .Portrait ||
            ui_accordion_pointer_is_revealed(runtime, .View, geometry.Vector2(mouse))) {
        target := ui_presentation_target(
            geometry.Vector2(mouse), regions, terminal_present)
        if target.kind != .None {
            return target
        }
    }
    accordion := ui_accordion_hover_target(runtime, geometry.Vector2(mouse), capture_view)
    if accordion.kind != .None {
        return accordion
    }
    return ui_world_hover_target(runtime, geometry.Vector2(mouse), capture_view.phase)
}

// Resolve revealed accordion inputs before the surrounding panel background.
ui_accordion_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, mouse: geometry.Vector2,
    capture_view: capturemodel.Gif_Capture_View) -> viewmodel.Ui_Interaction_Target {
    child_visible := ui_accordion_pointer_is_revealed(
        runtime, runtime^.active_accordion_section, geometry.Vector2(mouse))
    if child_visible &&
       uigif.gif_path_input_visible(runtime, capture_view) &&
       geometry.rectangle_contains(
        uigif.gif_path_input_rect(runtime), geometry.Vector2(mouse)) {
        return viewmodel.ui_interaction_target(
            .Control, .Input_Box, uigif.GIF_PATH_INPUT_BOX_ID)
    }
    if child_visible &&
       uilibrary.library_search_visible(runtime) &&
       geometry.rectangle_contains(
            uilibrary.library_search_input_rect(runtime), geometry.Vector2(mouse)) {
        return viewmodel.ui_interaction_target(
            .Control, .Input_Box, uilibrary.LIBRARY_SEARCH_INPUT_ID)
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(runtime^.ui_regions.accordion_rect), mouse) {
        return viewmodel.ui_interaction_target(.Panel_Content, .Accordion)
    }
    return {}
}

// Resolve persistent logical focus from presentation and routed press transitions.
ui_route_logical_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input,
    pointer_target: viewmodel.Ui_Interaction_Target) -> viewmodel.Ui_Focus_Target {
    result := runtime^.interaction.logical_focus
    if result.kind == .Input_Box && result.id == uigif.GIF_PATH_INPUT_BOX_ID &&
        !uigif.gif_path_input_visible(runtime, input.capture_view) {
        result = {}
    }
    if result.kind == .Input_Box && result.id == uilibrary.LIBRARY_SEARCH_INPUT_ID &&
        !uilibrary.library_search_visible(runtime) {
        result = {}
    }
    terminal_present := input.terminal_present
    visible := uipresentation.ui_presentation_is_visible(runtime)
    if terminal_present && visible && !runtime^.interaction.terminal_was_present {
        result = {kind = .Terminal}
    } else if (!terminal_present || !visible) && result.kind == .Terminal {
        result = {}
    }
    if uiwidgets.input_frame_left_pressed(input.frame) && !input.capture.active {
        result = pointer_target.focus
    }
    return result
}

// ui_valid_capture_owner releases input-box capture after its control disappears.
ui_valid_capture_owner :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    owner: viewmodel.Ui_Press_Owner_State,
    capture_view: capturemodel.Gif_Capture_View) -> viewmodel.Ui_Press_Owner_State {
    if owner.kind != .Input_Box ||
        owner.id == uigif.GIF_PATH_INPUT_BOX_ID &&
        uigif.gif_path_input_visible(runtime, capture_view) ||
        owner.id == uilibrary.LIBRARY_SEARCH_INPUT_ID &&
        uilibrary.library_search_visible(runtime) {
        return owner
    }
    runtime^.ui_press_owner = {}
    return {}
}


// Route wheel input to hover only when no pointer capture owns the frame.
ui_interaction_wheel_target :: #force_inline proc(
    delta: f32, capture, hover: viewmodel.Ui_Interaction_Target) ->
    viewmodel.Ui_Interaction_Target {
    if delta != 0 && capture.kind == .None {
        return hover
    }
    return {}
}

// Reconcile persistent logical focus and this frame's effective Terminal focus.
ui_route_interaction_frame :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input) -> viewmodel.Ui_Interaction_Frame {
    hover := ui_hover_target(runtime, input.frame,
        input.terminal_present, input.capture_view)
    capture_owner := ui_valid_capture_owner(runtime, input.capture, input.capture_view)
    capture := ui_capture_target(capture_owner)
    pointer_target := hover
    if capture.kind != .None {
        pointer_target = capture
    }
    logical_focus := ui_route_logical_focus(runtime, input, pointer_target)
    terminal_focused := uiterminal.ui_terminal_effectively_focused(
        logical_focus, input.frame.window_focused, input.terminal_present,
        uipresentation.ui_presentation_is_visible(runtime))
    wheel_target := ui_interaction_wheel_target(
        input.frame.mouse_wheel_delta, capture, hover)
    result := viewmodel.Ui_Interaction_Frame{
        logical_focus = logical_focus,
        hover = hover,
        pointer_capture = capture,
        pointer_target = pointer_target,
        wheel_target = wheel_target,
        terminal_focus_changed = terminal_focused !=
            runtime^.interaction.terminal_effectively_focused,
        terminal_focused = terminal_focused,
    }
    if input.frame.window_focused {
        result.effective_focus = logical_focus
    }
    viewmodel.ui_refresh_surface_interaction(&result)
    runtime^.interaction.logical_focus = logical_focus
    runtime^.interaction.terminal_was_present = input.terminal_present
    runtime^.interaction.terminal_effectively_focused = terminal_focused
    runtime^.interaction_frame = result
    return result
}

// ui_apply_semantic_focus updates transitional surface routing after key traversal.
ui_apply_semantic_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: input.Input_Frame, terminal_present: bool) {
    target, present := uisemantics.semantic_legacy_focus(runtime^.semantic_focus)
    if !present {
        return
    }
    routed := &runtime^.interaction_frame
    prior_terminal := runtime^.interaction.terminal_effectively_focused
    terminal_focused := uiterminal.ui_terminal_effectively_focused(
        target, frame.window_focused, terminal_present,
        uipresentation.ui_presentation_is_visible(runtime))
    routed^.logical_focus = target
    routed^.effective_focus = target if frame.window_focused else {}
    routed^.terminal_focus_changed = routed^.terminal_focus_changed ||
        terminal_focused != prior_terminal
    routed^.terminal_focused = terminal_focused
    runtime^.interaction.logical_focus = target
    runtime^.interaction.terminal_effectively_focused = terminal_focused
    viewmodel.ui_refresh_surface_interaction(routed)
}

// Route focus through the full interaction result for isolated callers and tests.
ui_reconcile_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: input.Input_Frame,
    terminal_present: bool,
    capture_view: capturemodel.Gif_Capture_View = {}) -> viewmodel.Ui_Interaction_Frame {
    return ui_route_interaction_frame(runtime, {
        frame = frame,
        terminal_present = terminal_present,
        capture = runtime^.ui_press_owner,
        capture_view = capture_view,
    })
}
