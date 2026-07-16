include("../geometry.jl")

using .EuclidGeometry
using Test

function sorted_points_xy(points::Vector{Vector{Float32}})
    return sort(points; by = p -> (p[1], p[2]))
end

function assert_point3_approx(actual::Vector{Float32}, expected::NTuple{3,Float32}; atol::Float32=1f-5)
    @test length(actual) == 3
    @test actual[1] ≈ expected[1] atol = atol
    @test actual[2] ≈ expected[2] atol = atol
    @test actual[3] ≈ expected[3] atol = atol
end

@testset "circle_line_intersections_xy" begin
    @testset "two intersections" begin
        line_a = Float32[-2f0, 0f0, 0f0]
        line_b = Float32[2f0, 0f0, 0f0]
        center = Float32[0f0, 0f0, 0f0]
        radius = 1f0

        points = sorted_points_xy(circle_line_intersections_xy(line_a, line_b, center, radius))
        @test length(points) == 2
        assert_point3_approx(points[1], (-1f0, 0f0, 0f0))
        assert_point3_approx(points[2], (1f0, 0f0, 0f0))
    end

    @testset "tangent intersection" begin
        line_a = Float32[-2f0, 1f0, 0f0]
        line_b = Float32[2f0, 1f0, 0f0]
        center = Float32[0f0, 0f0, 0f0]
        radius = 1f0

        points = circle_line_intersections_xy(line_a, line_b, center, radius)
        @test length(points) == 1
        assert_point3_approx(points[1], (0f0, 1f0, 0f0))
    end

    @testset "no intersection" begin
        line_a = Float32[-2f0, 3f0, 0f0]
        line_b = Float32[2f0, 3f0, 0f0]
        center = Float32[0f0, 0f0, 0f0]
        radius = 1f0

        points = circle_line_intersections_xy(line_a, line_b, center, radius)
        @test isempty(points)
    end

    @testset "invalid arguments" begin
        center = Float32[0f0, 0f0, 0f0]
        @test_throws ArgumentError circle_line_intersections_xy(Float32[0f0, 0f0, 0f0], Float32[0f0, 0f0, 0f0], center, 1f0)
        @test_throws ArgumentError circle_line_intersections_xy(Float32[0f0], Float32[1f0, 0f0], center, 1f0)
        @test_throws ArgumentError circle_line_intersections_xy(Float32[0f0, 0f0], Float32[1f0, 0f0], center, -1f0)
    end
end

@testset "circle_circle_intersections_xy" begin
    @testset "two intersections" begin
        center1 = Float32[0f0, 0f0, 0f0]
        center2 = Float32[1f0, 0f0, 0f0]

        points = sorted_points_xy(circle_circle_intersections_xy(center1, 1f0, center2, 1f0))
        @test length(points) == 2
        assert_point3_approx(points[1], (0.5f0, -sqrt(3f0) / 2f0, 0f0), atol = 2f-5)
        assert_point3_approx(points[2], (0.5f0, sqrt(3f0) / 2f0, 0f0), atol = 2f-5)
    end

    @testset "tangent intersection" begin
        center1 = Float32[0f0, 0f0, 0f0]
        center2 = Float32[2f0, 0f0, 0f0]

        points = circle_circle_intersections_xy(center1, 1f0, center2, 1f0)
        @test length(points) == 1
        assert_point3_approx(points[1], (1f0, 0f0, 0f0))
    end

    @testset "no intersection" begin
        @test isempty(circle_circle_intersections_xy(Float32[0f0, 0f0, 0f0], 1f0, Float32[4f0, 0f0, 0f0], 1f0))
        @test isempty(circle_circle_intersections_xy(Float32[0f0, 0f0, 0f0], 5f0, Float32[1f0, 0f0, 0f0], 1f0))
        @test isempty(circle_circle_intersections_xy(Float32[0f0, 0f0, 0f0], 1f0, Float32[0f0, 0f0, 0f0], 1f0))
    end

    @testset "invalid arguments" begin
        @test_throws ArgumentError circle_circle_intersections_xy(Float32[0f0, 0f0], -1f0, Float32[1f0, 0f0], 1f0)
        @test_throws ArgumentError circle_circle_intersections_xy(Float32[0f0, 0f0], 1f0, Float32[1f0, 0f0], -1f0)
    end
end

@testset "line_intersection_3d" begin
    @testset "proper intersection" begin
        a1 = Float32[0f0, 0f0, 0f0]
        a2 = Float32[2f0, 2f0, 2f0]
        b1 = Float32[0f0, 2f0, 2f0]
        b2 = Float32[2f0, 0f0, 0f0]

        point = line_intersection_3d(a1, a2, b1, b2)
        @test point !== nothing
        assert_point3_approx(point, (1f0, 1f0, 1f0), atol = 1f-4)
    end

    @testset "parallel returns nothing" begin
        a1 = Float32[0f0, 0f0, 0f0]
        a2 = Float32[1f0, 0f0, 0f0]
        b1 = Float32[0f0, 1f0, 0f0]
        b2 = Float32[1f0, 1f0, 0f0]

        @test line_intersection_3d(a1, a2, b1, b2) === nothing
    end

    @testset "skew returns nothing" begin
        a1 = Float32[0f0, 0f0, 0f0]
        a2 = Float32[1f0, 0f0, 0f0]
        b1 = Float32[0f0, 1f0, 1f0]
        b2 = Float32[0f0, 2f0, 1f0]

        @test line_intersection_3d(a1, a2, b1, b2) === nothing
    end

    @testset "invalid arguments" begin
        @test_throws ArgumentError line_intersection_3d(Float32[0f0, 0f0], Float32[1f0, 1f0, 1f0], Float32[0f0, 1f0, 0f0], Float32[1f0, 0f0, 0f0])
        @test_throws ArgumentError line_intersection_3d(Float32[0f0, 0f0, 0f0], Float32[0f0, 0f0, 0f0], Float32[0f0, 1f0, 0f0], Float32[1f0, 0f0, 0f0])
    end
end
