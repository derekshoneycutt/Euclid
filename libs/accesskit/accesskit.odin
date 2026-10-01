package accesskit

import "core:c"

when ODIN_OS == .Windows {
    foreign import accesskit_library "system:accesskit.lib"
} else {
    foreign import accesskit_library "system:accesskit"
}

// Node is opaque storage owned by AccessKit until explicitly freed or transferred.
Node :: struct {}

// Tree_Update is opaque storage owned by AccessKit until freed or transferred.
Tree_Update :: struct {}

// Tree_Info is opaque storage owned by AccessKit until transferred or freed.
Tree_Info :: struct {}

// Unix_Adapter is opaque storage owned by the Linux window session.
Unix_Adapter :: struct {}

// Macos_Subclassing_Adapter is opaque storage owned by the Cocoa window session.
Macos_Subclassing_Adapter :: struct {}

// Macos_Queued_Events is transferred work raised exactly once on the main thread.
Macos_Queued_Events :: struct {}

// Windows_Subclassing_Adapter is opaque storage owned by the Win32 window session.
Windows_Subclassing_Adapter :: struct {}

// Windows_Queued_Events is transferred work raised exactly once on the window thread.
Windows_Queued_Events :: struct {}

Action :: enum u8 {
    Click = 0,
    Focus = 1,
    Blur = 2,
    Collapse = 3,
    Expand = 4,
    Decrement = 6,
    Increment = 7,
    Replace_Selected_Text = 10,
    Scroll_Down = 11,
    Scroll_Left = 12,
    Scroll_Right = 13,
    Scroll_Up = 14,
    Scroll_Into_View = 15,
    Set_Scroll_Offset = 17,
    Set_Text_Selection = 18,
    Set_Value = 20,
}

Role :: enum u8 {
    Unknown = 0,
    Text_Run = 1,
    Label = 3,
    List_Item = 7,
    Paragraph = 13,
    Tree_Item = 9,
    Check_Box = 15,
    Text_Input = 17,
    Button = 18,
    Pane = 20,
    List = 24,
    Search_Input = 32,
    Application = 49,
    Blockquote = 53,
    Disclosure_Triangle = 67,
    Document = 68,
    Math = 92,
    Slider = 113,
    Status = 116,
    Tree = 129,
}

Text_Direction :: enum u8 {
    Left_To_Right = 0,
    Right_To_Left = 1,
    Top_To_Bottom = 2,
    Bottom_To_Top = 3,
}

Live :: enum u8 {
    Off = 0,
    Polite = 1,
    Assertive = 2,
}

Toggled :: enum u8 {
    False = 0,
    True = 1,
    Mixed = 2,
}

Orientation :: enum u8 {
    Horizontal = 0,
    Vertical = 1,
}

Node_Id :: distinct u64

Tree_Id :: struct {
    bytes: [16]u8,
}

Optional_Node_Id :: struct {
    has_value: bool,
    value: Node_Id,
}

Optional_Double :: struct {
    has_value: bool,
    value: f64,
}

Optional_Index :: struct {
    has_value: bool,
    value: uintptr,
}

Rect :: struct {
    x0, y0, x1, y1: f64,
}

Text_Position :: struct {
    node: Node_Id,
    character_index: uintptr,
}

Text_Selection :: struct {
    anchor, focus: Text_Position,
}

Optional_Coords :: struct {
    has_value: bool,
    length: uintptr,
    values: [^]f32,
}

Point :: struct {
    x, y: f64,
}

Action_Data_Tag :: enum c.int {
    Custom_Action = 0,
    Value = 1,
    Numeric_Value = 2,
    Scroll_Unit = 3,
    Scroll_Hint = 4,
    Scroll_To_Point = 5,
    Set_Scroll_Offset = 6,
    Set_Text_Selection = 7,
}

Action_Data :: struct {
    tag: Action_Data_Tag,
    payload: struct #raw_union {
        custom_action: i32,
        value: cstring,
        numeric_value: f64,
        scroll_unit: u8,
        scroll_hint: u8,
        scroll_to_point: Point,
        set_scroll_offset: Point,
        set_text_selection: Text_Selection,
    },
}

Optional_Action_Data :: struct {
    has_value: bool,
    value: Action_Data,
}

Action_Request :: struct {
    action: Action,
    target_tree: Tree_Id,
    target_node: Node_Id,
    data: Optional_Action_Data,
}

