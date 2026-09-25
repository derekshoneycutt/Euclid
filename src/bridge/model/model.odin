package bridgemodel

import animationmodel "../../core/animation"
import color "../../core/color"
import geometry "../../core/geometry"
import storage "../../core/storage"
import dynviewmodel "../../dynview/model"
import evidence_trace "../../evidence/trace"
import presentationmodel "../presentation"
import shapemodel "../../shapes/model"
import "../../julialib"

import "base:runtime"
import "core:encoding/uuid"
import "core:mem"
import vmem "core:mem/virtual"

// SCENE_COMMAND_BATCH_CAPACITY bounds one transactional animation command batch.
SCENE_COMMAND_BATCH_CAPACITY :: animationmodel.ANIMATION_VALUE_PENDING_WRITE_CAPACITY

// View snapshot storage is double-buffered and bounded independently of channel traffic.
VIEW_SNAPSHOT_SLOT_COUNT :: 2
VIEW_SNAPSHOT_TEXT_CAPACITY :: dynviewmodel.DYNVIEW_MAX_TEXT_BYTES
VIEW_SNAPSHOT_ARENA_RESERVATION :: uint(2 * mem.Megabyte)

// Bridge_Color preserves the fixed-width RGBA bridge contract.
Bridge_Color :: color.Color_RGBA8

#assert(size_of(Bridge_Color) == 4)
#assert(align_of(Bridge_Color) == align_of(u8))
#assert(size_of(geometry.Vector3) == 3 * size_of(f32))

// Scene_Command_Kind identifies one display-owned scene mutation request.
Scene_Command_Kind :: enum u8 {
    Set_Shape_Position,
    Set_Shape_Color,
    Set_Shape_Active_Color,
    Set_Shape_Brush,
    Set_Shape_Arc,
    Set_Shape_Trochoid,
    Set_Shape_Trochoid_Frontier,
    Set_Trochoid_Tool,
    Set_Trochoid_Tool_Parameter,
    Set_Shape_Cycloid,
    Set_Shape_Cycloid_Frontier,
    Set_Cycloid_Tool_Line,
    Set_Cycloid_Tool,
    Set_Cycloid_Tool_Parameter,
    Set_Shape_Visible,
    Set_Shape_Active_Feature,
    Set_Tool_Position,
    Set_Tool_Lock,
    Emit_Trailing_Particle,
    Emit_Flicker_Particle,
    Notify_Animation_Cycle_Boundary,
}

// Scene_Command carries one bounded semantic mutation across the host boundary.
Scene_Command :: struct {
    kind: Scene_Command_Kind,
    entity: u64,
    position: geometry.Vector3,
    second_position: geometry.Vector3,
    arc: shapemodel.Shape_Arc,
    trochoid: shapemodel.Shape_Trochoid,
    trochoid_tool: shapemodel.Shape_Trochoid_Tool,
    cycloid: shapemodel.Shape_Cycloid,
    cycloid_tool: shapemodel.Shape_Cycloid_Tool,
    color: Bridge_Color,
    scalar: f32,
    integer: int,
    flag: bool,
}

// Scene_Command_Batch owns one animation tick's transactional scene mutations.
Scene_Command_Batch :: struct {
    animation: ^Euclid_Julia_Animation_Interface,
    command_count: int,
    overflowed: bool,
    animation_value_writes: animationmodel.Animation_Value_Pending_Writes,
    commands: [SCENE_COMMAND_BATCH_CAPACITY]Scene_Command,
}

// Animation_Query_Snapshot is the immutable native state visible to one animation tick.
Animation_Query_Snapshot :: struct {
    shapes: shapemodel.Shape_Query_Snapshot,
    animation_values_valid: bool,
    animation_values: animationmodel.Animation_Value_Snapshot,
}

// View_Snapshot_Slot_State tracks one snapshot through staging and publication.
View_Snapshot_Slot_State :: enum u8 {
    Free,
    Reserved,
    Pending,
    Complete,
    Published,
}

