module EuclidSearchCorpus

using UUIDs
using ..AnimationCatalog
using ..EuclidSearchContent

export SEARCH_CORPUS_SCHEMA_VERSION, SearchDocument,
    build_search_documents, write_search_corpus

const SEARCH_CORPUS_SCHEMA_VERSION = 1
const SEARCH_SOURCE_NAMESPACE = "builtin"
const SEARCH_NAME_BYTE_CAPACITY = 256
const SEARCH_PATH_BYTE_CAPACITY = 2 * 1024

"""Canonical build-time record for one searchable catalog document."""
struct SearchDocument
    source_namespace::String
    document_id::String
    node_kind::UInt8
    display_name::String
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

"""Reject catalog-derived strings outside the canonical corpus bounds."""
function validate_document_strings(name::String, path::String)
    isempty(strip(name)) && throw(ArgumentError("search document name is empty"))
    occursin('\0', name) && throw(ArgumentError("search document name contains NUL"))
    ncodeunits(name) <= SEARCH_NAME_BYTE_CAPACITY ||
        throw(ArgumentError("search document name exceeds byte capacity"))
    occursin('\0', path) && throw(ArgumentError("search document path contains NUL"))
    ncodeunits(path) <= SEARCH_PATH_BYTE_CAPACITY ||
        throw(ArgumentError("search document path exceeds byte capacity"))
    return nothing
end

"""Build UUID-ordered search documents from catalog facts and authored content."""
function build_search_documents(
    descriptors::Vector{AnimationDescriptor}, content_loader::Function)

    by_id = validate_catalog(descriptors)
    documents = SearchDocument[]
    for descriptor in sort(descriptors; by=item -> string(item.id))
        path = hierarchy_path(descriptor, by_id)
        validate_document_strings(descriptor.display_name, path)
        content = descriptor.kind == TerminalNode ? nothing : content_loader(descriptor)
        content === nothing || content isa SearchContent ||
            throw(ArgumentError("sidecar returned invalid search content"))
        semantic_text = content === nothing ? "" : content.text
        aliases = content === nothing ? String[] : collect(content.aliases)
        push!(documents, SearchDocument(
            SEARCH_SOURCE_NAMESPACE, string(descriptor.id),
            UInt8(descriptor.kind), descriptor.display_name, path,
            semantic_text, aliases))
    end
    return documents
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

"""Write one canonical search document as a versioned JSON Lines record."""
function write_search_document(io::IO, document::SearchDocument)
    print(io, "{\"schema\":", SEARCH_CORPUS_SCHEMA_VERSION,
        ",\"source_namespace\":")
    write_json_string(io, document.source_namespace)
    print(io, ",\"document_id\":")
    write_json_string(io, document.document_id)
    print(io, ",\"node_kind\":", document.node_kind, ",\"display_name\":")
    write_json_string(io, document.display_name)
    print(io, ",\"hierarchy_path\":")
    write_json_string(io, document.hierarchy_path)
    print(io, ",\"semantic_text\":")
    write_json_string(io, document.semantic_text)
    print(io, ",\"aliases\":[")
    for (index, alias) in enumerate(document.aliases)
        index > 1 && print(io, ',')
        write_json_string(io, alias)
    end
    println(io, "]}")
end

"""Write the complete canonical corpus in its existing stable document order."""
function write_search_corpus(io::IO, documents::Vector{SearchDocument})
    for document in documents
        write_search_document(io, document)
    end
    return nothing
end

end