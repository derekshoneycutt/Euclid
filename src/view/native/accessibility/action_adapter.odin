package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "base:runtime"
import "core:log"
import "core:math"
import "core:unicode/utf8"

Adapter_Action_Mapping :: struct {
    required: portable.Publication_Action,
    mapped: Adapter_Action_Kind,
    numeric_value: f64,
    supported: bool,
}

// adapter_input_index finds one semantic identity in staged input.
adapter_input_index :: proc(
    input: Adapter_Tree_Input,
    identity: portable.Qualified_Identity) -> int {
    if identity == {
       } {return -1
    }
    for source, index in input.controls {
        if source.identity == identity {
           return index
        }
    }
    return -1
}

// adapter_stage_identity_unique rejects one duplicate staged identity.
adapter_stage_identity_unique :: proc(
    input: Adapter_Tree_Input, source: Adapter_Control_Input, index: int) -> bool {
    for prior in input.controls[:index] {
        if prior.identity != source.identity {
           continue
        }
        log.warnf("accessibility_control_identity_duplicate index=%d prior=%d",
            index, adapter_input_index(input, source.identity))
        return false
    }
    return true
}

// adapter_stage_validation_control resolves one temporary relation record.
adapter_stage_validation_control :: proc(
    input: Adapter_Tree_Input, source: Adapter_Control_Input, index: int,
    controls: ^[portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input) ->
    bool {
    if !adapter_stage_identity_unique(input, source, index) {
       return false
    }
    controls^[index] = source.control
    controls^[index].native_id = u64(index + 2)
    parent_index := adapter_input_index(input, source.parent_identity)
    if source.parent_identity != {
       } && parent_index < 0 {return false
    }
    if parent_index >= 0 {
       controls^[index].parent_native_id = u64(parent_index + 2)
    }
    active_index := adapter_input_index(input, source.active_descendant_identity)
    if source.active_descendant_identity != {
       } && active_index < 0 {return false
    }
    if active_index >= 0 {
        controls^[index].active_descendant_native_id = u64(active_index + 2)
    }
    controls_index := adapter_input_index(input, source.controls_identity)
    if source.controls_identity != {
       } && controls_index < 0 {return false
    }
    if controls_index >= 0 {
        controls^[index].controls_native_id = u64(controls_index + 2)
    }
    return true
}

// adapter_stage_validation validates relations without consuming registry IDs.
adapter_stage_validation :: proc(
    input: Adapter_Tree_Input,
    controls: ^[portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input) ->
    bool {
    for source, index in input.controls {
        if !adapter_stage_validation_control(
            input, source, index, controls) {return false}
    }
    validation: portable.Control_Tree_Publication
    status := portable.control_tree_build(&validation, {
        root_bounds = input.root_bounds,
        bounds_scale = input.bounds_scale,
        window_focused = input.window_focused,
        controls = controls^[:len(input.controls)],
    })
    if status != .Ok {
        log.warnf("accessibility_control_validation_failed status=%v controls=%d",
            status, len(input.controls))
        return false
    }
    return true
}

// adapter_resolve_relation maps one optional semantic identity to a native ID.
adapter_resolve_relation :: proc(
    input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64,
    identity: portable.Qualified_Identity) -> (u64, bool) {
    if identity == {
       } {return 0, true
    }
    index := adapter_input_index(input, identity)
    if index < 0 {
       return 0, false
    }
    return native_ids^[index], true
}

// adapter_resolve_control_ids assigns monotonic IDs to staged identities.
adapter_resolve_control_ids :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64) -> bool {
    for source, index in input.controls {
        native_id, resolved := portable.native_id_resolve(
            &owner^.native_ids, source.identity)
        if !resolved {
            log.warnf(
                "accessibility_control_identity_rejected index=%d owner=%d " +
                "local_id=%d has_uuid=%v registry_count=%d",
                index, source.identity.owner_domain, source.identity.local_id,
                source.identity.stable_uuid != ([16]u8{}), owner^.native_ids.count)
            return false
        }
        native_ids^[index] = native_id
    }
    return true
}

// adapter_stage_control resolves one record's hierarchy relations.
adapter_stage_control :: proc(
    input: Adapter_Tree_Input,
    native_ids: ^[portable.CONTROL_NODE_CAPACITY]u64,
    source: Adapter_Control_Input, index: int,
    destination: ^portable.Control_Publication_Input) -> bool {
    destination^ = source.control
    destination^.native_id = native_ids^[index]
    parent_id, parent_ok := adapter_resolve_relation(
        input, native_ids, source.parent_identity)
    active_id, active_ok := adapter_resolve_relation(
        input, native_ids, source.active_descendant_identity)
    controls_id, controls_ok := adapter_resolve_relation(
        input, native_ids, source.controls_identity)
    if !parent_ok || !active_ok || !controls_ok {
       return false
    }
    destination^.parent_native_id = parent_id
    destination^.active_descendant_native_id = active_id
    destination^.controls_native_id = controls_id
    return true
}

// adapter_stage_controls resolves native IDs into complete portable records.
adapter_stage_controls :: proc(
    owner: ^Adapter, input: Adapter_Tree_Input,
    controls: ^[portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input,
    count: ^int) -> bool {
    if owner == nil || controls == nil || count == nil ||
       len(input.controls) > portable.CONTROL_NODE_CAPACITY {return false}
    if owner^.native_ids.count == 0 {
        portable.native_id_registry_init(&owner^.native_ids)
    }
    validation_controls:
        [portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input
    if !adapter_stage_validation(input, &validation_controls) {
       return false
    }
    native_ids: [portable.CONTROL_NODE_CAPACITY]u64
    if !adapter_resolve_control_ids(owner, input, &native_ids) {
       return false
    }
    for source, index in input.controls {
        if !adapter_stage_control(
            input, &native_ids, source, index, &controls^[index]) {return false}
    }
    count^ = len(input.controls)
    return true
}

// adapter_retire_absent_controls retires IDs missing from the new tree.
adapter_retire_absent_controls :: proc(
    owner: ^Adapter, controls: []portable.Control_Publication_Input) {
    for old_id in owner^.control_native_ids[:owner^.control_count] {
        retained := false
        for control in controls {
            if control.native_id == old_id {
               retained = true; break
            }
        }
        if !retained {
           _ = portable.native_id_retire(&owner^.native_ids, old_id)
        }
    }
    owner^.control_native_ids = {}
    owner^.control_count = len(controls)
    for control, index in controls {
        owner^.control_native_ids[index] = control.native_id
    }
}

// adapter_publish_controls owns one complete portable control publication.
adapter_publish_controls :: proc(owner: ^Adapter, input: Adapter_Tree_Input) -> bool {
    if owner == nil {
       return false
    }
    controls: [portable.CONTROL_NODE_CAPACITY]portable.Control_Publication_Input
    control_count: int
    if !adapter_stage_controls(owner, input, &controls, &control_count) {
        return false
    }
    slice := controls[:control_count]
    status := portable.protected_publish_controls(&owner^.control_publication, {
        root_bounds = input.root_bounds,
        bounds_scale = input.bounds_scale,
        window_focused = input.window_focused,
        controls = slice,
    })
    if status != .Ok {
        log.warnf("accessibility_control_publish_failed status=%v controls=%d",
            status, control_count)
        return false
    }
    adapter_retire_absent_controls(owner, slice)
    return true
}

// adapter_publish_present_button publishes one present button with stable identity.
adapter_publish_present_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    child_id, child_ok := portable.native_id_resolve(&owner^.native_ids, identity)
    if !child_ok {
       return false
    }
    publication_input := input
    publication_input.child_id = child_id
    if portable.protected_publish_button(
        &owner^.publication, publication_input) != .Ok {return false}
    if owner^.child_present && owner^.child_native_id != child_id {
        _ = portable.native_id_retire(&owner^.native_ids, owner^.child_native_id)
    }
    owner^.child_identity = identity
    owner^.child_native_id = child_id
    owner^.child_present = true
    return true
}

// adapter_publish_removed_button retires the prior child after root publication.
adapter_publish_removed_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input) -> bool {
    if portable.protected_publish_button(&owner^.publication, input) != .Ok {
        return false
    }
    if owner^.child_present {
        _ = portable.native_id_retire(&owner^.native_ids, owner^.child_native_id)
    }
    owner^.child_identity = {}
    owner^.child_native_id = 0
    owner^.child_present = false
    return true
}

// adapter_publish_button owns static publication and native identity lifetime.
adapter_publish_button :: proc(
    owner: ^Adapter, input: portable.Button_Publication_Input,
    identity: portable.Qualified_Identity) -> bool {
    if owner == nil {
       return false
    }
    if owner^.native_ids.count == 0 {
        if !input.present {
           return true
        }
        portable.native_id_registry_init(&owner^.native_ids)
    }
    if input.present {
        return adapter_publish_present_button(owner, input, identity)
    }
    return adapter_publish_removed_button(owner, input)
}

// adapter_initialize_static owns the initial synthetic publication.
adapter_initialize_static :: proc(
    owner: ^Adapter, width, height: f64, focused: bool) -> bool {
    if owner == nil {
       return false
    }
    portable.native_id_registry_init(&owner^.native_ids)
    child_id, child_ok := portable.native_id_resolve(&owner^.native_ids, {
        domain = .Synthetic,
        local_id = portable.STATIC_CHILD_ID,
    })
    if !child_ok || child_id != portable.STATIC_CHILD_ID {
       return false
    }
    return portable.protected_publish(
        &owner^.publication, width, height, focused) == .Ok
}

// adapter_validate_action resolves one current request into display-owned facts.
adapter_validate_action :: proc(
    owner: ^Adapter, request: portable.Queued_Action,
    publication: portable.Static_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if request.publication_generation != publication.generation {
        return .Stale_Generation
    }
    identity, found := portable.native_id_lookup(
        &owner^.native_ids, request.target_native_id)
    if !found {
       return .Unknown_Target
    }
    if !publication.child_present || request.target_native_id != publication.child_id {
        return .Removed_Target
    }
    if request.kind == u16(accesskit.Action.Focus) &&
       publication.child_supports_focus {
        destination^ = {kind = .Focus, identity = identity}
        return .Ok
    }
    if request.kind == u16(accesskit.Action.Click) &&
       publication.child_supports_activate {
        if !publication.child_enabled {
           return .Disabled_Target
        }
        destination^ = {kind = .Activate, identity = identity}
        return .Ok
    }
    return .Unsupported_Action
}

// adapter_control_by_native_id finds one current complete publication record.
adapter_control_by_native_id :: proc(
    publication: ^portable.Control_Tree_Publication,
    native_id: u64) -> ^portable.Control_Publication {
    for index in 0..<publication^.control_count {
        candidate := &publication^.controls[index]
        if candidate^.native_id == native_id {
           return candidate
        }
    }
    return nil
}

// adapter_validate_numeric_action validates and copies one exact ranged value.
adapter_validate_numeric_action :: proc(
    control: ^portable.Control_Publication,
    request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    value := request.numeric_value
    valid := request.has_numeric_value &&
        !math.is_nan(value) && !math.is_inf(value) && control^.range.present &&
        value >= control^.range.minimum && value <= control^.range.maximum
    if !valid {
       return .Invalid_Value
    }
    if control^.role == .Tree && .Scroll in control^.actions {
        destination^.kind = .Set_Scroll_Value
        destination^.numeric_value = value
        return .Ok
    }
    if .Set_Value not_in control^.actions {
       return .Invalid_Value
    }
    destination^.kind = .Set_Value
    destination^.numeric_value = value
    return .Ok
}

// adapter_validate_text_action copies one already-bounded UTF-8 replacement.
adapter_validate_text_action :: proc(
    control: ^portable.Control_Publication, request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if .Replace_Selected_Text not_in control^.actions ||
       request.payload_length < 0 ||
       request.payload_length > len(request.payload) {return .Invalid_Value}
    payload := request.payload
    text := string(payload[:request.payload_length])
    if !utf8.valid_string(text) {
       return .Invalid_Value
    }
    destination^.kind = .Replace_Selected_Text
    if request.replace_entire_text {
       destination^.kind = .Replace_Text
    }
    destination^.payload_length = request.payload_length
    copy(destination^.payload[:request.payload_length],
        payload[:request.payload_length])
    return .Ok
}

// adapter_validate_selection_action checks indices against current text.
adapter_validate_selection_action :: proc(
    control: ^portable.Control_Publication, request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if .Set_Text_Selection not_in control^.actions || !control^.text_present ||
       request.selection_anchor > control^.character_count ||
       request.selection_focus > control^.character_count {
        return .Invalid_Value
    }
    destination^.kind = .Set_Text_Selection
    destination^.selection_anchor = request.selection_anchor
    destination^.selection_focus = request.selection_focus
    return .Ok
}

// adapter_map_click_action toggles branches and selects leaf TreeItems.
adapter_map_click_action :: proc(
    control: ^portable.Control_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if control^.role == .Tree_Item && .Toggle in control^.actions {
        destination^.kind = .Toggle
        return .Ok
    }
    if .Select in control^.actions {
       destination^.kind = .Select; return .Ok
    }
    if .Toggle in control^.actions {
       destination^.kind = .Toggle; return .Ok
    }
    if .Activate in control^.actions {
       destination^.kind = .Activate; return .Ok
    }
    return .Unsupported_Action
}

// adapter_simple_action_mapping maps one payload-free native action.
adapter_simple_action_mapping :: proc(
    action: accesskit.Action) -> Adapter_Action_Mapping {
    #partial switch action {
    case .Focus: return {.Focus, .Focus, 0, true}
    case .Increment: return {.Increment, .Increment, 0, true}
    case .Decrement: return {.Decrement, .Decrement, 0, true}
    case .Expand: return {.Expand, .Expand, 0, true}
    case .Collapse: return {.Collapse, .Collapse, 0, true}
    case .Scroll_Up: return {.Scroll, .Scroll, -1, true}
    case .Scroll_Down: return {.Scroll, .Scroll, 1, true}
    case: return {}
    }
}

