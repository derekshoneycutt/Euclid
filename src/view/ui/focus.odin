package ui

import viewmodel "../model"
import input "../input"

import "core:unicode/utf8"

// Scenario_Focus_Name maps stable test vocabulary to generation-free identity.
Scenario_Focus_Name :: struct {
    name: string,
    domain: viewmodel.Ui_Node_Domain,
    local_id: u64,
}

SCENARIO_FOCUS_NAMES :: [?]Scenario_Focus_Name{
    {"terminal", .Terminal, 0},
    {"presentation", .Presentation, 0},
    {"animation_restart", .Animation_Control, ANIMATION_REFRESH_BUTTON_ID},
    {"animation_pause", .Animation_Control, ANIMATION_PAUSE_BUTTON_ID},
    {"accordion_view", .Accordion, u64(viewmodel.Ui_Accordion_Section.View) + 1},
    {"accordion_library", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Library) + 1},
    {"accordion_save_gif", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Save_Gif) + 1},
    {"accordion_settings", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Settings) + 1},
    {"library_search", .Library_Control, LIBRARY_SEARCH_INPUT_ID},
    {"library_tree", .Animation_Tree, TREE_SEMANTIC_LOCAL_ID},
    {"settings_max_dust", .Settings_Control,
        SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID},
}

// Semantic_Control_Registration describes one ordinary control registration.
Semantic_Control_Registration :: struct {
    id: viewmodel.Ui_Node_Id,
    parent: viewmodel.Ui_Node_Id,
    active_descendant: viewmodel.Ui_Node_Id,
    controls: viewmodel.Ui_Node_Id,
    role: viewmodel.Ui_Node_Role,
    states: viewmodel.Ui_Node_State,
    actions: viewmodel.Ui_Node_Action_Set,
    region: viewmodel.Ui_Focus_Region,
    traversal_order: u16,
    bounds: viewmodel.Rectangle,
    clip_bounds: viewmodel.Rectangle,
    numeric_range: viewmodel.Ui_Numeric_Range,
    label: string,
    value: string,
    placeholder: string,
    text_cursor_byte: int,
    text_anchor_byte: int,
    text_present: bool,
    level: u16,
    position_in_set: u16,
    set_size: u16,
}

// semantic_control_id qualifies one existing widget identity by owning domain.
semantic_control_id :: #force_inline proc(
    domain: viewmodel.Ui_Node_Domain, local_id: int) -> viewmodel.Ui_Node_Id {
    return {domain = domain, local_id = u64(local_id)}
}

// semantic_snapshot returns the immutable snapshot used for current routing.
semantic_snapshot :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State) -> ^viewmodel.Ui_Semantic_Snapshot {
    if state == nil {return nil}
    return &state^.snapshots[state^.committed_index]
}

// semantic_staging_snapshot returns the snapshot currently accepting registrations.
semantic_staging_snapshot :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State) -> ^viewmodel.Ui_Semantic_Snapshot {
    if state == nil || !state^.staging_active {return nil}
    return &state^.snapshots[state^.staging_index]
}

// semantic_begin starts a fresh staging snapshot without disturbing committed data.
semantic_begin :: proc(state: ^viewmodel.Ui_Semantic_Focus_State) -> bool {
    if state == nil {return false}
    state^.staging_index = state^.committed_index == 0 ? 1 : 0
    staging := &state^.snapshots[state^.staging_index]
    staging^.node_count = 0
    staging^.text_count = 0
    staging^.generation = 0
    state^.staging_active = true
    state^.staging_rejected = false
    return true
}

// semantic_node_index resolves one complete identity in a populated snapshot.
semantic_node_index :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    id: viewmodel.Ui_Node_Id) -> int {
    if snapshot == nil {return -1}
    for index in 0..<snapshot^.node_count {
        if snapshot^.nodes[index].id == id {return index}
    }
    return -1
}

// semantic_node_text returns one validated text span owned by its snapshot.
semantic_node_text :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    offset: u32, length: u16) -> string {
    if snapshot == nil {return ""}
    first := int(offset)
    last := first + int(length)
    if first < 0 || last < first || last > snapshot^.text_count {return ""}
    return string(snapshot^.text[first:last])
}

