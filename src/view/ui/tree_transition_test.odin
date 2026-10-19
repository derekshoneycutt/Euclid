#+test
package ui

import viewmodel "model"
import testing "core:testing"
import mem "core:mem"
import geometry "../../core/geometry"
import bridgemodel "../../bridge/model"
import contentmodel "../../core/content"
import theme "theme"
import uisemantics "semantics"
import uiwidgets "widgets"
import uilibrary "library"
import uiaccordion "layout/accordion"
import storage "../../core/storage"

// Tree_Transition_Components retains only the bounded state used by tree geometry.
Tree_Transition_Components :: struct {
    tree: viewmodel.Ui_Library_Tree_State,
    motion: viewmodel.Ui_Tree_Motion,
    actions: viewmodel.Ui_Library_Actions_State,
    search: viewmodel.Library_Search_State,
}

// Tree_Transition_Geometry binds component fixtures to the geometry-only API.
Tree_Transition_Geometry :: struct {
    geometry: uilibrary.Tree_Geometry_Context,
    admission: uilibrary.Tree_Motion_Admission,
}

// Seed the stable IDs, registry links, and nested topology shared by geometry tests.
tree_transition_geometry_seed_nodes :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface) {
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes)
    ji^.content_generation = 1
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
}

// Build a valid committed projection from the seeded geometry topology.
tree_transition_geometry_seed_projection :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface) {
    assert(viewmodel.ui_tree_projection_init(projection))
    projection^.first_root = uilibrary.TREE_NO_ITEM
    projection^.last_root = uilibrary.TREE_NO_ITEM
    projection^.content_generation = 1
    projection^.topology_revision = 1
    projection^.valid = true
    previous: viewmodel.Ui_Tree_Projection
    for node in nodes {
        parent := uilibrary.TREE_NO_ITEM
        if node.parent != nil {
            parent = uilibrary.tree_projection_find(projection, node.parent^.stable_id)
        }
        assert(uilibrary.tree_projection_add(projection, &previous, {
            key = node.stable_id,
            target_id = node.stable_id,
            kind = .Animation,
            parent = parent,
            expanded = node.is_expanded,
            selectable = true,
        }) != uilibrary.TREE_NO_ITEM)
    }
}

// Prepare narrow geometry dependencies without constructing the application runtime.
tree_transition_geometry_fixture :: proc(
    state: ^Tree_Transition_Components,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface,
    panel: geometry.Rectangle) -> Tree_Transition_Geometry {
    tree_transition_geometry_seed_nodes(ji, nodes)
    projection := &state^.tree.projection
    tree_transition_geometry_seed_projection(projection, nodes)
    visibility := uilibrary.Tree_Visibility_Policy{
        search = &state^.search,
        projection = projection,
    }
    geometry_context := uilibrary.Tree_Geometry_Context{
        ji = ji,
        projection = projection,
        motion = &state^.motion,
        drawer = &state^.actions.drawer,
        search_active = false,
        visibility = visibility,
        panel = panel,
        row_height = theme.TREE_ROW_HEIGHT,
        now_seconds = 1,
    }
    return {
        geometry = geometry_context,
        admission = {
            generation = ji^.content_generation,
            topology_revision = projection^.topology_revision,
            count = projection^.count,
            panel = panel,
            row_height = geometry_context.row_height,
        },
    }
}

// Change the component fixture's logical expansion without requiring a full runtime.
tree_transition_set_component_expanded :: proc(
    state: ^Tree_Transition_Components,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    expanded: bool) {
    index := uilibrary.tree_projection_find(&state^.tree.projection, node^.stable_id)
    assert(index != uilibrary.TREE_NO_ITEM)
    state^.tree.projection.items[index].expanded = expanded
}

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
        ji = ji, ui_runtime = runtime, scroll_y = &runtime^.library.tree.scroll_y,
        list_panel = {10, 20, 200, 200},
        mouse_input = {sample_time_seconds = 1, mouse_position = {-1, -1}},
        visibility = {search = &runtime^.library.search},
        reduce_motion = runtime^.preferences.values.interface.reduce_motion ||
            runtime^.platform_reduce_motion,
    }
    assert(uilibrary.tree_projection_prepare(params))
    for node in nodes {
        index := uilibrary.tree_projection_find(
            &runtime^.library.tree.projection, node.stable_id)
        runtime^.library.tree.projection.items[index].expanded = node.is_expanded
    }
    return params
}

