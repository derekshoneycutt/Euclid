package dynviewmodel

import fontmodel "../../view/font/model"
import presentation_model "../../bridge/presentation"
import color "../../core/color"
import geometry "../../core/geometry"
import storage "../../core/storage"

DYNVIEW_MAX_COMMANDS :: 1024
DYNVIEW_MAX_TEXT_BYTES :: presentation_model.PRESENTATION_MAX_SOURCE_BYTES
FONT_SHAPED_GLYPH_CAPACITY :: fontmodel.FONT_SHAPED_GLYPH_CAPACITY
DYNVIEW_MAX_LAYOUT_LINES :: 4096
DYNVIEW_MAX_LAYOUT_ITEMS :: 8192
DYNVIEW_MAX_MATH_PROGRAMS :: 256
DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS :: DYNVIEW_MAX_MATH_PROGRAMS
DYNVIEW_MAX_MATH_NODES :: 4096
DYNVIEW_MAX_MATH_COMMANDS :: 4096
DYNVIEW_MAX_SHAPED_RUNS :: DYNVIEW_MAX_MATH_COMMANDS
DYNVIEW_MAX_DOCUMENTS :: 256
DYNVIEW_MAX_DOCUMENT_BLOCKS :: 256
DYNVIEW_MAX_DOCUMENT_INLINES :: 2048
DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS :: 512
DYNVIEW_MAX_DOCUMENT_BYTES :: 128 * 1024
DYNVIEW_MAX_DOCUMENT_SHAPED_RUNS :: DYNVIEW_MAX_DOCUMENT_INLINES
DYNVIEW_MAX_DOCUMENT_SHAPED_GLYPHS :: DYNVIEW_MAX_DOCUMENT_BYTES
DYNVIEW_MAX_DOCUMENT_LAYOUT_NODES :: DYNVIEW_MAX_DOCUMENT_INLINES
DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES :: DYNVIEW_MAX_LAYOUT_LINES
DYNVIEW_MAX_DOCUMENT_LAYOUT_ITEMS :: DYNVIEW_MAX_LAYOUT_ITEMS
DYNVIEW_MAX_DOCUMENT_BREAK_CANDIDATES :: DYNVIEW_MAX_DOCUMENT_LAYOUT_NODES + 1
DYNVIEW_MAX_DOCUMENT_BREAK_STATES :: DYNVIEW_MAX_DOCUMENT_BREAK_CANDIDATES * 4
DYNVIEW_MAX_DOCUMENT_BREAK_WORK :: 1024 * 1024
DYNVIEW_MAX_DOCUMENT_LAYOUT_COPY_TARGETS ::
    DYNVIEW_MAX_DOCUMENT_SHAPED_GLYPHS + DYNVIEW_MAX_DOCUMENT_INLINES

/****
    Dynview is just dynamic view, not original lol. It is a dynamic text construction,
    including limited LaTeX style support
*/



Font_Weight :: fontmodel.Font_Weight
Font_Variant_Flags :: fontmodel.Font_Variant_Flags
Color :: color.Color_RGBA8

Dynview_Text_Alignment :: enum {
    Left,
    Center,
}

