package core

// Defines the core structures used in the Euclid Application.
// The general bias is to just allocate memory upfront inside EuclidGeneralState and
// stick to that memory, except for a few UI helpers using temp_allocator, Julia's GC, and GIFs.
// This creates some hard caps on e.g. the particle system, but it also prevents wildness.

import "../julialib"
import "base:runtime"
import "core:encoding/uuid"
import vmem "core:mem/virtual"
import "core:sync/chan"
import "core:thread"
import "core:time"

import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 8192//4096
MAX_PARTICLES :: 2048
MAX_METAVALUES :: 256
MAX_SHAPESPOINTS :: 256
MAX_SHAPESCONSTRAINTS :: 256
MAX_DRAW_CACHE_POLYGON_VERTICES :: MAX_SHAPESPOINTS
MAX_DRAW_CACHE_POLYGON_TRIANGLES :: MAX_SHAPESPOINTS

DUST_GRID_CELL_SIZE :: 0.02
DUST_GRID_DIM :: 50
DUST_GRID_DIM_SQUARED :: DUST_GRID_DIM * DUST_GRID_DIM
DUST_GRID_BUCKET_CAP :: 16
DUST_GRID_BUCKET_COUNT :: DUST_GRID_DIM_SQUARED * DUST_GRID_BUCKET_CAP
DUST_COLLISION_PAIR_CAP :: MAX_LOW_PARTICLES * 16

TOOL_LENGTH :: 0.35

DYNVIEW__MAX_COMMANDS :: 1024
DYNVIEW__MAX_TEXT_BYTES :: 32 * 1024
DYNVIEW__MAX_LAYOUT_LINES :: 4096
DYNVIEW__MAX_LAYOUT_ITEMS :: 8192
DYNVIEW__MAX_MATH_PROGRAMS :: 256
DYNVIEW__MAX_MATH_NODES :: 4096
DYNVIEW__MAX_MATH_COMMANDS :: 4096

FONT_VARIANT_SLOT_COUNT :: 14

Vector2 :: rl.Vector2
Vector3 :: rl.Vector3

JULIA_REQUEST_CAPACITY :: 16
JULIA_EVENT_CAPACITY :: 16
SCRATCHPAD_ASYNC_SLOT_COUNT :: 16
SCRATCHPAD_ASYNC_TEXT_CAPACITY :: 4096
VIEW_SNAPSHOT_SLOT_COUNT :: 2
VIEW_SNAPSHOT_TEXT_CAPACITY :: DYNVIEW__MAX_TEXT_BYTES
ANIMATION_TICK_SLOT_COUNT :: 2

SCENE_COMMAND_BATCH_CAPACITY :: 64
SCENE_COMMAND_POINT_BATCH_CAPACITY :: 8


/****
    Starting with the Julia Animation tree structures
*/


Euclid_Julia_Animation_Interface :: struct {
    get_view_text : ^julialib.jl_value_t,
    initiate : ^julialib.jl_value_t, // initiate the animation type
    loop : ^julialib.jl_value_t, // ran each dt in the main window loop
    clean : ^julialib.jl_value_t, // stop and clear animations

    name : string,
    stable_id : uuid.Identifier,
    is_expanded : bool,
    is_selected : bool,

    first_child : ^Euclid_Julia_Animation_Interface,
    last_child : ^Euclid_Julia_Animation_Interface,
    parent : ^Euclid_Julia_Animation_Interface,
    next_sibling : ^Euclid_Julia_Animation_Interface,
    prev_sibling : ^Euclid_Julia_Animation_Interface,
    next_in_registry : ^Euclid_Julia_Animation_Interface,
    prev_in_registry : ^Euclid_Julia_Animation_Interface,
}

Euclid_Julia_Animation_Lookup_Entry :: struct {
    is_occupied : bool,
    stable_id : uuid.Identifier,
    animation : ^Euclid_Julia_Animation_Interface,
}

Euclid_Julia_Animation_Iterator :: struct {
    current : ^Euclid_Julia_Animation_Interface,
}

