package core

// Defines the core structures used in the Euclid Application.
// The general bias is to just allocate memory upfront inside EuclidGeneralState and
// stick to that memory, except for a few UI helpers using temp_allocator, Julia's GC, and GIFs.
// This creates some hard caps on e.g. the particle system, but it also prevents wildness.

import "base:runtime"
import "core:c"

import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 4096
MAX_PARTICLES :: 2048
MAX_METAVALUES :: 256
MAX_KINEPOINTS :: 256
MAX_KINECONSTRAINTS :: 256
MAX_JULIA_INTERFACES :: 512
MAX_DRAW_CACHE_POLYGON_VERTICES :: MAX_KINEPOINTS
MAX_DRAW_CACHE_POLYGON_TRIANGLES :: MAX_KINEPOINTS

DUST_GRID_CELL_SIZE :: 0.02
DUST_GRID_DIM :: 50
DUST_GRID_DIM_SQUARED :: DUST_GRID_DIM * DUST_GRID_DIM
DUST_GRID_BUCKET_CAP :: 16
DUST_GRID_BUCKET_COUNT :: DUST_GRID_DIM_SQUARED * DUST_GRID_BUCKET_CAP
DUST_COLLISION_PAIR_CAP :: MAX_LOW_PARTICLES * 16

TOOL_LENGTH :: 0.35

Vector2 :: rl.Vector2
Vector3 :: rl.Vector3

/*****
    This first section are julia structures taken from julia.h.

    We include them here to follow import conventions with core lying below everything
    else. This avoid having to have a separate julialib and julia library, which is just
    annoyingly redundant for this project.
*/




JL_IMAGE_SEARCH :: enum c.int {
    JL_IMAGE_CWD = 0,
    JL_IMAGE_JULIA_HOME = 1,
    JL_IMAGE_IN_MEMORY = 2,
}

jl_image_kind_t :: enum c.int {
    JL_IMAGE_KIND_NONE = 0,
    JL_IMAGE_KIND_JI = 1,
    JL_IMAGE_KIND_SO = 2,
}

jl_gc_collection_t :: enum c.int {
    JL_GC_AUTO = 0,
    JL_GC_FULL = 1,
    JL_GC_INCREMENTAL = 2,
}

jl_nullable_float64_t :: struct {
    hasvalue: u8,
    value: f64,
}

jl_nullable_float32_t :: struct {
    hasvalue: u8,
    value: f32,
}

jl_options_t :: struct {
    quiet: c.int8_t,
    banner: c.int8_t,
    julia_bindir: cstring,
    julia_bin: cstring,
    cmds: ^cstring,
    image_file: cstring,
    cpu_target: cstring,
    nthreadpools: c.int8_t,
    nthreads: c.int16_t,
    nmarkthreads: c.int16_t,
    nsweepthreads: c.int8_t,
    nthreads_per_pool: ^c.int16_t,
    nprocs: c.int32_t,
    machine_file: cstring,
    project: cstring,
    program_file: cstring,
    isinteractive: c.int8_t,
    color: c.int8_t,
    historyfile: c.int8_t,
    startupfile: c.int8_t,
    compile_enabled: c.int8_t,
    code_coverage: c.int8_t,
    malloc_log: c.int8_t,
    tracked_path: cstring,
    opt_level: c.int8_t,
    opt_level_min: c.int8_t,
    debug_level: c.int8_t,
    check_bounds: c.int8_t,
    depwarn: c.int8_t,
    warn_overwrite: c.int8_t,
    can_inline: c.int8_t,
    polly: c.int8_t,
    trace_compile: cstring,
    trace_dispatch: cstring,
    fast_math: c.int8_t,
    worker: c.int8_t,
    cookie: cstring,
    handle_signals: c.int8_t,
    use_experimental_features: c.int8_t,
    use_sysimage_native_code: c.int8_t,
    use_compiled_modules: c.int8_t,
    use_pkgimages: c.int8_t,
    bindto: cstring,
    outputbc: cstring,
    outputunoptbc: cstring,
    outputo: cstring,
    outputasm: cstring,
    outputji: cstring,
    output_code_coverage: cstring,
    incremental: c.int8_t,
    image_file_specified: c.int8_t,
    warn_scope: c.int8_t,
    image_codegen: c.int8_t,
    rr_detach: c.int8_t,
    strip_metadata: c.int8_t,
    strip_ir: c.int8_t,
    permalloc_pkgimg: c.int8_t,
    heap_size_hint: u64,
    hard_heap_limit: u64,
    heap_target_increment: u64,
    trace_compile_timing: c.int8_t,
    trim: c.int8_t,
    trace_eval: c.int8_t,
    task_metrics: c.int8_t,
    timeout_for_safepoint_straggler_s: c.int16_t,
    gc_sweep_always_full: c.int8_t,
    compress_sysimage: c.int8_t,
    alert_on_critical_error: c.int8_t,
    target_sanitize_memory: c.int8_t,
    target_sanitize_thread: c.int8_t,
    target_sanitize_address: c.int8_t,
}