// Set one test placement's display-owned expansion state.
tree_transition_set_expanded :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    node: ^bridgemodel.Euclid_Julia_Animation_Interface,
    expanded: bool) {
    index := uilibrary.tree_projection_find(
        &runtime^.library.tree.projection, node^.stable_id)
    assert(index != uilibrary.TREE_NO_ITEM)
    runtime^.library.tree.projection.items[index].expanded = expanded
}

// Verify closing motion reaches zero at the shared disclosure deadline.
@(test)
tree_branch_closes_at_deadline :: proc(t: ^testing.T) {
    branch := viewmodel.Ui_Tree_Branch_Motion{
        expanded = false,
        running = true,
        start_seconds = 1,
        start_height = 80,
        height = 80,
    }
    uilibrary.tree_motion_sample_branch(
        &branch, 80, 1 + uiaccordion.INTERFACE_TRANSITION_SECONDS)
    testing.expect_value(t, branch.height, f32(0))
    testing.expect(t, !branch.running)
}

// Verify exact duration, logical collapse, full-size rows, and static endpoint conservation.
@(test)
tree_transition_finishes_at_180_ms :: proc(t: ^testing.T) {
    state: Tree_Transition_Components
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    frame := tree_transition_geometry_fixture(
        &state, &ji, nodes[:], {10, 20, 200, 200})
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    initial_height := layout.content_height
    testing.expect_value(t, initial_height, theme.TREE_ROW_HEIGHT * 6)
    tree_transition_set_component_expanded(&state, &nodes[0], false)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect_value(t, layout.content_height, initial_height)
    testing.expect(t, !uilibrary.tree_layout_find(&layout, &nodes[2])^.logical)
    previous := layout.content_height
    samples := [5]f64{30, 60, 90, 120, 179}
    for milliseconds in samples {
        frame.geometry.now_seconds = 1 + milliseconds / 1000
        uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
        testing.expect(t, layout.content_height <= previous)
        testing.expect(t, state.motion.branches[0].running)
        bounds := uilibrary.tree_row_screen_geometry(
            layout.rows[0], frame.geometry.panel, 0)
        testing.expect_value(t, bounds.bounds.height, theme.TREE_ROW_HEIGHT)
        previous = layout.content_height
    }
    frame.geometry.now_seconds = 1 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect(t, !state.motion.branches[0].running)
    testing.expect_value(t, layout.count, 3)
    testing.expect_value(t, layout.content_height, theme.TREE_ROW_HEIGHT * 3)
    testing.expect_value(t,
        uilibrary.tree_layout_find(&layout, &nodes[4])^.content_y, theme.TREE_ROW_HEIGHT)
}

// Verify reversal samples current height without expanding the fixture beyond tree state.
@(test)
tree_transition_reverses_without_a_queue :: proc(t: ^testing.T) {
    state: Tree_Transition_Components
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    frame := tree_transition_geometry_fixture(
        &state, &ji, nodes[:], {10, 20, 200, 200})
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    tree_transition_set_component_expanded(&state, &nodes[0], false)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    frame.geometry.now_seconds = 1.06
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    before_height := layout.content_height
    tree_transition_set_component_expanded(&state, &nodes[0], true)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect_value(t, layout.content_height, before_height)
    testing.expect_value(t, state.motion.branches[0].start_seconds, f64(1.06))
    frame.geometry.now_seconds = 1.09
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect_value(t, state.motion.branches[0].start_seconds, f64(1.06))
    frame.geometry.now_seconds = 1.06 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect_value(t, layout.content_height, theme.TREE_ROW_HEIGHT * 6)
    testing.expect(t, !state.motion.branches[0].running)
}

