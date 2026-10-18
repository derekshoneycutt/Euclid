#+test
package ui

import core "../../core"
import bridgemodel "../../bridge/model"
import collections "../../collections"
import geometry "../../core/geometry"
import input "../input"
import native "../native"
import testing "core:testing"
import uuid "core:encoding/uuid"
import viewmodel "model"
import uilibrary "library"
import theme "theme"
import uiaccordion "layout/accordion"
import uisemantics "semantics"

// tree_actions_test_registry links three canonical animations with the middle one selected.
tree_actions_test_registry :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface) {
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes^)
    ji^.content_generation = 1
    for index in 0..<len(nodes^) {
        nodes[index].stable_id[0] = byte(index + 1)
        nodes[index].name = "Animation"
        nodes[index].node_kind = .Animation
        nodes[index].is_selected = index == 1
        if index + 1 < len(nodes^) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }

    }
    ji^.selected_animation = &nodes[1]
}

// tree_actions_test_semantic_frame commits one ordinary prepared frame and consumes commands.
tree_actions_test_semantic_frame :: proc(
    t: ^testing.T,
    params: ^uilibrary.Tree_List_Params) -> uilibrary.Tree_List_Preparation {
    params^.collections_revision =
        params^.general_state^.preferences_runtime.collection_revision
    testing.expect(t, uisemantics.semantic_begin(params^.ui_runtime^.semantic_focus))
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params^, &prepared)
    testing.expect_value(t,
        uisemantics.semantic_publish(params^.ui_runtime^.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    params^.ui_runtime^.semantic_focus^.command_count = 0
    return prepared
}

// tree_actions_test_key routes one real key event before preparing its owner frame.
tree_actions_test_key :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    key: input.Input_Key, shift: bool = false) {
    events := [1]input.Input_Event{{kind = .Press, key = key}}
    if shift {
        events[0].modifiers = {.Shift}
    }
    claims := uisemantics.semantic_route_keyboard(params^.ui_runtime^.semantic_focus,
        {events = events[:], window_focused = true})
    focus := params^.ui_runtime^.semantic_focus^.logical_focus
    if focus.domain != .Library_Action ||
        focus.local_id != uilibrary.TREE_ENTRY_NAME_INPUT {
        testing.expect(t, claims.claimed[0])
    }
    _ = tree_actions_test_semantic_frame(t, params)
}

// tree_actions_test_semantic_click commits pointer press and release through ordinary owners.
tree_actions_test_semantic_click :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    bounds: geometry.Rectangle) -> uilibrary.Tree_List_Preparation {
    params^.mouse_input.mouse_position = {
        bounds.x + bounds.width * 0.5, bounds.y + bounds.height * 0.5}
    params^.mouse_input.mouse_pressed = {.Left}
    params^.mouse_input.mouse_released = {}
    params^.mouse_input.mouse_down = {.Left}
    _ = tree_actions_test_semantic_frame(t, params)
    params^.mouse_input.mouse_pressed = {}
    params^.mouse_input.mouse_released = {.Left}
    params^.mouse_input.mouse_down = {}
    return tree_actions_test_semantic_frame(t, params)
}

