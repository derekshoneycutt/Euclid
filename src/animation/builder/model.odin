package buildermodel

import corecolor "../../core/color"
import geometry "../../core/geometry"
import operations "../operations"

BUILDER_JOB_CAPACITY :: 32
BUILDER_POINT_CAPACITY :: 128
BUILDER_DEFAULT_COLOR :: corecolor.Color_RGBA8{70, 130, 180, 255}
BUILDER_DEFAULT_BRUSH_SIZE :: f32(5)

Tool_Mode :: enum u8 {
    None,
    Point,
}

Placement_Phase :: enum u8 {
    Idle,
    Hover,
    Held,
    Waiting,
}

Placement_Status :: enum u8 {
    Ready,
    Point_Queued,
    Queue_Full,
    Point_Capacity_Full,
    Failed,
}

// Identify a point within one Builder generation.
Point_Identity :: struct {
    generation: u64,
    id: u64,
}

// Identify one accepted command within one Builder generation.
Command_Identity :: struct {
    generation: u64,
    id: u64,
}

// Select one operation in the bounded Builder FIFO.
Job_Kind :: enum u8 {
    Construct_Point,
    Edit_Point_Style,
    Hide_Point,
    Show_Point,
}

// Hold the per-field style values captured when a command is accepted.
Point_Style_Edit :: struct {
    color_set: bool,
    color: corecolor.Color_RGBA8,
    brush_set: bool,
    brush_size: f32,
}

// Hold one immutable accepted Builder command.
Job :: struct {
    identity: Command_Identity,
    kind: Job_Kind,
    point: Point_Identity,
    position: geometry.Vector3,
    style: Point_Style_Edit,
}

// Track logical point identity independently of native entity reservation.
Point_State :: enum u8 {
    Pending,
    Constructing,
    Ready,
    Failed,
}

// Retain the captured initial style and current native point projection.
Point_Record :: struct {
    identity: Point_Identity,
    entity: u64,
    position: geometry.Vector3,
    color: corecolor.Color_RGBA8,
    brush_size: f32,
    visible: bool,
    state: Point_State,
}

// Own the bounded FIFO, point records, active result, and generation counters.
Runtime :: struct {
    generation: u64,
    next_command_id: u64,
    next_point_id: u64,
    base_entity_count: u32,
    jobs: [BUILDER_JOB_CAPACITY]Job,
    job_head: int,
    job_count: int,
    points: [BUILDER_POINT_CAPACITY]Point_Record,
    point_count: int,
    active_operation: bool,
    active_reservation: operations.Active_Operation_Reservation,
    failed: bool,
    tool: Tool_Mode,
    color: corecolor.Color_RGBA8,
    palette_index: int,
    brush_size: f32,
    placement_phase: Placement_Phase,
    placement_position: geometry.Vector3,
    gesture_active: bool,
    gesture_style: Point_Style_Edit,
    selected_point: Point_Identity,
    waiting_point: Point_Identity,
    selection_revision: u64,
    placement_status: Placement_Status,
    style_draft_point: Point_Identity,
    style_draft_color: corecolor.Color_RGBA8,
    style_draft_brush_size: f32,
    style_draft_color_dirty: bool,
    style_draft_brush_dirty: bool,
}
