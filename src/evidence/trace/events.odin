package evidence_trace

// Package evidence_trace defines allocation-free semantic evidence shared by runtime owners.
// It owns no application state and imports no runtime subsystem.

// Version of the serialized event vocabulary and field interpretation.
TRACE_SCHEMA_VERSION :: u16(1)

// Required in-memory and serialized width of every pointer-free event record.
TRACE_EVENT_SIZE_BYTES :: 64

// Runtime owner that emitted one event in owner-local order.
//
// Values are serialized. Existing numeric assignments must not be reused or changed
// without advancing the trace schema version.
Producer :: enum u8 {
    Unknown = 0,
    Display = 1,
    Julia_Host = 2,
    Animation = 3,
    Simulation = 4,
    Constraint_Worker = 5,
    Particle_Worker = 6,
    Frame_Preparation = 7,
    Scenario = 8,
    Shape_Cache_Worker = 9,
    Dynview_Worker = 10,
}

// Evidence class used to filter events without interpreting subsystem payloads.
//
// A lane describes why an event exists; Kind identifies the concrete occurrence.
Lane :: enum u8 {
    Unknown = 0,
    Lifecycle = 1,
    Domain = 2,
    Transport = 3,
    Presentation = 4,
    Scenario = 5,
    Diagnostic = 6,
}

// Existing identity domain reused by one event correlation and generation pair.
//
// None means the event has no correlatable runtime identity. The remaining values
// distinguish otherwise equal numeric IDs issued by independent subsystems.
Correlation_Kind :: enum u8 {
    None = 0,
    Runtime_Request = 1,
    Animation = 2,
    Animation_Tick = 3,
    Scene_Batch = 4,
    Fixed_Step = 5,
    Task = 6,
    Capture = 7,
    Checkpoint = 8,
    Scenario_Action = 9,
    Text = 10,
}

// Stable semantic occurrence identifiers serialized by schema version.
//
// Numeric ranges are intentionally grouped by subsystem. Existing values remain stable;
// new kinds append within a suitable unused range or require a schema migration.
Kind :: enum u16 {
    // Unknown or forward-incompatible occurrence.
    Unknown = 0,

    // Evidence session lifecycle and recorder health (1-19).
    Session_Started = 1,
    Session_Configured = 2,
    Session_Finished = 3,
    Trace_Gap = 4,

    // Runtime lifecycle (20-59).
    Runtime_Starting = 20,
    Runtime_Ready = 21,
    Runtime_Reload_Started = 22,
    Runtime_Reload_Committed = 23,
    Runtime_Reload_Rolled_Back = 24,
    Runtime_Shutdown_Started = 25,
    Runtime_Shutdown_Complete = 26,

    // Animation lifecycle (60-119).
    Animation_Reset_Requested = 60,
    Animation_Reset_Committed = 61,
    Animation_Selected = 62,
    Animation_Tick_Accepted = 63,
    Animation_Tick_Committed = 64,
    Animation_Tick_Rejected = 65,
    Animation_Cycle_Boundary = 66,

    // Scene transport (120-179).
    Scene_Batch_Published = 120,
    Scene_Batch_Committed = 121,
    Scene_Batch_Rejected = 122,
    Scene_Command_Rejected = 123,

    // Geometry (180-259).
    Point_Position_Committed = 180,
    Point_Style_Committed = 181,
    Point_Visibility_Committed = 182,
    Constraint_Solve_Completed = 183,
    Constraint_Solve_Failed = 184,

    // Drawing tools (260-319).
    Pen_Joint_Committed = 260,
    Pen_Active_Committed = 261,
    Pen_Visibility_Committed = 262,
    Compass_Joint_Committed = 263,
    Compass_Active_Committed = 264,
    Compass_Visibility_Committed = 265,

    // Particles (320-359).
    Particle_Emission_Committed = 320,
    Particle_Emission_Rejected = 321,

    // View and presentation (360-419).
    Frame_Presented = 360,
    Dynview_Published = 361,
    Capture_Requested = 362,
    Capture_Completed = 363,
    Capture_Failed = 364,
    Gif_Started = 365,
    Gif_Completed = 366,
    Gif_Failed = 367,
    Shape_Cache_Prepared = 368,
    Dynview_Compiled = 369,
    Scratchpad_Completed = 370,

    // Rich checkpoint storage (420-459).
    Checkpoint_Requested = 420,
    Checkpoint_Stored = 421,
    Checkpoint_Unavailable = 422,
    Checkpoint_Evicted = 423,

    // Scenario execution (460-519).
    Scenario_Started = 460,
    Scenario_Action_Issued = 461,
    Scenario_Wait_Satisfied = 462,
    Scenario_Assertion_Passed = 463,
    Scenario_Assertion_Failed = 464,
    Scenario_Passed = 465,
    Scenario_Failed = 466,
    Scenario_Inconclusive = 467,

    // Allocation evidence (520-559).
    Allocation_Checkpoint = 520,
    Allocation_Baseline_Matched = 521,
    Allocation_Baseline_Mismatched = 522,
    Allocation_Bad_Free = 523,
}

