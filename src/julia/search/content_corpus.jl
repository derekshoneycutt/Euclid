module EuclidContentCorpus

using UUIDs
using ..AnimationCatalog
using ..EuclidSearchContent
using ..LocalizedContent

export CONTENT_CORPUS_SCHEMA_VERSION, ContentRecord,
    build_content_records, write_content_records

const CONTENT_CORPUS_SCHEMA_VERSION = 3
const CONTENT_CORPUS_MAX_BYTES = 4 * 1024 * 1024
const CONTENT_RECORD_MAX_BYTES = 16 * 1024
const CanonicalValue = Union{String,Int,Bool,Nothing,Vector{String}}

"""One versioned declaration in the deterministic content record stream."""
struct ContentRecord
    kind::UInt8
    identity::String
    fields::Vector{Pair{String,CanonicalValue}}
end

"""Convert fixed-field pairs to the canonical value representation."""
function canonical_fields(fields::Pair...)
    return Pair{String,CanonicalValue}[
        String(first(field)) => convert(CanonicalValue, last(field))
        for field in fields]
end

"""Create one record with the common schema and kind envelope."""
function content_record(kind::UInt8, identity::String, fields::Pair...)
    return ContentRecord(kind, identity, canonical_fields(
        "schema" => CONTENT_CORPUS_SCHEMA_VERSION,
        "kind" => Int(kind), fields...))
end

"""Return a JSON string using canonical compact escaping."""
function write_json_string(io::IO, value::String)
    print(io, '"')
    for character in value
        if character == '"' || character == '\\'
            print(io, '\\', character)
        elseif character == '\n'
            print(io, "\\n")
        elseif character == '\r'
            print(io, "\\r")
        elseif character == '\t'
            print(io, "\\t")
        elseif Int(character) < 0x20
            print(io, "\\u", uppercase(string(Int(character), base=16, pad=4)))
        else
            print(io, character)
        end
    end
    print(io, '"')
    return nothing
end

"""Write one scalar or string-array value in canonical JSON form."""
function write_json_value(io::IO, value::CanonicalValue)
    if value isa String
        write_json_string(io, value)
    elseif value isa Bool
        print(io, value)
    elseif value isa Integer
        print(io, value)
    elseif value === nothing
        print(io, "null")
    else
        print(io, '[')
        for (index, item) in enumerate(value)
            index > 1 && print(io, ',')
            write_json_string(io, item)
        end
        print(io, ']')
    end
    return nothing
end

"""Write one fixed-order canonical declaration record."""
function write_content_record(io::IO, record::ContentRecord)
    print(io, '{')
    for (index, field) in enumerate(record.fields)
        index > 1 && print(io, ',')
        write_json_string(io, first(field))
        print(io, ':')
        write_json_value(io, last(field))
    end
    println(io, '}')
    return nothing
end

"""Return the catalogue hierarchy using names from the selected locale."""
function catalog_hierarchy_path(
    descriptor::AnimationDescriptor,
    by_id::Dict{UUID,AnimationDescriptor}, names_by_id::Dict{UUID,String})
    names = String[names_by_id[descriptor.id]]
    parent_id = descriptor.parent_id
    while parent_id !== nothing
        parent = by_id[parent_id]
        pushfirst!(names, names_by_id[parent.id])
        parent_id = parent.parent_id
    end
    return join(names, " / ")
end

"""Return the stable string form for one typed UI argument."""
function argument_type_name(kind::LocalizedContent.MessageArgumentKind)
    kind == LocalizedContent.TextArgument && return "text"
    kind == LocalizedContent.UInt32Argument && return "uint32"
    kind == LocalizedContent.Int64Argument && return "int64"
    kind == LocalizedContent.Float32OneDecimalArgument && return "float32_1dp"
    throw(ArgumentError("unknown UI argument kind"))
end

