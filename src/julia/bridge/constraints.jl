"""
Get the maximum number of shapes constraints supported by the bridge.

------

Returns: `Int32` constraint capacity
"""
function get_constraint_capacity()
    @ccall get_constraint_capacity()::Int32
end

"""
Get the next constraint index in the shapes constraint system.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` next constraint index
"""
function get_constraint_next_index(state_ptr::Ptr{Cvoid})
    @ccall get_constraint_next_index(state_ptr::Ptr{Cvoid})::Int32
end

"""
Check whether a constraint index is in the valid bridge range.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint index to validate

Returns: `UInt8` where non-zero means valid
"""
function is_constraint_index_in_range(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall is_constraint_index_in_range(state_ptr::Ptr{Cvoid}, index::Int32)::UInt8
end

"""
Get one constraint view by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to retrieve

Returns: `BridgeConstraintView`
"""
function get_constraint_view(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall get_constraint_view(state_ptr::Ptr{Cvoid}, index::Int32)::BridgeConstraintView
end

"""
Create a new constraint from a bridge constraint spec.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `spec` : Constraint specification payload

Returns: `(status::Int32, index::Int32)` where index is -1 on failure
"""
function create_constraint(state_ptr::Ptr{Cvoid}, spec::BridgeConstraintSpec)
    out_index = Ref{Int32}(-1)
    status = @ccall create_constraint(state_ptr::Ptr{Cvoid}, spec::BridgeConstraintSpec,
        out_index::Ref{Int32})::Int32
    return status, out_index[]
end

"""
Update selected fields on an existing constraint.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to update
- `spec_mask` : Field selection mask using `CONSTRAINT_SPEC_*` constants
- `spec` : Source values for fields selected in `spec_mask`

Returns: `Int32` status code
"""
function update_constraint(state_ptr::Ptr{Cvoid}, index::Integer,
    spec_mask::Integer, spec::BridgeConstraintSpec)
    @ccall update_constraint(state_ptr::Ptr{Cvoid}, index::Int32,
        Int32(spec_mask)::Int32, spec::BridgeConstraintSpec)::Int32
end

"""
Enable or disable a constraint by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to update
- `enabled` : `true` to apply constraint, `false` to disable

Returns: `Int32` status code
"""
function set_constraint_enabled(state_ptr::Ptr{Cvoid}, index::Integer, enabled::Bool)
    @ccall set_constraint_enabled(state_ptr::Ptr{Cvoid}, index::Int32,
        UInt8(enabled)::UInt8)::Int32
end

"""
Clear one constraint slot by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to clear

Returns: `Int32` status code
"""
function clear_constraint(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall clear_constraint(state_ptr::Ptr{Cvoid}, index::Int32)::Int32
end

"""
Get total current constraint error across the point system.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Cfloat` total error
"""
function get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})
    @ccall get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})::Cfloat
end

"""
Get the current error value for one constraint.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `constraint_index` : Constraint id to inspect

Returns: `(status::Int32, error::Cfloat)`
"""
function get_constraint_error_bridge(state_ptr::Ptr{Cvoid}, constraint_index::Integer)
    out_error = Ref{Cfloat}(0)
    status = @ccall get_constraint_error_bridge(state_ptr::Ptr{Cvoid},
        Int32(constraint_index)::Int32, out_error::Ref{Cfloat})::Int32
    return status, out_error[]
end

"""
Apply one constraint by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `constraint_index` : Constraint id to apply

Returns: `Int32` status code
"""
function apply_constraint_bridge(state_ptr::Ptr{Cvoid}, constraint_index::Integer)
    @ccall apply_constraint_bridge(
        state_ptr::Ptr{Cvoid}, Int32(constraint_index)::Int32)::Int32
end

"""
Apply all constraints once in forward or reverse order.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `reverse` : `true` to apply in reverse order, `false` for forward order

Returns: `Int32` status code
"""
function apply_all_constraints_bridge(state_ptr::Ptr{Cvoid}, reverse::Bool=false)
    @ccall apply_all_constraints_bridge(
        state_ptr::Ptr{Cvoid}, UInt8(reverse)::UInt8)::Int32
end

"""
Solve constraints until total error is below threshold or iteration budget is exhausted.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `allowable_error` : Error threshold target
- `max_iterations` : Maximum solve iterations (native side clamps and defaults)

Returns: `BridgeSolveResult`
"""
function solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowable_error::Real,
    max_iterations::Integer)
    @ccall solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowable_error::Cfloat,
        Int32(max_iterations)::Int32)::BridgeSolveResult
end