// semantic_focus_matches_name resolves stable scenario names without exposing IDs.
semantic_focus_matches_name :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State, name: string) -> bool {
    snapshot := semantic_snapshot(state)
    if snapshot == nil {return false}
    index := semantic_node_index(snapshot, state^.logical_focus)
    if index < 0 {return false}
    id := snapshot^.nodes[index].id
    for entry in SCENARIO_FOCUS_NAMES {
        if entry.name == name {
            return id.domain == entry.domain && id.local_id == entry.local_id
        }
    }
    return false
}

// semantic_reject marks the current staging publication as unusable.
semantic_reject :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    status: viewmodel.Ui_Semantic_Status,
    id: viewmodel.Ui_Node_Id) -> viewmodel.Ui_Semantic_Status {
    if state == nil {return status}
    state^.staging_rejected = true
    state^.diagnostics.rejection_count += 1
    state^.diagnostics.last_rejection = status
    state^.diagnostics.offending_id = id
    return status
}

// semantic_registration_status validates one registration without mutating storage.
semantic_registration_status :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    registration: viewmodel.Ui_Semantic_Node_Registration) ->
    viewmodel.Ui_Semantic_Status {
    empty_id := viewmodel.Ui_Node_Id{}
    if registration.node.id == empty_id {return .Invalid_Id}
    if semantic_node_index(snapshot, registration.node.id) >= 0 {return .Duplicate_Id}
    if !utf8.valid_string(registration.label) ||
       !utf8.valid_string(registration.value) ||
       !utf8.valid_string(registration.placeholder) {
        return .Invalid_Utf8
    }
    if len(registration.label) > int(max(u16)) ||
       len(registration.value) > int(max(u16)) ||
       len(registration.placeholder) > int(max(u16)) {
        return .Text_Capacity
    }
    if snapshot^.node_count >= viewmodel.UI_SEMANTIC_NODE_CAPACITY {
        return .Node_Capacity
    }
    required_text := len(registration.label) + len(registration.value) +
        len(registration.placeholder)
    if required_text > viewmodel.UI_SEMANTIC_TEXT_CAPACITY - snapshot^.text_count {
        return .Text_Capacity
    }
    return .Ok
}

// semantic_register_node atomically copies one node and its borrowed UTF-8 text.
semantic_register_node :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    registration: viewmodel.Ui_Semantic_Node_Registration) ->
    viewmodel.Ui_Semantic_Status {
    snapshot := semantic_staging_snapshot(state)
    if snapshot == nil {return .Not_Staging}
    if state^.staging_rejected {return state^.diagnostics.last_rejection}
    status := semantic_registration_status(snapshot, registration)
    if status != .Ok {return semantic_reject(state, status, registration.node.id)}
    node := registration.node
    node.label_offset = u32(snapshot^.text_count)
    node.label_length = u16(len(registration.label))
    copy(snapshot^.text[snapshot^.text_count:], transmute([]u8)registration.label)
    snapshot^.text_count += len(registration.label)
    node.value_offset = u32(snapshot^.text_count)
    node.value_length = u16(len(registration.value))
    copy(snapshot^.text[snapshot^.text_count:], transmute([]u8)registration.value)
    snapshot^.text_count += len(registration.value)
    node.placeholder_offset = u32(snapshot^.text_count)
    node.placeholder_length = u16(len(registration.placeholder))
    copy(snapshot^.text[snapshot^.text_count:],
        transmute([]u8)registration.placeholder)
    snapshot^.text_count += len(registration.placeholder)
    snapshot^.nodes[snapshot^.node_count] = node
    snapshot^.node_count += 1
    return .Ok
}

// semantic_register_control publishes one ordinary control into staging storage.
semantic_register_control :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    control: Semantic_Control_Registration) -> viewmodel.Ui_Semantic_Status {
    states := control.states
    if state != nil && state^.window_focused &&
        state^.focus_origin == .Keyboard && state^.logical_focus == control.id {
        states += {.Focus_Visible}
    }
    return semantic_register_node(state, {
        node = {
            id = control.id,
            parent = control.parent,
            active_descendant = control.active_descendant,
            controls = control.controls,
            role = control.role,
            states = states,
            actions = control.actions,
            region = control.region,
            traversal_order = control.traversal_order,
            bounds = control.bounds,
            clip_bounds = control.clip_bounds,
            numeric_range = control.numeric_range,
            text_cursor_byte = u16(max(0, control.text_cursor_byte)),
            text_anchor_byte = u16(max(0, control.text_anchor_byte)),
            text_present = control.text_present,
            level = control.level,
            position_in_set = control.position_in_set,
            set_size = control.set_size,
        },
        label = control.label,
        value = control.value,
        placeholder = control.placeholder,
    })
}