// Verify concurrent root/nested motion composes clips without extending ancestor deadlines.
@(test)
tree_transition_composes_concurrent_nested_branches :: proc(t: ^testing.T) {
    state: Tree_Transition_Components
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    frame := tree_transition_geometry_fixture(
        &state, &ji, nodes[:], {10, 20, 200, 200})
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    tree_transition_set_component_expanded(&state, &nodes[0], false)
    tree_transition_set_component_expanded(&state, &nodes[4], false)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    frame.geometry.now_seconds = 1.03
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    tree_transition_set_component_expanded(&state, &nodes[1], false)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect(t, state.motion.branches[0].running)
    testing.expect(t, state.motion.branches[1].running)
    testing.expect(t, state.motion.branches[4].running)
    descendant := uilibrary.tree_layout_find(&layout, &nodes[2])
    ancestor := uilibrary.tree_layout_find(&layout, &nodes[1])
    testing.expect(t, descendant^.reveal.y >= ancestor^.reveal.y)
    testing.expect(t, descendant^.reveal.height <= ancestor^.reveal.height)
    frame.geometry.now_seconds = 1 + uiaccordion.INTERFACE_TRANSITION_SECONDS
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &layout)
    testing.expect(t, !state.motion.branches[0].running)
    testing.expect(t, state.motion.branches[1].running)
    testing.expect_value(t, state.motion.branches[0].height, f32(0))
}

// Verify logical semantics excludes closing tails while incoming bounds share visual clipping.
@(test)
tree_transition_semantics_share_prepared_clips :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params, &prepared)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect_value(t,
        uisemantics.semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t,
        uisemantics.semantic_node_index(
            uisemantics.semantic_snapshot(semantic),
            uilibrary.tree_item_semantic_id(&nodes[2])),
        -1)
    params.mouse_input.sample_time_seconds = 1.06
    uilibrary.prepare_tree_list_panel(params, &prepared)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect_value(t,
        uisemantics.semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
    row := uilibrary.tree_layout_find(&prepared.layout, &nodes[3])
    expected := uilibrary.tree_row_screen_geometry(row^,
        params.list_panel, runtime.library.tree.scroll_y)
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot,
        uilibrary.tree_item_semantic_id(&nodes[3]))
    tree_transition_expect_semantic_clip(t, snapshot, index, expected)
}

// Verify a visible tree semantic node publishes matching prepared bounds and clip.
tree_transition_expect_semantic_clip :: proc(
    t: ^testing.T, snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    index: int, expected: viewmodel.Ui_Control_Geometry) {
    node := snapshot^.nodes[index]
    testing.expect_value(t, node.bounds, expected.bounds)
    testing.expect_value(t, node.clip_bounds, expected.clip_bounds)
    testing.expect(t, .Visible not_in node.states)
    testing.expect_value(t, node.actions, viewmodel.Ui_Node_Action_Set{})
}

// Verify releases outside reveal cancel capture even when still inside the full-size row.
@(test)
tree_transition_hidden_release_cannot_activate :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    params.mouse_input.sample_time_seconds = 1.01
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    row := uilibrary.tree_layout_find(&prepared.layout, &nodes[1])
    runtime.input.press_owner = {
        active = true, kind = .List_Item,
        id = uilibrary.tree_placement_press_id(row^.item)}
    params.mouse_input.mouse_position = {
        params.list_panel.x + 30,
        params.list_panel.y + row^.content_y + theme.TREE_ROW_HEIGHT - 1}
    params.mouse_input.mouse_released = {.Left}
    prepared.scroll = uiwidgets.scroll_container_visual(params.list_panel,
        prepared.layout.content_height, 0, 1)
    hit := uilibrary.tree_update_prepared_rows(params, &prepared)
    testing.expect_value(t, hit.selected_node, nil)
    testing.expect(t, !runtime.input.press_owner.active)
}

// Verify required keyboard reveal settles ancestors, not an unrelated closing root.
@(test)
tree_transition_keyboard_reveal_finishes_required_path :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    tree_transition_set_expanded(&runtime, &nodes[0], true)
    tree_transition_set_expanded(&runtime, &nodes[4], false)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    uilibrary.tree_set_active_node(&runtime, &nodes[2], true)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect(t, !runtime.library.motion.branches[1].running)
    testing.expect(t, runtime.library.motion.branches[5].running)
    testing.expect(t,
        uilibrary.tree_row_is_revealed(
            uilibrary.tree_layout_find(&prepared.layout, &nodes[2])^))
    testing.expect(t, !runtime.library.tree.reveal_pending)
}

