package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

// accesskit_physical_bounds converts logical UI coordinates to physical pixels.
accesskit_physical_bounds :: proc(
    bounds: portable.Bounds, scale: f64) -> accesskit.Rect {
    return {
        bounds.x0 * scale, bounds.y0 * scale,
        bounds.x1 * scale, bounds.y1 * scale,
    }
}

// accesskit_configure_child copies the complete portable child record.
accesskit_configure_child :: proc(
    child: ^accesskit.Node, publication: ^portable.Static_Publication) {
    if publication^.child_role == .Button {
        accesskit.accesskit_node_set_label_with_length(
            child, cast(cstring)&publication^.label[0],
            uintptr(publication^.label_length))
        if !publication^.child_enabled {
           accesskit.accesskit_node_set_disabled(child)
        }
        if publication^.child_supports_focus {
            accesskit.accesskit_node_add_action(child, .Focus)
        }
        if publication^.child_supports_activate {
            accesskit.accesskit_node_add_action(child, .Click)
        }
    } else {
        accesskit.accesskit_node_set_value_with_length(
            child, cast(cstring)&publication^.label[0],
            uintptr(publication^.label_length))
    }
    accesskit.accesskit_node_set_bounds(
        child, cast(accesskit.Rect)publication^.child_bounds)
}

// accesskit_static_nodes creates the complete root and child records.
accesskit_static_nodes :: proc(
    publication: ^portable.Static_Publication) -> (^accesskit.Node, ^accesskit.Node) {
    root := accesskit.accesskit_node_new(.Application)
    child_role := accesskit.Role.Label
    if publication^.child_role == .Button {
       child_role = .Button
    }
    child := accesskit.accesskit_node_new(child_role)
    if root == nil || child == nil {
        if root != nil {
           accesskit.accesskit_node_free(root)
        }
        if child != nil {
           accesskit.accesskit_node_free(child)
        }
        return nil, nil
    }
    child_id := accesskit.Node_Id(publication^.child_id)
    accesskit.accesskit_node_set_children(root, 1, &child_id)
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    accesskit_configure_child(child, publication)
    return root, child
}

// accesskit_root_tree_update builds a complete root-only update after removal.
accesskit_root_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    root := accesskit.accesskit_node_new(.Application)
    if root == nil {
       return nil
    }
    accesskit.accesskit_node_set_bounds(
        root, cast(accesskit.Rect)publication^.root_bounds)
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(1, root_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    return update
}

// accesskit_child_tree_update builds one complete rooted child update.
accesskit_child_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    child_id := accesskit.Node_Id(publication^.child_id)
    focus_id := root_id
    if publication^.window_focused && publication^.child_focused {
        focus_id = child_id
    }
    root, child := accesskit_static_nodes(publication)
    if root == nil {
       return nil
    }
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(2, focus_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        accesskit.accesskit_node_free(child)
        return nil
    }
    tree := accesskit.accesskit_tree_info_new(root_id)
    if tree == nil {
        accesskit.accesskit_tree_update_free(update)
        accesskit.accesskit_node_free(root)
        accesskit.accesskit_node_free(child)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    accesskit.accesskit_tree_update_push_node(update, child_id, child)
    accesskit.accesskit_tree_update_set_tree_info(update, tree)
    accesskit.accesskit_tree_update_set_tree_id(update, {})
    return update
}

// accesskit_tree_update translates one validated static publication.
accesskit_tree_update :: proc(
    publication: ^portable.Static_Publication) -> ^accesskit.Tree_Update {
    if portable.publication_validate(publication) != .Ok {
       return nil
    }
    if !publication^.child_present {
       return accesskit_root_tree_update(publication)
    }
    return accesskit_child_tree_update(publication)
}

