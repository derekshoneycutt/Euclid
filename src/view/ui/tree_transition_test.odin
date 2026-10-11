#+test
package ui

import viewmodel "model"
import testing "core:testing"
import mem "core:mem"
import bridgemodel "../../bridge/model"
import contentmodel "../../core/content"
import theme "theme"
import uisemantics "semantics"
import uiwidgets "widgets"
import uilibrary "library"
import uiaccordion "layout/accordion"

// tree_transition_fixture supplies two roots, a nested branch, and permanent identities.
tree_transition_fixture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface) -> uilibrary.Tree_List_Params {
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes)
    ji^.selected_animation = &nodes[0]
    for index in 0..<len(nodes) {
        nodes[index].stable_id[0] = byte(index + 1)
        nodes[index].name = "branch"
        if index + 1 < len(nodes) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }
    }
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], &nodes[2], &nodes[3], true)
    seed_tree_node(&nodes[2], &nodes[1], nil, nil, false)
    seed_tree_node(&nodes[3], &nodes[0], nil, nil, false)
    seed_tree_node(&nodes[4], nil, &nodes[5], nil, true)
    seed_tree_node(&nodes[5], &nodes[4], nil, nil, false)
    params := uilibrary.Tree_List_Params{
        ji = ji, ui_runtime = runtime, scroll_y = &runtime^.tree_scroll_y,
        list_panel = {10, 20, 200, 200},
        mouse_input = {sample_time_seconds = 1, mouse_position = {-1, -1}},
        visibility = {search = &runtime^.library_search},
    }
    assert(uilibrary.tree_projection_prepare(params))
    for node in nodes {
        index := uilibrary.tree_projection_find(
            &runtime^.tree_projection, node.stable_id)
        runtime^.tree_projection.items[index].expanded = node.is_expanded
    }
    return params
}

// Set one test placement's display-owned expansion state.
tree_transition_set_expanded :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    expanded: bool) {
    index := uilibrary.tree_projection_find(
        &runtime^.tree_projection, node^.stable_id)
    assert(index != uilibrary.TREE_NO_ITEM)
    runtime^.tree_projection.items[index].expanded = expanded
}

// Verify exact duration, logical collapse, full-size rows, and static endpoint conservation.
@(test)
tree_transition_finishes_at_180_ms :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    initial := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, initial.content_height, theme.TREE_ROW_HEIGHT * 6)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    start := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, start.content_height, initial.content_height)
    testing.expect(t, !uilibrary.tree_layout_find(&start, &nodes[2])^.logical)
    previous := start.content_height
    samples := [5]f64{30, 60, 90, 120, 179}
    for milliseconds in samples {
        params.mouse_input.sample_time_seconds = 1 + milliseconds / 1000
        frame := uilibrary.tree_prepare_layout(params)
        testing.expect(t, frame.content_height <= previous)
        testing.expect(t, runtime.tree_motion.branches[0].running)
        bounds := uilibrary.tree_row_screen_geometry(frame.rows[0], params.list_panel, 0)
        testing.expect_value(t, bounds.bounds.height, theme.TREE_ROW_HEIGHT)
        previous = frame.content_height
    }
    params.mouse_input.sample_time_seconds = 1 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    final := uilibrary.tree_prepare_layout(params)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect_value(t, final.count, 3)
    testing.expect_value(t, final.content_height, theme.TREE_ROW_HEIGHT * 3)
    testing.expect_value(t,
        uilibrary.tree_layout_find(&final, &nodes[4])^.content_y, theme.TREE_ROW_HEIGHT)
}

// Verify reversal samples the current height and duplicate intent never restarts its deadline.
@(test)
tree_transition_reverses_without_a_queue :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.06
    before := uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    after := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, after.content_height, before.content_height)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1.06))
    params.mouse_input.sample_time_seconds = 1.09
    _ = uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1.06))
    params.mouse_input.sample_time_seconds =
        1.06 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    final := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, final.content_height, theme.TREE_ROW_HEIGHT * 6)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
}

// Verify concurrent root/nested motion composes clips without extending ancestor deadlines.
@(test)
tree_transition_composes_concurrent_nested_branches :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    tree_transition_set_expanded(&runtime, &nodes[4], false)
    _ = uilibrary.tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.03
    _ = uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[1], false)
    frame := uilibrary.tree_prepare_layout(params)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    testing.expect(t, runtime.tree_motion.branches[1].running)
    testing.expect(t, runtime.tree_motion.branches[4].running)
    descendant := uilibrary.tree_layout_find(&frame, &nodes[2])
    ancestor := uilibrary.tree_layout_find(&frame, &nodes[1])
    testing.expect(t, descendant^.reveal.y >= ancestor^.reveal.y)
    testing.expect(t, descendant^.reveal.height <= ancestor^.reveal.height)
    params.mouse_input.sample_time_seconds = 1 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    _ = uilibrary.tree_prepare_layout(params)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect(t, runtime.tree_motion.branches[1].running)
    testing.expect_value(t, runtime.tree_motion.branches[0].height, f32(0))
}

