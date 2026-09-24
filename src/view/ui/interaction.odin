package ui

import viewmodel "../model"
import geometry "../../core/geometry"

import "../input"

UI_PRESENTATION_SCROLLBAR_ID :: 1001
UI_TERMINAL_SCROLLBAR_ID :: 1002
UI_TREE_SCROLLBAR_ID :: 1003

// Inputs needed to resolve one immutable device frame against current UI geometry.
Ui_Interaction_Route_Input :: struct {
    frame: Input_Frame,
    terminal_present: bool,
    capture: viewmodel.Ui_Press_Owner_State,
}

// Capture and wheel facts needed to filter one resolved Terminal frame.
Ui_Terminal_Content_Route_Input :: struct {
    local_capture: bool,
    child_capture: bool,
    wheel_consumed: bool,
}

// Return one target with its focus owner and optional stable interaction identity.
ui_interaction_target :: #force_inline proc(
    kind: viewmodel.Ui_Interaction_Target_Kind,
    focus: viewmodel.Ui_Focus_Kind = .None,
    id: int = 0) -> viewmodel.Ui_Interaction_Target {
    return {kind = kind, focus = {kind = focus}, id = id}
}

// Classify icon-button capture between the world overlay and tree controls.
ui_icon_button_capture_target :: proc(
    capture: viewmodel.Ui_Press_Owner_State) -> viewmodel.Ui_Interaction_Target {
    if animation_control_id(capture.id) {
        return ui_interaction_target(.Control, id = capture.id)
    }
    return ui_interaction_target(.Control, .Accordion, capture.id)
}

// Classify legacy singleton capture until widget call sites register with the router.
ui_capture_target :: proc(
    capture: viewmodel.Ui_Press_Owner_State) -> viewmodel.Ui_Interaction_Target {
    if !capture.active { return {} }
    switch capture.kind {
    case .Splitter:
        return ui_interaction_target(.Splitter, id = capture.id)
    case .Scrollbar:
        focus := viewmodel.Ui_Focus_Kind.Accordion
        if capture.id == UI_PRESENTATION_SCROLLBAR_ID { focus = .Presentation }
        if capture.id == UI_TERMINAL_SCROLLBAR_ID { focus = .Terminal }
        return ui_interaction_target(.Scrollbar, focus, capture.id)
    case .Dynview_Selection, .Copy_Icon:
        return ui_interaction_target(.Control, .Presentation, capture.id)
    case .Icon_Button:
        return ui_icon_button_capture_target(capture)
    case .None:
        return {}
    case .List_Item, .Text_Button, .Checkbox, .Slider:
        return ui_interaction_target(.Control, .Accordion, capture.id)
    }
    return {}
}

// Compute presentation visibility from the resolved composition.
ui_composition_presentation_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime^.current_layout_mode == .Landscape ||
        runtime^.active_accordion_section == .View
}

// Report the display-owned presentation visibility published for this frame.
ui_presentation_is_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime != nil && runtime^.presentation_visible
}

// Return whether shared capture belongs to hidden Presentation or Terminal UI.
ui_presentation_owns_capture :: proc(
    owner: viewmodel.Ui_Press_Owner_State) -> bool {
    if owner.kind == .Dynview_Selection || owner.kind == .Copy_Icon {
        return true
    }
    return owner.kind == .Scrollbar &&
        (owner.id == UI_PRESENTATION_SCROLLBAR_ID ||
         owner.id == UI_TERMINAL_SCROLLBAR_ID)
}

// Clear focus and pointer transactions when composition hides the presentation.
ui_hide_presentation_interaction :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if ui_presentation_owns_capture(runtime^.ui_press_owner) {
        runtime^.ui_press_owner = {}
    }
    runtime^.text_scroll_dragging = false
    runtime^.text_scroll_drag_off = 0
    runtime^.terminal_scroll_dragging = false
    runtime^.terminal_scroll_drag_off = 0
    runtime^.dynview_selection.dragging = false
    focus := runtime^.interaction.logical_focus.kind
    if focus == .Terminal || focus == .Presentation {
        runtime^.interaction.logical_focus = {}
    }
    frame := &runtime^.interaction_frame
    was_terminal_focused := frame^.terminal_focused ||
        runtime^.interaction.terminal_effectively_focused
    frame^.logical_focus = runtime^.interaction.logical_focus
    frame^.effective_focus = runtime^.interaction.logical_focus
    frame^.terminal_focused = false
    frame^.terminal_focus_changed = was_terminal_focused
    frame^.terminal = {}
    frame^.presentation = {}
    runtime^.interaction.terminal_effectively_focused = false
}

