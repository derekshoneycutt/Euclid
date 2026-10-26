#+test
package ui

import collections "../../collections"
import bridgemodel "../../bridge/model"
import core "../../core"
import uuid "core:encoding/uuid"
import testing "core:testing"
import log "core:log"
import uioverlay "overlay"
import uianimation "animation"
import uisemantics "semantics"
import viewmodel "model"
import viewpreferences "../preferences"
import input "../input"
import userdata "../../userdata"

// Append a real durable destination through ordinary transactional display admission.
membership_test_head :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, number: u8) -> uuid.Identifier {
    id: uuid.Identifier
    id[0], id[15] = 91, number
    mutation, policy := collections.make_collection_create_mutation(
        &state.preferences_runtime.collections_state, id, "Duplicate destination")
    testing.expect_value(t, policy, collections.Policy_Error.None)
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(state, mutation),
        collections.Mutation_Error.None)
    return id
}

// Bind ordinary collection and semantic owners without a Julia/native runtime.
membership_test_fixture :: proc(t: ^testing.T, state: ^core.Euclid_General_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface) {
    _ = tree_collections_fixture(t, state, ji, nodes)
    state.julia_interface = ji
    ji.selected_animation = &nodes[1]
    state.ui_runtime.layout.ui_regions.world_rect = {0, 0, 640, 480}
}

// Pointer opening stays visually quiet; keyboard navigation restores visible row focus.
@(test)
membership_popup_preserves_focus_modality :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    _ = membership_test_head(t, state, 1)
    focus := state.ui_runtime.semantic_focus
    focus.focus_origin = .Pointer
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    testing.expect_value(t, focus.focus_origin, viewmodel.Ui_Focus_Origin.Pointer)
    uioverlay.membership_key(state, {
        kind = .Press,
        key = .Down,
    })
    testing.expect_value(t, focus.focus_origin, viewmodel.Ui_Focus_Origin.Keyboard)
    row := uioverlay.membership_row(&state.ui_runtime.membership, 0)
    uioverlay.membership_pointer(state, {
        window_focused = true,
        mouse_position = {row.x + 50, row.y + row.height * 0.5},
        mouse_pressed = {.Left},
        mouse_down = {.Left},
    })
    testing.expect_value(t, focus.focus_origin, viewmodel.Ui_Focus_Origin.Pointer)
    uioverlay.membership_close(state, true)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    testing.expect_value(t, focus.focus_origin, viewmodel.Ui_Focus_Origin.Keyboard)
}

// Opening preserves duplicate-name identities, empty destinations, Library order and star parity.
@(test)
membership_popup_uses_custom_heads_and_retains_accepted_membership :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    testing.expect(t, !uioverlay.membership_available(state))
    first := membership_test_head(t, state, 1)
    second := membership_test_head(t, state, 2)
    slots := uianimation.animation_control_layout_slots({0, 0, 640, 480}, true, true)
    testing.expect(t, uioverlay.membership_open(state, slots.membership))
    menu := &state.ui_runtime.membership
    testing.expect_value(t, menu.count, 2)
    testing.expect_value(t, menu.focused, first)
    uioverlay.membership_request(state, second)
    uioverlay.membership_commit(state)
    set := &state.preferences_runtime.collections_state
    identity, policy := collections.collection_animation_identity(
        set, second, nodes[1].stable_id)
    testing.expect_value(t, policy, collections.Policy_Error.None)
    testing.expect_value(t, identity.collection_id, second)
    testing.expect(t, menu.active)
    _, policy = collections.collection_animation_identity(set, first, nodes[1].stable_id)
    testing.expect_value(t, policy, collections.Policy_Error.Not_In_Collection)
    testing.expect_value(t, set.entry_count, 1)
    uioverlay.membership_request(state, first)
    uioverlay.membership_commit(state)
    testing.expect_value(t, set.entry_count, 2)
    testing.expect(t, menu.active)
}

