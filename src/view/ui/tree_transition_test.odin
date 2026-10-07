#+test
package ui

import "core:testing"
import "core:mem"
import bridgemodel "../../bridge/model"
import contentmodel "../../core/content"
import viewmodel "../model"

// tree_transition_fixture supplies two roots, a nested branch, and permanent identities.
tree_transition_fixture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface) -> Tree_List_Params {
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
    return {ji = ji, ui_runtime = runtime, scroll_y = &runtime^.tree_scroll_y,
        list_panel = {10, 20, 200, 200},
        mouse_input = {sample_time_seconds = 1, mouse_position = {-1, -1}},
        visibility = {search = &runtime^.library_search}}
}

// Verify exact duration, logical collapse, full-size rows, and static endpoint conservation.
@(test)
tree_transition_finishes_at_180_ms :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    initial := tree_prepare_layout(params)
    testing.expect_value(t, initial.content_height, TREE_ROW_HEIGHT * 6)
    nodes[0].is_expanded = false
    start := tree_prepare_layout(params)
    testing.expect_value(t, start.content_height, initial.content_height)
    testing.expect(t, !tree_layout_find(&start, &nodes[2])^.logical)
    previous := start.content_height
    samples := [5]f64{30, 60, 90, 120, 179}
    for milliseconds in samples {
        params.mouse_input.sample_time_seconds = 1 + milliseconds / 1000
        frame := tree_prepare_layout(params)
        testing.expect(t, frame.content_height <= previous)
        testing.expect(t, runtime.tree_motion.branches[0].running)
        bounds := tree_row_screen_geometry(frame.rows[0], params.list_panel, 0)
        testing.expect_value(t, bounds.bounds.height, TREE_ROW_HEIGHT)
        previous = frame.content_height
    }
    params.mouse_input.sample_time_seconds = 1 + INTERFACE_TRANSITION_SECONDS
    final := tree_prepare_layout(params)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect_value(t, final.count, 3)
    testing.expect_value(t, final.content_height, TREE_ROW_HEIGHT * 3)
    testing.expect_value(t,
        tree_layout_find(&final, &nodes[4])^.content_y, TREE_ROW_HEIGHT)
}

// Verify reversal samples the current height and duplicate intent never restarts its deadline.
@(test)
tree_transition_reverses_without_a_queue :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = tree_prepare_layout(params)
    nodes[0].is_expanded = false
    _ = tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.06
    before := tree_prepare_layout(params)
    nodes[0].is_expanded = true
    after := tree_prepare_layout(params)
    testing.expect_value(t, after.content_height, before.content_height)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1.06))
    params.mouse_input.sample_time_seconds = 1.09
    _ = tree_prepare_layout(params)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1.06))
    params.mouse_input.sample_time_seconds = 1.06 + INTERFACE_TRANSITION_SECONDS
    final := tree_prepare_layout(params)
    testing.expect_value(t, final.content_height, TREE_ROW_HEIGHT * 6)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
}

