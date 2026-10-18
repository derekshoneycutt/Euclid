#+test
package ui

import bridgemodel "../../bridge/model"
import collections "../../collections"
import storage "../../core/storage"
import "core:testing"
import "core:encoding/uuid"
import viewmodel "model"
import uilibrary "library"

// Repeated admitted edits reuse record/text/index pools without rebuilding stable nodes.
@(test)
library_storage_two_thousand_edit_cycles_reuse_warmed_peak :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    set := new(collections.Set, context.allocator)
    defer tree_favorites_destroy_set(set)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, set)
    projection := &runtime.library.tree.projection
    defer viewmodel.ui_tree_projection_destroy(projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    key := set^.entries[0].id
    node := projection^.items[uilibrary.tree_projection_find(projection, key)]
    builds := projection^.build_count
    library_storage_edit_batch(t, &params, 0)
    display := storage.tlsf_owner_diagnostics(&set^.allocator)
    prepared := storage.tlsf_owner_diagnostics(&projection^.allocator)
    library_storage_edit_batch(t, &params, 1000)
    library_storage_expect_reuse(t,
        display, storage.tlsf_owner_diagnostics(&set^.allocator))
    library_storage_expect_reuse(t,
        prepared, storage.tlsf_owner_diagnostics(&projection^.allocator))
    testing.expect_value(t,
        projection^.items[uilibrary.tree_projection_find(projection, key)], node)
    testing.expect_value(t, projection^.build_count, builds)
    testing.expect_value(t, set^.entry_count, 1)
}

// Compare live pressure at the same removed-transient baseline and retained peak.
library_storage_expect_reuse :: proc(
    t: ^testing.T, before, after: storage.Tlsf_Owner_Diagnostics) {
    testing.expect_value(t, after.retained_bytes, before.retained_bytes)
    testing.expect_value(t, after.pool_count, before.pool_count)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, after.peak_live_bytes, before.peak_live_bytes)
    testing.expect_value(t, after.peak_allocation_count, before.peak_allocation_count)
    testing.expect_value(t, after.growth_failure_count, uint(0))
}

// Each cycle renames, admits a fresh UUID, moves retained nodes, then removes it.
library_storage_edit_batch :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params, first: int) {
    set := params^.collections
    key := set^.entries[0].id
    identity, failure := collections.placement_identity_for_entry(set, key)
    testing.expect_value(t, failure, collections.Policy_Error.None)
    for index in first..<first + 1000 {
        rename, rename_error := collections.make_placement_name_mutation(
            identity, "A fixed peak retained label")
        testing.expect_value(t, rename_error, collections.Mutation_Error.None)
        library_storage_apply(t, params, rename, "")
        entry: uuid.Identifier
        entry[0] = 201
        entry[1] = byte(index)
        entry[2] = byte(index >> 8)
        add := collections.Mutation{
            kind = .Add_Favorite, entry_id = entry,
            animation_id = params^.ji^.animation_head^.stable_id,
            placement = {
                collection_id = collections.FAVORITES_COLLECTION_ID,
                entry_id = entry,
            },
        }
        library_storage_apply(t, params, add, "Animation")
        library_storage_move_roundtrip(t, params, identity)
        library_storage_apply(t, params, {
            kind = .Remove_Favorite, entry_id = entry,
            placement = add.placement,
        }, "")
        rename, rename_error = collections.make_placement_name_mutation(identity, "")
        testing.expect_value(t, rename_error, collections.Mutation_Error.None)
        library_storage_apply(t, params, rename, "")
        testing.expect_value(t, collections.find_entry(set, entry), -1)
    }
}

// Move the retained placement around its transient sibling without replacing either node.
library_storage_move_roundtrip :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    identity: collections.Placement_Identity) {
    directions := [2]collections.Move_Direction{.Down, .Up}
    for direction in directions {
        move, failure := collections.make_placement_move(
            params^.collections, identity, direction)
        testing.expect_value(t, failure, collections.Policy_Error.None)
        library_storage_apply(t, params, move, "")
    }
}

// Exercise the same reserve/model/commit boundary used by the ordinary save owner.
library_storage_apply :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    mutation: collections.Mutation, canonical: string) {
    projection := &params^.ui_runtime^.library.tree.projection
    testing.expect_value(t, viewmodel.ui_tree_projection_prepare_mutation(
        projection, mutation, canonical), collections.Mutation_Error.None)
    testing.expect_value(t, collections.apply_mutation(params^.collections, mutation),
        collections.Mutation_Error.None)
    params^.collections_revision += 1
    testing.expect(t, viewmodel.ui_tree_projection_commit_mutation(
        params^.ui_runtime, params^.collections, mutation, params^.collections_revision))
    testing.expect(t, uilibrary.tree_projection_prepare(params^))
}