// Verify search, external reveal, generation, viewport, and reduced-motion boundaries snap.
@(test)
tree_transition_invalidations_snap :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    layout: viewmodel.Ui_Tree_Prepared_Layout
    for trigger in 0..<7 {
        runtime.library.tree.reveal_pending = false
        runtime.preferences.values.interface.reduce_motion = false
        runtime.platform_reduce_motion = false
        params.reduce_motion = false
        uilibrary.tree_prepare_layout(params, &layout)
        item_index := uilibrary.tree_projection_find(
            &runtime.library.tree.projection, nodes[0].stable_id)
        tree_transition_set_expanded(
            &runtime, &nodes[0],
            !runtime.library.tree.projection.items[item_index].expanded)
        uilibrary.tree_prepare_layout(params, &layout)
        testing.expect(t, runtime.library.motion.branches[1].running)
        switch trigger {
        case 0: runtime.library.search.query_revision += 1
        case 1: runtime.library.search.committed_generation += 1
        case 2: ji.content_generation += 1
        case 3: params.list_panel.width += 1
        case 4: runtime.preferences.values.interface.reduce_motion = true
        case 5: runtime.platform_reduce_motion = true
        case 6:
            runtime.library.tree.reveal_pending = true
            runtime.library.tree.reveal_reason = .Programmatic
        }
        params.reduce_motion = runtime.preferences.values.interface.reduce_motion ||
            runtime.platform_reduce_motion
        uilibrary.tree_prepare_layout(params, &layout)
        testing.expect(t, !runtime.library.motion.branches[1].running)
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
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    runtime.library.tree.scroll_y = theme.TREE_ROW_HEIGHT * 3
    item := uilibrary.tree_layout_find(&prepared.layout, &nodes[4])^.item
    uilibrary.tree_motion_anchor(params, item, &prepared.layout)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    params.mouse_input.sample_time_seconds = 1.09
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    uilibrary.tree_motion_apply_anchor(params, &prepared.layout)
    testing.expect_value(t, uilibrary.tree_layout_find(
        &prepared.layout, &nodes[4])^.content_y -
        runtime.library.tree.scroll_y, runtime.library.motion.anchor_view_y)
    params.mouse_input.mouse_wheel_delta = -1
    uilibrary.tree_motion_apply_anchor(params, &prepared.layout)
    testing.expect(t, !runtime.library.motion.anchored)
    params.mouse_input.sample_time_seconds = 1.18
    uilibrary.tree_prepare_layout(params, &prepared.layout)
    uilibrary.tree_refresh_preparation(params, &prepared)
    testing.expect(t, runtime.library.tree.scroll_y <= prepared.scroll.maximum)
    testing.expect_value(t, prepared.scroll.maximum, theme.TREE_ROW_HEIGHT * 2)
}

// Hidden Library preparation admits its workspace even before the first visible frame.
@(test)
tree_transition_first_hidden_preparation_admits_motion_storage :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect_value(t, len(runtime.library.motion.branches), 0)
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_visual(params, &prepared)
    testing.expect_value(t, prepared.layout.count, 7)
    testing.expect_value(t, runtime.library.motion.count, 7)
    testing.expect(t, !runtime.library.motion.branches[1].running)
}

// Verify hidden Library preparation preserves user scroll and leaves no running branches.
@(test)
tree_transition_outgoing_preparation_is_noninteractive :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.tree_prepare_layout(params, &layout)
    runtime.library.tree.scroll_y = 400
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_wheel_delta = -10
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_visual(params, &prepared)
    testing.expect_value(t, runtime.library.tree.scroll_y, f32(400))
    testing.expect_value(t, prepared.content_height, theme.TREE_ROW_HEIGHT * 4)
    testing.expect(t, !runtime.library.motion.branches[1].running)
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
        list_panel = {0, 0, 200, 1000}, scroll_y = &runtime.library.tree.scroll_y}
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    for index in 0..<len(nodes) {
        tree_transition_set_expanded(&runtime, &nodes[index], true)
    }
    layout: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    testing.expect_value(t, layout.count, len(nodes) + 1)
    testing.expect_value(t, runtime.library.motion.count, len(nodes) + 1)
    testing.expect_value(t,
        layout.content_height, f32(len(nodes) + 1) * theme.TREE_ROW_HEIGHT)
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.tree_prepare_layout(params, &layout)
    testing.expect_value(t, layout.count, len(nodes) + 1)
    testing.expect(t, !layout.rows[len(nodes)].logical)
    testing.expect_value(t, layout.rows[len(nodes)].depth, len(nodes) - 1)
}

