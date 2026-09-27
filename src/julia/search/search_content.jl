module EuclidSearchContent

export SEARCH_ALIAS_BYTE_CAPACITY, SEARCH_ALIAS_COUNT_CAPACITY,
    SEARCH_TEXT_BYTE_CAPACITY, SearchContent

const SEARCH_TEXT_BYTE_CAPACITY = 8 * 1024
const SEARCH_ALIAS_COUNT_CAPACITY = 16
const SEARCH_ALIAS_BYTE_CAPACITY = 128

"""Authored semantic language used to discover one catalog entry."""
struct SearchContent
    text::String
    aliases::Tuple{Vararg{String}}

    """Construct one bounded immutable semantic-search value."""
    function SearchContent(text::String, aliases::Tuple{Vararg{String}})
        _validate_search_text(text)
        _validate_search_aliases(aliases)
        return new(text, aliases)
    end
end

"""Reject semantic prose that is empty, contains NUL, or exceeds its byte bound."""
function _validate_search_text(text::String)
    isempty(strip(text)) && throw(ArgumentError("search text must not be empty"))
    occursin('\0', text) && throw(ArgumentError("search text must not contain NUL"))
    ncodeunits(text) <= SEARCH_TEXT_BYTE_CAPACITY ||
        throw(ArgumentError("search text exceeds byte capacity"))
    return nothing
end

"""Reject aliases that violate count, byte, content, or uniqueness bounds."""
function _validate_search_aliases(aliases::Tuple{Vararg{String}})
    length(aliases) <= SEARCH_ALIAS_COUNT_CAPACITY ||
        throw(ArgumentError("search aliases exceed count capacity"))
    canonical_aliases = Set{String}()
    for alias in aliases
        canonical = lowercase(strip(alias))
        isempty(canonical) && throw(ArgumentError("search alias must not be empty"))
        occursin('\0', alias) && throw(ArgumentError("search alias must not contain NUL"))
        ncodeunits(alias) <= SEARCH_ALIAS_BYTE_CAPACITY ||
            throw(ArgumentError("search alias exceeds byte capacity"))
        canonical in canonical_aliases &&
            throw(ArgumentError("search aliases must be unique"))
        push!(canonical_aliases, canonical)
    end
    return nothing
end

end