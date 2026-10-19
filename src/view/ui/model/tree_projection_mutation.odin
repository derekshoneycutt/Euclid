package viewmodel

import collections "../../../collections"
import storage "../../../core/storage"
import uuid "core:encoding/uuid"

// Reserve every projection resource before the collection mutation is admitted.
ui_tree_projection_prepare_mutation :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation,
    canonical_name: string) -> collections.Mutation_Error {
    if projection == nil {
        return .None
    }
    if mutation.kind == .Create_Collection &&
        mutation.collection_id == TREE_COLLECTIONS_ROOT_ID {
        return .Policy
    }
    if mutation.kind == .Add_Favorite &&
        (mutation.entry_id == TREE_COLLECTIONS_ROOT_ID ||
            mutation.entry_id == collections.FAVORITES_COLLECTION_ID) {
        return .Policy
    }
    if mutation.kind == .Add_Collection_Animation &&
        (mutation.entry_id == TREE_COLLECTIONS_ROOT_ID ||
            mutation.entry_id == collections.FAVORITES_COLLECTION_ID) {
        return .Policy
    }
    if !projection.valid {
        return .None
    }
    return ui_tree_projection_prepare_valid_mutation(
        projection, mutation, canonical_name)
}

// Validate one mutation against a live projection and retain its admission state.
ui_tree_projection_prepare_valid_mutation :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation,
    canonical_name: string) -> collections.Mutation_Error {
    if projection.mutation_prepared {
        return .Policy
    }
    result := ui_tree_projection_admit_mutation(projection, mutation, canonical_name)
    if result != .None {
        return result
    }
    projection.prepared_mutation = mutation
    projection.mutation_prepared = true
    return .None
}

// Dispatch resource preparation and policy checks before recording admission.
ui_tree_projection_admit_mutation :: proc(
    projection: ^Ui_Tree_Projection, mutation: collections.Mutation,
    canonical_name: string) -> collections.Mutation_Error {
    switch mutation.kind {
    case .Create_Collection:
        return ui_tree_projection_prepare_collection(projection, mutation)
    case .Add_Favorite:
        return ui_tree_projection_prepare_add(projection, mutation, canonical_name)
    case .Add_Collection_Animation:
        return ui_tree_projection_prepare_collection_animation(
            projection, mutation, canonical_name)
    case .Remove_Favorite, .Remove_Collection_Animation,
        .Reorder_Siblings, .Set_Entry_Name:
        return ui_tree_projection_admit_placement_edit(projection, mutation)
    case .Set_Collection_Name, .Reorder_Collections, .Delete_Collection:
        return ui_tree_projection_prepare_head_edit(projection, mutation)
    }
    return .None
}

// Check topology identity for placement edits that need no detached resources.
ui_tree_projection_admit_placement_edit :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> collections.Mutation_Error {
    switch mutation.kind {
    case .Remove_Favorite:
        if !ui_tree_projection_remove_is_admissible(projection, mutation) {
            return .Policy
        }
    case .Remove_Collection_Animation:
        if !ui_tree_projection_custom_placement_is_admissible(
            projection, mutation.placement) {
            return .Policy
        }
    case .Reorder_Siblings:
        if !ui_tree_projection_reorder_is_admissible(projection, mutation) {
            return .Policy
        }
    case .Set_Entry_Name:
        if !ui_tree_projection_name_is_admissible(projection, mutation) {
            return .Policy
        }
    case .Create_Collection, .Add_Favorite, .Add_Collection_Animation,
        .Set_Collection_Name, .Reorder_Collections, .Delete_Collection:
        return .Policy
    }
    return .None
}

// Reserve and create all detached records needed for one Favorites addition.
ui_tree_projection_prepare_add :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation,
    canonical_name: string) -> collections.Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.animation_id == (uuid.Identifier{}) ||
        mutation.placement.entry_id != mutation.entry_id ||
        mutation.placement.collection_id != collections.FAVORITES_COLLECTION_ID ||
        mutation.placement.parent_entry_id != (uuid.Identifier{}) ||
        ui_tree_projection_find(projection, mutation.entry_id) != UI_TREE_NO_ITEM {
        return .Policy
    }
    root := ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID)
    favorites := ui_tree_projection_find(projection, collections.FAVORITES_COLLECTION_ID)
    if root == UI_TREE_NO_ITEM {
        return .Policy
    }
    additional := 1
    if favorites == UI_TREE_NO_ITEM {
        additional += 1
    }
    if !ui_tree_projection_reserve(projection, projection.count + additional) {
        return .Allocation_Failed
    }
    if favorites == UI_TREE_NO_ITEM &&
        !ui_tree_projection_prepare_shell_nodes(projection) {
        ui_tree_projection_abort_mutation(projection)
        return .Allocation_Failed
    }
    if !ui_tree_projection_prepare_placement_node(
        projection, mutation, canonical_name) {
        ui_tree_projection_abort_mutation(projection)
        return .Allocation_Failed
    }
    return .None
}