// Verify real pointer press/release toggles admit motion through the ordinary row owner.
@(test)
tree_transition_pointer_toggle_uses_prepared_row :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    params.mouse_input.mouse_position = {
        params.list_panel.x + theme.TREE_ROW_ICON_OFFSET_X + 2,
        params.list_panel.y + theme.TREE_ROW_HEIGHT + theme.TREE_ROW_ICON_OFFSET_Y + 2}
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_down = {.Left}
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect(t, runtime.input.press_owner.active)
    params.mouse_input.mouse_pressed = {}
    params.mouse_input.mouse_down = {}
    params.mouse_input.mouse_released = {.Left}
    uilibrary.prepare_tree_list_panel(params, &prepared)
    item_index := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, nodes[0].stable_id)
    testing.expect(t, runtime.library.tree.projection.items[item_index].expanded)
    testing.expect(t, runtime.library.motion.branches[1].running)
    testing.expect(t, !runtime.input.press_owner.active)
    testing.expect_value(t, prepared.content_height, theme.TREE_ROW_HEIGHT * 4)
    testing.expect_value(t, ji.selected_animation, &nodes[0])
}

// Verify addressed accessibility expansion animates and search-forced no-ops do not.
@(test)
tree_transition_addressed_expansion_and_search_policy :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    semantic^.commands[0] = {
        target = uilibrary.tree_item_semantic_id(&nodes[0]), kind = .Expand}
    semantic^.command_count = 1
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect(t, runtime.library.motion.branches[1].running)
    params.mouse_input.sample_time_seconds = 1.05
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect_value(t, runtime.library.motion.branches[1].start_seconds, f64(1))
    search := &runtime.library.search
    defer viewmodel.library_search_destroy(search)
    testing.expect(t, viewmodel.library_search_reserve_ids(search, false, 2))
    search.visible_ids[0] = nodes[0].stable_id
    search.visible_ids[1] = nodes[1].stable_id
    search.visible_id_count = 2
    search.active = true
    uilibrary.prepare_tree_list_panel(params, &prepared)
    semantic^.commands[0].kind = .Collapse
    uilibrary.prepare_tree_list_panel(params, &prepared)
    item_index := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, nodes[0].stable_id)
    testing.expect(t, !runtime.library.tree.projection.items[item_index].expanded)
    testing.expect(t,
        uilibrary.tree_node_is_effectively_expanded(params.visibility, &nodes[0]))
    testing.expect(t, !runtime.library.motion.branches[1].running)
}

// Verify reduced-motion collapse releases a held descendant even when no tail row remains.
@(test)
tree_transition_snap_cancels_removed_row_capture :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params, &prepared)
    runtime.input.press_owner = {
        active = true, kind = .List_Item,
        id = uilibrary.tree_placement_press_id(
            runtime.library.tree.projection.items[
                uilibrary.tree_projection_find(&runtime.library.tree.projection,
                    nodes[2].stable_id)])}
    runtime.preferences.values.interface.reduce_motion = true
    params.reduce_motion = true
    tree_transition_set_expanded(&runtime, &nodes[0], false)
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect(t, !runtime.input.press_owner.active)
    testing.expect(t, !runtime.library.motion.branches[0].running)
}

// Exercise topology invalidation and reduced motion within the tracked interval.
tree_transition_test_invalidation_paths :: proc(
    params: ^uilibrary.Tree_List_Params,
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    prepared: ^uilibrary.Tree_List_Preparation) {
    params^.ji^.content_generation += 1
    uilibrary.prepare_tree_list_panel(params^, prepared)
    params^.reduce_motion = true
    runtime^.preferences.values.interface.reduce_motion = true
    params^.mouse_input.sample_time_seconds += 0.1
    uilibrary.prepare_tree_list_panel(params^, prepared)
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
    prepared: uilibrary.Tree_List_Preparation
    for frame in 0..<40 {
        params.mouse_input.sample_time_seconds = 1 + f64(frame) / 100
        if frame % 4 == 0 {
            index := uilibrary.tree_projection_find(
                &runtime.library.tree.projection, nodes[0].stable_id)
            tree_transition_set_expanded(
                &runtime, &nodes[0],
                !runtime.library.tree.projection.items[index].expanded)
        }
        if frame % 5 == 0 {
            index := uilibrary.tree_projection_find(
                &runtime.library.tree.projection, nodes[4].stable_id)
            tree_transition_set_expanded(
                &runtime, &nodes[4],
                !runtime.library.tree.projection.items[index].expanded)
        }
        uilibrary.prepare_tree_list_panel(params, &prepared)
    }
    tree_transition_test_invalidation_paths(&params, &runtime, &prepared)
    testing.expect_value(t, tracker.total_allocation_count, i64(0))
}

