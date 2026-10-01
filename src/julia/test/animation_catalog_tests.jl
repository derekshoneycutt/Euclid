using UUIDs

if !isdefined(Main, :AnimationCatalog)
    include("../animation_catalog.jl")
end
using .AnimationCatalog

if !isdefined(Main, :AnimationCatalogGeneration)
    include("../../content/animation_catalog_generation.jl")
end
using .AnimationCatalogGeneration: AnimationDescriptors

if !isdefined(Main, :EuclidAnimations)
    include("../animations.jl")
end
if !isdefined(Main, :EuclidSearchContent)
    include("../search/search_content.jl")
end
if !isdefined(Main, :EuclidSearchCorpus)
    include("../search/search_corpus.jl")
end
if !isdefined(Main, :NullAnimation)
    include("../../content/nullanimation.jl")
end
if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const CatalogRootId = UUID("e405664d-b83f-5ca6-af5d-45fead73b38d")
const CatalogLeafId = UUID("683b096d-5f64-50d2-9853-df907ca19075")
const AlgebraOverviewId = UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903")
const PerpendicularId = UUID("144e86ef-79d1-53b5-90bd-920dc9764972")
const ProductionContentRoot = normpath(joinpath(@__DIR__, "..", "..", "content"))

@testset "canonical search corpus" begin
    parent_id = UUID("50000000-0000-0000-0000-000000000000")
    child_id = UUID("10000000-0000-0000-0000-000000000000")
    terminal_id = UUID("90000000-0000-0000-0000-000000000000")
    descriptors = AnimationDescriptor[
        AnimationDescriptor(parent_id, nothing, "Geometry", 0,
            CategoryNode, "geometry/overview.jl"),
        AnimationDescriptor(terminal_id, nothing, "Terminal", 1,
            TerminalNode, nothing),
        AnimationDescriptor(child_id, parent_id, "Perpendicular", 0,
            LeafNode, "geometry/perpendicular.jl"),
    ]
    loader = descriptor -> EuclidSearchContent.SearchContent(
        "Semantic content for $(descriptor.display_name).", ("alternate",))
    records = EuclidSearchCorpus.build_catalog_corpus(descriptors, loader)
    @test getproperty.(records, :animation_id) ==
        string.([child_id, parent_id, terminal_id])
    @test getproperty.(records, :catalog_order) == [2, 0, 1]
    @test records[1].parent_animation_id == string(parent_id)
    @test records[1].hierarchy_path == "Geometry / Perpendicular"
    @test records[1].sibling_order == 0
    @test records[1].implementation_path == "geometry/perpendicular.jl"
    @test records[3].semantic_text == ""
    @test isempty(records[3].aliases)
    first_output = IOBuffer()
    second_output = IOBuffer()
    EuclidSearchCorpus.write_catalog_corpus(first_output, records)
    EuclidSearchCorpus.write_catalog_corpus(second_output, records)
    first_bytes = take!(first_output)
    @test first_bytes == take!(second_output)
    @test EuclidSearchCorpus.CATALOG_CORPUS_SCHEMA_VERSION == 2
    @test String(first_bytes) == """
    {"schema":2,"source_namespace":"builtin","animation_id":"10000000-0000-0000-0000-000000000000","parent_animation_id":"50000000-0000-0000-0000-000000000000","node_kind":2,"display_name":"Perpendicular","sibling_order":0,"catalog_order":2,"implementation_path":"geometry/perpendicular.jl","hierarchy_path":"Geometry / Perpendicular","semantic_text":"Semantic content for Perpendicular.","aliases":["alternate"]}
    {"schema":2,"source_namespace":"builtin","animation_id":"50000000-0000-0000-0000-000000000000","parent_animation_id":null,"node_kind":1,"display_name":"Geometry","sibling_order":0,"catalog_order":0,"implementation_path":"geometry/overview.jl","hierarchy_path":"Geometry","semantic_text":"Semantic content for Geometry.","aliases":["alternate"]}
    {"schema":2,"source_namespace":"builtin","animation_id":"90000000-0000-0000-0000-000000000000","parent_animation_id":null,"node_kind":3,"display_name":"Terminal","sibling_order":1,"catalog_order":1,"implementation_path":null,"hierarchy_path":"Terminal","semantic_text":"","aliases":[]}
    """
    unsafe_descriptors = copy(descriptors)
    unsafe_descriptors[3] = AnimationDescriptor(child_id, parent_id, "Perpendicular", 0,
        LeafNode, "geometry/../outside.jl")
    @test_throws ArgumentError EuclidSearchCorpus.build_catalog_corpus(
        unsafe_descriptors, loader)
    oversized_descriptors = copy(descriptors)
    oversized_descriptors[3] = AnimationDescriptor(
        child_id, parent_id, "Perpendicular", 0, LeafNode,
        repeat("a", EuclidSearchCorpus.CATALOG_PATH_BYTE_CAPACITY + 1))
    @test_throws ArgumentError EuclidSearchCorpus.build_catalog_corpus(
        oversized_descriptors, loader)
end

