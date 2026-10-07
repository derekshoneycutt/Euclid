package ui

import "../../core"
import contentdata "../../core/content"
import geometry "../../core/geometry"
import viewmodel "../model"
import view_core "../core"
import view_font "../font"
import "../input"
import native "../native"
import terminalview "../terminal"
import ui_dynview "./dynview"
import julia "../../bridge"
import "core:log"

CONTEXT_MENU_PADDING :: f32(8)
CONTEXT_MENU_ROW_HEIGHT :: f32(28)

// context_menu_id qualifies popup nodes by their opening generation.
context_menu_id :: proc(
    menu: ^viewmodel.Ui_Context_Menu_State,
    local_id: int = 0) -> viewmodel.Ui_Node_Id {
    return {
        domain = .Context_Menu,
        local_id = u64(local_id),
        generation = menu^.generation,
    }
}

// context_menu_focus publishes the current enabled item or empty-menu container.
context_menu_focus :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    menu := &runtime^.context_menu
    local_id := menu^.focused + 1
    runtime^.semantic_focus^.logical_focus = context_menu_id(menu, local_id)
    runtime^.semantic_focus^.focus_origin = .Keyboard
    menu^.focus_changed = true
}

// context_menu_close releases popup focus without overriding an outside click.
context_menu_close :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, restore: bool) {
    menu := &runtime^.context_menu
    menu^.active = false
    menu^.focus_changed = restore
    if restore {
        runtime^.semantic_focus^.logical_focus = menu^.target
        runtime^.semantic_focus^.focus_origin = .Keyboard
        menu^.focus_changed = true
    } else if runtime^.semantic_focus^.logical_focus.domain == .Context_Menu {
        semantic_clear_pointer_focus(runtime^.semantic_focus)
    }
}

// context_menu_move finds one enabled command, wrapping once through bounded storage.
context_menu_move :: proc(
    menu: ^viewmodel.Ui_Context_Menu_State,
    direction: int, edge: bool = false) {
    index := menu^.focused
    if edge {
        index = -1 if direction > 0 else menu^.count
    }
    for _ in 0..<menu^.count {
        index = (index + direction + menu^.count) % menu^.count
        if menu^.items[index].enabled {
            menu^.focused = index
            return
        }
    }
    menu^.focused = -1
}

// context_menu_item_rect returns one row's shared drawing and hit-test geometry.
context_menu_item_rect :: proc(
    menu: ^viewmodel.Ui_Context_Menu_State,
    index: int) -> geometry.Rectangle {
    return {menu^.bounds.x + CONTEXT_MENU_PADDING,
        menu^.bounds.y + CONTEXT_MENU_PADDING + f32(index)*CONTEXT_MENU_ROW_HEIGHT,
        menu^.bounds.width - 2*CONTEXT_MENU_PADDING, CONTEXT_MENU_ROW_HEIGHT}
}

// context_menu_hit resolves a row without admitting its disabled action.
context_menu_hit :: proc(
    menu: ^viewmodel.Ui_Context_Menu_State, point: geometry.Vector2) -> int {
    for index in 0..<menu^.count {
        if geometry.rectangle_contains(context_menu_item_rect(menu, index), point) {
            return index
        }
    }
    return -1
}

// context_menu_paste_available preserves prompt readiness and foreground ownership.
context_menu_paste_available :: proc(state: ^core.Euclid_General_State) -> bool {
    term := &state^.terminal
    return term^.initialized && term^.julia_session_ready &&
        (state^.shell.phase == .Running ||
         !term^.awaiting_eval && term^.banner_ready && state^.shell.phase == .Inactive)
}

// context_menu_target_valid rejects changed content, processes, and hidden geometry.
context_menu_target_valid :: proc(state: ^core.Euclid_General_State) -> bool {
    menu := &state^.ui_runtime.context_menu
    if !ui_presentation_is_visible(&state^.ui_runtime) ||
        menu^.window != state^.ui_runtime.window ||
        menu^.viewport != view_text_content_panel(
            state^.ui_runtime.ui_regions.text_rect) {
        return false
    }
    if menu^.target.domain == .Terminal {
        return is_terminal_selected(state) &&
            menu^.target == terminal_semantic_id(state) &&
            menu^.process_id == u64(state^.shell.operation_id.slot) &&
            menu^.process_generation == state^.shell.operation_id.generation
    }
    return !is_terminal_selected(state) &&
        menu^.content_revision == state^.dynview.content.revision &&
        menu^.target == presentation_semantic_id(state)
}

