"""Geometry results accepted by the world-space queued transformation API."""
const TransformShape = Union{
    OdinJuliaBridge.BridgeShapeEntityResult, OdinJuliaBridge.BridgeShapeLine,
    OdinJuliaBridge.BridgeShapeTriangle, OdinJuliaBridge.BridgeShapeSquare,
    OdinJuliaBridge.BridgeShapePentagon, OdinJuliaBridge.BridgeShapeCircle,
    OdinJuliaBridge.BridgeShapeCircleRegion, OdinJuliaBridge.BridgeShapeCycloidResult,
    OdinJuliaBridge.BridgeShapeTrochoidResult, OdinJuliaBridge.BridgeShapeConicResult}

"""Identify authoritative motion targets and their native plane contract."""
struct ShapeMotionDefinition
    host::UInt64
    ids::Vector{UInt64}
    kinds::Tuple{Vararg{Int32}}
    oriented::Bool
end

"""Resolve a standalone result; native kind validation excludes labels."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeEntityResult) =
    ShapeMotionDefinition(
        shape.index, UInt64[shape.index], (OdinJuliaBridge.SHAPE_KIND_POINT,), false)

"""Resolve a line's authoritative defining endpoints."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeLine) =
    ShapeMotionDefinition(
        shape.host_id, UInt64[line_endpoint_ids(shape)...],
        (OdinJuliaBridge.SHAPE_KIND_LINE,), false)

"""Resolve a triangle's ordered vertices without introducing a second pose."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeTriangle) =
    ShapeMotionDefinition(shape.host_id, polygon_vertex_ids(shape),
        (OdinJuliaBridge.SHAPE_KIND_POLYGON,), false)

"""Resolve a square's ordered vertices without introducing a second pose."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeSquare) =
    ShapeMotionDefinition(shape.host_id, polygon_vertex_ids(shape),
        (OdinJuliaBridge.SHAPE_KIND_POLYGON,), false)

"""Resolve a pentagon's ordered vertices without introducing a second pose."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapePentagon) =
    ShapeMotionDefinition(shape.host_id, polygon_vertex_ids(shape),
        (OdinJuliaBridge.SHAPE_KIND_POLYGON,), false)

"""Resolve an arc or filled sector's center and plane orientation."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeCircle) =
    ShapeMotionDefinition(shape.host_id, UInt64[shape.host_id],
        (OdinJuliaBridge.SHAPE_KIND_ARC, OdinJuliaBridge.SHAPE_KIND_FILLED_ARC), true)

"""Resolve a region's centers and shared plane orientation."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeCircleRegion) =
    ShapeMotionDefinition(shape.host_id, UInt64[circle_region_center_ids(shape)...],
        (OdinJuliaBridge.SHAPE_KIND_CIRCLE_REGION,), true)

"""Resolve a cycloid's rail and shared plane orientation."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeCycloidResult) =
    ShapeMotionDefinition(
        shape.host_id, UInt64[shape.first_id, shape.second_id],
        (OdinJuliaBridge.SHAPE_KIND_CYCLOID,), true)

"""Resolve a trochoid's analytic host and intrinsic plane."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeTrochoidResult) =
    ShapeMotionDefinition(shape.host_id, UInt64[shape.host_id],
        (OdinJuliaBridge.SHAPE_KIND_TROCHOID,), true)

"""Resolve a parabola or hyperbola's analytic host and intrinsic plane."""
shape_motion_definition(shape::OdinJuliaBridge.BridgeShapeConicResult) =
    ShapeMotionDefinition(shape.host_id, UInt64[shape.host_id],
        (OdinJuliaBridge.SHAPE_KIND_PARABOLA, OdinJuliaBridge.SHAPE_KIND_HYPERBOLA), true)