// Reserve one detached custom placement node beneath its live writable head.
ui_tree_projection_prepare_collection_animation :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation,
    canonical_name: string) -> collections.Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.animation_id == (uuid.Identifier{}) ||
        mutation.placement.entry_id != mutation.entry_id ||
        mutation.placement.parent_entry_id != (uuid.Identifier{}) ||
        mutation.placement.collection_id == collections.FAVORITES_COLLECTION_ID ||
        ui_tree_projection_find(projection, mutation.entry_id) != UI_TREE_NO_ITEM {
        return .Policy
    }
    parent := ui_tree_projection_find(projection, mutation.placement.collection_id)
    if parent == UI_TREE_NO_ITEM ||
        !ui_tree_projection_is_custom_head(projection, parent) {
        return .Policy
    }
    if !ui_tree_projection_reserve(projection, projection.count + 1) {
        return .Allocation_Failed
    }
    if !ui_tree_projection_prepare_placement_node(projection, mutation, canonical_name) {
        ui_tree_projection_abort_mutation(projection)
        return .Allocation_Failed
    }
    return .None
}

// Prepare a detached Favorites head beneath the permanent Collections root.
ui_tree_projection_prepare_shell_nodes :: proc(
    projection: ^Ui_Tree_Projection) -> bool {
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    favorites, favorites_ok := ui_tree_projection_make_node({
        key = collections.FAVORITES_COLLECTION_ID,
        kind = .Collection,
        parent = UI_TREE_NO_ITEM,
        first_child = UI_TREE_NO_ITEM,
        last_child = UI_TREE_NO_ITEM,
        next_sibling = UI_TREE_NO_ITEM,
        expanded = projection.favorites_expanded,
    }, "", allocator)
    if !favorites_ok {
        return false
    }
    return ui_tree_projection_stage_node(projection, favorites)
}

// Prepare one detached placement node with its owned canonical label.
ui_tree_projection_prepare_placement_node :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation,
    canonical_name: string) -> bool {
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    placement, placement_ok := ui_tree_projection_make_node({
        key = mutation.entry_id,
        target_animation_id = mutation.animation_id,
        kind = .Placement,
        parent = UI_TREE_NO_ITEM,
        first_child = UI_TREE_NO_ITEM,
        last_child = UI_TREE_NO_ITEM,
        next_sibling = UI_TREE_NO_ITEM,
        selectable = true,
    }, canonical_name, allocator)
    if !placement_ok {
        return false
    }
    return ui_tree_projection_stage_node(projection, placement)
}

// Retain one detached node in the bounded mutation staging area.
ui_tree_projection_stage_node :: proc(
    projection: ^Ui_Tree_Projection,
    node: ^Ui_Tree_Item) -> bool {
    if projection.prepared_node_count >= len(projection.prepared_nodes) {
        allocator := storage.tlsf_owner_allocator(&projection.allocator)
        ui_tree_projection_free_node(node, allocator)
        return false
    }
    projection.prepared_nodes[projection.prepared_node_count] = node
    projection.prepared_node_count += 1
    return true
}

// Validate a Favorites removal against the current linked projection node.
ui_tree_projection_remove_is_admissible :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> bool {
    index := ui_tree_projection_find(projection, mutation.entry_id)
    favorites := ui_tree_projection_find(projection, collections.FAVORITES_COLLECTION_ID)
    return index != UI_TREE_NO_ITEM &&
        mutation.placement.entry_id == mutation.entry_id &&
        ui_tree_projection_identity_is_root_favorite(mutation.placement) &&
        projection.items[index].kind == .Placement &&
        projection.items[index].parent == favorites &&
        ui_tree_projection_is_linked(projection, index)
}

