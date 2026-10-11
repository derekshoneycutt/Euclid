if !isdefined(Main, :CodeWiki)
    include("../../../tools/code_wiki.jl")
end

using .CodeWiki
using Test

"""Build a minimal navigation manifest for testing."""
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

"""Build a minimal navigation package for testing."""
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
    sample_page = only(filter(
        output -> output.path == "Code/Julia/Sample.md", pinned_outputs))
    @test occursin(
        "https://github.com/example/repo/blob/revision/src/julia/sample.jl",
        sample_page.content)
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
    markdown = "[Guide](Guide.md)\n`[]u8`\n```odin\nvalue: []u8\n```\n"
    @test CodeWiki.local_markdown_links(markdown) == ["Guide.md"]

    mktempdir() do directory
        manifest = navigation_test_manifest()
        wiki_root = joinpath(directory, "docs", "wiki")
        mkpath(joinpath(wiki_root, "Code"))
        mkpath(joinpath(wiki_root, "Guides"))
        write(joinpath(wiki_root, "Home.md"),
            "# Home\n\n[Code](Code/Home.md)\n[Architecture](Guides/Architecture.md#architecture)\n")
        write(joinpath(wiki_root, "_Sidebar.md"), "[Home](Home.md)\n")
        write(joinpath(wiki_root, "Code", "Home.md"), "# Code\n")
        write(joinpath(wiki_root, "Guides", "Home.md"), "# Guides\n")
        write(joinpath(wiki_root, "Guides", "Architecture.md"), "# Architecture\n")

        expected = ["Home.md", "_Sidebar.md", "Code/Home.md", "Guides/Home.md",
            "Guides/Architecture.md"]

        @test validate_managed_outputs(manifest, expected, directory)
        @test validate_wiki_links(manifest, directory)
        @test_throws ErrorException CodeWiki.validate_local_markdown_link(
            directory, "docs/wiki/Home.md", "Guides/Architecture.md#missing")

        write(joinpath(wiki_root, "Code", "stale.md"), "# Stale\n")
        @test_throws ErrorException validate_managed_outputs(
            manifest, expected, directory)
        write(joinpath(wiki_root, "Home.md"), "# Home\n\n[Missing](missing.md)\n")
        @test_throws ErrorException validate_wiki_links(manifest, directory)
    end
end


@testset "relocatable authored Guide links" begin
    mktempdir() do directory
        manifest = navigation_test_manifest()
        guide = only(manifest.guides)
        source = joinpath(directory, manifest.wiki_root, guide.path)
        mkpath(dirname(source))
        mkpath(joinpath(directory, "src", "view"))
        write(joinpath(directory, "src", "view", "frame.odin"), "package view\n")
        write(joinpath(directory, "README.md"), "# Project\n")
        markdown = "# Architecture\n\n[Frame](../../../src/view/frame.odin)\n" *
            "[Project](../../../README.md#project)\n[Guides](Home.md)\n" *
            "[Self](#architecture)\n[Web](https://example.com)\n" *
            "`[Missing](../../../missing.odin)`\n```odin\n" *
            "[Missing](../../../missing.odin)\n```\n~~~text\n" *
            "[Missing](../../../missing.odin)\n~~~\n"
        write(source, markdown)
        prefix = "https://github.com/example/repo/blob/revision/"
        output = only(CodeWiki.build_authored_guide_outputs(
            directory, manifest; source_link_prefix=prefix))
        @test occursin("[Frame]($(prefix)src/view/frame.odin)", output.content)
        @test occursin("[Project]($(prefix)README.md#project)", output.content)
        @test occursin("[Guides](Home.md)", output.content)
        @test occursin("[Self](#architecture)", output.content)
        @test occursin("[Web](https://example.com)", output.content)
        @test occursin(split(markdown, "`[Missing]"; limit=2)[2], output.content)
        @test read(source, String) == markdown
        outputs = [
            WikiOutput(owner="wiki_compositor", path="Home.md",
                content="# Home\n[Architecture](Guides/Architecture.md)\n"),
            WikiOutput(owner="wiki_compositor", path="_Sidebar.md",
                content="[Home](Home.md)\n"),
            WikiOutput(owner="wiki_compositor", path="Guides/Home.md",
                content="# Guides\n"),
            WikiOutput(owner="code_wiki", path="Code/Home.md", content="# Code\n")]
        push!(outputs, output)
        artifact = joinpath(directory, "bin", "nested", "wiki")
        @test length(CodeWiki.replace_wiki_artifact(
            directory, artifact, manifest, outputs)) == 5
        published = joinpath(directory, "published")
        sync_wiki_artifact(manifest, artifact, published)
        page = read(joinpath(published, "Guides-Architecture.md"), String)
        @test occursin("[Frame]($(prefix)src/view/frame.odin)", page)
        @test occursin("[Guides](Guides)", page)
        for target in ("../../../missing.odin", "../../../../outside.odin",
            "../../../README.md#missing")
            write(source, "[Invalid]($target)\n")
            @test_throws ErrorException CodeWiki.build_authored_guide_outputs(
                directory, manifest; source_link_prefix=prefix)
        end
        write(source, "[Missing](Missing.md)\n")
        invalid = only(CodeWiki.build_authored_guide_outputs(directory, manifest))
        outputs[end] = invalid
        @test_throws ErrorException CodeWiki.replace_wiki_artifact(
            directory, artifact, manifest, outputs)
        @test read(joinpath(artifact, guide.path), String) == output.content
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
            write(output, "# $path\n")
        end
        write(joinpath(artifact, "Home.md"),
            "# Euclid\n\n[Code](Code/Home.md)\n[Architecture](Guides/Architecture.md)\n")
        write(joinpath(artifact, "Code", "Home.md"),
            "# Code\n\n[Architecture](../Guides/Architecture.md#system-design)\n")
        mkpath(joinpath(destination, "Code"))
        mkpath(joinpath(destination, "Guides"))
        write(joinpath(destination, "Code", "stale.md"), "stale\n")
        write(joinpath(destination, "Code-Stale.md"), "stale\n")
        write(joinpath(destination, "Guides", "Unmanaged.md"), "preserve\n")
        write(joinpath(destination, "Community.md"), "preserve\n")

        published = sync_wiki_artifact(manifest, artifact, destination)

        @test published == ["Code.md", "Guides-Architecture.md", "Guides.md",
            "Home.md", "_Sidebar.md"]
        @test !ispath(joinpath(destination, "Code", "stale.md"))
        @test !ispath(joinpath(destination, "Code-Stale.md"))
        @test read(joinpath(destination, "Home.md"), String) ==
            "# Euclid\n\n[Code](Code)\n[Architecture](Guides-Architecture)\n"
        @test read(joinpath(destination, "Code.md"), String) ==
            "# Code\n\n[Architecture](Guides-Architecture#system-design)\n"
        @test isfile(joinpath(destination, "Guides", "Unmanaged.md"))
        @test isfile(joinpath(destination, "Community.md"))
    end
end