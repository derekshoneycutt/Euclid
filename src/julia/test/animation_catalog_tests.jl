using UUIDs

if !isdefined(Main, :AnimationCatalog)
    include("../animation_catalog.jl")
end
using .AnimationCatalog

if !isdefined(Main, :EuclidAnimations)
    include("../animations.jl")
end
if !isdefined(Main, :NullAnimation)
    include("../nullanimation.jl")
end
if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const CatalogRootId = UUID("e405664d-b83f-5ca6-af5d-45fead73b38d")
const CatalogLeafId = UUID("683b096d-5f64-50d2-9853-df907ca19075")
const AlgebraOverviewId = UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903")

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
        dirname(@__DIR__), [descriptor], AlgebraOverviewId; owner)
    @test implementation.id == AlgebraOverviewId
    @test nameof(implementation.entry) == :animation_entry
end

@testset "complete production catalog contract" begin
    @test length(AnimationDescriptors) == 118
    @test count(descriptor -> descriptor.kind == ScratchpadNode,
        AnimationDescriptors) == 1
    roots = filter(descriptor -> descriptor.parent_id === nothing,
        AnimationDescriptors)
    @test first(roots).kind == ScratchpadNode
    @test first(roots).display_name == "Scratchpad"
    @test getproperty.(roots, :sibling_order) == collect(0:4)
    path_backed = filter(
        descriptor -> descriptor.implementation_path !== nothing,
        AnimationDescriptors)
    @test length(path_backed) == 117
    generation = create_euclid_runtime_generation()
    for descriptor in path_backed
        implementation = load_generation_animation(generation, descriptor.id)
        @test implementation.id == descriptor.id
        @test nameof(implementation.entry) == :animation_entry
    end
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