// Verify late search publication cannot change the disclosure facts of an already prepared frame.
@(test)
tree_transition_prepared_disclosure_is_frozen :: proc(t: ^testing.T) {
    state: Tree_Transition_Components
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    frame := tree_transition_geometry_fixture(
        &state, &ji, nodes[:], {10, 20, 200, 200})
    tree_transition_set_component_expanded(&state, &nodes[0], false)
    defer viewmodel.library_search_destroy(&state.search)
    testing.expect(t, viewmodel.library_search_reserve_ids(&state.search, false, 2))
    state.search.active = true
    state.search.visible_ids[0] = nodes[0].stable_id
    state.search.visible_ids[1] = nodes[1].stable_id
    state.search.visible_id_count = 2
    frame.geometry.search_active = true
    frame.admission.search_active = true
    prepared: viewmodel.Ui_Tree_Prepared_Layout
    next_frame: viewmodel.Ui_Tree_Prepared_Layout
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &prepared)
    testing.expect(t, prepared.rows[0].expanded)
    state.search.active = false
    frame.geometry.search_active = false
    frame.admission.search_active = false
    testing.expect(t, prepared.rows[0].expanded)
    uilibrary.tree_layout_prepare(frame.geometry, frame.admission, &next_frame)
    testing.expect(t, !next_frame.rows[0].expanded)
}

// Seed a data-controlled deep chain without imposing the former inline row limit.
tree_transition_seed_deep_chain :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: []bridgemodel.Euclid_Julia_Animation_Interface) {
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes)
    ji^.content_generation = 1
    for index in 0..<len(nodes) {
        identity := index + 1
        nodes[index].stable_id[0] = byte(identity)
        nodes[index].stable_id[1] = byte(identity >> 8)
        nodes[index].name = "deep"
        nodes[index].node_kind = .Animation
        nodes[index].is_expanded = true
        if index > 0 {
            nodes[index].parent = &nodes[index - 1]
            nodes[index - 1].first_child = &nodes[index]
        }
        if index + 1 < len(nodes) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }
    }
}

// Deep layouts grow typed projection buffers and keep scratch consumers independent.
@(test)
tree_layout_workspace_reuses_deep_topology :: proc(t: ^testing.T) {
    state: Tree_Transition_Components
    ji: bridgemodel.Euclid_Julia_Interface
    nodes := make([]bridgemodel.Euclid_Julia_Animation_Interface, 600, context.allocator)
    defer delete(nodes, context.allocator)
    tree_transition_seed_deep_chain(&ji, nodes)
    tree_transition_geometry_seed_projection(&state.tree.projection, nodes)
    defer viewmodel.ui_tree_projection_destroy(&state.tree.projection)
    frame := tree_transition_deep_geometry(
        &state, &ji, {10, 20, 400, 800})
    prepared: viewmodel.Ui_Tree_Prepared_Layout
    scratch: viewmodel.Ui_Tree_Prepared_Layout
    testing.expect(t, uilibrary.tree_layout_prepare(
        frame.geometry, frame.admission, &prepared))
    testing.expect_value(t, prepared.count, len(nodes))
    testing.expect_value(t, prepared.rows[len(nodes) - 1].depth, len(nodes) - 1)
    testing.expect(t, uilibrary.tree_layout_prepare_mode(
        frame.geometry, frame.admission, &scratch, true))
    testing.expect(t, &prepared.rows[0] != &scratch.rows[0])
    testing.expect_value(t, prepared.rows[len(nodes) - 1].depth, len(nodes) - 1)
    tree_transition_assert_repeated_preparation_is_reused(t, frame, &prepared)
}

