println("Building gifs from Jupyter notebooks for Euclid Elements Book I")
using NBInclude

# Setup the build directory
println("Setting up build directories...")
try; mkpath("build"); catch; end
cd("build/")
try; mkpath("ElementsBook1/Definitions/gifs"); catch; end
try; mkpath("ElementsBook1/AddedAxioms/gifs"); catch; end
try; mkpath("obj"); catch; end
println("Build directories prepared.")

# First, export all the notebooks to the build dir
println("Extracting Jupyter notebooks to julia files...")
@time begin
    # Definitions...
    nbexport("obj/Elements1_Def_001-Point.jl", "../ElementsBook1/Definitions/001-Point.ipynb")
    nbexport("obj/Elements1_Def_002-Line.jl", "../ElementsBook1/Definitions/002-Line.ipynb")
    nbexport("obj/Elements1_Def_003-LineExtremities.jl", "../ElementsBook1/Definitions/003-LineExtremities.ipynb")
    nbexport("obj/Elements1_Def_004-StraightLine.jl", "../ElementsBook1/Definitions/004-StraightLine.ipynb")
    nbexport("obj/Elements1_Def_005-Surface.jl", "../ElementsBook1/Definitions/005-Surface.ipynb")
    nbexport("obj/Elements1_Def_006-SurfaceExtremities.jl", "../ElementsBook1/Definitions/006-SurfaceExtremities.ipynb")
    nbexport("obj/Elements1_Def_007-PlaneSurface.jl", "../ElementsBook1/Definitions/007-PlaneSurface.ipynb")
    nbexport("obj/Elements1_Def_008-PlaneAngle.jl", "../ElementsBook1/Definitions/008-PlaneAngle.ipynb")
    nbexport("obj/Elements1_Def_009-RectilinealAngle.jl", "../ElementsBook1/Definitions/009-RectilinealAngle.ipynb")

    # Added Axioms...
    nbexport("obj/Elements1_AddAxiom_001-HighlightingPoints.jl", "../ElementsBook1/AddedAxioms/001-HighlightingPoints.ipynb")
    nbexport("obj/Elements1_AddAxiom_002-MovingPoints.jl", "../ElementsBook1/AddedAxioms/002-MovingPoints.ipynb")
    nbexport("obj/Elements1_AddAxiom_003-HighlightingLines.jl", "../ElementsBook1/AddedAxioms/003-HighlightingLines.ipynb")
    nbexport("obj/Elements1_AddAxiom_004-MovingLines.jl", "../ElementsBook1/AddedAxioms/004-MovingLines.ipynb")
    nbexport("obj/Elements1_AddAxiom_005-RotatingLines.jl", "../ElementsBook1/AddedAxioms/005-RotatingLines.ipynb")
    nbexport("obj/Elements1_AddAxiom_006-ReflectingLines.jl", "../ElementsBook1/AddedAxioms/006-ReflectingLines.ipynb")
    nbexport("obj/Elements1_AddAxiom_007-IntersectingLines.jl", "../ElementsBook1/AddedAxioms/007-IntersectingLines.ipynb")
    nbexport("obj/Elements1_AddAxiom_008-MovingSurfaces.jl", "../ElementsBook1/AddedAxioms/008-MovingSurfaces.ipynb")
    nbexport("obj/Elements1_AddAxiom_009-RotatingSurfaces.jl", "../ElementsBook1/AddedAxioms/009-RotatingSurfaces.ipynb")
    nbexport("obj/Elements1_AddAxiom_010-ReflectingSurfaces.jl", "../ElementsBook1/AddedAxioms/010-ReflectingSurfaces.ipynb")
    nbexport("obj/Elements1_AddAxiom_011-HighlightingAngles.jl", "../ElementsBook1/AddedAxioms/011-HighlightingAngles.ipynb")
    nbexport("obj/Elements1_AddAxiom_012-MovingAngles.jl", "../ElementsBook1/AddedAxioms/012-MovingAngles.ipynb")
    nbexport("obj/Elements1_AddAxiom_013-RotatingAngles.jl", "../ElementsBook1/AddedAxioms/013-RotatingAngles.ipynb")
    nbexport("obj/Elements1_AddAxiom_014-ReflectingAngles.jl", "../ElementsBook1/AddedAxioms/014-ReflectingAngles.ipynb")
end
println("Extracted Jupyter notebooks to julia files.")


