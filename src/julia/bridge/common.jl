struct BridgeDynviewMathOp
    kind::Int32
    style_id::Int32
    child_program_id::Int32
    secondary_child_program_id::Int32
    script_style_id::Int32
    accent_style_id::Int32
    accent_mode::Int32
    radical_mode::Int32
    large_op_kind::Int32
    text_offset::Int32
    text_len::Int32
    index_text_offset::Int32
    index_text_len::Int32
    sup_text_offset::Int32
    sup_text_len::Int32
    sub_text_offset::Int32
    sub_text_len::Int32
    script_scale::Float32
    script_sup_raise::Float32
    script_sub_drop::Float32
    script_gap::Float32
    accent_thickness::Float32
    accent_offset::Float32
end

struct BridgeColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

struct BridgePointView
    valid::UInt8
    index::Int64

    pointType::Int64
    doDraw::UInt8
    brushSize::Cfloat
    offset::Cfloat

    hasPosition::UInt8
    pos::NTuple{3, Cfloat}

    hasColor::UInt8
    color::BridgeColor

    hasActiveColor::UInt8
    activeColor::BridgeColor

    hasLabel::UInt8
    label::UInt32
    decorationKind::Int32

    activeChild::Int64
    childCount::Int64
    childPointHead::Int64
    nextChildPoint::Int64
end

struct BridgeConstraintView
    valid::UInt8
    index::Int32

    traits::Int32
    onPoint::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    dependOn::Int32
    hasChildOffset::UInt8
    childOffset::Int32
    doApply::UInt8
end

struct BridgeConstraintSpec
    traits::Int32
    onPoint::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    dependOn::Int32
    hasChildOffset::UInt8
    childOffset::Int32
    doApply::UInt8
end

struct BridgeSolveResult
    status::Int32
    iterations::Int32
    initialError::Cfloat
    finalError::Cfloat
    converged::UInt8
end

struct BridgeShapeLine
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
end

struct BridgeShapeCircle
    hostId::Int64
    startId::Int64
    endId::Int64
end

struct BridgeShapeFilledCircle
    hostId::Int64
    startId::Int64
    endId::Int64
end

struct BridgeShapeTriangle
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
    joint3Id::Int64
end

struct BridgeShapeSquare
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
    joint3Id::Int64
    joint4Id::Int64
end

struct BridgeShapePentagon
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
    joint3Id::Int64
    joint4Id::Int64
    joint5Id::Int64
end

struct BridgeShapePen
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64

    lengthConstraintId::Int64
    point1FloorId::Int64
    point2FloorId::Int64
    lockPoint1Id::Int64
    lockPoint2Id::Int64
end

struct BridgeShapeCompass
    hostId::Int64
    joint1Id::Int64
    pivotId::Int64
    joint2Id::Int64

    centerPivotId::Int64
    limb1LengthId::Int64
    limb2LengthId::Int64
    point1FloorId::Int64
    pivotFloorId::Int64
    point2FloorId::Int64
    lockPoint1Id::Int64
    lockPoint2Id::Int64
end

const LABEL_DECORATION_NONE = Int32(0)
const LABEL_DECORATION_PRIME = Int32(1)
const LABEL_DECORATION_DOUBLEPRIME = Int32(2)
const LABEL_DECORATION_TRIPLEPRIME = Int32(3)
const LABEL_DECORATION_HAT = Int32(4)
const LABEL_DECORATION_BAR = Int32(5)

const BRIDGE_STATUS_OK = Int32(0)
const BRIDGE_STATUS_INVALID_INDEX = Int32(1)
const BRIDGE_STATUS_INVALID_ARGUMENT = Int32(2)
const BRIDGE_STATUS_INVALID_GRAPH = Int32(3)
const BRIDGE_STATUS_INVALID_CONSTRAINT = Int32(4)
const BRIDGE_STATUS_OUT_OF_CAPACITY = Int32(5)
const BRIDGE_STATUS_ILLEGAL_STATE = Int32(6)
const BRIDGE_STATUS_NON_CONVERGED = Int32(7)

