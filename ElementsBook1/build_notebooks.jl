println("Building gifs from Jupyter notebooks for Euclid Elements Book I")
using NBInclude

# Setup the build directory
println("Setting up build directories...")
try; mkpath("build/obj"); catch; end
try; mkpath("build/gifs"); catch; end
println("Build directories prepared.")

build_definitions_names = [
    "001-Point",
    "002-Line",
    "003-LineExtremities",
    "004-StraightLine",
    "005-Surface",
    "006-SurfaceExtremities",
    "007-PlaneSurface",
    "008-PlaneAngle",
    "009-RectilinealAngle",
    "010a-RightAngle",
    "010b-Perpendicular",
    "011-ObtuseAngle",
    "012-AcuteAngle",
    "013-Boundary",
    "014-Figure",
    "015-Circle",
    "016-Center",
    "017-Diameter",
    "018-Semicircle",
    "019a-Trilateral",
    "019b-Quadrilateral",
    "019c-Multilateral",
    "020a-Equilateral",
    "020b-Isosceles",
    "020c-Scalene",
    "021a-RightTriangles",
    "021b-ObtuseTriangle",
    "021c-AcuteTriangle",
    "022a-Square",
    "022b-Oblong",
    "022c-Rhombus",
    "022d-Rhomboid",
    "022e-Trapezia",
    "023-ParallelLines"
]

build_definitions_obj = [
    ("build/obj/Elements1_Def_" * name * ".jl",
     "./Definitions/" * name * ".ipynb",
     name)
    for name in build_definitions_names
]

# First, export all the notebooks to the build dir
println("Extracting Jupyter notebooks to julia files...")
@time begin
    # Definitions...
    foreach(build_definitions_obj) do obj
        nbexport(obj[1], obj[2])
    end
end
println("Extracted Jupyter notebooks to julia files.")


# We the need to do some setup so all the following scripts run something better
println("Importing Euclid and EuclidGLMakie...")
@time using Euclid
@time using EuclidGLMakie
using GLMakie: record
import EuclidGLMakie.draw_animation
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String, timestamps; framerate=24)
    record(doer, chart.f, "build/" * filename, timestamps; framerate=framerate)
    println("Finished: "*filename)
end
function draw_animation(doer::Function, chart::EuclidChartSpace, filename::String; duration=24, framerate=24)
    record(doer, chart.f, "build/" * filename, range(0,2π, step=2π/(duration*framerate)); framerate=framerate)
    println("Finished: "*filename)
end
println("Euclid imported.")


# Render definitions
println("Rendering Euclid Elements Book I, Definitions...")
foreach(build_definitions_obj) do obj
    println("Euclid Elements Book I Definition: " * obj[3])
    @time include("./" * obj[1])
end
println("Euclid Elements Book I, Definitions rendered.")
cd("../../../")
