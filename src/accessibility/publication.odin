package accessibility

import "core:math"
import "core:sync"
import "core:unicode/utf8"

STATIC_LABEL_CAPACITY :: 64
SYNTHETIC_ROOT_ID :: u64(1)
STATIC_CHILD_ID :: u64(2)
CONTROL_NODE_CAPACITY :: 63
CONTROL_TEXT_CAPACITY :: 4096

// Publication_Role identifies the portable native role for the projected child.
Publication_Role :: enum u8 {
    Label,
    Button,
    Checkbox,
    Slider,
    Accordion_Header,
    Status,
}

// Publication_Action identifies one owner action accepted by a projected node.
Publication_Action :: enum u8 {
    Focus,
    Activate,
    Toggle,
    Increment,
    Decrement,
    Set_To_Bound,
    Set_Value,
}

Publication_Action_Set :: bit_set[Publication_Action; u16]

// Numeric_Range stores one validated native-ready ranged-control value.
Numeric_Range :: struct {
    minimum: f64,
    maximum: f64,
    current: f64,
    step: f64,
    vertical: bool,
    present: bool,
}

// Control_Publication_Input borrows one complete semantic control for one copy.
Control_Publication_Input :: struct {
    native_id: u64,
    role: Publication_Role,
    bounds: Bounds,
    label: string,
    value: string,
    actions: Publication_Action_Set,
    range: Numeric_Range,
    enabled: bool,
    focusable: bool,
    focused: bool,
    checked: bool,
    selected: bool,
    expanded: bool,
}

// Tree_Publication_Input borrows one complete flat ordinary-control projection.
Tree_Publication_Input :: struct {
    root_bounds: Bounds,
    window_focused: bool,
    controls: []Control_Publication_Input,
}

// Control_Publication owns one copied native-ready ordinary control record.
Control_Publication :: struct {
    native_id: u64,
    role: Publication_Role,
    bounds: Bounds,
    label_offset: u16,
    label_length: u16,
    value_offset: u16,
    value_length: u16,
    actions: Publication_Action_Set,
    range: Numeric_Range,
    enabled: bool,
    focusable: bool,
    focused: bool,
    checked: bool,
    selected: bool,
    expanded: bool,
}

// Control_Tree_Publication owns a complete rooted ordinary-control tree.
Control_Tree_Publication :: struct {
    generation: u64,
    root_id: u64,
    root_bounds: Bounds,
    window_focused: bool,
    controls: [CONTROL_NODE_CAPACITY]Control_Publication,
    text: [CONTROL_TEXT_CAPACITY]u8,
    control_count: int,
    text_count: int,
}

// Protected_Control_Publication serializes complete tree snapshots for callbacks.
Protected_Control_Publication :: struct {
    mutex: sync.Mutex,
    current: Control_Tree_Publication,
    closing: bool,
}

// Button_Publication_Input groups one complete display-owned button projection.
Button_Publication_Input :: struct {
    present: bool,
    child_id: u64,
    root_bounds: Bounds,
    child_bounds: Bounds,
    label: string,
    window_focused: bool,
    child_enabled: bool,
    child_focusable: bool,
    child_focused: bool,
    child_supports_focus: bool,
    child_supports_activate: bool,
}

// Publication_Status identifies one rejected static native-tree fact.
Publication_Status :: enum u8 {
    Ok,
    Invalid_Id,
    Duplicate_Id,
    Missing_Parent,
    Cycle,
    Unreachable_Node,
    Invalid_Utf8,
    Invalid_Bounds,
    Capacity,
}

// Bounds stores one finite non-inverted rectangle in logical window coordinates.
Bounds :: struct {
    x0, y0, x1, y1: f64,
}

// Static_Publication owns every fact exposed by the Phase 1 native tree.
Static_Publication :: struct {
    generation: u64,
    root_id: u64,
    child_present: bool,
    child_id: u64,
    child_parent_id: u64,
    child_role: Publication_Role,
    root_bounds: Bounds,
    child_bounds: Bounds,
    label: [STATIC_LABEL_CAPACITY]u8,
    label_length: int,
    window_focused: bool,
    child_enabled: bool,
    child_focusable: bool,
    child_focused: bool,
    child_supports_focus: bool,
    child_supports_activate: bool,
}