"""Return the single default edition for one subject and application locale."""
function default_edition(
    manifest::LocalizedContent.ContentManifest,
    namespace::String, animation_id::UUID, locale_tag::String)
    matches = filter(manifest.availability) do item
        item.source_namespace == namespace &&
            item.animation_id == animation_id &&
            item.locale_tag == locale_tag && item.is_default
    end
    length(matches) == 1 ||
        throw(ArgumentError("subject has no unique default edition"))
    return only(matches).edition_id
end

"""Append locale declarations, UI signatures, and translated templates."""
function append_ui_records!(
    records::Vector{ContentRecord},
    manifest::LocalizedContent.ContentManifest)
    for locale in manifest.locales
        push!(records, content_record(UInt8(2), locale.tag,
            "tag" => locale.tag, "is_default" => locale.is_default))
    end
    for message in manifest.ui_messages
        push!(records, content_record(UInt8(3), message.key,
            "message_key" => message.key,
            "native_message_id" => Int(message.native_id),
            "developer_context" => message.developer_context))
        for (ordinal, argument) in enumerate(message.arguments)
            identity = "$(message.key)|$(lpad(ordinal - 1, 2, '0'))"
            push!(records, content_record(UInt8(4), identity,
                "message_key" => message.key,
                "ordinal" => ordinal - 1,
                "argument_name" => argument.name,
                "argument_type" => argument_type_name(argument.kind)))
        end
    end
    for translation in manifest.translations
        identity = "$(translation.locale_tag)|$(translation.message_key)"
        push!(records, content_record(UInt8(5), identity,
            "locale_tag" => translation.locale_tag,
            "message_key" => translation.message_key,
            "template" => translation.template))
    end
    return nothing
end

"""Append stable catalogue identities, topology, and localized names."""
function append_catalog_records!(
    records::Vector{ContentRecord},
    manifest::LocalizedContent.ContentManifest,
    descriptors::Vector{AnimationDescriptor})
    for subject in manifest.subjects
        identity = "$(subject.source_namespace)|$(subject.animation_id)"
        push!(records, content_record(UInt8(6), identity,
            "source_namespace" => subject.source_namespace,
            "animation_id" => string(subject.animation_id)))
    end
    catalog_order = Dict(item.id => index - 1
        for (index, item) in enumerate(descriptors))
    for descriptor in descriptors
        identity = "builtin|$(descriptor.id)"
        push!(records, content_record(UInt8(7), identity,
            "source_namespace" => "builtin",
            "animation_id" => string(descriptor.id),
            "parent_animation_id" => descriptor.parent_id === nothing ?
                nothing : string(descriptor.parent_id),
            "node_kind" => Int(descriptor.kind),
            "sibling_order" => descriptor.sibling_order,
            "catalog_order" => catalog_order[descriptor.id],
            "implementation_path" => descriptor.implementation_path))
    end
    for name in manifest.catalog_names
        identity = "$(name.source_namespace)|$(name.animation_id)|$(name.locale_tag)"
        push!(records, content_record(UInt8(8), identity,
            "source_namespace" => name.source_namespace,
            "animation_id" => string(name.animation_id),
            "locale_tag" => name.locale_tag,
            "display_name" => name.display_name))
    end
    return nothing
end

"""Append edition provenance and subject-specific availability declarations."""
function append_edition_records!(
    records::Vector{ContentRecord},
    manifest::LocalizedContent.ContentManifest)
    for edition in manifest.editions
        push!(records, content_record(UInt8(9), edition.edition_id,
            "edition_id" => edition.edition_id,
            "unique_name" => edition.unique_name,
            "text_language_tag" => edition.text_language_tag,
            "description" => edition.description))
    end
    for availability in manifest.availability
        identity = join((availability.source_namespace,
            string(availability.animation_id), availability.locale_tag,
            availability.edition_id), "|")
        push!(records, content_record(UInt8(10), identity,
            "source_namespace" => availability.source_namespace,
            "animation_id" => string(availability.animation_id),
            "locale_tag" => availability.locale_tag,
            "edition_id" => availability.edition_id,
            "is_default" => availability.is_default))
    end
    return nothing
end