// adapter_map_control_action maps one supported native action to its owner command.
adapter_map_control_action :: proc(
    control: ^portable.Control_Publication,
    request: portable.Queued_Action,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    action := accesskit.Action(request.kind)
    if action == .Click {
       return adapter_map_click_action(control, destination)
    }
    if action == .Set_Value {
        return adapter_validate_numeric_action(control, request, destination)
    }
    if action == .Replace_Selected_Text {
        return adapter_validate_text_action(control, request, destination)
    }
    if action == .Set_Text_Selection {
        return adapter_validate_selection_action(control, request, destination)
    }
    mapping := adapter_simple_action_mapping(action)
    if !mapping.supported || mapping.required not_in control^.actions {
        return .Unsupported_Action
    }
    destination^.kind = mapping.mapped
    destination^.numeric_value = mapping.numeric_value
    return .Ok
}

// adapter_validate_control_action resolves one current ordinary-control request.
adapter_validate_control_action :: proc(
    owner: ^Adapter, request: portable.Queued_Action,
    publication: ^portable.Control_Tree_Publication,
    destination: ^Adapter_Action) -> Adapter_Action_Status {
    if request.publication_generation != publication^.generation {
        return .Stale_Generation
    }
    identity, found := portable.native_id_lookup(
        &owner^.native_ids, request.target_native_id)
    if !found {
       return .Unknown_Target
    }
    control := adapter_control_by_native_id(publication, request.target_native_id)
    if control == nil {
       return .Removed_Target
    }
    if !control^.enabled {
       return .Disabled_Target
    }
    destination^.identity = identity
    return adapter_map_control_action(control, request, destination)
}