Euclid_Julia_Interface :: struct {
    init_scripts : ^julialib.jl_value_t,
    global_loop : ^julialib.jl_value_t,
    scratchpad_classify_input : ^julialib.jl_value_t,
    scratchpad_complete_backslash : ^julialib.jl_value_t,
    scratchpad_complete_input : ^julialib.jl_value_t,
    scratchpad_queue_input : ^julialib.jl_value_t,
    scratchpad_save_history_to_file : ^julialib.jl_value_t,
    scratchpad_history_previous : ^julialib.jl_value_t,
    scratchpad_history_next : ^julialib.jl_value_t,
    scratchpad_history_reset_cursor : ^julialib.jl_value_t,
    asset_archive_mod_time_unix_nano: i64,

    null_animation : Euclid_Julia_Animation_Interface,

    current_animation : ^Euclid_Julia_Animation_Interface,
    selected_animation : ^Euclid_Julia_Animation_Interface,
    pending_animation_reset : bool,
    animation_reset_cooldown_remaining : f32,

    animation_head : ^Euclid_Julia_Animation_Interface,
    animation_tail : ^Euclid_Julia_Animation_Interface,
    animation_count : int,

    animation_lookup_entries : []Euclid_Julia_Animation_Lookup_Entry,
    animation_lookup_capacity : int,
    animation_lookup_count : int,

    animation_name_arena: vmem.Arena,
    animation_name_allocator: runtime.Allocator,
    animation_name_arena_initialized: bool,
}


/****
    The Shape system, used to draw the tools and the various points/lines/shapes/polygons

    Point and Constraint are the primitive types; the others are shorthands for representing
    them between function calls, outside of the array of points/constraints

    The draw cache are computed through a lerp for preparation before draw
*/






Shapes_Point_Type :: enum {
    Label,
    Point,
    Line,
    Circle,
    FilledCircle,
    Triangle,
    Square,
    Pentagon,
    Pen,
    Compass,
}

Shapes_Label_Decoration_Kind :: enum {
    None,
    Prime,
    DoublePrime,
    TriplePrime,
    Hat,
    Bar,
}

Shapes_Point :: struct {
    kind : Shapes_Point_Type,

    position : Maybe(Vector3),
    previous_position : Maybe(Vector3),
    color : Maybe(rl.Color),
    active_color : Maybe(rl.Color),
    brush_size : f32,
    offset : f32,
    label : Maybe(rune),
    decoration_kind : Shapes_Label_Decoration_Kind,

    active_child: int,
    child_count : int,
    child_point_head : int,
    next_child_point : int,

    do_draw : bool,
}

Shapes_Constraint_Kind :: enum {
    Distance,
    Floor,
    SnapToFloor,
    SnapPoint,
    MaxAngle,
    MinAngle,
    CenterPivot,
}

Shapes_Constraint :: struct {
    kind : Shapes_Constraint_Kind,

    on_point : int,
    restriction : Vector3,
    bounce : f32,
    allowance : f32,
    depend_on : i32,
    child_offset : Maybe(i32),

    do_apply : bool,
}

Shapes_Compass :: struct {
    host_id : int,
    joint1_id : int,
    pivot_id : int,
    joint2_id : int,

    center_pivot_id : int,
    limb1_length_id : int,
    limb2_length_id : int,
    point1_floor_id : int,
    pivot_floor_id : int,
    point2_floor_id : int,
    lock_point1_id : int,
    lock_point2_id : int,
}

Shapes_Pen :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,

    length_constraint_id : int,
    point1_floor_id : int,
    point2_floor_id : int,
    lock_point1_id : int,
    lock_point2_id : int,
}

Shapes_Line :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
}

Shapes_Circle :: struct {
    host_id : int,
    start_id : int,
    end_id : int,
}

Shapes_Filled_Circle :: struct {
    host_id : int,
    start_id : int,
    end_id : int,
}

Shapes_Triangle :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
}

Shapes_Square :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
    joint4_id : int,
}

Shapes_Pentagon :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
    joint4_id : int,
    joint5_id : int,
}

Shapes_Draw_Base :: struct {
    kind: Shapes_Point_Type,
    source_index: int,
    brush_size: f32,
    color: rl.Color,
    active_color: rl.Color,
    has_active_color: bool,
    active_child: int,
}

Shapes_Label_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
    label: rune,
    decoration_kind: Shapes_Label_Decoration_Kind,
}

Shapes_Point_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
}

Shapes_Line_Draw :: struct {
    using base: Shapes_Draw_Base,
    point1: Vector3,
    point2: Vector3,
}

Shapes_Circle_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    start: Vector3,
    end: Vector3,
    offset: f32,
}

Shapes_Filled_Circle_Draw :: struct {
    using base: Shapes_Draw_Base,
    center: Vector3,
    start: Vector3,
    end: Vector3,
    offset: f32,
}

Shapes_Polygon_Ring_Node :: struct {
    prev: int,
    next: int,
    active: bool,
}

Shapes_Polygon_Triangle :: struct {
    a: int,
    b: int,
    c: int,
}

