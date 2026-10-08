package treeview

import model "model"

// Logical_Rows owns bounded preorder indices, excluding outgoing visual-only descendants.
Logical_Rows :: struct {
    indices: [model.NODE_CAPACITY]int,
    count: int,
}

// effectively_expanded keeps user intent distinct from caller-forced ancestry.
effectively_expanded :: proc(node: Node) -> bool {
    return node.expanded || node.forced_expanded
}

// logical_append walks already admitted topology without allocation or application policy.
logical_append :: proc(description: Description, index: int, rows: ^Logical_Rows) {
    for current := index; current != model.NO_NODE;
        current = description.nodes[current].next_sibling {
        node := description.nodes[current]
        if !node.included {
            continue
        }
        assert(rows^.count < len(rows^.indices),
            "tree logical rows exceed admitted capacity")
        rows^.indices[rows^.count] = current
        rows^.count += 1
        if effectively_expanded(node) {
            logical_append(description, node.first_child, rows)
        }
    }
}

// logical_rows returns current logical order after each working-frame mutation.
logical_rows :: proc(description: Description) -> Logical_Rows {
    result: Logical_Rows
    logical_append(description, description.first_root, &result)
    return result
}

// logical_position distinguishes an absent item from the first visible row.
logical_position :: proc(rows: ^Logical_Rows, index: int) -> int {
    for candidate, position in rows^.indices[:rows^.count] {
        if candidate == index {
            return position
        }
    }
    return model.NO_NODE
}

// resolve_active prefers a visible retained item, then selection, then the first row.
resolve_active :: proc(description: Description, state: ^model.State) -> int {
    rows := logical_rows(description)
    active := find_key(description, state^.active_key)
    if logical_position(&rows, active) != model.NO_NODE {
        return active
    }
    for index in rows.indices[:rows.count] {
        if description.nodes[index].selected {
            return index
        }
    }
    if rows.count == 0 {
        return model.NO_NODE
    }
    return rows.indices[0]
}

// set_active stores only a stable key and optionally requests navigation reveal.
set_active :: proc(state: ^model.State, node: Node, reveal: bool) {
    state^.active_key = node.key
    if reveal {
        state^.reveal_key = node.key
        state^.reveal_pending = true
        state^.reveal_reason = .Navigation
    }
}