// semantic_node_is_focus_candidate reports whether a published node admits focus.
semantic_node_is_focus_candidate :: proc(node: viewmodel.Ui_Semantic_Node) -> bool {
    required := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable}
    return node.states & required == required
}

// semantic_node_is_tab_stop reports whether a focus candidate enters global traversal.
semantic_node_is_tab_stop :: proc(node: viewmodel.Ui_Semantic_Node) -> bool {
    return semantic_node_is_focus_candidate(node) && .Tab_Stop in node.states &&
        .Focus in node.actions
}

// semantic_validate_snapshot checks complete identity, hierarchy, and traversal policy.
semantic_validate_snapshot :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot) ->
    (viewmodel.Ui_Semantic_Status, viewmodel.Ui_Node_Id) {
    if snapshot == nil {return .Invalid_Argument, {}}
    root_parent := viewmodel.Ui_Node_Id{}
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if node.parent != root_parent &&
             semantic_node_index(snapshot, node.parent) < 0 {
            return .Missing_Parent, node.id
        }
        if node.controls != root_parent &&
             semantic_node_index(snapshot, node.controls) < 0 {
            return .Missing_Parent, node.id
        }
        if !semantic_node_is_tab_stop(node) {continue}
        for prior in snapshot^.nodes[:index] {
            if semantic_node_is_tab_stop(prior) &&
                 prior.region == node.region &&
                 prior.traversal_order == node.traversal_order {
                return .Traversal_Collision, node.id
            }
        }
    }
    return .Ok, {}
}

// semantic_tab_stop_before reports explicit global traversal order.
semantic_tab_stop_before :: proc(
    left, right: viewmodel.Ui_Semantic_Node) -> bool {
    return left.region < right.region || left.region == right.region &&
        left.traversal_order < right.traversal_order
}

// semantic_edge_tab_stop finds the first or last enabled global stop.
semantic_edge_tab_stop :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot, reverse: bool) -> int {
    result := -1
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if !semantic_node_is_tab_stop(node) {continue}
        if result < 0 || reverse == semantic_tab_stop_before(
            snapshot^.nodes[result], node) {result = index}
    }
    return result
}

// semantic_tab_anchor_index resolves focus or its nearest tab-stop ancestor.
semantic_tab_anchor_index :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    focused: viewmodel.Ui_Node_Id) -> int {
    index := semantic_node_index(snapshot, focused)
    for index >= 0 {
        node := snapshot^.nodes[index]
        if semantic_node_is_tab_stop(node) {return index}
        index = semantic_node_index(snapshot, node.parent)
    }
    return -1
}

// semantic_next_tab_stop finds one directional stop and wraps at either edge.
semantic_next_tab_stop :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    focused: viewmodel.Ui_Node_Id, reverse: bool) -> int {
    anchor := semantic_tab_anchor_index(snapshot, focused)
    if anchor < 0 {return semantic_edge_tab_stop(snapshot, reverse)}
    result := -1
    anchor_node := snapshot^.nodes[anchor]
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if !semantic_node_is_tab_stop(node) {continue}
        follows := semantic_tab_stop_before(anchor_node, node)
        if reverse {follows = semantic_tab_stop_before(node, anchor_node)}
        if !follows {continue}
        if result < 0 || reverse == semantic_tab_stop_before(
            snapshot^.nodes[result], node) {result = index}
    }
    if result >= 0 {return result}
    return semantic_edge_tab_stop(snapshot, reverse)
}

// semantic_append_command retains one addressed action for current-frame owners.
semantic_append_command :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    command: viewmodel.Ui_Focus_Command) -> bool {
    if state^.command_count >= len(state^.commands) {return false}
    state^.commands[state^.command_count] = command
    state^.command_count += 1
    return true
}

// semantic_command_requested reports one addressed current-frame owner action.
semantic_command_requested :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    target: viewmodel.Ui_Node_Id,
    kind: viewmodel.Ui_Focus_Command_Kind) -> bool {
    if state == nil {return false}
    for command in state^.commands[:state^.command_count] {
        if command.target == target && command.kind == kind {return true}
    }
    return false
}