Dynview_Text_Style :: struct {
    color: Color,
    alignment: Dynview_Text_Alignment,
    bold: bool,
    italic: bool,
    underline: bool,
    font_flags: fontmodel.Font_Variant_Flags,
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

Dynview_Math_Style_Level :: enum i32 {
    Display = 0,
    Text = 1,
    Script = 2,
    Script_Script = 3,
}

Dynview_Math_Length_Unit :: enum i32 {
    Default = 0,
    Zero = 1,
    Em = 2,
    Ex = 3,
    Point = 4,
}

Dynview_Math_Length :: struct {
    value: f32,
    unit: Dynview_Math_Length_Unit,
}

Dynview_Math_Table_Row_Spacing :: enum i32 {
    Matrix = 0,
    Tight = 1,
    Cases = 2,
    Alignment = 3,
}

Dynview_Math_Table_Descriptor :: struct {
    rows: int,
    columns: int,
    cell_style: Dynview_Math_Style_Level,
    row_spacing: Dynview_Math_Table_Row_Spacing,
    column_alignments: [16]Dynview_Matrix_Column_Alignment,
    column_boundary_gaps: [17]Dynview_Math_Length,
    vertical_rule_counts: [17]u8,
    row_extra_gaps: [16]Dynview_Math_Length,
    horizontal_rule_counts: [17]u8,
}

Dynview_Command_Kind :: enum {
    Begin_Block,
    End_Block,
    Text_Run,
    Math_Glyph_Run,
    Math_Block,
    Script_Attach,
    Frac,
    Stretch_Delimiter,
    Matrix,
    Style_Override,
    Stack,
    Large_Op,
    Accent_Bar,
    Radical_Bar,
    Line_Break,
    Divider,
    Inline_Line,
    Inline_Box,
    Inline_Circle,
    Inline_Filled_Box,
    Inline_Filled_Circle,
    Inline_Pie_Section,
    Inline_Perpendicular,
    Inline_Triangle,
    Inline_Pentagon,
}

Dynview_Math_Atom_Class :: enum i32 {
    None = 0,
    Ord,
    Op,
    Bin,
    Rel,
    Open,
    Close,
    Punct,
    Inner,
}

Dynview_Math_Glue_Kind :: enum i32 {
    None = 0,
    Thick,
    Space,
    Negative_Thin,
    Quad,
    Thin,
}

Dynview_Command :: struct {
    kind: Dynview_Command_Kind,
    math_atom_class: Dynview_Math_Atom_Class,
    math_glue_kind: Dynview_Math_Glue_Kind,
    block_id: i32,
    style_id: i32,
    math_program_id: i32,
    secondary_math_program_id: i32,
    tertiary_math_program_id: i32,
    table_descriptor_index: i32,
    math_style_level: u8,
    math_style_cramped: bool,
    math_font_size: f32,
    shaped_run_indices: [4]i32,
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
    operator_growth: i32,
    operator_limits: i32,
    radical_index_text_offset: int,
    radical_index_text_len: int,
    accent_style_id: i32,
    accent_thickness: f32,
    accent_offset: f32,
    inline_atom_dimension: f32,
    inline_atom_stroke: f32,
    inline_box_height: f32,
    has_brush_color: bool,
    brush_color: Color,
    inline_outline_stroke: f32,
    pie_start_angle_degrees: f32,
    pie_end_angle_degrees: f32,
    pie_is_filled: bool,
    has_outline_color: bool,
    outline_color: Color,
    shape_is_filled: bool,
    shape_edge_color_1: Color,
    shape_edge_color_2: Color,
    shape_edge_color_3: Color,
    shape_edge_color_4: Color,
    shape_edge_color_5: Color,
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
    rect: geometry.Rectangle,
    hover_rect: geometry.Rectangle,
}

Dynview_Layout_Item_Kind :: enum {
    Text_Run,
    Math_Glyph_Run,
    Math_Block,
    Script_Attach,
    Frac,
    Stretch_Delimiter,
    Matrix,
    Style_Override,
    Stack,
    Large_Op,
    Accent_Bar,
    Radical_Bar,
    Inline_Line,
    Inline_Box,
    Inline_Circle,
    Inline_Filled_Box,
    Inline_Filled_Circle,
    Inline_Pie_Section,
    Inline_Perpendicular,
    Inline_Triangle,
    Inline_Pentagon,
}

Dynview_Layout_Item :: struct {
    kind: Dynview_Layout_Item_Kind,
    block_id: i32,
    style_id: i32,
    math_command_index: i32,
    math_program_id: i32,
    secondary_math_program_id: i32,
    tertiary_math_program_id: i32,
    table_descriptor_index: i32,
    math_style_level: u8,
    math_style_cramped: bool,
    math_font_size: f32,
    line_index: int,
    col_start: int,
    col_span: int,
    row_offset: int,
    row_span: int,
    baseline_row: int,
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
    script_sup_x: f32,
    script_sup_baseline: f32,
    script_sub_x: f32,
    script_sub_baseline: f32,
    script_space_after: f32,
    script_geometry_valid: bool,
    math_first_glyph_id: u32,
    math_last_glyph_id: u32,
    math_has_edge_glyphs: bool,
    script_base_glyph_id: u32,
    script_sup_glyph_id: u32,
    script_sub_glyph_id: u32,
    fraction_numerator_x: f32,
    fraction_numerator_baseline: f32,
    fraction_denominator_x: f32,
    fraction_denominator_baseline: f32,
    fraction_rule_left: f32,
    fraction_rule_right: f32,
    fraction_rule_center: f32,
    fraction_rule_thickness: f32,
    fraction_geometry_valid: bool,
    accent_child_baseline: f32,
    accent_rule_left: f32,
    accent_rule_right: f32,
    accent_rule_center: f32,
    accent_rule_thickness: f32,
    accent_geometry_valid: bool,
    accent_child_x: f32,
    accent_glyph_x: f32,
    accent_glyph_line_top: f32,
    accent_glyph_scale: f32,
    accent_glyph_raster_ascent: f32,
    accent_glyph_font_generation: u64,
    accent_glyph_construction: fontmodel.Font_Math_Stretch_Construction,
    accent_mode: i32,
    radical_mode: i32,
    large_op_kind: i32,
    operator_growth: i32,
    operator_limits: i32,
    math_atom_class: Dynview_Math_Atom_Class,
    operator_glyph_id: u32,
    operator_font_generation: u64,
    operator_glyph_x: f32,
    operator_glyph_line_top: f32,
    operator_glyph_font_size: f32,
    operator_geometry_valid: bool,
    math_stretch_constructions: [2]fontmodel.Font_Math_Stretch_Construction,
    math_stretch_font_generation: u64,
    math_stretch_raster_ascent: f32,
    math_stretch_scale: f32,
    math_stretch_left_x: f32,
    math_stretch_right_x: f32,
    math_stretch_bottom: f32,
    math_stretch_vertical_origins: [2]f32,
    math_stretch_content_x: f32,
    math_stretch_target_height: f32,
    math_stretch_geometry_valid: bool,
    radical_rule_left: f32,
    radical_rule_right: f32,
    radical_rule_center: f32,
    radical_rule_thickness: f32,
    radical_degree_x: f32,
    radical_degree_baseline: f32,
    radical_geometry_valid: bool,
    radical_index_text_offset: int,
    radical_index_text_len: int,
    accent_style_id: i32,
    accent_thickness: f32,
    accent_offset: f32,
    inline_atom_dimension: f32,
    inline_atom_stroke: f32,
    inline_box_height: f32,
    has_brush_color: bool,
    brush_color: Color,
    inline_outline_stroke: f32,
    pie_start_angle_degrees: f32,
    pie_end_angle_degrees: f32,
    pie_is_filled: bool,
    has_outline_color: bool,
    outline_color: Color,
    shape_is_filled: bool,
    shape_edge_color_1: Color,
    shape_edge_color_2: Color,
    shape_edge_color_3: Color,
    shape_edge_color_4: Color,
    shape_edge_color_5: Color,
    content_offset_x: f32,
    content_offset_y: f32,
    overflows_horizontally: bool,
    draw_width: f32,
    math_advance: f32,
    draw_height: f32,
    pie_center_offset_x: f32,
    pie_center_offset_y: f32,
    ascent: f32,
    descent: f32,
    visual_padding_top: f32,
    visual_padding_bottom: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
}

Dynview_Math_Node_Kind :: enum {
    None,
    Sequence,
    Glyph_Run,
    Script,
    Radical,
    Fraction,
    Stretch_Delimiter,
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
    advance: f32,
    ascent: f32,
    descent: f32,
    visual_padding_top: f32,
    visual_padding_bottom: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
    first_glyph_id: u32,
    last_glyph_id: u32,
    has_edge_glyphs: bool,
}

Dynview_Shaped_Site :: enum u8 {
    Primary,
    Superscript,
    Subscript,
    Radical_Index,
}

Dynview_Shaped_Run :: struct {
    math_command_index: int,
    site: Dynview_Shaped_Site,
    text_offset: int,
    text_len: int,
    glyph_start: int,
    glyph_count: int,
    font_generation: u64,
    base_pixel_size: f32,
    raster_ascent: f32,
    advance: f32,
    ink_left: f32,
    ink_right: f32,
    ascent: f32,
    descent: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
}

Dynview_Layout_Line :: struct {
    item_start: int,
    item_count: int,
    row_start: int,
    row_span: int,
    baseline_row: int,
    max_ascent: f32,
    max_descent: f32,

    // Unused vertical space between this line's lowest ink and its band bottom. The
    // next line may raise ink into it without colliding.
    ink_slack_below: f32,
}

Dynview_Command_Buffer :: struct {
    revision: u64,
    command_count: int,
    text_bytes_len: int,
    has_stream_error: bool,
    stream_open_block: bool,
    stream_open_block_id: i32,
    command_view: []Dynview_Command,
    text_view: []u8,

    commands: [DYNVIEW_MAX_COMMANDS]Dynview_Command,
    text_bytes: [DYNVIEW_MAX_TEXT_BYTES]u8,
}

// Identify one font-independent block copied into a semantic snapshot.
Dynview_Document_Block_Kind :: enum u8 {
    Paragraph,
    Display,
    List_Item,
}

// Identify one resolved document container in snapshot-owned storage.
Dynview_Document_Container_Kind :: enum u8 {
    None,
    Quote,
    Quotation,
    Itemize,
    Enumerate,
    Description,
}

// Identify list formatting independently from surrounding quotation containers.
Dynview_Document_List_Kind :: enum u8 {
    None,
    Itemize,
    Enumerate,
    Description,
}

// Identify one semantic item copied into a document block.
Dynview_Document_Inline_Kind :: enum u8 {
    Text,
    Space,
    Math,
    Shape,
    Penalty,
    Forced_Break,
}

// Distinguish spacing behavior before physical measurement.
Dynview_Document_Space_Kind :: enum u8 {
    Breakable,
    Nonbreaking,
    Controlled,
}

// Identify block alignment independently from physical placement.
Dynview_Document_Alignment :: enum u8 {
    Left,
    Center,
    Right,
}

// Identify supported inline Euclid shape semantics in snapshot storage.
Dynview_Document_Shape_Kind :: enum u8 {
    None,
    Point,
    Line,
    Circle,
    Box,
    Angle,
    Semicircle,
    Perpendicular,
    Triangle,
    Pentagon,
}

// Retain one optional semantic color without parser-owned storage.
Dynview_Document_Color :: struct {
    present: bool,
    value: Color,
}

// Retain one font-independent inline Euclid shape payload.
Dynview_Document_Shape :: struct {
    present: bool,
    kind: Dynview_Document_Shape_Kind,
    color: Dynview_Document_Color,
    width: f32,
    height: f32,
    thickness: f32,
    filled: bool,
    start_angle: f32,
    end_angle: f32,
    fill_color: Dynview_Document_Color,
    arc_color: Dynview_Document_Color,
    edge_colors: [5]Dynview_Document_Color,
}

// Retain one contiguous semantic document inside snapshot-owned storage.
Dynview_Document :: struct {
    source_offset: int,
    source_count: int,
    text_offset: int,
    text_count: int,
    block_start: int,
    block_count: int,
    inline_start: int,
    inline_count: int,
    display_row_start: int,
    display_row_count: int,
}

// Identify the document-level policy for one technical display environment.
Dynview_Document_Display_Kind :: enum {
    Plain,
    Equation,
    Align,
    Gather,
    Multline,
}

// Retain one pointer-free semantic block with staging-relative child offsets.
Dynview_Document_Block :: struct {
    kind: Dynview_Document_Block_Kind,
    inline_start: int,
    inline_count: int,
    source_offset: int,
    source_count: int,
    alignment: Dynview_Document_Alignment,
    no_indent: bool,
    container_kind: Dynview_Document_Container_Kind,
    container_depth: u8,
    left_margin_levels: u8,
    right_margin_levels: u8,
    list_kind: Dynview_Document_List_Kind,
    list_id: u16,
    item_ordinal: u16,
    item_first_block: bool,
    display_kind: Dynview_Document_Display_Kind,
    display_row_start: int,
    display_row_count: int,
    display_numbered: bool,
}

// Retain one pointer-free technical display row with resolved math program IDs.
Dynview_Document_Display_Row :: struct {
    source_offset: int,
    source_count: int,
    primary_program_id: int,
    secondary_program_id: int,
    alignment: Dynview_Document_Alignment,
    suppress_number: bool,
    number: int,
}

// Retain one pointer-free inline item with staging-relative byte and program offsets.
Dynview_Document_Inline :: struct {
    kind: Dynview_Document_Inline_Kind,
    source_offset: int,
    source_count: int,
    text_offset: int,
    text_count: int,
    font_flags: i32,
    color: Dynview_Document_Color,
    space_kind: Dynview_Document_Space_Kind,
    shape: Dynview_Document_Shape,
    root_style: Dynview_Math_Style_Level,
    math_program_id: int,
    penalty: i32,
}

// Retain one generation-specific JuliaMono measurement for a semantic prose inline.
Dynview_Document_Shaped_Run :: struct {
    inline_index: int,
    text_offset: int,
    text_count: int,
    glyph_start: int,
    glyph_count: int,
    requested_font_key: fontmodel.Font_Key,
    effective_font_key: fontmodel.Font_Key,
    font_generation: u64,
    base_pixel_size: f32,
    raster_ascent: f32,
    width: f32,
    ascent: f32,
    descent: f32,
}

Dynview_Document_Layout_Node_Kind :: enum u8 {
    Box,
    Glue,
    Penalty,
    Forced_Break,
}

Dynview_Document_Box_Kind :: enum u8 {
    None,
    Prose,
    Math,
    Shape,
}

// Retain one measured semantic inline before paragraph breaking.
Dynview_Document_Layout_Node :: struct {
    kind: Dynview_Document_Layout_Node_Kind,
    box_kind: Dynview_Document_Box_Kind,
    inline_index: int,
    shaped_run_index: int,
    source_offset: int,
    source_count: int,
    text_offset: int,
    text_count: int,
    width: f32,
    ascent: f32,
    descent: f32,
    stretch: f32,
    shrink: f32,
    penalty: i32,
    break_allowed: bool,
}

// Retain one positioned semantic inline in pixel-native paragraph space.
Dynview_Document_Layout_Item :: struct {
    box_kind: Dynview_Document_Box_Kind,
    inline_index: int,
    shaped_run_index: int,
    line_index: int,
    source_offset: int,
    source_count: int,
    text_offset: int,
    text_count: int,
    x: f32,
    top: f32,
    baseline: f32,
    width: f32,
    ascent: f32,
    descent: f32,
}

// Retain one measured paragraph line and its contiguous item range.
Dynview_Document_Layout_Line :: struct {
    node_start: int,
    node_count: int,
    item_start: int,
    item_count: int,
    block_index: int,
    x: f32,
    top: f32,
    baseline: f32,
    bottom: f32,
    natural_width: f32,
    width: f32,
    adjustment_ratio: f32,
    ascent: f32,
    descent: f32,
    overfull: bool,
    display_row_index: int,
    display_number: int,
    display_number_x: f32,
    display_number_width: f32,
    display_number_baseline_offset: f32,
    display_content_width: f32,
}

// Retain one semantic block's contiguous measured line range.
Dynview_Document_Layout_Block :: struct {
    source_block_index: int,
    node_start: int,
    node_count: int,
    line_start: int,
    line_count: int,
    top: f32,
    bottom: f32,
    height: f32,
    spacing_before: f32,
    reserved_top: f32,
    reserved_bottom: f32,
    trailing_padding: f32,
    row_start: int,
    row_count: int,
    width: f32,
    content_origin: f32,
    content_width: f32,
    list_label_above: bool,
}

// Identify authored separation before one selectable document target.
Dynview_Document_Selection_Separator :: enum u8 {
    None,
    Space,
    Line,
    Item,
    Block,
}

// Retain one source span's horizontal geometry in a measured semantic line.
Dynview_Document_Layout_Copy_Target :: struct {
    line_index: int,
    item_index: int,
    offset: int,
    count: int,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    canonical_text: bool,
    separator_before: Dynview_Document_Selection_Separator,
}

// Identify the visible presentation model owning one logical text selection.
Dynview_Selection_Mode :: enum u8 {
    None,
    Semantic_Document,
    Atomic_Source,
    Wrapped_Text,
}

// Identify one half-open boundary between ordered selectable presentation units.
Dynview_Selection_Position :: struct {
    unit_index: int,
}

// Retain display-thread selection state against one compiled content revision.
Dynview_Selection_State :: struct {
    mode: Dynview_Selection_Mode,
    revision: u64,
    anchor: Dynview_Selection_Position,
    head: Dynview_Selection_Position,
    active: bool,
    dragging: bool,
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
    math_table_descriptor_count: int,
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
    last_cell_width: f32,
    last_cell_height: f32,
    last_style_revision: u64,
    last_prose_effective_keys: [int(fontmodel.Font_Key.Math_Regular)]fontmodel.Font_Key,
    last_prose_font_generations: [int(fontmodel.Font_Key.Math_Regular)]u64,

    last_invalidation_mask: u32,
    last_error_code: i32,

    shaped_runs: []Dynview_Shaped_Run,
    shaped_glyphs: []fontmodel.Shaped_Glyph,
    math_kern_tables: []fontmodel.Font_Math_Kern_Table,
    math_accent_sources: [][2]fontmodel.Font_Math_Stretch_Source,
    shaped_font_generation: u64,
    math_constants: fontmodel.Font_Math_Constants,
    math_operator_variants:
        [DYNVIEW_MAX_MATH_COMMANDS]fontmodel.Font_Math_Glyph_Variants,
    math_stretch_sources:
        [DYNVIEW_MAX_MATH_COMMANDS][2]fontmodel.Font_Math_Stretch_Source,

    document_shaped_runs: []Dynview_Document_Shaped_Run,
    document_shaped_glyphs: []fontmodel.Shaped_Glyph,
    document_layout_nodes: []Dynview_Document_Layout_Node,
    document_layout_blocks: []Dynview_Document_Layout_Block,
    document_layout_lines: []Dynview_Document_Layout_Line,
    document_layout_items: []Dynview_Document_Layout_Item,
    document_layout_copy_targets: []Dynview_Document_Layout_Copy_Target,
    document_layout_total_height: f32,
    document_layout_is_valid: bool,
    document_layout_used_greedy_fallback: bool,
    document_layout_break_fallback_code: i32,
    document_layout_overfull_line_count: int,

    compiled_plain_text: []u8,
    compiled_copy_payload: []u8,
    copy_blocks: []Dynview_Copy_Block,
    copy_hit_targets: []Dynview_Copy_Hit_Target,
    copy_hit_target_builder: storage.Bounded_Element_Builder(Dynview_Copy_Hit_Target),
    layout_lines: []Dynview_Layout_Line,
    layout_items: []Dynview_Layout_Item,
    layout_line_builder: storage.Bounded_Element_Builder(Dynview_Layout_Line),
    layout_item_builder: storage.Bounded_Element_Builder(Dynview_Layout_Item),
    math_programs: [DYNVIEW_MAX_MATH_PROGRAMS]Dynview_Math_Program,
    math_table_descriptors:
        [DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS]Dynview_Math_Table_Descriptor,
    math_commands: [DYNVIEW_MAX_MATH_COMMANDS]Dynview_Command,
    math_nodes: [DYNVIEW_MAX_MATH_NODES]Dynview_Math_Node,
    document_text_count: int,
    document_count: int,
    document_block_count: int,
    document_inline_count: int,
    document_display_row_count: int,
    document_text: [DYNVIEW_MAX_DOCUMENT_BYTES]u8,
    documents: [DYNVIEW_MAX_DOCUMENTS]Dynview_Document,
    document_blocks: [DYNVIEW_MAX_DOCUMENT_BLOCKS]Dynview_Document_Block,
    document_inlines: [DYNVIEW_MAX_DOCUMENT_INLINES]Dynview_Document_Inline,
    document_display_rows:
        [DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS]Dynview_Document_Display_Row,
}

Dynview_Cache_Access_State :: enum {
    Uninitialized,
    Worker_Mutable,
    Display_Readable,
}

Dynview_Content_View :: struct {
    revision: u64,
    presentation_mime: presentation_model.Presentation_Mime,
    presentation_bytes: []u8,
    has_stream_error: bool,
    stream_open_block: bool,
    stream_open_block_id: i32,
    commands: []Dynview_Command,
    text_bytes: []u8,
    math_programs: []Dynview_Math_Program,
    math_table_descriptors: []Dynview_Math_Table_Descriptor,
    math_commands: []Dynview_Command,
    math_nodes: []Dynview_Math_Node,
    document_text: []u8,
    documents: []Dynview_Document,
    document_blocks: []Dynview_Document_Block,
    document_inlines: []Dynview_Document_Inline,
    document_display_rows: []Dynview_Document_Display_Row,
}

Dynview_System :: struct {
    enabled: bool,
    pending_invalidation_mask: u32,
    content: Dynview_Content_View,

    cache_arena: storage.Arena_Owner,
    cache_access_state: Dynview_Cache_Access_State,
    cache_worker_thread_id: int,
    math_shaping: fontmodel.Font_Math_Shaping_Capability,

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