// Rejected queue admission never turns a checkbox on, and retry remains ordinary input.
@(test)
membership_popup_rejection_does_not_publish_optimistic_checks :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    id := membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    store: userdata.Store
    state.preferences_runtime.settings_store = &store
    defer state.preferences_runtime.settings_store = nil
    state.preferences_runtime.collection_mutation_count = collections.MUTATION_CAPACITY
    uioverlay.membership_request(state, id)
    previous_logger := context.logger
    context.logger = log.nil_logger()
    uioverlay.membership_commit(state)
    context.logger = previous_logger
    testing.expect(t, !uioverlay.membership_checkbox(state, 0, {}).checked)
    state.preferences_runtime.collection_mutation_count = 0
    uioverlay.membership_request(state, id)
    uioverlay.membership_commit(state)
    testing.expect(t, uioverlay.membership_checkbox(state, 0, {}).checked)
}

// Real checkbox pointer release and UUID-qualified native toggle preserve independent values.
@(test)
membership_popup_pointer_and_semantic_routes_share_accepted_checkboxes :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    id := membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    row := uioverlay.membership_row(&state.ui_runtime.membership, 0)
    point: input.Input_Position = {row.x + 50, row.y + row.height*0.5}
    storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    routed := uioverlay.membership_route(state, {
        window_focused = true,
        mouse_position = point,
        mouse_pressed = {.Left},
        mouse_down = {.Left},
    }, storage[:])
    testing.expect_value(t, card(routed.mouse_pressed), 0)
    _ = uioverlay.membership_route(state, {
        window_focused = true,
        mouse_position = point,
        mouse_released = {.Left},
    }, storage[:])
    uioverlay.membership_commit(state)
    testing.expect(t, uioverlay.membership_checkbox(state, 0, {}).checked)
    membership_test_native_toggle(t, state, id)
}

// Verify native publication exposes accepted state before issuing its qualified toggle.
membership_test_native_toggle :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, id: uuid.Identifier) {
    testing.expect(t, uisemantics.semantic_begin(state.ui_runtime.semantic_focus))
    _ = uianimation.prepare_animation_controls(state, {})
    uioverlay.membership_prepare(state)
    testing.expect_value(t,
        uisemantics.semantic_publish(state.ui_runtime.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(state.ui_runtime.semantic_focus)
    index := viewmodel.ui_semantic_snapshot_find(snapshot,
        uioverlay.membership_id(&state.ui_runtime.membership, id))
    testing.expect(t, index >= 0)
    if index < 0 {
        return
    }
    testing.expect_value(t, snapshot.nodes[index].role, viewmodel.Ui_Node_Role.Checkbox)
    testing.expect(t, .Checked in snapshot.nodes[index].states)
    state.semantic_focus.commands[0] = {
        kind = .Toggle,
        target = snapshot.nodes[index].id,
    }
    state.semantic_focus.command_count = 1
    uioverlay.membership_commands(state)
    uioverlay.membership_commit(state)
    testing.expect(t, !uioverlay.membership_checkbox(state, 0, {}).checked)
}

// Unbounded destinations use reusable capacity and keyboard reveal rather than a fixed menu array.
@(test)
membership_popup_scrolls_and_reuses_workspace :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    last: uuid.Identifier
    for index in 1..=40 {
        last = membership_test_head(t, state, u8(index))
    }
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    menu := &state.ui_runtime.membership
    address := raw_data(menu.order)
    uioverlay.membership_key(state, {
        kind = .Press,
        key = .End,
    })
    testing.expect_value(t, menu.focused, last)
    testing.expect(t, menu.scroll_y > 0)
    row := uioverlay.membership_row(menu, menu.count - 1)
    testing.expect(t, row.y + row.height <= menu.clip.y + menu.clip.height)
    testing.expect(t, uioverlay.membership_order(state))
    testing.expect_value(t, raw_data(menu.order), address)
    uioverlay.membership_close(state, true)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    testing.expect_value(t, raw_data(menu.order), address)
}

// A pending action is not silently retargeted by selection, reload, layout or recording.
@(test)
membership_popup_invalidates_opening_context :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    id := membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    uioverlay.membership_request(state, id)
    ji.selected_animation = &nodes[2]
    uioverlay.membership_commit(state)
    testing.expect_value(t, state.preferences_runtime.collections_state.entry_count, 0)
    uioverlay.membership_prepare(state)
    testing.expect(t, !state.ui_runtime.membership.active)
    for reason in 0..<3 {
        testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
        if reason == 0 {
            ji.content_generation += 1
        }
        if reason == 1 {
            state.ui_runtime.layout.ui_regions.world_rect.width += 1
        }
        if reason == 2 {
            state.gif_capture_status.gif_capture_phase = .Recording
        }
        uioverlay.membership_prepare(state)
        testing.expect(t, !state.ui_runtime.membership.active)
    }
}