// Validate a custom placement against its qualified live parent chain.
ui_tree_projection_custom_placement_is_admissible :: proc(
    projection: ^Ui_Tree_Projection,
    identity: collections.Placement_Identity) -> bool {
    if identity.entry_id == (uuid.Identifier{}) ||
        identity.collection_id == (uuid.Identifier{}) ||
        identity.collection_id == collections.FAVORITES_COLLECTION_ID {
        return false
    }
    index := ui_tree_projection_find(projection, identity.entry_id)
    collection := ui_tree_projection_find(projection, identity.collection_id)
    parent_key := identity.parent_entry_id if
        identity.parent_entry_id != (uuid.Identifier{}) else identity.collection_id
    parent := ui_tree_projection_find(projection, parent_key)
    if index == UI_TREE_NO_ITEM || collection == UI_TREE_NO_ITEM ||
        parent == UI_TREE_NO_ITEM || projection.items[index].kind != .Placement ||
        projection.items[index].parent != parent ||
        !ui_tree_projection_is_linked(projection, index) {
        return false
    }
    for ancestor, steps := parent, 0;
        ancestor != UI_TREE_NO_ITEM && steps < projection.count;
        ancestor, steps = projection.items[ancestor].parent, steps + 1 {
        if ancestor == collection {
            return true
        }
    }
    return false
}

// Validate a sibling move against exact linked placement addresses in either collection.
ui_tree_projection_reorder_is_admissible :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> bool {
    index := ui_tree_projection_find(projection, mutation.placement.entry_id)
    sibling := ui_tree_projection_find(projection, mutation.sibling_entry_id)
    if mutation.placement.entry_id != mutation.entry_id ||
        index == UI_TREE_NO_ITEM || sibling == UI_TREE_NO_ITEM ||
        projection.items[index].parent != projection.items[sibling].parent ||
        !ui_tree_projection_is_linked(projection, sibling) {
        return false
    }
    if ui_tree_projection_identity_is_root_favorite(mutation.placement) {
        favorites := ui_tree_projection_find(
            projection, collections.FAVORITES_COLLECTION_ID)
        return projection.items[index].kind == .Placement &&
            projection.items[index].parent == favorites &&
            ui_tree_projection_is_linked(projection, index)
    }
    sibling_identity := mutation.placement
    sibling_identity.entry_id = mutation.sibling_entry_id
    return ui_tree_projection_custom_placement_is_admissible(
        projection, mutation.placement) &&
        ui_tree_projection_custom_placement_is_admissible(
            projection, sibling_identity)
}

// Validate a name edit against its exact linked Favorites or custom placement.
ui_tree_projection_name_is_admissible :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> bool {
    if mutation.placement.entry_id != mutation.entry_id {
        return false
    }
    if ui_tree_projection_identity_is_root_favorite(mutation.placement) {
        index := ui_tree_projection_find(projection, mutation.entry_id)
        favorites := ui_tree_projection_find(
            projection, collections.FAVORITES_COLLECTION_ID)
        return index != UI_TREE_NO_ITEM &&
            projection.items[index].kind == .Placement &&
            projection.items[index].parent == favorites &&
            ui_tree_projection_is_linked(projection, index)
    }
    return ui_tree_projection_custom_placement_is_admissible(
        projection, mutation.placement)
}

// Accept only a qualified root placement in Favorites.
ui_tree_projection_identity_is_root_favorite :: proc(
    identity: collections.Placement_Identity) -> bool {
    return identity.collection_id == collections.FAVORITES_COLLECTION_ID &&
        identity.parent_entry_id == (uuid.Identifier{})
}

// Publish the already-reserved topology patch after its model edit succeeds.
ui_tree_projection_commit_mutation :: proc(
    runtime: ^Euclid_Ui_Runtime_State,
    set: ^collections.Set,
    mutation: collections.Mutation,
    collections_revision: u64) -> bool {
    if runtime == nil || set == nil {
        return false
    }
    projection := &runtime.library.tree.projection
    if !projection.valid {
        if mutation.kind == .Delete_Collection {
            ui_tree_collection_retire_identity(
                runtime, mutation.collection_id, TREE_COLLECTIONS_ROOT_ID)
            if runtime.library.entry_name.placement.collection_id ==
                mutation.collection_id {
                runtime.library.entry_name = {}
            }
            runtime.library.actions = {}
        }
        return true
    }
    if !projection.mutation_prepared ||
        projection.prepared_mutation != mutation {
        return false
    }
    if !ui_tree_projection_publish_prepared_mutation(
        runtime, projection, set, mutation) {
        return false
    }
    projection.collections_revision = collections_revision
    ui_tree_projection_abort_mutation(projection)
    return true
}