// Publish current composition visibility and reconcile hidden interaction once.
ui_publish_presentation_visibility :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    visible := ui_composition_presentation_visible(runtime)
    if runtime^.presentation_visible == visible { return false }
    runtime^.presentation_visible = visible
    if !visible { ui_hide_presentation_interaction(runtime) }
    return true
}

// Resolve a visible Presentation or Terminal target.
ui_presentation_target :: proc(
    mouse: geometry.Vector2, regions: viewmodel.Ui_Regions,
    terminal_present: bool) -> viewmodel.Ui_Interaction_Target {
    if terminal_present &&
        geometry.rectangle_contains(
            geometry.Rectangle(regions.terminal_rect), mouse) {
        return ui_interaction_target(.Panel_Content, .Terminal)
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(regions.text_rect), mouse) {
        return ui_interaction_target(.Panel_Content, .Presentation)
    }
    return {}
}

// Resolve the topmost static target under the current pointer sample.
ui_world_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse: geometry.Vector2) -> viewmodel.Ui_Interaction_Target {
    control_id, over_control := animation_control_hit_test(
        geometry.Rectangle(runtime^.ui_regions.world_rect),
        runtime^.gif_capture_phase, mouse)
    if over_control {
        return ui_interaction_target(.Control, id = control_id)
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(runtime^.ui_regions.world_rect), mouse) {
        return ui_interaction_target(.World)
    }
    return {}
}

// Resolve the topmost static target under the current pointer sample.
ui_hover_target :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> viewmodel.Ui_Interaction_Target {
    mouse := input_frame_mouse_position(frame)
    if !splitters_locked_for_gif(runtime^.gif_capture_phase) {
        axis, hovered := splitter_hovered_axis(mouse,
            runtime^.current_layout_mode,
            runtime^.vertical_split_x, runtime^.horizontal_split_y,
            runtime^.window)
        if hovered {
            id := SPLITTER_VERTICAL_PRESS_ID
            if axis == .Horizontal { id = SPLITTER_HORIZONTAL_PRESS_ID }
            return ui_interaction_target(.Splitter, id = id)
        }
    }
    regions := runtime^.ui_regions
    if ui_presentation_is_visible(runtime) {
        target := ui_presentation_target(
            geometry.Vector2(mouse), regions, terminal_present)
        if target.kind != .None { return target }
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(regions.accordion_rect), geometry.Vector2(mouse)) {
        return ui_interaction_target(.Panel_Content, .Accordion)
    }
    return ui_world_hover_target(runtime, geometry.Vector2(mouse))
}

// Resolve persistent logical focus from presentation and routed press transitions.
ui_route_logical_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input,
    pointer_target: viewmodel.Ui_Interaction_Target) -> viewmodel.Ui_Focus_Target {
    result := runtime^.interaction.logical_focus
    terminal_present := input.terminal_present
    visible := ui_presentation_is_visible(runtime)
    if terminal_present && visible && !runtime^.interaction.terminal_was_present {
        result = {kind = .Terminal}
    } else if (!terminal_present || !visible) && result.kind == .Terminal {
        result = {}
    }
    if input_frame_left_pressed(input.frame) && !input.capture.active {
        result = pointer_target.focus
    }
    return result
}

// Return whether Terminal is the active and valid keyboard focus target.
ui_terminal_effectively_focused :: #force_inline proc(
    logical_focus: viewmodel.Ui_Focus_Target,
    window_focused: bool,
    terminal_present, presentation_visible: bool) -> bool {
    return window_focused && terminal_present && presentation_visible &&
        logical_focus.kind == .Terminal
}