// adapter_drain_action validates one copied request against current publication.
adapter_drain_action :: proc(
    owner: ^Adapter, destination: ^Adapter_Action) -> Adapter_Action_Status {
    if owner == nil || destination == nil {
       return .Closing
    }
    request: portable.Queued_Action
    if !portable.action_queue_pop(&owner^.actions, &request) {
       return .Empty
    }
    control_publication: portable.Control_Tree_Publication
    if portable.protected_control_snapshot(
            &owner^.control_publication, &control_publication) {
        status := adapter_validate_control_action(
            owner, request, &control_publication, destination)
        adapter_record_action_rejection(owner, status)
        return status
    }
    publication: portable.Static_Publication
    if !portable.protected_snapshot(&owner^.publication, &publication) {
        adapter_record_action_rejection(owner, .Closing)
        return .Closing
    }
    status := adapter_validate_action(owner, request, publication, destination)
    adapter_record_action_rejection(owner, status)
    return status
}

// accesskit_activation_callback transfers one protected tree to AccessKit.
accesskit_activation_callback :: proc "c" (user_data: rawptr) -> ^accesskit.Tree_Update {
    context = runtime.default_context()
    owner := cast(^Adapter)user_data
    adapter_record_diagnostic(owner, .Activation)
    control_publication: portable.Control_Tree_Publication
    if owner != nil && portable.protected_control_snapshot(
            &owner^.control_publication, &control_publication) {
        return accesskit_control_tree_update(&control_publication)
    }
    publication: portable.Static_Publication
    if owner == nil ||
       !portable.protected_snapshot(&owner^.publication, &publication) {
        adapter_record_diagnostic(owner, .Rejected_Callback)
        return nil
    }
    return accesskit_tree_update(&publication)
}

