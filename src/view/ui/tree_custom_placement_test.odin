#+test
package ui

import bridgemodel "../../bridge/model"
import collections "../../collections"
import testing "core:testing"
import viewmodel "model"
import uilibrary "library"
import uuid "core:encoding/uuid"

Tree_Custom_Placement_Fixture :: struct {
    runtime: viewmodel.Euclid_Ui_Runtime_State,
    ji: bridgemodel.Euclid_Julia_Interface,
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface,
    set: ^collections.Set,
    first_collection: uuid.Identifier,
    second_collection: uuid.Identifier,
}

// Create two custom heads and a live catalogue for placement projection tests.
tree_custom_placement_fixture :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture) {
    fixture^.set = new(collections.Set, context.allocator)
    collections.initialize(fixture^.set)
    fixture^.first_collection[0], fixture^.second_collection[0] = 51, 52
    ids: [2]uuid.Identifier = {fixture^.first_collection, fixture^.second_collection}
    for id in ids {
        mutation, failure := collections.make_collection_create_mutation(
            fixture^.set, id, "Custom")
        testing.expect_value(t, failure, collections.Policy_Error.None)
        testing.expect_value(t, collections.apply_mutation(fixture^.set, mutation),
            collections.Mutation_Error.None)
    }
    fixture^.nodes[0].stable_id[0], fixture^.nodes[1].stable_id[0] = 11, 12
    fixture^.nodes[0].name, fixture^.nodes[1].name = "Canonical A", "Canonical B"
    fixture^.nodes[0].node_kind, fixture^.nodes[1].node_kind =
        .Animation, .Animation
    fixture^.nodes[0].next_in_registry = &fixture^.nodes[1]
    fixture^.ji.animation_head = &fixture^.nodes[0]
    fixture^.ji.animation_count = len(fixture^.nodes)
    fixture^.ji.content_generation = 1
}

// Publish one local model mutation through the projection's prepare/commit contract.
tree_custom_placement_apply :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    mutation: collections.Mutation, canonical_name: string = "") {
    projection := &fixture^.runtime.library.tree.projection
    testing.expect_value(t, viewmodel.ui_tree_projection_prepare_mutation(
        projection, mutation, canonical_name), collections.Mutation_Error.None)
    testing.expect_value(t, collections.apply_mutation(fixture^.set, mutation),
        collections.Mutation_Error.None)
    revision := projection.collections_revision + 1
    testing.expect(t, viewmodel.ui_tree_projection_commit_mutation(
        &fixture^.runtime, fixture^.set, mutation, revision))
}

// Release fixture-owned model and projection storage after each placement scenario.
tree_custom_placement_destroy :: proc(fixture: ^Tree_Custom_Placement_Fixture) {
    viewmodel.ui_tree_projection_destroy(&fixture^.runtime.library.tree.projection)
    collections.destroy(fixture^.set)
    free(fixture^.set, context.allocator)
}

// Borrow fixture owners with the first accepted collection revision.
tree_custom_placement_params :: proc(
    fixture: ^Tree_Custom_Placement_Fixture) -> uilibrary.Tree_List_Params {
    return {
        ji = &fixture.ji,
        ui_runtime = &fixture.runtime,
        collections = fixture.set,
        collections_revision = 1,
    }
}

// Admit and publish a membership addition with the catalogue's canonical label.
tree_custom_placement_add :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    collection_id, entry_id, animation_id: uuid.Identifier) {
    mutation, failure := collections.make_collection_animation_add_mutation(
        fixture.set, collection_id, entry_id, animation_id)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    canonical_name := ""
    for node in fixture.nodes {
        if node.stable_id == animation_id {
            canonical_name = node.name
        }
    }
    tree_custom_placement_apply(t, fixture, mutation, canonical_name)
}

// Resolve exact current membership before constructing a removal for either path.
tree_custom_placement_removal :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    entry_id: uuid.Identifier) -> collections.Mutation {
    identity, identity_error := collections.placement_identity_for_entry(
        fixture.set, entry_id)
    testing.expect_value(t, identity_error, collections.Policy_Error.None)
    removal, failure := collections.make_collection_animation_remove_mutation(
        fixture.set, identity)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    return removal
}

// Publish an alias through the same qualified naming contract as the editor.
tree_custom_placement_rename :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    entry_id: uuid.Identifier, name: string) {
    identity, failure := collections.placement_identity_for_entry(fixture.set, entry_id)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    rename, mutation_error := collections.make_placement_name_mutation(identity, name)
    testing.expect_value(t, mutation_error, collections.Mutation_Error.None)
    tree_custom_placement_apply(t, fixture, rename)
}

// Move an occurrence upward without changing its owning collection or target.
tree_custom_placement_move_up :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    entry_id: uuid.Identifier) {
    identity, failure := collections.placement_identity_for_entry(fixture.set, entry_id)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    move: collections.Mutation
    move, failure = collections.make_placement_move(fixture.set, identity, .Up)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    tree_custom_placement_apply(t, fixture, move)
}