// Reconcile persistent logical focus and this frame's effective Terminal focus.
ui_route_interaction_frame :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input) -> viewmodel.Ui_Interaction_Frame {
    hover := ui_hover_target(runtime, input.frame, input.terminal_present)
    capture := ui_capture_target(input.capture)
    pointer_target := hover
    if capture.kind != .None { pointer_target = capture }
    logical_focus := ui_route_logical_focus(runtime, input, pointer_target)
    terminal_focused := ui_terminal_effectively_focused(
        logical_focus, input.frame.window_focused, input.terminal_present,
        ui_presentation_is_visible(runtime))
    wheel_target: viewmodel.Ui_Interaction_Target
    if input.frame.mouse_wheel_delta != 0 && capture.kind == .None {
        wheel_target = hover
    }
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
    ui_refresh_surface_interaction(&result)
    runtime^.interaction.logical_focus = logical_focus
    runtime^.interaction.terminal_was_present = input.terminal_present
    runtime^.interaction.terminal_effectively_focused = terminal_focused
    runtime^.interaction_frame = result
    return result
}

// Route focus through the full interaction result for isolated callers and tests.
ui_reconcile_focus :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> viewmodel.Ui_Interaction_Frame {
    return ui_route_interaction_frame(runtime, {
        frame = frame,
        terminal_present = terminal_present,
        capture = runtime^.ui_press_owner,
    })
}

// Refresh narrow surface eligibility after static or layout-dependent routing.
ui_refresh_surface_interaction :: proc(frame: ^viewmodel.Ui_Interaction_Frame) {
    frame^.terminal = {
        keyboard = frame^.effective_focus.kind == .Terminal,
        pointer = frame^.pointer_target.focus.kind == .Terminal,
        wheel = frame^.wheel_target.focus.kind == .Terminal,
    }
    frame^.presentation = {
        keyboard = frame^.effective_focus.kind == .Presentation,
        pointer = frame^.pointer_target.focus.kind == .Presentation,
        wheel = frame^.wheel_target.focus.kind == .Presentation,
    }
    frame^.accordion = {
        keyboard = frame^.effective_focus.kind == .Accordion,
        pointer = frame^.pointer_target.focus.kind == .Accordion,
        wheel = frame^.wheel_target.focus.kind == .Accordion,
    }
}

// Refine the static Terminal panel target with prepared scrollbar geometry.
ui_refine_terminal_scroll_route :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    over_track: bool,
    pointer_reserved: bool,
    wheel_present: bool) {
    frame := &runtime^.interaction_frame
    scrollbar := ui_interaction_target(
        .Scrollbar, .Terminal, UI_TERMINAL_SCROLLBAR_ID)
    if over_track { frame^.hover = scrollbar }
    capture := frame^.pointer_capture
    capture_allows_scrollbar := capture.kind == .None ||
        capture.kind == .Scrollbar && capture.focus.kind == .Terminal
    if pointer_reserved && capture_allows_scrollbar {
        frame^.pointer_target = scrollbar
    }
    if over_track && wheel_present && capture.kind == .None {
        frame^.wheel_target = scrollbar
    }
    ui_refresh_surface_interaction(frame)
}

// Return pointer fields required to finish admitted local or child transactions.
ui_terminal_captured_pointer_fields :: proc(
    local_capture: bool,
    child_capture: bool) -> input.Input_Pointer_Fields {
    fields: input.Input_Pointer_Fields
    if local_capture { fields += {.Screen_Position, .Release_Edges} }
    if child_capture {
        fields += {.Motion, .Release_Edges, .Levels, .Terminal_Position,
            .Terminal_Ownership}
    }
    return fields
}

// Route one resolved frame to Terminal content from the shared interaction result.
ui_route_terminal_content_frame :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    bounds: geometry.Rectangle,
    route: Ui_Terminal_Content_Route_Input) -> Input_Frame {
    if !runtime^.interaction_frame.terminal.pointer {
        fields := ui_terminal_captured_pointer_fields(
            route.local_capture, route.child_capture)
        return input.input_frame_filter_pointer(
            frame, fields, {bounds.x - 1, bounds.y - 1})
    }
    result := frame
    if route.wheel_consumed || !runtime^.interaction_frame.terminal.wheel {
        result.mouse_wheel_delta = 0
    }
    return result
}