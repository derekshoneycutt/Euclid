package viewmodel

import dynviewmodel "../../dynview/model"
import color "../../core/color"
import geometry "../../core/geometry"

import "core:encoding/uuid"
import "core:time"

TOOL_LENGTH :: 0.35
MAX_TOOL_BRUSH_OCCLUDERS :: 2
GIF_PATH_CAPACITY :: 4096
LIBRARY_SEARCH_QUERY_BYTE_CAPACITY :: 512
LIBRARY_SEARCH_RESULT_CAPACITY :: 64
LIBRARY_SEARCH_VISIBLE_ID_CAPACITY :: 256
// Capacity covers 256 filtered tree nodes, 1,024 Dynview copy targets, and 64
// static, container, and responsive-layout nodes.
UI_SEMANTIC_NODE_CAPACITY :: 1344
UI_SEMANTIC_TEXT_CAPACITY :: 64 * 1024
UI_FOCUS_COMMAND_CAPACITY :: 128
UI_FOCUS_COMMAND_PAYLOAD_CAPACITY :: LIBRARY_SEARCH_QUERY_BYTE_CAPACITY
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

// Gif_Capture_Timing_Mode selects authored or observed playback timing.
Gif_Capture_Timing_Mode :: enum u8 {
    Animation,
    Recorded,
}

// Gif_Capture_Operations supplies display-owned streaming encoder calls to policy.
Gif_Capture_Frame :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
}

Gif_Capture_Operations :: struct {
    user_data: rawptr,
    begin: proc(user_data: rawptr, width, height: int) -> bool,
    stage_frame: proc(user_data: rawptr, frame: Gif_Capture_Frame) -> bool,
    commit_frame: proc(user_data: rawptr, duration_ms: u64) -> bool,
    close: proc(user_data: rawptr) -> bool,
    abort: proc(user_data: rawptr),
    published_path: proc(user_data: rawptr) -> string,
}

