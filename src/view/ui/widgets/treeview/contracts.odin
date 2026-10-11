package treeview

import model "model"
import viewmodel "../../model"

// Node borrows one label and describes caller-owned facts, not application objects.
Node :: struct {
    key: model.Item_Key,
    semantic_id: viewmodel.Ui_Node_Id,
    capture_id: int,
    label: string,
    parent: int,
    first_child: int,
    next_sibling: int,
    included: bool,
    expanded: bool,
    forced_expanded: bool,
    selected: bool,
    enabled: bool,
    selectable: bool,
}

// Description borrows ordered hierarchy storage until preparation and drawing finish.
Description :: struct {
    nodes: []Node,
    first_root: int,
    generation: u64,
    topology_revision: u64,
}

// Description_Status reports admission failures explicitly before interaction begins.
Description_Status :: enum {
    Ok,
    Capacity_Exceeded,
    Invalid_Index,
    Invalid_Identity,
    Duplicate_Identity,
    Invalid_Topology,
}

// Intent_Kind separates caller-owned mutation from intrinsic widget interaction.
Intent_Kind :: enum {
    Set_Expanded,
    Select,
}

// Intent addresses authoritative caller state by stable key, never a borrowed pointer.
Intent :: struct {
    kind: Intent_Kind,
    key: model.Item_Key,
    expanded: bool,
}

// One command can emit one intent; reserve two additional pointer actions.
INTENT_CAPACITY :: viewmodel.UI_FOCUS_COMMAND_CAPACITY + 2

// Frame owns working facts and ordered intents, but only borrows label storage.
Frame :: struct {
    nodes: [model.NODE_CAPACITY]Node,
    count: int,
    first_root: int,
    generation: u64,
    topology_revision: u64,
    intents: [INTENT_CAPACITY]Intent,
    intent_count: int,
}

// Intent_Status rejects mutations explicitly without changing working or caller facts.
Intent_Status :: enum {
    Ok,
    Capacity_Exceeded,
    Unknown_Item,
    Disabled_Item,
    Unsupported_Action,
}

// description_index_valid admits only the sentinel or one current node index.
description_index_valid :: proc(index, count: int) -> bool {
    return index == model.NO_NODE || index >= 0 && index < count
}

// description_node_status validates identities and links without mutating caller data.
description_node_status :: proc(description: Description, index: int) ->
    Description_Status {
    node := description.nodes[index]
    if !description_index_valid(node.parent, len(description.nodes)) ||
        !description_index_valid(node.first_child, len(description.nodes)) ||
        !description_index_valid(node.next_sibling, len(description.nodes)) {
        return .Invalid_Index
    }
    if node.key == (model.Item_Key{}) ||
        node.semantic_id == (viewmodel.Ui_Node_Id{}) || node.capture_id <= 0 {
        return .Invalid_Identity
    }
    for prior in description.nodes[:index] {
        if prior.key == node.key || prior.semantic_id == node.semantic_id ||
            prior.capture_id == node.capture_id {
            return .Duplicate_Identity
        }
    }
    return .Ok
}

// description_visit validates ordered ancestry and rejects cycles or shared children.
description_visit :: proc(
    description: Description, index, parent: int,
    visited: ^[model.NODE_CAPACITY]bool, count: ^int) -> bool {
    for current := index; current != model.NO_NODE;
        current = description.nodes[current].next_sibling {
        if visited[current] || description.nodes[current].parent != parent {
            return false
        }
        visited[current] = true
        count^ += 1
        if !description_visit(description, description.nodes[current].first_child,
            current, visited, count) {
            return false
        }
    }
    return true
}

// description_status validates bounded, uniquely identified, fully reachable topology.
description_status :: proc(description: Description) -> Description_Status {
    count := len(description.nodes)
    if count > model.NODE_CAPACITY {
        return .Capacity_Exceeded
    }
    if !description_index_valid(description.first_root, count) {
        return .Invalid_Index
    }
    for index in 0..<count {
        status := description_node_status(description, index)
        if status != .Ok {
            return status
        }
    }
    visited: [model.NODE_CAPACITY]bool
    reached: int
    if !description_visit(description, description.first_root, model.NO_NODE,
        &visited, &reached) || reached != count {
        return .Invalid_Topology
    }
    return .Ok
}
