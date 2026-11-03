using Test

# Standalone: julia --project=tools/analysis tools/test/sysimage_inputs_tests.jl
if !isdefined(Main, :SYSIMAGE_STABLE_INPUTS)
    include(joinpath(@__DIR__, "..", "make.jl"))
end

@testset "sysimage input fingerprint" begin
    relative_inputs = replace.(
        relpath.(sysimage_stable_input_paths(), JULIA_TEST_PROJECT), '\\' => '/')
    @test "animation_catalog.jl" in relative_inputs
    @test "localized_content.jl" in relative_inputs
    @test "animations/trochoids.jl" in relative_inputs
    @test "animations/cycloids.jl" in relative_inputs
    @test "animations/conics.jl" in relative_inputs
    animation_inputs = filter(path -> startswith(path, "animations/"), relative_inputs)
    @test !isempty(animation_inputs)
    @test all(path -> path in relative_inputs,
        ["animations/" * name
            for name in readdir(joinpath(JULIA_TEST_PROJECT, "animations"))])
    @test !("animation_catalog_data.jl" in relative_inputs)
    @test !("animation_catalog_generation.jl" in relative_inputs)
    @test !("nullanimation.jl" in relative_inputs)
    @test !any(startswith(path, "elements/") for path in relative_inputs)
    @test length(content_input_fingerprint()) == 64

    mktempdir() do root
        first_path = joinpath(root, "first.jl")
        second_path = joinpath(root, "second.jl")
        write(first_path, "first")
        write(second_path, "second")
        identity = "julia=test;platform=test"
        first = fingerprint_sysimage_inputs(
            [first_path, second_path], root; identity)
        @test first == fingerprint_sysimage_inputs(
            [first_path, second_path], root; identity)
        @test first != fingerprint_sysimage_inputs(
            [first_path, second_path], root; identity=identity * ";changed")
        write(second_path, "changed")
        @test first != fingerprint_sysimage_inputs(
            [first_path, second_path], root; identity)
    end
    mktempdir() do root
        for relative in SYSIMAGE_STABLE_INPUTS
            if isdir(joinpath(JULIA_TEST_PROJECT, relative))
                mkpath(joinpath(root, relative))
            else
                write(joinpath(root, relative), "")
            end
        end
        child = joinpath(root, "animations", "nested", "motion.jl")
        mkpath(dirname(child))
        write(child, "first")
        @test child in sysimage_stable_input_paths(root)
        first = sysimage_input_fingerprint(root)
        write(child, "second")
        @test sysimage_input_fingerprint(root) != first
    end
end