// accesskit_ordinary_control_role maps ordinary controls to AccessKit.
accesskit_ordinary_control_role :: proc(
    role: portable.Publication_Role) -> (accesskit.Role, bool) {
    #partial switch role {
    case .Checkbox: return .Check_Box, true
    case .Slider: return .Slider, true
    case .Status: return .Status, true
    case .Button: return .Button, true
    case .Accordion_Header: return .Disclosure_Triangle, true
    case .Panel: return .Pane, true
    case .Label: return .Label, true
    case .Menu: return .Menu, true
    case .Menu_Item: return .Menu_Item, true
    }
    return .Unknown, false
}

// accesskit_control_role maps one portable control role to AccessKit.
accesskit_control_role :: proc(role: portable.Publication_Role) -> accesskit.Role {
    mapped, supported := accesskit_ordinary_control_role(role)
    if supported {
       return mapped
    }
    #partial switch role {
    case .Search_Input: return .Search_Input
    case .Text_Run: return .Text_Run
    case .Tree: return .Tree
    case .Tree_Item: return .Tree_Item
    case: return .Unknown
    }
}

// accesskit_configure_basic_actions advertises ordinary owner actions.
accesskit_configure_basic_actions :: proc(
    node: ^accesskit.Node, actions: portable.Publication_Action_Set) {
    if .Focus in actions {
       accesskit.accesskit_node_add_action(node, .Focus)
    }
    if .Show_Context_Menu in actions {
        accesskit.accesskit_node_add_action(node, .Show_Context_Menu)
        accesskit.accesskit_node_set_has_popup(node, .Menu)
    }
    if .Activate in actions || .Toggle in actions {
        accesskit.accesskit_node_add_action(node, .Click)
    }
    if .Increment in actions {
       accesskit.accesskit_node_add_action(node, .Increment)
    }
    if .Decrement in actions {
       accesskit.accesskit_node_add_action(node, .Decrement)
    }
    if .Set_Value in actions {
       accesskit.accesskit_node_add_action(node, .Set_Value)
    }
}

// accesskit_configure_extended_actions advertises text and composite actions.
accesskit_configure_extended_actions :: proc(
    node: ^accesskit.Node, actions: portable.Publication_Action_Set) {
    if .Replace_Selected_Text in actions {
        accesskit.accesskit_node_add_action(node, .Replace_Selected_Text)
    }
    if .Set_Text_Selection in actions {
        accesskit.accesskit_node_add_action(node, .Set_Text_Selection)
    }
    if .Select in actions {
       accesskit.accesskit_node_add_action(node, .Click)
    }
    if .Expand in actions {
       accesskit.accesskit_node_add_action(node, .Expand)
    }
    if .Collapse in actions {
       accesskit.accesskit_node_add_action(node, .Collapse)
    }
    if .Scroll in actions {
        accesskit.accesskit_node_add_action(node, .Scroll_Up)
        accesskit.accesskit_node_add_action(node, .Scroll_Down)
        accesskit.accesskit_node_add_action(node, .Set_Value)
    }
}

// accesskit_configure_control_actions advertises owner-supported native actions.
accesskit_configure_control_actions :: proc(
    node: ^accesskit.Node, actions: portable.Publication_Action_Set) {
    accesskit_configure_basic_actions(node, actions)
    accesskit_configure_extended_actions(node, actions)
}

// accesskit_configure_control_state publishes role-specific control state.
accesskit_configure_control_state :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    if !control.enabled {
       accesskit.accesskit_node_set_disabled(node)
    }
    if control.role == .Checkbox {
        toggled := accesskit.Toggled.False
        if control.checked {
           toggled = .True
        }
        accesskit.accesskit_node_set_toggled(node, toggled)
    }
    if control.selected {
       accesskit.accesskit_node_set_selected(node, true)
    }
    if control.role == .Accordion_Header {
        accesskit.accesskit_node_set_expanded(node, control.expanded)
    }
    if control.role == .Tree_Item && .Toggle in control.actions {
        accesskit.accesskit_node_set_expanded(node, control.expanded)
    }
    if control.role == .Status {
        accesskit.accesskit_node_set_live(node, .Polite)
        if control.busy {
           accesskit.accesskit_node_set_busy(node)
        }
    }
}

