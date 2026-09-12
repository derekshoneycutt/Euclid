"""
Cache addresses of Odin bridge functions exported by the Euclid executable.

A normal Julia JIT session can resolve bare `@ccall` names from the host process,
but code restored from a PackageCompiler sysimage cannot do so reliably on Windows.
Host exports remain at fixed addresses for the lifetime of the process.
"""
HOST_SYMBOL_CACHE = Dict{Symbol, Ptr{Cvoid}}()

"""
Resolve an Odin bridge function exported by the Euclid executable.

Windows sysimage code must call bridge functions through explicit pointers because
the functions belong to the host executable rather than a DLL in Julia's loader path.
Resolved addresses are cached in `HOST_SYMBOL_CACHE`.
"""
function host_symbol(name::Symbol)
    get!(HOST_SYMBOL_CACHE, name) do
        # A null module name asks Windows for the module containing the process entry
        # point: euclid.exe. This must not be replaced with a libjulia module handle.
        module_handle = Base.@ccall "kernel32".GetModuleHandleW(
            C_NULL::Ptr{UInt16})::Ptr{Cvoid}
        module_handle == C_NULL && error("could not resolve Euclid executable module")

        pointer = Base.@ccall "kernel32".GetProcAddress(
            module_handle::Ptr{Cvoid}, String(name)::Cstring)::Ptr{Cvoid}
        pointer == C_NULL && error("could not resolve Euclid host symbol: $name")
        pointer
    end
end

"""
Call an Odin bridge export using Julia's typed `@ccall` syntax.

This module-local macro intentionally shadows `Base.@ccall` for the bridge wrapper
files. On Windows it rewrites the bare function name to a pointer resolved from the
Euclid executable, allowing calls compiled into a PackageCompiler sysimage to work.
Other platforms retain Julia's normal process-wide symbol lookup behavior.
"""
macro ccall(expression)
    if !Sys.iswindows()
        return esc(:(Base.@ccall $expression))
    end

    call_expression = expression.args[1]
    function_name = call_expression.args[1]
    function_name isa Symbol || error("Euclid bridge calls require a bare host symbol")

    # Base.@ccall represents a function-pointer callee as an interpolated AST node.
    # GlobalRef keeps the resolver bound to OdinJuliaBridge when this expansion is
    # compiled into a sysimage and later restored into an embedded Julia runtime.
    rewritten_call = copy(call_expression)
    resolver = GlobalRef(@__MODULE__, :host_symbol)
    rewritten_call.args[1] = Expr(:$, :($resolver($(QuoteNode(function_name)))))
    rewritten = Expr(:(::), rewritten_call, expression.args[2])
    return esc(:(Base.@ccall $rewritten))
end

struct BridgeColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

"""
Radius and arc angle bounds for one circle shape.

Mirrors the Odin `Bridge_Arc_Geometry` ABI struct field-for-field.
"""
struct BridgeArcGeometry
    radius::Cfloat
    start_theta::Cfloat
    end_theta::Cfloat
end

"""
Four vertices for one square shape.

Mirrors the Odin `Bridge_Square_Vertices` ABI struct field-for-field.
"""
struct BridgeSquareVertices
    vertices::NTuple{4, NTuple{3, Cfloat}}
end

"""
Five vertices for one pentagon shape.

Mirrors the Odin `Bridge_Pentagon_Vertices` ABI struct field-for-field.
"""
struct BridgePentagonVertices
    vertices::NTuple{5, NTuple{3, Cfloat}}
end

"""Canonical presentation values passed to shape constructors."""
struct BridgeShapeStyle
    color::BridgeColor
    brush_size::Cfloat
end

"""Position and presentation values passed to standalone shape constructors."""
struct BridgePositionedShapeInput
    position::NTuple{3, Cfloat}
    style::BridgeShapeStyle
end

"""Direct targets and policy for one distance constraint."""
struct BridgeDistanceConstraintInput
    first::UInt64
    second::UInt64
    length::Cfloat
    movement::Int32
    enabled::UInt8
end

"""Direct targets and policy for one angle constraint."""
struct BridgeAngleConstraintInput
    first::UInt64
    pivot::UInt64
    second::UInt64
    limit::Cfloat
    movement::Int32
    enabled::UInt8
end

"""Result of constructing one standalone entity."""
struct BridgeShapeEntityResult
    status::Int32
    index::UInt64
end