// View_Snapshot owns all bounded source and semantic records for one publication slot.
View_Snapshot :: struct {
    state: View_Snapshot_Slot_State,
    candidate_committed: bool,
    origin: evidence_trace.Identity,
    request_id: u64,
    generation: u64,
    runtime_generation: u64,
    animation_generation: u64,
    animation: ^Euclid_Julia_Animation_Interface,
    presentation_mime: presentationmodel.Presentation_Mime,

    arena: storage.Arena_Owner,
    presentation_builder: storage.Bounded_Byte_Builder,
    command_text_builder: storage.Bounded_Byte_Builder,
    command_builder: storage.Bounded_Element_Builder(dynviewmodel.Dynview_Command),
    math_program_builder:
        storage.Bounded_Element_Builder(dynviewmodel.Dynview_Math_Program),
    math_table_descriptor_builder:
        storage.Bounded_Element_Builder(dynviewmodel.Dynview_Math_Table_Descriptor),
    math_command_builder: storage.Bounded_Element_Builder(dynviewmodel.Dynview_Command),
    math_node_builder: storage.Bounded_Element_Builder(dynviewmodel.Dynview_Math_Node),
    document_text_builder: storage.Bounded_Byte_Builder,
    document_builder: storage.Bounded_Element_Builder(dynviewmodel.Dynview_Document),
    document_block_builder:
        storage.Bounded_Element_Builder(dynviewmodel.Dynview_Document_Block),
    document_inline_builder:
        storage.Bounded_Element_Builder(dynviewmodel.Dynview_Document_Inline),
    document_display_row_builder:
        storage.Bounded_Element_Builder(dynviewmodel.Dynview_Document_Display_Row),

    presentation_bytes: []u8,
    command_text: []u8,
    command_revision: u64,
    stream_has_error: bool,
    stream_open_block: bool,
    stream_open_block_id: i32,
    commands: []dynviewmodel.Dynview_Command,
    math_programs: []dynviewmodel.Dynview_Math_Program,
    math_table_descriptors: []dynviewmodel.Dynview_Math_Table_Descriptor,
    math_commands: []dynviewmodel.Dynview_Command,
    math_nodes: []dynviewmodel.Dynview_Math_Node,
    document_text: []u8,
    documents: []dynviewmodel.Dynview_Document,
    document_blocks: []dynviewmodel.Dynview_Document_Block,
    document_inlines: []dynviewmodel.Dynview_Document_Inline,
    document_display_rows: []dynviewmodel.Dynview_Document_Display_Row,
}

// Animation_Node_Kind identifies one node's role in the Julia animation tree.
Animation_Node_Kind :: enum i32 {
    Category = 1,
    Leaf = 2,
    Terminal = 3,
}

// Animation_Operation identifies a lifecycle operation sent to animation policy.
Animation_Operation :: enum i32 {
    Enter = 1,
    Tick = 2,
    Exit = 3,
}

// Euclid_Julia_Animation_Interface retains one Julia animation entry and tree links.
Euclid_Julia_Animation_Interface :: struct {
    entry: ^julialib.jl_value_t,

    name: string,
    stable_id: uuid.Identifier,
    node_kind: Animation_Node_Kind,
    sibling_order: i32,
    is_expanded: bool,
    is_selected: bool,

    first_child: ^Euclid_Julia_Animation_Interface,
    last_child: ^Euclid_Julia_Animation_Interface,
    parent: ^Euclid_Julia_Animation_Interface,
    next_sibling: ^Euclid_Julia_Animation_Interface,
    prev_sibling: ^Euclid_Julia_Animation_Interface,
    next_in_registry: ^Euclid_Julia_Animation_Interface,
    prev_in_registry: ^Euclid_Julia_Animation_Interface,
}

// Euclid_Julia_Animation_Lookup_Entry stores one bounded registry lookup slot.
Euclid_Julia_Animation_Lookup_Entry :: struct {
    is_occupied: bool,
    stable_id: uuid.Identifier,
    animation: ^Euclid_Julia_Animation_Interface,
}

// Euclid_Julia_Animation_Iterator tracks traversal through the animation registry.
Euclid_Julia_Animation_Iterator :: struct {
    current: ^Euclid_Julia_Animation_Interface,
}

// Euclid_Julia_Interface owns one generation's Julia handles and animation registry.
Euclid_Julia_Interface :: struct {
    invoke_with_exception_diagnostics: ^julialib.jl_value_t,
    init_scripts: ^julialib.jl_value_t,
    ensure_animation_loaded: ^julialib.jl_value_t,
    global_loop: ^julialib.jl_value_t,
    asset_package_identity: [32]byte,
    asset_package_identity_valid: bool,

    null_animation: Euclid_Julia_Animation_Interface,

    current_animation: ^Euclid_Julia_Animation_Interface,
    selected_animation: ^Euclid_Julia_Animation_Interface,
    pending_animation_reset: bool,
    animation_reset_cooldown_remaining: f32,

    animation_head: ^Euclid_Julia_Animation_Interface,
    animation_tail: ^Euclid_Julia_Animation_Interface,
    animation_count: int,

    animation_lookup_entries: []Euclid_Julia_Animation_Lookup_Entry,
    animation_lookup_capacity: int,
    animation_lookup_count: int,

    animation_registry_arena: vmem.Arena,
    animation_registry_allocator: runtime.Allocator,
    animation_registry_arena_initialized: bool,
}