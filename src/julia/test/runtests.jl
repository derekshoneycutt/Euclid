using Test

@testset "EuclidApp Julia Tests" begin
    @testset "Phase 1 - Geometry" begin
        include("geometry_tests.jl")
    end

    @testset "Phase 2 - Scratchpad" begin
        include("scratchpad_tests.jl")
    end

    @testset "Phase 5 - Bridge Helpers" begin
        include("bridge_helpers_tests.jl")
    end
end