// context_menu_refresh derives availability without reading clipboard content.
context_menu_refresh :: proc(state: ^core.Euclid_General_State) {
    menu := &state^.ui_runtime.context_menu
    if menu^.target.domain == .Terminal {
        term := &state^.terminal
        start, end := terminalview.terminal_selection_ordered(
            term^.view_selection_anchor, term^.view_selection_head)
        menu^.items[0].enabled = term^.view_selection_active && start != end
        menu^.items[1].enabled = context_menu_paste_available(state)
    } else {
        text := julia.current_view_snapshot_text(state)
        content := ui_dynview.dynview_selection_content(&state^.dynview, text)
        selection := &state^.ui_runtime.dynview_selection
        ui_dynview.dynview_selection_reconcile(selection, content)
        menu^.items[0].enabled = selection^.active &&
            selection^.anchor.unit_index != selection^.head.unit_index
        menu^.items[1].enabled = content.unit_count > 0
    }
    if menu^.focused >= 0 && !menu^.items[menu^.focused].enabled {
        context_menu_move(menu, 1)
    }
}

// Admit one command and copy its label into bounded popup-owned storage.
context_menu_append_item :: proc(
    state: ^core.Euclid_General_State,
    command: viewmodel.Ui_Context_Command,
    message: contentdata.Content_Message_Id) -> bool {
    menu := &state^.ui_runtime.context_menu
    if menu^.count >= len(menu^.items) || command == .None {
        log.warn("context_menu_item_rejected reason=capacity_or_command")
        return false
    }
    item := &menu^.items[menu^.count]
    label := view_core.shell_message(state, message)
    if len(label) == 0 || len(label) > len(item^.label) {
        log.warn("context_menu_item_rejected reason=label")
        return false
    }
    item^.command = command
    item^.label_length = len(label)
    copy(item^.label[:], label)
    menu^.count += 1
    return true
}

// Measure admitted labels with a conservative minimum width for unprepared fonts.
context_menu_size :: proc(state: ^core.Euclid_General_State) -> geometry.Vector2 {
    menu := &state^.ui_runtime.context_menu
    width := f32(140)
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    for &item in menu^.items[:menu^.count] {
        measured_width, measured := view_core.ui_text_measure_monospace(
            string(item.label[:item.label_length]), face, TREE_FONT_SIZE, 0)
        if measured {
            width = max(width, measured_width + 2*CONTEXT_MENU_PADDING)
        }
    }
    return {width, 2*CONTEXT_MENU_PADDING + f32(menu^.count)*CONTEXT_MENU_ROW_HEIGHT}
}

// Supply surface commands independently of popup navigation and rendering.
context_menu_surface_items :: proc(state: ^core.Euclid_General_State) -> bool {
    if !context_menu_append_item(state, .Copy, .Context_Copy) {
        return false
    }
    if state^.ui_runtime.context_menu.target.domain == .Terminal {
        return context_menu_append_item(state, .Paste, .Context_Paste)
    }
    return context_menu_append_item(state, .Select_All, .Context_Select_All)
}

// context_menu_place keeps the popup inside the current logical window.
context_menu_place :: proc(
    anchor: geometry.Vector2, size: geometry.Vector2,
    window: viewmodel.Ui_Window_Metrics) -> geometry.Rectangle {
    width := min(size.x, f32(window.width))
    height := min(size.y, f32(window.height))
    return {
        max(0, min(anchor.x, f32(window.width)-width)),
        max(0, min(anchor.y, f32(window.height)-height)),
        width, height,
    }
}

// context_menu_open records an immutable target while preserving selection and cursor.
context_menu_open :: proc(
    state: ^core.Euclid_General_State,
    target: viewmodel.Ui_Node_Id, anchor: geometry.Vector2) {
    runtime := &state^.ui_runtime
    menu := &runtime^.context_menu
    generation := menu^.generation + 1
    capture := menu^.captured_buttons
    swallowed := menu^.swallowed_activation_keys
    caret := menu^.keyboard_anchor
    menu^ = {
        active = true, target = target, generation = generation,
        content_revision = state^.dynview.content.revision,
        process_id = u64(state^.shell.operation_id.slot),
        process_generation = state^.shell.operation_id.generation,
        focused = -1, pressed_item = -1, captured_buttons = capture,
        swallowed_activation_keys = swallowed, keyboard_anchor = caret,
        window = runtime^.window,
        viewport = view_text_content_panel(runtime^.ui_regions.text_rect),
    }
    if !context_menu_surface_items(state) {
        context_menu_close(runtime, false)
        return
    }
    context_menu_refresh(state)
    context_menu_move(menu, 1)
    menu^.bounds = context_menu_place(anchor, context_menu_size(state), runtime^.window)
    runtime^.interaction.logical_focus =
        {kind = .Terminal} if target.domain == .Terminal else
            viewmodel.Ui_Focus_Target{kind = .Presentation}
    context_menu_focus(runtime)
}