@testset "search content value contract" begin
    content = EuclidSearchContent.SearchContent(
        "Perpendicular lines form right angles.",
        ("normal line", "right angle"))
    @test content.text == "Perpendicular lines form right angles."
    @test content.aliases == ("normal line", "right angle")
    @test_throws ArgumentError EuclidSearchContent.SearchContent("", ())
    @test_throws ArgumentError EuclidSearchContent.SearchContent("valid", ("",))
    @test_throws ArgumentError EuclidSearchContent.SearchContent(
        "valid", ("Right Angle", " right angle "))
    @test_throws ArgumentError EuclidSearchContent.SearchContent("bad\0text", ())
end

"""Construct one valid two-node catalog for loader tests."""
function test_catalog(; leaf_id=CatalogLeafId, path="test/fixtures/lazy_animation.jl")
    return AnimationDescriptor[
        AnimationDescriptor(CatalogRootId, nothing, "Root", 0,
            CategoryNode, "test/fixtures/lazy_animation.jl"),
        AnimationDescriptor(leaf_id, CatalogRootId, "Leaf", 0,
            LeafNode, path),
    ]
end

"""Return the required adjacent sidecar path for one implementation path."""
function content_sidecar_path(implementation_path::String)
    return replace(implementation_path, r"\.jl$" => "_content.jl")
end

"""Collect every adjacent content sidecar relative to the production root."""
function production_content_sidecars()
    sidecars = String[]
    for (directory, _, files) in walkdir(ProductionContentRoot)
        for file in filter(path -> endswith(path, "_content.jl"), files)
            path = relpath(joinpath(directory, file), ProductionContentRoot)
            push!(sidecars, replace(path, '\\' => '/'))
        end
    end
    return sort!(sidecars)
end

@testset "animation catalog validation" begin
    descriptors = test_catalog()
    @test length(validate_catalog(descriptors)) == 2
    @test_throws ArgumentError validate_catalog([descriptors; descriptors[1]])
    @test_throws ArgumentError validate_catalog(test_catalog(path="../outside.jl"))
    @test_throws ArgumentError validate_catalog(test_catalog(path="/tmp/outside.jl"))
    @test_throws ArgumentError validate_catalog(test_catalog(path="test\\outside.jl"))
    missing_parent = AnimationDescriptor(CatalogLeafId, uuid4(), "Leaf", 0,
        LeafNode, "test/fixtures/lazy_animation.jl")
    @test_throws ArgumentError validate_catalog([missing_parent])
end

