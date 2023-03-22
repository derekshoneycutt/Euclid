
# EUCLID!!!
# This is the high level file including all requirements and all pieces of the Euclid project.
# Individual frontends (e.g. Jupyter notebooks) pull this in for easiest access.


using GeometryBasics;
using LinearAlgebra;
using Symbolics;
using Latexify;
using Colors;
using GLMakie;
using Distributions;
using Base64;

# Load the core library features
include("Core/Paths.jl");
include("Core/Colors.jl");
include("Core/Animations.jl");
include("Core/Text.jl");
include("Core/TextMove.jl");



# Load Euclid Elements books
include("ElementsBook1/EuclidElementsBook1.jl");

"EUCLID!"