// Verify logical semantics excludes closing tails while incoming bounds share visual clipping.
@(test)
tree_transition_semantics_share_prepared_clips :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = uilibrary.prepare_tree_list_panel(params)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    _ = uilibrary.prepare_tree_list_panel(params)
    testing.expect_value(t,
        uisemantics.semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t,
        uisemantics.semantic_node_index(
            uisemantics.semantic_snapshot(semantic),
            uilibrary.tree_item_semantic_id(&nodes[2])),
        -1)
    params.mouse_input.sample_time_seconds = 1.06
    _ = uilibrary.prepare_tree_list_panel(params)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    prepared := uilibrary.prepare_tree_list_panel(params)
    testing.expect_value(t,
        uisemantics.semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    row := uilibrary.tree_layout_find(&prepared.layout, &nodes[3])
    expected := uilibrary.tree_row_screen_geometry(row^,
        params.list_panel, runtime.tree_scroll_y)
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot,
        uilibrary.tree_item_semantic_id(&nodes[3]))
    testing.expect_value(t, snapshot^.nodes[index].bounds, expected.bounds)
    testing.expect_value(t, snapshot^.nodes[index].clip_bounds, expected.clip_bounds)
    testing.expect(t, .Visible not_in snapshot^.nodes[index].states)
    testing.expect_value(t,
        snapshot^.nodes[index].actions, viewmodel.Ui_Node_Action_Set{})
}

// Verify releases outside reveal cancel capture even when still inside the full-size row.
@(test)
tree_transition_hidden_release_cannot_activate :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    _ = uilibrary.tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.01
    layout := uilibrary.tree_prepare_layout(params)
    row := uilibrary.tree_layout_find(&layout, &nodes[1])
    runtime.ui_press_owner = {
        active = true, kind = .List_Item,
        id = uilibrary.tree_placement_press_id(row^.item)}
    params.mouse_input.mouse_position = {
        params.list_panel.x + 30,
        params.list_panel.y + row^.content_y + theme.TREE_ROW_HEIGHT - 1}
    params.mouse_input.mouse_released = {.Left}
    prepared := uilibrary.Tree_List_Preparation{
        layout = layout,
        scroll = uiwidgets.scroll_container_visual(params.list_panel,
            layout.content_height, 0, 1),
    }
    hit := uilibrary.tree_update_prepared_rows(params, &prepared)
    testing.expect_value(t, hit.selected_node, nil)
    testing.expect(t, !runtime.ui_press_owner.active)
}

// Verify required keyboard reveal settles ancestors, not an unrelated closing root.
@(test)
tree_transition_keyboard_reveal_finishes_required_path :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.prepare_tree_list_panel(params)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    tree_transition_set_expanded(&runtime, &nodes[4], false)
    _ = uilibrary.prepare_tree_list_panel(params)
    uilibrary.tree_set_active_node(&runtime, &nodes[2], true)
    prepared := uilibrary.prepare_tree_list_panel(params)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect(t, runtime.tree_motion.branches[4].running)
    testing.expect(t,
        uilibrary.tree_row_is_revealed(
            uilibrary.tree_layout_find(&prepared.layout, &nodes[2])^))
    testing.expect(t, !runtime.tree_reveal_pending)
}

// Verify search, external reveal, generation, viewport, and reduced-motion boundaries snap.
@(test)
tree_transition_invalidations_snap :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    for trigger in 0..<7 {
        runtime.tree_reveal_pending = false
        runtime.settings_preferences.interface.reduce_motion = false
        runtime.platform_reduce_motion = false
        _ = uilibrary.tree_prepare_layout(params)
        item_index := uilibrary.tree_projection_find(
            &runtime.tree_projection, nodes[0].stable_id)
        tree_transition_set_expanded(
            &runtime, &nodes[0], !runtime.tree_projection.items[item_index].expanded)
        _ = uilibrary.tree_prepare_layout(params)
        testing.expect(t, runtime.tree_motion.branches[0].running)
        switch trigger {
        case 0: runtime.library_search.query_revision += 1
        case 1: runtime.library_search.committed_generation += 1
        case 2: ji.content_generation += 1
        case 3: params.list_panel.width += 1
        case 4: runtime.settings_preferences.interface.reduce_motion = true
        case 5: runtime.platform_reduce_motion = true
        case 6:
            runtime.tree_reveal_pending = true
            runtime.tree_reveal_reason = .Programmatic
        }
        _ = uilibrary.tree_prepare_layout(params)
        testing.expect(t, !runtime.tree_motion.branches[0].running)
    }
}