// Bind deep-chain state to the same production geometry contract as the pane.
tree_transition_deep_geometry :: proc(
    state: ^Tree_Transition_Components,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    panel: geometry.Rectangle) -> Tree_Transition_Geometry {
    projection := &state^.tree.projection
    visibility := uilibrary.Tree_Visibility_Policy{
        search = &state^.search,
        projection = projection,
    }
    return {
        geometry = {
            ji = ji,
            projection = projection,
            motion = &state^.motion,
            drawer = &state^.actions.drawer,
            visibility = visibility,
            panel = panel,
            now_seconds = 1,
        },
        admission = {
            generation = ji^.content_generation,
            topology_revision = projection^.topology_revision,
            count = projection^.count,
            panel = panel,
        },
    }
}

// Assert unchanged backing after one thousand warmed tree preparations.
tree_transition_assert_repeated_preparation_is_reused :: proc(
    t: ^testing.T, frame: Tree_Transition_Geometry,
    prepared: ^viewmodel.Ui_Tree_Prepared_Layout) {
    owner := &frame.geometry.projection^.allocator
    before := storage.tlsf_owner_diagnostics(owner)
    for _ in 0..<1000 {
        testing.expect(t, uilibrary.tree_layout_prepare(
            frame.geometry, frame.admission, prepared))
    }
    after := storage.tlsf_owner_diagnostics(owner)
    testing.expect_value(t, after.retained_bytes, before.retained_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
}

// Scroll and resize retain logical membership while bounds follow the final viewport.
@(test)
tree_semantics_retain_offscreen_identity_and_reveal :: proc(t: ^testing.T) {
    semantic: viewmodel.Ui_Semantic_Focus_State
    defer viewmodel.ui_semantic_focus_destroy(&semantic)
    runtime := viewmodel.Euclid_Ui_Runtime_State{semantic_focus = &semantic}
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&runtime, &ji, nodes[:])
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    params.list_panel = {10, 20, 75, theme.TREE_ROW_HEIGHT}
    runtime.library.tree.reveal_pending = false
    prepared: uilibrary.Tree_List_Preparation
    testing.expect(t, uisemantics.semantic_begin(&semantic))
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect_value(t, uisemantics.semantic_publish(&semantic),
        viewmodel.Ui_Semantic_Status.Ok)
    target := uilibrary.tree_item_semantic_id(&nodes[5])
    snapshot := uisemantics.semantic_snapshot(&semantic)
    index := uisemantics.semantic_node_index(snapshot, target)
    testing.expect(t, index >= 0)
    before := snapshot.nodes[index]
    testing.expect(t, .Visible in before.states && .Focus in before.actions)
    testing.expect_value(t, before.parent,
        uilibrary.tree_item_semantic_id(&nodes[4]))
    runtime.library.tree.scroll_y = theme.TREE_ROW_HEIGHT * 5
    tree_transition_assert_scrolled_identity(t, params, &prepared, before)
    params.list_panel = {10, 20, 320, theme.TREE_ROW_HEIGHT * 2}
    uilibrary.tree_set_active_node(&runtime, &nodes[5], true)
    tree_transition_assert_scrolled_identity(t, params, &prepared, before)
    testing.expect(t, !runtime.library.tree.reveal_pending)
}

// Compare hierarchy and action identity after a new frame has scrolled or resized.
tree_transition_assert_scrolled_identity :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params,
    prepared: ^uilibrary.Tree_List_Preparation,
    before: viewmodel.Ui_Semantic_Node) {
    semantic := params.ui_runtime.semantic_focus
    testing.expect(t, uisemantics.semantic_begin(semantic))
    uilibrary.prepare_tree_list_panel(params, prepared)
    testing.expect_value(t, uisemantics.semantic_publish(semantic),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, before.id)
    testing.expect(t, index >= 0)
    after := snapshot.nodes[index]
    testing.expect_value(t, after.parent, before.parent)
    testing.expect_value(t, after.level, before.level)
    testing.expect_value(t, after.position_in_set, before.position_in_set)
    testing.expect_value(t, after.actions, before.actions)
    testing.expect(t, after.bounds.y != before.bounds.y)
    testing.expect(t, after.clip_bounds.width <= params.list_panel.width)
}
