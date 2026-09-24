include(joinpath(@__DIR__, "..", "sdl_boundary_analysis.jl"))

"""Build the exact dependency inventory expected by the SDL owner policy."""
function expected_sdl_dependencies()
    dependencies = DependencyEdge[]
    for policy in SDL_OWNER_POLICIES
        push!(dependencies, DependencyEdge(
            policy.path,
            "vendor:sdl3",
            nothing,
            "external",
            "odin",
            "import",
            3,
            1))
        if policy.count == 2
            push!(dependencies, DependencyEdge(
                policy.path,
                "vendor:sdl3/image",
                nothing,
                "external",
                "odin",
                "import",
                4,
                1))
        end
    end
    return dependencies
end

"""Run the SDL boundary extension against one synthetic dependency inventory."""
function analyze_sdl_dependencies(dependencies)
    paths = Tuple(unique(dependency.source_path for dependency in dependencies))
    context = AnalysisContext(
        ".",
        :default,
        AfterLanguageAnalysis,
        paths,
        (),
        Tuple(dependencies),
        (),
        nothing,
        nothing)
    return analyze_extension(SdlBoundaryExtension(), context, Dict())
end

@testset "SDL boundary analysis" begin
    @testset "complete classified inventory" begin
        result = analyze_sdl_dependencies(expected_sdl_dependencies())

        @test isempty(result.diagnostics)
        inventory = result.artifacts["allowed_imports_by_category"]
        @test length(inventory) == length(SDL_OWNER_POLICIES)
    end

    @testset "unclassified SDL import" begin
        dependencies = expected_sdl_dependencies()
        push!(dependencies, DependencyEdge(
            "src/dynview/model/model.odin",
            "vendor:sdl3",
            nothing,
            "external",
            "odin",
            "import",
            9,
            1))

        result = analyze_sdl_dependencies(dependencies)

        @test length(result.diagnostics) == 1
        @test result.diagnostics[1].path == "src/dynview/model/model.odin"
        @test occursin("no classified", result.diagnostics[1].message)
    end

    @testset "removed backends are forbidden" begin
        for target in ("vendor:raylib", "vendor:raylib/rlgl")
            dependencies = expected_sdl_dependencies()
            push!(dependencies, DependencyEdge(
                "src/view/example.odin",
                target,
                nothing,
                "external",
                "odin",
                "import",
                9,
                1))

            result = analyze_sdl_dependencies(dependencies)

            @test length(result.diagnostics) == 1
            @test result.diagnostics[1].path == "src/view/example.odin"
            @test occursin("forbidden", result.diagnostics[1].message)
        end
    end

    @testset "stale classified owner" begin
        dependencies = expected_sdl_dependencies()
        deleteat!(dependencies, findfirst(dependency ->
            dependency.source_path == "src/view/native/sdl_icon.odin", dependencies))

        result = analyze_sdl_dependencies(dependencies)

        @test length(result.diagnostics) == 1
        @test result.diagnostics[1].path == "src/view/native/sdl_icon.odin"
        @test occursin("expected 1 import", result.diagnostics[1].message)
    end

    @testset "fixtures and probes are outside exact owner policy" begin
        dependencies = expected_sdl_dependencies()
        append!(dependencies, [
            DependencyEdge(
                "src/view/native/example_test.odin",
                "vendor:sdl3",
                nothing,
                "external",
                "odin",
                "import",
                4,
                1),
            DependencyEdge(
                "src/test_helpers/native.odin",
                "vendor:sdl3",
                nothing,
                "external",
                "odin",
                "import",
                3,
                1),
            DependencyEdge(
                "tools/sdl3_probe/main.odin",
                "vendor:sdl3",
                nothing,
                "external",
                "odin",
                "import",
                3,
                1),
            DependencyEdge(
                "tools/sdl3_image_probe/main.odin",
                "vendor:sdl3/image",
                nothing,
                "external",
                "odin",
                "import",
                3,
                1),
        ])

        result = analyze_sdl_dependencies(dependencies)

        @test isempty(result.diagnostics)
    end

    @testset "platform path normalization" begin
        dependencies = expected_sdl_dependencies()
        dependency_index = findfirst(dependency ->
            dependency.source_path == "src/view/native/sdl_icon.odin", dependencies)
        original = dependencies[dependency_index]
        dependencies[dependency_index] = DependencyEdge(
            "src\\view\\native\\sdl_icon.odin",
            original.target,
            original.target_path,
            original.resolution,
            original.language,
            original.kind,
            original.line,
            original.column)

        result = analyze_sdl_dependencies(dependencies)

        @test isempty(result.diagnostics)
    end
end
