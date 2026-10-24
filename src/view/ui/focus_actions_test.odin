#+test
package ui

import input "../input"
import testing "core:testing"
import viewmodel "model"
import uisemantics "semantics"
import uilibrary "library"
import bridgemodel "../../bridge/model"
import geometry "../../core/geometry"
import collections "../../collections"
import uuid "core:encoding/uuid"
import uiwidgets "widgets"

// Verify selecting another placement flushes exact text and preserves its owned draft.
@(test)
library_entry_name_selection_flush_preserves_exact_text :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    entry_id := state^.ui_runtime.library.tree.selected_item_id
    name := "Compare these"
    testing.expect(t, uilibrary.library_entry_name_begin(
        state, entry_id, "Animation"))
    testing.expect(t, uilibrary.library_entry_name_edit(state, entry_id, name))

    other_id := uuid.Identifier{}
    other_id[0] = 90
    other_index := uilibrary.tree_projection_find(
        &state^.ui_runtime.library.tree.projection, other_id)
    testing.expect(t, other_index != uilibrary.TREE_NO_ITEM)
    if other_index == uilibrary.TREE_NO_ITEM {
        return
    }
    uilibrary.tree_select_item(
        params, state^.ui_runtime.library.tree.projection.items[other_index])

    entry_index := collections.find_entry(
        params.collections, entry_id)
    draft := &state^.ui_runtime.library.entry_name
    testing.expect(t, entry_index >= 0)
    if entry_index < 0 {
        return
    }
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id,
        state^.ui_runtime.library.tree.projection.items[other_index].key)
    testing.expect_value(t,
        string(params.collections^.entries[entry_index].custom_name[
            :params.collections^.entries[entry_index].custom_name_length]), name)
    testing.expect_value(t, string(draft^.value[:draft^.value_length]), name)
    testing.expect_value(t,
        string(draft^.accepted_name[:draft^.accepted_name_length]), name)
}

// Complete the trailing TeX command without exceeding the name's byte capacity.
library_entry_name_test_complete_unicode_name :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params,
    selected: uuid.Identifier, expected: []u8) -> int {
    state := params.general_state
    prefix_length := collections.ENTRY_NAME_MAX_BYTES - len("\\alpha")
    prefill: [collections.ENTRY_NAME_MAX_BYTES]u8
    for index in 0..<prefix_length {
        prefill[index] = 'x'
    }
    copy(prefill[prefix_length:], "\\alpha")
    testing.expect(t, uilibrary.library_entry_name_begin(
        state, selected, string(prefill[:])))

    edit_events := [2]input.Input_Event{
        {kind = .Press, key = .End}, {kind = .Press, key = .Right}}
    rect := geometry.Rectangle{0, 0, 320, 30}
    input_params := uilibrary.library_entry_name_input_params(
        params, selected, rect, rect, {events = edit_events[:]})
    input_params.focused = true
    testing.expect(t, input_params.edit_policy.unicode_completion)
    testing.expect(t, uiwidgets.input_box_unicode_enabled(input_params))
    draft := &state^.ui_runtime.library.entry_name
    prepared := uiwidgets.input_box_apply_edit_keyboard(
        input_params.state, input_params.edit_target, input_params.frame,
        "", input_params.edit_policy)
    copy(expected[:prefix_length], prefill[:prefix_length])
    copy(expected[prefix_length:], "α")
    expected_length := prefix_length + len("α")
    testing.expect(t, prepared.changed)
    testing.expect_value(t, string(draft^.value[:draft^.value_length]),
        string(expected[:expected_length]))
    testing.expect(t, uilibrary.library_entry_name_edit(
        state, selected, string(draft^.value[:draft^.value_length])))
    testing.expect(t, draft^.dirty)
    return expected_length
}

