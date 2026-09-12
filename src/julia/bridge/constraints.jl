"""Create one direct-target floor constraint."""
function create_floor_constraint(state_ptr::Ptr{Cvoid}, point::Integer,
    height::Real=0, bounce::Real=0; enabled::Bool=true)
    @ccall create_floor_constraint(state_ptr::Ptr{Cvoid}, UInt64(point)::UInt64,
        Cfloat(height)::Cfloat, Cfloat(bounce)::Cfloat,
        UInt8(enabled)::UInt8)::Int32
end

"""Create one direct-target snap-to-floor constraint."""
function create_snap_to_floor_constraint(state_ptr::Ptr{Cvoid}, point::Integer,
    height::Real=0, allowance::Real=0; enabled::Bool=true)
    @ccall create_snap_to_floor_constraint(state_ptr::Ptr{Cvoid},
        UInt64(point)::UInt64, Cfloat(height)::Cfloat, Cfloat(allowance)::Cfloat,
        UInt8(enabled)::UInt8)::Int32
end

"""Create one direct-target snap-point constraint."""
function create_snap_point_constraint(state_ptr::Ptr{Cvoid}, point::Integer,
    position; enabled::Bool=true)
    target = (Cfloat(position[1]), Cfloat(position[2]), Cfloat(position[3]))
    @ccall create_snap_point_constraint(state_ptr::Ptr{Cvoid},
        UInt64(point)::UInt64, target::NTuple{3, Cfloat},
        UInt8(enabled)::UInt8)::Int32
end

"""Create one direct-target distance constraint."""
function create_distance_constraint(state_ptr::Ptr{Cvoid}, first::Integer,
    second::Integer, length::Real, movement::Integer; enabled::Bool=true)
    input = BridgeDistanceConstraintInput(UInt64(first), UInt64(second),
        Cfloat(length), Int32(movement), UInt8(enabled))
    @ccall create_distance_constraint(state_ptr::Ptr{Cvoid},
        input::BridgeDistanceConstraintInput)::Int32
end

"""Create one direct-target maximum-angle constraint."""
function create_max_angle_constraint(state_ptr::Ptr{Cvoid}, first::Integer,
    pivot::Integer, second::Integer, limit::Real, movement::Integer;
    enabled::Bool=true)
    input = BridgeAngleConstraintInput(UInt64(first), UInt64(pivot), UInt64(second),
        Cfloat(limit), Int32(movement), UInt8(enabled))
    @ccall create_max_angle_constraint(state_ptr::Ptr{Cvoid},
        input::BridgeAngleConstraintInput)::Int32
end

"""Create one direct-target minimum-angle constraint."""
function create_min_angle_constraint(state_ptr::Ptr{Cvoid}, first::Integer,
    pivot::Integer, second::Integer, limit::Real, movement::Integer;
    enabled::Bool=true)
    input = BridgeAngleConstraintInput(UInt64(first), UInt64(pivot), UInt64(second),
        Cfloat(limit), Int32(movement), UInt8(enabled))
    @ccall create_min_angle_constraint(state_ptr::Ptr{Cvoid},
        input::BridgeAngleConstraintInput)::Int32
end

"""Create one direct-target center-pivot constraint."""
function create_center_pivot_constraint(state_ptr::Ptr{Cvoid}, first::Integer,
    pivot::Integer, second::Integer; enabled::Bool=true)
    @ccall create_center_pivot_constraint(state_ptr::Ptr{Cvoid},
        UInt64(first)::UInt64, UInt64(pivot)::UInt64, UInt64(second)::UInt64,
        UInt8(enabled)::UInt8)::Int32
end

"""Return aggregate error across canonical direct-target constraints."""
function get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})
    @ccall get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})::Cfloat
end

"""Apply every canonical direct-target constraint once."""
function apply_all_constraints_bridge(state_ptr::Ptr{Cvoid}, reverse::Bool=false)
    @ccall apply_all_constraints_bridge(
        state_ptr::Ptr{Cvoid}, UInt8(reverse)::UInt8)::Int32
end

"""Solve canonical direct-target constraints within an iteration budget."""
function solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowable_error::Real,
    max_iterations::Integer)
    @ccall solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowable_error::Cfloat,
        Int32(max_iterations)::Int32)::BridgeSolveResult
end