// adapter_action_generation snapshots the generation used for ingress validation.
adapter_action_generation :: proc(owner: ^Adapter) -> (u64, bool) {
    controls: portable.Control_Tree_Publication
    if portable.protected_control_snapshot(&owner^.control_publication, &controls) {
        return controls.generation, true
    }
    publication: portable.Static_Publication
    if portable.protected_snapshot(&owner^.publication, &publication) {
        return publication.generation, true
    }
    return 0, false
}

// accesskit_action_supported admits only actions translated by the shared adapter.
accesskit_action_supported :: proc(action: accesskit.Action) -> bool {
    #partial switch action {
    case .Click, .Focus, .Increment, .Decrement, .Set_Value,
         .Replace_Selected_Text, .Set_Text_Selection, .Expand, .Collapse,
         .Scroll_Up, .Scroll_Down:
        return true
    case: return false
    }
}

// accesskit_copy_text_value copies one native string into bounded owner storage.
accesskit_copy_text_value :: proc(
    request: ^accesskit.Action_Request,
    copied: ^portable.Queued_Action) -> portable.Action_Queue_Status {
    if !request^.data.has_value || request^.data.value.tag != .Value ||
       request^.data.value.payload.value == nil {return .Invalid_Target}
    source := cast([^]u8)request^.data.value.payload.value
    for copied^.payload_length < len(copied^.payload) &&
        source[copied^.payload_length] != 0 {
        copied^.payload[copied^.payload_length] = source[copied^.payload_length]
        copied^.payload_length += 1
    }
    if copied^.payload_length == len(copied^.payload) &&
       source[copied^.payload_length] != 0 {return .Payload_Overflow}
    return .Ok
}

