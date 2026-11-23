package bridge_scene

import bridgemodel "../model"
import geometry "../../core/geometry"
import shapemodel "../../shapes/model"

FLOOR_CONTACT_Z_EPSILON :: 0.015

Bridge_Color :: bridgemodel.Bridge_Color
Vector3 :: geometry.Vector3

// Carry presentation values shared by shape construction exports.
Bridge_Shape_Style :: struct {
    color: Bridge_Color,
    brush_size: f32,
}

// Carry one positioned shape's construction values within the ABI parameter budget.
Bridge_Positioned_Shape_Input :: struct {
    position: geometry.Vector3,
    style: Bridge_Shape_Style,
}

// Carry direct distance-constraint targets and policy as one ABI value.
Bridge_Distance_Constraint_Input :: struct {
    first: u64,
    second: u64,
    length: f32,
    movement: i32,
    enabled: u8,
}

// Carry direct angle-constraint targets and policy as one ABI value.
Bridge_Angle_Constraint_Input :: struct {
    first: u64,
    pivot: u64,
    second: u64,
    limit: f32,
    movement: i32,
    enabled: u8,
}

// Return one packed entity identity with an explicit operation status.
Bridge_Shape_Entity_Result :: struct {
    status: i32,
    entity: u64,
}

// Return one line host and both direct endpoint identities.
Bridge_Shape_Line_Result :: struct {
    status: i32,
    shape: u64,
    first: u64,
    second: u64,
}

// Return one arc host identity.
Bridge_Shape_Arc_Result :: struct {
    status: i32,
    shape: u64,
}

// Return one circle-region host and both direct center identities.
Bridge_Shape_Circle_Region_Result :: struct {
    status: i32,
    shape: u64,
    first_center: u64,
    second_center: u64,
}

// Return one arc host and its complete mutable geometry.
Bridge_Shape_Arc_Query_Result :: struct {
    status: i32,
    shape: u64,
    arc: shapemodel.Bridge_Arc_Geometry,
}

// Return one trochoid host identity.
Bridge_Shape_Trochoid_Result :: struct {
    status: i32,
    shape: u64,
}

// Return one trochoid host and its complete mutable geometry.
Bridge_Shape_Trochoid_Query_Result :: struct {
    status: i32,
    shape: u64,
    geometry: shapemodel.Bridge_Trochoid_Geometry,
}

// Return one cycloid host and both direct endpoint identities.
Bridge_Shape_Cycloid_Result :: struct {
    status: i32,
    shape: u64,
    first: u64,
    second: u64,
}

// Return one cycloid's endpoint positions and complete mutable geometry.
Bridge_Shape_Cycloid_Query_Result :: struct {
    status: i32,
    shape: u64,
    first: geometry.Vector3,
    second: geometry.Vector3,
    geometry: shapemodel.Bridge_Cycloid_Geometry,
}

// Return one parabola host and its complete mutable geometry.
Bridge_Shape_Parabola_Result :: struct {
    status: i32,
    shape: u64,
}

// Return one parabola's complete mutable geometry.
Bridge_Shape_Parabola_Query_Result :: struct {
    status: i32,
    shape: u64,
    geometry: shapemodel.Bridge_Parabola_Geometry,
}

// Return the single host of a complete hyperbola.
Bridge_Shape_Hyperbola_Result :: struct {
    status: i32,
    shape: u64,
}

// Return one complete hyperbola's common mutable geometry.
Bridge_Shape_Hyperbola_Query_Result :: struct {
    status: i32,
    shape: u64,
    geometry: shapemodel.Bridge_Hyperbola_Geometry,
    branches: shapemodel.Hyperbola_Branches,
}

// Return one triangle host and its direct ordered vertex identities.
Bridge_Shape_Triangle_Result :: struct {
    status: i32,
    shape: u64,
    first: u64,
    second: u64,
    third: u64,
}

// Return one square host and its direct ordered vertex identities.
Bridge_Shape_Square_Result :: struct {
    status: i32,
    shape: u64,
    vertices: [4]u64,
}

// Return one pentagon host and its direct ordered vertex identities.
Bridge_Shape_Pentagon_Result :: struct {
    status: i32,
    shape: u64,
    vertices: [5]u64,
}

// Return component projections for one resolved packed entity.
Bridge_Shape_View :: struct {
    status: i32,
    entity: u64,
    kind: i32,
    visible: u8,
    has_transform: u8,
    has_style: u8,
    has_active_feature: u8,
    position: geometry.Vector3,
    color: Bridge_Color,
    active_color: Bridge_Color,
    has_active_color: u8,
    brush_size: f32,
    active_feature: u16,
}

// Return metadata from copying one immutable label source.
Bridge_Solve_Result :: struct {
    status: i32,
    iterations: i32,
    initial_error: f32,
    final_error: f32,
    converged: u8,
}