// Apply the already-admitted topology patch without allocating.
ui_tree_projection_publish_prepared_mutation :: proc(
    runtime: ^Euclid_Ui_Runtime_State,
    projection: ^Ui_Tree_Projection,
    set: ^collections.Set,
    mutation: collections.Mutation) -> bool {
    committed := true
    switch mutation.kind {
    case .Create_Collection, .Reorder_Collections, .Delete_Collection:
        committed = ui_tree_projection_publish_head(runtime, mutation)
    case .Add_Favorite:
        committed = ui_tree_projection_commit_add(projection)
    case .Add_Collection_Animation:
        committed = ui_tree_projection_commit_custom_add(projection)
    case .Remove_Favorite:
        committed = ui_tree_projection_publish_favorite_removal(runtime, set, mutation)
    case .Remove_Collection_Animation:
        committed = ui_tree_projection_commit_custom_remove(
            runtime, projection, mutation)
    case .Reorder_Siblings:
        committed = ui_tree_projection_commit_reorder(projection, mutation)
    case .Set_Entry_Name, .Set_Collection_Name:
    }
    if !committed {
        return false
    }
    if mutation.kind != .Set_Entry_Name && mutation.kind != .Set_Collection_Name {
        projection.topology_revision += 1
    }
    return true
}

// Retire a favorite and repair both occurrence focus and optional shell focus.
ui_tree_projection_publish_favorite_removal :: proc(
    runtime: ^Euclid_Ui_Runtime_State,
    set: ^collections.Set,
    mutation: collections.Mutation) -> bool {
    if !ui_tree_projection_commit_remove(&runtime.library.tree.projection, set) {
        return false
    }
    ui_tree_projection_repair_removed_identity(runtime, mutation.entry_id)
    ui_tree_projection_repair_retired_favorites(runtime)
    return true
}

// Remove one custom placement node without retiring its collection or group.
ui_tree_projection_commit_custom_remove :: proc(
    runtime: ^Euclid_Ui_Runtime_State,
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> bool {
    index := ui_tree_projection_find(projection, mutation.entry_id)
    if index == UI_TREE_NO_ITEM || !ui_tree_projection_remove(projection, index) {
        return false
    }
    replacement := mutation.placement.parent_entry_id if
        mutation.placement.parent_entry_id != (uuid.Identifier{}) else
            mutation.placement.collection_id
    ui_tree_projection_repair_custom_removed_identity(
        runtime, mutation.entry_id, replacement)
    return true
}

// Repoint session focus only when it referred to the removed custom occurrence.
ui_tree_projection_repair_custom_removed_identity :: proc(
    runtime: ^Euclid_Ui_Runtime_State,
    removed, replacement: uuid.Identifier) {
    if runtime.library.tree.selected_item_id == removed {
        runtime.library.tree.selected_item_id = replacement
        runtime.library.tree.reveal_stable_id = replacement
        runtime.library.tree.reveal_pending = true
    }
    if runtime.semantic_focus != nil {
        if runtime.semantic_focus.active_tree_item == removed {
            runtime.semantic_focus.active_tree_item = replacement
        }
        if runtime.semantic_focus.logical_focus.stable_id == removed {
            runtime.semantic_focus.logical_focus = {
                domain = .Animation_Tree, local_id = 1}
            runtime.semantic_focus.active_tree_item = replacement
            runtime.semantic_focus.last_region = .Accordion_Content
            runtime.semantic_focus.last_traversal_order = 3
        }
    }
    if runtime.library.tree.reveal_stable_id == removed {
        runtime.library.tree.reveal_stable_id = replacement
        runtime.library.tree.reveal_pending = true
    }
    if runtime.library.entry_name.entry_id == removed {
        runtime.library.entry_name = {}
    }
    if runtime.library.actions.drawer.entry_id == removed {
        runtime.library.actions.drawer = {}
        runtime.library.actions.reorder = {}
        runtime.input.press_owner = {}
    }
}

// Retain a usable root focus when the optional Favorites head disappears.
ui_tree_projection_repair_retired_favorites :: proc(
    runtime: ^Euclid_Ui_Runtime_State) {
    projection := &runtime.library.tree.projection
    if ui_tree_projection_find(
        projection, collections.FAVORITES_COLLECTION_ID) != UI_TREE_NO_ITEM {
        return
    }
    if runtime.library.tree.selected_item_id == collections.FAVORITES_COLLECTION_ID {
        runtime.library.tree.selected_item_id = TREE_COLLECTIONS_ROOT_ID
    }
    if runtime.semantic_focus != nil &&
        runtime.semantic_focus.active_tree_item == collections.FAVORITES_COLLECTION_ID {
        runtime.semantic_focus.active_tree_item = TREE_COLLECTIONS_ROOT_ID
    }
}

// Remove an accepted placement and its empty collection shell when necessary.
ui_tree_projection_commit_remove :: proc(
    projection: ^Ui_Tree_Projection,
    set: ^collections.Set) -> bool {
    index := ui_tree_projection_find(
        projection, projection.prepared_mutation.entry_id)
    if index == UI_TREE_NO_ITEM || !ui_tree_projection_remove(projection, index) {
        return false
    }
    favorites := ui_tree_projection_find(projection, collections.FAVORITES_COLLECTION_ID)
    return favorites != UI_TREE_NO_ITEM &&
        projection.items[favorites].first_child != UI_TREE_NO_ITEM ||
        ui_tree_projection_remove_collection_shell(projection)
}

// Preserve disclosure state while retiring an empty Favorites branch.
ui_tree_projection_remove_collection_shell :: proc(
    projection: ^Ui_Tree_Projection) -> bool {
    favorites := ui_tree_projection_find(projection, collections.FAVORITES_COLLECTION_ID)
    root := ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID)
    if root != UI_TREE_NO_ITEM {
        projection.collections_expanded = projection.items[root].expanded
    }
    if favorites != UI_TREE_NO_ITEM {
        projection.favorites_expanded = projection.items[favorites].expanded
        if !ui_tree_projection_remove(projection, favorites) {
            return false
        }
    }
    return true
}