// accesskit_text_run_target resolves the position node for one editable owner.
accesskit_text_run_target :: proc(
    publication: ^portable.Control_Tree_Publication,
    owner_id: u64) -> accesskit.Node_Id {
    for control in publication^.controls[:publication^.control_count] {
        if control.parent_native_id == owner_id && control.role == .Text_Run {
            return accesskit.Node_Id(control.native_id)
        }
    }
    return accesskit.Node_Id(owner_id)
}

// accesskit_copy_selection_value validates and copies one TextRun selection.
accesskit_copy_selection_value :: proc(
    request: ^accesskit.Action_Request,
    publication: ^portable.Control_Tree_Publication,
    copied: ^portable.Queued_Action) -> portable.Action_Queue_Status {
    if !request^.data.has_value ||
       request^.data.value.tag != .Set_Text_Selection {return .Invalid_Target}
    selection := request^.data.value.payload.set_text_selection
    target := accesskit_text_run_target(publication, copied^.target_native_id)
    if selection.anchor.node != target || selection.focus.node != target ||
       selection.anchor.character_index > uintptr(max(u16)) ||
       selection.focus.character_index > uintptr(max(u16)) {
        return .Invalid_Target
    }
    copied^.selection_anchor = u16(selection.anchor.character_index)
    copied^.selection_focus = u16(selection.focus.character_index)
    return .Ok
}