// semantic_simple_external_action authorizes one payload-free owner command.
semantic_simple_external_action :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State, node: viewmodel.Ui_Semantic_Node,
    target: viewmodel.Ui_Node_Id, kind: viewmodel.Ui_Focus_Command_Kind) -> bool {
    required_action: viewmodel.Ui_Node_Action
    #partial switch kind {
    case .Activate: required_action = .Activate
    case .Toggle: required_action = .Toggle
    case .Increment: required_action = .Increment
    case .Decrement: required_action = .Decrement
    case .Select: required_action = .Select
    case .Expand: required_action = .Expand
    case .Collapse: required_action = .Collapse
    case: required_action = .Focus
    }
    if required_action != .Focus && required_action in node.actions {
        return semantic_append_command(state, {target = target, kind = kind})
    }
    return false
}

// semantic_apply_external_action validates and converges one owner-external action.
semantic_apply_external_action :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    target: viewmodel.Ui_Node_Id,
    kind: viewmodel.Ui_Focus_Command_Kind,
    numeric_value: f64 = 0) -> bool {
    if state == nil {return false}
    snapshot := semantic_snapshot(state)
    index := semantic_node_index(snapshot, target)
    if index < 0 {return false}
    node := snapshot^.nodes[index]
    required_states := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable}
    if node.states & required_states != required_states {return false}
    if kind == .Focus && .Focus in node.actions {
        state^.logical_focus = target
        state^.focus_origin = .Keyboard
        state^.last_region = node.region
        state^.last_traversal_order = node.traversal_order
        return true
    }
    if kind == .Set_Value && .Set_Value in node.actions {
        return semantic_append_command(state, {
            target = target, kind = kind, numeric_value = numeric_value})
    }
    if kind == .Scroll_Page && .Scroll in node.actions {
        amount := i32(1)
        if numeric_value < 0 {amount = -1}
        return semantic_append_command(state, {
            target = target, kind = kind, amount = amount})
    }
    if kind == .Set_Scroll_Value && .Scroll in node.actions {
        return semantic_append_command(state, {
            target = target, kind = kind, numeric_value = numeric_value})
    }
    return semantic_simple_external_action(state, node, target, kind)
}

// semantic_apply_external_text_action validates and copies one bounded text command.
semantic_apply_external_text_action :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    target: viewmodel.Ui_Node_Id,
    kind: viewmodel.Ui_Focus_Command_Kind,
    payload: string, anchor, focus: u16) -> bool {
    if state == nil || len(payload) > viewmodel.UI_FOCUS_COMMAND_PAYLOAD_CAPACITY {
        return false
    }
    snapshot := semantic_snapshot(state)
    index := semantic_node_index(snapshot, target)
    if index < 0 {return false}
    node := snapshot^.nodes[index]
    required := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable}
    if node.states & required != required {return false}
    command := viewmodel.Ui_Focus_Command{target = target, kind = kind,
        payload_length = u16(len(payload)), selection_anchor = anchor,
        selection_focus = focus}
    if kind == .Replace_Selected_Text && .Replace_Selected_Text in node.actions {
        copy(command.payload[:len(payload)], transmute([]u8)payload)
        return semantic_append_command(state, command)
    }
    if kind == .Replace_Text && .Replace_Selected_Text in node.actions {
        copy(command.payload[:len(payload)], transmute([]u8)payload)
        return semantic_append_command(state, command)
    }
    if kind == .Set_Text_Selection && .Set_Text_Selection in node.actions {
        return semantic_append_command(state, command)
    }
    return false
}

// semantic_request_pointer_focus moves focus to one registered staging node.
semantic_request_pointer_focus :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    target: viewmodel.Ui_Node_Id) -> bool {
    snapshot := semantic_staging_snapshot(state)
    index := semantic_node_index(snapshot, target)
    if index < 0 || !semantic_node_is_focus_candidate(snapshot^.nodes[index]) {
        return false
    }
    node := snapshot^.nodes[index]
    state^.logical_focus = target
    state^.focus_origin = .Pointer
    state^.last_region = node.region
    state^.last_traversal_order = node.traversal_order
    return true
}

// semantic_clear_pointer_focus clears control focus for a broad pointer target.
semantic_clear_pointer_focus :: proc(state: ^viewmodel.Ui_Semantic_Focus_State) {
    if state == nil {return}
    state^.logical_focus = {}
    state^.focus_origin = .Pointer
    state^.last_region = .None
    state^.last_traversal_order = 0
}

