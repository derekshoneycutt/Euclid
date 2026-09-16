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
if !isdefined(Main, :NullAnimation)
    include("../../content/nullanimation.jl")
end
if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const CatalogRootId = UUID("e405664d-b83f-5ca6-af5d-45fead73b38d")
const CatalogLeafId = UUID("683b096d-5f64-50d2-9853-df907ca19075")
const AlgebraOverviewId = UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903")
const ProductionContentRoot = normpath(joinpath(@__DIR__, "..", "..", "content"))

"""Construct one valid two-node catalog for loader tests."""
function test_catalog(; leaf_id=CatalogLeafId, path="test/fixtures/lazy_animation.jl")
    return AnimationDescriptor[
        AnimationDescriptor(CatalogRootId, nothing, "Root", 0,
            CategoryNode, "test/fixtures/lazy_animation.jl"),
        AnimationDescriptor(leaf_id, CatalogRootId, "Leaf", 0,
            LeafNode, path),
    ]
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
    Core.eval(owner, :(const NullAnimation = $NullAnimation))
    implementation = ensure_animation_loaded(
        ProductionContentRoot, [descriptor], AlgebraOverviewId; owner)
    @test implementation.id == AlgebraOverviewId
    @test nameof(implementation.entry) == :animation_entry
end

@testset "complete production catalog contract" begin
    @test length(AnimationDescriptors) == 132
    @test count(descriptor -> descriptor.kind == TerminalNode,
        AnimationDescriptors) == 1
    roots = filter(descriptor -> descriptor.parent_id === nothing,
        AnimationDescriptors)
    @test first(roots).kind == TerminalNode
    @test first(roots).display_name == "Terminal"
    @test getproperty.(roots, :sibling_order) == collect(0:5)
    curves_id = UUID("13d8650f-98d2-4701-9312-d9b6ce4c46a6")
    curves = sort(filter(descriptor -> descriptor.parent_id == curves_id,
        AnimationDescriptors); by=descriptor -> descriptor.sibling_order)
    @test getproperty.(curves, :display_name) ==
        ["Circle", "Ellipse", "Cycloid", "Curtate Cycloid",
            "Prolate Cycloid", "Cardioid", "Limaçon", "Dimpled Limaçon",
            "Convex Limaçon", "Deltoid", "Astroid", "5-Hypocycloid",
            "11⁄2-Hypocycloid"]
    @test getproperty.(curves, :sibling_order) == collect(0:12)
    path_backed = filter(
        descriptor -> descriptor.implementation_path !== nothing,
        AnimationDescriptors)
    @test length(path_backed) == 131
    generation = create_euclid_runtime_generation(ProductionContentRoot)
    for descriptor in path_backed
        implementation = load_generation_animation(generation, descriptor.id)
        @test implementation.id == descriptor.id
        @test nameof(implementation.entry) == :animation_entry
        source = read(
            joinpath(ProductionContentRoot, descriptor.implementation_path), String)
        @test occursin(r"export[^\n]*get_view_content", source)
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
