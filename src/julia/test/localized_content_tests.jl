using Test
using UUIDs

if !isdefined(Main, :AnimationCatalog)
    include("../animation_catalog.jl")
end
if !isdefined(Main, :LocalizedContent)
    include("../localized_content.jl")
end
if !isdefined(Main, :AnimationCatalogGeneration)
    include("../../content/animation_catalog_generation.jl")
end

using .AnimationCatalog
using .AnimationCatalogGeneration: AnimationDescriptors, AuthoredManifest
using .LocalizedContent

"""Copy a manifest so one validation case can make an isolated mutation."""
function copy_content_manifest(manifest::ContentManifest)
    return ContentManifest(
        copy(manifest.locales),
        copy(manifest.ui_messages),
        copy(manifest.translations),
        copy(manifest.catalog_names),
        copy(manifest.subjects),
        copy(manifest.editions),
        copy(manifest.availability))
end

@testset "localized content declarations" begin
    @test validate_content_manifest(AuthoredManifest, AnimationDescriptors) ===
        AuthoredManifest
    @test length(AuthoredManifest.ui_messages) == 81
    @test length(AuthoredManifest.translations) == 81
    @test length(AuthoredManifest.catalog_names) == 138
    @test length(AuthoredManifest.editions) == 3
    @test length(AuthoredManifest.subjects) == 139
    @test length(AuthoredManifest.availability) == 139
    @test count(entry -> entry.is_default, AuthoredManifest.availability) == 139
    @test getproperty.(AuthoredManifest.locales, :tag) == ["en-US"]
    @test Set(getproperty.(AuthoredManifest.editions, :edition_id)) == Set((
        "elements-heath-adapted", "hilbert-townsend-adapted", "original-en-us"))
    @test all(entry -> entry.locale_tag == "en-US" && entry.is_default,
        AuthoredManifest.availability)

    descriptor_by_id = Dict(item.id => item for item in AnimationDescriptors)
    names_by_id = Dict(item.animation_id => item.display_name
        for item in AuthoredManifest.catalog_names)
    @test Set(keys(names_by_id)) == Set(keys(descriptor_by_id))
    @test all(names_by_id[item.id] == item.display_name for item in AnimationDescriptors)
    @test count(entry -> entry.edition_id == "elements-heath-adapted",
        AuthoredManifest.availability) == 39
    @test count(entry -> entry.edition_id == "hilbert-townsend-adapted",
        AuthoredManifest.availability) == 61
    @test count(entry -> entry.edition_id == "original-en-us",
        AuthoredManifest.availability) == 39

    @testset "duplicate identities and names" begin
        duplicate_message = copy_content_manifest(AuthoredManifest)
        push!(duplicate_message.ui_messages, first(duplicate_message.ui_messages))
        @test_throws ArgumentError validate_content_manifest(
            duplicate_message, AnimationDescriptors)

        duplicate_message_key = copy_content_manifest(AuthoredManifest)
        original_message = first(duplicate_message_key.ui_messages)
        push!(duplicate_message_key.ui_messages, UiMessageDeclaration(
            UInt16(65534), original_message.key, original_message.developer_context,
            copy(original_message.arguments)))
        @test_throws ArgumentError validate_content_manifest(
            duplicate_message_key, AnimationDescriptors)

        duplicate_name = copy_content_manifest(AuthoredManifest)
        push!(duplicate_name.catalog_names, first(duplicate_name.catalog_names))
        @test_throws ArgumentError validate_content_manifest(
            duplicate_name, AnimationDescriptors)

        duplicate_sibling_name = copy_content_manifest(AuthoredManifest)
        elements_id = UUID("4a3a9e1f-6448-554a-8e37-52f579b7476b")
        target = findfirst(item -> item.animation_id == elements_id,
            duplicate_sibling_name.catalog_names)
        original = duplicate_sibling_name.catalog_names[target]
        duplicate_sibling_name.catalog_names[target] = CatalogNameDeclaration(
            original.source_namespace, original.animation_id, original.locale_tag,
            "Terminal")
        @test_throws ArgumentError validate_content_manifest(
            duplicate_sibling_name, AnimationDescriptors)
    end

    @testset "missing required declarations" begin
        missing_default = copy_content_manifest(AuthoredManifest)
        missing_default.availability[1] = AvailabilityDeclaration(
            "builtin", missing_default.availability[1].animation_id,
            "en-US", missing_default.availability[1].edition_id, false)
        @test_throws ArgumentError validate_content_manifest(
            missing_default, AnimationDescriptors)

        missing_name = copy_content_manifest(AuthoredManifest)
        pop!(missing_name.catalog_names)
        @test_throws ArgumentError validate_content_manifest(
            missing_name, AnimationDescriptors)

        missing_translation = copy_content_manifest(AuthoredManifest)
        pop!(missing_translation.translations)
        @test_throws ArgumentError validate_content_manifest(
            missing_translation, AnimationDescriptors)
    end

    @testset "unknown references" begin
        unknown_translation = copy_content_manifest(AuthoredManifest)
        push!(unknown_translation.translations,
            UiTranslationDeclaration("en-US", "ui.unknown", "Unknown"))
        @test_throws ArgumentError validate_content_manifest(
            unknown_translation, AnimationDescriptors)

        unknown_name = copy_content_manifest(AuthoredManifest)
        push!(unknown_name.catalog_names,
            CatalogNameDeclaration("builtin", UUID(UInt128(1)), "en-US", "Unknown"))
        @test_throws ArgumentError validate_content_manifest(
            unknown_name, AnimationDescriptors)

        unknown_edition = copy_content_manifest(AuthoredManifest)
        push!(unknown_edition.availability, AvailabilityDeclaration(
            "builtin", UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d"),
            "en-US", "missing-edition", false))
        @test_throws ArgumentError validate_content_manifest(
            unknown_edition, AnimationDescriptors)

        unknown_subject = copy_content_manifest(AuthoredManifest)
        push!(unknown_subject.availability, AvailabilityDeclaration(
            "builtin", UUID(UInt128(1)), "en-US", "original-en-us", false))
        @test_throws ArgumentError validate_content_manifest(
            unknown_subject, AnimationDescriptors)

        unknown_locale = copy_content_manifest(AuthoredManifest)
        push!(unknown_locale.availability, AvailabilityDeclaration(
            "builtin", UUID(UInt128(0)), "fr-FR", "original-en-us", false))
        @test_throws ArgumentError validate_content_manifest(
            unknown_locale, AnimationDescriptors)
    end

    @testset "encoding and signature validation" begin
        malformed_utf8 = copy_content_manifest(AuthoredManifest)
        first_name = first(malformed_utf8.catalog_names)
        malformed_utf8.catalog_names[1] = CatalogNameDeclaration(
            first_name.source_namespace, first_name.animation_id,
            first_name.locale_tag, String(UInt8[0xff]))
        @test_throws ArgumentError validate_content_manifest(
            malformed_utf8, AnimationDescriptors)

        embedded_nul = copy_content_manifest(AuthoredManifest)
        first_translation = first(embedded_nul.translations)
        embedded_nul.translations[1] = UiTranslationDeclaration(
            first_translation.locale_tag, first_translation.message_key, "bad\0text")
        @test_throws ArgumentError validate_content_manifest(
            embedded_nul, AnimationDescriptors)

        signature_mismatch = copy_content_manifest(AuthoredManifest)
        argument_translation = findfirst(
            entry -> entry.message_key == "ui.library.suggestion_action",
            signature_mismatch.translations)
        translation = signature_mismatch.translations[argument_translation]
        signature_mismatch.translations[argument_translation] =
            UiTranslationDeclaration(translation.locale_tag, translation.message_key,
                "Use suggested search: {unknown}")
        @test_throws ArgumentError validate_content_manifest(
            signature_mismatch, AnimationDescriptors)

        malformed_template = copy_content_manifest(AuthoredManifest)
        malformed_template.translations[argument_translation] =
            UiTranslationDeclaration("en-US", translation.message_key, "Open {query")
        @test_throws ArgumentError validate_content_manifest(
            malformed_template, AnimationDescriptors)
    end

    @testset "edition fixtures share the production validation path" begin
        ancient_greek = copy_content_manifest(AuthoredManifest)
        push!(ancient_greek.editions, EditionDeclaration(
            "ancient-greek-test", "Ancient Greek Test", "grc",
            "Validation-only Ancient Greek availability fixture."))
        push!(ancient_greek.availability, AvailabilityDeclaration(
            "builtin", UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d"),
            "en-US", "ancient-greek-test", false))
        @test validate_content_manifest(ancient_greek, AnimationDescriptors) ===
            ancient_greek

        for (edition_id, name) in (
            ("original-fixture-one", "Original fixture one"),
            ("original-fixture-two", "Original fixture two"))
            original_fixture = copy_content_manifest(AuthoredManifest)
            push!(original_fixture.editions,
                EditionDeclaration(edition_id, name, "en-US",
                    "Validation-only original-content edition fixture."))
            push!(original_fixture.availability, AvailabilityDeclaration(
                "builtin", UUID(UInt128(0)), "en-US", edition_id, false))
            @test validate_content_manifest(
                original_fixture, AnimationDescriptors) === original_fixture
        end
    end

    @testset "frozen record capacities" begin
        for (kind, capacity) in RECORD_CAPACITIES
            @test check_record_capacity(kind, capacity) === nothing
            @test_throws ArgumentError check_record_capacity(kind, capacity + 1)
        end
        @test_throws ArgumentError check_record_capacity(:unknown, 0)
    end
end
