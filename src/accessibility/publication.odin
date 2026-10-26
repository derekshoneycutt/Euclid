package accessibility

import "core:math"
import "core:sync"
import "core:unicode/utf8"
import storage "../core/storage"
import "base:runtime"

STATIC_LABEL_CAPACITY :: 64
SYNTHETIC_ROOT_ID :: u64(1)
STATIC_CHILD_ID :: u64(2)
CONTROL_NODE_CAPACITY :: 320
CONTROL_TEXT_CAPACITY :: 32 * 1024
CONTROL_CHARACTER_CAPACITY :: 1024

// Publication_Role identifies the portable native role for the projected child.
Publication_Role :: enum u8 {
    Label,
    Text_Run,
    Button,
    Checkbox,
    Slider,
    Accordion_Header,
    Panel,
    Status,
    Search_Input,
    Tree,
    Tree_Item,
    Menu,
    Menu_Item,
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
    Replace_Selected_Text,
    Set_Text_Selection,
    Select,
    Expand,
    Collapse,
    Scroll,
    Show_Context_Menu,
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
    parent_native_id: u64,
    active_descendant_native_id: u64,
    controls_native_id: u64,
    role: Publication_Role,
    bounds: Bounds,
    label: string,
    value: string,
    placeholder: string,
    actions: Publication_Action_Set,
    range: Numeric_Range,
    enabled: bool,
    focusable: bool,
    focused: bool,
    checked: bool,
    selected: bool,
    expanded: bool,
    busy: bool,
    text_present: bool,
    text_cursor_byte: int,
    text_anchor_byte: int,
    level: u32,
    position_in_set: u32,
    set_size: u32,
}

// Tree_Publication_Input borrows one complete flat ordinary-control projection.
Tree_Publication_Input :: struct {
    root_bounds: Bounds,
    bounds_scale: f64,
    window_focused: bool,
    controls: []Control_Publication_Input,
}

// Control_Publication owns one copied native-ready ordinary control record.
Control_Publication :: struct {
    native_id: u64,
    parent_native_id: u64,
    active_descendant_native_id: u64,
    controls_native_id: u64,
    role: Publication_Role,
    bounds: Bounds,
    label_offset: int,
    label_length: int,
    value_offset: int,
    value_length: int,
    placeholder_offset: int,
    placeholder_length: int,
    character_offset: int,
    character_count: int,
    cursor_character: int,
    anchor_character: int,
    word_start_offset: int,
    word_start_count: int,
    actions: Publication_Action_Set,
    range: Numeric_Range,
    enabled: bool,
    focusable: bool,
    focused: bool,
    checked: bool,
    selected: bool,
    expanded: bool,
    busy: bool,
    text_present: bool,
    level: u32,
    position_in_set: u32,
    set_size: u32,
}

// Control_Tree_Publication owns a complete rooted ordinary-control tree.
Control_Tree_Publication :: struct {
    generation: u64,
    root_id: u64,
    root_bounds: Bounds,
    bounds_scale: f64,
    window_focused: bool,
    memory: ^storage.Tlsf_Owner,
    controls: []Control_Publication,
    text: []u8,
    character_lengths: []u8,
    word_starts: []u8,
    children: []u64,
    child_offsets: []int,
    child_counts: []int,
    index: map[u64]int,
    control_count: int,
    text_count: int,
    character_count: int,
    word_start_count: int,
}

// Protected_Control_Publication serializes complete tree snapshots for callbacks.
Protected_Control_Publication :: struct {
    mutex: sync.Mutex,
    drained: sync.Cond,
    readers: int,
    memory: ^storage.Tlsf_Owner,
    current: Control_Tree_Publication,
    active: ^Control_Publication_Lease,
    retired: ^Control_Publication_Lease,
    closing: bool,
}

// Control_Publication_Lease pins immutable storage until the callback releases it.
Control_Publication_Lease :: struct {
    value: Control_Tree_Publication,
    readers: int,
    next: ^Control_Publication_Lease,
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
    if !value.present {
        return true
    }
    values: [4]f64 = {value.minimum, value.maximum, value.current, value.step}
    for item in values {
        if math.is_nan(item) || math.is_inf(item) {
            return false
        }
    }
    return value.minimum <= value.current && value.current <= value.maximum &&
        value.minimum <= value.maximum && value.step > 0
}