Shapes_Polygon_Draw :: struct {
    using base: Shapes_Draw_Base,
    first_vertex: int,
    vertex_count: int,
    first_triangle: int,
    triangle_count: int,
}

Shapes_Pen_Draw :: struct {
    using base: Shapes_Draw_Base,
    joint1: Vector3,
    joint2: Vector3,
}

Shapes_Compass_Draw :: struct {
    using base: Shapes_Draw_Base,
    joint1: Vector3,
    pivot: Vector3,
    joint2: Vector3,
}

Shapes_Draw_Cache_Item :: union {
    Shapes_Label_Draw,
    Shapes_Point_Draw,
    Shapes_Line_Draw,
    Shapes_Circle_Draw,
    Shapes_Filled_Circle_Draw,
    Shapes_Polygon_Draw,
    Shapes_Pen_Draw,
    Shapes_Compass_Draw,
}

Shapes_Draw_Cache :: struct {
    items: [MAX_SHAPESPOINTS]Shapes_Draw_Cache_Item,
    item_count: int,

    polygon_vertices: [MAX_DRAW_CACHE_POLYGON_VERTICES]Vector3,
    polygon_vertex_count: int,
    polygon_triangles: [MAX_DRAW_CACHE_POLYGON_TRIANGLES]Shapes_Polygon_Triangle,
    polygon_triangle_count: int,
    polygon_ring_nodes: [MAX_DRAW_CACHE_POLYGON_VERTICES]Shapes_Polygon_Ring_Node,

    pen: Shapes_Pen_Draw,
    draw_pen: bool,
    compass: Shapes_Compass_Draw,
    draw_compass: bool,
}

Shapes_Point_System :: struct {
    draw_cache : Shapes_Draw_Cache,

    points : [MAX_SHAPESPOINTS]Shapes_Point,
    constraints : [MAX_SHAPESCONSTRAINTS]Shapes_Constraint,
    next_point_index : int,
    next_constraint_index : int,

    anim_points_start : int,
    anim_constraints_start : int,
}


/****
    The particle system is basically a 3-layered SoA system, each layer having its own type
    of particles.
*/






Particle :: struct {
    pos_x : f32,
    pos_y : f32,
    pos_z : f32,
    vel_x : f32,
    vel_y : f32,
    vel_z : f32,

    age : f32,
    life : f32,
    size : f32,
    ember_size_start : f32,
    ember_size_end : f32,
    ember_white_at_birth : f32,
    color : rl.Color,
    alive : bool,
    lit_frames : i16,
}