"""Construct one default-edition search projection from validated declarations."""
function search_projection_record(
    descriptor::AnimationDescriptor,
    manifest::LocalizedContent.ContentManifest,
    content_loader::Function, locale_tag::String,
    by_id::Dict{UUID,AnimationDescriptor}, names_by_id::Dict{UUID,String})
    content = descriptor.kind == TerminalNode ? nothing : content_loader(descriptor)
    content === nothing || content isa SearchContent ||
        throw(ArgumentError("sidecar returned invalid search content"))
    semantic_text = content === nothing ? "" : content.text
    aliases = content === nothing ? String[] : collect(content.aliases)
    descriptor.kind == TerminalNode ||
        !isempty(strip(semantic_text)) ||
        throw(ArgumentError("path-backed document has empty semantic text"))
    edition_id = default_edition(manifest, "builtin", descriptor.id, locale_tag)
    identity = "builtin|$(descriptor.id)|$locale_tag|$edition_id"
    return content_record(
        UInt8(11), identity,
        "source_namespace" => "builtin",
        "animation_id" => string(descriptor.id),
        "locale_tag" => locale_tag,
        "edition_id" => edition_id,
        "display_name" => names_by_id[descriptor.id],
        "hierarchy_path" => catalog_hierarchy_path(descriptor, by_id, names_by_id),
        "semantic_text" => semantic_text,
        "aliases" => aliases)
end

"""Append search projections sharing the shipped locale's catalogue names."""
function append_search_records!(
    records::Vector{ContentRecord}, descriptors::Vector{AnimationDescriptor},
    manifest::LocalizedContent.ContentManifest, content_loader::Function)
    by_id = Dict(item.id => item for item in descriptors)
    locale_tag = only(manifest.locales).tag
    names_by_id = Dict(
        item.animation_id => item.display_name
        for item in manifest.catalog_names if item.locale_tag == locale_tag)
    for descriptor in descriptors
        push!(records, search_projection_record(
            descriptor, manifest, content_loader, locale_tag, by_id, names_by_id))
    end
    return nothing
end

"""Reject a serialized corpus that exceeds aggregate or per-record bounds."""
function validate_content_record_sizes(records::Vector{ContentRecord})
    encoded = IOBuffer()
    write_content_records(encoded, records)
    bytes = take!(encoded)
    length(bytes) <= CONTENT_CORPUS_MAX_BYTES ||
        throw(ArgumentError("content corpus exceeds aggregate capacity"))
    for line in split(String(bytes), '\n'; keepempty=false)
        ncodeunits(line) <= CONTENT_RECORD_MAX_BYTES ||
            throw(ArgumentError("content record exceeds line capacity"))
    end
    return nothing
end

"""Build all record kinds, including search projections with current indexed bytes."""
function build_content_records(
    descriptors::Vector{AnimationDescriptor},
    manifest::LocalizedContent.ContentManifest,
    content_loader::Function)
    validate_catalog(descriptors)
    LocalizedContent.validate_content_manifest(manifest, descriptors)
    records = ContentRecord[]
    metadata = (
        "schema_version" => "3",
        "tool_compatibility" => "euclid-content-builder-v1",
        "sqlite_version" => "3.53.4",
        "tokenizer_version" => "porter-unicode61-v1",
        "query_contract_version" => "1",
        "default_locale" => only(filter(item -> item.is_default, manifest.locales)).tag)
    for (key, value) in sort!(collect(metadata); by=first)
        push!(records, content_record(UInt8(1), key, "key" => key, "value" => value))
    end
    append_ui_records!(records, manifest)
    append_catalog_records!(records, manifest, descriptors)
    append_edition_records!(records, manifest)
    append_search_records!(records, descriptors, manifest, content_loader)
    sort!(records; by=record -> (record.kind, record.identity))
    validate_content_record_sizes(records)
    return records
end

"""Write all content records in stable kind and identity order."""
function write_content_records(io::IO, records::Vector{ContentRecord})
    for record in records
        write_content_record(io, record)
    end
    return nothing
end

end
