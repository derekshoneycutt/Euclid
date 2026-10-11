"""Typed declarations and admission checks for reloadable localized content."""
module LocalizedContent

using UUIDs
using ..AnimationCatalog: AnimationDescriptor, validate_catalog

export MessageArgumentKind, TextArgument, UInt32Argument, Int64Argument,
    Float32OneDecimalArgument, LocaleDeclaration, MessageArgument,
    UiMessageDeclaration, UiMessageSourceDeclaration,
    UiTranslationDeclaration, CatalogNameDeclaration,
    ContentSubjectDeclaration, EditionDeclaration, AvailabilityDeclaration,
    ContentManifest, RECORD_CAPACITIES, check_record_capacity,
    validate_content_manifest

@enum MessageArgumentKind::UInt8 begin
    TextArgument = 1
    UInt32Argument = 2
    Int64Argument = 3
    Float32OneDecimalArgument = 4
end

const RECORD_CAPACITIES = (
    :locales => 4,
    :ui_messages => 96,
    :ui_arguments => 32,
    :translations => 384,
    :subjects => 139,
    :catalog_nodes => 138,
    :catalog_names => 552,
    :editions => 8,
    :availability => 2224,
    :total_records => 4096)

"""One available UI locale and its default-selection status."""
struct LocaleDeclaration
    tag::String
    is_default::Bool
end

"""One typed, named argument in a UI message signature."""
struct MessageArgument
    name::String
    kind::MessageArgumentKind
end

"""Stable UI message identity, developer context, and typed signature."""
struct UiMessageDeclaration
    native_id::UInt16
    key::String
    developer_context::String
    arguments::Vector{MessageArgument}
end

"""One stable message declaration paired with its authored en-US template."""
struct UiMessageSourceDeclaration
    message::UiMessageDeclaration
    en_us_template::String
end

"""One locale-specific UI message template."""
struct UiTranslationDeclaration
    locale_tag::String
    message_key::String
    template::String
end

"""One locale-scoped display name for a stable content subject."""
struct CatalogNameDeclaration
    source_namespace::String
    animation_id::UUID
    locale_tag::String
    display_name::String
end

"""One catalogue subject or reserved non-catalogue content subject."""
struct ContentSubjectDeclaration
    source_namespace::String
    animation_id::UUID
end

"""One selectable content variant and its provenance metadata."""
struct EditionDeclaration
    edition_id::String
    unique_name::String
    text_language_tag::String
    description::String
end

"""Availability of one edition for a subject and UI locale."""
struct AvailabilityDeclaration
    source_namespace::String
    animation_id::UUID
    locale_tag::String
    edition_id::String
    is_default::Bool
end

"""All authored declarations that must validate as one content unit."""
struct ContentManifest
    locales::Vector{LocaleDeclaration}
    ui_messages::Vector{UiMessageDeclaration}
    translations::Vector{UiTranslationDeclaration}
    catalog_names::Vector{CatalogNameDeclaration}
    subjects::Vector{ContentSubjectDeclaration}
    editions::Vector{EditionDeclaration}
    availability::Vector{AvailabilityDeclaration}
end

"""Reject a count above its frozen record capacity."""
function check_record_capacity(kind::Symbol, count::Integer)
    index = findfirst(capacity -> first(capacity) == kind, RECORD_CAPACITIES)
    index === nothing && throw(ArgumentError("unknown content record kind: $kind"))
    count < 0 && throw(ArgumentError("content record count must be nonnegative"))
    count <= last(RECORD_CAPACITIES[index]) ||
        throw(ArgumentError("$kind content record capacity exceeded"))
    return nothing
end

"""Validate and return a complete authored content manifest."""
function validate_content_manifest(
    manifest::ContentManifest, descriptors::Vector{AnimationDescriptor})
    validate_catalog(descriptors)
    _validate_record_capacities(manifest, descriptors)
    locales = _validate_locales(manifest.locales)
    subjects = _validate_subjects(manifest.subjects, descriptors)
    messages = _validate_messages(manifest.ui_messages)
    _validate_translations(manifest.translations, locales, messages)
    _validate_catalog_names(manifest.catalog_names, locales, subjects, descriptors)
    editions = _validate_editions(manifest.editions)
    _validate_availability(manifest.availability, locales, subjects, editions)
    return manifest
end

"""Check the per-table and total bounds before validating record contents."""
function _validate_record_capacities(
    manifest::ContentManifest, descriptors::Vector{AnimationDescriptor})
    argument_count = sum(length(message.arguments) for message in manifest.ui_messages)
    check_record_capacity(:locales, length(manifest.locales))
    check_record_capacity(:ui_messages, length(manifest.ui_messages))
    check_record_capacity(:ui_arguments, argument_count)
    check_record_capacity(:translations, length(manifest.translations))
    check_record_capacity(:subjects, length(manifest.subjects))
    check_record_capacity(:catalog_nodes, length(descriptors))
    check_record_capacity(:catalog_names, length(manifest.catalog_names))
    check_record_capacity(:editions, length(manifest.editions))
    check_record_capacity(:availability, length(manifest.availability))
    total = argument_count + length(manifest.locales) + length(manifest.ui_messages) +
        length(manifest.translations) + length(manifest.subjects) +
        length(descriptors) + length(manifest.catalog_names) +
        length(manifest.editions) + length(manifest.availability)
    check_record_capacity(:total_records, total)
    return nothing