// control_text_boundary reports whether one byte offset starts a UTF-8 character.
control_text_boundary :: proc(value: string, offset: int) -> bool {
    if offset < 0 || offset > len(value) {
        return false
    }
    if offset == 0 || offset == len(value) {
        return true
    }
    return value[offset] & 0xc0 != 0x80
}

// control_publication_text returns one validated copied string slice.
control_publication_text :: proc(
    value: ^Control_Tree_Publication, offset, length: int) -> string {
    if value == nil {
        return ""
    }
    start := int(offset)
    finish := start + int(length)
    if start < 0 || finish < start || finish > value^.text_count {
        return ""
    }
    return string(value^.text[start:finish])
}

// control_tree_find_id resolves one projected native ID without allocation.
control_tree_find_id :: proc(
    value: ^Control_Tree_Publication, native_id: u64) -> int {
    if value == nil || native_id == 0 {
        return -1
    }
    if index, found := value^.index[native_id]; found {
        return index
    }
    return -1
}

// control_node_validate_relation rejects controls targets absent from the tree.
control_node_validate_relation :: proc(
    value: ^Control_Tree_Publication,
    node: Control_Publication) -> Publication_Status {
    if node.controls_native_id == 0 {
        return .Ok
    }
    if control_tree_find_id(value, node.controls_native_id) < 0 {
        return .Unreachable_Node
    }
    return .Ok
}

// control_node_text_ranges_fit rejects negative and overflowing copied-string ranges.
control_node_text_ranges_fit :: proc(
    value: ^Control_Tree_Publication, node: Control_Publication) -> bool {
    offsets: [3]int = {node.label_offset, node.value_offset, node.placeholder_offset}
    lengths: [3]int = {node.label_length, node.value_length, node.placeholder_length}
    for offset, index in offsets {
        if offset < 0 || offset > value^.text_count || lengths[index] < 0 ||
           lengths[index] > value^.text_count - offset {
            return false
        }
    }
    return true
}