// Verify concurrent root/nested motion composes clips without extending ancestor deadlines.
@(test)
tree_transition_composes_concurrent_nested_branches :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = tree_prepare_layout(params)
    nodes[0].is_expanded = false
    nodes[4].is_expanded = false
    _ = tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.03
    _ = tree_prepare_layout(params)
    nodes[1].is_expanded = false
    frame := tree_prepare_layout(params)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    testing.expect(t, runtime.tree_motion.branches[1].running)
    testing.expect(t, runtime.tree_motion.branches[4].running)
    descendant := tree_layout_find(&frame, &nodes[2])
    ancestor := tree_layout_find(&frame, &nodes[1])
    testing.expect(t, descendant^.reveal.y >= ancestor^.reveal.y)
    testing.expect(t, descendant^.reveal.height <= ancestor^.reveal.height)
    params.mouse_input.sample_time_seconds = 1 + INTERFACE_TRANSITION_SECONDS
    _ = tree_prepare_layout(params)
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
    _ = prepare_tree_list_panel(params)
    nodes[0].is_expanded = false
    testing.expect(t, semantic_begin(semantic))
    _ = prepare_tree_list_panel(params)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_node_index(
        semantic_snapshot(semantic), tree_item_semantic_id(&nodes[2])), -1)
    params.mouse_input.sample_time_seconds = 1.06
    _ = prepare_tree_list_panel(params)
    nodes[0].is_expanded = true
    testing.expect(t, semantic_begin(semantic))
    prepared := prepare_tree_list_panel(params)
    testing.expect_value(t, semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    row := tree_layout_find(&prepared.layout, &nodes[3])
    expected := tree_row_screen_geometry(row^, params.list_panel, runtime.tree_scroll_y)
    snapshot := semantic_snapshot(semantic)
    index := semantic_node_index(snapshot, tree_item_semantic_id(&nodes[3]))
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
    nodes[0].is_expanded = false
    _ = tree_prepare_layout(params)
    nodes[0].is_expanded = true
    _ = tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.01
    layout := tree_prepare_layout(params)
    row := tree_layout_find(&layout, &nodes[1])
    runtime.ui_press_owner = {
        active = true, kind = .List_Item, id = tree_node_press_id(&nodes[1])}
    params.mouse_input.mouse_position = {
        params.list_panel.x + 30,
        params.list_panel.y + row^.content_y + TREE_ROW_HEIGHT - 1}
    params.mouse_input.mouse_released = {.Left}
    prepared := Tree_List_Preparation{layout = layout,
        scroll = scroll_container_visual(params.list_panel, layout.content_height, 0, 1)}
    hit := tree_update_prepared_rows(params, &prepared)
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
    nodes[0].is_expanded = false
    _ = prepare_tree_list_panel(params)
    nodes[0].is_expanded = true
    nodes[4].is_expanded = false
    _ = prepare_tree_list_panel(params)
    tree_set_active_node(&runtime, &nodes[2], true)
    prepared := prepare_tree_list_panel(params)
    testing.expect(t, !runtime.tree_motion.branches[0].running)
    testing.expect(t, runtime.tree_motion.branches[4].running)
    testing.expect(t,
        tree_row_is_revealed(tree_layout_find(&prepared.layout, &nodes[2])^))
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
        _ = tree_prepare_layout(params)
        nodes[0].is_expanded = !nodes[0].is_expanded
        _ = tree_prepare_layout(params)
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
        _ = tree_prepare_layout(params)
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
    params.list_panel.height = TREE_ROW_HEIGHT * 2
    layout := tree_prepare_layout(params)
    runtime.tree_scroll_y = TREE_ROW_HEIGHT * 3
    tree_motion_anchor(params, &nodes[4], &layout)
    nodes[0].is_expanded = false
    _ = tree_prepare_layout(params)
    params.mouse_input.sample_time_seconds = 1.09
    layout = tree_prepare_layout(params)
    tree_motion_apply_anchor(params, &layout)
    testing.expect_value(t, tree_layout_find(&layout, &nodes[4])^.content_y -
        runtime.tree_scroll_y, runtime.tree_motion.anchor_view_y)
    params.mouse_input.mouse_wheel_delta = -1
    tree_motion_apply_anchor(params, &layout)
    testing.expect(t, !runtime.tree_motion.anchored)
    params.mouse_input.sample_time_seconds = 1.18
    layout = tree_prepare_layout(params)
    prepared := Tree_List_Preparation{layout = layout}
    tree_refresh_preparation(params, &prepared)
    testing.expect(t, runtime.tree_scroll_y <= prepared.scroll.maximum)
    testing.expect_value(t, prepared.scroll.maximum, TREE_ROW_HEIGHT)
}