Particle_System :: struct {
    low_particles : #soa[MAX_LOW_PARTICLES]Particle,
    particles : #soa[MAX_PARTICLES]Particle,
    high_particles : #soa[MAX_PARTICLES]Particle,

    dust_buckets : [DUST_GRID_BUCKET_COUNT]i32,
    dust_counts : [DUST_GRID_DIM_SQUARED]i32,
    dust_pair_a : [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_b : [DUST_COLLISION_PAIR_CAP]i32,
    dust_pair_count : int,
    dust_pair_dropped_count : int,

    next_index : int,
    spawn_timer : f32,
    rng_state : u64,

    last_render_low : int,
    last_render_mid : int,
    last_render_high : int,

    use_max_dust_particles : int,
}





/****
    Draw scaling and framing information; controls for screen shaking and Isometric Scaling
*/


Iso_Scale :: struct {
    scale : f32,
    x_offset : f32,
    y_offset : f32,

    half_scale : f32,
    quarter_scale : f32,

    main_light_dir : Vector3,
    use_directional_shadow : bool,

    screenshake_trauma : f32,
    screenshake_elapsed : f32,
    screenshake_offset_x : f32,
    screenshake_offset_y : f32,
    screenshake_phase : f32,
}




/****
    Dynview is just dynamic view, not original lol. It is a dynamic text construction,
    including limited LaTeX style support
*/



Font_Weight :: enum {
    Light,
    Regular,
    Medium,
    SemiBold,
    Bold,
    ExtraBold,
    Black,
}

Font_Variant_Flags :: enum u32 {
    None = 0,
    Italic = 1 << 0,
    Light = 1 << 1,
    Regular = 1 << 2,
    Medium = 1 << 3,
    SemiBold = 1 << 4,
    Bold = 1 << 5,
    ExtraBold = 1 << 6,
    Black = 1 << 7,
}

Dynview_Text_Alignment :: enum {
    Left,
    Center,
}

Dynview_Text_Style :: struct {
    color: rl.Color,
    alignment: Dynview_Text_Alignment,
    bold: bool,
    italic: bool,
    font_flags: Font_Variant_Flags,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
    force_line_start: bool,
    wrap_scale: f32,
}

Dynview_Matrix_Column_Alignment :: enum i32 {
    Left = 0,
    Center = 1,
    Right = 2,
}

Dynview_Command_Kind :: enum {
    BeginBlock,
    EndBlock,
    TextRun,
    MathGlyphRun,
    MathBlock,
    ScriptAttachRecursive,
    FracRecursive,
    StretchDelimiterRecursive,
    MatrixRecursive,
    LargeOpRecursive,
    AccentBarRecursive,
    RadicalBarRecursive,
    CopyableTextRun,
    LineBreak,
    Divider,
    InlineLine,
    InlineBox,
    InlineCircle,
    InlineFilledBox,
    InlineFilledCircle,
    InlinePieSection,
}

Dynview_Command :: struct {
    kind: Dynview_Command_Kind,
    block_id: i32,
    style_id: i32,
    math_program_id: i32,
    secondary_math_program_id: i32,
    text_offset: int,
    text_len: int,
    script_base_text_offset: int,
    script_base_text_len: int,
    script_sup_text_offset: int,
    script_sup_text_len: int,
    script_sub_text_offset: int,
    script_sub_text_len: int,
    script_style_id: i32,
    script_scale: f32,
    script_sup_raise: f32,
    script_sub_drop: f32,
    script_gap: f32,
    accent_mode: i32,
    radical_mode: i32,
    large_op_kind: i32,
    radical_index_text_offset: int,
    radical_index_text_len: int,
    accent_style_id: i32,
    accent_thickness: f32,
    accent_offset: f32,
    copy_text_offset: int,
    copy_text_len: int,
    inline_atom_dimension: f32,
    inline_atom_stroke: f32,
    inline_box_height: f32,
    has_brush_color: bool,
    brush_color: rl.Color,
    inline_outline_stroke: f32,
    pie_start_angle_degrees: f32,
    pie_end_angle_degrees: f32,
}

Dynview_Copy_Block :: struct {
    block_id: i32,
    block_kind: i32,
    row_start: int,
    row_end: int,
    payload_offset: int,
    payload_len: int,
}

Dynview_Copy_Hit_Target :: struct {
    block_id: i32,
    payload_offset: int,
    payload_len: int,
    rect: rl.Rectangle,
    hover_rect: rl.Rectangle,
}

Dynview_Layout_Item_Kind :: enum {
    TextRun,
    MathGlyphRun,
    MathBlock,
    ScriptAttachRecursive,
    FracRecursive,
    StretchDelimiterRecursive,
    MatrixRecursive,
    LargeOpRecursive,
    AccentBarRecursive,
    RadicalBarRecursive,
    InlineLine,
    InlineBox,
    InlineCircle,
    InlineFilledBox,
    InlineFilledCircle,
    InlinePieSection,
}

Dynview_Layout_Item :: struct {
    kind: Dynview_Layout_Item_Kind,
    block_id: i32,
    style_id: i32,
    math_program_id: i32,
    secondary_math_program_id: i32,
    line_index: int,
    col_start: int,
    col_span: int,
    text_offset: int,
    text_len: int,
    script_sup_text_offset: int,
    script_sup_text_len: int,
    script_sub_text_offset: int,
    script_sub_text_len: int,
    script_style_id: i32,
    script_scale: f32,
    script_sup_raise: f32,
    script_sub_drop: f32,
    script_gap: f32,
    accent_mode: i32,
    radical_mode: i32,
    large_op_kind: i32,
    radical_index_text_offset: int,
    radical_index_text_len: int,
    accent_style_id: i32,
    accent_thickness: f32,
    accent_offset: f32,
    inline_atom_dimension: f32,
    inline_atom_stroke: f32,
    inline_box_height: f32,
    has_brush_color: bool,
    brush_color: rl.Color,
    inline_outline_stroke: f32,
    pie_start_angle_degrees: f32,
    pie_end_angle_degrees: f32,
    x_offset: f32,
    y_offset: f32,
    draw_width: f32,
    draw_height: f32,
    ascent: f32,
    descent: f32,
    visual_padding_top: f32,
    visual_padding_bottom: f32,
}

Dynview_Math_Node_Kind :: enum {
    None,
    Sequence,
    GlyphRun,
    Script,
    Radical,
    Fraction,
    StretchDelimiter,
}

Dynview_Math_Node :: struct {
    kind: Dynview_Math_Node_Kind,
    style_id: i32,
    text_offset: int,
    text_len: int,
    first_child: int,
    child_count: int,
    base_child: int,
    superscript_child: int,
    subscript_child: int,
    radicand_child: int,
    index_child: int,
    numerator_child: int,
    denominator_child: int,
    x_offset: f32,
    y_offset: f32,
    draw_width: f32,
    ascent: f32,
    descent: f32,
}

Dynview_Math_Program :: struct {
    valid: bool,
    root_node_index: int,
    node_start: int,
    node_count: int,
    command_start: int,
    command_count: int,
    copy_text_offset: int,
    copy_text_len: int,
    draw_width: f32,
    ascent: f32,
    descent: f32,
    visual_padding_top: f32,
    visual_padding_bottom: f32,
}

Dynview_Layout_Line :: struct {
    item_start: int,
    item_count: int,
    y_offset: f32,
    line_height: f32,
    baseline: f32,
    max_ascent: f32,
    max_descent: f32,
}

Dynview_Command_Buffer :: struct {
    revision: u64,
    command_count: int,
    text_bytes_len: int,
    has_stream_error: bool,
    stream_open_block: bool,
    stream_open_block_id: i32,

    commands: [DYNVIEW__MAX_COMMANDS]Dynview_Command,
    text_bytes: [DYNVIEW__MAX_TEXT_BYTES]u8,
}

Dynview_Compile_Cache :: struct {
    compiled_revision: u64,
    compiled_command_count: int,
    compiled_text_bytes_len: int,
    compiled_plain_text_len: int,
    compiled_copy_payload_len: int,
    copy_block_count: int,
    copy_hit_target_count: int,
    layout_line_count: int,
    layout_item_count: int,
    math_program_count: int,
    math_command_count: int,
    math_node_count: int,
    layout_is_valid: bool,
    is_valid: bool,

    layout_total_height: f32,
    layout_average_line_height: f32,

    last_content_hash: u64,
    last_content_len: int,
    last_panel_width: f32,
    last_panel_height: f32,
    last_font_size: f32,
    last_wrap_advance: f32,
    last_style_revision: u64,

    last_invalidation_mask: u32,
    last_error_code: i32,

    compiled_plain_text: [DYNVIEW__MAX_TEXT_BYTES]u8,
    compiled_copy_payload: [DYNVIEW__MAX_TEXT_BYTES]u8,
    copy_blocks: [DYNVIEW__MAX_COMMANDS]Dynview_Copy_Block,
    copy_hit_targets: [DYNVIEW__MAX_COMMANDS]Dynview_Copy_Hit_Target,
    layout_lines: [DYNVIEW__MAX_LAYOUT_LINES]Dynview_Layout_Line,
    layout_items: [DYNVIEW__MAX_LAYOUT_ITEMS]Dynview_Layout_Item,
    math_programs: [DYNVIEW__MAX_MATH_PROGRAMS]Dynview_Math_Program,
    math_commands: [DYNVIEW__MAX_MATH_COMMANDS]Dynview_Command,
    math_nodes: [DYNVIEW__MAX_MATH_NODES]Dynview_Math_Node,
}

Dynview_System :: struct {
    enabled: bool,
    pending_invalidation_mask: u32,

    copy_icon_hover_active: bool,
    copy_icon_hover_block_id: i32,
    copy_icon_hover_t: f32,

    copy_icon_press_active: bool,
    copy_icon_press_block_id: i32,
    copy_icon_press_t: f32,

    copy_icon_linger_active: bool,
    copy_icon_linger_block_id: i32,
    copy_icon_linger_remaining: f32,

    command_buffer: Dynview_Command_Buffer,
    compile_cache: Dynview_Compile_Cache,
}



/****
    The UI state information controls scaling and view-based primitives, including UI control
*/


Stroke3D_Render_State :: struct {
    shader: rl.Shader,
    ready: bool,
    loc_light_dir: i32,
    loc_ambient: i32,
    loc_diffuse: i32,
    loc_specular_strength: i32,
    loc_specular_power: i32,
    loc_p0: i32,
    loc_p1: i32,
    loc_radius: i32,
    loc_viewport_height: i32,
}

Dust_Render_State :: struct {
    texture: rl.Texture2D,
    ready: bool,
}

Gif_Capture_Phase :: enum {
    Idle,
    Armed,
    Recording,
    Finalizing,
    Saved,
    Error,
}

Gif_Encode_Result :: struct {
    data: []u8,
    data_size: int,
}

Gif_Encode_Frame :: struct {
    pixels: []u32,
    depth: int,
    count: int,
    r_bits: int,
    g_bits: int,
    b_bits: int,
    is_cooked: bool,
}

Gif_Encode_Buffer :: struct {
    next: ^Gif_Encode_Buffer,
    size: int,
    data: []u8,
}

Gif_Encode_State :: struct {
    previous_frame: Gif_Encode_Frame,
    current_frame: Gif_Encode_Frame,

    lzw_mem: []i16,
    tlb_mem: []u8,
    used_mem: []u8,

    list_head: ^Gif_Encode_Buffer,
    list_tail: ^Gif_Encode_Buffer,

    width: int,
    height: int,
    alpha_threshold: int,
    use_bgra: bool,

    frames_submitted: int,

    arena: vmem.Arena,
    arena_allocator: runtime.Allocator,
    arena_initialized: bool,
}

Gif_Capture_Session :: struct {
    encoder: Gif_Encode_State,
    active: bool,
}

Euclid_Font_Variant_Slot :: struct {
    loaded: bool,
    missing_warned: bool,
    font: rl.Font,
}

Euclid_Font_Runtime :: struct {
    regular_slot_index: int,
    variants: [FONT_VARIANT_SLOT_COUNT]Euclid_Font_Variant_Slot,
}

Ui_Layout_Mode :: enum {
    Baseline,
}

Ui_Regions :: struct {
    world_rect: rl.Rectangle,
    tree_rect: rl.Rectangle,
    text_rect: rl.Rectangle,
    settings_rect: rl.Rectangle,
    gif_rect: rl.Rectangle,
    scratchpad_rect: rl.Rectangle,
}

Ui_Press_Owner_Kind :: enum {
    None,
    List_Item,
    Icon_Button,
    Text_Button,
    Checkbox,
    Input_Box,
    Slider,
    Scrollbar,
}

Ui_Press_Owner_State :: struct {
    active: bool,
    kind: Ui_Press_Owner_Kind,
    id: int,
}

Euclid_UI_Runtime_State :: struct {
    tree_scroll_y: f32,
    view_text_scroll_y: f32,

    tree_scroll_dragging: bool,
    tree_scroll_drag_off: f32,
    ui_press_owner: Ui_Press_Owner_State,

    show_tree_settings: bool,
    show_tree_gif: bool,
    settings_slider_dragging: bool,
    settings_slider_drag_offset_x: f32,

    text_scroll_dragging: bool,
    text_scroll_drag_off: f32,

    limit_fps : bool,
    display_fps : bool,
    simulation_paused: bool,
    use_simd_batch_projection : bool,
    fps_avg_bucket_seconds : [60]f32,
    fps_avg_bucket_frames : [60]int,
    fps_avg_bucket_cursor : int,
    fps_avg_bucket_elapsed : f32,
    fps_avg_rolling_seconds : f32,
    fps_avg_rolling_frames : int,
    fps_avg_live : f32,

    save_gif_requested: bool,
    gif_downsample_factor: int,
    gif_frame_step: int,
    gif_capture_phase: Gif_Capture_Phase,
    gif_capture_frame_counter: int,
    gif_captured_frames: int,
    gif_status_note: [260]u8,
    gif_status_note_len: int,
    last_gif_path: [260]u8,
    last_gif_path_len: int,

    scratchpad_input: [4096]u8,
    scratchpad_input_len: int,
    scratchpad_input_cursor: int,
    scratchpad_input_viewport_col_start: int,
    scratchpad_input_generation: u64,
    scratchpad_pending_submit_request_id: u64,
    scratchpad_latest_completion_request_id: u64,
    scratchpad_history_reset_pending: bool,
    scratchpad_last_output_len: int,
    scratchpad_follow_output: bool,

    current_layout_mode: Ui_Layout_Mode,
    ui_regions: Ui_Regions,
}


// TODO: I keep thinking of getting rid of the drawing surface structure... it's old and
//  seems ridiculous to me a lot of the time

Euclid_Drawing_Surface :: struct {
    zeros : Vector3,
    right_up : Vector3,
    left_down : Vector3,
    right_down : Vector3,

    color : rl.Color,
    edge_color : rl.Color,

    edge_size : f32,
}

Chalk_Audio_Runtime :: struct {
    stream: rl.AudioStream,
    sample_buffer: [512]f32,
    prev_out: f32,
    phase: f32,
    accum_speed: f32,
    has_contact_this_frame: bool,
    initialized: bool,

    // Stick-slip grain envelope: gives constant-speed scripted motion the same
    // organic irregularity that human mouse jitter provides naturally.
    grain_level: f32,
    grain_target: f32,
    grain_hold_remaining: f32,
    resonance_freq_offset: f32,
    hit_envelope: f32,

    pen_prev_pos: Vector3,
    pen_has_prev: bool,
    pen_prev_contact: bool,

    compass_tip1_prev_pos: Vector3,
    compass_tip1_has_prev: bool,
    compass_tip1_prev_contact: bool,

    compass_tip2_prev_pos: Vector3,
    compass_tip2_has_prev: bool,
    compass_tip2_prev_contact: bool,
}


Bridge_Color :: struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

Scene_Command_Kind :: enum u8 {
    Set_Point_Position,
    Set_Point_Color,
    Set_Point_Brush,
    Set_Point_Offset,
    Show_Point,
    Hide_Point,
    Hide_Point_Batch,
    Lock_Pen_Joint1,
    Move_Pen_Joint2,
    Set_Pen_Active,
    Show_Pen,
    Hide_Pen,
    Hide_Compass,
    Show_Compass,
    Set_Compass_Active,
    Lock_Compass_Joint1,
    Lock_Compass_Joint2,
    Set_Animation_Meta,
    Set_Drawing_Sound_Enabled,
    Simulate_Drawing_Sound,
    Emit_Trailing_Particle,
    Emit_Flicker_Particle,
    Notify_Animation_Cycle_Boundary,
}

Scene_Command :: struct {
    kind: Scene_Command_Kind,
    point_index: int,
    position: Vector3,
    color: Bridge_Color,
    scalar: f32,
    integer: int,
    flag: bool,
    point_count: int,
    point_indices: [SCENE_COMMAND_POINT_BATCH_CAPACITY]i32,
}

Scene_Command_Batch :: struct {
    animation: ^Euclid_Julia_Animation_Interface,
    command_count: int,
    overflowed: bool,
    commands: [SCENE_COMMAND_BATCH_CAPACITY]Scene_Command,
}

Animation_Query_Snapshot :: struct {
    points: [MAX_SHAPESPOINTS]Shapes_Point,
    metadata: [MAX_METAVALUES]f32,
    pen: Shapes_Pen,
    compass: Shapes_Compass,
}

Julia_Request_Kind :: enum {
    Initialize,
    Invoke,
    Scratchpad,
    View_Snapshot,
    Animation_Tick,
    Shutdown,
}

Julia_Event_Kind :: enum {
    Initialized,
    Invoke_Complete,
    Scratchpad_Complete,
    View_Snapshot_Complete,
    Animation_Tick_Complete,
    Shutdown_Complete,
}

Animation_Tick_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
}

