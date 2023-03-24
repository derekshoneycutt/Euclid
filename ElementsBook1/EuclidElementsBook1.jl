#


# Note on additional axioms:
#       Although they might not all be "axioms" in a traditional
#       sense, the idea is that they underly the geometry being explored.
#       Sometimes, that is purely in a constructive "drawing" sense.
#       Sometimes, that is because Euclid assumed them.
#       They are numbered but mixed into the items as they are relevant.
#       Some of these are created as an exercise less than to be help in Euclid.


# ==============================================
#               Definitions
# ==============================================

# Definition 1 and its highlighting and moving axioms
include("Definitions/src/001-Point.jl")
include("AddedAxioms/src/001-PointHighlight.jl")
include("AddedAxioms/src/002-PointMove.jl")

# Defintion 2 and its highlighting axioms
include("Definitions/src/002-Line.jl")
include("AddedAxioms/src/003-LineHighlight.jl")

# Defintion 3 and resulting moving axioms
include("Definitions/src/003-LineExtremities.jl")
include("AddedAxioms/src/004-LineMove.jl")
include("AddedAxioms/src/005-LineRotate.jl")

# Definition 4 and resulting axioms
include("Definitions/src/004-StraightLine.jl")
include("AddedAxioms/src/006-LineReflect.jl")
include("AddedAxioms/src/007-LineIntersect.jl")

# Definition 5
include("Definitions/src/005-Surface.jl")

# Definition 6
include("Definitions/src/006-SurfaceExtremities.jl")



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
#               Propositions
# ==============================================

# Propositions 1
include("Propositions/src/001-EquilateralTriangle.jl")
