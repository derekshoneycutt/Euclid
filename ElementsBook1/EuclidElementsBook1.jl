
# ==============================================
#               Definitions
# ==============================================

# Definition 1 and its highlighting axiom
include("Definitions/src/001-Point.jl")
include("AddedAxioms/src/001-PointHighlight.jl")

# Defintion 2 and its highlighting axiom
include("Definitions/src/002-Line.jl")
include("AddedAxioms/src/002-LineHighlight.jl")

# Defintion 3
include("Definitions/src/003-LineExtremities.jl")

# Definition 4
include("Definitions/src/004-StraightLine.jl")



# ==============================================
#               Postulates
# ==============================================

# Postulate 1
include("Postulates/src/001-DrawStraightLine.jl")

# ==============================================
#               Common Notions
# ==============================================

# Common Notion 1
include("CommonNotions/src/001-EqualThings.jl")


# ==============================================
#               Additional Axioms
# ==============================================

#   Intersection Axioms (e.g. Prop I.1):
include("AddedAxioms/src/003-LineIntersect.jl")

#   Movement Axioms (e.g. Prop I.4):
#       Some of these are less necessary for mimicking Euclid
#       as much as they are interesting for animations.
#       Animations try to mimick the human proving this with Euclid.
include("AddedAxioms/src/004-PointMove.jl")
include("AddedAxioms/src/005-LineMove.jl")
include("AddedAxioms/src/006-LineRotate.jl")
include("AddedAxioms/src/007-LineReflect.jl")


# ==============================================
#               Propositions
# ==============================================

# Propositions 1
include("Propositions/src/001-EquilateralTriangle.jl")