// Local membership patches preserve surviving node addresses.
@(test)
tree_custom_placement_local_membership_preserves_survivors :: proc(t: ^testing.T) {
    fixture: Tree_Custom_Placement_Fixture
    tree_custom_placement_fixture(t, &fixture)
    defer tree_custom_placement_destroy(&fixture)
    params := tree_custom_placement_params(&fixture)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &fixture.runtime.library.tree.projection
    root := uilibrary.tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    first_head := uilibrary.tree_projection_find(projection, fixture.first_collection)
    second_head := uilibrary.tree_projection_find(projection, fixture.second_collection)
    root_node, first_node, second_node :=
        projection.items[root], projection.items[first_head],
        projection.items[second_head]
    first_entry, second_entry := uuid.Identifier{}, uuid.Identifier{}
    first_entry[0], second_entry[0] = 61, 62
    tree_custom_placement_add(t, &fixture,
        fixture.first_collection, first_entry, fixture.nodes[0].stable_id)
    tree_custom_placement_add(t, &fixture,
        fixture.first_collection, second_entry, fixture.nodes[1].stable_id)

    testing.expect_value(t, projection.items[root], root_node)
    testing.expect_value(t, projection.items[first_head], first_node)
    testing.expect_value(t, projection.items[second_head], second_node)
    first := uilibrary.tree_projection_find(projection, first_entry)
    second := uilibrary.tree_projection_find(projection, second_entry)
    testing.expect_value(t, projection.items[first_head].first_child, first)
    testing.expect_value(t, projection.items[first].next_sibling, second)
    removal := tree_custom_placement_removal(t, &fixture, first_entry)
    surviving_placement := projection.items[second]
    tree_custom_placement_apply(t, &fixture, removal)

    testing.expect_value(t, uilibrary.tree_projection_find(projection, first_entry),
        viewmodel.UI_TREE_NO_ITEM)
    second = uilibrary.tree_projection_find(projection, second_entry)
    testing.expect_value(t, projection.items[second], surviving_placement)
    testing.expect_value(t, projection.items[first_head].first_child, second)
    testing.expect_value(t, projection.items[root], root_node)
    testing.expect_value(t, projection.items[second_head], second_node)
}

// Custom aliases and sibling order remain independent, including unavailable targets.
@(test)
tree_custom_placement_aliases_and_moves_are_collection_qualified :: proc(
    t: ^testing.T) {
    fixture: Tree_Custom_Placement_Fixture
    tree_custom_placement_fixture(t, &fixture)
    defer tree_custom_placement_destroy(&fixture)
    first_id, missing_id, second_id :=
        uuid.Identifier{}, uuid.Identifier{}, uuid.Identifier{}
    first_id[0], missing_id[0], second_id[0] = 71, 72, 73
    missing_animation: uuid.Identifier = {}
    missing_animation[0] = 99
    params := tree_custom_placement_params(&fixture)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &fixture.runtime.library.tree.projection
    tree_custom_placement_add(t, &fixture,
        fixture.first_collection, first_id, fixture.nodes[0].stable_id)
    tree_custom_placement_add(t, &fixture,
        fixture.first_collection, missing_id, missing_animation)
    tree_custom_placement_add(t, &fixture,
        fixture.second_collection, second_id, fixture.nodes[0].stable_id)
    missing := uilibrary.tree_projection_find(projection, missing_id)
    testing.expect_value(t, uilibrary.tree_item_label(
        &fixture.ji, projection.items[missing], fixture.set), "Unavailable animation")
    tree_custom_placement_expect_controls(t, &fixture, missing_id)
    tree_custom_placement_expect_aliases_and_move(
        t, &fixture, [3]uuid.Identifier{first_id, missing_id, second_id})
    testing.expect_value(t,
        projection.items[missing].target_animation_id, missing_animation)
}

// Assert unavailable occurrences retain controls only while their owner is writable.
tree_custom_placement_expect_controls :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    missing_id: uuid.Identifier) {
    projection := &fixture.runtime.library.tree.projection
    missing := uilibrary.tree_projection_find(projection, missing_id)
    root := uilibrary.tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    head := uilibrary.tree_projection_find(projection, fixture.first_collection)
    projection.items[root].expanded = true
    projection.items[head].expanded = true
    testing.expect(t, uilibrary.tree_actions_eligible(
        projection, fixture.set, missing_id, false, projection.items[missing]))
    fixture.set.collections[collections.find_collection(
        fixture.set, fixture.first_collection)].is_read_only = true
    testing.expect(t, !uilibrary.tree_actions_eligible(
        projection, fixture.set, missing_id, false, projection.items[missing]))
    fixture.set.collections[collections.find_collection(
        fixture.set, fixture.first_collection)].is_read_only = false
}

