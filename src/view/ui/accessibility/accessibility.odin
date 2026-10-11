package uiaccessibility

import native "../../native"
import accessibility "../../../accessibility"
import core "../../../core"
import uuid "core:encoding/uuid"
import log "core:log"
import viewmodel "../model"
import uisemantics "../semantics"

// accessibility_ui_identity preserves one complete semantic target for native lookup.
accessibility_ui_identity :: proc(
    id: viewmodel.Ui_Node_Id) -> accessibility.Qualified_Identity {
    if id == (viewmodel.Ui_Node_Id{}) {
        return {}
    }
    return {
        domain = .Ui,
        owner_domain = u16(id.domain),
        local_id = id.local_id,
        stable_uuid = cast([16]u8)id.stable_id,
        generation = id.generation,
    }
}

// accessibility_tree_focus_owner preserves one Tab stop for native item focus.
accessibility_tree_focus_owner :: proc(
    semantic: ^viewmodel.Ui_Semantic_Focus_State,
    target: viewmodel.Ui_Node_Id) -> viewmodel.Ui_Node_Id {
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, target)
    if index < 0 || snapshot^.nodes[index].role != .Tree_Item {
        return target
    }
    semantic^.active_tree_item = target.stable_id
    parent := snapshot^.nodes[index].parent
    for parent != (viewmodel.Ui_Node_Id{}) {
        parent_index := uisemantics.semantic_node_index(snapshot, parent)
        if parent_index < 0 {
            return target
        }
        node := snapshot^.nodes[parent_index]
        if node.role == .Tree {
            return node.id
        }
        parent = node.parent
    }
    return target
}

// accessibility_primary_command_kind maps ordinary native actions.
accessibility_primary_command_kind :: proc(
    kind: native.Sdl_Accessibility_Action_Kind) -> viewmodel.Ui_Focus_Command_Kind {
    #partial switch kind {
    case .Focus: return .Focus
    case .Activate: return .Activate
    case .Toggle: return .Toggle
    case .Increment: return .Increment
    case .Decrement: return .Decrement
    case .Set_Value: return .Set_Value
    case: return .None
    }
}

// accessibility_extended_command_kind maps text and composite native actions.
accessibility_extended_command_kind :: proc(
    kind: native.Sdl_Accessibility_Action_Kind) -> viewmodel.Ui_Focus_Command_Kind {
    #partial switch kind {
    case .Replace_Selected_Text: return .Replace_Selected_Text
    case .Replace_Text: return .Replace_Text
    case .Set_Text_Selection: return .Set_Text_Selection
    case .Select: return .Select
    case .Expand: return .Expand
    case .Collapse: return .Collapse
    case .Scroll: return .Scroll_Page
    case .Set_Scroll_Value: return .Set_Scroll_Value
    case .Show_Context_Menu: return .Show_Context_Menu
    }
    return .None
}

// accessibility_command_kind maps one validated native action to UI vocabulary.
accessibility_command_kind :: proc(
    kind: native.Sdl_Accessibility_Action_Kind) -> viewmodel.Ui_Focus_Command_Kind {
    mapped := accessibility_primary_command_kind(kind)
    if mapped != .None {
        return mapped
    }
    return accessibility_extended_command_kind(kind)
}

// apply_accessibility_action converges one validated request with its UI owner.
apply_accessibility_action :: proc(
    state: ^core.Euclid_General_State, action: ^native.Sdl_Accessibility_Action) {
    identity := action^.identity
    target := viewmodel.Ui_Node_Id{
        domain = cast(viewmodel.Ui_Node_Domain)identity.owner_domain,
        local_id = identity.local_id,
        stable_id = cast(uuid.Identifier)identity.stable_uuid,
        generation = identity.generation,
    }
    kind := accessibility_command_kind(action^.kind)
    semantic := state^.ui_runtime.semantic_focus
    if kind == .Focus {
        target = accessibility_tree_focus_owner(semantic, target)
    }
    if kind == .Replace_Selected_Text || kind == .Replace_Text ||
       kind == .Set_Text_Selection {
        _ = uisemantics.semantic_apply_external_text_action(semantic, {
            target = target,
            kind = kind,
            payload = string(action^.payload[:action^.payload_length]),
            anchor = action^.selection_anchor,
            focus = action^.selection_focus,
        })
        return
    }
    _ = uisemantics.semantic_apply_external_action(
        semantic, target, kind, action^.numeric_value)
}