// context_menu_keyboard_anchor uses current prepared caret geometry or pane fallback.
context_menu_keyboard_anchor :: proc(
    state: ^core.Euclid_General_State) -> geometry.Vector2 {
    panel := view_text_content_panel(state^.ui_runtime.ui_regions.text_rect)
    caret := state^.ui_runtime.context_menu.keyboard_anchor
    if is_terminal_selected(state) && caret.height > 0 {
        return {
            max(panel.x, min(caret.x, panel.x+panel.width-CONTEXT_MENU_PADDING)),
            max(panel.y,
                min(caret.y+caret.height, panel.y+panel.height-CONTEXT_MENU_PADDING)),
        }
    }
    selection := state^.ui_runtime.dynview_selection
    targets := state^.dynview.compile_cache.document_layout_copy_targets
    if selection.active && selection.mode == .Semantic_Document && len(targets) > 0 {
        index := max(0, min(selection.head.unit_index-1, len(targets)-1))
        rect := ui_dynview.dynview_document_target_rect(targets[index], {
            panel = panel, scroll_y = state^.ui_runtime.view_text_scroll_y,
            text_padding = TEXT_PADDING})
        return {
            max(panel.x, min(rect.x, panel.x+panel.width-CONTEXT_MENU_PADDING)),
            max(panel.y,
                min(rect.y+rect.height, panel.y+panel.height-CONTEXT_MENU_PADDING)),
        }
    }
    return {panel.x + CONTEXT_MENU_PADDING, panel.y + CONTEXT_MENU_PADDING}
}

// context_menu_pointer_target admits content presses without stealing child capture.
context_menu_pointer_target :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    child_capture: bool) -> viewmodel.Ui_Node_Id {
    runtime := &state^.ui_runtime
    if !frame.window_focused || runtime^.ui_press_owner.active || child_capture ||
        !ui_presentation_is_visible(runtime) {
        return {}
    }
    panel := view_text_content_panel(runtime^.ui_regions.text_rect)
    panel.width -= SCROLLBAR_WIDTH
    if !geometry.rectangle_contains(panel, input_frame_mouse_position(frame)) {
        return {}
    }
    if is_terminal_selected(state) {
        if terminalview.terminal_mouse_reporting_owns_pointer(&state^.terminal, frame) {
            return {}
        }
        if !state^.terminal.initialized || !state^.terminal.julia_session_ready {
            return {}
        }
        return terminal_semantic_id(state)
    }
    return presentation_semantic_id(state)
}

// context_menu_activate retains exactly one validated owner command.
context_menu_activate :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, index: int) {
    menu := &runtime^.context_menu
    if index < 0 || index >= menu^.count || !menu^.items[index].enabled {
        return
    }
    menu^.pending = menu^.items[index].command
    context_menu_close(runtime, true)
}

// Apply directional keys independently of command activation and dismissal.
context_menu_navigation_key :: proc(
    menu: ^viewmodel.Ui_Context_Menu_State, key: input.Input_Key) -> bool {
    #partial switch key {
    case .Down:
        context_menu_move(menu, 1)
    case .Up:
        context_menu_move(menu, -1)
    case .Home:
        context_menu_move(menu, 1, true)
    case .End:
        context_menu_move(menu, -1, true)
    case:
        return false
    }
    return true
}

// context_menu_key applies popup-only navigation without Terminal key interpretation.
context_menu_key :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, event: input.Input_Event) {
    menu := &runtime^.context_menu
    if event.kind != .Press && event.kind != .Repeat {
        return
    }
    if context_menu_navigation_key(menu, event.key) {
        context_menu_focus(runtime)
        return
    }
    #partial switch event.key {
    case .Enter, .Space:
        menu^.swallowed_activation_keys |= 1 if event.key == .Enter else 2
        if event.kind == .Press {
            context_menu_activate(runtime, menu^.focused)
        }
    case .Escape:
        context_menu_close(runtime, true)
    case .Tab:
        if event.kind != .Press {
            return
        }
        context_menu_close(runtime, true)
        snapshot := semantic_snapshot(runtime^.semantic_focus)
        next := semantic_next_tab_stop(snapshot, menu^.target, .Shift in event.modifiers)
        if next >= 0 {
            runtime^.semantic_focus^.logical_focus = snapshot^.nodes[next].id
        }
    }
    if menu^.active { context_menu_focus(runtime) }
}