const BRIDGE_DYNVIEW_BLOCK_INPUT = Int32(1)
const BRIDGE_DYNVIEW_BLOCK_OUTPUT = Int32(2)
const BRIDGE_DYNVIEW_STYLE_DEFAULT = Int32(0)
const BRIDGE_DYNVIEW_STYLE_PROMPT = Int32(1)
const BRIDGE_DYNVIEW_STYLE_OUTPUT = Int32(2)
const BRIDGE_DYNVIEW_STYLE_ERROR = Int32(3)
const BRIDGE_DYNVIEW_STYLE_BOLD = Int32(10)
const BRIDGE_DYNVIEW_STYLE_ITALIC = Int32(11)
const BRIDGE_DYNVIEW_STYLE_CENTER = Int32(12)
const BRIDGE_DYNVIEW_STYLE_MEDIUM = Int32(13)
const BRIDGE_DYNVIEW_STYLE_SEMIBOLD = Int32(14)
const BRIDGE_DYNVIEW_STYLE_EXTRABOLD = Int32(15)
const BRIDGE_DYNVIEW_STYLE_BLACK = Int32(16)
const BRIDGE_DYNVIEW_STYLE_INLINE_ATOM = Int32(20)
const BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT = Int32(1 << 24)
const BRIDGE_DYNVIEW_ACCENT_MODE_OVERLINE = Int32(1)
const BRIDGE_DYNVIEW_ACCENT_MODE_UNDERLINE = Int32(2)
const BRIDGE_DYNVIEW_RADICAL_MODE_SQRT = Int32(1)
const BRIDGE_DYNVIEW_RADICAL_MODE_NTHROOT = Int32(2)
const BRIDGE_DYNVIEW_LARGE_OP_KIND_SUM = Int32(1)
const BRIDGE_DYNVIEW_LARGE_OP_KIND_PROD = Int32(2)
const BRIDGE_DYNVIEW_LARGE_OP_KIND_INT = Int32(3)
const BRIDGE_DYNVIEW_LARGE_OP_KIND_LIM = Int32(4)
const BRIDGE_DYNVIEW_DELIMITER_KIND_NONE = Int32(0)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_PAREN = Int32(1)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_PAREN = Int32(2)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACKET = Int32(3)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACKET = Int32(4)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACE = Int32(5)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACE = Int32(6)
const BRIDGE_DYNVIEW_DELIMITER_KIND_VERT = Int32(7)
const BRIDGE_DYNVIEW_DELIMITER_KIND_DOUBLE_VERT = Int32(8)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_CEIL = Int32(9)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_CEIL = Int32(10)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_FLOOR = Int32(11)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_FLOOR = Int32(12)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_ANGLE = Int32(13)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_ANGLE = Int32(14)

const BRIDGE_DYNVIEW_FONT_FLAG_NONE = Int32(0)
const BRIDGE_DYNVIEW_FONT_FLAG_ITALIC = Int32(1 << 0)
const BRIDGE_DYNVIEW_FONT_FLAG_LIGHT = Int32(1 << 1)
const BRIDGE_DYNVIEW_FONT_FLAG_REGULAR = Int32(1 << 2)
const BRIDGE_DYNVIEW_FONT_FLAG_MEDIUM = Int32(1 << 3)
const BRIDGE_DYNVIEW_FONT_FLAG_SEMIBOLD = Int32(1 << 4)
const BRIDGE_DYNVIEW_FONT_FLAG_BOLD = Int32(1 << 5)
const BRIDGE_DYNVIEW_FONT_FLAG_EXTRABOLD = Int32(1 << 6)
const BRIDGE_DYNVIEW_FONT_FLAG_BLACK = Int32(1 << 7)

const CONSTRAINT_SPEC_TRAITS = Int32(1 << 0)
const CONSTRAINT_SPEC_ONPOINT = Int32(1 << 1)
const CONSTRAINT_SPEC_RESTRICTION = Int32(1 << 2)
const CONSTRAINT_SPEC_BOUNCE = Int32(1 << 3)
const CONSTRAINT_SPEC_ALLOWANCE = Int32(1 << 4)
const CONSTRAINT_SPEC_DEPENDON = Int32(1 << 5)
const CONSTRAINT_SPEC_CHILDOFFSET = Int32(1 << 6)
const CONSTRAINT_SPEC_DOAPPLY = Int32(1 << 7)

const ANIMATION_STABLE_ID_NAMESPACE = UUID("66f8da8f-bd5c-5f58-ae66-5cbaf6ea4d41")

"""
Build a dynview style id that carries explicit JuliaMono font variant flags.

Combine one or more `BRIDGE_DYNVIEW_FONT_FLAG_*` bits (including `ITALIC`) and
pass the resulting style id into `dynview_text_run`/`dynview_math_glyph_run`.
"""
dynview_style_with_font_flags(flags::Integer) =
    Int32(BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT | Int32(flags))

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
function bridge_color(name::Symbol)
    bridge_color(parse(Colorant, String(name)))
end
function bridge_color(name::AbstractString)
    bridge_color(parse(Colorant, name))
end