// semantic_focus_for_press applies pointer focus for one exact capture owner.
semantic_focus_for_press :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    owner: ^viewmodel.Ui_Press_Owner_State,
    kind: viewmodel.Ui_Press_Owner_Kind,
    press_id: int,
    target: viewmodel.Ui_Node_Id) -> bool {
    if owner == nil || !owner^.active || owner^.kind != kind ||
        owner^.id != press_id {return false}
    return semantic_request_pointer_focus(state, target)
}

// semantic_activation_command maps discrete activation for ordinary controls.
semantic_activation_command :: proc(
    node: viewmodel.Ui_Semantic_Node,
    event: input.Input_Event) -> viewmodel.Ui_Focus_Command_Kind {
    if event.kind != .Press {return .None}
    if node.role == .Checkbox && event.key == .Space &&
        .Toggle in node.actions {return .Toggle}
    if (node.role == .Button || node.role == .Accordion_Header) &&
        (event.key == .Enter || event.key == .Space) &&
        .Activate in node.actions {return .Activate}
    return .None
}

// semantic_slider_command maps repeatable adjustment keys to bounded owner commands.
semantic_slider_command :: proc(
    node: viewmodel.Ui_Semantic_Node,
    key: input.Input_Key) -> (viewmodel.Ui_Focus_Command_Kind, i32) {
    if (key == .Left || key == .Down) && .Decrement in node.actions {
        return .Decrement, 1
    }
    if (key == .Right || key == .Up) && .Increment in node.actions {
        return .Increment, 1
    }
    if key == .Home && .Set_To_Bound in node.actions {return .Set_Minimum, 0}
    if key == .End && .Set_To_Bound in node.actions {return .Set_Maximum, 0}
    if key == .Page_Down && .Decrement in node.actions {return .Page_Step, -1}
    if key == .Page_Up && .Increment in node.actions {return .Page_Step, 1}
    return .None, 0
}

// semantic_document_command maps page navigation to the document scroll owner.
semantic_document_command :: proc(
    node: viewmodel.Ui_Semantic_Node,
    key: input.Input_Key) -> (viewmodel.Ui_Focus_Command_Kind, i32) {
    if .Scroll not_in node.actions {return .None, 0}
    if key == .Page_Down {return .Scroll_Page, 1}
    if key == .Page_Up {return .Scroll_Page, -1}
    return .None, 0
}

// semantic_tree_command maps composite navigation to advertised tree actions.
semantic_tree_command :: proc(
    node: viewmodel.Ui_Semantic_Node,
    key: input.Input_Key) -> viewmodel.Ui_Focus_Command_Kind {
    if key == .Left && (.Collapse in node.actions || .Select in node.actions) {
        return .Tree_Parent
    }
    if key == .Right && (.Expand in node.actions || .Select in node.actions) {
        return .Tree_Child
    }
    if key == .Space &&
        (.Expand in node.actions || .Collapse in node.actions) {return .Toggle}
    if .Select not_in node.actions {return .None}
    #partial switch key {
    case .Up: return .Tree_Previous
    case .Down: return .Tree_Next
    case .Home: return .Tree_First
    case .End: return .Tree_Last
    case .Enter: return .Select
    }
    return .None
}

// semantic_command_for_event maps one focused role and key to an owner command.
semantic_command_for_event :: proc(
    node: viewmodel.Ui_Semantic_Node,
    event: input.Input_Event) -> (viewmodel.Ui_Focus_Command_Kind, i32) {
    if event.kind != .Press && event.kind != .Repeat {return .None, 0}
    if .Control in event.modifiers || .Alt in event.modifiers ||
        .Super in event.modifiers {return .None, 0}
    #partial switch node.role {
    case .Button, .Accordion_Header:
        return semantic_activation_command(node, event), 0
    case .Checkbox:
        return semantic_activation_command(node, event), 0
    case .Slider:
        return semantic_slider_command(node, event.key)
    case .Tree:
        return semantic_tree_command(node, event.key), 0
    case .Document:
        return semantic_document_command(node, event.key)
    case:
    }
    return .None, 0
}