// Verify anchoring is bounded and yields to user wheel input before content moves.
@(test)
tree_transition_scroll_anchor_respects_input_and_clamp :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    params.list_panel.height = theme.TREE_ROW_HEIGHT * 2
    layout := uilibrary.tree_prepare_layout(params)
    runtime.tree_scroll_y = theme.TREE_ROW_HEIGHT * 3
    item := uilibrary.tree_layout_find(&layout, &nodes[4])^.item
    uilibrary.tree_motion_anchor(params, item, &layout)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.09
    layout = uilibrary.tree_prepare_layout(params)
    uilibrary.tree_motion_apply_anchor(params, &layout)
    testing.expect_value(t, uilibrary.tree_layout_find(&layout, &nodes[4])^.content_y -
        runtime.tree_scroll_y, runtime.tree_motion.anchor_view_y)
    params.mouse_input.mouse_wheel_delta = -1
    uilibrary.tree_motion_apply_anchor(params, &layout)
    testing.expect(t, !runtime.tree_motion.anchored)
    params.mouse_input.sample_time_seconds = 1.18
    layout = uilibrary.tree_prepare_layout(params)
    prepared := uilibrary.Tree_List_Preparation{layout = layout}
    uilibrary.tree_refresh_preparation(params, &prepared)
    testing.expect(t, runtime.tree_scroll_y <= prepared.scroll.maximum)
    testing.expect_value(t, prepared.scroll.maximum, theme.TREE_ROW_HEIGHT)
}

// Verify hidden Library preparation preserves user scroll and leaves no running branches.
@(test)
tree_transition_outgoing_preparation_is_noninteractive :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = uilibrary.tree_prepare_layout(params)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.tree_prepare_layout(params)
    runtime.tree_scroll_y = 400
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_wheel_delta = -10
    prepared := uilibrary.prepare_tree_visual(params)
    testing.expect_value(t, runtime.tree_scroll_y, f32(400))
    testing.expect_value(t, prepared.content_height, theme.TREE_ROW_HEIGHT * 3)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect_value(t, prepared.hovered_node, nil)
    testing.expect(t, nodes[1].is_expanded)
}

// Verify deepest admitted trees use fixed storage and inherit clips without extra native depth.
@(test)
tree_transition_covers_full_catalogue_capacity :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    CAPACITY :: contentmodel.CATALOG_RECORD_CAPACITY
    nodes: [CAPACITY]bridgemodel.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    for index in 0..<len(nodes) {
        stable_index := index + 1
        nodes[index].stable_id[0] = byte(stable_index)
        nodes[index].stable_id[1] = byte(stable_index >> 8)
        nodes[index].is_expanded = true
        if index + 1 < len(nodes) {
            nodes[index].first_child = &nodes[index + 1]
            nodes[index].next_in_registry = &nodes[index + 1]
            nodes[index + 1].parent = &nodes[index]
        }
    }
    params := uilibrary.Tree_List_Params{ji = &ji, ui_runtime = &runtime,
        list_panel = {0, 0, 200, 1000}, scroll_y = &runtime.tree_scroll_y}
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    for index in 0..<len(nodes) {
        tree_transition_set_expanded(&runtime, &nodes[index], true)
    }
    initial := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, initial.count, len(nodes))
    testing.expect_value(t, runtime.tree_motion.count, len(nodes))
    testing.expect_value(t,
        initial.content_height, f32(len(nodes)) * theme.TREE_ROW_HEIGHT)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    closing := uilibrary.tree_prepare_layout(params)
    testing.expect_value(t, closing.count, len(nodes))
    testing.expect(t, !closing.rows[len(nodes) - 1].logical)
    testing.expect_value(t, closing.rows[len(nodes) - 1].depth, len(nodes) - 1)
}