// context_menu_opening_key recognizes reserved Euclid popup chords.
context_menu_opening_key :: proc(event: input.Input_Event) -> bool {
    return event.kind == .Press &&
        (event.key == .Menu && event.modifiers == {} ||
         event.key == .F10 && event.modifiers == {.Shift})
}

// context_menu_route_keyboard claims popup events and their correlated text.
context_menu_route_keyboard :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    claims: ^input.Input_Event_Claim_State) {
    menu := &state^.ui_runtime.context_menu
    owned := menu^.active || menu^.pending != .None
    for event, index in frame.events {
        bit := u8(1) if event.key == .Enter else u8(2) if event.key == .Space else u8(0)
        if bit != 0 && menu^.swallowed_activation_keys & bit != 0 {
            _ = input.input_event_claim(frame, index, claims)
            if event.kind == .Release {
                menu^.swallowed_activation_keys &= ~bit
            }
            continue
        }
        if !owned && frame.window_focused && context_menu_opening_key(event) {
            target := state^.ui_runtime.semantic_focus^.logical_focus
            if target.domain == .Presentation || target.domain == .Terminal {
                context_menu_open(state, target, context_menu_keyboard_anchor(state))
                owned = true
            }
        } else if menu^.active {
            context_menu_key(&state^.ui_runtime, event)
        }
        if owned {
            _ = input.input_event_claim(frame, index, claims)
        }
    }
}

// Retain all popup presses, activating only a matching left-button release.
context_menu_pointer_items :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, frame: input.Input_Frame,
    result: input.Input_Frame, captured: input.Input_Mouse_Buttons) {
    menu := &runtime^.context_menu
    point := input_frame_mouse_position(frame)
    inside := geometry.rectangle_contains(menu^.bounds, point)
    index := context_menu_hit(menu, point)
    if inside {
        menu^.captured_buttons |= transmute(u8)result.mouse_pressed
        if index >= 0 && menu^.items[index].enabled && frame.mouse_moved {
            menu^.focused = index
            context_menu_focus(runtime)
        }
        if .Left in result.mouse_pressed {
            menu^.pressed_item = index
        }
    }
    if .Left in frame.mouse_released && .Left in captured {
        if inside && index == menu^.pressed_item {
            context_menu_activate(runtime, index)
        }
        menu^.pressed_item = -1
    }
}

// context_menu_route_pointer isolates complete popup pointer transactions.
context_menu_route_pointer :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    child_capture: bool) -> input.Input_Frame {
    menu := &state^.ui_runtime.context_menu
    result := frame
    captured := transmute(input.Input_Mouse_Buttons)menu^.captured_buttons
    result.mouse_pressed -= captured
    result.mouse_released -= captured
    result.mouse_down -= captured
    menu^.captured_buttons = transmute(u8)(captured & frame.mouse_down)
    inside_existing := menu^.active && geometry.rectangle_contains(
        menu^.bounds, input_frame_mouse_position(frame))
    if .Right in result.mouse_pressed && !inside_existing {
        target := context_menu_pointer_target(state, frame, child_capture)
        if target != (viewmodel.Ui_Node_Id{}) {
            context_menu_open(state, target, input_frame_mouse_position(frame))
            menu^.captured_buttons |= transmute(u8)input.Input_Mouse_Buttons{.Right}
        } else if menu^.active {
            context_menu_close(&state^.ui_runtime, false)
            return result
        }
    }
    if !menu^.active {
        return result
    }
    point := input_frame_mouse_position(frame)
    inside := geometry.rectangle_contains(menu^.bounds, point)
    if !inside && card(result.mouse_pressed - {.Right}) > 0 {
        context_menu_close(&state^.ui_runtime, false)
        return result
    }
    context_menu_pointer_items(&state^.ui_runtime, frame, result, captured)
    return input.input_frame_filter_pointer(result, {.Screen_Position})
}

// context_menu_route runs before ordinary routing and returns only unowned input.
context_menu_route :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    storage: []input.Input_Event, child_capture: bool) -> input.Input_Frame {
    menu := &state^.ui_runtime.context_menu
    if menu^.active && (!frame.window_focused || !context_menu_target_valid(state)) {
        context_menu_close(&state^.ui_runtime, false)
    }
    if menu^.active {
        context_menu_refresh(state)
    }
    result := context_menu_route_pointer(state, frame, child_capture)
    claims: input.Input_Event_Claim_State
    context_menu_route_keyboard(state, result, &claims)
    return input.input_frame_copy_unclaimed_events(result, &claims, storage)
}