// Escape consumes its correlated input and restores the opening trigger; held Space never repeats.
@(test)
membership_popup_keyboard_dismissal_and_held_activation :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    _ = membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    uioverlay.membership_key(state, {
        kind = .Press,
        key = .Space,
    })
    uioverlay.membership_commit(state)
    uioverlay.membership_key(state, {
        kind = .Repeat,
        key = .Space,
    })
    testing.expect(t, !state.ui_runtime.membership.pending_valid)
    uioverlay.membership_key(state, {
        kind = .Press,
        key = .Escape,
    })
    testing.expect(t, !state.ui_runtime.membership.active)
    testing.expect_value(t, state.semantic_focus.logical_focus,
        uisemantics.semantic_control_id(
            .Animation_Control, uioverlay.MEMBERSHIP_CONTROL_ID))
}

// A held Space captures its correlated repeat text, not unrelated text for the next editor.
@(test)
membership_popup_dismissal_preserves_unrelated_text :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    _ = membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    uioverlay.membership_key(state, {
        kind = .Press,
        key = .Space,
    })
    uioverlay.membership_close(state, true)
    events: [4]input.Input_Event = {
        {
            kind = .Text,
            codepoint = 'T',
        },
        {
            kind = .Repeat,
            key = .Space,
            correlation = {
                partner_index = 2,
                valid = true,
            },
        },
        {
            kind = .Text,
            codepoint = ' ',
            correlation = {
                partner_index = 1,
                valid = true,
            },
        },
        {
            kind = .Release,
            key = .Space,
        },
    }
    storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    routed := uioverlay.membership_route(state, {
        window_focused = true,
        events = events[:],
    }, storage[:])
    testing.expect_value(t, len(routed.events), 1)
    if len(routed.events) == 1 {
        testing.expect_value(t, routed.events[0].codepoint, rune('T'))
    }
    testing.expect_value(t, state.ui_runtime.membership.swallowed_keys, u8(0))
}

// Focus loss dismisses; an outside press remains available to the newly clicked ordinary target.
@(test)
membership_popup_focus_loss_and_outside_press_dismiss :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    _ = membership_test_head(t, state, 1)
    storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    _ = uioverlay.membership_route(state, {
        window_focused = true,
    }, storage[:])
    testing.expect(t, state.ui_runtime.membership.active)
    _ = uioverlay.membership_route(state, {
        window_focused = false,
    }, storage[:])
    testing.expect(t, !state.ui_runtime.membership.active)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    routed := uioverlay.membership_route(state, {
        window_focused = true,
        mouse_position = {-1, -1},
        mouse_pressed = {.Left},
        mouse_down = {.Left},
    }, storage[:])
    testing.expect(t, !state.ui_runtime.membership.active)
    testing.expect(t, .Left in routed.mouse_pressed)
}

// Opening serials prevent a retired native checkbox from modifying a newly opened popup.
@(test)
membership_popup_rejects_retired_native_identity :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    id := membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    stale := uioverlay.membership_id(&state.ui_runtime.membership, id)
    uioverlay.membership_close(state, true)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    state.semantic_focus.commands[0] = {
        kind = .Toggle,
        target = stale,
    }
    state.semantic_focus.command_count = 1
    uioverlay.membership_commands(state)
    uioverlay.membership_prepare(state)
    testing.expect(t, !state.ui_runtime.membership.pending_valid)
    testing.expect(t, !uioverlay.membership_checkbox(state, 0, {}).checked)
}

// A destination becoming read-only disables its checkbox without hiding accepted membership.
@(test)
membership_popup_revalidates_writable_destination :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    membership_test_fixture(t, state, &ji, &nodes)
    id := membership_test_head(t, state, 1)
    testing.expect(t, uioverlay.membership_open(state, {580, 430, 30, 30}))
    uioverlay.membership_request(state, id)
    uioverlay.membership_commit(state)
    set := &state.preferences_runtime.collections_state
    set.collections[collections.find_collection(set, id)].is_read_only = true
    params := uioverlay.membership_checkbox(state, 0, {})
    testing.expect(t, params.checked)
    testing.expect(t, !params.enabled)
}