jl_image_buf_t :: struct {
    kind: jl_image_kind_t,
    pointers: rawptr,
    data: cstring,
    size: c.size_t,
    base: u64,
    checksum: u32,
}

jl_cgparams_t :: struct {
    track_allocations: c.int,
    code_coverage: c.int,
    prefer_specsig: c.int,

    gnu_pubnames: c.int,
    debug_info_kind: c.int,
    debug_info_level: c.int,
    safepoint_on_entry: c.int,
    gcstack_arg: c.int,

    use_jlplt: c.int,
    force_emit_all: c.int,

    sanitize_memory: c.int,
    sanitize_thread: c.int,
    sanitize_address: c.int,

    unique_names: c.int,
}

jl_emission_params_t :: struct {
    emit_metadata: c.int,
}

jl_gcframe_t :: struct {}
jl_tls_states_t :: struct {}
jl_value_t :: struct {}
jl_sym_t :: struct {}
jl_svec_t :: struct {}
jl_genericmemory_t :: struct {
    length: c.size_t,
    ptr: rawptr,
}
jl_genericmemoryref_t :: struct {
    ptr_or_offset: rawptr,
    mem: ^jl_genericmemory_t,
}
jl_array_t :: struct {
    ref: jl_genericmemoryref_t,
    dimsize: [1]c.size_t,
}
jl_datatype_t :: struct {}
jl_typename_t :: struct {}
jl_tupletype_t :: struct {}
jl_tvar_t :: struct {}
jl_unionall_t :: struct {}
jl_binding_t :: struct {}
jl_binding_partition_t :: struct {}
jl_globalref_t :: struct {}
jl_method_t :: struct {}
jl_method_instance_t :: struct {}
jl_code_info_t :: struct {}
jl_code_instance_t :: struct {}
jl_debuginfo_t :: struct {}
jl_module_t :: struct {}
jl_task_t :: struct {}
jl_weakref_t :: struct {}
JL_STREAM :: struct {}
ios_t :: struct {}

/****
    The remaining structures are unique to the Euclid application


    Starting with the Julia Animation tree structures
*/


Euclid_Julia_Animation_Interface :: struct {
    get_view_text : ^jl_value_t,
    initiate : ^jl_value_t, // initiate the animation type
    loop : ^jl_value_t, // ran each dt in the main window loop
    clean : ^jl_value_t, // stop and clear animations

    name : string,
    is_expanded : bool,
    is_selected : bool,

    first_child_id : int,
    parent_id : int,
    next_sibling : int,
}

Euclid_Julia_Interface :: struct {
    init_scripts : ^jl_value_t,
    global_loop : ^jl_value_t,
    scratchpad_classify_input : ^jl_value_t,
    scratchpad_queue_input : ^jl_value_t,
    scratchpad_save_history_to_file : ^jl_value_t,
    scratchpad_history_previous : ^jl_value_t,
    scratchpad_history_next : ^jl_value_t,
    scratchpad_history_reset_cursor : ^jl_value_t,
    asset_archive_mod_time_unix_nano: i64,

    null_animation : Euclid_Julia_Animation_Interface,

    current_animation : ^Euclid_Julia_Animation_Interface,
    current_animation_index : int,
    selected_animation_index : int,
    pending_animation_reset : bool,
    animation_reset_cooldown_remaining : f32,

    animations : [MAX_JULIA_INTERFACES]Euclid_Julia_Animation_Interface,
    next_animation_index : int,
}


/****
    The Shape system, used to draw the tools and the various points/lines/shapes/polygons

    Point and Constraint are the primitive types; the others are shorthands for representing
    them between function calls, outside of the array of points/constraints

    The draw cache are computed through a lerp for preparation before draw
*/






Kine_Shape_Point_Type :: enum {
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

Kine_Label_Decoration_Kind :: enum {
    None,
    Prime,
    DoublePrime,
    TriplePrime,
    Hat,
    Bar,
}

Kine_Shape_Point :: struct {
    kind : Kine_Shape_Point_Type,

    position : Maybe(Vector3),
    previous_position : Maybe(Vector3),
    color : Maybe(rl.Color),
    active_color : Maybe(rl.Color),
    brush_size : f32,
    offset : f32,
    label : Maybe(rune),
    decoration_kind : Kine_Label_Decoration_Kind,

    active_child: int,
    child_count : int,
    child_point_head : int,
    next_child_point : int,

    do_draw : bool,
}

Kine_Constraint_Kind :: enum {
    Distance,
    Floor,
    SnapToFloor,
    SnapPoint,
    MaxAngle,
    MinAngle,
    CenterPivot,
}

Kine_Constraint :: struct {
    kind : Kine_Constraint_Kind,

    on_point : int,
    restriction : Vector3,
    bounce : f32,
    allowance : f32,
    depend_on : i32,
    child_offset : Maybe(i32),

    do_apply : bool,
}

Kine_Shape_Compass :: struct {
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

Kine_Shape_Pen :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,

    length_constraint_id : int,
    point1_floor_id : int,
    point2_floor_id : int,
    lock_point1_id : int,
    lock_point2_id : int,
}

Kine_Shape_Line :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
}

