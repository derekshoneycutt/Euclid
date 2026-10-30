package uioverlay

import core "../../../core"
import collections "../../../collections"
import geometry "../../../core/geometry"
import uuid "core:encoding/uuid"
import input "../../input"
import viewmodel "../model"
import uiwidgets "../widgets"
import theme "../theme"

// Return the shared unclipped row bounds; all painting and hit testing use this geometry.
membership_row :: proc(
    menu: ^viewmodel.Ui_Collection_Membership_State,
    index: int) -> geometry.Rectangle {
    scale := theme.ui_control_size_scale(menu.control_size_percent)
    return {
        menu.clip.x,
        menu.clip.y + f32(index)*menu.row_height - menu.scroll_y,
        max(0, menu.clip.width - 14*scale),
        menu.row_height,
    }
}

// Keyboard and native focus reveal any destination without rebuilding or copying its label.
membership_focus :: proc(state: ^core.Euclid_General_State, id: uuid.Identifier) {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    for slot, index in menu.order[:menu.count] {
        if set.collections[slot].id != id {
            continue
        }
        top := f32(index)*menu.row_height
        menu.scroll_y = clamp(
            menu.scroll_y, top + menu.row_height - menu.clip.height, top)
        menu.scroll_y = max(menu.scroll_y, 0)
        menu.focused = id
        focus := state.ui_runtime.semantic_focus
        focus.logical_focus = membership_id(menu, id)
        focus.focus_origin = .Keyboard
        return
    }
}

// Move through current Library order, wrapping only for ordinary arrow and tab navigation.
membership_move :: proc(state: ^core.Euclid_General_State, direction: int, edge: bool) {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    current := -1
    for slot, index in menu.order[:menu.count] {
        if set.collections[slot].id == menu.focused {
            current = index; break
        }
    }
    if edge {
        current = -1 if direction > 0 else menu.count
    }
    next := (current + direction + menu.count) % menu.count
    membership_focus(state, set.collections[menu.order[next]].id)
}

// Keep popup keyboard ownership through repeat and release and reject held activation.
membership_key :: proc(state: ^core.Euclid_General_State, event: input.Input_Event) {
    if event.kind != .Press && event.kind != .Repeat {
        return
    }
    #partial switch event.key {
    case .Up:
        membership_move(state, -1, false)
    case .Down:
        membership_move(state, 1, false)
    case .Home:
        membership_move(state, 1, true)
    case .End:
        membership_move(state, -1, true)
    case .Tab:
        membership_move(state, -1 if .Shift in event.modifiers else 1, false)
    case .Enter, .Space:
        state.ui_runtime.membership.swallowed_keys |= 1 if event.key == .Enter else 2
        if event.kind == .Press {
            membership_request(state, state.ui_runtime.membership.focused)
        }
    case .Escape:
        membership_close(state, true)
    }
}

// Use the standard checkbox press/release widget; its accepted state is never optimistic.
membership_checkbox :: proc(
    state: ^core.Euclid_General_State, index: int,
    frame: input.Input_Frame) -> uiwidgets.Checkbox_Params {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    head := &set.collections[menu.order[index]]
    _, failure := collections.collection_edit_index(set, head.id)
    _, policy := collections.collection_animation_identity(
        set, head.id, menu.animation_id)
    row := membership_row(menu, index)
    scale := theme.ui_control_size_scale(menu.control_size_percent)
    return {
        id = index + 1,
        rect = {
            row.x + 2*scale,
            row.y + (row.height - 18*scale) * 0.5,
            18*scale,
            18*scale,
        },
        checked = policy == .None,
        enabled = failure == .None,
        mouse = frame,
        interaction_space_rect = menu.clip,
        interaction_enabled = true,
        semantic_clip = menu.clip,
    }
}

// Wheel, track and thumb interaction use the same scroll container as other Euclid panels.
membership_scroll :: proc(state: ^core.Euclid_General_State,
    frame: input.Input_Frame) -> uiwidgets.Scroll_Container_Update_Result {
    menu := &state.ui_runtime.membership
    result := uiwidgets.scroll_container_update({
        id = -2104,
        rect = menu.clip,
        scroll_y_in = menu.scroll_y,
        content_height = f32(menu.count) * menu.row_height,
        mouse_input = frame,
        interaction_space_rect = menu.clip,
        wheel_step = menu.row_height * 3,
        control_size_percent = menu.control_size_percent,
        press_owner = &menu.press_owner,
        state_in = {menu.dragging, menu.drag_offset},
    })
    menu.scroll_y = result.scroll_y_out
    menu.dragging, menu.drag_offset = result.state_out.is_dragging_thumb,
        result.state_out.drag_offset_y
    return result
}

// Capture identity at press and reject a release whose row moved under the pointer.
membership_pointer :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame) {
    menu := &state.ui_runtime.membership
    scrolling := membership_scroll(state, frame)
    if scrolling.pointer_reserved {
        return
    }
    set := &state.preferences_runtime.collections_state
    for slot, index in menu.order[:menu.count] {
        params := membership_checkbox(state, index, frame)
        row := membership_row(menu, index)
        params.rect = row
        result := uiwidgets.update_checkbox(params, &menu.press_owner)
        if result.pressed && uiwidgets.input_frame_left_pressed(frame) {
            menu.pressed = set.collections[slot].id
            menu.focused = menu.pressed
            state.ui_runtime.semantic_focus.logical_focus = membership_id(
                menu, menu.focused)
            state.ui_runtime.semantic_focus.focus_origin = .Pointer
        }
        if result.toggled && menu.pressed == set.collections[slot].id {
            membership_request(state, menu.pressed)
        }
    }
    if uiwidgets.input_frame_left_released(frame) {
        menu.pressed = {}
    }
}

// Claim complete keyboard transactions, including correlated text and post-dismissal key release.
membership_route_keys :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    claims: ^input.Input_Event_Claim_State) {
    menu := &state.ui_runtime.membership
    for event, index in frame.events {
        bit := u8(1) if event.key == .Enter else u8(2) if event.key == .Space else 0
        swallowed := !input.input_event_is_text_payload(event) &&
            bit != 0 && menu.swallowed_keys & bit != 0
        if menu.active || swallowed {
            input.input_event_claim(frame, index, claims)
            if menu.active {
                membership_key(state, event)
            }
            if event.kind == .Release {
                menu.swallowed_keys &= ~bit
            }
        }
    }
}

// Isolate complete popup pointer/key transactions before underlying controls see the frame.
membership_route :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    storage: []input.Input_Event) -> input.Input_Frame {
    menu := &state.ui_runtime.membership
    if menu.active &&
       (!frame.window_focused || !membership_valid(state) || !membership_order(state)) {
        membership_close(state, false)
    }
    result := frame
    captured := transmute(input.Input_Mouse_Buttons)menu.captured_buttons
    result.mouse_pressed -= captured
    result.mouse_released -= captured
    result.mouse_down -= captured
    menu.captured_buttons = transmute(u8)(captured & frame.mouse_down)
    claims: input.Input_Event_Claim_State
    membership_route_keys(state, frame, &claims)
    if menu.active {
        if !geometry.rectangle_contains(
            menu.bounds, uiwidgets.input_frame_mouse_position(frame)) &&
            card(result.mouse_pressed) > 0 {
            membership_close(state, false)
        } else {
            membership_pointer(state, frame)
            menu.captured_buttons |= transmute(u8)frame.mouse_pressed
            result = input.input_frame_filter_pointer(result, {.Screen_Position})
        }
    }
    return input.input_frame_copy_unclaimed_events(result, &claims, storage)
}
