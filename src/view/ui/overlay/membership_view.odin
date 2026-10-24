package uioverlay

import core "../../../core"
import viewmodel "../model"
import native "../../native"
import viewmessages "../../messages"
import uisemantics "../semantics"
import uiwidgets "../widgets"
import theme "../theme"

// Consume UUID/opening-qualified native commands without allowing a stale popup to retarget.
membership_commands :: proc(state: ^core.Euclid_General_State) {
    menu := &state.ui_runtime.membership
    if !menu.active {
        return
    }
    focus := state.ui_runtime.semantic_focus
    for command in focus.commands[:focus.command_count] {
        if command.target.domain != .Collection_Membership ||
            command.target != membership_id(menu, command.target.stable_id) {
            continue
        }
        if command.kind == .Toggle {
            membership_request(state, command.target.stable_id)
        }
        if command.kind == .Focus {
            membership_focus(state, command.target.stable_id)
        }
    }
}

// Publish real checkbox roles with accepted values and the same clipped geometry as pointer input.
membership_publish_row :: proc(state: ^core.Euclid_General_State, index: int) {
    menu := &state.ui_runtime.membership
    set := &state.preferences_runtime.collections_state
    head := &set.collections[menu.order[index]]
    params := membership_checkbox(state, index, {})
    states := viewmodel.Ui_Node_State{.Visible, .Focusable}
    if params.enabled {
        states += {.Enabled}
    }
    if params.checked {
        states += {.Checked}
    }
    _ = uisemantics.semantic_register_control(state.ui_runtime.semantic_focus, {
        id = membership_id(menu, head.id), parent = membership_id(menu),
        role = .Checkbox, states = states, actions = {.Focus, .Toggle},
        traversal_order = u32(index),
        bounds = membership_row(menu, index), clip_bounds = menu.clip,
        label = string(head.name[:head.name_length]),
    })
}

// Final geometry validation happens after splitters, layout and selection commits.
membership_prepare :: proc(state: ^core.Euclid_General_State) {
    menu := &state.ui_runtime.membership
    if !menu.active {
        return
    }
    if !membership_valid(state) || !membership_order(state) {
        membership_close(state, false)
        return
    }
    membership_place(state)
    focused := state.ui_runtime.semantic_focus.logical_focus
    if focused.domain == .Collection_Membership && focused.generation == menu.serial &&
        focused.stable_id != menu.focused {
        membership_focus(state, focused.stable_id)
    }
    _ = uisemantics.semantic_register_control(state.ui_runtime.semantic_focus, {
        id = membership_id(menu), role = .Panel, states = {.Visible, .Enabled},
        bounds = menu.bounds, clip_bounds = menu.bounds,
        label = viewmessages.shell_message(state, .Animation_Add_Collections),
    })
    for index in 0..<menu.count {
        membership_publish_row(state, index)
    }
}

// Draw accepted checkboxes and borrowed labels inside a scroll-clipped destination list.
membership_draw_row :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder, index: int) {
    menu := &state.ui_runtime.membership
    row := membership_row(menu, index)
    if row.y + row.height <= menu.clip.y || row.y >= menu.clip.y + menu.clip.height {
        return
    }
    head := &state.preferences_runtime.collections_state.collections[menu.order[index]]
    params := membership_checkbox(state, index, {})
    if head.id == menu.focused &&
        state.ui_runtime.semantic_focus.focus_origin == .Keyboard {
        uiwidgets.draw_encoded_focus_ring(encoder, row)
    }
    uiwidgets.draw_encoded_checkbox_geometry(encoder, params.rect, params.checked)
    label := row
    label.x += 28
    label.width -= 28
    context_menu_draw_label(state, encoder,
        string(head.name[:head.name_length]), label, params.enabled)
}

// Paint the popup after ordinary UI; labels never retain pointers across content reloads.
draw_encoded_membership :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    menu := &state.ui_runtime.membership
    if !menu.active {
        return
    }
    _ = uiwidgets.surface_shadow_draw(encoder, menu.bounds, .High)
    _ = native.draw_encoder_rectangle(
        encoder, menu.bounds, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, menu.bounds, 1, theme.UI_BORDER_COLOR)
    _ = native.draw_encoder_push_scissor(encoder, menu.bounds)
    context_menu_draw_label(state, encoder,
        viewmessages.shell_message(state, .Animation_Add_Collections), {
            menu.bounds.x + 8, menu.bounds.y + 4, menu.bounds.width - 16,
            menu.header_height - 8,
        }, true)
    _ = native.draw_encoder_push_scissor(encoder, menu.clip)
    for index in 0..<menu.count {
        membership_draw_row(state, encoder, index)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
    scrolling := uiwidgets.scroll_container_visual(menu.clip,
        f32(menu.count)*menu.row_height, menu.scroll_y, menu.row_height * 3)
    uiwidgets.draw_encoded_scrollbar(encoder, scrolling.scrollbar)
    _ = native.draw_encoder_pop_scissor(encoder)
}