Animation_Tick_Slot :: struct {
    state: Animation_Tick_Slot_State,
    request_id: u64,
    generation: u64,
    sequence: u64,
    host_state: ^Euclid_General_State,
    animation: ^Euclid_Julia_Animation_Interface,
    dt: f32,
    submitted_at: time.Tick,
    query_snapshot: Animation_Query_Snapshot,
    scene_batch: Scene_Command_Batch,
}

View_Snapshot_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
    Published,
}

View_Snapshot :: struct {
    state: View_Snapshot_Slot_State,
    request_id: u64,
    generation: u64,
    host_state: ^Euclid_General_State,
    animation: ^Euclid_Julia_Animation_Interface,
    fallback_text_len: int,
    fallback_text: [VIEW_SNAPSHOT_TEXT_CAPACITY]u8,
    command_buffer: Dynview_Command_Buffer,
    math_program_count: int,
    math_command_count: int,
    math_node_count: int,
    math_programs: [DYNVIEW__MAX_MATH_PROGRAMS]Dynview_Math_Program,
    math_commands: [DYNVIEW__MAX_MATH_COMMANDS]Dynview_Command,
    math_nodes: [DYNVIEW__MAX_MATH_NODES]Dynview_Math_Node,
}

Scratchpad_Async_Kind :: enum {
    Submit,
    Complete,
    History_Previous,
    History_Next,
    History_Reset,
    Save_History,
}

