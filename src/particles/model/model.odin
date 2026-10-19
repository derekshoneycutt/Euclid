package particlemodel

import color "../../core/color"
import geometry "../../core/geometry"
import rand "core:math/rand"

MAX_LOW_PARTICLES :: 65536
MAX_PARTICLES :: 2048
MAX_FORMATION_PARTICLES :: 16384
MAX_FORMATION_REVEALS :: 256
// Quantized view-depth bins for the per-frame formation draw-order counting sort.
FORMATION_DEPTH_BUCKETS :: 1024
MAX_DEPARTURE_MATERIAL_SAMPLES :: 900
DUST_ATLAS_VARIANT_COUNT :: 9

DUST_FIELD_DIM :: 251
DUST_FIELD_NODE_COUNT :: DUST_FIELD_DIM * DUST_FIELD_DIM
DUST_FIELD_STENCIL_CAP :: 4
DUST_SETTLED_SPEED_SQ :: f32(1e-8)
DUST_TOOL_CONTACT_CAP :: 64
DUST_REGION_PUSH_CAP :: 4
DUST_REGION_PUSH_VERTEX_CAP :: 96
SCENARIO_DUST_EMISSION_REQUEST_CAP :: 16

// Store one fixed scalar plane over the global dust-field topology.
Dust_Field_Scalar :: [DUST_FIELD_NODE_COUNT]f32

// Describe the four field nodes influencing one board-space position.
Dust_Field_Stencil :: struct {
    indices: [DUST_FIELD_STENCIL_CAP]i32,
    weights: [DUST_FIELD_STENCIL_CAP]f32,
}

// Cache one grounded particle's compact bilinear transfer coordinates.
Dust_Transfer :: struct {
    particle_index: i32,
    base_node: i32,
    fraction_x, fraction_y: f32,
}

// Describe one inclusive rectangular region of the vector-dust field.
Dust_Field_Bounds :: struct {
    min_x, min_y: i32,
    max_x, max_y: i32,
    valid: bool,
}

// Own the fixed physics planes for the field-only grounded-dust experiment.
Dust_Field_State :: struct {
    density: Dust_Field_Scalar,
    momentum_x: Dust_Field_Scalar,
    momentum_y: Dust_Field_Scalar,
    solved_velocity_x: Dust_Field_Scalar,
    solved_velocity_y: Dust_Field_Scalar,
    support_bounds: Dust_Field_Bounds,
    previous_solve_bounds: Dust_Field_Bounds,
}

// Spatial layout for one deterministic diagnostic dust emission.
Dust_Emission_Distribution :: enum u8 {
    Point,
    Disc,
    Grid,
}

// Describe one bounded worker-owned diagnostic dust emission request.
Scenario_Dust_Emission_Request :: struct {
    distribution: Dust_Emission_Distribution,
    count: u32,
    x, y, radius: f32,
    seed: u64,
    correlation: u64,
    generation: u64,
}

// Fixed display-to-particle handoff storage for scenario dust requests.
Dust_Emission_Request_Queue :: struct {
    items: [SCENARIO_DUST_EMISSION_REQUEST_CAP]Scenario_Dust_Emission_Request,
    count: int,
}

// Identify the owner semantics used to coalesce adjacent tool contacts.
Dust_Tool_Contact_Source :: enum u8 {
    Point,
    Compass_Filled_Sweep,
    Scenario,
    Label,
}

// Describe one ordered point push or compound filled-compass sweep.
Dust_Tool_Contact :: struct {
    endpoint: geometry.Vector3,
    previous_segment_first: geometry.Vector3,
    previous_segment_second: geometry.Vector3,
    segment_first: geometry.Vector3,
    segment_second: geometry.Vector3,
    max_spawn_sequence: u64,
    has_sweep: bool,
    source: Dust_Tool_Contact_Source,
}

// Copy one revealed floor polygon outline for the worker to clear its ground dust.
Dust_Region_Push :: struct {
    vertices: [DUST_REGION_PUSH_VERTEX_CAP]geometry.Vector2,
    vertex_count: int,
}

// Store one particle's simulation and rendering state.
Particle :: struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    vel_x: f32,
    vel_y: f32,
    vel_z: f32,

    age: f32,
    life: f32,
    size: f32,
    color: color.Color_RGBA8,
    dust_sprite_index: u8,
    alive: bool,
}

// Select how one tool-trail particle moves over its simulated life.
Trail_Particle_Role :: enum u8 {
    // Drop a short way onto the stroke, then shrink and fade where it landed.
    Pigment,
    // Start small and white, hop off the stroke, and cool to the stroke color.
    Leaper,
}

// Store one tool-trail particle. Its look is a pure function of age over life:
// ground is where it settles, offset is its sideways reach, height its lift, and hot
// the white a pigment starts with before cooling to its color.
Trail_Particle :: struct {
    ground_x, ground_y, ground_z: f32,
    offset_x, offset_y, height: f32,
    age, life, size, hot: f32,
    role: Trail_Particle_Role,
    hops: u8,
    color: color.Color_RGBA8,
    alive: bool,
}

// Describe one trail particle's resolved world position, tint, and screen diameter.
Trail_Particle_Visual :: struct {
    position: geometry.Vector3,
    color: color.Color_RGBA8,
    diameter: f32,
    visible: bool,
    // light is a white-hot leaper's local light strength; lift is its hop height.
    light: f32,
    lift: f32,
}

// Distinguish authored reveal target types without coupling particle storage to bridge.
Formation_Target_Kind :: enum u8 {
    Label,
    Region,
    // A filled compass sector that forms behind the swinging leg.
    Sweep,
}

// Identify one reserved formation particle slot incarnation.
Formation_Particle_Handle :: struct {
    slot: i32,
    generation: u64,
}

