module AnimationCatalog

using UUIDs

export AnimationDescriptor, AnimationImplementation,
    AnimationNodeKind, AnimationNode, TerminalNode, BuilderNode,
    animation, ensure_animation_loaded, validate_catalog

@enum AnimationNodeKind::UInt8 begin
    AnimationNode = 1
    TerminalNode = 2
    BuilderNode = 3
end

"""Immutable metadata for one animation tree node."""
struct AnimationDescriptor
    id::UUID
    parent_id::Union{UUID,Nothing}
    display_name::String
    sibling_order::Int
    kind::AnimationNodeKind
    implementation_path::Union{String,Nothing}
end

"""Validated result returned by one path-backed animation program."""
struct AnimationImplementation
    id::UUID
    entry::Function
end

"""Construct a validated animation implementation result."""
function animation(id::UUID, entry::Function)
    return AnimationImplementation(id, entry)
end

"""Return whether a relative implementation path remains inside the source root."""
function _implementation_path_is_safe(path::String)
    isempty(path) && return false
    isabspath(path) && return false
    occursin('\\', path) && return false
    components = split(path, '/')
    any(component -> isempty(component) || component == "." || component == "..",
        components) && return false
    return replace(normpath(path), '\\' => '/') == path
end

"""Validate and index one descriptor before hierarchy validation."""
function _validate_catalog_descriptor!(
    descriptor::AnimationDescriptor,
    by_id::Dict{UUID,AnimationDescriptor},
    sibling_orders::Set{Tuple{Union{UUID,Nothing},Int}})
    _validate_catalog_descriptor_identity!(descriptor, by_id, sibling_orders)
    if descriptor.kind == TerminalNode || descriptor.kind == BuilderNode
        _validate_native_catalog_descriptor!(descriptor)
    else
        path = descriptor.implementation_path
        path isa String && _implementation_path_is_safe(path) ||
            throw(ArgumentError("animation implementation path is unsafe"))
    end
    by_id[descriptor.id] = descriptor
    return nothing
end

"""Validate unique identity, display name, and sibling order."""
function _validate_catalog_descriptor_identity!(
    descriptor::AnimationDescriptor,
    by_id::Dict{UUID,AnimationDescriptor},
    sibling_orders::Set{Tuple{Union{UUID,Nothing},Int}})
    descriptor.id == UUID(UInt128(0)) &&
        throw(ArgumentError("animation id must be nonzero"))
    haskey(by_id, descriptor.id) &&
        throw(ArgumentError("duplicate animation id: $(descriptor.id)"))
    isempty(descriptor.display_name) &&
        throw(ArgumentError("animation display name must not be empty"))
    descriptor.sibling_order < 0 &&
        throw(ArgumentError("animation sibling order must be nonnegative"))
    order_key = (descriptor.parent_id, descriptor.sibling_order)
    order_key in sibling_orders && throw(ArgumentError("duplicate sibling order"))
    push!(sibling_orders, order_key)
    return nothing
end

"""Require native descriptors to be root nodes without implementation paths."""
function _validate_native_catalog_descriptor!(descriptor::AnimationDescriptor)
    descriptor.parent_id === nothing ||
        throw(ArgumentError("native catalogue node must be a root"))
    descriptor.implementation_path === nothing ||
        throw(ArgumentError(
            "native catalogue node must not have an implementation path"))
    return nothing
end

"""Validate the complete catalog before constructing any host metadata."""
function validate_catalog(descriptors::Vector{AnimationDescriptor})
    isempty(descriptors) && throw(ArgumentError("animation catalog must not be empty"))
    by_id = Dict{UUID,AnimationDescriptor}()
    sibling_orders = Set{Tuple{Union{UUID,Nothing},Int}}()
    for descriptor in descriptors
        _validate_catalog_descriptor!(descriptor, by_id, sibling_orders)
    end
    _validate_catalog_hierarchy(by_id)
    return by_id
end

"""Reject missing parents, self-parenting, and hierarchy cycles."""
function _validate_catalog_hierarchy(by_id::Dict{UUID,AnimationDescriptor})
    for descriptor in values(by_id)
        parent_id = descriptor.parent_id
        parent_id === nothing && continue
        haskey(by_id, parent_id) || throw(ArgumentError("animation parent is missing"))
        parent_id == descriptor.id && throw(ArgumentError("animation cannot parent itself"))
        seen = Set{UUID}([descriptor.id])
        current = parent_id
        while current !== nothing
            current in seen && throw(ArgumentError("animation hierarchy contains a cycle"))
            push!(seen, current)
            current = by_id[current].parent_id
        end
    end
end

"""Evaluate and validate one animation program in a named module owner."""
function _load_animation(
    source_root::AbstractString, descriptors::Vector{AnimationDescriptor},
    owner::Module, id::UUID)

    root = abspath(String(source_root))
    isdir(root) || throw(ArgumentError("animation source root is not a directory"))
    descriptor = findfirst(candidate -> candidate.id == id, descriptors)
    descriptor = descriptor === nothing ? nothing : descriptors[descriptor]
    descriptor === nothing && throw(KeyError(id))
    path = descriptor.implementation_path
    path isa String || throw(ArgumentError("animation has no loadable implementation"))
    _implementation_path_is_safe(path) ||
        throw(ArgumentError("animation implementation path is unsafe"))
    result = Base.include(owner, joinpath(root, path))
    result isa AnimationImplementation ||
        throw(ArgumentError("animation program returned an invalid result"))
    result.id == id || throw(ArgumentError("animation implementation id mismatch"))
    return result
end

"""Load one animation from an explicit catalog for contract tests."""
function ensure_animation_loaded(
    source_root::AbstractString, descriptors::Vector{AnimationDescriptor},
    id::UUID; owner::Module=Main)

    validate_catalog(descriptors)
    return _load_animation(source_root, descriptors, owner, id)
end

end
