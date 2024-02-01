println("Building gifs from Jupyter notebooks for Euclid Elements Book I")
using NBInclude

# Setup the build directory
println("Setting up build directories...")
try; mkpath("build/obj"); catch; end
try; mkpath("build/gifs"); catch; end
println("Build directories prepared.")

# First, export all the notebooks to the build dir
println("Extracting Jupyter notebooks to julia files...")
@time begin
    # Definitions...
    nbexport("build/obj/Elements1_Def_001-Point.jl", "./Definitions/001-Point.ipynb")
    nbexport("build/obj/Elements1_Def_002-Line.jl", "./Definitions/002-Line.ipynb")
    nbexport("build/obj/Elements1_Def_003-LineExtremities.jl", "./Definitions/003-LineExtremities.ipynb")
    nbexport("build/obj/Elements1_Def_004-StraightLine.jl", "./Definitions/004-StraightLine.ipynb")
    nbexport("build/obj/Elements1_Def_005-Surface.jl", "./Definitions/005-Surface.ipynb")
    nbexport("build/obj/Elements1_Def_006-SurfaceExtremities.jl", "./Definitions/006-SurfaceExtremities.ipynb")
    nbexport("build/obj/Elements1_Def_007-PlaneSurface.jl", "./Definitions/007-PlaneSurface.ipynb")
    nbexport("build/obj/Elements1_Def_008-PlaneAngle.jl", "./Definitions/008-PlaneAngle.ipynb")
    nbexport("build/obj/Elements1_Def_009-RectilinealAngle.jl", "./Definitions/009-RectilinealAngle.ipynb")
    nbexport("build/obj/Elements1_Def_010-RightPerpendicular.jl", "./Definitions/010-RightPerpendicular.ipynb")
    nbexport("build/obj/Elements1_Def_011-ObtuseAngle.jl", "./Definitions/011-ObtuseAngle.ipynb")
    nbexport("build/obj/Elements1_Def_012-AcuteAngle.jl", "./Definitions/012-AcuteAngle.ipynb")
    nbexport("build/obj/Elements1_Def_013-Boundary.jl", "./Definitions/013-Boundary.ipynb")
    nbexport("build/obj/Elements1_Def_014-Figure.jl", "./Definitions/014-Figure.ipynb")
    nbexport("build/obj/Elements1_Def_015-Circle.jl", "./Definitions/015-Circle.ipynb")
    nbexport("build/obj/Elements1_Def_016-Center.jl", "./Definitions/016-Center.ipynb")
    nbexport("build/obj/Elements1_Def_017-Diameter.jl", "./Definitions/017-Diameter.ipynb")
    nbexport("build/obj/Elements1_Def_018-Semicircle.jl", "./Definitions/018-Semicircle.ipynb")
end
println("Extracted Jupyter notebooks to julia files.")


# We the need to do some setup so all the following scripts run something better
println("Importing Euclid and overriding Jupypter-specific commands for build-specific alternates...")
@time using Euclid
using GLMakie
import Euclid.draw_animation
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String, timestamps; framerate=24)
    record(doer, chart.f, "build/" * filename, timestamps; framerate=framerate)
    println("Finished: "*filename)
end
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String; duration=24, framerate=24)
    record(doer, chart.f, "build/" * filename, range(0,2π, step=2π/(duration*framerate)); framerate=framerate)
    println("Finished: "*filename)
end
println("Euclid imported and patched.")


# Render definitions
println("Rendering Euclid Elements Book I, Definitions...")
println("Euclid Elements Book I Definition 1 Point...")
@time include("./build/obj/Elements1_Def_001-Point.jl")
println("Euclid Elements Book I Definition 2 Line...")
@time include("./build/obj/Elements1_Def_002-Line.jl")
println("Euclid Elements Book I Definition 3 Line Extremity...")
@time include("./build/obj/Elements1_Def_003-LineExtremities.jl")
println("Euclid Elements Book I Definition 4 Straight Line...")
@time include("./build/obj/Elements1_Def_004-StraightLine.jl")
println("Euclid Elements Book I Definition 5 Surface...")
@time include("./build/obj/Elements1_Def_005-Surface.jl")
println("Euclid Elements Book I Definition 6 Surface Extremities...")
@time include("./build/obj/Elements1_Def_006-SurfaceExtremities.jl")
println("Euclid Elements Book I Definition 7 Plane Surface...")
@time include("./build/obj/Elements1_Def_007-PlaneSurface.jl")
println("Euclid Elements Book I Definition 8 Plane Angle...")
@time include("./build/obj/Elements1_Def_008-PlaneAngle.jl")
println("Euclid Elements Book I Definition 9 Rectilineal Angle...")
@time include("./build/obj/Elements1_Def_009-RectilinealAngle.jl")
println("Euclid Elements Book I Definition 10 Right Angle/Perpendicular...")
@time include("./build/obj/Elements1_Def_010-RightPerpendicular.jl")
println("Euclid Elements Book I Definition 11 Obtuse Angle...")
@time include("./build/obj/Elements1_Def_011-ObtuseAngle.jl")
println("Euclid Elements Book I Definition 12 Acute Angle...")
@time include("./build/obj/Elements1_Def_012-AcuteAngle.jl")
println("Euclid Elements Book I Definition 13 Boundary...")
@time include("./build/obj/Elements1_Def_013-Boundary.jl")
println("Euclid Elements Book I Definition 14 Figure...")
@time include("./build/obj/Elements1_Def_014-Figure.jl")
println("Euclid Elements Book I Definition 15 Circle...")
@time include("./build/obj/Elements1_Def_015-Circle.jl")
println("Euclid Elements Book I Definition 16 Center...")
@time include("./build/obj/Elements1_Def_016-Center.jl")
println("Euclid Elements Book I Definition 17 Diameter...")
@time include("./build/obj/Elements1_Def_017-Diameter.jl")
println("Euclid Elements Book I Definition 18 Semicircle...")
@time include("./build/obj/Elements1_Def_018-Semicircle.jl")
println("Euclid Elements Book I, Definitions rendered.")
cd("../../../")
