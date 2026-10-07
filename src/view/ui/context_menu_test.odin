#+test
package ui

import "../../core"
import viewmodel "../model"
import bridgemodel "../../bridge/model"
import "../input"
import "core:testing"

// context_menu_test_state supplies owned localization and bounded semantic storage.
context_menu_test_state :: proc(t: ^testing.T) -> ^core.Euclid_General_State {
    state := make_shell_test_state(t)
    runtime := &state^.ui_runtime
    runtime^.semantic_focus = new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    runtime^.window = {640, 400}
    runtime^.presentation_visible = true
    runtime^.ui_regions.text_rect = {100, 100, 400, 200}
    runtime^.context_menu = {active = true, generation = 1,
        target = presentation_semantic_id(state), count = 2, focused = 0,
        bounds = {120, 120, 160, 72}, pressed_item = -1,
        viewport = view_text_content_panel(runtime^.ui_regions.text_rect),
        window = runtime^.window}
    runtime^.context_menu.items[0] = {command = .Copy, enabled = true}
    runtime^.context_menu.items[1] = {command = .Select_All, enabled = true}
    context_menu_focus(runtime)
    return state
}

// context_menu_test_destroy releases synthetic owners without native teardown.
context_menu_test_destroy :: proc(state: ^core.Euclid_General_State) {
    free(state^.ui_runtime.semantic_focus, context.allocator)
    destroy_shell_test_state(state)
}

// Verify stable menu sets and opening preservation of logical Dynview selection.
@(test)
context_menu_opens_exact_surface_commands :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    state^.dynview.enabled = true
    state^.dynview.cache_access_state = .Display_Readable
    state^.dynview.compile_cache.is_valid = true
    state^.dynview.content.presentation_mime = .Text_Latex
    source := "x"
    state^.dynview.content.presentation_bytes = transmute([]u8)source
    selection := &state^.ui_runtime.dynview_selection
    selection^ = {mode = .Atomic_Source, active = true, head = {unit_index = 1}}
    context_menu_open(state, presentation_semantic_id(state), {120, 120})
    menu := &state^.ui_runtime.context_menu
    testing.expect_value(t, menu^.count, 2)
    testing.expect_value(t, menu^.items[0].command, viewmodel.Ui_Context_Command.Copy)
    testing.expect_value(t, menu^.items[1].command,
        viewmodel.Ui_Context_Command.Select_All)
    testing.expect_value(t,
        string(menu^.items[1].label[:menu^.items[1].label_length]), "Select All")
    testing.expect(t, selection^.active && selection^.head.unit_index == 1)
    animation := bridgemodel.Euclid_Julia_Animation_Interface{node_kind = .Terminal}
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = &animation
    context_menu_open(state, terminal_semantic_id(state), {120, 120})
    testing.expect_value(t, menu^.items[1].command, viewmodel.Ui_Context_Command.Paste)
    testing.expect_value(t,
        string(menu^.items[1].label[:menu^.items[1].label_length]), "Paste")
}

// Verify navigation skips disabled rows and remains safe when every row is disabled.
@(test)
context_menu_navigation_is_bounded :: proc(t: ^testing.T) {
    menu := viewmodel.Ui_Context_Menu_State{count = 3, focused = 0}
    menu.items[0].enabled = true
    menu.items[2].enabled = true
    context_menu_move(&menu, 1)
    testing.expect_value(t, menu.focused, 2)
    context_menu_move(&menu, 1)
    testing.expect_value(t, menu.focused, 0)
    context_menu_move(&menu, -1, true)
    testing.expect_value(t, menu.focused, 2)
    menu.items[0].enabled = false
    menu.items[2].enabled = false
    context_menu_move(&menu, 1)
    testing.expect_value(t, menu.focused, -1)
}

// Verify outside pointer presses survive dismissal without old-pane focus restoration.
@(test)
context_menu_outside_click_passes_through_once :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    frame := input.Input_Frame{mouse_position = {10, 10},
        mouse_pressed = {.Left}, mouse_down = {.Left}}
    routed := context_menu_route_pointer(state, frame, false)
    testing.expect(t, !state^.ui_runtime.context_menu.active)
    testing.expect_value(t, routed.mouse_pressed, frame.mouse_pressed)
    testing.expect_value(t, routed.mouse_down, frame.mouse_down)
    testing.expect(t, state^.ui_runtime.semantic_focus^.logical_focus == {})
}