"""Admit one copied typed-shape motion, leaving state sampling to activation."""
function queue_shape_transform!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    spec::TransformSpec, duration::Real; reflection::Bool=false)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("transformation requires a successful shape result"))
    definition = shape_motion_definition(shape)
    host, ids = definition.host, definition.ids
    session = ensure_session!(runtime)
    host in session.managed_host_ids ||
        throw(ArgumentError("transformation requires a Terminal-managed shape"))
    draw_duration = validated_duration(duration)
    require_action_capacity(session)
    if !queued_construction_target(session, host)
        validated_target(state_ptr, host).point_type in definition.kinds ||
            throw(ArgumentError("transformation target has the wrong geometry kind"))
    end
    validate_transform_targets(runtime, state_ptr, ids)
    starts = [Float32[0, 0, 0] for _ in ids]
    payload = TransformPayload(
        ids, starts, spec, host, definition.kinds, definition.oriented,
        (0f0, 0f0, 0f0, 1f0), reflection)
    start_job!(runtime, state_ptr, ReplDrawJob(:transform, draw_duration, 0f0, payload))
    return shape
end

"""
Queue world-space translation, preserving intrinsic geometry and defining identities.

The starting state is sampled after preceding queued actions finish. Displacement
uses world units and is not clamped to the board. Returns the original typed shape.
"""
function translate!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    displacement::AbstractVector{<:Real}; duration::Real=DEFAULT_TRANSFORM_DURATION)
    spec = TranslateSpec(vec3("displacement", displacement))
    return queue_shape_transform!(runtime, state_ptr, shape, spec, duration)
end

"""Copy and validate a directed world axis and authored signed angle."""
function world_rotation_spec(axis_start, axis_end, angle::Real)
    first = vec3("axis_start", axis_start)
    second = vec3("axis_end", axis_end)
    length_squared = sum((Float64(second[i]) - first[i])^2 for i in 1:3)
    length_squared > Float64(EuclidAnimations.TransformEps)^2 ||
        throw(ArgumentError("rotation axis must have distinct endpoints"))
    return RotateSpec(first, second, validated_angle_theta(angle))
end

"""
Queue right-handed rotation about the world line `axis_start` -> `axis_end`.

The signed angle is in radians, including negative and multi-turn angles. Every
frame is evaluated from activation-time state. Returns the original typed shape.
"""
function rotate!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    axis_start::AbstractVector{<:Real}, axis_end::AbstractVector{<:Real},
    angle::Real; duration::Real=DEFAULT_TRANSFORM_DURATION)
    spec = world_rotation_spec(axis_start, axis_end, angle)
    return queue_shape_transform!(runtime, state_ptr, shape, spec, duration)
end

"""Build a world-axis line through an explicit pivot without changing its inputs."""
function axis_rotation!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    angle::Real, pivot, axis::Int, duration::Real)
    first = vec3("pivot", pivot)
    second = copy(first)
    second[axis] += 1f0
    return rotate!(runtime, state_ptr, shape, first, second, angle; duration)
end

"""Queue a world-X rotation in radians through the required `pivot`."""
function rotate_x!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    angle::Real; pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    return axis_rotation!(runtime, state_ptr, shape, angle, pivot, 1, duration)
end

"""Queue a world-Y rotation in radians through the required `pivot`."""
function rotate_y!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    angle::Real; pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    return axis_rotation!(runtime, state_ptr, shape, angle, pivot, 2, duration)
end

"""Queue a world-Z rotation in radians through the required `pivot`."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    angle::Real; pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    return axis_rotation!(runtime, state_ptr, shape, angle, pivot, 3, duration)
end

"""
Queue planar reflection as one right-handed +pi turn about `line_start` -> `line_end`.

