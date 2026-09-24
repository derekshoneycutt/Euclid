package viewmodel

import dynviewmodel "../../dynview/model"
import gifmodel "../../files/gif_model"
import color "../../core/color"
import geometry "../../core/geometry"

import "core:encoding/uuid"
import "core:time"

TOOL_LENGTH :: 0.35
MAX_TOOL_BRUSH_OCCLUDERS :: 2
Color :: color.Color_RGBA8
Rectangle :: geometry.Rectangle
Vector3 :: geometry.Vector3

// Iso_Scale owns display projection and screen-shake state.
Iso_Scale :: struct {
    scale: f32,
    x_offset: f32,
    y_offset: f32,
    half_scale: f32,
    quarter_scale: f32,
    main_light_dir: Vector3,
    use_directional_shadow: bool,
    screenshake_trauma: f32,
    screenshake_elapsed: f32,
    screenshake_offset_x: f32,
    screenshake_offset_y: f32,
    screenshake_phase: f32,
}

// Gif_Capture_Phase tracks display-owned GIF capture policy.
Gif_Capture_Phase :: enum {
    Idle,
    Armed,
    Recording,
    Finalizing,
    Saved,
    Error,
}

// Gif_Capture_Session combines display capture dimensions with encoder storage.
Gif_Capture_Session :: struct {
    encoder: gifmodel.Gif_Encode_State,
    active: bool,
    source_width: int,
    source_height: int,
    started_at: time.Tick,
    frame_materialization_ms: f64,
    materialized_frames: u64,
    recording_presentations: u64,
    paused_presentations: u64,
}

Layout_Preference :: enum u8 {
    Auto,
    Landscape,
    Portrait,
}

Ui_Layout_Mode :: enum u8 {
    Landscape,
    Portrait,
}

// Ui_Window_Metrics records the display thread's authoritative logical extent.
Ui_Window_Metrics :: struct {
    width: int,
    height: int,
}

// Ui_Landscape_Layout_State retains split intent independently of pixel extent.
Ui_Landscape_Layout_State :: struct {
    vertical_ratio: f32,
    horizontal_ratio: f32,
    active_section: Ui_Accordion_Section,
}

// Ui_Portrait_Layout_State retains portrait split and accordion intent.
Ui_Portrait_Layout_State :: struct {
    world_height_ratio: f32,
    active_section: Ui_Accordion_Section,
    entered: bool,
}

// Ui_Accordion_Section identifies the one expanded auxiliary application view.
Ui_Accordion_Section :: enum u8 {
    Library,
    Save_Gif,
    Settings,
    View,
}

Ui_Regions :: struct {
    world_rect: Rectangle,
    accordion_rect: Rectangle,
    text_rect: Rectangle,
    terminal_rect: Rectangle,
}

Ui_Press_Owner_Kind :: enum {
    None,
    List_Item,
    Icon_Button,
    Text_Button,
    Checkbox,
    Slider,
    Scrollbar,
    Splitter,
    Dynview_Selection,
    Copy_Icon,
}

Ui_Press_Owner_State :: struct {
    active: bool,
    kind: Ui_Press_Owner_Kind,
    id: int,
}

Ui_Focus_Kind :: enum u8 {
    None,
    Terminal,
    Presentation,
    Accordion,
    Input_Box,
}

Ui_Focus_Target :: struct {
    kind: Ui_Focus_Kind,
    id: int,
}

Ui_Interaction_Target_Kind :: enum u8 {
    None,
    Splitter,
    Control,
    Scrollbar,
    Panel_Content,
    World,
}

Ui_Interaction_Target :: struct {
    kind: Ui_Interaction_Target_Kind,
    focus: Ui_Focus_Target,
    id: int,
}

Ui_Surface_Interaction :: struct {
    keyboard: bool,
    pointer: bool,
    wheel: bool,
}

Ui_Interaction_State :: struct {
    logical_focus: Ui_Focus_Target,
    terminal_was_present: bool,
    terminal_effectively_focused: bool,
}

Ui_Interaction_Frame :: struct {
    logical_focus: Ui_Focus_Target,
    effective_focus: Ui_Focus_Target,
    hover: Ui_Interaction_Target,
    pointer_capture: Ui_Interaction_Target,
    pointer_target: Ui_Interaction_Target,
    wheel_target: Ui_Interaction_Target,
    terminal: Ui_Surface_Interaction,
    presentation: Ui_Surface_Interaction,
    accordion: Ui_Surface_Interaction,
    terminal_focus_changed: bool,
    terminal_focused: bool,
}

// Ui_Cursor_Kind is the portable pointer shape requested by UI interaction.
Ui_Cursor_Kind :: enum u8 {
    Default,
    Resize_Ew,
    Resize_Ns,
}

// Euclid_Ui_Runtime_State owns persistent display interaction and panel state.
Euclid_Ui_Runtime_State :: struct {
    tree_scroll_y: f32,
    tree_reveal_pending: bool,
    tree_reveal_stable_id: uuid.Identifier,
    view_text_scroll_y: f32,
    view_text_scroll_max: f32,
    tree_scroll_dragging: bool,
    tree_scroll_drag_off: f32,
    ui_press_owner: Ui_Press_Owner_State,
    active_accordion_section: Ui_Accordion_Section,
    presentation_visible: bool,
    settings_slider_dragging: bool,
    settings_slider_drag_offset_x: f32,
    text_scroll_dragging: bool,
    text_scroll_drag_off: f32,
    terminal_scroll_dragging: bool,
    terminal_scroll_drag_off: f32,
    dynview_selection: dynviewmodel.Dynview_Selection_State,
    vertical_split_x: f32,
    horizontal_split_y: f32,
    vertical_split_hover: f32,
    horizontal_split_hover: f32,
    splitter_drag_offset: f32,
    cursor: Ui_Cursor_Kind,
    limit_fps: bool,
    display_fps: bool,
    simulation_paused: bool,
    animation_policy_paused: bool,
    use_simd_batch_projection: bool,
    use_gpu_dust_instancing: bool,
    fps_avg_bucket_seconds: [60]f32,
    fps_avg_bucket_frames: [60]int,
    fps_avg_bucket_cursor: int,
    fps_avg_bucket_elapsed: f32,
    fps_avg_rolling_seconds: f32,
    fps_avg_rolling_frames: int,
    fps_avg_live: f32,
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
    window: Ui_Window_Metrics,
    layout_preference: Layout_Preference,
    landscape: Ui_Landscape_Layout_State,
    portrait: Ui_Portrait_Layout_State,
    current_layout_mode: Ui_Layout_Mode,
    ui_regions: Ui_Regions,
    interaction: Ui_Interaction_State,
    interaction_frame: Ui_Interaction_Frame,
}

// Euclid_Drawing_Surface defines the display-owned world drawing plane.
Euclid_Drawing_Surface :: struct {
    zeros: Vector3,
    right_up: Vector3,
    left_down: Vector3,
    right_down: Vector3,
    color: Color,
    edge_color: Color,
    edge_size: f32,
}