// tree_actions_test_fixture creates three shuffled Favorites and a selected middle row.
tree_actions_test_fixture :: proc(
    state: ^core.Euclid_General_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface) ->
        uilibrary.Tree_List_Params {
    tree_actions_test_registry(ji, nodes)
    set := &state^.preferences_runtime.collections_state
    collections.initialize(set)
    for index in 0..<len(nodes^) {
        entry_id := uuid.Identifier{}
        entry_id[0] = byte(90 + index)
        assert(collections.favorites_add(
            set, entry_id, nodes[index].stable_id) == .None)
    }
    set^.entries[0].sibling_order = 30
    set^.entries[1].sibling_order = 10
    set^.entries[2].sibling_order = 20
    state^.preferences_runtime.collection_revision = 1
    state^.ui_runtime.layout.active_accordion_section = .Library
    state^.ui_runtime.platform_reduce_motion = true
    state^.ui_runtime.library.tree.selected_item_id = set^.entries[1].id
    params := uilibrary.Tree_List_Params{
        general_state = state, ji = ji, collections = set,
        collections_revision = 1, ui_runtime = &state^.ui_runtime,
        list_panel = {10, 20, 220, 180},
        scroll_y = &state^.ui_runtime.library.tree.scroll_y,
        mouse_input = {sample_time_seconds = 1, mouse_position = {-1, -1}},
        visibility = {search = &state^.ui_runtime.library.search},
        reduce_motion = state^.ui_runtime.preferences.values.interface.reduce_motion ||
            state^.ui_runtime.platform_reduce_motion,
    }
    assert(uilibrary.tree_projection_prepare(params))
    tree_actions_test_expand_favorites(params)
    return params
}

// tree_actions_test_expand_favorites exposes both retained collection ancestors.
tree_actions_test_expand_favorites :: proc(params: uilibrary.Tree_List_Params) {
    runtime := params.ui_runtime
    root := uilibrary.tree_projection_find(
        &runtime^.library.tree.projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        &runtime^.library.tree.projection, collections.FAVORITES_COLLECTION_ID)
    runtime^.library.tree.projection.items[root].expanded = true
    runtime^.library.tree.projection.items[favorites].expanded = true
}

// tree_actions_test_row finds a prepared row by stable placement identity.
tree_actions_test_row :: proc(
    layout: ^viewmodel.Ui_Tree_Prepared_Layout, key: uuid.Identifier) ->
        ^viewmodel.Ui_Tree_Prepared_Row {
    for index in 0..<layout^.count {
        if layout^.rows[index].item^.key == key {
            return &layout^.rows[index]
        }
    }
    return nil
}

// tree_actions_test_click drives one ordinary press/release pair through tree preparation.
tree_actions_test_click :: proc(
    params: ^uilibrary.Tree_List_Params,
    position: input.Input_Position) -> uilibrary.Tree_List_Preparation {
    prepared: uilibrary.Tree_List_Preparation
    params^.mouse_input.sample_time_seconds += 0.01
    params^.mouse_input.mouse_position = position
    params^.mouse_input.mouse_pressed = {.Left}
    params^.mouse_input.mouse_released = {}
    params^.mouse_input.mouse_down = {.Left}
    uilibrary.prepare_tree_list_panel(params^, &prepared)
    params^.mouse_input.sample_time_seconds += 0.01
    params^.mouse_input.mouse_pressed = {}
    params^.mouse_input.mouse_released = {.Left}
    params^.mouse_input.mouse_down = {}
    uilibrary.prepare_tree_list_panel(params^, &prepared)
    return prepared
}

// tree_actions_test_click_move drives a prepared move control and refreshes its revision.
tree_actions_test_click_move :: proc(
    params: ^uilibrary.Tree_List_Params, prepared: ^uilibrary.Tree_List_Preparation,
    direction: collections.Move_Direction) -> uilibrary.Tree_List_Preparation {
    params^.collections_revision =
        params^.general_state^.preferences_runtime.collection_revision
    row := tree_actions_test_row(&prepared^.layout,
        params^.ui_runtime^.library.tree.selected_item_id)
    rect := row^.actions.move_up_rect if direction == .Up else
        row^.actions.move_down_rect
    bounds := uilibrary.tree_actions_screen_rect(
        rect, params^.list_panel, prepared^.scroll.scroll_y_out)
    result := tree_actions_test_click(params, {
        bounds.x + bounds.width * 0.5, bounds.y + bounds.height * 0.5})
    params^.collections_revision =
        params^.general_state^.preferences_runtime.collection_revision
    return result
}