// Protected_Publication serializes callback snapshots with display-owned updates.
Protected_Publication :: struct {
    mutex: sync.Mutex,
    current: Static_Publication,
    closing: bool,
}

// bounds_are_valid accepts only finite rectangles with nonnegative extents.
bounds_are_valid :: proc(bounds: Bounds) -> bool {
    finite := !math.is_nan(bounds.x0) && !math.is_inf(bounds.x0) &&
        !math.is_nan(bounds.y0) && !math.is_inf(bounds.y0) &&
        !math.is_nan(bounds.x1) && !math.is_inf(bounds.x1) &&
        !math.is_nan(bounds.y1) && !math.is_inf(bounds.y1)
    return finite && bounds.x0 <= bounds.x1 && bounds.y0 <= bounds.y1
}

// numeric_range_is_valid accepts finite ordered values and one positive step.
numeric_range_is_valid :: proc(value: Numeric_Range) -> bool {
    if !value.present {return true}
    values := [4]f64{value.minimum, value.maximum, value.current, value.step}
    for item in values {
        if math.is_nan(item) || math.is_inf(item) {return false}
    }
    return value.minimum <= value.current && value.current <= value.maximum &&
        value.minimum <= value.maximum && value.step > 0
}

// control_publication_text returns one validated copied string slice.
control_publication_text :: proc(
    value: ^Control_Tree_Publication, offset, length: u16) -> string {
    if value == nil {return ""}
    start := int(offset)
    finish := start + int(length)
    if start < 0 || finish < start || finish > value^.text_count {return ""}
    return string(value^.text[start:finish])
}

// control_node_validate_identity rejects empty, root, and duplicate native IDs.
control_node_validate_identity :: proc(
    value: ^Control_Tree_Publication,
    node: Control_Publication, index: int) -> Publication_Status {
    if node.native_id == 0 {return .Invalid_Id}
    if node.native_id == value^.root_id {return .Duplicate_Id}
    for prior in value^.controls[:index] {
        if prior.native_id == node.native_id {return .Duplicate_Id}
    }
    return .Ok
}

// control_node_validate_content proves one node's geometry, text, and range.
control_node_validate_content :: proc(
    value: ^Control_Tree_Publication,
    node: Control_Publication) -> Publication_Status {
    if !bounds_are_valid(node.bounds) || !numeric_range_is_valid(node.range) {
        return .Invalid_Bounds
    }
    if node.role == .Slider && !node.range.present {return .Invalid_Bounds}
    label := control_publication_text(value, node.label_offset, node.label_length)
    text_value := control_publication_text(
        value, node.value_offset, node.value_length)
    if !utf8.valid_string(label) || !utf8.valid_string(text_value) {
        return .Invalid_Utf8
    }
    return .Ok
}

// control_tree_validate proves IDs, text, bounds, roles, and ranges are complete.
control_tree_validate :: proc(
    value: ^Control_Tree_Publication) -> Publication_Status {
    if value == nil || value^.root_id == 0 {return .Invalid_Id}
    if !bounds_are_valid(value^.root_bounds) {return .Invalid_Bounds}
    if value^.control_count < 0 || value^.control_count > CONTROL_NODE_CAPACITY ||
       value^.text_count < 0 || value^.text_count > CONTROL_TEXT_CAPACITY {
        return .Capacity
    }
    for node, index in value^.controls[:value^.control_count] {
        identity_status := control_node_validate_identity(value, node, index)
        if identity_status != .Ok {return identity_status}
        content_status := control_node_validate_content(value, node)
        if content_status != .Ok {return content_status}
    }
    return .Ok
}

// control_tree_copy_text appends one borrowed string into publication-owned storage.
control_tree_copy_text :: proc(
    destination: ^Control_Tree_Publication, value: string,
    offset, length: ^u16) -> bool {
    if destination == nil || offset == nil || length == nil ||
       destination^.text_count + len(value) > len(destination^.text) {
        return false
    }
    offset^ = u16(destination^.text_count)
    length^ = u16(len(value))
    copy(destination^.text[destination^.text_count:], transmute([]u8)value)
    destination^.text_count += len(value)
    return true
}

