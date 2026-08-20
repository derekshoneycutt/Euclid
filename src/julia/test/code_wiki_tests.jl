if !isdefined(Main, :CodeWiki)
    include("../../../tools/code_wiki.jl")
end

using .CodeWiki
using Test

const ODIN_DOC_FIXTURE = """package sample
\tfile: sample.odin
\t\tdocumented :: proc(value: int) -> bool {...} /* 1!20 */
\t\t\t  Return whether the value is accepted.
\t\t\t
\t\t\tParameters:
\t\t\t  - value: Candidate value.

\t\tUNDOCUMENTED :: 4 /* 1!80 */
\t\tINFERRED := 5 /* 1!100 */


\tfullpath:
\t\t/tmp/sample
\tfiles:
\t\tsample.odin
"""

@testset "Odin package discovery" begin
    mktempdir() do directory
        mkpath(joinpath(directory, "src", "first"))
        mkpath(joinpath(directory, "src", "excluded", "nested"))
        write(joinpath(directory, "src", "root.odin"), "package root\n")
        write(joinpath(directory, "src", "first", "first.odin"), "package first\n")
        write(joinpath(directory, "src", "excluded", "nested", "skip.odin"), "package skip\n")
        config = OdinWikiConfig(
            repository_root=directory,
            excluded_roots=["src/excluded"])

        @test discover_odin_packages(config) == ["src", "src/first"]
    end
end

@testset "Odin text documentation parsing" begin
    package = parse_odin_doc(ODIN_DOC_FIXTURE, "src/sample")

    @test package.stable_id == "odin:src:sample"
    @test package.display_name == "sample"
    @test package.source_files == ["sample.odin"]
    @test length(package.symbols) == 3

    documented = package.symbols[1]
    @test documented.name == "documented"
    @test documented.declaration_kind == :procedure
    @test documented.signature == "documented :: proc(value: int) -> bool {...}"
    @test documented.doc_markdown ==
        "Return whether the value is accepted.\n\nParameters:\n- value: Candidate value."
    @test documented.visibility == :documented
    @test package.symbols[2].visibility == :all
    @test package.symbols[3].name == "INFERRED"
    @test package.symbols[3].declaration_kind == :constant

    @test_throws ErrorException parse_odin_doc(
        "package broken\n\torphan hierarchy", "src/broken")
end

@testset "Odin source enrichment and rendering" begin
    mktempdir() do directory
        source_directory = joinpath(directory, "src", "sample")
        mkpath(source_directory)
        write(joinpath(source_directory, "sample.odin"), """package sample

// Sample package documentation.

@(export)
documented :: proc "c" (value: int) -> bool {
    return value > 0
}
""")
        package = parse_odin_doc(ODIN_DOC_FIXTURE, "src/sample")
        CodeWiki.enrich_odin_source_metadata!(package, directory)

        documented = package.symbols[1]
        @test package.doc_markdown == "Sample package documentation."
        @test documented.source_line == 6
        @test documented.declaration_kind == :exported_abi_procedure
        @test documented.exported_abi_name == "documented"

        rendered = render_odin_package_page(package)
        @test startswith(rendered, "<!-- Generated from source doc comments.")
        @test occursin("# Odin Package `sample`", rendered)
        @test occursin("## C ABI Procedures", rendered)
        @test occursin("Sample package documentation.", rendered)
        @test occursin("[Source](../../../../src/sample/sample.odin#L6)", rendered)
        @test !occursin("UNDOCUMENTED", rendered)
    end
end

@testset "live Odin compiler extraction" begin
    repository_root = abspath(joinpath(@__DIR__, "..", "..", ".."))
    config = OdinWikiConfig(
        repository_root=repository_root,
        excluded_roots=["src/julialib"])
    packages = discover_odin_packages(config)

    @test "src/core" in packages
    @test !("src/julialib" in packages)

    package = extract_odin_package(config, "src/core")
    symbol = only(filter(item -> item.name == "font_weight_rank", package.symbols))
    @test occursin("Defines the core structures", package.doc_markdown)
    @test symbol.source_path == "src/core/font_styles.odin"
    @test symbol.source_line > 0
    @test occursin("canonical weight ordering", symbol.doc_markdown)

    root_package = extract_odin_package(config, "src")
    @test "odin:src:core" in root_package.child_package_ids

    extracted = CodeWiki.extract_default_wiki_packages(repository_root)
    odin_packages = filter(item -> item.language == :odin, extracted)
    @test sort([package.source_root for package in odin_packages]) == packages
    @test "julia:EuclidLatex" in [package.stable_id for package in extracted]
end