// tree_actions_test_open_drawer verifies disclosure geometry and preserved selection.
tree_actions_test_open_drawer :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params) ->
        uilibrary.Tree_List_Preparation {
    selected_id := params^.ui_runtime^.library.tree.selected_item_id
    selected := params^.ji^.selected_animation
    initial: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params^, &initial)
    row := tree_actions_test_row(&initial.layout, selected_id)
    testing.expect(t, row != nil && row^.actions.eligible)
    testing.expect(t, !params^.ui_runtime^.library.actions.drawer.open)
    initial_height := initial.layout.content_height

    toggle := uilibrary.tree_actions_screen_rect(
        row^.actions.toggle_rect, params^.list_panel, 0)
    open := tree_actions_test_click(params, {
        toggle.x + toggle.width * 0.5, toggle.y + toggle.height * 0.5})
    testing.expect(t, params^.ui_runtime^.library.actions.drawer.open)
    testing.expect_value(
        t, params^.ui_runtime^.library.tree.selected_item_id, selected_id)
    testing.expect_value(t, params^.ji^.selected_animation, selected)

    row = tree_actions_test_row(&open.layout, selected_id)
    testing.expect(t, row^.actions.open)
    testing.expect_value(t, row^.actions.height,
        uilibrary.TREE_ACTION_BUTTON_HEIGHT * 2 +
            uilibrary.TREE_ACTION_BUTTON_GAP + uilibrary.TREE_ACTION_DRAWER_PADDING * 2)
    testing.expect_value(t, open.layout.content_height,
        initial_height + row^.actions.height)
    return open
}

// tree_actions_test_expect_order checks authoritative sibling enumeration after a move.
tree_actions_test_expect_order :: proc(
    t: ^testing.T, set: ^collections.Set) {
    ordered_indexes: [collections.ENTRY_INDEX_BUFFER_CAPACITY]int
    count, failure := collections.ordered_siblings(
        set, collections.FAVORITES_COLLECTION_ID, {}, ordered_indexes[:])
    testing.expect_value(t, failure, collections.Policy_Error.None)
    testing.expect_value(t, count, 3)
    testing.expect_value(t, set^.entries[ordered_indexes[0]].id[0], u8(92))
    testing.expect_value(t, set^.entries[ordered_indexes[1]].id[0], u8(91))
    testing.expect_value(t, set^.entries[ordered_indexes[2]].id[0], u8(90))
}

// Verify disclosure and repeated pointer moves preserve placement and playback identity.
@(test)
tree_actions_toggle_and_reorder_through_shared_tree_pipeline :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected_id := state^.ui_runtime.library.tree.selected_item_id
    selected := ji.selected_animation
    open := tree_actions_test_open_drawer(t, &params)
    moved := tree_actions_test_click_move(&params, &open, .Down)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected_id)
    testing.expect_value(t, ji.selected_animation, selected)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)

    tree_actions_test_expect_order(t, params.collections)
    row := tree_actions_test_row(&moved.layout, selected_id)
    testing.expect(t, row != nil && row^.actions.open)
    testing.expect_value(t, row^.actions.move_up_enabled, true)
    testing.expect_value(t, row^.actions.move_down_enabled, true)
    testing.expect_value(t, ji.selected_animation, selected)

    moved = tree_actions_test_click_move(&params, &moved, .Down)
    row = tree_actions_test_row(&moved.layout, selected_id)
    testing.expect(t, !row^.actions.move_down_enabled)
    moved = tree_actions_test_click_move(&params, &moved, .Up)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, selected_id)
    testing.expect_value(t, ji.selected_animation, selected)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)

    tree_actions_test_expect_order(t, params.collections)
    params.mouse_input.mouse_wheel_delta = 1
    uilibrary.prepare_tree_list_panel(params, &moved)
    testing.expect(t, state^.ui_runtime.library.actions.drawer.open)
}