end

"""Validate locale tags and require exactly one default locale."""
function _validate_locales(locales::Vector{LocaleDeclaration})
    isempty(locales) && throw(ArgumentError("content manifest has no locales"))
    tags = Set{String}()
    default_count = 0
    for locale in locales
        _validate_text(locale.tag, "locale tag", 35)
        occursin(r"^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$", locale.tag) ||
            throw(ArgumentError("locale tag is malformed"))
        locale.tag in tags && throw(ArgumentError("duplicate locale tag"))
        push!(tags, locale.tag)
        default_count += locale.is_default
    end
    default_count == 1 || throw(ArgumentError("content needs exactly one default locale"))
    return tags
end

"""Validate unique subjects and exact coverage of catalogue nodes plus the adapter."""
function _validate_subjects(
    subjects::Vector{ContentSubjectDeclaration},
    descriptors::Vector{AnimationDescriptor})
    subject_ids = Set{Tuple{String,UUID}}()
    for subject in subjects
        _validate_text(subject.source_namespace, "source namespace", 64)
        key = (subject.source_namespace, subject.animation_id)
        key in subject_ids && throw(ArgumentError("duplicate content subject"))
        push!(subject_ids, key)
    end
    catalog_ids = Set(("builtin", descriptor.id) for descriptor in descriptors)
    expected_ids = union(catalog_ids, Set([("builtin", UUID(UInt128(0)))]))
    subject_ids == expected_ids ||
        throw(ArgumentError("content subjects do not match catalogue and adapter"))
    return subject_ids
end

"""Validate stable UI message keys, native IDs, contexts, and signatures."""
function _validate_messages(messages::Vector{UiMessageDeclaration})
    by_key = Dict{String,UiMessageDeclaration}()
    native_ids = Set{UInt16}()
    for message in messages
        message.native_id != 0 || throw(ArgumentError("native message ID must be nonzero"))
        message.native_id in native_ids && throw(ArgumentError("duplicate native message ID"))
        push!(native_ids, message.native_id)
        _validate_text(message.key, "message key", 64)
        occursin(r"^[a-z][a-z0-9._-]*$", message.key) ||
            throw(ArgumentError("message key is malformed"))
        _validate_text(message.developer_context, "developer context", 256)
        haskey(by_key, message.key) && throw(ArgumentError("duplicate message key"))
        length(message.arguments) <= 2 ||
            throw(ArgumentError("message has more than two arguments"))
        _validate_message_arguments(message.arguments)
        by_key[message.key] = message
    end
    return by_key
end

"""Validate unique argument names and the supported wire argument kinds."""
function _validate_message_arguments(arguments::Vector{MessageArgument})
    names = Set{String}()
    for argument in arguments
        _validate_text(argument.name, "argument name", 32)
        occursin(r"^[a-z][a-z0-9_]{0,31}$", argument.name) ||
            throw(ArgumentError("message argument name is malformed"))
        argument.name in names && throw(ArgumentError("duplicate message argument"))
        push!(names, argument.name)
        argument.kind in instances(MessageArgumentKind) ||
            throw(ArgumentError("message argument kind is unsupported"))
    end
    return nothing
end

"""Validate complete locale coverage and exact placeholder/signature matches."""
function _validate_translations(
    translations::Vector{UiTranslationDeclaration}, locales::Set{String},
    messages::Dict{String,UiMessageDeclaration})
    translated = Set{Tuple{String,String}}()
    for translation in translations
        translation.locale_tag in locales ||
            throw(ArgumentError("translation references an unknown locale"))
        message = get(messages, translation.message_key, nothing)
        message === nothing && throw(ArgumentError("translation references an unknown message"))
        key = (translation.locale_tag, translation.message_key)
        key in translated && throw(ArgumentError("duplicate message translation"))
        push!(translated, key)
        _validate_text(translation.template, "message template", 128)
        _validate_template_signature(translation.template, message.arguments)
    end
    expected = Set((locale, key) for locale in locales for key in keys(messages))
    translated == expected ||
        throw(ArgumentError("translations do not completely cover UI messages"))
    return nothing
end

"""Require the template placeholder names to equal the declared argument names."""
function _validate_template_signature(
    template::String, arguments::Vector{MessageArgument})
    placeholders = _template_argument_names(template)
    signature = Set(argument.name for argument in arguments)
    placeholders == signature ||
        throw(ArgumentError("message template does not match its signature"))
    return nothing
end