// drain_accessibility_actions converges validated native requests with UI commands.
drain_accessibility_actions :: proc(
    state: ^core.Euclid_General_State, platform: ^native.Sdl_Platform) {
    for {
        action: native.Sdl_Accessibility_Action
        status := native.sdl_platform_drain_accessibility_action(platform, &action)
        if status == .Empty || status == .Closing {
            return
        }
        if status != .Ok {
            continue
        }
        apply_accessibility_action(state, &action)
    }
}

// accessibility_button_bounds clips one semantic rectangle to its owner viewport.
accessibility_button_bounds :: proc(
    node: viewmodel.Ui_Semantic_Node) -> accessibility.Bounds {
    x0 := max(node.bounds.x, node.clip_bounds.x)
    y0 := max(node.bounds.y, node.clip_bounds.y)
    x1 := min(node.bounds.x + node.bounds.width,
        node.clip_bounds.x + node.clip_bounds.width)
    y1 := min(node.bounds.y + node.bounds.height,
        node.clip_bounds.y + node.clip_bounds.height)
    return {f64(x0), f64(y0), f64(max(x0, x1)), f64(max(y0, y1))}
}

// accessibility_ordinary_publication_role maps ordinary semantic controls.
accessibility_ordinary_publication_role :: proc(
    role: viewmodel.Ui_Node_Role) -> (accessibility.Publication_Role, bool) {
    #partial switch role {
    case .Button: return .Button, true
    case .Checkbox: return .Checkbox, true
    case .Slider: return .Slider, true
    case .Accordion_Header: return .Accordion_Header, true
    case .Panel: return .Panel, true
    case .Status: return .Status, true
    case .Menu: return .Menu, true
    case .Menu_Item: return .Menu_Item, true
    case: return {}, false
    }
}

// accessibility_composite_publication_role maps text and tree controls.
accessibility_composite_publication_role :: proc(
    role: viewmodel.Ui_Node_Role) -> (accessibility.Publication_Role, bool) {
    #partial switch role {
    case .Input: return .Search_Input, true
    case .Text_Run: return .Text_Run, true
    case .Tree: return .Tree, true
    case .Tree_Item: return .Tree_Item, true
    case .Document, .Terminal: return .Panel, true
    case .Surface:
    }
    return {}, false
}

// accessibility_publication_role maps one ordinary semantic role for projection.
accessibility_publication_role :: proc(
    role: viewmodel.Ui_Node_Role) -> (accessibility.Publication_Role, bool) {
    mapped, supported := accessibility_ordinary_publication_role(role)
    if supported {
        return mapped, true
    }
    return accessibility_composite_publication_role(role)
}

// accessibility_ordinary_publication_actions maps ordinary owner actions.
accessibility_ordinary_publication_actions :: proc(
    actions: viewmodel.Ui_Node_Action_Set) -> accessibility.Publication_Action_Set {
    result: accessibility.Publication_Action_Set
    if .Focus in actions {
        result += {.Focus}
    }
    if .Activate in actions {
        result += {.Activate}
    }
    if .Toggle in actions {
        result += {.Toggle}
    }
    if .Increment in actions {
        result += {.Increment}
    }
    if .Decrement in actions {
        result += {.Decrement}
    }
    if .Set_To_Bound in actions {
        result += {.Set_To_Bound}
    }
    if .Set_Value in actions {
        result += {.Set_Value}
    }
    return result
}

// accessibility_extended_publication_actions maps text and composite actions.
accessibility_extended_publication_actions :: proc(
    actions: viewmodel.Ui_Node_Action_Set) -> accessibility.Publication_Action_Set {
    result: accessibility.Publication_Action_Set
    if .Replace_Selected_Text in actions {
        result += {.Replace_Selected_Text}
    }
    if .Set_Text_Selection in actions {
        result += {.Set_Text_Selection}
    }
    if .Select in actions {
        result += {.Select}
    }
    if .Expand in actions {
        result += {.Expand}
    }
    if .Collapse in actions {
        result += {.Collapse}
    }
    if .Scroll in actions {
        result += {.Scroll}
    }
    return result
}

// accessibility_publication_actions maps advertised owner actions without widening.
accessibility_publication_actions :: proc(
    actions: viewmodel.Ui_Node_Action_Set) -> accessibility.Publication_Action_Set {
    result := accessibility_ordinary_publication_actions(actions) |
        accessibility_extended_publication_actions(actions)
    if .Show_Context_Menu in actions {
        result += {.Show_Context_Menu}
    }
    return result
}