// semantic_route_traversal applies one admitted directional traversal event.
semantic_route_traversal :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    frame: input.Input_Frame, event_index: int,
    terminal_owns_keyboard: bool,
    claims: ^input.Input_Event_Claim_State) -> bool {
    snapshot := semantic_snapshot(state)
    event := frame.events[event_index]
    focused_index := semantic_node_index(snapshot, state^.logical_focus)
    terminal_focused := focused_index >= 0 &&
        snapshot^.nodes[focused_index].role == .Terminal
    terminal_focused = terminal_focused ||
        focused_index < 0 && terminal_owns_keyboard
    if event.kind != .Press || event.key != .Tab || .Alt in event.modifiers ||
        .Super in event.modifiers ||
        terminal_focused != (.Control in event.modifiers) {return false}
    next := semantic_next_tab_stop(snapshot, state^.logical_focus,
        .Shift in event.modifiers)
    if next < 0 || !input.input_event_claim(frame, event_index, claims) {return false}
    node := snapshot^.nodes[next]
    state^.logical_focus = node.id
    state^.focus_origin = .Keyboard
    state^.last_region = node.region
    state^.last_traversal_order = node.traversal_order
    return semantic_append_command(state, {
        target = node.id, kind = .Focus, event_index = u16(event_index)})
}

// semantic_route_focused_command routes one non-traversal event to current focus.
semantic_route_focused_command :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    frame: input.Input_Frame, event_index: int,
    claims: ^input.Input_Event_Claim_State) {
    focused_index := semantic_node_index(snapshot, state^.logical_focus)
    if focused_index < 0 {return}
    kind, amount := semantic_command_for_event(
        snapshot^.nodes[focused_index], frame.events[event_index])
    if kind == .None || !input.input_event_claim(frame, event_index, claims) {return}
    _ = semantic_append_command(state, {
        target = state^.logical_focus, kind = kind, amount = amount,
        event_index = u16(event_index)})
}

// semantic_route_keyboard claims traversal and emits bounded role commands in order.
semantic_route_keyboard :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    frame: input.Input_Frame,
    terminal_owns_keyboard: bool = false) -> input.Input_Event_Claim_State {
    claims: input.Input_Event_Claim_State
    if state == nil {return claims}
    state^.window_focused = frame.window_focused
    state^.command_count = 0
    snapshot := semantic_snapshot(state)
    for _, event_index in frame.events {
        if semantic_route_traversal(state, frame, event_index,
            terminal_owns_keyboard, &claims) {continue}
        if terminal_owns_keyboard {continue}
        semantic_route_focused_command(
            state, snapshot, frame, event_index, &claims)
    }
    return claims
}

// semantic_focus_moved reports whether this frame produced a focus command.
semantic_focus_moved :: proc(state: ^viewmodel.Ui_Semantic_Focus_State) -> bool {
    return state != nil && state^.command_count > 0 &&
        state^.commands[0].kind == .Focus
}

// semantic_legacy_focus maps semantic ownership into transitional surface routing.
semantic_legacy_focus :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State) ->
    (viewmodel.Ui_Focus_Target, bool) {
    snapshot := semantic_snapshot(state)
    index := semantic_node_index(snapshot, state^.logical_focus)
    if index < 0 {return {}, false}
    node := snapshot^.nodes[index]
    if node.role == .Terminal || node.id.domain == .Terminal {
        return {kind = .Terminal}, true
    }
    if node.role == .Document || node.id.domain == .Presentation {
        return {kind = .Presentation}, true
    }
    if node.role == .Input {
        return {kind = .Input_Box, id = int(node.id.local_id)}, true
    }
    if node.id.domain == .Animation_Control {return {}, true}
    return {kind = .Accordion}, true
}

// semantic_nearest_candidate finds the next, then prior, candidate in one local order.
semantic_nearest_candidate :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    reference: viewmodel.Ui_Semantic_Node,
    require_same_parent: bool) -> int {
    next_index, prior_index := -1, -1
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if !semantic_node_is_focus_candidate(node) {continue}
        if !require_same_parent && !semantic_node_is_tab_stop(node) {continue}
        if node.region != reference.region ||
            (require_same_parent && node.parent != reference.parent) {continue}
        if node.traversal_order > reference.traversal_order &&
             (next_index < 0 || node.traversal_order <
                snapshot^.nodes[next_index].traversal_order) {next_index = index}
        if node.traversal_order < reference.traversal_order &&
             (prior_index < 0 || node.traversal_order >
                snapshot^.nodes[prior_index].traversal_order) {prior_index = index}
    }
    if next_index >= 0 {return next_index}
    return prior_index
}