// Check independent aliases and stable nodes across a qualified sibling move.
tree_custom_placement_expect_aliases_and_move :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    ids: [3]uuid.Identifier) {
    projection := &fixture.runtime.library.tree.projection
    first := uilibrary.tree_projection_find(projection, ids[0])
    missing := uilibrary.tree_projection_find(projection, ids[1])
    second := uilibrary.tree_projection_find(projection, ids[2])
    first_node, missing_node, second_node :=
        projection.items[first], projection.items[missing], projection.items[second]
    tree_custom_placement_rename(t, fixture, ids[0], "Opening construction")
    tree_custom_placement_rename(t, fixture, ids[2], "Compass approach")
    testing.expect_value(t, uilibrary.tree_item_label(
        &fixture.ji, projection.items[first], fixture.set), "Opening construction")
    testing.expect_value(t, uilibrary.tree_item_label(
        &fixture.ji, projection.items[second], fixture.set), "Compass approach")
    testing.expect_value(t, uilibrary.tree_item_label(
        &fixture.ji, projection.items[missing], fixture.set), "Unavailable animation")

    tree_custom_placement_move_up(t, fixture, ids[1])
    head := uilibrary.tree_projection_find(projection, fixture.first_collection)
    testing.expect_value(t, projection.items[head].first_child, missing)
    testing.expect_value(t, projection.items[missing].next_sibling, first)
    testing.expect_value(t, projection.items[first], first_node)
    testing.expect_value(t, projection.items[missing], missing_node)
    testing.expect_value(t, projection.items[second], second_node)
}

// Initial projection retains persisted custom groups instead of flattening descendants.
@(test)
tree_custom_placement_projection_preserves_stored_group_hierarchy :: proc(
    t: ^testing.T) {
    fixture: Tree_Custom_Placement_Fixture
    tree_custom_placement_fixture(t, &fixture)
    defer tree_custom_placement_destroy(&fixture)
    group_id, child_id := uuid.Identifier{}, uuid.Identifier{}
    group_id[0], child_id[0] = 81, 82
    testing.expect_value(t, collections.append_entry(fixture.set, {
        id = group_id,
        collection_id = fixture.first_collection,
        sibling_order = 0,
        kind = .Group,
    }), collections.Policy_Error.None)
    testing.expect_value(t, collections.append_entry(fixture.set, {
        id = child_id,
        collection_id = fixture.first_collection,
        parent_entry_id = group_id,
        sibling_order = 0,
        kind = .Animation,
        animation_id = fixture.nodes[0].stable_id,
    }), collections.Policy_Error.None)
    params: uilibrary.Tree_List_Params = {
        ji = &fixture.ji,
        ui_runtime = &fixture.runtime,
        collections = fixture.set,
        collections_revision = 1,
    }
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &fixture.runtime.library.tree.projection
    head := uilibrary.tree_projection_find(projection, fixture.first_collection)
    group := uilibrary.tree_projection_find(projection, group_id)
    child := uilibrary.tree_projection_find(projection, child_id)
    testing.expect_value(t, projection.items[group].kind,
        viewmodel.Ui_Tree_Item_Kind.Group)
    testing.expect_value(t, projection.items[head].first_child, group)
    testing.expect_value(t, projection.items[group].first_child, child)
    testing.expect_value(t, projection.items[child].parent, group)
    tree_custom_placement_expect_group_reconciliation(
        t, &fixture, params, group_id, child_id)
}

// External membership edits preserve stored group and child node identities.
tree_custom_placement_expect_group_reconciliation :: proc(
    t: ^testing.T, fixture: ^Tree_Custom_Placement_Fixture,
    initial_params: uilibrary.Tree_List_Params, group_id, child_id: uuid.Identifier) {
    params := initial_params
    projection := &fixture.runtime.library.tree.projection
    head := uilibrary.tree_projection_find(projection, fixture.first_collection)
    group := uilibrary.tree_projection_find(projection, group_id)
    child := uilibrary.tree_projection_find(projection, child_id)
    group_node := projection.items[group]
    child_node := projection.items[child]
    added_id: uuid.Identifier = {}
    added_id[0] = 83
    mutation, failure := collections.make_collection_animation_add_mutation(
        fixture.set, fixture.first_collection, added_id, fixture.nodes[1].stable_id)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    testing.expect_value(t, collections.apply_mutation(fixture.set, mutation),
        collections.Mutation_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, projection.items[group], group_node)
    testing.expect_value(t, projection.items[child], child_node)
    added := uilibrary.tree_projection_find(projection, added_id)
    testing.expect_value(t, projection.items[head].first_child, group)
    testing.expect_value(t, projection.items[group].next_sibling, added)

    mutation = tree_custom_placement_removal(t, fixture, child_id)
    testing.expect_value(t, collections.apply_mutation(fixture.set, mutation),
        collections.Mutation_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, projection.items[group], group_node)
    testing.expect_value(t, uilibrary.tree_projection_find(projection, child_id),
        viewmodel.UI_TREE_NO_ITEM)
    testing.expect_value(t, projection.items[group].first_child,
        viewmodel.UI_TREE_NO_ITEM)
}
