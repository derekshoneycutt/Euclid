package termattachment

DEFAULT_ATTACHMENT_CAPACITY :: 256
DEFAULT_PLACEMENT_CAPACITY :: 1024
DEFAULT_TRANSFER_CAPACITY :: 4
DEFAULT_TRANSFER_BYTE_LIMIT :: 32 * 1024 * 1024
DEFAULT_DIMENSION_LIMIT :: 8192
DEFAULT_IMAGE_PIXEL_LIMIT :: 16_777_216
DEFAULT_CPU_BYTE_LIMIT :: 256 * 1024 * 1024
DEFAULT_GPU_BYTE_LIMIT :: 256 * 1024 * 1024
DEFAULT_ANIMATED_ATTACHMENT_LIMIT :: 64
DEFAULT_ANIMATION_FRAME_LIMIT :: 1024
DEFAULT_ANIMATION_DECODE_BYTE_LIMIT :: 256 * 1024 * 1024
DEFAULT_ANIMATION_MIN_FRAME_DURATION_NS :: 10 * 1_000_000
DEFAULT_ANIMATION_MAX_FRAME_DURATION_NS :: 60 * 1_000_000_000
DEFAULT_ANIMATION_DURATION_NS_LIMIT :: 24 * 60 * 60 * 1_000_000_000
FALLBACK_TEXT_BYTE_CAPACITY :: 256

// Generational identity for one immutable attachment lifetime.
Attachment_Id :: struct {
    slot: int,
    generation: u64,
}

// Generational identity for one placement lifetime.
Placement_Id :: struct {
    slot: int,
    generation: u64,
}

// Generational identity for one encoded transfer lifetime.
Transfer_Id :: struct {
    slot: int,
    generation: u64,
}

// Semantic payload representation independent of its transport protocol.
Payload_Kind :: enum u8 {
    Raster,
}

// Source protocol or internal producer that created an attachment.
Protocol_Origin :: enum u8 {
    Kitty,
    Sixel,
    Iterm2,
}

// Primitive screen identity that avoids a dependency on the terminal grid package.
Screen_Identity :: enum u8 {
    Primary,
    Alternate,
}

// Policy for mapping intrinsic content into an allocated rectangle.
Sizing_Mode :: enum u8 {
    Intrinsic_Centered,
    Fit,
    Fill,
    Explicit_Pixels,
    Explicit_Cells,
}

// Policy for terminal cursor movement after creating a placement.
Cursor_Policy :: enum u8 {
    Protocol_Default,
    Preserve,
    Advance,
}

// Policy controlling replacement, deletion, and terminal-row retention.
Lifecycle_Policy :: enum u8 {
    Addressable,
    Cursor_Anchored,
}

// CPU payload format resolved without exposing a native rendering resource.
Raster_Format :: enum u8 {
    Rgb8,
    Rgba8,
    Indexed8,
}

// Complete caller-owned input for one immutable attachment admission.
Attachment_Admission :: struct {
    // Semantic identity and borrowed source bytes copied during admission.
    metadata: Attachment_Metadata,
    payload: []u8,

    // Raster layout used to validate rows and interpret the copied payload.
    payload_format: Raster_Format,
    payload_stride: int,

    // Protocol identity retention independent of placements and checkpoint pins.
    protocol_retained: bool,
}

// Complete caller-owned input for one asynchronous raster preparation reservation.
Attachment_Reservation :: struct {
    // Semantic identity and exact output storage reserved before task submission.
    metadata: Attachment_Metadata,
    payload_byte_count: int,

    // Raster layout used to validate and publish the prepared output.
    payload_format: Raster_Format,
    payload_stride: int,

    // Protocol identity retention independent of placements and preparation ownership.
    protocol_retained: bool,
}

// Borrowed immutable payload resolved from one live attachment generation.
Payload_View :: struct {
    bytes: []u8,
    format: Raster_Format,
    stride: int,
}

// Offset and byte count within one attachment-owned recyclable payload.
Payload_Range :: struct {
    offset: int,
    count: int,
}

// Immutable normalized frame descriptor independent of source protocol syntax.
Animation_Frame :: struct {
    pixels: Payload_Range,
    duration_ns: u64,
}