// Verify item presses stay owned and execute only on matching release.
@(test)
context_menu_item_click_never_reaches_underlying_content :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    pressed := input.Input_Frame{mouse_position = {130, 135},
        mouse_pressed = {.Left}, mouse_down = {.Left}}
    routed := context_menu_route_pointer(state, pressed, false)
    testing.expect(t, routed.mouse_pressed == {} && routed.mouse_down == {})
    released := pressed
    released.mouse_pressed = {}
    released.mouse_down = {}
    released.mouse_released = {.Left}
    routed = context_menu_route_pointer(state, released, false)
    menu := &state^.ui_runtime.context_menu
    testing.expect(t, routed.mouse_released == {} && !menu^.active)
    testing.expect_value(t, menu^.pending, viewmodel.Ui_Context_Command.Copy)
    testing.expect_value(t, state^.ui_runtime.semantic_focus^.logical_focus, menu^.target)
}

// Verify Escape restores the origin while popup keyboard/text never reaches Terminal.
@(test)
context_menu_claims_ordered_keyboard_and_text :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    events := [3]input.Input_Event{
        {kind = .Press, key = .Escape},
        {kind = .Text, codepoint = 'x'},
        {kind = .Press, key = .Enter}}
    frame := input.Input_Frame{events = events[:]}
    claims: input.Input_Event_Claim_State
    context_menu_route_keyboard(state, frame, &claims)
    testing.expect(t, claims.claimed[0] && claims.claimed[1] && claims.claimed[2])
    testing.expect(t, !state^.ui_runtime.context_menu.active)
    testing.expect_value(t, state^.ui_runtime.context_menu.pending,
        viewmodel.Ui_Context_Command.None)
}

// Verify pointer activation cannot leak same-frame text after closing the popup.
@(test)
context_menu_pointer_activation_claims_remaining_text :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    frame := input.Input_Frame{mouse_position = {130, 135},
        mouse_pressed = {.Left}, mouse_down = {.Left}}
    _ = context_menu_route_pointer(state, frame, false)
    frame.mouse_pressed = {}
    frame.mouse_down = {}
    frame.mouse_released = {.Left}
    _ = context_menu_route_pointer(state, frame, false)
    events := [1]input.Input_Event{{kind = .Text, codepoint = 'x'}}
    claims: input.Input_Event_Claim_State
    context_menu_route_keyboard(state, {events = events[:]}, &claims)
    testing.expect(t, claims.claimed[0])
}

// Verify activation repeat/release is consumed after dismissal and cannot submit input.
@(test)
context_menu_activation_release_stays_owned :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    context_menu_key(&state^.ui_runtime, {kind = .Press, key = .Enter})
    events := [2]input.Input_Event{
        {kind = .Repeat, key = .Enter}, {kind = .Release, key = .Enter}}
    claims: input.Input_Event_Claim_State
    context_menu_route_keyboard(state, {events = events[:]}, &claims)
    testing.expect(t, claims.claimed[0] && claims.claimed[1])
    testing.expect_value(t,
        state^.ui_runtime.context_menu.swallowed_activation_keys, u8(0))
}

// Verify target replacement and resized geometry invalidate the retained command owner.
@(test)
context_menu_rejects_stale_content_and_geometry :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    testing.expect(t, context_menu_target_valid(state))
    state^.dynview.content.revision += 1
    testing.expect(t, !context_menu_target_valid(state))
    state^.dynview.content.revision -= 1
    state^.ui_runtime.window.width += 1
    testing.expect(t, !context_menu_target_valid(state))
}

// Verify placement is bounded at window edges and reserved chords are exact.
@(test)
context_menu_placement_and_opening_chords :: proc(t: ^testing.T) {
    box := context_menu_place({639, 399}, {160, 72}, {640, 400})
    testing.expect_value(t, box, viewmodel.Rectangle{480, 328, 160, 72})
    testing.expect(t, context_menu_opening_key({kind = .Press, key = .Menu}))
    testing.expect(t,
        context_menu_opening_key({kind = .Press, key = .F10, modifiers = {.Shift}}))
    testing.expect(t, !context_menu_opening_key({kind = .Press, key = .F10}))
    testing.expect(t, !context_menu_opening_key({kind = .Repeat, key = .Menu}))
}