"""Pointer-free component projection for one packed entity."""
struct BridgePointView
    status::Int32
    index::UInt64
    point_type::Int32
    do_draw::UInt8
    has_position::UInt8
    has_color::UInt8
    has_active_feature::UInt8
    pos::NTuple{3, Cfloat}
    color::BridgeColor
    active_color::BridgeColor
    has_active_color::UInt8
    brush_size::Cfloat
    offset::Cfloat
    active_child::UInt16
end

"""Metadata returned after copying one immutable label source."""
struct BridgeLabelCopyResult
    status::Int32
    byte_count::Int32
    mime::Int32
end

struct BridgeSolveResult
    status::Int32
    iterations::Int32
    initial_error::Cfloat
    final_error::Cfloat
    converged::UInt8
end

struct BridgeShapeLine
    status::Int32
    host_id::UInt64
    joint1_id::UInt64
    joint2_id::UInt64
end

struct BridgeShapeCircle
    status::Int32
    host_id::UInt64
    center_id::UInt64
    start_id::UInt64
    end_id::UInt64
end

const BridgeShapeFilledCircle = BridgeShapeCircle

struct BridgeShapeTriangle
    status::Int32
    host_id::UInt64
    joint1_id::UInt64
    joint2_id::UInt64
    joint3_id::UInt64
end

struct BridgeShapeSquare
    status::Int32
    host_id::UInt64
    joint1_id::UInt64
    joint2_id::UInt64
    joint3_id::UInt64
    joint4_id::UInt64
end

struct BridgeShapePentagon
    status::Int32
    host_id::UInt64
    joint1_id::UInt64
    joint2_id::UInt64
    joint3_id::UInt64
    joint4_id::UInt64
    joint5_id::UInt64
end

const BRIDGE_STATUS_OK = Int32(0)
const BRIDGE_STATUS_INVALID_INDEX = Int32(1)
const BRIDGE_STATUS_INVALID_ARGUMENT = Int32(2)
const BRIDGE_STATUS_INVALID_GRAPH = Int32(3)
const BRIDGE_STATUS_INVALID_CONSTRAINT = Int32(4)
const BRIDGE_STATUS_OUT_OF_CAPACITY = Int32(5)
const BRIDGE_STATUS_ILLEGAL_STATE = Int32(6)
const BRIDGE_STATUS_NON_CONVERGED = Int32(7)
const BRIDGE_STATUS_NOT_FOUND = Int32(8)
const BRIDGE_STATUS_SCHEMA_MISMATCH = Int32(9)

const BRIDGE_VERSION = Int32(6)
const BRIDGE_FEATURE_TYPED_ANIMATION_STATE = Int32(1 << 4)
const BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG = Int32(1 << 5)
const BRIDGE_FEATURE_MIME_PRESENTATION = Int32(1 << 6)

const ANIMATION_STABLE_ID_NAMESPACE = UUID("66f8da8f-bd5c-5f58-ae66-5cbaf6ea4d41")

"""
Derive a deterministic animation stable ID string from a semantic key.

This helper uses UUID v5 with a fixed project namespace so the same key always
produces the same identity across reloads.
"""
animation_stable_id_from_key(key::AbstractString) =
    string(uuid5(ANIMATION_STABLE_ID_NAMESPACE, String(key)))

"""
Construct a new BridgeColor from standard Julia color types

--------

Takes in a Julia color and returns `BridgeColor`
"""
function bridge_color(c::Colorant)
    rgba = RGBA(c)
    BridgeColor(
        UInt8(round(Int, rgba.r * 255.0)),
        UInt8(round(Int, rgba.g * 255.0)),
        UInt8(round(Int, rgba.b * 255.0)),
        UInt8(round(Int, rgba.alpha * 255.0)))
end

"""Return one named Julia logo color, or `nothing` for other color names."""
function julia_palette_color(name::AbstractString)
    if name == "julia_blue"
        return BridgeColor(0x40, 0x63, 0xd8, 0xff)
    elseif name == "julia_green"
        return BridgeColor(0x38, 0x98, 0x26, 0xff)
    elseif name == "julia_purple"
        return BridgeColor(0x95, 0x58, 0xb2, 0xff)
    elseif name == "julia_red"
        return BridgeColor(0xcb, 0x3c, 0x33, 0xff)
    end
    return nothing
end

function bridge_color(name::Symbol)
    text = String(name)
    palette_color = julia_palette_color(text)
    return palette_color === nothing ? bridge_color(parse(Colorant, text)) : palette_color
end
function bridge_color(name::AbstractString)
    palette_color = julia_palette_color(name)
    return palette_color === nothing ? bridge_color(parse(Colorant, name)) : palette_color
end