// Immutable loop and frame-range contract for one published attachment timeline.
Animation_Timeline :: struct {
    frame_count: int,
    cycle_duration_ns: u64,
    repeat_count: u32,
    infinite: bool,
}

// Complete caller-owned input for one pending full-canvas animation reservation.
Animation_Reservation :: struct {
    metadata: Attachment_Metadata,
    frame_count: int,
    payload_byte_count: int,
    temporary_decode_byte_count: int,
    repeat_count: u32,
    infinite: bool,
    protocol_retained: bool,
}

// Exclusive mutable destinations borrowed by one animation preparation task.
Animation_Preparation :: struct {
    pixels: []u8,
    frames: []Animation_Frame,
}

// Borrowed immutable normalized animation resolved from one live generation.
Animation_View :: struct {
    pixels: []u8,
    frames: []Animation_Frame,
    timeline: Animation_Timeline,
}

// One transactional Kitty frame upload or edit against a live attachment.
Kitty_Frame_Mutation :: struct {
    pixels: []u8,
    format: Raster_Format,
    width: int,
    height: int,
    destination_x: int,
    destination_y: int,
    base_frame: int,
    edit_frame: int,
    gap_ms: i32,
    gap_specified: bool,
    background_rgba: u32,
    overwrite: bool,
}

// One transactional Kitty frame-to-frame rectangle composition.
Kitty_Frame_Composition :: struct {
    source_frame: int,
    destination_frame: int,
    source_x: int,
    source_y: int,
    destination_x: int,
    destination_y: int,
    width: int,
    height: int,
    overwrite: bool,
}

// Timeline timing and loop controls applied atomically to one Kitty attachment.
Kitty_Animation_Control :: struct {
    frame_number: int,
    gap_ms: i32,
    gap_specified: bool,
    loop_count: u32,
}

// Result of mutating a prepared attachment generation.
Animation_Mutation_Outcome :: enum u8 {
    Found,
    Stale,
    Invalid,
    Not_Found,
    Capacity_Exceeded,
    Allocation_Failed,
}

// Result of admitting an object into one bounded store.
Admission_Outcome :: enum u8 {
    Admitted,
    Invalid,
    Capacity_Exceeded,
    Byte_Limit_Exceeded,
    Pixel_Limit_Exceeded,
    Allocation_Failed,
    No_Evictable_Entry,
}

// Result of resolving or mutating a generational handle.
Handle_Outcome :: enum u8 {
    Found,
    Stale,
}

// Inclusive-origin, exclusive-size pixel rectangle within one payload.
Pixel_Rectangle :: struct {
    x: int,
    y: int,
    width: int,
    height: int,
}

// Immutable natural measurement and optional semantic alignment metadata.
Intrinsic_Metrics :: struct {
    width: int,
    height: int,
    has_baseline: bool,
    baseline_from_top: f32,
}

// Bounded semantic fallback retained with an attachment.
Fallback_Text :: struct {
    bytes: [FALLBACK_TEXT_BYTE_CAPACITY]u8,
    count: int,
}

// Immutable metadata shared by every placement of one payload.
Attachment_Metadata :: struct {
    kind: Payload_Kind,
    origin: Protocol_Origin,
    metrics: Intrinsic_Metrics,
    fallback: Fallback_Text,
}

// Cell and pixel geometry for one terminal-owned presentation.
Placement_Geometry :: struct {
    // Stable terminal anchor independent of viewport position.
    screen: Screen_Identity,
    logical_row: i64,
    column: int,

    // Optional cell and pixel allocation; zero dimensions defer to sizing policy.
    column_span: int,
    row_span: int,
    pixel_width: int,
    pixel_height: int,

    // Content transform within the terminal-owned allocation.
    content_offset_x: int,
    content_offset_y: int,
    source: Pixel_Rectangle,
    sizing: Sizing_Mode,

    // Presentation ordering and protocol-defined cursor behavior.
    z_index: i32,
    cursor: Cursor_Policy,
}