// Verify the Library editor completes and saves a name at its UTF-8 byte limit.
@(test)
library_entry_name_unicode_completion_saves_within_byte_limit :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.library.tree.selected_item_id
    expected: [collections.ENTRY_NAME_MAX_BYTES]u8
    expected_length := library_entry_name_test_complete_unicode_name(
        t, params, selected, expected[:])
    rect := geometry.Rectangle{0, 0, 320, 30}
    enter := [1]input.Input_Event{{kind = .Press, key = .Enter}}
    input_params := uilibrary.library_entry_name_input_params(
        params, selected, rect, rect, {events = enter[:]})
    prepared := uiwidgets.input_box_apply_edit_keyboard(
        input_params.state, input_params.edit_target, input_params.frame,
        "", input_params.edit_policy)
    testing.expect(t, prepared.submit_requested)
    testing.expect(t, uilibrary.library_entry_name_flush(state, selected))
    entry_index := collections.find_entry(params.collections, selected)
    testing.expect(t, entry_index >= 0)
    if entry_index < 0 {
        return
    }
    entry := params.collections^.entries[entry_index]
    testing.expect_value(t, string(entry.custom_name[:entry.custom_name_length]),
        string(expected[:expected_length]))
    testing.expect_value(t, entry.custom_name_length, expected_length)
}

// Verify tree activity stays separate from selection while actions follow the tree stop.
@(test)
semantic_favorites_actions_tab_activation_and_escape :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    toggle := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    tree_actions_test_key(t, &params, .Down)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Enter)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus.local_id,
        uilibrary.TREE_ENTRY_NAME_INPUT)
    tree_actions_test_key(t, &params, .Tab, true)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus.local_id,
        uilibrary.TREE_ENTRY_NAME_INPUT)
    tree_actions_test_key(t, &params, .Escape)
    testing.expect(t, !state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Space)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
}

// Verify the inline editor publishes placement semantics and owns pointer focus.
@(test)
semantic_favorites_name_editor_pointer_focus_and_identity :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    prepared := tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    row := tree_actions_test_row(&prepared.layout, selected)
    prepared = tree_actions_test_semantic_click(t, &params,
        uilibrary.tree_actions_screen_rect(
            row^.actions.toggle_rect, params.list_panel, 0))
    testing.expect(t, prepared.entry_name_prepared)
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)

    editor_id := uilibrary.tree_actions_semantic_id(
        params, selected, uilibrary.TREE_ENTRY_NAME_INPUT)
    tree_actions_test_expect_name_editor_semantics(t, params, selected, editor_id)

    state^.ui_runtime.input.interaction_frame.pointer_target =
        viewmodel.ui_interaction_target(.Control, .Input_Box,
            uilibrary.TREE_ENTRY_NAME_INPUT_ID)
    _ = tree_actions_test_semantic_click(t, &params,
        prepared.entry_name_input.control_geometry.bounds)
    testing.expect_value(t, semantic^.logical_focus, editor_id)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

// Keyboard editor focus maps placement-qualified semantics to the actual input widget.
@(test)
semantic_favorites_name_editor_keyboard_focus_routes_to_widget :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    prepared := tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    row := tree_actions_test_row(&prepared.layout, selected)
    _ = tree_actions_test_semantic_click(t, &params,
        uilibrary.tree_actions_screen_rect(
            row^.actions.toggle_rect, params.list_panel, 0))
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(
        params, selected, uilibrary.TREE_ENTRY_NAME_INPUT)
    ui_apply_semantic_focus(
        &state^.ui_runtime, {window_focused = true}, false)
    expected := viewmodel.Ui_Focus_Target{
        kind = .Input_Box, id = uilibrary.TREE_ENTRY_NAME_INPUT_ID,
    }
    testing.expect_value(t, state^.ui_runtime.input.interaction.logical_focus, expected)
    testing.expect_value(t,
        state^.ui_runtime.input.interaction_frame.effective_focus, expected)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)
}

// Verify the editable field and its text run have stable parentage and actions.
tree_actions_test_expect_name_editor_semantics :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params,
    selected: uuid.Identifier, editor_id: viewmodel.Ui_Node_Id) {
    text_id := editor_id
    text_id.local_id = uilibrary.TREE_ENTRY_NAME_TEXT_RUN
    snapshot := uisemantics.semantic_snapshot(params.ui_runtime^.semantic_focus)
    editor_index := uisemantics.semantic_node_index(snapshot, editor_id)
    text_index := uisemantics.semantic_node_index(snapshot, text_id)
    testing.expect(t, editor_index >= 0 && text_index >= 0)
    if editor_index < 0 || text_index < 0 {
        return
    }
    editor := snapshot^.nodes[editor_index]
    text := snapshot^.nodes[text_index]
    drawer_id := uilibrary.tree_actions_semantic_id(
        params, selected, uilibrary.TREE_ACTION_DRAWER)
    testing.expect_value(t, editor.role, viewmodel.Ui_Node_Role.Input)
    testing.expect_value(t, editor.parent, drawer_id)
    testing.expect_value(t, text.role, viewmodel.Ui_Node_Role.Text_Run)
    testing.expect_value(t, text.parent, editor_id)
    testing.expect(t, .Tab_Stop in editor.states && .Enabled in editor.states)
}

