package viewscenario

import collections "../../collections"
import viewmodel "../ui/model"
import uilibrary "../ui/library"
import uisemantics "../ui/semantics"
import uuid "core:encoding/uuid"

// Route only the explicit lifecycle-control vocabulary through published UI controls.
scenario_collection_control :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string) -> (bool, bool) {
    switch operation {
    case "create_focus", "create_press", "create_release":
        return true, scenario_collection_create_control(runtime, item, operation)
    case "delete_focus", "delete_activate", "delete_press", "delete_release":
        return true, scenario_collection_delete_control(runtime, item, operation)
    }
    return false, false
}

// Observe bounded lifecycle facts by UUID rather than duplicate visible labels.
scenario_collection_assertion :: proc(
    runtime: ^Scenario_Runtime, operation, argument: string) -> bool {
    if operation == "membership_open" || operation == "membership_closed" {
        return runtime.state.ui_runtime.membership.active ==
            (operation == "membership_open")
    }
    if operation == "one_custom_empty" || operation == "two_custom_empty" {
        return scenario_empty_collections_assertion(
            runtime, operation == "two_custom_empty")
    }
    confirmation := runtime.state.ui_runtime.library.actions.delete_confirmation
    item := scenario_favorites_item(runtime, argument)
    armed := item != nil && confirmation.armed && confirmation.collection_id == item.key
    return armed if operation == "delete_armed" else !armed
}

// Resolve an ordinal destination to its UUID without treating a duplicate label as a key.
scenario_collection_endpoint :: proc(
    set: ^collections.Set, first: bool) -> uuid.Identifier {
    chosen := -1
    for head, index in set^.collections[:set^.collection_count] {
        if head.role != .User {
            continue
        }
        if chosen < 0 || first && head.order < set^.collections[chosen].order ||
            !first && head.order > set^.collections[chosen].order {
            chosen = index
        }
    }
    return set^.collections[chosen].id if chosen >= 0 else uuid.Identifier{}
}

// Route collection creation through its published button, never direct model mutation.
scenario_collection_create_control :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string) -> bool {
    if item^.kind != .Collections {
        return false
    }
    if operation == "create_release" {
        if !runtime^.pointer_override || !runtime^.pointer_down {
            return false
        }
        runtime^.pointer_down = false
        runtime^.pointer_pressed = false
        runtime^.pointer_released = true
        return true
    }
    focus := runtime^.state^.ui_runtime.semantic_focus
    id: viewmodel.Ui_Node_Id = {
        domain = .Library_Action,
        local_id = uilibrary.TREE_COLLECTION_CREATE,
        stable_id = item^.key,
        generation = runtime^.state^.julia_interface^.content_generation,
    }
    if operation == "create_focus" {
        return uisemantics.semantic_apply_external_action(focus, id, .Focus)
    }
    snapshot := uisemantics.semantic_snapshot(focus)
    index := uisemantics.semantic_node_index(snapshot, id)
    if index < 0 || .Enabled not_in snapshot^.nodes[index].states {
        return false
    }
    pointer := "press" if operation == "create_press" else "release"
    return scenario_favorites_pointer(runtime, snapshot^.nodes[index].bounds, pointer)
}

// Pointer, keyboard focus and native activation resolve the same published guarded button.
scenario_collection_delete_control :: proc(
    runtime: ^Scenario_Runtime, item: ^viewmodel.Ui_Tree_Item,
    operation: string) -> bool {
    if item.kind != .Collection || item.key == collections.FAVORITES_COLLECTION_ID {
        return false
    }
    focus := runtime.state.ui_runtime.semantic_focus
    id: viewmodel.Ui_Node_Id = {
        domain = .Library_Action,
        local_id = uilibrary.TREE_COLLECTION_DELETE,
        stable_id = item.key,
        generation = runtime.state.julia_interface.content_generation,
    }
    if operation == "delete_focus" || operation == "delete_activate" {
        kind := viewmodel.Ui_Focus_Command_Kind.Focus if
            operation == "delete_focus" else viewmodel.Ui_Focus_Command_Kind.Activate
        return scenario_library_queue_command(runtime, {
            target = id,
            kind = kind,
        })
    }
    snapshot := uisemantics.semantic_snapshot(focus)
    index := uisemantics.semantic_node_index(snapshot, id)
    if index < 0 || .Enabled not_in snapshot.nodes[index].states {
        return false
    }
    return scenario_favorites_pointer(runtime, snapshot.nodes[index].bounds,
        "press" if operation == "delete_press" else "release")
}

// Require the exact empty-head count and matching visible stable projection records.
scenario_empty_collections_assertion :: proc(
    runtime: ^Scenario_Runtime, two: bool) -> bool {
    state := runtime^.state
    set := &state^.preferences_runtime.collections_state
    expected := 2 if two else 1
    if set^.collection_count != expected + 1 || set^.entry_count != 0 ||
        collections.validate(set) != .None {
        return false
    }
    projection := &state^.ui_runtime.library.tree.projection
    for collection in set^.collections[:set^.collection_count] {
        if collection.role != .User {
            continue
        }
        index := uilibrary.tree_projection_find(projection, collection.id)
        if index < 0 || projection^.items[index].kind != .Collection ||
            string(collection.name[:collection.name_length]) != "New Collection" {
            return false
        }
    }
    return uilibrary.tree_projection_find(
        projection, collections.FAVORITES_COLLECTION_ID) == uilibrary.TREE_NO_ITEM
}
