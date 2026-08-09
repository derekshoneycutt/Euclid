if !isdefined(Main, :CodeWiki)
    include("../../../tools/code_wiki.jl")
end

using .CodeWiki
using Test

function navigation_test_manifest(; sections=nothing)
    default_sections = [
        WikiSection(
            id="code", display_name="Code", description="Reference.",
            source_policy="generated", owner="code_wiki",
            managed_output_paths=["Code"], navigation_order=10,
            landing_page="Code/Home.md", stale_boundary="Code", publish=true),
        WikiSection(
            id="guides", display_name="Guides", description="Guidance.",
            source_policy="authored", owner="wiki_compositor",
            managed_output_paths=["Guides/Home.md"], navigation_order=20,
            landing_page="Guides/Home.md", stale_boundary="Guides/Home.md", publish=true),
    ]
    return WikiManifest(
        wiki_root="docs/wiki", shared_output_paths=["Home.md", "_Sidebar.md"],
        sections=sections === nothing ? default_sections : sections,
        guides=[WikiGuide(
            title="Architecture", path="Guides/Architecture.md",
            summary="System design.", navigation_order=10)],
        guide_relations=[WikiGuideRelation(
            package_id="julia:Sample",
            guide_paths=["Guides/Architecture.md#system-design"],
            symbol_prefixes=["run"])])
end

function navigation_test_package()
    package = DocumentationPackage(
        language=:julia, stable_id="julia:Sample", display_name="Sample",
        source_root="src/julia", doc_markdown="Sample module.")
    push!(package.symbols, DocumentationSymbol(
        language=:julia, stable_id="julia:Sample:function:run!",
        package_id=package.stable_id, name="run!", qualified_name="Sample.run!",
        declaration_kind=:function, signature="run!()", doc_markdown="Run it.",
        source_path="src/julia/sample.jl", source_line=4,
        method_signatures=["run!()"]))
    return package
end

@testset "Wiki manifest ownership" begin
    manifest = navigation_test_manifest()
    @test validate_wiki_manifest(manifest) === manifest

    overlapping = copy(manifest.sections)
    push!(overlapping, WikiSection(
        id="nested", display_name="Nested", description="Invalid.",
        source_policy="generated", owner="other", managed_output_paths=["Code/Julia"],
        navigation_order=30, landing_page="Code/Julia/Home.md",
        stale_boundary="Code/Julia", publish=true))
    @test_throws ErrorException validate_wiki_manifest(
        navigation_test_manifest(sections=overlapping))

    valid = WikiOutput(owner="code_wiki", path="Code/Home.md", content="# Code\n")
    @test validate_wiki_outputs(manifest, [valid]) == [valid]
    @test only(manifest.guides).owner == "guide_authors"
    @test_throws ErrorException validate_wiki_outputs(manifest, [
        WikiOutput(owner="code_wiki", path="Guides/Home.md", content="# Guides\n")])
    @test_throws ErrorException validate_wiki_outputs(manifest, [
        WikiOutput(owner="code_wiki", path="Other/Home.md", content="# Other\n")])
    @test_throws ErrorException validate_wiki_outputs(manifest, [valid, valid])

    compositor_paths = [output.path for output in build_wiki_compositor_outputs(manifest)]
    @test compositor_paths == ["Guides/Home.md", "Home.md", "_Sidebar.md"]
    code_outputs = build_code_wiki_outputs([navigation_test_package()], BridgePair[])
    @test all(output -> startswith(output.path, "Code/"), code_outputs)
    pinned_outputs = build_code_wiki_outputs(
        [navigation_test_package()], BridgePair[];
        source_link_prefix="https://github.com/example/repo/blob/revision/")
    sample_page = only(filter(output -> output.path == "Code/Julia/Sample.md", pinned_outputs))
    @test occursin(
        "https://github.com/example/repo/blob/revision/src/julia/sample.jl", sample_page.content)
    mktempdir() do directory
        cross_owner = WikiOutput(
            owner="code_wiki", path="Guides/Home.md", content="# Replaced\n")
        @test_throws ErrorException write_wiki_outputs(
            directory, manifest, [cross_owner])
        @test !ispath(joinpath(directory, "docs", "wiki", "Guides", "Home.md"))
    end