// Verify hidden Library preparation preserves user scroll and leaves no running branches.
@(test)
tree_transition_outgoing_preparation_is_noninteractive :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = tree_prepare_layout(params)
    nodes[0].is_expanded = false
    _ = tree_prepare_layout(params)
    runtime.tree_scroll_y = 400
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_wheel_delta = -10
    prepared := prepare_tree_visual(params)
    testing.expect_value(t, runtime.tree_scroll_y, f32(400))
    testing.expect_value(t, prepared.content_height, TREE_ROW_HEIGHT * 3)
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
        nodes[index].stable_id[0] = byte(index + 1)
        nodes[index].is_expanded = true
        if index + 1 < len(nodes) {
            nodes[index].first_child = &nodes[index + 1]
            nodes[index].next_in_registry = &nodes[index + 1]
            nodes[index + 1].parent = &nodes[index]
        }
    }
    params := Tree_List_Params{ji = &ji, ui_runtime = &runtime,
        list_panel = {0, 0, 200, 1000}, scroll_y = &runtime.tree_scroll_y}
    initial := tree_prepare_layout(params)
    testing.expect_value(t, initial.count, len(nodes))
    testing.expect_value(t, runtime.tree_motion.count, len(nodes))
    testing.expect_value(t, initial.content_height, f32(len(nodes)) * TREE_ROW_HEIGHT)
    nodes[0].is_expanded = false
    closing := tree_prepare_layout(params)
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
    nodes[0].is_expanded = false
    _ = prepare_tree_list_panel(params)
    params.mouse_input.mouse_position = {
        params.list_panel.x + TREE_ROW_ICON_OFFSET_X + 2,
        params.list_panel.y + TREE_ROW_ICON_OFFSET_Y + 2}
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_down = {.Left}
    _ = prepare_tree_list_panel(params)
    testing.expect(t, runtime.ui_press_owner.active)
    params.mouse_input.mouse_pressed = {}
    params.mouse_input.mouse_down = {}
    params.mouse_input.mouse_released = {.Left}
    prepared := prepare_tree_list_panel(params)
    testing.expect(t, nodes[0].is_expanded)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    testing.expect(t, !runtime.ui_press_owner.active)
    testing.expect_value(t, prepared.content_height, TREE_ROW_HEIGHT * 3)
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
    nodes[0].is_expanded = false
    _ = prepare_tree_list_panel(params)
    semantic^.commands[0] = {
        target = tree_item_semantic_id(&nodes[0]), kind = .Expand}
    semantic^.command_count = 1
    _ = prepare_tree_list_panel(params)
    testing.expect(t, runtime.tree_motion.branches[0].running)
    params.mouse_input.sample_time_seconds = 1.05
    _ = prepare_tree_list_panel(params)
    testing.expect_value(t, runtime.tree_motion.branches[0].start_seconds, f64(1))
    runtime.library_search.active = true
    runtime.library_search.visible_ids[0] = nodes[0].stable_id
    runtime.library_search.visible_ids[1] = nodes[1].stable_id
    runtime.library_search.visible_id_count = 2
    _ = prepare_tree_list_panel(params)
    semantic^.commands[0].kind = .Collapse
    _ = prepare_tree_list_panel(params)
    testing.expect(t, !nodes[0].is_expanded)
    testing.expect(t, tree_node_is_effectively_expanded(params.visibility, &nodes[0]))
    testing.expect(t, !runtime.tree_motion.branches[0].running)
}

// Verify reduced-motion collapse releases a held descendant even when no tail row remains.
@(test)
tree_transition_snap_cancels_removed_row_capture :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    _ = prepare_tree_list_panel(params)
    runtime.ui_press_owner = {
        active = true, kind = .List_Item, id = tree_node_press_id(&nodes[2])}
    runtime.settings_preferences.interface.reduce_motion = true
    nodes[0].is_expanded = false
    _ = prepare_tree_list_panel(params)
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
            nodes[0].is_expanded = !nodes[0].is_expanded
        }
        if frame % 5 == 0 {
            nodes[4].is_expanded = !nodes[4].is_expanded
        }
        _ = prepare_tree_list_panel(params)
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
    nodes[0].is_expanded = false
    runtime.library_search.active = true
    runtime.library_search.visible_ids[0] = nodes[0].stable_id
    runtime.library_search.visible_ids[1] = nodes[1].stable_id
    runtime.library_search.visible_id_count = 2
    prepared := tree_prepare_layout(params)
    testing.expect(t, prepared.rows[0].expanded)
    runtime.library_search.active = false
    testing.expect(t, prepared.rows[0].expanded)
    next_frame := tree_prepare_layout(params)
    testing.expect(t, !next_frame.rows[0].expanded)
}