// Verify interior moves retain action focus and an endpoint returns focus to disclosure.
@(test)
semantic_favorites_actions_move_focus_and_boundary :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Space)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus.local_id,
        uilibrary.TREE_ENTRY_NAME_INPUT)
    tree_actions_test_key(t, &params, .Enter)
    testing.expect_value(t, semantic^.logical_focus.local_id,
        uilibrary.TREE_ENTRY_NAME_INPUT)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    tree_actions_test_key(t, &params, .Tab)
    tree_actions_test_key(t, &params, .Tab)
    down := semantic^.logical_focus
    tree_actions_test_key(t, &params, .Enter)
    testing.expect_value(t, semantic^.logical_focus, down)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    tree_actions_test_key(t, &params, .Space)
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)
}

// Verify Escape is not globally claimed and context retirement does not steal new focus.
@(test)
semantic_favorites_actions_context_focus_repair :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    events := [1]input.Input_Event{{kind = .Press, key = .Escape}}
    claims := uisemantics.semantic_route_keyboard(semantic, {events = events[:]})
    testing.expect(t, !claims.claimed[0])
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Enter)
    state^.ui_runtime.library.search.active = true
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, semantic^.logical_focus, uilibrary.tree_semantic_id())
    state^.ui_runtime.library.search.active = false
    _ = tree_actions_test_semantic_frame(t, &params)
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Enter)
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    state^.ui_runtime.library.tree.selected_item_id = nodes[0].stable_id
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, semantic^.logical_focus, uilibrary.tree_semantic_id())
}

// Verify pointer disclosure owns focus without falling through to tree selection.
@(test)
semantic_favorites_pointer_focus_and_visible_drawer_tail :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.library.tree.selected_item_id
    prepared := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, selected)
    prepared = tree_actions_test_semantic_click(t, &params,
        uilibrary.tree_actions_screen_rect(
            row^.actions.toggle_rect, params.list_panel, 0))
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect_value(t,
        semantic^.logical_focus.domain, viewmodel.Ui_Node_Domain.Library_Action)
    testing.expect_value(t, semantic^.focus_origin, viewmodel.Ui_Focus_Origin.Pointer)
    row = tree_actions_test_row(&prepared.layout, selected)
    params.list_panel.height = 36
    params.scroll_y^ = row^.actions.move_down_rect.y - 4
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    state^.ui_runtime.library.actions.reveal_pending = false
    prepared = tree_actions_test_semantic_frame(t, &params)
    row = tree_actions_test_row(&prepared.layout, selected)
    bounds := uilibrary.tree_actions_screen_rect(row^.actions.move_down_rect,
        params.list_panel, prepared.scroll.scroll_y_out)
    testing.expect(t, geometry.rectangles_intersect(bounds, params.list_panel))
    _ = tree_actions_test_semantic_click(t, &params, bounds)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected)
    testing.expect_value(t, semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_DOWN)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(2))
}

// Verify addressed focus reveals an action after resizing without undoing ordinary scrolling.
@(test)
semantic_favorites_actions_reveal_and_scroll_clipping :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.library.tree.selected_item_id
    uilibrary.tree_actions_toggle(params, selected)
    _ = tree_actions_test_semantic_frame(t, &params)
    down := uilibrary.tree_actions_semantic_id(
        params, selected, uilibrary.TREE_ACTION_DOWN)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, down, .Focus))
    params.list_panel.height = 36
    prepared := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, selected)
    bounds := uilibrary.tree_actions_screen_rect(row^.actions.move_down_rect,
        params.list_panel, prepared.scroll.scroll_y_out)
    testing.expect(t, bounds.y >= params.list_panel.y)
    testing.expect(t,
        bounds.y + bounds.height <= params.list_panel.y + params.list_panel.height)
    params.scroll_y^ = 0
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, params.scroll_y^, f32(0))
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
    snapshot := uisemantics.semantic_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, down)]
    testing.expect(t, .Tab_Stop not_in node.states && .Enabled not_in node.states)
    testing.expect(t,
        !uisemantics.semantic_apply_external_action(semantic, down, .Activate))
}