// Select the authored lifecycle one settling fragment follows within its reveal.
Formation_Particle_Role :: enum u8 {
    // Fade and grow in while falling, then deposit at the target.
    Pigment,
    // Hop upward as a large pale circle, then shrink into pigment on landing.
    Leaper,
}

// Store one particle that belongs only to the authored formation layer.
// Birth and flight are fractions of the owning reveal's authored duration; offsets
// and height are normalized world distances from the attached target. Label ink
// offsets are screen-facing logical pixels from the projected label anchor.
Formation_Particle :: struct {
    target_x, target_y, target_z: f32,
    offset_x, offset_y, height: f32,
    ink_x, ink_y: f32,
    birth, flight, size: f32,
    barycentric_u, barycentric_v: f32,
    triangle_offset: i32,
    role: Formation_Particle_Role,
    hops: u8,
    color: color.Color_RGBA8,
    reveal_slot: i32,
    reveal_generation: u64,
    slot_generation: u64,
    alive: bool,
}

// Track one animation-owned interval independently of ordinary particle time.
Formation_Reveal_Record :: struct {
    kind: Formation_Target_Kind,
    owner_entity: u64,
    animation_generation: u64,
    slot_generation: u64,
    start_progress: f64,
    duration: f32,
    seed: u64,
    material_count: int,
    topology_signature: u64,
    // Sweep reveals: signed sector already seeded, its latest angular speed in
    // radians per second, and the accepted progress when it last grew.
    covered_sweep, sweep_speed: f32,
    last_growth: f64,
    // Region reveals: the outline has already pushed its ground dust aside.
    dust_pushed: bool,
    active: bool,
}

// Describe one transaction-approved reveal interval before assigning a native slot.
Formation_Reveal_Request :: struct {
    kind: Formation_Target_Kind,
    owner_entity: u64,
    animation_generation: u64,
    progress: f64,
    duration: f32,
    seed: u64,
}

// Copy one shaped-glyph coverage centroid relative to its projected label anchor.
Formation_Label_Ink_Sample :: struct {
    offset: geometry.Vector2,
    coverage: u8,
}

// Describe one label's freshly copied ink and the current draw identity it belongs to.
Formation_Label_Target_Request :: struct {
    anchor: geometry.Vector3,
    color: color.Color_RGBA8,
    font_size: f32,
    signature: u64,
}

// Copy one bounded material origin and its effective alpha before owner retirement.
Departure_Material_Sample :: struct {
    position: geometry.Vector3,
    coverage: u8,
}

// Preserve one sampled rendered-triangle attachment for moving region targets.
Polygon_Material_Sample :: struct {
    position: geometry.Vector3,
    coverage: u8,
    triangle_offset: i32,
    barycentric_u, barycentric_v: f32,
}

// Describe one formation particle's resolved world position, tint, and size.
// Screen offsets are added after projection so label ink stays screen-facing.
Formation_Particle_Visual :: struct {
    position: geometry.Vector3,
    screen_offset: geometry.Vector2,
    color: color.Color_RGBA8,
    diameter: f32,
    visible: bool,
    // light is a white-hot leaper's local light strength; lift is its hop height.
    light: f32,
    lift: f32,
}

// Own one display frame's compacted visible formation visuals and back-to-front order.
// Only the display thread writes this scratch while encoding the formation pass.
Formation_Draw_Order :: struct {
    visuals: [MAX_FORMATION_PARTICLES]Formation_Particle_Visual,
    depths: [MAX_FORMATION_PARTICLES]f32,
    order: [MAX_FORMATION_PARTICLES]u16,
    buckets: [FORMATION_DEPTH_BUCKETS + 1]u32,
}

// Own bounded formation records and the dedicated, non-dust particle population.
Formation_State :: struct {
    particles: #soa[MAX_FORMATION_PARTICLES]Formation_Particle,
    draw_order: Formation_Draw_Order,
    reveals: [MAX_FORMATION_REVEALS]Formation_Reveal_Record,
    particle_count: int,
    reveal_count: int,
    next_particle_slot: int,
    next_reveal_slot: int,
    next_particle_generation: u64,
    next_reveal_generation: u64,
    animation_generation: u64,
    accepted_progress: f64,
}

// Own bounded dust, tool-trail, and formation storage and deterministic random state.
Particle_System :: struct {
    low_particles: #soa[MAX_LOW_PARTICLES]Particle,
    low_particle_screens: [MAX_LOW_PARTICLES]geometry.Vector2,
    particles: #soa[MAX_PARTICLES]Trail_Particle,
    formation: Formation_State,
    departure_capture_failures: u64,

    dust_tool_contacts: [DUST_TOOL_CONTACT_CAP]Dust_Tool_Contact,
    dust_tool_contact_count: int,
    dust_tool_contact_overflow_count: int,
    dust_tool_contact_coalesced_count: u64,
    dust_tool_contact_sample_count: u64,
    dust_tool_contact_field_node_visit_count: u64,
    dust_region_pushes: [DUST_REGION_PUSH_CAP]Dust_Region_Push,
    dust_region_push_count: int,
    dust_slot_spawn_sequences: [MAX_LOW_PARTICLES]u64,
    dust_spawn_sequence: u64,

    dust_floor_rest_count: int,

    dust_field: Dust_Field_State,
    dust_transfers: [MAX_LOW_PARTICLES]Dust_Transfer,
    dust_transfer_count: int,
    dust_grounded_count: int,
    dust_peak_speed_sq: f32,
    dust_kinetic_measure: f32,

    next_index: int,
    spawn_timer: f32,
    rng_state: rand.Xoshiro256_Random_State,

    last_render_low: int,
    last_render_mid: int,

    use_max_dust_particles: int,
}
