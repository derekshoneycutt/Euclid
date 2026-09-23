include(joinpath(@__DIR__, "..", "raylib_boundary_analysis.jl"))

"""Build the exact dependency inventory expected by the Raylib owner policy."""
function expected_raylib_dependencies()
    dependencies = DependencyEdge[]
    for policy in RAYLIB_OWNER_POLICIES
        push!(dependencies, DependencyEdge(
            policy.path,
            "vendor:raylib",
            nothing,
            "external",
            "odin",
            "import",
            3,
            1))
        if policy.count == 2
            push!(dependencies, DependencyEdge(
                policy.path,
                "vendor:raylib/rlgl",
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

"""Run the boundary extension against one synthetic dependency inventory."""
function analyze_raylib_dependencies(dependencies)
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
    return analyze_extension(RaylibBoundaryExtension(), context, Dict())
end

@testset "Raylib boundary analysis" begin
    @testset "complete classified inventory" begin
        result = analyze_raylib_dependencies(expected_raylib_dependencies())

        @test isempty(result.diagnostics)
        inventory = result.artifacts["allowed_imports_by_category"]
        @test sort!(collect(keys(inventory))) == [
            "audio",
            "backend resource ownership",
            "capture acquisition",
            "documented font/image compatibility requirement",
            "subsystem drawing",
            "window/event shell",
        ]
    end

    @testset "unclassified canonical import" begin
        dependencies = expected_raylib_dependencies()
        push!(dependencies, DependencyEdge(
            "src/dynview/model/model.odin",
            "vendor:raylib",
            nothing,
            "external",
            "odin",
            "import",
            9,
            1))

        result = analyze_raylib_dependencies(dependencies)

        @test length(result.diagnostics) == 1
        @test result.diagnostics[1].path == "src/dynview/model/model.odin"
        @test occursin("no classified", result.diagnostics[1].message)
    end

    @testset "unclassified rlgl import" begin
        dependencies = expected_raylib_dependencies()
        push!(dependencies, DependencyEdge(
            "src/particles/model/model.odin",
            "vendor:raylib/rlgl",
            nothing,
            "external",
            "odin",
            "import",
            8,
            1))

        result = analyze_raylib_dependencies(dependencies)

        @test length(result.diagnostics) == 1
        @test result.diagnostics[1].path == "src/particles/model/model.odin"
    end

    @testset "stale classified owner" begin
        dependencies = expected_raylib_dependencies()
        deleteat!(dependencies, findfirst(dependency ->
            dependency.source_path == "src/audio/chalk.odin", dependencies))

        result = analyze_raylib_dependencies(dependencies)

        @test length(result.diagnostics) == 1
        @test result.diagnostics[1].path == "src/audio/chalk.odin"
        @test occursin("expected 1 import", result.diagnostics[1].message)
    end

    @testset "fixture imports are outside production policy" begin
        dependencies = expected_raylib_dependencies()
        append!(dependencies, [
            DependencyEdge(
                "src/dynview/parse/parser_test.odin",
                "vendor:raylib",
                nothing,
                "external",
                "odin",
                "import",
                4,
                1),
            DependencyEdge(
                "src/test_helpers/test_helpers.odin",
                "vendor:raylib",
                nothing,
                "external",
                "odin",
                "import",
                3,
                1),
            DependencyEdge(
                "src/core/example.odin",
                "vendor:other",
                nothing,
                "external",
                "odin",
                "import",
                2,
                1),
        ])

        result = analyze_raylib_dependencies(dependencies)

        @test isempty(result.diagnostics)
    end

    @testset "platform path normalization" begin
        dependencies = expected_raylib_dependencies()
        dependency_index = findfirst(dependency ->
            dependency.source_path == "src/audio/chalk.odin", dependencies)
        original = dependencies[dependency_index]
        dependencies[dependency_index] = DependencyEdge(
            "src\\audio\\chalk.odin",
            original.target,
            original.target_path,
            original.resolution,
            original.language,
            original.kind,
            original.line,
            original.column)

        result = analyze_raylib_dependencies(dependencies)

        @test isempty(result.diagnostics)
    end
end