// context_menu_publish registers content-free popup nodes in the staged hierarchy.
context_menu_publish :: proc(state: ^core.Euclid_General_State) {
    runtime := &state^.ui_runtime
    menu := &runtime^.context_menu
    if !menu^.active {
        return
    }
    id := context_menu_id(menu)
    _ = semantic_register_control(runtime^.semantic_focus, {
        id = id, parent = menu^.target, role = .Menu,
        states = {.Visible, .Enabled, .Focusable}, actions = {.Focus},
        bounds = menu^.bounds, clip_bounds = menu^.bounds,
        label = view_core.shell_message(state, .Context_Menu_Label)})
    for &item, index in menu^.items[:menu^.count] {
        states := viewmodel.Ui_Node_State{.Visible, .Focusable}
        if item.enabled {
            states += {.Enabled}
        }
        _ = semantic_register_control(runtime^.semantic_focus, {
            id = context_menu_id(menu, index+1), parent = id, role = .Menu_Item,
            states = states, actions = {.Focus, .Activate},
            bounds = context_menu_item_rect(menu, index), clip_bounds = menu^.bounds,
            label = string(item.label[:item.label_length])})
    }
}

// context_menu_prepare converges native popup requests before semantic publication.
context_menu_prepare :: proc(state: ^core.Euclid_General_State) {
    runtime := &state^.ui_runtime
    menu := &runtime^.context_menu
    if menu^.active && !context_menu_target_valid(state) {
        context_menu_close(runtime, false)
    }
    commands := runtime^.semantic_focus^.commands[:runtime^.semantic_focus^.command_count]
    for command in commands {
        if command.kind == .Show_Context_Menu &&
            (command.target == presentation_semantic_id(state) &&
             !is_terminal_selected(state) ||
             command.target == terminal_semantic_id(state) &&
             is_terminal_selected(state)) {
            context_menu_open(state, command.target, context_menu_keyboard_anchor(state))
        }
        if menu^.active &&
            command.target == context_menu_id(menu, int(command.target.local_id)) &&
            command.kind == .Activate {
            context_menu_activate(runtime, int(command.target.local_id)-1)
        }
    }
    if menu^.active {
        context_menu_refresh(state)
        focused := runtime^.semantic_focus^.logical_focus
        if focused.domain == .Context_Menu && focused.local_id > 0 {
            menu^.focused = int(focused.local_id)-1
        }
        context_menu_publish(state)
    }
}

// context_menu_execute_presentation applies the shared selection representation.
context_menu_execute_presentation :: proc(
    state: ^core.Euclid_General_State, command: viewmodel.Ui_Context_Command) {
    text := julia.current_view_snapshot_text(state)
    content := ui_dynview.dynview_selection_content(&state^.dynview, text)
    selection := &state^.ui_runtime.dynview_selection
    ui_dynview.dynview_selection_reconcile(selection, content)
    if command == .Select_All {
        ui_dynview.dynview_selection_select_all(selection, content.unit_count)
    } else if command == .Copy {
        if !ui_dynview.dynview_selection_copy(&state^.dynview, selection^, text) {
            log.warn("context_menu_copy_rejected")
        }
    }
}

// draw_encoded_context_menu renders the popup after all ordinary UI passes.
draw_encoded_context_menu :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    menu := &state^.ui_runtime.context_menu
    if !menu^.active {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, menu^.bounds)
    _ = native.draw_encoder_rectangle(
        encoder, menu^.bounds, UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder, menu^.bounds, 1, UI_BORDER_COLOR)
    for &item, index in menu^.items[:menu^.count] {
        row := context_menu_item_rect(menu, index)
        if menu^.focused == index {
            _ = native.draw_encoder_rectangle_outline(encoder, row, 1, UI_TEXT_COLOR)
        }
        label := string(item.label[:item.label_length])
        context_menu_draw_label(state, encoder, label, row, item.enabled)
    }

    _ = native.draw_encoder_pop_scissor(encoder)
}

// context_menu_draw_label distinguishes disabled commands without hiding their names.
context_menu_draw_label :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    label: string, row: geometry.Rectangle, enabled: bool) {
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    tint := UI_TEXT_COLOR
    if !enabled {
        tint = UI_BORDER_COLOR
    }
    _ = view_core.ui_text_shaped({
        encoder = encoder,
        resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        key = .Regular, text = label,
        position = {row.x, row.y + (row.height-TREE_FONT_SIZE)*0.5},
        color = tint, font = view_core.ui_text_font(face),
    })
}
