package treeview

import model "model"

// frame_begin admits topology once, then copies facts without retaining caller arrays.
frame_begin :: proc(description: Description, frame: ^Frame) -> Description_Status {
    status := description_status(description)
    if status != .Ok {
        return status
    }
    frame^ = {
        count = len(description.nodes), first_root = description.first_root,
        generation = description.generation,
        topology_revision = description.topology_revision,
    }
    copy(frame^.nodes[:frame^.count], description.nodes)
    return .Ok
}

// frame_description borrows working facts only while the addressed frame remains alive.
frame_description :: proc(frame: ^Frame) -> Description {
    return {
        nodes = frame^.nodes[:frame^.count], first_root = frame^.first_root,
        generation = frame^.generation, topology_revision = frame^.topology_revision,
    }
}

// find_key resolves a stable identity within already admitted frame-local storage.
find_key :: proc(description: Description, key: model.Item_Key) -> int {
    for node, index in description.nodes {
        if node.key == key {
            return index
        }
    }
    return model.NO_NODE
}

// frame_intent_status checks capability and storage before any transactional mutation.
frame_intent_status :: proc(frame: ^Frame, intent: Intent) -> Intent_Status {
    if frame^.intent_count >= len(frame^.intents) {
        return .Capacity_Exceeded
    }
    index := find_key(frame_description(frame), intent.key)
    if index == model.NO_NODE {
        return .Unknown_Item
    }
    node := frame^.nodes[index]
    if !node.enabled {
        return .Disabled_Item
    }
    if intent.kind == .Set_Expanded && node.first_child == model.NO_NODE ||
        intent.kind == .Select && !node.selectable {
        return .Unsupported_Action
    }
    return .Ok
}

// frame_issue preserves ordered effects locally until the caller commits the intents.
frame_issue :: proc(frame: ^Frame, intent: Intent) -> Intent_Status {
    status := frame_intent_status(frame, intent)
    if status != .Ok {
        return status
    }
    index := find_key(frame_description(frame), intent.key)
    switch intent.kind {
    case .Set_Expanded:
        frame^.nodes[index].expanded = intent.expanded
    case .Select:
        for &node in frame^.nodes[:frame^.count] {
            node.selected = node.key == intent.key
        }
    }
    frame^.intents[frame^.intent_count] = intent
    frame^.intent_count += 1
    return .Ok
}