Scratchpad_Async_Slot_State :: enum u8 {
    Free,
    Pending,
    Complete,
}

Scratchpad_Async_Slot :: struct {
    state: Scratchpad_Async_Slot_State,
    kind: Scratchpad_Async_Kind,
    request_id: u64,
    input_generation: u64,
    host_state: ^Euclid_General_State,
    caret_byte: int,
    input_len: int,
    input: [SCRATCHPAD_ASYNC_TEXT_CAPACITY]u8,
    result_len: int,
    result: [SCRATCHPAD_ASYNC_TEXT_CAPACITY]u8,
    parse_result: i32,
    succeeded: bool,
}

Julia_Lifecycle_State :: enum {
    Not_Started,
    Starting,
    Ready,
    Shutdown_Requested,
    Failed,
    Stopped,
}

Julia_Reload_State :: enum {
    Idle,
    Quiescing,
    Including,
    Registering,
    Publishing,
    Failed,
}

Julia_Task_Proc :: #type proc(data: rawptr) -> bool

Julia_Request :: struct {
    kind: Julia_Request_Kind,
    request_id: u64,
    task: Julia_Task_Proc,
    data: rawptr,
    slot_index: i32,
}

Julia_Event :: struct {
    kind: Julia_Event_Kind,
    request_kind: Julia_Request_Kind,
    request_id: u64,
    slot_index: i32,
    succeeded: bool,
}