// Publish pane entry points without retaining any content or text-selection facts.
accessibility_pane_record :: proc(
    semantic: ^viewmodel.Ui_Semantic_Focus_State,
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    node: viewmodel.Ui_Semantic_Node) -> accessibility.Control_Publication_Input {
    return {
        role = .Panel, bounds = accessibility_button_bounds(node),
        label = uisemantics.semantic_node_text(
            snapshot, node.label_offset, node.label_length),
        enabled = .Enabled in node.states, focusable = .Focusable in node.states,
        focused = semantic^.logical_focus == node.id,
        actions = {.Focus, .Show_Context_Menu},
    }
}

// accessibility_control_record copies one portable semantic control record.
accessibility_control_record :: proc(
    semantic: ^viewmodel.Ui_Semantic_Focus_State,
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    node: viewmodel.Ui_Semantic_Node,
    role: accessibility.Publication_Role) -> accessibility.Control_Publication_Input {
    if node.role == .Document || node.role == .Terminal {
        return accessibility_pane_record(semantic, snapshot, node)
    }
    record := accessibility.Control_Publication_Input{
        role = role,
        bounds = accessibility_button_bounds(node),
        label = uisemantics.semantic_node_text(
            snapshot, node.label_offset, node.label_length),
        value = uisemantics.semantic_node_text(
            snapshot, node.value_offset, node.value_length),
        placeholder = uisemantics.semantic_node_text(
            snapshot, node.placeholder_offset, node.placeholder_length),
        actions = accessibility_publication_actions(node.actions),
        range = {node.numeric_range.minimum, node.numeric_range.maximum,
            node.numeric_range.current, node.numeric_range.step,
            node.numeric_range.orientation == .Vertical, node.numeric_range.present},
        enabled = .Enabled in node.states,
        focusable = .Focusable in node.states,
        focused = semantic^.logical_focus == node.id,
        checked = .Checked in node.states,
        selected = .Selected in node.states,
        expanded = .Expanded in node.states,
        busy = .Busy in node.states,
        text_present = node.text_present,
        text_cursor_byte = int(node.text_cursor_byte),
        text_anchor_byte = int(node.text_anchor_byte),
        level = node.level,
        position_in_set = node.position_in_set,
        set_size = node.set_size,
    }
    return record
}

// accessibility_control_input copies one committed ordinary semantic record.
accessibility_control_input :: proc(
    semantic: ^viewmodel.Ui_Semantic_Focus_State,
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    node: viewmodel.Ui_Semantic_Node,
    role: accessibility.Publication_Role) -> native.Sdl_Accessibility_Control_Input {
    return {
        identity = accessibility_ui_identity(node.id),
        parent_identity = accessibility_ui_identity(node.parent),
        active_descendant_identity = accessibility_ui_identity(
            node.active_descendant),
        controls_identity = accessibility_ui_identity(node.controls),
        control = accessibility_control_record(semantic, snapshot, node, role),
    }
}

// publish_accessibility_controls projects all committed ordinary controls.
publish_accessibility_controls :: proc(
    state: ^core.Euclid_General_State, platform: ^native.Sdl_Platform) {
    semantic := state^.ui_runtime.semantic_focus
    snapshot := uisemantics.semantic_snapshot(semantic)
    root_bounds := accessibility.Bounds{0, 0,
        f64(platform^.metrics.logical_width), f64(platform^.metrics.logical_height)}
    controls: [accessibility.CONTROL_NODE_CAPACITY]native.Sdl_Accessibility_Control_Input
    control_count := 0
    for node in snapshot^.nodes[:snapshot^.node_count] {
        role, supported := accessibility_publication_role(node.role)
        if !supported || .Visible not_in node.states {
            continue
        }
        if control_count >= len(controls) {
            log.warn("accessibility_control_capacity_exceeded")
            return
        }
        controls[control_count] = accessibility_control_input(
            semantic, snapshot, node, role)
        control_count += 1
    }
    if !native.sdl_platform_publish_accessibility_controls(platform, {
            root_bounds = root_bounds,
            bounds_scale = f64(platform^.metrics.display_scale),
            window_focused = semantic^.window_focused,
            controls = controls[:control_count],
        }) {
        log.warn("accessibility_control_publication_failed")
    }
}