// accesskit_configure_control_range publishes one complete finite numeric range.
accesskit_configure_control_range :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    range := control.range
    if !range.present {
       return
    }
    if control.role == .Tree {
        accesskit.accesskit_node_set_scroll_y(node, range.current)
        accesskit.accesskit_node_set_scroll_y_min(node, range.minimum)
        accesskit.accesskit_node_set_scroll_y_max(node, range.maximum)
    }
    accesskit.accesskit_node_set_min_numeric_value(node, range.minimum)
    accesskit.accesskit_node_set_max_numeric_value(node, range.maximum)
    accesskit.accesskit_node_set_numeric_value(node, range.current)
    accesskit.accesskit_node_set_numeric_value_step(node, range.step)
    orientation := accesskit.Orientation.Horizontal
    if range.vertical {
        orientation = .Vertical
    }
    accesskit.accesskit_node_set_orientation(node, orientation)
}

// accesskit_configure_control_set_facts publishes TreeItem structural position.
accesskit_configure_control_set_facts :: proc(
    node: ^accesskit.Node, control: portable.Control_Publication) {
    if control.role != .Tree_Item {
        return
    }
    if control.level > 0 {
        accesskit.accesskit_node_set_level(node, uintptr(control.level))
    }
    if control.set_size > 0 {
        accesskit.accesskit_node_set_size_of_set(node, uintptr(control.set_size))
    }
    if control.position_in_set > 0 {
        accesskit.accesskit_node_set_position_in_set(
            node, uintptr(control.position_in_set))
    }
}

// Resolve the text-run node used as the selection anchor for one search input.
accesskit_control_selection_id :: proc(
    publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) -> u64 {
    for candidate in publication^.controls[:publication^.control_count] {
        if candidate.parent_native_id == control.native_id &&
           candidate.role == .Text_Run {
            return candidate.native_id
        }
    }
    return control.native_id
}

// accesskit_configure_control_text publishes copied editable text and selection.
accesskit_configure_control_text :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    if !control.text_present {
        return
    }
    placeholder := portable.control_publication_text(
        publication, control.placeholder_offset, control.placeholder_length)
    if len(placeholder) > 0 {
        accesskit.accesskit_node_set_placeholder_with_length(
            node, cast(cstring)raw_data(placeholder), uintptr(len(placeholder)))
    }
    if control.role != .Search_Input && control.character_count > 0 {
        first := int(control.character_offset)
        accesskit.accesskit_node_set_character_lengths(node,
            uintptr(control.character_count), &publication^.character_lengths[first])
    }
    if control.role != .Search_Input && control.word_start_count > 0 {
        first := int(control.word_start_offset)
        accesskit.accesskit_node_set_word_starts(node,
            uintptr(control.word_start_count), &publication^.word_starts[first])
    }
    if control.role != .Search_Input {
       return
    }
    selection_id := accesskit_control_selection_id(publication, control)
    native_id := accesskit.Node_Id(selection_id)
    accesskit.accesskit_node_set_text_selection(node, {
        anchor = {native_id, uintptr(control.anchor_character)},
        focus = {native_id, uintptr(control.cursor_character)},
    })
}

// accesskit_configure_control copies one complete portable record into AccessKit.
accesskit_configure_control :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    label := portable.control_publication_text(
        publication, control.label_offset, control.label_length)
    value := portable.control_publication_text(
        publication, control.value_offset, control.value_length)
    accesskit.accesskit_node_set_label_with_length(
        node, cast(cstring)raw_data(label), uintptr(len(label)))
    if control.role == .Text_Run ||
       control.role != .Search_Input && len(value) > 0 {
        accesskit.accesskit_node_set_value_with_length(
            node, cast(cstring)raw_data(value), uintptr(len(value)))
    }
    accesskit_configure_control_actions(node, control.actions)
    accesskit_configure_control_state(node, control)
    accesskit_configure_control_range(node, control)
    accesskit_configure_control_set_facts(node, control)
    accesskit_configure_control_text(node, publication, control)
    accesskit.accesskit_node_set_bounds(node,
        accesskit_physical_bounds(control.bounds, publication^.bounds_scale))
}