// Apply a reserved sibling-link change without allocating or replacing nodes.
ui_tree_projection_commit_reorder :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> bool {
    index := ui_tree_projection_find(projection, mutation.placement.entry_id)
    sibling := ui_tree_projection_find(projection, mutation.sibling_entry_id)
    return index != UI_TREE_NO_ITEM && sibling != UI_TREE_NO_ITEM &&
        ui_tree_projection_move_relative(
            projection, index, sibling, mutation.direction)
}

// Free detached additions when the durable model rejects the prepared edit.
ui_tree_projection_abort_mutation :: proc(
    projection: ^Ui_Tree_Projection) {
    if projection == nil || !projection.allocator.initialized {
        return
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    for index in 0..<projection.prepared_node_count {
        ui_tree_projection_free_node(projection.prepared_nodes[index], allocator)
        projection.prepared_nodes[index] = nil
    }
    projection.prepared_node_count = 0
    projection.prepared_mutation = {}
    projection.mutation_prepared = false
}

// Add prepared nodes without allocation and preserve the registry root boundary.
ui_tree_projection_commit_add :: proc(
    projection: ^Ui_Tree_Projection) -> bool {
    base, nodes_committed := ui_tree_projection_commit_prepared_nodes(projection)
    if !nodes_committed {
        return false
    }
    root := ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID)
    favorites := ui_tree_projection_find(
        projection, collections.FAVORITES_COLLECTION_ID)
    placement := ui_tree_projection_find(
        projection, projection.prepared_mutation.entry_id)
    return root != UI_TREE_NO_ITEM && favorites != UI_TREE_NO_ITEM &&
        placement != UI_TREE_NO_ITEM &&
        ui_tree_projection_link_added_favorite(
            projection, base, root, favorites, placement)
}