// control_node_validate_characters proves copied UTF-8 widths and selection indices.
control_node_validate_characters :: proc(
    value: ^Control_Tree_Publication, node: Control_Publication,
    text_length: int) -> Publication_Status {
    if !node.text_present {
        return .Ok
    }
    first := node.character_offset
    if first < 0 || first > value^.character_count || node.character_count < 0 ||
       node.character_count > value^.character_count - first ||
       node.cursor_character < 0 || node.cursor_character > node.character_count ||
       node.anchor_character < 0 || node.anchor_character > node.character_count {
        return .Capacity
    }
    byte_count := 0
    for length in value^.character_lengths[first:first + node.character_count] {
        if int(length) > text_length - byte_count {
            return .Invalid_Utf8
        }
        byte_count += int(length)
    }
    if byte_count != text_length {
        return .Invalid_Utf8
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
    if node.role == .Slider && !node.range.present {
        return .Invalid_Bounds
    }
    if !control_node_text_ranges_fit(value, node) {
        return .Capacity
    }
    label := control_publication_text(value, node.label_offset, node.label_length)
    text_value := control_publication_text(
        value, node.value_offset, node.value_length)
    placeholder := control_publication_text(
        value, node.placeholder_offset, node.placeholder_length)
    if !utf8.valid_string(label) || !utf8.valid_string(text_value) ||
       !utf8.valid_string(placeholder) {
        return .Invalid_Utf8
    }
    return control_node_validate_characters(value, node, len(text_value))
}

// control_tree_validate proves IDs, text, bounds, roles, and ranges are complete.
control_tree_validate :: proc(
    value: ^Control_Tree_Publication) -> Publication_Status {
    if value == nil || value^.root_id == 0 {
        return .Invalid_Id
    }
    if !bounds_are_valid(value^.root_bounds) {
        return .Invalid_Bounds
    }
    if value^.control_count < 0 || value^.control_count > len(value^.controls) ||
       value^.text_count < 0 || value^.text_count > len(value^.text) ||
       value^.character_count < 0 ||
       value^.character_count > len(value^.character_lengths) {
        return .Capacity
    }
    for node, index in value^.controls[:value^.control_count] {
        identity_status := Publication_Status.Ok
        if node.native_id == 0 {
            identity_status = .Invalid_Id
        } else if node.native_id == value^.root_id ||
            control_tree_find_id(value, node.native_id) != index {
            identity_status = .Duplicate_Id
        }
        if identity_status != .Ok {
            return identity_status
        }
        relation_status := control_node_validate_relation(value, node)
        if relation_status != .Ok {
            return relation_status
        }
        content_status := control_node_validate_content(value, node)
        if content_status != .Ok {
            return content_status
        }
    }
    return control_tree_validate_graph(value)
}

// control_tree_parents_exist rejects missing parents before child-list construction.
control_tree_parents_exist :: proc(value: ^Control_Tree_Publication) -> bool {
    for node in value^.controls[:value^.control_count] {
        if node.parent_native_id == 0 {
            return false
        }
        if node.parent_native_id != value^.root_id &&
           control_tree_find_id(value, node.parent_native_id) < 0 {
            return false
        }
    }
    return true
}

// control_tree_validate_graph proves rooted ancestry in linear display-owner work.
control_tree_validate_graph :: proc(
    value: ^Control_Tree_Publication) -> Publication_Status {
    if !control_tree_parents_exist(value) {
        return .Missing_Parent
    }
    control_tree_children(value)
    count := value^.control_count + 1
    if count > max(int) / 3 {
        return .Capacity
    }
    allocator := storage.tlsf_owner_allocator(value^.memory)
    scratch, error := make([]int, count * 3, allocator)
    if error != nil {
        return .Capacity
    }
    defer delete(scratch, storage.tlsf_owner_allocator(value^.memory))
    starts, ends, visited :=
        scratch[:count], scratch[count:count * 2], scratch[count * 2:]
    control_tree_walk_root(value, starts, ends, visited)
    for node, index in value^.controls[:value^.control_count] {
        if starts[index + 1] == 0 {
            return .Cycle
        }
        if node.active_descendant_native_id == 0 {
            continue
        }
        child := control_tree_find_id(value, node.active_descendant_native_id) + 1
        if child == 0 || starts[child] <= starts[index + 1] ||
           starts[child] > ends[index + 1] {
            return .Unreachable_Node
        }
    }
    return .Ok
}

// control_tree_walk_root computes ancestry intervals without recursive stack growth.
control_tree_walk_root :: proc(
    value: ^Control_Tree_Publication, starts, ends, visited: []int) {
    current, clock := 0, 1
    starts[0] = clock
    for current >= 0 {
        if visited[current] < value^.child_counts[current] {
            offset := value^.child_offsets[current] + visited[current]
            visited[current] += 1
            child := control_tree_find_id(value, value^.children[offset]) + 1
            clock += 1
            starts[child] = clock
            current = child
            continue
        }
        ends[current] = clock
        if current == 0 {
            break
        }
        current = control_tree_find_id(
            value, value^.controls[current - 1].parent_native_id) + 1
    }
}

// control_tree_copy_text appends one borrowed string into publication-owned storage.
control_tree_copy_text :: proc(
    destination: ^Control_Tree_Publication, value: string,
    offset, length: ^int) -> bool {
    if destination == nil || offset == nil || length == nil ||
       destination^.text_count + len(value) > len(destination^.text) {
        return false
    }
    offset^ = destination^.text_count
    length^ = len(value)
    copy(destination^.text[destination^.text_count:], transmute([]u8)value)
    destination^.text_count += len(value)
    return true
}

// Copy UTF-8 character widths and word starts into bounded publication storage.
control_tree_copy_character_metadata :: proc(
    destination: ^Control_Tree_Publication, node: ^Control_Publication,
    source: Control_Publication_Input) -> bool {
    byte_offset := 0
    previous_space := true
    for byte_offset < len(source.value) {
        if destination^.character_count >= len(destination^.character_lengths) {
            return false
        }
        _, width := utf8.decode_rune(source.value[byte_offset:])
        if width <= 0 || width > int(max(u8)) {
            return false
        }
        if byte_offset < source.text_cursor_byte {
            node^.cursor_character += 1
        }
        if byte_offset < source.text_anchor_byte {
            node^.anchor_character += 1
        }
        destination^.character_lengths[destination^.character_count] = u8(width)
        is_space := source.value[byte_offset] == ' ' ||
            source.value[byte_offset] == '\t' || source.value[byte_offset] == '\n'
        if previous_space && !is_space && node^.character_count <= int(max(u8)) {
            destination^.word_starts[destination^.word_start_count] =
                u8(node^.character_count)
            destination^.word_start_count += 1
            node^.word_start_count += 1
        } else if previous_space && !is_space {
            node^.word_start_count = 0
        }
        previous_space = is_space
        destination^.character_count += 1
        node^.character_count += 1
        byte_offset += width
    }
    return byte_offset == len(source.value)
}

// control_tree_copy_characters copies UTF-8 widths and selection character indices.
control_tree_copy_characters :: proc(
    destination: ^Control_Tree_Publication, node: ^Control_Publication,
    source: Control_Publication_Input) -> bool {
    if !source.text_present {
        return true
    }
    if !control_text_boundary(source.value, source.text_cursor_byte) ||
       !control_text_boundary(source.value, source.text_anchor_byte) {
        return false
    }
    node^.text_present = true
    node^.character_offset = destination^.character_count
    node^.word_start_offset = destination^.word_start_count
    return control_tree_copy_character_metadata(destination, node, source)
}

// control_publication_from_input copies non-text facts into owned storage.
control_publication_from_input :: proc(
    source: Control_Publication_Input) -> Control_Publication {
    return {
        native_id = source.native_id,
        parent_native_id = source.parent_native_id,
        active_descendant_native_id = source.active_descendant_native_id,
        controls_native_id = source.controls_native_id,
        role = source.role,
        bounds = source.bounds,
        actions = source.actions,
        range = source.range,
        enabled = source.enabled,
        focusable = source.focusable,
        focused = source.focused,
        checked = source.checked,
        selected = source.selected,
        expanded = source.expanded,
        busy = source.busy,
        level = source.level,
        position_in_set = source.position_in_set,
        set_size = source.set_size,
    }
}

// control_tree_append copies one source into the next candidate slot.
control_tree_append :: proc(
    candidate: ^Control_Tree_Publication,
    source: Control_Publication_Input) -> Publication_Status {
        if source.text_present &&
           (!control_text_boundary(source.value, source.text_cursor_byte) ||
            !control_text_boundary(source.value, source.text_anchor_byte)) {
            return .Invalid_Utf8
        }
        node := control_publication_from_input(source)
        if node.parent_native_id == 0 {
            node.parent_native_id = candidate^.root_id
        }
        if !control_tree_copy_text(candidate, source.label,
                &node.label_offset, &node.label_length) ||
           !control_tree_copy_text(candidate, source.value,
                 &node.value_offset, &node.value_length) ||
             !control_tree_copy_text(candidate, source.placeholder,
                 &node.placeholder_offset, &node.placeholder_length) ||
             !control_tree_copy_characters(candidate, &node, source) {
            return .Capacity
        }
        candidate^.controls[candidate^.control_count] = node
        candidate^.control_count += 1
    return .Ok
}

// control_tree_candidate initializes normalized root facts for a detached generation.
control_tree_candidate :: proc(
    input: Tree_Publication_Input,
    memory: ^storage.Tlsf_Owner) -> Control_Tree_Publication {
    scale := input.bounds_scale
    if scale <= 0 || math.is_nan(scale) || math.is_inf(scale) {
        scale = 1
    }
    return {
        memory = memory,
        root_id = SYNTHETIC_ROOT_ID,
        root_bounds = input.root_bounds,
        bounds_scale = scale,
        window_focused = input.window_focused,
    }
}

// control_tree_build copies one complete validated ordinary-control projection.
control_tree_build :: proc(
    destination: ^Control_Tree_Publication,
    input: Tree_Publication_Input, memory: ^storage.Tlsf_Owner) -> Publication_Status {
    if destination == nil || memory == nil || !memory.initialized {
        return .Invalid_Id
    }
    if destination^.generation == max(u64) || len(input.controls) == max(int) {
        return .Capacity
    }
    candidate := control_tree_candidate(input, memory)
    if !control_tree_allocate(&candidate, input) {
        control_tree_destroy(&candidate)
        return .Capacity
    }
    for source in input.controls {
        status := control_tree_append(&candidate, source)
        if status != .Ok {
            control_tree_destroy(&candidate)
            return status
        }
        candidate.index[source.native_id] = candidate.control_count - 1
    }
    status := control_tree_validate(&candidate)
    if status == .Ok {
        candidate.generation = destination^.generation + 1
        control_tree_destroy(destination)
        destination^ = candidate
    } else {
        control_tree_destroy(&candidate)
    }
    return status
}

// control_tree_measure checks aggregate lengths before publication allocation.
control_tree_measure :: proc(input: Tree_Publication_Input) -> ([2]int, bool) {
    text_count, character_count := 0, 0
    for source in input.controls {
        texts: [3]string = {source.label, source.value, source.placeholder}
        for text in texts {
            if len(text) > max(int) - text_count {
                return {}, false
            }
            text_count += len(text)
        }
        if source.text_present {
            if len(source.value) > max(int) - character_count {
                return {}, false
            }
            character_count += len(source.value)
        }
    }
    return {text_count, character_count}, true
}

// control_tree_allocate reserves publication storage on the display owner.
control_tree_allocate :: proc(
    value: ^Control_Tree_Publication, input: Tree_Publication_Input) -> bool {
    size, fits := control_tree_measure(input)
    if !fits {
        return false
    }
    error: runtime.Allocator_Error
    allocator := storage.tlsf_owner_allocator(value^.memory)
    value^.controls, error = make([]Control_Publication, len(input.controls),
        allocator)
    if error != nil {
        return false
    }
    value^.text, error = make([]u8, size[0], allocator)
    if error != nil {
        return false
    }
    value^.character_lengths, error = make(
        []u8, size[1], allocator)
    if error != nil {
        return false
    }
    value^.word_starts, error = make(
        []u8, size[1], allocator)
    if error != nil {
        return false
    }
    return control_tree_allocate_relations(value, len(input.controls))
}

// Allocate indexed hierarchy storage in the publication's independently retired domain.
control_tree_allocate_relations :: proc(
    value: ^Control_Tree_Publication, count: int) -> bool {
    error: runtime.Allocator_Error
    allocator := storage.tlsf_owner_allocator(value^.memory)
    value^.children, error = make(
        []u64, count, allocator)
    if error != nil {
        return false
    }
    value^.child_offsets, error = make(
        []int, count + 1, allocator)
    if error != nil {
        return false
    }
    value^.child_counts, error = make(
        []int, count + 1, allocator)
    if error != nil {
        return false
    }
    value^.index, error = make(
        map[u64]int, count, allocator)
    return error == nil
}

// control_tree_destroy reclaims a detached tree exclusively on its display owner.
control_tree_destroy :: proc(value: ^Control_Tree_Publication) {
    if value == nil || value^.memory == nil {
        return
    }
    delete(value^.controls, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.text, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.character_lengths, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.word_starts, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.children, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.child_offsets, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.child_counts, storage.tlsf_owner_allocator(value^.memory))
    delete(value^.index)
    value^ = {}
}

// control_tree_children groups committed child order without callback scratch.
control_tree_children :: proc(value: ^Control_Tree_Publication) {
    for &count in value^.child_counts {
        count = 0
    }
    for node in value^.controls {
        parent := control_tree_find_id(value, node.parent_native_id) + 1
        value^.child_counts[parent] += 1
    }
    offset := 0
    for count, index in value^.child_counts {
        value^.child_offsets[index] = offset
        offset += count
    }
    for node in value^.controls {
        parent := control_tree_find_id(value, node.parent_native_id) + 1
        value^.children[value^.child_offsets[parent]] = node.native_id
        value^.child_offsets[parent] += 1
    }
    for count, index in value^.child_counts {
        value^.child_offsets[index] -= count
    }
}

// protected_publish_controls atomically retains one changed complete tree.
protected_publish_controls :: proc(
    protected: ^Protected_Control_Publication,
    input: Tree_Publication_Input) -> Publication_Status {
    if protected == nil || protected^.memory == nil {
        return .Invalid_Id
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {
        return .Invalid_Id
    }
    if control_tree_matches_input(&protected^.current, input) {
        return .Ok
    }
    if protected^.current.generation == max(u64) {
        return .Capacity
    }
    candidate: Control_Tree_Publication
    status := control_tree_build(&candidate, input, protected^.memory)
    if status != .Ok {
        return status
    }

    allocator := storage.tlsf_owner_allocator(protected^.memory)
    slot, error := new(Control_Publication_Lease, allocator)
    if error != nil {
        control_tree_destroy(&candidate)
        return .Capacity
    }
    candidate.generation = protected^.current.generation + 1
    protected_control_commit(protected, slot, candidate)
    return .Ok
}

// protected_control_commit swaps complete generations while preserving leased predecessors.
protected_control_commit :: proc(
    protected: ^Protected_Control_Publication, slot: ^Control_Publication_Lease,
    candidate: Control_Tree_Publication) {
    slot^.value = candidate
    if protected^.active != nil {
        protected^.active.next = protected^.retired
        protected^.retired = protected^.active
    }
    protected^.active = slot
    protected^.current = candidate
}

// control_input_matches_node compares facts and selections, never backing addresses.
control_input_matches_node :: proc(
    value: ^Control_Tree_Publication, node: Control_Publication,
    source: Control_Publication_Input) -> bool {
    expected := control_publication_from_input(source)
    if expected.parent_native_id == 0 {
        expected.parent_native_id = value^.root_id
    }
    actual := node
    actual.label_offset, actual.label_length = 0, 0
    actual.value_offset, actual.value_length = 0, 0
    actual.placeholder_offset, actual.placeholder_length = 0, 0
    actual.character_offset, actual.character_count = 0, 0
    actual.cursor_character, actual.anchor_character = 0, 0
    actual.word_start_offset, actual.word_start_count = 0, 0
    actual.text_present = false
    if actual != expected || node.text_present != source.text_present ||
       control_publication_text(value,
            node.label_offset, node.label_length) != source.label ||
       control_publication_text(value,
            node.value_offset, node.value_length) != source.value ||
       control_publication_text(value,
            node.placeholder_offset, node.placeholder_length) != source.placeholder {
        return false
    }
    if !source.text_present {
        return true
    }
    return control_input_matches_selection(value, node, source)
}

// Compare byte-addressed selection against the immutable character-width table.
control_input_matches_selection :: proc(
    value: ^Control_Tree_Publication, node: Control_Publication,
    source: Control_Publication_Input) -> bool {
    cursor, anchor := 0, 0
    count := node.character_offset + node.character_count
    for width, index in value^.character_lengths[node.character_offset:count] {
        if index < node.cursor_character {
            cursor += int(width)
        }
        if index < node.anchor_character {
            anchor += int(width)
        }
    }
    return cursor == source.text_cursor_byte && anchor == source.text_anchor_byte
}

// control_tree_matches_input permits unchanged display updates without allocation.
control_tree_matches_input :: proc(
    value: ^Control_Tree_Publication, input: Tree_Publication_Input) -> bool {
    scale := input.bounds_scale
    if scale <= 0 || math.is_nan(scale) || math.is_inf(scale) {
        scale = 1
    }
    if value == nil || value^.generation == 0 ||
       value^.control_count != len(input.controls) ||
       value^.root_bounds != input.root_bounds || value^.bounds_scale != scale ||
       value^.window_focused != input.window_focused {
        return false
    }
    for source, index in input.controls {
        if !control_input_matches_node(value, value^.controls[index], source) {
            return false
        }
    }
    return true
}

// protected_control_acquire borrows immutable storage without callback allocation.
protected_control_acquire :: proc(
    protected: ^Protected_Control_Publication) -> ^Control_Publication_Lease {
    if protected == nil {
        return nil
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing || protected^.active == nil ||
       protected^.readers == max(int) {
        return nil
    }
    protected^.active.readers += 1
    protected^.readers += 1
    return protected^.active
}

// protected_control_release relinquishes a lease; only display collection frees it.
protected_control_release :: proc(
    protected: ^Protected_Control_Publication, lease: ^Control_Publication_Lease) {
    if protected == nil || lease == nil {
        return
    }
    sync.mutex_lock(&protected^.mutex)
    assert(lease^.readers > 0)
    lease^.readers -= 1
    protected^.readers -= 1
    if protected^.readers == 0 {
        sync.cond_broadcast(&protected^.drained)
    }
    sync.mutex_unlock(&protected^.mutex)
}

// protected_control_wait_drained joins accepted readers after native callbacks stop.
protected_control_wait_drained :: proc(protected: ^Protected_Control_Publication) {
    if protected == nil {
        return
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    assert(protected^.closing)
    for protected^.readers > 0 {
        sync.cond_wait(&protected^.drained, &protected^.mutex)
    }
}

// protected_control_collect reclaims retired generations at a display boundary.
protected_control_collect :: proc(protected: ^Protected_Control_Publication) -> bool {
    if protected == nil {
        return true
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    link := &protected^.retired
    for link^ != nil {
        lease := link^
        if lease^.readers != 0 {
            link = &lease^.next
            continue
        }
        link^ = lease^.next
        control_tree_destroy(&lease^.value)
        runtime.mem_free_with_size(lease, size_of(Control_Publication_Lease),
            storage.tlsf_owner_allocator(protected^.memory))
    }
    return protected^.retired == nil
}

// protected_control_snapshot borrows a descriptor for display-owner-only inspection.
protected_control_snapshot :: proc(
    protected: ^Protected_Control_Publication,
    destination: ^Control_Tree_Publication) -> bool {
    if protected == nil || destination == nil {
        return false
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {
        return false
    }
    destination^ = protected^.current
    return destination^.generation != 0
}

// protected_control_close rejects observations before native teardown begins.
protected_control_close :: proc(protected: ^Protected_Control_Publication) {
    if protected == nil {
        return
    }
    sync.mutex_lock(&protected^.mutex)
    protected^.closing = true
    if protected^.active != nil {
        protected^.active.next = protected^.retired
        protected^.retired = protected^.active
        protected^.active = nil
        protected^.current = {}
    }
    sync.mutex_unlock(&protected^.mutex)
}

// publication_validate_child proves the projected child's complete tree contract.
publication_validate_child :: proc(value: ^Static_Publication) -> Publication_Status {
    if value^.child_id == 0 {
        return .Invalid_Id
    }
    if value^.root_id == value^.child_id {
        return .Duplicate_Id
    }
    if value^.child_parent_id == value^.child_id {
        return .Cycle
    }
    if value^.child_parent_id == 0 {
        return .Missing_Parent
    }
    if value^.child_parent_id != value^.root_id {
        return .Unreachable_Node
    }
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
    if value == nil || value^.root_id == 0 {
        return .Invalid_Id
    }
    if !bounds_are_valid(value^.root_bounds) {
        return .Invalid_Bounds
    }
    if !value^.child_present {
        return .Ok
    }
    return publication_validate_child(value)
}

// publication_build creates one complete Phase 1 root and static child.
publication_build :: proc(
    destination: ^Static_Publication, width, height: f64,
    focused: bool) -> Publication_Status {
    if destination == nil {
        return .Invalid_Id
    }
    next_generation := destination^.generation + 1
    candidate: Static_Publication = {
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
    if status == .Ok {
        destination^ = candidate
    }
    return status
}

// publication_build_button creates one complete root and real button projection.
publication_build_button :: proc(
    destination: ^Static_Publication,
    input: Button_Publication_Input) -> Publication_Status {
    if destination == nil || input.child_id == 0 {
        return .Invalid_Id
    }
    if len(input.label) > len(destination^.label) {
        return .Capacity
    }
    candidate: Static_Publication = {
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
    if status == .Ok {
        destination^ = candidate
    }
    return status
}

// publication_build_root creates a root-only tree after the projected button leaves.
publication_build_root :: proc(
    destination: ^Static_Publication, bounds: Bounds,
    focused: bool) -> Publication_Status {
    if destination == nil {
        return .Invalid_Id
    }
    candidate: Static_Publication = {
        generation = destination^.generation + 1,
        root_id = SYNTHETIC_ROOT_ID,
        root_bounds = bounds,
        window_focused = focused,
    }
    status := publication_validate(&candidate)
    if status == .Ok {
        destination^ = candidate
    }
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
    if protected == nil {
        return .Invalid_Id
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {
        return .Invalid_Id
    }
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
    if status != .Ok {
        return status
    }
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
    if protected == nil {
        return .Invalid_Id
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {
        return .Invalid_Id
    }
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
    if protected == nil || destination == nil {
        return false
    }
    sync.mutex_lock(&protected^.mutex)
    defer sync.mutex_unlock(&protected^.mutex)
    if protected^.closing {
        return false
    }
    destination^ = protected^.current
    return publication_validate(destination) == .Ok
}

// protected_close prevents callbacks from observing publication storage as current.
protected_close :: proc(protected: ^Protected_Publication) {
    if protected == nil {
        return
    }
    sync.mutex_lock(&protected^.mutex)
    protected^.closing = true
    sync.mutex_unlock(&protected^.mutex)
}