Tree_Update_Factory :: proc "c" (user_data: rawptr) -> ^Tree_Update
Activation_Handler :: proc "c" (user_data: rawptr) -> ^Tree_Update
Action_Handler :: proc "c" (request: ^Action_Request, user_data: rawptr)
Deactivation_Handler :: proc "c" (user_data: rawptr)

#assert(size_of(Action) == 1)
#assert(size_of(Role) == 1)
#assert(size_of(Toggled) == 1)
#assert(size_of(Orientation) == 1)
#assert(size_of(Live) == 1)
#assert(size_of(Node_Id) == 8)
#assert(size_of(Tree_Id) == 16)
#assert(size_of(Optional_Node_Id) == 16)
#assert(size_of(Optional_Double) == 16)
#assert(size_of(Optional_Index) == 16)
#assert(size_of(Rect) == 32)
#assert(size_of(Text_Position) == 16)
#assert(size_of(Text_Selection) == 32)
#assert(size_of(Optional_Coords) == 24)
#assert(size_of(Action_Data_Tag) == 4)
#assert(size_of(Action_Data) == 40)
#assert(size_of(Optional_Action_Data) == 48)
#assert(size_of(Action_Request) == 80)

foreign accesskit_library {
    accesskit_node_new :: proc(role: Role) -> ^Node ---
    accesskit_node_free :: proc(node: ^Node) ---
    accesskit_node_role :: proc(node: ^Node) -> Role ---
    accesskit_node_supports_action :: proc(node: ^Node, action: Action) -> bool ---
    accesskit_node_add_action :: proc(node: ^Node, action: Action) ---
    accesskit_node_set_disabled :: proc(node: ^Node) ---
    accesskit_node_set_children :: proc(
        node: ^Node, length: uintptr, values: [^]Node_Id) ---
    accesskit_node_set_controls :: proc(
        node: ^Node, length: uintptr, values: [^]Node_Id) ---
    accesskit_node_set_active_descendant :: proc(node: ^Node, value: Node_Id) ---
    accesskit_node_clear_active_descendant :: proc(node: ^Node) ---
    accesskit_node_set_label :: proc(node: ^Node, value: cstring) ---
    accesskit_node_set_label_with_length :: proc(
        node: ^Node, value: cstring, length: uintptr) ---
    accesskit_node_set_value :: proc(node: ^Node, value: cstring) ---
    accesskit_node_set_value_with_length :: proc(
        node: ^Node, value: cstring, length: uintptr) ---
    accesskit_node_set_placeholder_with_length :: proc(
        node: ^Node, value: cstring, length: uintptr) ---
    accesskit_node_set_character_lengths :: proc(
        node: ^Node, length: uintptr, values: [^]u8) ---
    accesskit_node_character_positions :: proc(
        node: ^Node) -> Optional_Coords ---
    accesskit_node_set_character_positions :: proc(
        node: ^Node, length: uintptr, values: [^]f32) ---
    accesskit_node_character_widths :: proc(
        node: ^Node) -> Optional_Coords ---
    accesskit_node_set_character_widths :: proc(
        node: ^Node, length: uintptr, values: [^]f32) ---
    accesskit_node_set_text_direction :: proc(
        node: ^Node, value: Text_Direction) ---
    accesskit_node_set_word_starts :: proc(
        node: ^Node, length: uintptr, values: [^]u8) ---
    accesskit_node_set_text_selection :: proc(
        node: ^Node, value: Text_Selection) ---
    accesskit_node_set_scroll_y :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_scroll_y_min :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_scroll_y_max :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_level :: proc(node: ^Node, value: uintptr) ---
    accesskit_node_set_size_of_set :: proc(node: ^Node, value: uintptr) ---
    accesskit_node_set_position_in_set :: proc(node: ^Node, value: uintptr) ---
    accesskit_node_set_bounds :: proc(node: ^Node, value: Rect) ---
    accesskit_node_set_numeric_value :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_min_numeric_value :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_max_numeric_value :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_numeric_value_step :: proc(node: ^Node, value: f64) ---
    accesskit_node_set_expanded :: proc(node: ^Node, value: bool) ---
    accesskit_node_set_selected :: proc(node: ^Node, value: bool) ---
    accesskit_node_set_toggled :: proc(node: ^Node, value: Toggled) ---
    accesskit_node_set_orientation :: proc(node: ^Node, value: Orientation) ---
    accesskit_node_set_live :: proc(node: ^Node, value: Live) ---
    accesskit_node_set_busy :: proc(node: ^Node) ---
    accesskit_tree_update_with_capacity_and_focus :: proc(
        capacity: uintptr, focus: Node_Id) -> ^Tree_Update ---
    accesskit_tree_update_free :: proc(update: ^Tree_Update) ---
    accesskit_tree_update_push_node :: proc(
        update: ^Tree_Update, id: Node_Id, node: ^Node) ---
    accesskit_tree_info_new :: proc(root: Node_Id) -> ^Tree_Info ---
    accesskit_tree_info_free :: proc(tree: ^Tree_Info) ---
    accesskit_tree_update_set_tree_info :: proc(
        update: ^Tree_Update, tree: ^Tree_Info) ---
    accesskit_tree_update_set_tree_id :: proc(
        update: ^Tree_Update, tree_id: Tree_Id) ---
    accesskit_rect_new :: proc(x0, y0, x1, y1: f64) -> Rect ---
    accesskit_action_request_free :: proc(request: ^Action_Request) ---
}