// Verify drawer motion shares disclosure timing and disables controls on the closing tail.
@(test)
tree_actions_motion_uses_disclosure_policy_without_closing_actions :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    state^.ui_runtime.platform_reduce_motion = false
    params.reduce_motion = false
    owner := state^.ui_runtime.library.tree.selected_item_id
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params, &prepared)
    uilibrary.tree_actions_toggle(params, owner)
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    row := tree_actions_test_row(&prepared.layout, owner)
    testing.expect_value(t, row^.actions.height, f32(0))
    testing.expect(t, state^.ui_runtime.library.actions.drawer.running)

    tree_actions_test_advance_motion(&params, 0.5, &prepared.layout)
    row = tree_actions_test_row(&prepared.layout, owner)
    testing.expect(t, row^.actions.height > 0)
    testing.expect(t, row^.actions.height < uilibrary.TREE_ACTION_BUTTON_HEIGHT * 2 +
        uilibrary.TREE_ACTION_BUTTON_GAP + uilibrary.TREE_ACTION_DRAWER_PADDING * 2)

    tree_actions_test_advance_motion(&params, 0.5, &prepared.layout)
    row = tree_actions_test_row(&prepared.layout, owner)
    testing.expect(t, row^.actions.open)
    uilibrary.tree_actions_toggle(params, owner)
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    row = tree_actions_test_row(&prepared.layout, owner)
    testing.expect(t, !row^.actions.open && row^.actions.height > 0)
    tree_actions_test_closing_controls(t, &params, row)

    tree_actions_test_advance_motion(&params, 1, &prepared.layout)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})
}

// tree_actions_test_advance_motion samples layout after a fraction of disclosure duration.
tree_actions_test_advance_motion :: proc(
    params: ^uilibrary.Tree_List_Params,
    fraction: f64,
    layout: ^viewmodel.Ui_Tree_Prepared_Layout) {
    params^.mouse_input.sample_time_seconds +=
        uiaccordion.INTERFACE_TRANSITION_SECONDS * fraction
    uilibrary.tree_prepare_layout(params^, layout)
}

// tree_actions_test_closing_controls verifies the visible closing tail cannot issue moves.
tree_actions_test_closing_controls :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    row: ^viewmodel.Ui_Tree_Prepared_Row) {
    hit: uilibrary.Tree_Hit
    params^.mouse_input.mouse_position = {
        params^.list_panel.x + row^.actions.move_down_rect.x + 4,
        params^.list_panel.y + row^.actions.move_down_rect.y + 4,
    }
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.tree_actions_prepare_controls(
        params^, row, &prepared,
        {panel = params^.list_panel, allow_clicks = true}, &hit)
    testing.expect_value(t, hit.actions_move_id, uuid.Identifier{})
}

// Verify responsive geometry, endpoint disabling, and clipping use prepared drawer bounds.
@(test)
tree_actions_geometry_stacks_and_clips_disabled_endpoints :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    first_id := params.collections^.entries[1].id
    last_id := params.collections^.entries[0].id
    state^.ui_runtime.library.tree.selected_item_id = first_id
    uilibrary.tree_actions_toggle(params, first_id)
    params.list_panel.width = 220
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    row := tree_actions_test_row(&layout, first_id)
    testing.expect(t, row^.actions.open)
    testing.expect(t, row^.actions.move_up_rect.y < row^.actions.move_down_rect.y)
    testing.expect(t, !row^.actions.move_up_enabled)
    testing.expect(t, row^.actions.move_down_enabled)

    state^.ui_runtime.library.tree.selected_item_id = last_id
    uilibrary.tree_actions_toggle(params, last_id)
    uilibrary.tree_prepare_layout(params, &layout)
    row = tree_actions_test_row(&layout, last_id)
    testing.expect(t, !row^.actions.move_down_enabled)
    testing.expect(t, row^.actions.move_up_enabled)

    params.list_panel.height = 50
    clip := uilibrary.tree_actions_screen_clip(
        row^, params.list_panel, row^.content_y + theme.TREE_ROW_HEIGHT - 4)
    testing.expect_value(t, clip.height, f32(46))
    testing.expect(t, geometry.rectangles_intersect(clip, params.list_panel))
}

