package core

import animation_model "animation"
import bridgemodel "../bridge/model"
import dynviewmodel "../dynview/model"
import audiomodel "../audio/model"
import fontmodel "../view/font/model"
import viewmodel "../view/model"
import viewterminalmodel "../view/terminal/model"
import particlemodel "../particles/model"
import shapemodel "../shapes/model"

// Defines the core structures used in the Euclid Application.
// The general bias is to just allocate memory upfront inside Euclid_General_State and
// stick to that memory, except for a few UI helpers using temp_allocator, Julia's GC, and GIFs.
// This creates some hard caps on e.g. the particle system, but it also prevents wildness.

// Compile application scenario automation only for repository debug and test builds.
SCENARIOS_ENABLED :: #config(EUCLID_ENABLE_SCENARIOS, false)

// Compile headless harness execution only for the harness executable and tests.
HARNESS_ENABLED :: #config(EUCLID_ENABLE_HARNESS, false)

import "../taskpool"
import evidence_allocation "../evidence/allocation"
import evidence_checkpoint "../evidence/checkpoint"
import evidence_session "../evidence/session"
import evidence_text "../evidence/text"
import evidence_trace "../evidence/trace"
import "base:runtime"

Simulation_Task_Data :: struct {
    state: ^Euclid_General_State,
    dt: f32,
    evidence_ring: evidence_trace.Ring,
    dust_emission_queue: particlemodel.Dust_Emission_Request_Queue,
    scenario_dust_kick_requested: bool,
}

Math_Shaping_Workspace :: struct {
    projection: [dynviewmodel.DYNVIEW_MAX_TEXT_BYTES]u8,
    glyphs: [fontmodel.FONT_SHAPED_GLYPH_CAPACITY]fontmodel.Shaped_Glyph,
}

Document_Prose_Shaping_Workspace :: struct {
    glyphs: [dynviewmodel.DYNVIEW_MAX_DOCUMENT_SHAPED_GLYPHS]fontmodel.Shaped_Glyph,
}

Frame_Preparation_Task_Data :: struct {
    state: ^Euclid_General_State,
    interpolation_alpha: f32,
    evidence_ring: evidence_trace.Ring,
    math_shaping_workspace: ^Math_Shaping_Workspace,
    prose_shaping_workspace: ^Document_Prose_Shaping_Workspace,
}

Simulation_Executor :: struct {
    pool: taskpool.Task_Pool,
    particle_task: Simulation_Task_Data,
    constraint_task: Simulation_Task_Data,
    shape_cache_task: Frame_Preparation_Task_Data,
    dynview_task: Frame_Preparation_Task_Data,
    math_shaping_workspace: Math_Shaping_Workspace,
    prose_shaping_workspace: ^Document_Prose_Shaping_Workspace,
}





/****
    General state of the application is the host of all primary memory for Odin and the application
*/


Julia_Interface_Slots ::
    [bridgemodel.JULIA_INTERFACE_GENERATION_SLOT_COUNT]bridgemodel.Euclid_Julia_Interface


Euclid_General_State :: struct {
    saved_context : runtime.Context,

    iso_scale: ^viewmodel.Iso_Scale,

    draw_surface: ^viewmodel.Euclid_Drawing_Surface,

    julia_runtime_service: ^bridgemodel.Julia_Runtime_Service,
    julia_interface_slots: Julia_Interface_Slots,
    julia_interface_active_slot: int,
    julia_interface: ^bridgemodel.Euclid_Julia_Interface,

    shape_world: ^shapemodel.Shape_World,
    world_trochoid_tool: shapemodel.Shape_Trochoid_Tool_Handle,
    world_cycloid_tool: shapemodel.Shape_Cycloid_Tool_Handle,
    world_compass: shapemodel.Shape_Compass_Handle,
    world_pen: shapemodel.Shape_Pen_Handle,

    particle_system: ^particlemodel.Particle_System,

    dynview: dynviewmodel.Dynview_System,

    chalk_audio: audiomodel.Chalk_Audio_Runtime,
    user_drawing_sound_enabled: bool,
    animation_drawing_sound_enabled: bool,
    
    stroke_3d: viewmodel.Tool_Render_State,
    dust_render: viewmodel.Dust_Render_State,
    ui_runtime: viewmodel.Euclid_Ui_Runtime_State,
    gif_capture: viewmodel.Gif_Capture_Session,
    font_cache: fontmodel.Font_Cache,
    terminal: viewterminalmodel.Terminal_State,
    terminal_tick_publisher: viewterminalmodel.Terminal_Tick_Publisher,
    shell: viewterminalmodel.Shell_Runtime,
    terminal_graphics_user_data: rawptr,
    terminal_graphics_release: viewterminalmodel.Terminal_Graphics_Lifecycle_Proc,
    terminal_graphics_shutdown: viewterminalmodel.Terminal_Graphics_Lifecycle_Proc,

    simulation_executor: ^Simulation_Executor,
    scene_command_batch_target: ^bridgemodel.Scene_Command_Batch,
    animation_query_snapshot_target: ^bridgemodel.Animation_Query_Snapshot,

    cycle_boundary_generation: u64,
    consumed_cycle_boundary_generation: u64,

    evidence_session: evidence_session.Session,
    evidence_allocations: ^evidence_allocation.Domain,
    evidence_arena_baselines: evidence_allocation.Arena_Baselines,
    evidence_ring: evidence_trace.Ring,
    evidence_text: evidence_text.Store,
    evidence_checkpoints: evidence_checkpoint.Store,

    fixed_step: u64,
    simulation_time: f32,
    current_delta_time : f32,
    accumulator : f32,

    animation_memory: animation_model.Animation_Memory,
    animation_values: animation_model.Animation_Value_Store,
    dynview_documents: dynviewmodel.Dynview_Document_Store,
}

Window_Mode :: enum u8 {
    Fixed,
    Resizable,
}

Layout_Preference :: viewmodel.Layout_Preference

Window_Startup_Policy :: struct {
    width: int,
    height: int,
    mode: Window_Mode,
    layout: Layout_Preference,
    custom_size_set: bool,
}

Euclid_Run_Settings :: struct {
    do_run : bool,
    do_antialiasing : bool,
    do_vsync : bool,
    dust_particle_max: int,
    limit_fps: bool,
    use_simd_batch_projection: bool,
    use_gpu_dust_instancing: bool,
    window: Window_Startup_Policy,
    evidence_allocations: ^evidence_allocation.Domain,
    evidence: evidence_session.Config,
    profile_path: string,
    scenario_input: string,
    scenario_artifact_output: string,
    diagnostics_path : string,
}