// semantic_first_candidate finds the earliest candidate in global region order.
semantic_first_candidate :: proc(snapshot: ^viewmodel.Ui_Semantic_Snapshot) -> int {
    result := -1
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if !semantic_node_is_tab_stop(node) {continue}
        if result < 0 || node.region < snapshot^.nodes[result].region ||
            (node.region == snapshot^.nodes[result].region &&
             node.traversal_order < snapshot^.nodes[result].traversal_order) {
            result = index
        }
    }
    return result
}

// semantic_generation_replacement finds the same qualified identity after renewal.
semantic_generation_replacement :: proc(
    snapshot: ^viewmodel.Ui_Semantic_Snapshot,
    id: viewmodel.Ui_Node_Id) -> int {
    for node, index in snapshot^.nodes[:snapshot^.node_count] {
        if node.id.domain == id.domain && node.id.local_id == id.local_id &&
            node.id.stable_id == id.stable_id &&
            semantic_node_is_focus_candidate(node) {return index}
    }
    return -1
}

// semantic_find_repair_candidate chooses deterministic focus after identity retirement.
semantic_find_repair_candidate :: proc(
    current, previous: ^viewmodel.Ui_Semantic_Snapshot,
    focused: viewmodel.Ui_Node_Id) -> int {
    previous_index := semantic_node_index(previous, focused)
    if previous_index < 0 {return semantic_first_candidate(current)}
    replacement := semantic_generation_replacement(current, focused)
    if replacement >= 0 {return replacement}
    previous_node := previous^.nodes[previous_index]
    empty_id := viewmodel.Ui_Node_Id{}
    if previous_node.parent != empty_id {
        sibling := semantic_nearest_candidate(current, previous_node, true)
        if sibling >= 0 {return sibling}
        parent := semantic_node_index(current, previous_node.parent)
        if parent >= 0 && semantic_node_is_focus_candidate(
            current^.nodes[parent]) {return parent}
    }
    nearby := semantic_nearest_candidate(current, previous_node, false)
    if nearby >= 0 {return nearby}
    return semantic_first_candidate(current)
}

// semantic_reconcile_focus preserves valid focus or repairs it against current nodes.
semantic_reconcile_focus :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    current, previous: ^viewmodel.Ui_Semantic_Snapshot) {
    empty_id := viewmodel.Ui_Node_Id{}
    if state^.logical_focus == empty_id {return}
    focused_index := semantic_node_index(current, state^.logical_focus)
    if focused_index >= 0 && semantic_node_is_focus_candidate(
        current^.nodes[focused_index]) {return}
    replacement := semantic_find_repair_candidate(current, previous,
        state^.logical_focus)
    if replacement < 0 {
        state^.logical_focus = {}
        state^.last_region = .None
        state^.last_traversal_order = 0
        return
    }
    node := current^.nodes[replacement]
    state^.logical_focus = node.id
    state^.last_region = node.region
    state^.last_traversal_order = node.traversal_order
}

// semantic_refresh_focus_visible marks only effective keyboard-origin focus.
semantic_refresh_focus_visible :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State,
    snapshot: ^viewmodel.Ui_Semantic_Snapshot) {
    for &node in snapshot^.nodes[:snapshot^.node_count] {
        node.states -= {.Focus_Visible}
    }
    if !state^.window_focused || state^.focus_origin != .Keyboard {return}
    index := semantic_node_index(snapshot, state^.logical_focus)
    if index >= 0 {snapshot^.nodes[index].states += {.Focus_Visible}}
}

// semantic_publish validates, reconciles, and atomically commits the staging snapshot.
semantic_publish :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State) -> viewmodel.Ui_Semantic_Status {
    staging := semantic_staging_snapshot(state)
    if staging == nil {return .Not_Staging}
    if state^.staging_rejected {
        state^.staging_active = false
        return state^.diagnostics.last_rejection
    }
    status, offending_id := semantic_validate_snapshot(staging)
    if status != .Ok {
        _ = semantic_reject(state, status, offending_id)
        state^.staging_active = false
        return status
    }
    previous := semantic_snapshot(state)
    semantic_reconcile_focus(state, staging, previous)
    semantic_refresh_focus_visible(state, staging)
    staging^.generation = previous^.generation + 1
    state^.committed_index = state^.staging_index
    state^.staging_active = false
    state^.diagnostics.node_high_water = max(
        state^.diagnostics.node_high_water, staging^.node_count)
    state^.diagnostics.text_high_water = max(
        state^.diagnostics.text_high_water, staging^.text_count)
    state^.diagnostics.last_rejection = .Ok
    state^.diagnostics.offending_id = {}
    return .Ok
}