// Verify removing both neighbors leaves a singleton with both endpoints disabled.
@(test)
tree_actions_geometry_disables_singleton_endpoints :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    first_id := params.collections^.entries[1].id
    last_id := params.collections^.entries[0].id
    testing.expect_value(t, collections.favorites_remove(
        params.collections, first_id), collections.Policy_Error.None)
    testing.expect_value(t, collections.favorites_remove(
        params.collections, last_id), collections.Policy_Error.None)
    state^.preferences_runtime.collection_revision += 1
    params.collections_revision = state^.preferences_runtime.collection_revision
    uilibrary.tree_actions_close_context(&state^.ui_runtime)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    middle_id := params.collections^.entries[0].id
    state^.ui_runtime.library.tree.selected_item_id = middle_id
    uilibrary.tree_actions_toggle(params, middle_id)
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    row := tree_actions_test_row(&layout, middle_id)
    testing.expect(t, !row^.actions.move_up_enabled)
    testing.expect(t, !row^.actions.move_down_enabled)
}

// Verify selection, search, ancestor collapse, and panel exit close the drawer.
@(test)
tree_actions_close_when_owner_context_changes :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    owner := state^.ui_runtime.library.tree.selected_item_id

    uilibrary.tree_actions_toggle(params, owner)
    state^.ui_runtime.library.tree.selected_item_id = params.collections^.entries[2].id
    uilibrary.tree_actions_reconcile(params)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})

    state^.ui_runtime.library.tree.selected_item_id = owner
    uilibrary.tree_actions_toggle(params, owner)
    favorites := uilibrary.tree_projection_find(
        &state^.ui_runtime.library.tree.projection, collections.FAVORITES_COLLECTION_ID)
    state^.ui_runtime.library.tree.projection.items[favorites].expanded = false
    uilibrary.tree_actions_reconcile(params)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})

    state^.ui_runtime.library.tree.projection.items[favorites].expanded = true
    uilibrary.tree_actions_toggle(params, owner)
    params.visibility.search^.active = true
    uilibrary.tree_actions_reconcile(params)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})

    params.visibility.search^.active = false
    uilibrary.tree_actions_toggle(params, owner)
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_visual(params, &prepared)
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})
}

// Verify removal and generation reload discard stale drawer ownership.
@(test)
tree_actions_close_when_owner_removed_or_content_reloaded :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    owner := state^.ui_runtime.library.tree.selected_item_id
    uilibrary.tree_actions_toggle(params, owner)
    testing.expect_value(t, collections.favorites_remove(
        params.collections, owner), collections.Policy_Error.None)
    state^.preferences_runtime.collection_revision += 1
    params.collections_revision = state^.preferences_runtime.collection_revision
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})

    remaining := params.collections^.entries[0].id
    state^.ui_runtime.library.tree.selected_item_id = remaining
    uilibrary.tree_actions_toggle(params, remaining)
    ji.content_generation += 1
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, state^.ui_runtime.library.actions.drawer.entry_id,
        uuid.Identifier{})
}