// accesskit_copy_action_payload copies one optional native action payload.
accesskit_copy_action_payload :: proc(
    request: ^accesskit.Action_Request,
    publication: ^portable.Control_Tree_Publication,
    copied: ^portable.Queued_Action) -> portable.Action_Queue_Status {
    if request^.action == .Set_Value && request^.data.has_value &&
       request^.data.value.tag == .Numeric_Value {
        copied^.numeric_value = request^.data.value.payload.numeric_value
        copied^.has_numeric_value = true
    }
    text_value := request^.action == .Replace_Selected_Text ||
        request^.action == .Set_Value && request^.data.has_value &&
        request^.data.value.tag == .Value
    if request^.action == .Set_Value && !copied^.has_numeric_value && !text_value {
        return .Invalid_Target
    }
    if text_value {
        copied^.replace_entire_text = request^.action == .Set_Value
        copied^.kind = u16(accesskit.Action.Replace_Selected_Text)
        status := accesskit_copy_text_value(request, copied)
        if status != .Ok {
           return status
        }
    }
    if request^.action == .Set_Text_Selection {
        return accesskit_copy_selection_value(request, publication, copied)
    }
    return .Ok
}

// accesskit_copy_action_request copies one request into bounded owner storage.
accesskit_copy_action_request :: proc(
    owner: ^Adapter,
    request: ^accesskit.Action_Request) -> portable.Action_Queue_Status {
    if owner == nil || request == nil {
       return .Invalid_Target
    }
    generation, live := adapter_action_generation(owner)
    if !live {
       return .Closing
    }
    control_publication: portable.Control_Tree_Publication
    _ = portable.protected_control_snapshot(
        &owner^.control_publication, &control_publication)
    if !accesskit_action_supported(request^.action) {
       return .Invalid_Target
    }
    copied := portable.Queued_Action{
        kind = u16(request^.action),
        target_native_id = u64(request^.target_node),
        publication_generation = generation,
    }
    status := accesskit_copy_action_payload(
        request, &control_publication, &copied)
    if status != .Ok {
       return status
    }
    return portable.action_queue_push(&owner^.actions, &copied)
}

// accesskit_action_callback copies ingress and frees upstream ownership once.
accesskit_action_callback :: proc "c" (
    request: ^accesskit.Action_Request, user_data: rawptr) {
    context = runtime.default_context()
    owner := cast(^Adapter)user_data
    adapter_record_diagnostic(owner, .Action)
    if request == nil {
       return
    }
    defer accesskit.accesskit_action_request_free(request)
    _ = accesskit_copy_action_request(owner, request)
}

// accesskit_deactivation_callback records that native clients no longer need updates.
accesskit_deactivation_callback :: proc "c" (user_data: rawptr) {
    context = runtime.default_context()
    adapter_record_diagnostic(cast(^Adapter)user_data, .Deactivation)
}

// adapter_close_admission rejects callbacks before native teardown begins.
adapter_close_admission :: proc(owner: ^Adapter) {
    if owner == nil {
       return
    }
    portable.protected_close(&owner^.publication)
    portable.protected_control_close(&owner^.control_publication)
    portable.action_queue_close(&owner^.actions)
}