// control_tree_build copies one complete validated ordinary-control projection.
control_tree_build :: proc(
    destination: ^Control_Tree_Publication,
    input: Tree_Publication_Input) -> Publication_Status {
    if destination == nil {return .Invalid_Id}
    if len(input.controls) > CONTROL_NODE_CAPACITY {return .Capacity}
    candidate := Control_Tree_Publication{
        root_id = SYNTHETIC_ROOT_ID,
        root_bounds = input.root_bounds,
        window_focused = input.window_focused,
    }
    for source, index in input.controls {
        node := Control_Publication{
            native_id = source.native_id, role = source.role,
            bounds = source.bounds, actions = source.actions, range = source.range,
            enabled = source.enabled, focusable = source.focusable,
            focused = source.focused, checked = source.checked,
            selected = source.selected, expanded = source.expanded,
        }
        if !control_tree_copy_text(&candidate, source.label,
                &node.label_offset, &node.label_length) ||
           !control_tree_copy_text(&candidate, source.value,
                &node.value_offset, &node.value_length) {
            return .Capacity
        }
        candidate.controls[index] = node
        candidate.control_count += 1
    }
    status := control_tree_validate(&candidate)
    if status == .Ok {
        candidate.generation = destination^.generation + 1
        destination^ = candidate
    }
    return status
}

// control_trees_match reports semantic equality while ignoring generation.
control_trees_match :: proc(
    left, right: Control_Tree_Publication) -> bool {
    normalized_left := left
    normalized_right := right
    normalized_left.generation = 0
    normalized_right.generation = 0
    return normalized_left == normalized_right
}

// protected_publish_controls atomically retains one changed complete tree.
protected_publish_controls :: proc(
    protected: ^Protected_Control_Publication,
    input: Tree_Publication_Input) -> Publication_Status {
    if protected == nil {return .Invalid_Id}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return .Invalid_Id}
    candidate: Control_Tree_Publication
    status := control_tree_build(&candidate, input)
    if status != .Ok {return status}
    if control_tree_validate(&protected^.current) == .Ok &&
       control_trees_match(protected^.current, candidate) {
        return .Ok
    }
    candidate.generation = protected^.current.generation + 1
    protected^.current = candidate
    return .Ok
}

// protected_control_snapshot copies one immutable complete callback view.
protected_control_snapshot :: proc(
    protected: ^Protected_Control_Publication,
    destination: ^Control_Tree_Publication) -> bool {
    if protected == nil || destination == nil {return false}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return false}
    destination^ = protected^.current
    return control_tree_validate(destination) == .Ok
}

// protected_control_close rejects observations before native teardown begins.
protected_control_close :: proc(protected: ^Protected_Control_Publication) {
    if protected == nil {return}
    sync.mutex_lock(&protected^.mutex)
    protected^.closing = true
    sync.mutex_unlock(&protected^.mutex)
}

// publication_validate_child proves the projected child's complete tree contract.
publication_validate_child :: proc(value: ^Static_Publication) -> Publication_Status {
    if value^.child_id == 0 {return .Invalid_Id}
    if value^.root_id == value^.child_id {return .Duplicate_Id}
    if value^.child_parent_id == value^.child_id {return .Cycle}
    if value^.child_parent_id == 0 {return .Missing_Parent}
    if value^.child_parent_id != value^.root_id {return .Unreachable_Node}
    if value^.label_length < 0 || value^.label_length > len(value^.label) {
        return .Capacity
    }
    if !utf8.valid_string(string(value^.label[:value^.label_length])) {
        return .Invalid_Utf8
    }
    if !bounds_are_valid(value^.root_bounds) ||
       !bounds_are_valid(value^.child_bounds) {
        return .Invalid_Bounds
    }
    return .Ok
}

// publication_validate proves the complete rooted-tree contract.
publication_validate :: proc(value: ^Static_Publication) -> Publication_Status {
    if value == nil || value^.root_id == 0 {return .Invalid_Id}
    if !bounds_are_valid(value^.root_bounds) {return .Invalid_Bounds}
    if !value^.child_present {return .Ok}
    return publication_validate_child(value)
}

// publication_build creates one complete Phase 1 root and static child.
publication_build :: proc(
    destination: ^Static_Publication, width, height: f64,
    focused: bool) -> Publication_Status {
    if destination == nil {return .Invalid_Id}
    next_generation := destination^.generation + 1
    candidate := Static_Publication{
        generation = next_generation,
        root_id = SYNTHETIC_ROOT_ID,
        child_present = true,
        child_id = STATIC_CHILD_ID,
        child_parent_id = SYNTHETIC_ROOT_ID,
        child_role = .Label,
        root_bounds = {0, 0, width, height},
        child_bounds = {0, 0, width, height},
        window_focused = focused,
    }
    label := "Euclid workspace"
    copy(candidate.label[:], transmute([]u8)label)
    candidate.label_length = len(label)
    status := publication_validate(&candidate)
    if status == .Ok {destination^ = candidate}
    return status
}

