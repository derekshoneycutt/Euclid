package julia_host

import shapemodel "../../shapes/model"
import operations "../../animation/operations"

// Julia module provides the Odin-Julia Bridge to coordinate all actions between the 2
// languages. Most of these are wrappers around Odin module functions with some specific
// behavior for simplicity on the animation.
// Otherwise, the rest of Julia module is the Julia code.

// We provide a basic Bridge version and feature flags capability for building onto.
// Effort was made to wrap most of what the animations might need for now in the Shapes
// system especially, and also some access to particle system.
// Doc comments are verbose in the julia companion to this, and methods are largely 1-to-1.

// Importantly, the catalogue of animations is stored as Julia Animation Interfaces in
// the Julia Interface. There is really not enough to justify separating them out, although
// it can feel a little tight here. Ultimately, the Julia is more in control of the catalogue,
// though it is stored and chosen from via the Odin.


MAX_SHAPESPOINTS :: shapemodel.MAX_SHAPESPOINTS
MAX_SHAPESCONSTRAINTS :: shapemodel.MAX_SHAPESCONSTRAINTS

ANIMATION_RESET_MIN_INTERVAL :: 0.35

BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY :: (1 << 1)
BRIDGE_FEATURE_ANIMATION_STABLE_ID :: (1 << 3)
BRIDGE_FEATURE_TYPED_ANIMATION_STATE :: (1 << 4)
BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG :: (1 << 5)
BRIDGE_FEATURE_MIME_PRESENTATION :: (1 << 6)
BRIDGE_FEATURE_TROCHOIDS :: (1 << 7)
BRIDGE_FEATURE_CYCLOIDS :: (1 << 8)
BRIDGE_FEATURE_CIRCLE_REGIONS :: (1 << 9)
BRIDGE_FEATURE_ANIMATION_CONTENT_SPECIFICATION :: (1 << 10)
BRIDGE_FEATURE_SETTLING_FORMATION :: (1 << 11)
BRIDGE_FEATURE_CONICS :: (1 << 12)
BRIDGE_FEATURE_NATIVE_MODIFIERS :: (1 << 13)
BRIDGE_FEATURE_ACTIVE_OPERATIONS :: (1 << 14)
BRIDGE_FEATURE_ACTIVE_GROUP_TRANSFORMS :: (1 << 15)
BRIDGE_FEATURE_ACTIVE_POLYGON_TRACES :: (1 << 16)
BRIDGE_FEATURE_NATIVE_ROLLING_OPERATIONS :: (1 << 17)
BRIDGE_FEATURE_NATIVE_CONIC_OPERATIONS :: (1 << 18)
NATIVE_ACTIVE_POLYGON_TRACE_KIND :: 53
NATIVE_MODIFIER_CYCLOID_SEQUENCE_KIND :: 54
NATIVE_MODIFIER_TROCHOID_SEQUENCE_KIND :: 55
NATIVE_MODIFIER_PARABOLA_SEQUENCE_KIND :: 56
NATIVE_MODIFIER_HYPERBOLA_SEQUENCE_KIND :: 57

BRIDGE_VERSION :: 21
BRIDGE_FEATURE_FLAGS :: 1 |
    BRIDGE_FEATURE_ANIMATION_CYCLE_BOUNDARY |
    BRIDGE_FEATURE_ANIMATION_STABLE_ID |
    BRIDGE_FEATURE_TYPED_ANIMATION_STATE |
    BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG |
    BRIDGE_FEATURE_MIME_PRESENTATION |
    BRIDGE_FEATURE_TROCHOIDS |
    BRIDGE_FEATURE_CYCLOIDS |
    BRIDGE_FEATURE_CIRCLE_REGIONS |
    BRIDGE_FEATURE_ANIMATION_CONTENT_SPECIFICATION |
    BRIDGE_FEATURE_SETTLING_FORMATION |
    BRIDGE_FEATURE_CONICS |
    BRIDGE_FEATURE_NATIVE_MODIFIERS |
    BRIDGE_FEATURE_ACTIVE_OPERATIONS |
    BRIDGE_FEATURE_ACTIVE_GROUP_TRANSFORMS |
    BRIDGE_FEATURE_ACTIVE_POLYGON_TRACES |
    BRIDGE_FEATURE_NATIVE_ROLLING_OPERATIONS |
    BRIDGE_FEATURE_NATIVE_CONIC_OPERATIONS

Bridge_Native_Modifier_Request :: struct {
    kind: i32,
    entity: u64,
    second_entity: u64,
    third_entity: u64,
    elapsed: f32,
    duration: f32,
    start: [3]f32,
    second: [3]f32,
    third: [3]f32,
    displacement: [3]f32,
    axis_a: [3]f32,
    axis_b: [3]f32,
    angle: f32,
    radius: f32,
    brush: f32,
    color_packed: u32,
    scalar: f32,
    integer: i32,
    flag: u8,
}

#assert(size_of(Bridge_Native_Modifier_Request) == 144)

Bridge_Active_Group_Transform_Target :: struct {
    entity: u64,
    start: [3]f32,
}


REQUESTS_TARGETS_CAPACITY :: operations.ACTIVE_OPERATION_GROUP_TARGET_CAPACITY

Bridge_Active_Group_Transform_Request :: struct {
    modifier: Bridge_Native_Modifier_Request,
    target_count: i32,
    targets: [REQUESTS_TARGETS_CAPACITY]Bridge_Active_Group_Transform_Target,
    orientation_entity: u64,
    orientation: [4]f32,
    oriented: u8,
}

#assert(size_of(Bridge_Active_Group_Transform_Target) == 24)
#assert(size_of(Bridge_Active_Group_Transform_Request) == 568)

Bridge_Active_Polygon_Trace_Target :: struct {
    entity: u64,
    start: [3]f32,
}

ACTIVE_POLYGON_TRACE_VERTEX_CAPACITY ::
    operations.ACTIVE_OPERATION_POLYGON_TRACE_VERTEX_CAPACITY

Bridge_Active_Polygon_Trace_Request :: struct {
    modifier: Bridge_Native_Modifier_Request,
    vertex_count: i32,
    vertices: [ACTIVE_POLYGON_TRACE_VERTEX_CAPACITY]Bridge_Active_Polygon_Trace_Target,
}

#assert(size_of(Bridge_Active_Polygon_Trace_Target) == 24)
#assert(size_of(Bridge_Active_Polygon_Trace_Request) == 272)