Kine_Shape_Circle :: struct {
    host_id : int,
    start_id : int,
    end_id : int,
}

Kine_Shape_Filled_Circle :: struct {
    host_id : int,
    start_id : int,
    end_id : int,
}

Kine_Shape_Triangle :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
}

Kine_Shape_Square :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
    joint4_id : int,
}

Kine_Shape_Pentagon :: struct {
    host_id : int,
    joint1_id : int,
    joint2_id : int,
    joint3_id : int,
    joint4_id : int,
    joint5_id : int,
}

Kine_Draw_Base :: struct {
    kind: Kine_Shape_Point_Type,
    source_index: int,
    brush_size: f32,
    color: rl.Color,
    active_color: rl.Color,
    has_active_color: bool,
    active_child: int,
}

Kine_Label_Draw :: struct {
    using base: Kine_Draw_Base,
    point1: Vector3,
    label: rune,
    decoration_kind: Kine_Label_Decoration_Kind,
}

Kine_Point_Draw :: struct {
    using base: Kine_Draw_Base,
    point1: Vector3,
}

Kine_Line_Draw :: struct {
    using base: Kine_Draw_Base,
    point1: Vector3,
    point2: Vector3,
}

Kine_Circle_Draw :: struct {
    using base: Kine_Draw_Base,
    center: Vector3,
    start: Vector3,
    end: Vector3,
    offset: f32,
}

Kine_Filled_Circle_Draw :: struct {
    using base: Kine_Draw_Base,
    center: Vector3,
    start: Vector3,
    end: Vector3,
    offset: f32,
}

Kine_Polygon_Ring_Node :: struct {
    prev: int,
    next: int,
    active: bool,
}

Kine_Polygon_Triangle :: struct {
    a: int,
    b: int,
    c: int,
}

Kine_Polygon_Draw :: struct {
    using base: Kine_Draw_Base,
    first_vertex: int,
    vertex_count: int,
    first_triangle: int,
    triangle_count: int,
}

Kine_Pen_Draw :: struct {
    using base: Kine_Draw_Base,
    joint1: Vector3,
    joint2: Vector3,
}

Kine_Compass_Draw :: struct {
    using base: Kine_Draw_Base,
    joint1: Vector3,
    pivot: Vector3,
    joint2: Vector3,
}

Kine_Draw_Cache_Item :: union {
    Kine_Label_Draw,
    Kine_Point_Draw,
    Kine_Line_Draw,
    Kine_Circle_Draw,
    Kine_Filled_Circle_Draw,
    Kine_Polygon_Draw,
}

Kine_Draw_Cache :: struct {
    items: [MAX_KINEPOINTS]Kine_Draw_Cache_Item,
    item_count: int,

    polygon_vertices: [MAX_DRAW_CACHE_POLYGON_VERTICES]Vector3,
    polygon_vertex_count: int,
    polygon_triangles: [MAX_DRAW_CACHE_POLYGON_TRIANGLES]Kine_Polygon_Triangle,
    polygon_triangle_count: int,
    polygon_ring_nodes: [MAX_DRAW_CACHE_POLYGON_VERTICES]Kine_Polygon_Ring_Node,

    pen: Kine_Pen_Draw,
    draw_pen: bool,
    compass: Kine_Compass_Draw,
    draw_compass: bool,
}

Kine_Point_System :: struct {
    draw_cache : Kine_Draw_Cache,

    points : [MAX_KINEPOINTS]Kine_Shape_Point,
    constraints : [MAX_KINECONSTRAINTS]Kine_Constraint,
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

    last_render_low : int,
    last_render_mid : int,
    last_render_high : int,

    use_max_dust_particles : int,
}

/****
    The UI state information controls scaling and view-based primitives, including UI control
*/




Iso_Scale :: struct {
    scale : f32,
    x_offset : f32,
    y_offset : f32,

    half_scale : f32,
    quarter_scale : f32,

    main_light_dir : Vector3,
    use_directional_shadow : bool,
}

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
}

Gif_Capture_Session :: struct {
    encoder: Gif_Encode_State,
    active: bool,
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

Euclid_UI_Runtime_State :: struct {
    tree_scroll_y: f32,
    view_text_scroll_y: f32,

    tree_scroll_dragging: bool,
    tree_scroll_drag_off: f32,

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


/****
    General state of the application is the host of all primary memory for Odin and the application
*/



Euclid_General_State :: struct {
    saved_context : runtime.Context,

    iso_scale : ^Iso_Scale,

    draw_surface : ^Euclid_Drawing_Surface,

    julia_interface : ^Euclid_Julia_Interface,
    point_system : ^Kine_Point_System,
    particle_system : ^Particle_System,
    compass : Kine_Shape_Compass,
    pen : Kine_Shape_Pen,

    stroke_3d: Stroke3D_Render_State,
    dust_render: Dust_Render_State,
    ui_runtime: Euclid_UI_Runtime_State,
    gif_capture: Gif_Capture_Session,
    font: rl.Font,
    scratchpad_font: rl.Font,

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