// publication_build_button creates one complete root and real button projection.
publication_build_button :: proc(
    destination: ^Static_Publication,
    input: Button_Publication_Input) -> Publication_Status {
    if destination == nil || input.child_id == 0 {return .Invalid_Id}
    if len(input.label) > len(destination^.label) {return .Capacity}
    candidate := Static_Publication{
        generation = destination^.generation + 1,
        root_id = SYNTHETIC_ROOT_ID,
        child_present = true,
        child_id = input.child_id,
        child_parent_id = SYNTHETIC_ROOT_ID,
        child_role = .Button,
        root_bounds = input.root_bounds,
        child_bounds = input.child_bounds,
        window_focused = input.window_focused,
        child_enabled = input.child_enabled,
        child_focusable = true,
        child_focused = input.child_focused,
        child_supports_focus = true,
        child_supports_activate = true,
    }
    copy(candidate.label[:], transmute([]u8)input.label)
    candidate.label_length = len(input.label)
    status := publication_validate(&candidate)
    if status == .Ok {destination^ = candidate}
    return status
}

// publication_build_root creates a root-only tree after the projected button leaves.
publication_build_root :: proc(
    destination: ^Static_Publication, bounds: Bounds,
    focused: bool) -> Publication_Status {
    if destination == nil {return .Invalid_Id}
    candidate := Static_Publication{
        generation = destination^.generation + 1,
        root_id = SYNTHETIC_ROOT_ID,
        root_bounds = bounds,
        window_focused = focused,
    }
    status := publication_validate(&candidate)
    if status == .Ok {destination^ = candidate}
    return status
}

// publications_match reports semantic equality while ignoring generation counters.
publications_match :: proc(left, right: Static_Publication) -> bool {
    normalized_left := left
    normalized_right := right
    normalized_left.generation = 0
    normalized_right.generation = 0
    return normalized_left == normalized_right
}

// protected_publish_button atomically publishes one changed button or root-only tree.
protected_publish_button :: proc(
    protected: ^Protected_Publication,
    input: Button_Publication_Input) -> Publication_Status {
    if protected == nil {return .Invalid_Id}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return .Invalid_Id}
    candidate: Static_Publication
    status := Publication_Status.Ok
    if input.present {
        status = publication_build_button(&candidate, input)
        candidate.child_focusable = input.child_focusable
        candidate.child_supports_focus = input.child_supports_focus
        candidate.child_supports_activate = input.child_supports_activate
    } else {
        status = publication_build_root(
            &candidate, input.root_bounds, input.window_focused)
    }
    if status != .Ok {return status}
    if publication_validate(&protected^.current) == .Ok &&
       publications_match(protected^.current, candidate) {
        return .Ok
    }
    candidate.generation = protected^.current.generation + 1
    protected^.current = candidate
    return .Ok
}

// protected_publish atomically replaces the last good publication.
protected_publish :: proc(
    protected: ^Protected_Publication, width, height: f64,
    focused: bool) -> Publication_Status {
    if protected == nil {return .Invalid_Id}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return .Invalid_Id}
    current := &protected^.current
    if publication_validate(current) == .Ok &&
       current^.root_bounds.x1 == width && current^.root_bounds.y1 == height &&
         current^.window_focused == focused {
        return .Ok
    }
    return publication_build(&protected^.current, width, height, focused)
}

// protected_snapshot copies one immutable callback view while admission remains open.
protected_snapshot :: proc(
    protected: ^Protected_Publication,
    destination: ^Static_Publication) -> bool {
    if protected == nil || destination == nil {return false}
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {return false}
    destination^ = protected^.current
    return publication_validate(destination) == .Ok
}

// protected_close prevents callbacks from observing publication storage as current.
protected_close :: proc(protected: ^Protected_Publication) {
    if protected == nil {return}
    sync.mutex_lock(&protected^.mutex)
    protected^.closing = true
    sync.mutex_unlock(&protected^.mutex)
}