// accesskit_configure_control_hierarchy publishes children and active descendant.
accesskit_configure_control_hierarchy :: proc(
    node: ^accesskit.Node, publication: ^portable.Control_Tree_Publication,
    control: portable.Control_Publication) {
    child_ids: [portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id
    child_count := 0
    for candidate in publication^.controls[:publication^.control_count] {
        if candidate.parent_native_id != control.native_id {
           continue
        }
        child_ids[child_count] = accesskit.Node_Id(candidate.native_id)
        child_count += 1
    }
    accesskit.accesskit_node_set_children(node, uintptr(child_count), &child_ids[0])
    if control.active_descendant_native_id != 0 {
        accesskit.accesskit_node_set_active_descendant(
            node, accesskit.Node_Id(control.active_descendant_native_id))
    } else {
        accesskit.accesskit_node_clear_active_descendant(node)
    }
    if control.controls_native_id != 0 {
        relation := accesskit.Node_Id(control.controls_native_id)
        accesskit.accesskit_node_set_controls(node, 1, &relation)
    }
}

// accesskit_control_root_update creates and transfers one complete synthetic root.
accesskit_control_root_update :: proc(
    publication: ^portable.Control_Tree_Publication,
    child_ids: ^[portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id,
    child_count: int,
    focus_id: accesskit.Node_Id) -> ^accesskit.Tree_Update {
    root_id := accesskit.Node_Id(publication^.root_id)
    root := accesskit.accesskit_node_new(.Application)
    if root == nil {
       return nil
    }
    accesskit.accesskit_node_set_children(root, uintptr(child_count), &child_ids^[0])
    accesskit.accesskit_node_set_bounds(
        root, accesskit_physical_bounds(
            publication^.root_bounds, publication^.bounds_scale))
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(
        uintptr(publication^.control_count + 1), focus_id)
    if update == nil {
        accesskit.accesskit_node_free(root)
        return nil
    }
    tree := accesskit.accesskit_tree_info_new(root_id)
    if tree == nil {
        accesskit.accesskit_tree_update_free(update)
        accesskit.accesskit_node_free(root)
        return nil
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    accesskit.accesskit_tree_update_set_tree_info(update, tree)
    accesskit.accesskit_tree_update_set_tree_id(update, {})
    return update
}

// accesskit_control_push_nodes transfers every complete child into one update.
accesskit_control_push_nodes :: proc(
    update: ^accesskit.Tree_Update,
    publication: ^portable.Control_Tree_Publication) -> bool {
    for control in publication^.controls[:publication^.control_count] {
        child := accesskit.accesskit_node_new(accesskit_control_role(control.role))
        if child == nil {
           return false
        }
        accesskit_configure_control(child, publication, control)
        accesskit_configure_control_hierarchy(child, publication, control)
        accesskit.accesskit_tree_update_push_node(
            update, accesskit.Node_Id(control.native_id), child)
    }
    return true
}

// accesskit_control_tree_update builds one complete rooted control update.
accesskit_control_tree_update :: proc(
    publication: ^portable.Control_Tree_Publication) -> ^accesskit.Tree_Update {
    if portable.control_tree_validate(publication) != .Ok {
       return nil
    }
    focus_id := accesskit.Node_Id(publication^.root_id)
    child_ids: [portable.CONTROL_NODE_CAPACITY]accesskit.Node_Id
    child_count := 0
    for control in publication^.controls[:publication^.control_count] {
        if control.parent_native_id == publication^.root_id {
            child_ids[child_count] = accesskit.Node_Id(control.native_id)
            child_count += 1
        }
        if publication^.window_focused && control.focused {
            focus_id = accesskit.Node_Id(control.native_id)
        }
    }
    update := accesskit_control_root_update(
        publication, &child_ids, child_count, focus_id)
    if update == nil {
       return nil
    }
    if !accesskit_control_push_nodes(update, publication) {
        accesskit.accesskit_tree_update_free(update)
        return nil
    }
    return update
}