The line must lie in the target plane at activation. Swapping its endpoints reverses
the above/below-surface animation path while preserving the planar reflected endpoint.
This is not a general 3D mirror-plane operation. Returns the original typed shape.
"""
function reflect!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, shape::TransformShape,
    line_start::AbstractVector{<:Real}, line_end::AbstractVector{<:Real};
    duration::Real=DEFAULT_TRANSFORM_DURATION)
    spec = world_rotation_spec(line_start, line_end, Float32(pi))
    return queue_shape_transform!(
        runtime, state_ptr, shape, spec, duration; reflection=true)
end

"""Subtract inline world vectors."""
motion_difference(a, b) = ntuple(i -> a[i] - b[i], 3)

"""Compute an inline world-vector dot product."""
motion_dot(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

"""Compute an inline right-handed world-vector cross product."""
motion_cross(a, b) = ntuple(i ->
    a[mod1(i + 1, 3)] * b[mod1(i + 2, 3)] -
    a[mod1(i + 2, 3)] * b[mod1(i + 1, 3)], 3)

"""Construct a unit XYZW quaternion without losing the authored rotation path."""
function motion_rotation(spec::RotateSpec, progress::Float32)
    axis = ntuple(i -> Float64(spec.axis_b[i]) - spec.axis_a[i], 3)
    inverse_length = inv(sqrt(motion_dot(axis, axis)))
    sine, cosine = sincos(spec.theta * progress * 0.5f0)
    return ntuple(i -> i == 4 ? cosine :
        Float32(axis[i] * inverse_length) * sine, 4)
end

"""Compose local-to-world XYZW orientations with the world rotation on the left."""
function motion_compose(a::NTuple{4,Float32}, b::NTuple{4,Float32})
    result = (
        a[4]*b[1] + a[1]*b[4] + a[2]*b[3] - a[3]*b[2],
        a[4]*b[2] - a[1]*b[3] + a[2]*b[4] + a[3]*b[1],
        a[4]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[4],
        a[4]*b[4] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3])
    inverse_length = inv(sqrt(sum(abs2, result)))
    return map(value -> value * inverse_length, result)
end

"""Rotate an inline vector by a normalized XYZW quaternion."""
function motion_rotate(q::NTuple{4,Float32}, vector)
    first = motion_cross(q, vector)
    second = motion_cross(q, first)
    return ntuple(i -> vector[i] + 2f0 * (q[4] * first[i] + second[i]), 3)
end

"""Reject reflection axes that do not lie in the target's activation-time plane."""
function validate_reflection_plane(payload::TransformPayload)
    spec = payload.spec
    spec isa RotateSpec || error("reflection requires a directed rotation")
    axis = motion_difference(spec.axis_b, spec.axis_a)
    normal = payload.oriented ?
        motion_rotate(payload.start_orientation, (0f0, 0f0, 1f0)) :
        reflection_point_normal(payload.start_positions, spec.axis_a, axis)
    normal_length = sqrt(motion_dot(normal, normal))
    normal_length <= EuclidAnimations.TransformEps && return nothing
    tolerance = 1f-5 * normal_length
    abs(motion_dot(normal, axis)) <= tolerance * sqrt(motion_dot(axis, axis)) ||
        throw(ArgumentError("reflection line must lie in the target plane"))
    for point in payload.start_positions
        delta = motion_difference(point, spec.axis_a)
        abs(motion_dot(normal, delta)) <=
            tolerance * max(1f0, sqrt(motion_dot(delta, delta))) ||
            throw(ArgumentError("reflection requires a coplanar target and line"))
    end
    return nothing
end

"""Find a plane containing a directed reflection line and the defining points."""
function reflection_point_normal(points, origin, axis)
    normal = (0f0, 0f0, 0f0)
    for point in points
        normal = motion_cross(axis, motion_difference(point, origin))
        motion_dot(normal, normal) > EuclidAnimations.TransformEps^2 && break
    end
    return normal
end

"""Translate an activation-sampled position in inline world coordinates."""
motion_position(spec::TranslateSpec, start, progress, _rotation) =
    ntuple(i -> start[i] + spec.displacement[i] * progress, 3)

"""Rotate an activation-sampled position around its directed world axis."""
function motion_position(spec::RotateSpec, start, _progress, rotation)
    relative = motion_rotate(rotation, motion_difference(start, spec.axis_a))
    return ntuple(i -> spec.axis_a[i] + relative[i], 3)
end

"""Capture one coherent position/orientation update from activation-time state."""
function render_rigid_transform!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::TransformPayload,
    spec::Union{TranslateSpec,RotateSpec})
    progress = clamp(Float32(elapsed / duration), 0f0, 1f0)
    rotation = spec isa RotateSpec ? motion_rotation(spec, progress) :
        (0f0, 0f0, 0f0, 1f0)
    for (index, id) in pairs(payload.point_ids)
        point = motion_position(spec, payload.start_positions[index], progress, rotation)
        checked_terminal_status(
            OdinJuliaBridge.set_point_position_status(state_ptr, id, point),
            "shape defining-point motion")
    end
    if payload.oriented && spec isa RotateSpec
        orientation = motion_compose(rotation, payload.start_orientation)
        checked_terminal_status(OdinJuliaBridge.set_shape_orientation(
            state_ptr, payload.host_id, orientation), "shape plane rotation")
    end
    return nothing
end
