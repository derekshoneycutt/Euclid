module EuclidLegacySearchCorpus

using UUIDs
using ..AnimationCatalog
using ..EuclidSearchContent

export CATALOG_CORPUS_SCHEMA_VERSION, CatalogCorpusRecord,
    build_catalog_corpus, write_catalog_corpus

const CATALOG_CORPUS_SCHEMA_VERSION = 2
const CATALOG_SOURCE_NAMESPACE = "builtin"
const CATALOG_NAME_BYTE_CAPACITY = 256
const CATALOG_PATH_BYTE_CAPACITY = 2 * 1024

"""Canonical build-time record for one animation catalogue entry."""
struct CatalogCorpusRecord
    source_namespace::String
    animation_id::String
    parent_animation_id::Union{String,Nothing}
    node_kind::UInt8
    display_name::String
    sibling_order::Int
    catalog_order::Int
    implementation_path::Union{String,Nothing}
    hierarchy_path::String
    semantic_text::String
    aliases::Vector{String}
end

"""Return the catalog-derived hierarchy path for one descriptor."""
function hierarchy_path(
    descriptor::AnimationDescriptor,
    by_id::Dict{UUID,AnimationDescriptor})

    names = String[descriptor.display_name]
    parent_id = descriptor.parent_id
    while parent_id !== nothing
        parent = by_id[parent_id]
        pushfirst!(names, parent.display_name)
        parent_id = parent.parent_id
    end
    return join(names, " / ")
end

"""Reject catalogue strings outside the canonical corpus bounds."""
function validate_document_strings(
    name::String, hierarchy::String, implementation_path::Union{String,Nothing})

    isempty(strip(name)) && throw(ArgumentError("search document name is empty"))
    occursin('\0', name) && throw(ArgumentError("search document name contains NUL"))
    ncodeunits(name) <= CATALOG_NAME_BYTE_CAPACITY ||
        throw(ArgumentError("search document name exceeds byte capacity"))
    occursin('\0', hierarchy) &&
        throw(ArgumentError("search document hierarchy contains NUL"))
    ncodeunits(hierarchy) <= CATALOG_PATH_BYTE_CAPACITY ||
        throw(ArgumentError("search document hierarchy exceeds byte capacity"))
    if implementation_path !== nothing
        occursin('\0', implementation_path) &&
            throw(ArgumentError("implementation path contains NUL"))
        ncodeunits(implementation_path) <= CATALOG_PATH_BYTE_CAPACITY ||
            throw(ArgumentError("implementation path exceeds byte capacity"))
    end
    return nothing
end

"""Build UUID-ordered records with order from validated descriptor order."""
function build_catalog_corpus(
    descriptors::Vector{AnimationDescriptor}, content_loader::Function)

    by_id = validate_catalog(descriptors)
    catalog_order = Dict(descriptor.id => index - 1
        for (index, descriptor) in enumerate(descriptors))
    records = CatalogCorpusRecord[]
    for descriptor in sort(descriptors; by=item -> string(item.id))
        hierarchy = hierarchy_path(descriptor, by_id)
        validate_document_strings(
            descriptor.display_name, hierarchy, descriptor.implementation_path)
        content = descriptor.kind == TerminalNode ? nothing : content_loader(descriptor)
        content === nothing || content isa SearchContent ||
            throw(ArgumentError("sidecar returned invalid search content"))
        semantic_text = content === nothing ? "" : content.text
        aliases = content === nothing ? String[] : collect(content.aliases)
        push!(records, CatalogCorpusRecord(
            CATALOG_SOURCE_NAMESPACE, string(descriptor.id),
            descriptor.parent_id === nothing ? nothing : string(descriptor.parent_id),
            UInt8(descriptor.kind), descriptor.display_name, descriptor.sibling_order,
            catalog_order[descriptor.id], descriptor.implementation_path,
            hierarchy, semantic_text, aliases))
    end
    return records
end

"""Write one JSON string with deterministic escaping."""
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
end

"""Write one canonical catalogue record as a versioned JSON Lines record."""
function write_catalog_record(io::IO, record::CatalogCorpusRecord)
    print(io, "{\"schema\":", CATALOG_CORPUS_SCHEMA_VERSION,
        ",\"source_namespace\":")
    write_json_string(io, record.source_namespace)
    print(io, ",\"animation_id\":")
    write_json_string(io, record.animation_id)
    print(io, ",\"parent_animation_id\":")
    if record.parent_animation_id === nothing
        print(io, "null")
    else
        write_json_string(io, record.parent_animation_id)
    end
    print(io, ",\"node_kind\":", record.node_kind, ",\"display_name\":")
    write_json_string(io, record.display_name)
    print(io, ",\"sibling_order\":", record.sibling_order,
        ",\"catalog_order\":", record.catalog_order,
        ",\"implementation_path\":")
    if record.implementation_path === nothing
        print(io, "null")
    else
        write_json_string(io, record.implementation_path)
    end
    print(io, ",\"hierarchy_path\":")
    write_json_string(io, record.hierarchy_path)
    print(io, ",\"semantic_text\":")
    write_json_string(io, record.semantic_text)
    print(io, ",\"aliases\":[")
    for (index, alias) in enumerate(record.aliases)
        index > 1 && print(io, ',')
        write_json_string(io, alias)
    end
    println(io, "]}")
end

"""Write the complete canonical corpus in stable UUID order."""
function write_catalog_corpus(io::IO, records::Vector{CatalogCorpusRecord})
    for record in records
        write_catalog_record(io, record)
    end
    return nothing
end

end