// Append a reserved custom placement beneath its accepted root collection.
ui_tree_projection_commit_custom_add :: proc(
    projection: ^Ui_Tree_Projection) -> bool {
    _, nodes_committed := ui_tree_projection_commit_prepared_nodes(projection)
    if !nodes_committed {
        return false
    }
    mutation := projection.prepared_mutation
    parent_key := mutation.placement.parent_entry_id if
        mutation.placement.parent_entry_id != (uuid.Identifier{}) else
            mutation.placement.collection_id
    parent := ui_tree_projection_find(projection, parent_key)
    placement := ui_tree_projection_find(projection, mutation.entry_id)
    if parent == UI_TREE_NO_ITEM || placement == UI_TREE_NO_ITEM {
        return false
    }
    parent_node := projection.items[parent]
    if parent_node.last_child == UI_TREE_NO_ITEM {
        parent_node.first_child = placement
    } else {
        projection.items[parent_node.last_child].next_sibling = placement
    }
    parent_node.last_child = placement
    projection.items[placement].parent = parent
    projection.items[placement].next_sibling = UI_TREE_NO_ITEM
    return true
}

// Append reserved nodes and their UUID indexes after validating the complete batch.
ui_tree_projection_commit_prepared_nodes :: proc(
    projection: ^Ui_Tree_Projection) -> (int, bool) {
    if projection.prepared_node_count == 0 ||
        projection.prepared_node_count > projection.capacity - projection.count ||
        !ui_tree_projection_prepared_nodes_are_unique(projection) {
        return projection.count, false
    }
    base := projection.count
    for offset in 0..<projection.prepared_node_count {
        node := projection.prepared_nodes[offset]
        projection.items[projection.count] = node
        if !ui_tree_projection_index_insert(projection, node.key, projection.count) {
            return base, false
        }
        projection.count += 1
        projection.prepared_nodes[offset] = nil
    }
    projection.prepared_node_count = 0
    return base, true
}

// Link a newly appended placement under the Favorites shell.
ui_tree_projection_link_added_favorite :: proc(
    projection: ^Ui_Tree_Projection,
    base, root, favorites, placement: int) -> bool {
    root_node := projection.items[root]
    if favorites == base {
        projection.items[favorites].next_sibling = root_node.first_child
        root_node.first_child = favorites
        if root_node.last_child == UI_TREE_NO_ITEM {
            root_node.last_child = favorites
        }
        projection.items[favorites].parent = root
        projection.items[favorites].first_child = placement
    }
    favorites_node := projection.items[favorites]
    if favorites_node.last_child != UI_TREE_NO_ITEM &&
        favorites_node.last_child != placement {
        projection.items[favorites_node.last_child].next_sibling = placement
    }
    projection.items[favorites].last_child = placement
    projection.items[placement].parent = favorites
    projection.items[placement].next_sibling = UI_TREE_NO_ITEM
    return true
}

// Validate all reserved keys before publishing any prepared node.
ui_tree_projection_prepared_nodes_are_unique :: proc(
    projection: ^Ui_Tree_Projection) -> bool {
    for index in 0..<projection.prepared_node_count {
        node := projection.prepared_nodes[index]
        if node == nil ||
            ui_tree_projection_find(projection, node.key) != UI_TREE_NO_ITEM {
            return false
        }
        for previous in 0..<index {
            if projection.prepared_nodes[previous].key == node.key {
                return false
            }
        }
    }
    return true
}