"""Parse simple named placeholders and reject all other brace syntax."""
function _template_argument_names(template::String)
    names = Set{String}()
    index = firstindex(template)
    while index <= lastindex(template)
        character = template[index]
        if character == '}'
            throw(ArgumentError("message template has an unmatched closing brace"))
        elseif character == '{'
            closing = findnext(isequal('}'), template, nextind(template, index))
            closing === nothing && throw(ArgumentError("message template has an open brace"))
            body_start = nextind(template, index)
            body = body_start == closing ? "" :
                template[body_start:prevind(template, closing)]
            occursin('{', body) && throw(ArgumentError("nested message placeholders are invalid"))
            occursin(r"^[a-z][a-z0-9_]{0,31}$", body) ||
                throw(ArgumentError("message placeholder name is malformed"))
            push!(names, body)
            index = nextind(template, closing)
        else
            index = nextind(template, index)
        end
    end
    return names
end

"""Validate localized names, references, and unambiguous sibling labels."""
function _validate_catalog_names(
    names::Vector{CatalogNameDeclaration}, locales::Set{String},
    subjects::Set{Tuple{String,UUID}}, descriptors::Vector{AnimationDescriptor})
    by_identity = Dict{Tuple{String,UUID,String},String}()
    for name in names
        key = (name.source_namespace, name.animation_id, name.locale_tag)
        haskey(by_identity, key) &&
            throw(ArgumentError("duplicate localized catalogue name"))
        key[3] in locales || throw(ArgumentError("catalogue name references an unknown locale"))
        key[1:2] in subjects ||
            throw(ArgumentError("catalogue name references an unknown subject"))
        _validate_text(name.display_name, "catalogue name", 256)
        by_identity[key] = name.display_name
    end
    expected = Set(("builtin", descriptor.id, locale)
        for descriptor in descriptors for locale in locales)
    Set(keys(by_identity)) == expected ||
        throw(ArgumentError("catalogue names do not cover every node and locale"))
    _validate_sibling_names(by_identity, descriptors)
    return nothing
end

"""Reject equal names among siblings while allowing names reused elsewhere."""
function _validate_sibling_names(
    names::Dict{Tuple{String,UUID,String},String},
    descriptors::Vector{AnimationDescriptor})
    locales = Set(key[3] for key in keys(names))
    sibling_names = Set{Tuple{Union{UUID,Nothing},String,String}}()
    for descriptor in descriptors, locale in locales
        name = names[("builtin", descriptor.id, locale)]
        key = (descriptor.parent_id, locale, name)
        key in sibling_names && throw(ArgumentError("duplicate sibling catalogue name"))
        push!(sibling_names, key)
    end
    return nothing
end

"""Validate unique edition identities and required provenance strings."""
function _validate_editions(editions::Vector{EditionDeclaration})
    by_id = Dict{String,EditionDeclaration}()
    unique_names = Set{String}()
    for edition in editions
        _validate_text(edition.edition_id, "edition ID", 64)
        _validate_text(edition.unique_name, "edition name", 256)
        _validate_text(edition.text_language_tag, "edition language tag", 35)
        _validate_text(edition.description, "edition description", 1024)
        haskey(by_id, edition.edition_id) && throw(ArgumentError("duplicate edition ID"))
        edition.unique_name in unique_names && throw(ArgumentError("duplicate edition name"))
        push!(unique_names, edition.unique_name)
        by_id[edition.edition_id] = edition
    end
    return by_id
end

"""Validate availability references and one default edition per subject and locale."""
function _validate_availability(
    availability::Vector{AvailabilityDeclaration}, locales::Set{String},
    subjects::Set{Tuple{String,UUID}}, editions::Dict{String,EditionDeclaration})
    seen = Set{Tuple{String,UUID,String,String}}()
    default_counts = Dict{Tuple{String,UUID,String},Int}()
    for entry in availability
        entry.locale_tag in locales ||
            throw(ArgumentError("availability references an unknown locale"))
        (entry.source_namespace, entry.animation_id) in subjects ||
            throw(ArgumentError("availability references an unknown subject"))
        haskey(editions, entry.edition_id) ||
            throw(ArgumentError("availability references an unknown edition"))
        key = (entry.source_namespace, entry.animation_id,
            entry.locale_tag, entry.edition_id)
        key in seen && throw(ArgumentError("duplicate edition availability"))
        push!(seen, key)
        entry.is_default &&
            (default_counts[key[1:3]] = get(default_counts, key[1:3], 0) + 1)
    end
    for subject in subjects, locale in locales
        get(default_counts, (subject..., locale), 0) == 1 ||
            throw(ArgumentError("subject and locale need exactly one default edition"))
    end
    return nothing
end

"""Reject invalid UTF-8, embedded NUL, empty required text, and overlong fields."""
function _validate_text(value::String, label::String, capacity::Int)
    isvalid(value) || throw(ArgumentError("$label is not valid UTF-8"))
    occursin('\0', value) && throw(ArgumentError("$label contains NUL"))
    isempty(strip(value)) && throw(ArgumentError("$label is empty"))
    ncodeunits(value) <= capacity ||
        throw(ArgumentError("$label exceeds its byte capacity"))
    return nothing
end

end