// Gif_Capture_Session combines portable capture policy and encoder operations.
Gif_Capture_Session :: struct {
    operations: Gif_Capture_Operations,
    active: bool,
    source_width: int,
    source_height: int,
    output_width: int,
    output_height: int,
    started_at: time.Tick,
    active_downsample_factor: int,
    active_frame_step: int,
    active_timing_mode: Gif_Capture_Timing_Mode,
    staged: bool,
    staged_fixed_step: u64,
    staged_at: time.Tick,
    last_duration_ms: u64,
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
    Input_Box,
    Checkbox,
    Slider,
    Scrollbar,
    Splitter,
    Dynview_Selection,
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

// Ui_Node_Domain qualifies semantic identities across independently owned UI areas.
Ui_Node_Domain :: enum u8 {
    None,
    Application,
    Animation_Control,
    Accordion,
    Library_Control,
    Animation_Tree,
    Gif_Control,
    Settings_Control,
    Presentation,
    Terminal,
}

// Ui_Node_Id identifies one semantic node across stable and generated content.
Ui_Node_Id :: struct {
    domain: Ui_Node_Domain,
    local_id: u64,
    stable_id: uuid.Identifier,
    generation: u64,
}

// Ui_Node_Role describes the application-level meaning of one semantic node.
Ui_Node_Role :: enum u8 {
    Surface,
    Button,
    Input,
    Text_Run,
    Checkbox,
    Slider,
    Accordion_Header,
    Status,
    Tree,
    Tree_Item,
    Document,
    Terminal,
}

Ui_Node_State_Flag :: enum u8 {
    Visible,
    Enabled,
    Focusable,
    Tab_Stop,
    Selected,
    Checked,
    Expanded,
    Read_Only,
    Focus_Visible,
}

Ui_Node_State :: bit_set[Ui_Node_State_Flag; u16]

Ui_Node_Action :: enum u8 {
    Focus,
    Activate,
    Toggle,
    Increment,
    Decrement,
    Set_To_Bound,
    Set_Value,
    Select,
    Expand,
    Collapse,
    Copy,
    Scroll,
    Replace_Selected_Text,
    Set_Text_Selection,
}

Ui_Node_Action_Set :: bit_set[Ui_Node_Action; u16]

// Ui_Control_Action_Source records which input routes produced one control action.
Ui_Control_Action_Source_Flag :: enum u8 {
    Pointer,
    Semantic,
    Scenario,
}

Ui_Control_Action_Source :: bit_set[Ui_Control_Action_Source_Flag; u8]

// Ui_Control_Geometry carries authoritative interaction and clipping bounds.
Ui_Control_Geometry :: struct {
    bounds: Rectangle,
    clip_bounds: Rectangle,
}

// Ui_Range_Orientation describes the axis of one numeric control.
Ui_Range_Orientation :: enum u8 {
    Horizontal,
    Vertical,
}

// Ui_Numeric_Range exposes typed range facts without parsing display text.
Ui_Numeric_Range :: struct {
    minimum: f64,
    maximum: f64,
    current: f64,
    step: f64,
    orientation: Ui_Range_Orientation,
    present: bool,
}

// Ui_Editable_Text_Mode distinguishes mutable input from read-only text fields.
Ui_Editable_Text_Mode :: enum u8 {
    Read_Only,
    Editable,
}

// Ui_Editable_Text_Descriptor borrows one committed UTF-8 value for a frame.
Ui_Editable_Text_Descriptor :: struct {
    id: Ui_Node_Id,
    text_run_id: Ui_Node_Id,
    parent: Ui_Node_Id,
    region: Ui_Focus_Region,
    traversal_order: u16,
    label: string,
    placeholder: string,
    text: string,
    mode: Ui_Editable_Text_Mode,
    cursor_byte: int,
    anchor_byte: int,
    content_revision: u64,
}

// Ui_Editable_Text_Geometry carries prepared control, caret, and selection facts.
Ui_Editable_Text_Geometry :: struct {
    control: Ui_Control_Geometry,
    caret: Rectangle,
    selection: Rectangle,
    cursor_column: int,
    anchor_column: int,
}

// Ui_Focus_Command_Kind identifies one action addressed to its current owner.
Ui_Focus_Command_Kind :: enum u8 {
    None,
    Focus,
    Activate,
    Toggle,
    Increment,
    Decrement,
    Set_Minimum,
    Set_Maximum,
    Set_Value,
    Page_Step,
    Tree_Previous,
    Tree_Next,
    Tree_Parent,
    Tree_Child,
    Tree_First,
    Tree_Last,
    Select,
    Expand,
    Collapse,
    Copy,
    Scroll_Page,
    Set_Scroll_Value,
    Replace_Selected_Text,
    Replace_Text,
    Set_Text_Selection,
}

// Ui_Focus_Command carries one bounded event-derived action to a semantic owner.
Ui_Focus_Command :: struct {
    target: Ui_Node_Id,
    kind: Ui_Focus_Command_Kind,
    amount: i32,
    numeric_value: f64,
    payload: [UI_FOCUS_COMMAND_PAYLOAD_CAPACITY]u8,
    payload_length: u16,
    selection_anchor: u16,
    selection_focus: u16,
    event_index: u16,
}

// Ui_Focus_Region defines explicit global traversal groups.
Ui_Focus_Region :: enum u8 {
    None,
    Animation_Overlay,
    Accordion_Headers,
    Accordion_Content,
    Pane_Layout,
    Presentation,
}

// Ui_Semantic_Node owns offsets into its containing snapshot's UTF-8 storage.
Ui_Semantic_Node :: struct {
    id: Ui_Node_Id,
    parent: Ui_Node_Id,
    active_descendant: Ui_Node_Id,
    controls: Ui_Node_Id,
    role: Ui_Node_Role,
    states: Ui_Node_State,
    actions: Ui_Node_Action_Set,
    region: Ui_Focus_Region,
    traversal_order: u16,
    bounds: Rectangle,
    clip_bounds: Rectangle,
    numeric_range: Ui_Numeric_Range,
    label_offset: u32,
    label_length: u16,
    value_offset: u32,
    value_length: u16,
    placeholder_offset: u32,
    placeholder_length: u16,
    text_cursor_byte: u16,
    text_anchor_byte: u16,
    text_present: bool,
    level: u16,
    position_in_set: u16,
    set_size: u16,
}

// Ui_Semantic_Node_Registration borrows text only for one atomic registration.
Ui_Semantic_Node_Registration :: struct {
    node: Ui_Semantic_Node,
    label: string,
    value: string,
    placeholder: string,
}

// Ui_Semantic_Snapshot owns one complete immutable semantic tree publication.
Ui_Semantic_Snapshot :: struct {
    nodes: [UI_SEMANTIC_NODE_CAPACITY]Ui_Semantic_Node,
    text: [UI_SEMANTIC_TEXT_CAPACITY]u8,
    node_count: int,
    text_count: int,
    generation: u64,
}

Ui_Semantic_Status :: enum u8 {
    Ok,
    Invalid_Argument,
    Invalid_Id,
    Duplicate_Id,
    Missing_Parent,
    Node_Capacity,
    Text_Capacity,
    Invalid_Utf8,
    Traversal_Collision,
    Not_Staging,
}

Ui_Focus_Origin :: enum u8 {
    None,
    Pointer,
    Keyboard,
}

// Ui_Semantic_Diagnostics records bounded-storage pressure and publication failures.
Ui_Semantic_Diagnostics :: struct {
    node_high_water: int,
    text_high_water: int,
    rejection_count: u64,
    last_rejection: Ui_Semantic_Status,
    offending_id: Ui_Node_Id,
}

// Ui_Semantic_Focus_State owns double-buffered snapshots and persistent logical focus.
Ui_Semantic_Focus_State :: struct {
    snapshots: [2]Ui_Semantic_Snapshot,
    committed_index: u8,
    staging_index: u8,
    staging_active: bool,
    staging_rejected: bool,
    window_focused: bool,
    logical_focus: Ui_Node_Id,
    focus_origin: Ui_Focus_Origin,
    last_region: Ui_Focus_Region,
    last_traversal_order: u16,
    active_tree_item: uuid.Identifier,
    commands: [UI_FOCUS_COMMAND_CAPACITY]Ui_Focus_Command,
    command_count: int,
    diagnostics: Ui_Semantic_Diagnostics,
}

// Ui_Cursor_Kind is the portable pointer shape requested by UI interaction.
Ui_Cursor_Kind :: enum u8 {
    Default,
    Text,
    Resize_Ew,
    Resize_Ns,
}

// Ui_Input_Box_State retains bounded interaction state while borrowing model text.
Ui_Input_Box_State :: struct {
    cursor_byte: int,
    anchor_byte: int,
    scroll_x: f32,
    content_revision: u64,
    dragging: bool,
}

// Library_Search_State owns bounded display-side query and accepted-result state.
Library_Search_State :: struct {
    query: [LIBRARY_SEARCH_QUERY_BYTE_CAPACITY]u8,
    query_length: int,
    query_revision: u64,
    input: Ui_Input_Box_State,
    generation: u64,
    committed_generation: u64,
    index_generation: u64,
    debounce_remaining_seconds: f32,
    query_dirty: bool,
    submit_requested: bool,
    worker_available: bool,
    invalid_query: bool,
    active: bool,
    visible_ids: [LIBRARY_SEARCH_VISIBLE_ID_CAPACITY]uuid.Identifier,
    visible_id_count: int,
    total_match_count: u32,
    more_available: bool,
    suggestion: [LIBRARY_SEARCH_QUERY_BYTE_CAPACITY]u8,
    suggestion_length: int,
    scenario_correlation: u64,
    scenario_correlation_generation: u64,
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
    terminal_semantic_focus_initialized: bool,
    terminal_semantic_focus_generation: u64,
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
    gpu_dust_instancing_available: bool,
    use_gpu_dust_instancing: bool,
    colored_vertex_count: u32,
    colored_index_count: u32,
    curve_candidate_point_count: u32,
    curve_retained_point_count: u32,
    curve_retention_ratio: f32,
    colored_primitive_overflow_count: u32,
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
    gif_timing_mode: Gif_Capture_Timing_Mode,
    gif_capture_phase: Gif_Capture_Phase,
    gif_capture_frame_counter: int,
    gif_captured_frames: int,
    gif_status_note: [260]u8,
    gif_status_note_len: int,
    last_gif_path: [GIF_PATH_CAPACITY]u8,
    last_gif_path_len: int,
    last_gif_path_revision: u64,
    last_gif_path_truncated: bool,
    gif_path_input: Ui_Input_Box_State,
    library_search: Library_Search_State,
    window: Ui_Window_Metrics,
    layout_preference: Layout_Preference,
    landscape: Ui_Landscape_Layout_State,
    portrait: Ui_Portrait_Layout_State,
    current_layout_mode: Ui_Layout_Mode,
    ui_regions: Ui_Regions,
    interaction: Ui_Interaction_State,
    interaction_frame: Ui_Interaction_Frame,
    semantic_focus: ^Ui_Semantic_Focus_State,
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

// library_search_clear_results removes accepted topology and suggestion state.
library_search_clear_results :: proc(search: ^Library_Search_State) {
    search^.active = false
    search^.invalid_query = false
    search^.visible_id_count = 0
    search^.total_match_count = 0
    search^.more_available = false
    search^.suggestion_length = 0
}

// library_search_query_changed invalidates results and starts the typeahead debounce.
library_search_query_changed :: proc(
    search: ^Library_Search_State, debounce_seconds: f32,
    content_replaced: bool = false) {
    search^.generation += 1
    search^.scenario_correlation = 0
    search^.scenario_correlation_generation = 0
    if content_replaced {search^.query_revision += 1}
    library_search_clear_results(search)
    search^.query_dirty = search^.query_length > 0
    search^.submit_requested = false
    search^.debounce_remaining_seconds = max(debounce_seconds, f32(0))
}