// Orthogonal event properties that do not change the event kind.
Flag :: enum u16 {
    // Dropping this event makes correctness evidence incomplete.
    Required,
    // Event records a rejected, failed, or otherwise adverse outcome.
    Failure,
    // Associated bounded data omitted one or more bytes or records.
    Truncated,
    // Correlation was valid structurally but no longer owned current state.
    Stale,
    // Runtime policy selected a documented fallback instead of explicit input.
    Defaulted,
}

// Compact set of independent properties attached to one event.
Flags :: bit_set[Flag; u16]

// One existing runtime identity; zero ID means no correlation is available.
Identity :: struct {
    // Namespace that defines the meaning and uniqueness scope of id.
    kind : Correlation_Kind,

    // Existing subsystem-issued identity; zero represents no concrete identity.
    id : u64,

    // Reuse generation, or zero for identity domains that are not generational.
    generation : u64,
}

// Bounded point mutation payload stored directly in an event.
Point_Payload :: struct {
    point_index: u32,
    field: u16,
    visible: u8,
    reserved: u8,
}

// Bounded request outcome payload stored directly in an event.
Request_Payload :: struct {
    status: u16,
    reason: u16,
    slot: u32,
}

// Generational bounded-store handle stored directly in an event.
Handle_Payload :: struct {
    slot: u16,
    generation: u16,
    flags: u16,
    reserved: u16,
}

// Pair of bounded counters stored directly in an event.
Count_Payload :: struct {
    first: u32,
    second: u32,
}

// Fixed payload union interpreted only according to the event kind.
Event_Payload :: struct #raw_union {
    point: Point_Payload,
    request: Request_Payload,
    handle: Handle_Payload,
    counts: Count_Payload,
}

#assert(size_of(Event_Payload) == 8)

// Fixed-size serialized semantic fact containing no pointers or owned storage.
//
// Field widths and order are part of TRACE_SCHEMA_VERSION. Producers populate only
// kind-relevant metadata and payload values; zero consistently means unavailable.
Event :: struct {
    // Producer-local ordering and optional monotonic timing metadata.
    sequence : u64,
    timestamp_ns : u64,

    // Existing runtime identity and optional reuse generation.
    correlation : u64,
    generation : u64,

    // Optional authoritative simulation position observed by the producer.
    tick : u64,
    revision : u64,

    // Event ownership, evidence class, and correlation namespace.
    producer : Producer,
    lane : Lane,
    correlation_kind : Correlation_Kind,

    // Reserved schema byte; producers write zero and readers ignore it.
    reserved : u8,

    // Semantic occurrence and independent evidence properties.
    kind : Kind,
    flags : Flags,

    // Kind-specific fixed payload selected by the event kind.
    payload : Event_Payload,
}

#assert(size_of(Event) == TRACE_EVENT_SIZE_BYTES)

//   Return the existing runtime identity carried by one event.
//
// Parameters:
//   - event: Semantic event to inspect.
//
// Returns:
//   - Correlation kind, ID, and generation without allocation.
//
// Notes:
//   - The query is pure and preserves zero values for unavailable identity metadata.
event_identity :: proc(event: Event) -> Identity {
    return {
        kind = event.correlation_kind,
        id = event.correlation,
        generation = event.generation,
    }
}

//   Test whether one event carries an exact existing runtime identity.
//
// Parameters:
//   - event: Semantic event to inspect.
//   - identity: Identity required by the query.
//
// Returns:
//   - True when kind, ID, and generation all match.
//
// Notes:
//   - Matching is exact; a zero identity is not treated as a wildcard.
event_correlates :: proc(event: Event, identity: Identity) -> bool {
    return event_identity(event) == identity
}