Julia_Runtime_Service :: struct {
    worker: ^thread.Thread,
    requests: chan.Chan(Julia_Request),
    events: chan.Chan(Julia_Event),
    next_request_id: u64,
    owner_thread_id: int,
    lifecycle: Julia_Lifecycle_State,
    active_request_id: u64,
    active_request_kind: Julia_Request_Kind,
    failed_request_count: u64,
    last_failed_request_id: u64,
    last_failed_request_kind: Julia_Request_Kind,
    request_saturation_count: u64,
    reload_state: Julia_Reload_State,
    runtime_generation: u64,
    reload_failed_mtime_unix_nano: i64,
    scratchpad_slots: [SCRATCHPAD_ASYNC_SLOT_COUNT]Scratchpad_Async_Slot,
    completed_scratchpad_slots: [SCRATCHPAD_ASYNC_SLOT_COUNT]i32,
    completed_scratchpad_head: int,
    completed_scratchpad_count: int,
    dynview_staging: ^Dynview_System,
    view_snapshots: [VIEW_SNAPSHOT_SLOT_COUNT]View_Snapshot,
    view_snapshot_generation: u64,
    view_snapshot_pending: bool,
    published_view_snapshot_index: int,
    animation_tick_slots: [ANIMATION_TICK_SLOT_COUNT]Animation_Tick_Slot,
    animation_generation: u64,
    animation_tick_sequence: u64,
    animation_last_committed_sequence: u64,
    animation_tick_pending: bool,
    animation_accumulated_dt: f32,
    animation_ticks_submitted: u64,
    animation_ticks_committed: u64,
    animation_ticks_coalesced: u64,
    animation_ticks_stale: u64,
    animation_ticks_dropped: u64,
    animation_queue_high_water: u64,
    animation_last_latency_ms: f64,
    animation_max_latency_ms: f64,
}

