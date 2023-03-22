
# Definition 1 and its highlighting axiom
include("Definitions/src/001-Point.jl")
include("AddedAxioms/src/001-PointHighlight.jl")

# Defintion 2 and its highlighting axiom
include("Definitions/src/002-Line.jl")
include("AddedAxioms/src/002-LineHighlight.jl")

# Defintion 3 and related additional axioms
include("Definitions/src/003-LineExtremities.jl")

# Definition 4 and related additional axioms
include("Definitions/src/004-StraightLine.jl")


# Additional Axioms: Assumed by Euclid!
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