end

@testset "deterministic Wiki identities and Guide links" begin
    manifest = navigation_test_manifest()
    package = navigation_test_package()
    apply_guide_relations!([package], manifest)
    symbol = only(package.symbols)

    @test package.authored_document_refs == ["Guides/Architecture.md#system-design"]
    @test symbol.authored_document_refs == ["Guides/Architecture.md#system-design"]
    @test CodeWiki.wiki_symbol_anchor(symbol) == "symbol-julia-Sample-function-run"
    @test assign_package_page_paths([package])[package.stable_id] ==
        "Code/Julia/Sample.md"

    rendered = render_julia_module_page(package)
    @test occursin("<a id=\"symbol-julia-Sample-function-run\"></a>", rendered)
    @test occursin(
        "[Architecture](../../Guides/Architecture.md#system-design)", rendered)

    duplicate = navigation_test_package()
    duplicate.stable_id = "julia:OtherSample"
    paths = assign_package_page_paths([package, duplicate])
    @test paths[package.stable_id] != paths[duplicate.stable_id]
end

@testset "managed outputs and local links" begin
    mktempdir() do directory
        manifest = navigation_test_manifest()
        wiki_root = joinpath(directory, "docs", "wiki")
        mkpath(joinpath(wiki_root, "Code"))
        mkpath(joinpath(wiki_root, "Guides"))
        write(joinpath(wiki_root, "Home.md"), "# Home\n\n[Code](Code/Home.md)\n")
        write(joinpath(wiki_root, "_Sidebar.md"), "[Home](Home.md)\n")
        write(joinpath(wiki_root, "Code", "Home.md"), "# Code\n")
        write(joinpath(wiki_root, "Guides", "Home.md"), "# Guides\n")
        write(joinpath(wiki_root, "Guides", "Architecture.md"), "# Architecture\n")
        expected = ["Home.md", "_Sidebar.md", "Code/Home.md", "Guides/Home.md",
            "Guides/Architecture.md"]

        @test validate_managed_outputs(manifest, expected, directory)
        @test validate_wiki_links(manifest, directory)

        write(joinpath(wiki_root, "Code", "stale.md"), "# Stale\n")
        @test_throws ErrorException validate_managed_outputs(manifest, expected, directory)
        write(joinpath(wiki_root, "Home.md"), "# Home\n\n[Missing](missing.md)\n")
        @test_throws ErrorException validate_wiki_links(manifest, directory)
    end
end


@testset "scoped Wiki publication" begin
    mktempdir() do directory
        manifest = navigation_test_manifest()
        artifact = joinpath(directory, "artifact")
        destination = joinpath(directory, "wiki")
        for path in ["Home.md", "_Sidebar.md", "Code/Home.md", "Guides/Home.md",
            "Guides/Architecture.md"]
            output = joinpath(artifact, path)
            mkpath(dirname(output))
            write(output, "published $path\n")
        end
        mkpath(joinpath(destination, "Code"))
        mkpath(joinpath(destination, "Guides"))
        write(joinpath(destination, "Code", "stale.md"), "stale\n")
        write(joinpath(destination, "Guides", "Unmanaged.md"), "preserve\n")
        write(joinpath(destination, "Community.md"), "preserve\n")

        published = sync_wiki_artifact(manifest, artifact, destination)

        @test "Code" in published
        @test !ispath(joinpath(destination, "Code", "stale.md"))
        @test read(joinpath(destination, "Code", "Home.md"), String) ==
            "published Code/Home.md\n"
        @test isfile(joinpath(destination, "Guides", "Unmanaged.md"))
        @test isfile(joinpath(destination, "Community.md"))
    end
end