when ODIN_OS == .Linux {
    foreign accesskit_library {
        accesskit_unix_adapter_new :: proc(
            activation_handler: Activation_Handler,
            activation_handler_userdata: rawptr,
            action_handler: Action_Handler,
            action_handler_userdata: rawptr,
            deactivation_handler: Deactivation_Handler,
            deactivation_handler_userdata: rawptr) -> ^Unix_Adapter ---
        accesskit_unix_adapter_free :: proc(adapter: ^Unix_Adapter) ---
        accesskit_unix_adapter_set_root_window_bounds :: proc(
            adapter: ^Unix_Adapter, outer, inner: Rect) ---
        accesskit_unix_adapter_update_if_active :: proc(
            adapter: ^Unix_Adapter, update_factory: Tree_Update_Factory,
            update_factory_userdata: rawptr) ---
        accesskit_unix_adapter_update_window_focus_state :: proc(
            adapter: ^Unix_Adapter, is_focused: bool) ---
    }
}

when ODIN_OS == .Darwin {
    foreign accesskit_library {
        accesskit_macos_queued_events_raise :: proc(
            events: ^Macos_Queued_Events) ---
        accesskit_macos_subclassing_adapter_new :: proc(
            view: rawptr,
            activation_handler: Activation_Handler,
            activation_handler_userdata: rawptr,
            action_handler: Action_Handler,
            action_handler_userdata: rawptr) -> ^Macos_Subclassing_Adapter ---
        accesskit_macos_subclassing_adapter_for_window :: proc(
            window: rawptr,
            activation_handler: Activation_Handler,
            activation_handler_userdata: rawptr,
            action_handler: Action_Handler,
            action_handler_userdata: rawptr) -> ^Macos_Subclassing_Adapter ---
        accesskit_macos_subclassing_adapter_free :: proc(
            adapter: ^Macos_Subclassing_Adapter) ---
        accesskit_macos_subclassing_adapter_update_if_active :: proc(
            adapter: ^Macos_Subclassing_Adapter,
            update_factory: Tree_Update_Factory,
            update_factory_userdata: rawptr) -> ^Macos_Queued_Events ---
        accesskit_macos_subclassing_adapter_update_view_focus_state :: proc(
            adapter: ^Macos_Subclassing_Adapter,
            is_focused: bool) -> ^Macos_Queued_Events ---
        accesskit_macos_add_focus_forwarder_to_window_class :: proc(
            class_name: cstring) ---
        accesskit_macos_add_focus_forwarder_to_window_class_with_length :: proc(
            class_name: cstring, length: uintptr) ---
    }
}

when ODIN_OS == .Windows {
    foreign accesskit_library {
        accesskit_windows_queued_events_raise :: proc(
            events: ^Windows_Queued_Events) ---
        accesskit_windows_subclassing_adapter_new :: proc(
            hwnd: rawptr,
            activation_handler: Activation_Handler,
            activation_handler_userdata: rawptr,
            action_handler: Action_Handler,
            action_handler_userdata: rawptr) -> ^Windows_Subclassing_Adapter ---
        accesskit_windows_subclassing_adapter_free :: proc(
            adapter: ^Windows_Subclassing_Adapter) ---
        accesskit_windows_subclassing_adapter_update_if_active :: proc(
            adapter: ^Windows_Subclassing_Adapter,
            update_factory: Tree_Update_Factory,
            update_factory_userdata: rawptr) -> ^Windows_Queued_Events ---
    }
}