Simulation_Task_Data :: struct {
    state: ^Euclid_General_State,
    dt: f32,
}

Frame_Preparation_Task_Data :: struct {
    state: ^Euclid_General_State,
    interpolation_alpha: f32,
}

Simulation_Executor :: struct {
    pool: thread.Pool,
    particle_task: Simulation_Task_Data,
    constraint_task: Simulation_Task_Data,
    shape_cache_task: Frame_Preparation_Task_Data,
    dynview_task: Frame_Preparation_Task_Data,
}

/****
    General state of the application is the host of all primary memory for Odin and the application
*/



Euclid_General_State :: struct {
    saved_context : runtime.Context,
    julia_runtime_service: ^Julia_Runtime_Service,
    simulation_executor: ^Simulation_Executor,
    dynview_emit_target: ^Dynview_System,
    scene_command_batch_target: ^Scene_Command_Batch,
    animation_query_snapshot_target: ^Animation_Query_Snapshot,

    iso_scale : ^Iso_Scale,

    draw_surface : ^Euclid_Drawing_Surface,

    julia_interface : ^Euclid_Julia_Interface,
    point_system : ^Shapes_Point_System,
    particle_system : ^Particle_System,
    dynview: Dynview_System,
    chalk_audio: Chalk_Audio_Runtime,
    user_drawing_sound_enabled: bool,
    animation_drawing_sound_enabled: bool,
    compass : Shapes_Compass,
    pen : Shapes_Pen,

    stroke_3d: Stroke3D_Render_State,
    dust_render: Dust_Render_State,
    ui_runtime: Euclid_UI_Runtime_State,
    gif_capture: Gif_Capture_Session,
    font_runtime: Euclid_Font_Runtime,
    font: rl.Font,

    cycle_boundary_generation: u64,
    consumed_cycle_boundary_generation: u64,

    current_delta_time : f32,
    accumulator : f32,

    anim_metadata : [MAX_METAVALUES]f32,
}

Euclid_Run_Settings :: struct {
    do_run : bool,
    do_antialiasing : bool,
    do_vsync : bool,
}