# We the need to do some setup so all the following scripts run something better
println("Importing Euclid and overriding Jupypter-specific commands for build-specific alternates...")
@time using Euclid
using GLMakie
import Euclid.draw_animation
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String, timestamps; framerate=24)
    record(doer, chart.f, filename, timestamps; framerate=framerate)
    println("Finished: "*filename)
end
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String; duration=24, framerate=24)
    record(doer, chart.f, filename, range(0,2π, step=2π/(duration*framerate)); framerate=framerate)
    println("Finished: "*filename)
end
println("Euclid imported and patched.")


# Render definitions
println("Rendering Euclid Elements Book I, Definitions...")
cd("ElementsBook1/Definitions")
println("Euclid Elements Book I Definition 1 Point...")
@time include("../build/obj/Elements1_Def_001-Point.jl")
println("Euclid Elements Book I Definition 2 Line...")
@time include("../build/obj/Elements1_Def_002-Line.jl")
println("Euclid Elements Book I Definition 3 Line Extremity...")
@time include("../build/obj/Elements1_Def_003-LineExtremities.jl")
println("Euclid Elements Book I Definition 4 Straight Line...")
@time include("../build/obj/Elements1_Def_004-StraightLine.jl")
println("Euclid Elements Book I Definition 5 Surface...")
@time include("../build/obj/Elements1_Def_005-Surface.jl")
println("Euclid Elements Book I Definition 6 Surface Extremities...")
@time include("../build/obj/Elements1_Def_006-SurfaceExtremities.jl")
println("Euclid Elements Book I Definition 7 Plane Surface...")
@time include("../build/obj/Elements1_Def_007-PlaneSurface.jl")
println("Euclid Elements Book I Definition 8 Plane Angle...")
@time include("../build/obj/Elements1_Def_008-PlaneAngle.jl")
println("Euclid Elements Book I Definition 9 Rectilineal Angle...")
@time include("../build/obj/Elements1_Def_009-RectilinealAngle.jl")
println("Euclid Elements Book I, Definitions rendered.")
cd("../../")


# Render Additional Axioms
println("Rendering Euclid Elements Book I, Added Axioms...")
cd("ElementsBook1/AddedAxioms")
println("Euclid Elements Book I Added Axiom 1 Highlighting Points...")
@time include("../build/obj/Elements1_AddAxiom_001-HighlightingPoints.jl")
println("Euclid Elements Book I Added Axiom 2 Moving Points...")
@time include("../build/obj/Elements1_AddAxiom_002-MovingPoints.jl")
println("Euclid Elements Book I Added Axiom 3 Highlighting Lines...")
@time include("../build/obj/Elements1_AddAxiom_003-HighlightingLines.jl")
println("Euclid Elements Book I Added Axiom 4 Moving Lines...")
@time include("../build/obj/Elements1_AddAxiom_004-MovingLines.jl")
println("Euclid Elements Book I Added Axiom 5 Rotating Lines...")
@time include("../build/obj/Elements1_AddAxiom_005-RotatingLines.jl")
println("Euclid Elements Book I Added Axiom 6 Reflecting Lines...")
@time include("../build/obj/Elements1_AddAxiom_006-ReflectingLines.jl")
println("Euclid Elements Book I Added Axiom 7 Intersecting Lines...")
@time include("../build/obj/Elements1_AddAxiom_007-IntersectingLines.jl")
println("Euclid Elements Book I Added Axiom 8 Moving Surfaces...")
@time include("../build/obj/Elements1_AddAxiom_008-MovingSurfaces.jl")
println("Euclid Elements Book I Added Axiom 9 Rotating Surfaces...")
@time include("../build/obj/Elements1_AddAxiom_009-RotatingSurfaces.jl")
println("Euclid Elements Book I Added Axiom 10 Reflecting Surfaces...")
@time include("../build/obj/Elements1_AddAxiom_010-ReflectingSurfaces.jl")
println("Euclid Elements Book I Added Axiom 11 Highlighting Angles...")
@time include("../build/obj/Elements1_AddAxiom_011-HighlightingAngles.jl")
println("Euclid Elements Book I Added Axiom 12 Moving Angles...")
@time include("../build/obj/Elements1_AddAxiom_012-MovingAngles.jl")
println("Euclid Elements Book I Added Axiom 13 Rotating Angles...")
@time include("../build/obj/Elements1_AddAxiom_013-RotatingAngles.jl")
println("Euclid Elements Book I Added Axiom 14 Reflecting Angles...")
@time include("../build/obj/Elements1_AddAxiom_014-ReflectingAngles.jl")
println("Euclid Elements Book I, Added Axioms rendered.")
cd("../../")