// Verify real pointer press/release toggles admit motion through the ordinary row owner.
@(test)
tree_transition_pointer_toggle_uses_prepared_row :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.prepare_tree_list_panel(params)
    params.mouse_input.mouse_position = {
        params.list_panel.x + theme.TREE_ROW_ICON_OFFSET_X + 2,
        params.list_panel.y + theme.TREE_ROW_ICON_OFFSET_Y + 2}
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_down = {.Left}
    _ = uilibrary.prepare_tree_list_panel(params)
    testing.expect(t, runtime.ui_press_owner.active)
    params.mouse_input.mouse_pressed = {}
    params.mouse_input.mouse_down = {}
    params.mouse_input.mouse_released = {.Left}
    prepared := uilibrary.prepare_tree_list_panel(params)
    item_index := uilibrary.tree_projection_find(
        &runtime.tree_projection, nodes[0].stable_id)
    testing.expect(t, runtime.tree_projection.items[item_index].expanded)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    testing.expect(t, !runtime.ui_press_owner.active)
    testing.expect_value(t, prepared.content_height, theme.TREE_ROW_HEIGHT * 3)
    testing.expect_value(t, ji.selected_animation, &nodes[0])
}

// Verify addressed accessibility expansion animates and search-forced no-ops do not.
@(test)
tree_transition_addressed_expansion_and_search_policy :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.prepare_tree_list_panel(params)
    semantic^.commands[0] = {
        target = uilibrary.tree_item_semantic_id(&nodes[0]), kind = .Expand}
    semantic^.command_count = 1
    _ = uilibrary.prepare_tree_list_panel(params)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    params.mouse_input.sample_time_seconds = 1.05
    _ = uilibrary.prepare_tree_list_panel(params)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1))
    runtime.library_search.active = true
    runtime.library_search.visible_ids[0] = nodes[0].stable_id
    runtime.library_search.visible_ids[1] = nodes[1].stable_id
    runtime.library_search.visible_id_count = 2
    _ = uilibrary.prepare_tree_list_panel(params)
    semantic^.commands[0].kind = .Collapse
    _ = uilibrary.prepare_tree_list_panel(params)
    item_index := uilibrary.tree_projection_find(
        &runtime.tree_projection, nodes[0].stable_id)
    testing.expect(t, !runtime.tree_projection.items[item_index].expanded)
    testing.expect(t,
        uilibrary.tree_node_is_effectively_expanded(params.visibility, &nodes[0]))
    testing.expect(t, !runtime.tree_motion.branches[0].running)
}

// Verify reduced-motion collapse releases a held descendant even when no tail row remains.
@(test)
tree_transition_snap_cancels_removed_row_capture :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = uilibrary.prepare_tree_list_panel(params)
    runtime.ui_press_owner = {
        active = true, kind = .List_Item,
        id = uilibrary.tree_placement_press_id(
            &runtime.tree_projection.items[
                uilibrary.tree_projection_find(&runtime.tree_projection,
                    nodes[2].stable_id)])}
    runtime.settings_preferences.interface.reduce_motion = true
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    _ = uilibrary.prepare_tree_list_panel(params)
    testing.expect(t, !runtime.ui_press_owner.active)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
}

// Verify rapid concurrent preparation uses bounded stack/model storage, not context allocations.
@(test)
tree_transition_preparation_does_not_allocate :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    previous_allocator := context.allocator
    context.allocator = mem.tracking_allocator(&tracker)
    defer context.allocator = previous_allocator
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    for frame in 0..<40 {
        params.mouse_input.sample_time_seconds = 1 + f64(frame) / 100
        if frame % 4 == 0 {
            index := uilibrary.tree_projection_find(
                &runtime.tree_projection, nodes[0].stable_id)
            tree_transition_set_expanded(
                &runtime, &nodes[0], !runtime.tree_projection.items[index].expanded)
        }
        if frame % 5 == 0 {
            index := uilibrary.tree_projection_find(
                &runtime.tree_projection, nodes[4].stable_id)
            tree_transition_set_expanded(
                &runtime, &nodes[4], !runtime.tree_projection.items[index].expanded)
        }
        _ = uilibrary.prepare_tree_list_panel(params)
    }
    testing.expect_value(t, tracker.total_allocation_count, i64(0))
}

// Verify late search publication cannot change the disclosure facts of an already prepared frame.
@(test)
tree_transition_prepared_disclosure_is_frozen :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    runtime.library_search.active = true
    runtime.library_search.visible_ids[0] = nodes[0].stable_id
    runtime.library_search.visible_ids[1] = nodes[1].stable_id
    runtime.library_search.visible_id_count = 2
    prepared := uilibrary.tree_prepare_layout(params)
    testing.expect(t, prepared.rows[0].expanded)
    runtime.library_search.active = false
    testing.expect(t, prepared.rows[0].expanded)
    next_frame := uilibrary.tree_prepare_layout(params)
    testing.expect(t, !next_frame.rows[0].expanded)
}