// Remove an empty leaf and compact only the index table, never surviving nodes.
ui_tree_projection_remove :: proc(
    projection: ^Ui_Tree_Projection, index: int) -> bool {
    if index < 0 || index >= projection.count {
        return false
    }
    item := projection.items[index]
    if item.first_child != UI_TREE_NO_ITEM ||
        !ui_tree_projection_unlink(projection, index) {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    ui_tree_projection_free_node(item, allocator)
    for move_index in index..<projection.count - 1 {
        projection.items[move_index] = projection.items[move_index + 1]
    }
    projection.count -= 1
    ui_tree_projection_adjust_index(&projection.first_root, index)
    ui_tree_projection_adjust_index(&projection.last_root, index)
    for move_index in 0..<projection.count {
        node := projection.items[move_index]
        ui_tree_projection_adjust_index(&node.parent, index)
        ui_tree_projection_adjust_index(&node.first_child, index)
        ui_tree_projection_adjust_index(&node.last_child, index)
        ui_tree_projection_adjust_index(&node.next_sibling, index)
    }
    for &slot in projection.index {
        slot = {}
    }
    for move_index in 0..<projection.count {
        if !ui_tree_projection_index_insert(
            projection, projection.items[move_index].key, move_index) {
            return false
        }
    }
    return true
}

// Check that a node is reachable through its owner's ordered sibling chain.
ui_tree_projection_is_linked :: proc(
    projection: ^Ui_Tree_Projection, index: int) -> bool {
    if projection == nil || index < 0 || index >= projection.count {
        return false
    }
    item := projection.items[index]
    first := projection.first_root
    if item.parent != UI_TREE_NO_ITEM {
        if item.parent < 0 || item.parent >= projection.count {
            return false
        }
        first = projection.items[item.parent].first_child
    }
    current := first
    for _ in 0..<projection.count {
        if current == UI_TREE_NO_ITEM {
            return false
        }
        if current == index {
            return true
        }
        if current < 0 || current >= projection.count {
            return false
        }
        current = projection.items[current].next_sibling
    }
    return false
}

// Unlink one node from its parent's current sibling chain.
ui_tree_projection_unlink :: proc(
    projection: ^Ui_Tree_Projection, index: int) -> bool {
    item := projection.items[index]
    parent := item.parent
    first := &projection.first_root
    last := &projection.last_root
    if parent != UI_TREE_NO_ITEM {
        first = &projection.items[parent].first_child
        last = &projection.items[parent].last_child
    }
    previous := UI_TREE_NO_ITEM
    current := first^
    for _ in 0..<projection.count {
        if current == UI_TREE_NO_ITEM {
            return false
        }
        if current == index {
            if previous == UI_TREE_NO_ITEM {
                first^ = item.next_sibling
            } else {
                projection.items[previous].next_sibling = item.next_sibling
            }
            if last^ == index {
                last^ = previous
            }
            item.parent = UI_TREE_NO_ITEM
            item.next_sibling = UI_TREE_NO_ITEM
            return true
        }
        previous = current
        current = projection.items[current].next_sibling
    }
    return false
}

// Reindex one topology link after a dense slot has been removed.
ui_tree_projection_adjust_index :: proc(index: ^int, removed: int) {
    if index^ > removed {
        index^ -= 1
    } else if index^ == removed {
        index^ = UI_TREE_NO_ITEM
    }
}

// Move a sibling immediately before or after its accepted adjacent neighbor.
ui_tree_projection_move_relative :: proc(
    projection: ^Ui_Tree_Projection,
    index, sibling: int,
    direction: collections.Move_Direction) -> bool {
    if (direction != .Up && direction != .Down) ||
        index == sibling ||
        projection.items[index].parent != projection.items[sibling].parent ||
        !ui_tree_projection_unlink(projection, index) {
        return false
    }
    parent := projection.items[sibling].parent
    first := &projection.first_root
    last := &projection.last_root
    if parent != UI_TREE_NO_ITEM {
        first = &projection.items[parent].first_child
        last = &projection.items[parent].last_child
    }
    moved := projection.items[index]
    moved.parent = parent
    if direction == .Up {
        return ui_tree_projection_insert_before(
            projection, index, sibling, first)
    }
    moved.next_sibling = projection.items[sibling].next_sibling
    projection.items[sibling].next_sibling = index
    if last^ == sibling {
        last^ = index
    }
    return true
}

// Insert a detached sibling before its still-linked neighbor.
ui_tree_projection_insert_before :: proc(
    projection: ^Ui_Tree_Projection,
    index, sibling: int,
    first: ^int) -> bool {
    previous := UI_TREE_NO_ITEM
    current := first^
    for _ in 0..<projection.count {
        if current == sibling {
            projection.items[index].next_sibling = sibling
            if previous == UI_TREE_NO_ITEM {
                first^ = index
            } else {
                projection.items[previous].next_sibling = index
            }
            return true
        }
        if current == UI_TREE_NO_ITEM {
            return false
        }
        previous = current
        current = projection.items[current].next_sibling
    }
    return false
}

// Clear session identities that refer to a removed placement.
ui_tree_projection_repair_removed_identity :: proc(
    runtime: ^Euclid_Ui_Runtime_State, removed: uuid.Identifier) {
    if runtime.library.tree.selected_item_id == removed {
        runtime.library.tree.selected_item_id = {}
    }
    if runtime.semantic_focus != nil &&
        runtime.semantic_focus.active_tree_item == removed {
        runtime.semantic_focus.active_tree_item = {}
        runtime.library.tree.reveal_pending = false
    }
    if runtime.library.tree.reveal_stable_id == removed {
        runtime.library.tree.reveal_pending = false
    }
    if runtime.library.actions.drawer.entry_id == removed {
        runtime.library.actions.drawer = {}
        runtime.library.actions.reorder = {}
    }
}