// Verify the drawer extends the whole selected row behind two borderless button fills.
@(test)
tree_actions_draw_geometry_balances_clips :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    state^.julia_interface = &ji
    owner := state^.ui_runtime.library.tree.selected_item_id
    prepared := tree_actions_test_open_drawer(t, &params)
    row := tree_actions_test_row(&prepared.layout, owner)
    drawer := uilibrary.tree_actions_screen_rect(
        row^.actions.drawer_rect, params.list_panel, prepared.scroll.scroll_y_out)

    vertices: [1024]native.Draw_Vertex
    indices: [2048]u32
    batches: [256]native.Draw_Batch
    commands: [256]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {800, 800}, {800, 800}))
    uilibrary.draw_tree_actions_drawer_surfaces(
        {encoder = &encoder, panel = params.list_panel,
            scroll_y = prepared.scroll.scroll_y_out}, row^)
    testing.expect_value(t, encoder.scissor_count, 1)
    testing.expect_value(t, encoder.statistics.scissor_overflows, u32(0))
    testing.expect_value(t, encoder.statistics.command_overflows, u32(0))
    testing.expect_value(t, drawer.x, params.list_panel.x)
    testing.expect_value(t, drawer.width, params.list_panel.width)
    testing.expect_value(t, encoder.vertex_count, 12)
    testing.expect_value(t, vertices[0].position, (geometry.Vector2{drawer.x, drawer.y}))
    testing.expect_value(t,
        vertices[1].position.x, params.list_panel.x + params.list_panel.width)
    for vertex in vertices[:4] {
        testing.expect_value(t, vertex.color, theme.UI_BORDER_COLOR)
    }
}

// Verify resting and disabled buttons remain visible, with borderless enabled hover feedback.
@(test)
tree_actions_button_surface_is_borderless_feedback :: proc(t: ^testing.T) {
    vertices: [32]native.Draw_Vertex
    indices: [48]u32
    batches: [8]native.Draw_Batch
    commands: [8]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {800, 800}, {800, 800}))
    rect := geometry.Rectangle{10, 20, 80, 24}
    uilibrary.draw_tree_actions_button_surface(&encoder, rect, {}, true)
    for vertex in vertices[:4] {
        testing.expect_value(t, vertex.color, theme.UI_COMPONENT_BACKGROUND_COLOR)
    }
    uilibrary.draw_tree_actions_button_surface(&encoder, rect, {hovered = true}, false)
    testing.expect_value(t, encoder.vertex_count, 8)
    disabled := theme.UI_COMPONENT_BACKGROUND_COLOR
    disabled.a = 150
    for vertex in vertices[4:8] {
        testing.expect_value(t, vertex.color, disabled)
    }
    uilibrary.draw_tree_actions_button_surface(&encoder, rect, {hovered = true}, true)
    testing.expect_value(t, encoder.vertex_count, 16)
    highlight := theme.UI_TEXT_COLOR
    highlight.a = 24
    for vertex in vertices[12:16] {
        testing.expect_value(t, vertex.color, highlight)
    }
}

// Verify open ellipsis inversion leaves the collapsed dots and hover treatment unchanged.
@(test)
tree_actions_toggle_inverts_only_while_open :: proc(t: ^testing.T) {
    vertices: [512]native.Draw_Vertex
    indices: [1024]u32
    batches: [8]native.Draw_Batch
    commands: [8]native.Draw_Command
    encoder: native.Draw_Encoder
    rect := geometry.Rectangle{10, 20, 22, theme.TREE_ROW_HEIGHT}
    for open in ([2]bool{false, true}) {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {800, 800}, {800, 800}))
        uilibrary.draw_tree_actions_toggle(&encoder, rect, {}, open)
        dot_start := 0
        dot_color := theme.UI_TEXT_COLOR
        if open {
            dot_start = 4
            dot_color = theme.UI_BORDER_COLOR
            for vertex in vertices[:4] {
                testing.expect_value(t, vertex.color, theme.UI_TEXT_COLOR)
            }
        }
        testing.expect(t, encoder.vertex_count > dot_start)
        for vertex in vertices[dot_start:encoder.vertex_count] {
            testing.expect_value(t, vertex.color, dot_color)
        }
    }
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {800, 800}, {800, 800}))
    uilibrary.draw_tree_actions_toggle(&encoder, rect, {hovered = true}, false)
    highlight := theme.UI_TEXT_COLOR
    highlight.a = 24
    testing.expect_value(t, vertices[0].color, highlight)
}
