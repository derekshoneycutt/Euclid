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

Action :: enum u8 {
    Click = 0,
    Focus = 1,
    Blur = 2,
}

Role :: enum u8 {
    Unknown = 0,
    Label = 3,
    Check_Box = 15,
    Text_Input = 17,
    Button = 18,
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
#assert(size_of(Node_Id) == 8)
#assert(size_of(Tree_Id) == 16)
#assert(size_of(Optional_Node_Id) == 16)
#assert(size_of(Optional_Double) == 16)
#assert(size_of(Optional_Index) == 16)
#assert(size_of(Rect) == 32)
#assert(size_of(Text_Position) == 16)
#assert(size_of(Text_Selection) == 32)
#assert(size_of(Action_Data_Tag) == 4)
#assert(size_of(Action_Data) == 40)
#assert(size_of(Optional_Action_Data) == 48)
#assert(size_of(Action_Request) == 80)

foreign accesskit_library {
    accesskit_node_new :: proc(role: Role) -> ^Node ---
    accesskit_node_free :: proc(node: ^Node) ---
    accesskit_node_role :: proc(node: ^Node) -> Role ---
    accesskit_rect_new :: proc(x0, y0, x1, y1: f64) -> Rect ---
    accesskit_action_request_free :: proc(request: ^Action_Request) ---
}