@testset "production animation program contract" begin
    descriptor = AnimationDescriptor(AlgebraOverviewId, nothing, "Algebra", 0,
        CategoryNode, "algebra/algebra_overview.jl")
    owner = Module(:ProductionAnimationContract, false, false)
    Core.eval(owner, :(const AnimationCatalog = $AnimationCatalog))
    Core.eval(owner, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(owner, :(const EuclidLatex = $EuclidLatex))
    Core.eval(owner, :(const EuclidSearchContent = $EuclidSearchContent))
    Core.eval(owner, :(const NullAnimation = $NullAnimation))
    implementation = ensure_animation_loaded(
        ProductionContentRoot, [descriptor], AlgebraOverviewId; owner)
    @test implementation.id == AlgebraOverviewId
    @test nameof(implementation.entry) == :animation_entry
end

@testset "representative pure content sidecar" begin
    descriptor = only(filter(
        candidate -> candidate.id == PerpendicularId, AnimationDescriptors))
    owner = Module(:PerpendicularContentContract, false, false)
    Core.eval(owner, :(const AnimationCatalog = $AnimationCatalog))
    Core.eval(owner, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(owner, :(const EuclidAnimations = $EuclidAnimations))
    Core.eval(owner, :(const EuclidLatex = $EuclidLatex))
    Core.eval(owner, :(const EuclidSearchContent = $EuclidSearchContent))
    implementation = ensure_animation_loaded(
        ProductionContentRoot, AnimationDescriptors, PerpendicularId; owner)
    animation_module = getfield(owner, :ElementsOneDefinitionPerpendicular)
    sidecar = getfield(animation_module, :ElementsOneDefinitionPerpendicularContent)
    first_search = sidecar.get_search_content()
    second_search = sidecar.get_search_content()
    @test first_search == second_search
    @test presented_text(animation_module.get_view_content(C_NULL)) ==
        presented_text(sidecar.get_view_content())
end

@testset "complete production catalog contract" begin
    @test length(AnimationDescriptors) == 138
    corpus_records = EuclidSearchCorpus.build_catalog_corpus(
        AnimationDescriptors,
        _ -> EuclidSearchContent.SearchContent("Catalog metadata.", ()))
    ordered_records = sort(corpus_records; by=record -> record.catalog_order)
    @test getproperty.(ordered_records, :catalog_order) == collect(0:137)
    @test getproperty.(ordered_records, :sibling_order) ==
        getproperty.(AnimationDescriptors, :sibling_order)
    @test getproperty.(ordered_records, :implementation_path) ==
        getproperty.(AnimationDescriptors, :implementation_path)
    @test count(record -> record.implementation_path === nothing,
        ordered_records) == 1
    @test only(filter(record -> record.implementation_path === nothing,
        ordered_records)).node_kind == UInt8(TerminalNode)
    @test all(record -> !isempty(record.animation_id) &&
        !isempty(record.display_name) && !isempty(record.hierarchy_path),
        ordered_records)
    @test count(descriptor -> descriptor.kind == TerminalNode,
        AnimationDescriptors) == 1
    roots = filter(descriptor -> descriptor.parent_id === nothing,
        AnimationDescriptors)
    @test first(roots).kind == TerminalNode
    @test first(roots).display_name == "Terminal"
    @test getproperty.(roots, :sibling_order) == collect(0:6)
    curves_id = UUID("13d8650f-98d2-4701-9312-d9b6ce4c46a6")
    curves = sort(filter(descriptor -> descriptor.parent_id == curves_id,
        AnimationDescriptors); by=descriptor -> descriptor.sibling_order)
    @test getproperty.(curves, :display_name) ==
        ["Circle", "Ellipse", "Cycloid", "Curtate Cycloid",
            "Prolate Cycloid", "Cardioid", "Limaçon", "Dimpled Limaçon",
            "Convex Limaçon", "Deltoid", "Astroid", "5-Hypocycloid",
                "11⁄2-Hypocycloid", "Nephroid", "3-Dimple Epitrochoid",
                "5-Point Hypotrochoid"]
            @test getproperty.(curves, :sibling_order) == collect(0:15)
    logic_id = UUID("2905c158-007b-4412-be60-20a27decc0b2")
    logic = sort(filter(descriptor -> descriptor.parent_id == logic_id,
        AnimationDescriptors); by=descriptor -> descriptor.sibling_order)
    @test getproperty.(logic, :display_name) == ["And", "Not"]
    @test getproperty.(logic, :sibling_order) == collect(0:1)
    path_backed = filter(
        descriptor -> descriptor.implementation_path !== nothing,
        AnimationDescriptors)
    @test length(path_backed) == 137
    implementation_paths = String[
        descriptor.implementation_path for descriptor in path_backed]
    expected_sidecars = sort!(content_sidecar_path.(implementation_paths))
    @test length(unique(implementation_paths)) == 137
    @test production_content_sidecars() == expected_sidecars
    generation = create_euclid_runtime_generation(ProductionContentRoot)
    for descriptor in path_backed
        implementation = load_generation_animation(
            generation, descriptor.id, descriptor.implementation_path)
        @test implementation.id == descriptor.id
        @test nameof(implementation.entry) == :animation_entry
        source = read(
            joinpath(ProductionContentRoot, descriptor.implementation_path), String)
        @test occursin(r"export[^\n]*get_view_content", source)
        sidecar_relative = content_sidecar_path(descriptor.implementation_path)
        sidecar_source = read(joinpath(ProductionContentRoot, sidecar_relative), String)
        @test occursin("get_search_content", sidecar_source)
        @test !occursin("OdinJuliaBridge", sidecar_source)
        @test !occursin(r"\b(?:rand|randn|time|open|read|write)\s*\(", sidecar_source)
        animation_module = parentmodule(implementation.entry)
        content_name = Symbol(string(nameof(animation_module)), "Content")
        @test isdefined(animation_module, content_name)
        content_module = getfield(animation_module, content_name)
        get_search_content = Base.invokelatest(
            getfield, content_module, :get_search_content)
        get_sidecar_view = Base.invokelatest(
            getfield, content_module, :get_view_content)
        get_runtime_view = Base.invokelatest(
            getfield, animation_module, :get_view_content)
        first_search = Base.invokelatest(get_search_content)
        second_search = Base.invokelatest(get_search_content)
        @test first_search isa EuclidSearchContent.SearchContent
        @test first_search == second_search
        @test presented_text(Base.invokelatest(get_sidecar_view)) ==
            presented_text(Base.invokelatest(get_runtime_view, C_NULL))
        @test occursin("publish_view_content", source)
        @test !occursin("get_view_text", source)
        @test !occursin("publish_view_update", source)
    end
end

@testset "production presentation boundary" begin
    forbidden = r"\b(?:dynview_[a-z0-9_]+|BRIDGE_DYNVIEW_[A-Z0-9_]+)\b"
    violations = String[]
    roots = (dirname(@__DIR__), ProductionContentRoot)
    for root in roots
        for (directory, _, files) in walkdir(root)
            startswith(directory, joinpath(root, "test")) && continue
            for file in filter(path -> endswith(path, ".jl"), files)
                path = joinpath(directory, file)
                occursin(forbidden, read(path, String)) && push!(violations, path)
            end
        end
    end
    @test isempty(violations)
end

@testset "animation loading contract" begin
    implementation = ensure_animation_loaded(
        dirname(@__DIR__), test_catalog(), CatalogLeafId)
    @test implementation.id == CatalogLeafId
    @test Base.invokelatest(implementation.entry, C_NULL, Int32(2), 0.25f0)

    mismatch_catalog = test_catalog(leaf_id=uuid4())
    @test_throws ArgumentError ensure_animation_loaded(
        dirname(@__DIR__), mismatch_catalog, mismatch_catalog[2].id)
end