// Verify bounded descriptor admission rejects overflow without changing existing rows.
@(test)
context_menu_command_admission_is_atomic :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    menu := &state^.ui_runtime.context_menu
    menu^.count = 0
    for _ in 0..<len(menu^.items) {
        testing.expect(t, context_menu_append_item(state, .Copy, .Context_Copy))
    }
    before := menu^.items
    testing.expect(t, !context_menu_append_item(state, .Paste, .Context_Paste))
    testing.expect_value(t, menu^.count, len(menu^.items))
    testing.expect_value(t, menu^.items, before)
}

// Verify every popup button release stays owned after dismissal, including disabled rows.
@(test)
context_menu_disabled_rows_capture_all_buttons :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    state^.ui_runtime.context_menu.items[0].enabled = false
    frame := input.Input_Frame{mouse_position = {130, 135},
        mouse_pressed = {.Left, .Middle, .Right}, mouse_down = {.Left, .Middle, .Right}}
    routed := context_menu_route_pointer(state, frame, false)
    testing.expect(t, routed.mouse_pressed == {} && routed.mouse_down == {})
    context_menu_close(&state^.ui_runtime, true)
    frame.mouse_pressed = {}
    frame.mouse_down = {}
    frame.mouse_released = {.Left, .Middle, .Right}
    routed = context_menu_route_pointer(state, frame, false)
    testing.expect(t, routed.mouse_released == {})
    testing.expect_value(t, state^.ui_runtime.context_menu.pending,
        viewmodel.Ui_Context_Command.None)
}

// Verify negotiated Terminal mouse reporting and existing capture outrank popup opening.
@(test)
context_menu_terminal_pointer_priority :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    animation := bridgemodel.Euclid_Julia_Animation_Interface{node_kind = .Terminal}
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = &animation
    state^.terminal.initialized = true
    state^.terminal.julia_session_ready = true
    state^.terminal.output_interpreter.input_mode = {
        mouse_tracking = .Button, mouse_sgr_encoding = true}
    frame := input.Input_Frame{window_focused = true, mouse_position = {150, 150},
        mouse_pressed = {.Right}, mouse_down = {.Right}}
    testing.expect_value(t, context_menu_pointer_target(state, frame, false),
        viewmodel.Ui_Node_Id{})
    frame.mouse_modifiers = {.Shift}
    testing.expect_value(t, context_menu_pointer_target(state, frame, false),
        terminal_semantic_id(state))
    testing.expect_value(t, context_menu_pointer_target(state, frame, true),
        viewmodel.Ui_Node_Id{})
    state^.ui_runtime.ui_press_owner.active = true
    testing.expect_value(t, context_menu_pointer_target(state, frame, false),
        viewmodel.Ui_Node_Id{})
    state^.terminal.initialized = false
}

// Verify focus loss, hidden panes and replacement foreground owners revoke the menu.
@(test)
context_menu_revokes_invalid_owners :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    _ = context_menu_route(state, {window_focused = false}, storage[:], false)
    testing.expect(t, !state^.ui_runtime.context_menu.active)
    testing.expect_value(t, state^.ui_runtime.semantic_focus^.logical_focus,
        viewmodel.Ui_Node_Id{})
    state^.ui_runtime.presentation_visible = false
    testing.expect(t, !context_menu_target_valid(state))
    state^.ui_runtime.presentation_visible = true
    animation := bridgemodel.Euclid_Julia_Animation_Interface{node_kind = .Terminal}
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.selected_animation = &animation
    context_menu_open(state, terminal_semantic_id(state), {120, 120})
    testing.expect(t, context_menu_target_valid(state))
    state^.shell.operation_id.generation += 1
    testing.expect(t, !context_menu_target_valid(state))
}

// Verify Tab leaves the popup through application traversal rather than Terminal input.
@(test)
context_menu_tab_traverses_from_origin :: proc(t: ^testing.T) {
    state := context_menu_test_state(t)
    defer context_menu_test_destroy(state)
    semantic := state^.ui_runtime.semantic_focus
    snapshot := semantic_snapshot(semantic)
    snapshot^.node_count = 2
    snapshot^.nodes[0] = semantic_test_node(
        state^.ui_runtime.context_menu.target, {}, .Presentation, 0)
    snapshot^.nodes[1] = semantic_test_node({domain = .Animation_Control, local_id = 1},
        {}, .Animation_Overlay, 0)
    context_menu_key(&state^.ui_runtime, {kind = .Press, key = .Tab})
    testing.expect(t, !state^.ui_runtime.context_menu.active)
    testing.expect_value(t, semantic^.logical_focus, snapshot^.nodes[1].id)
}