// Complete immutable placement contract referencing one attachment lifetime.
Placement_Metadata :: struct {
    attachment_id: Attachment_Id,
    geometry: Placement_Geometry,
    lifecycle: Lifecycle_Policy,
}

// Centralized resource and occupancy policy for attachment stores.
Limits :: struct {
    // Fixed entry-table capacities allocated during store initialization.
    attachment_capacity: int,
    placement_capacity: int,
    transfer_capacity: int,

    // Per-transfer and per-image admission limits.
    transfer_byte_limit: int,
    dimension_limit: int,
    image_pixel_limit: int,

    // Aggregate retained CPU payload and GPU residency budgets.
    cpu_byte_limit: int,
    gpu_byte_limit: int,

    // Animated occupancy, preparation, timeline, and temporary decode policy.
    animated_attachment_limit: int,
    animation_frame_limit: int,
    animation_decode_byte_limit: int,
    animation_min_frame_duration_ns: u64,
    animation_max_frame_duration_ns: u64,
    animation_duration_ns_limit: u64,
}

// Frame-local pixel geometry supplied to an application-owned raster renderer.
Render_Rectangle :: struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

// Complete immutable draw request without native graphics resource types.
Raster_Draw_Request :: struct {
    // Payload identity and source crop resolved by the display-owned renderer.
    attachment_id: Attachment_Id,
    source: Pixel_Rectangle,

    // Frame-local destination and terminal clipping rectangles.
    destination: Render_Rectangle,
    clip: Render_Rectangle,

    // Stable terminal stacking order for this placement.
    z_index: i32,
}

//   Draw one measured raster placement without mutating terminal state.
//
// Parameters:
//   - user_data: Opaque display-owned renderer state borrowed for this call.
//   - request: Immutable payload identity and frame-local draw geometry.
//
// Returns:
//   - True when the renderer accepted and drew the request; false when the
//     payload is unavailable or cannot be drawn.
//
// Notes:
//   - Implementations may resolve native resources but must not retain request
//     data or mutate terminal attachment state.
Raster_Draw_Handler :: #type proc(
    user_data: rawptr, request: Raster_Draw_Request) -> bool

// Borrowing renderer capability implemented by a display-owned resource cache.
Raster_Renderer :: struct {
    user_data: rawptr,
    draw: Raster_Draw_Handler,
}

// Callback that maps one captured placement geometry into replacement topology.
Placement_Relocate_Handler :: #type proc(
    user_data: rawptr, geometry: Placement_Geometry) ->
    (Placement_Geometry, bool)

//   Return the initial bounded resource policy for terminal graphics.
//
// Returns:
//   - Fixed entry capacities and byte/pixel budgets selected for initial
//     graphics protocol support.
//
// Notes:
//   - Values are application policy rather than protocol limits. Callers may
//     supply a different fully positive `Limits` value to `store_init`.
limits_default :: proc() -> Limits {
    return {
        attachment_capacity = DEFAULT_ATTACHMENT_CAPACITY,
        placement_capacity = DEFAULT_PLACEMENT_CAPACITY,
        transfer_capacity = DEFAULT_TRANSFER_CAPACITY,
        transfer_byte_limit = DEFAULT_TRANSFER_BYTE_LIMIT,
        dimension_limit = DEFAULT_DIMENSION_LIMIT,
        image_pixel_limit = DEFAULT_IMAGE_PIXEL_LIMIT,
        cpu_byte_limit = DEFAULT_CPU_BYTE_LIMIT,
        gpu_byte_limit = DEFAULT_GPU_BYTE_LIMIT,
        animated_attachment_limit = DEFAULT_ANIMATED_ATTACHMENT_LIMIT,
        animation_frame_limit = DEFAULT_ANIMATION_FRAME_LIMIT,
        animation_decode_byte_limit = DEFAULT_ANIMATION_DECODE_BYTE_LIMIT,
        animation_min_frame_duration_ns = DEFAULT_ANIMATION_MIN_FRAME_DURATION_NS,
        animation_max_frame_duration_ns = DEFAULT_ANIMATION_MAX_FRAME_DURATION_NS,
        animation_duration_ns_limit = DEFAULT_ANIMATION_DURATION_NS_LIMIT,
    }
}