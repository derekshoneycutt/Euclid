"""Clear all cached parse/compile entries."""
function clear_cache!()
    empty!(PARSE_CACHE)
    empty!(PARSE_CACHE_ORDER)
    return nothing
end

"""Return current cache entry count."""
cache_size() = length(PARSE_CACHE)

"""Return hard cache-entry limit used for automatic eviction."""
cache_max_entries() = PARSE_CACHE_MAX_ENTRIES

"""Drop one cached key from insertion-order bookkeeping if present."""
function cache_order_remove_key!(key::Tuple{String, Int32, Int32})
    index = findfirst(isequal(key), PARSE_CACHE_ORDER)
    if index !== nothing
        deleteat!(PARSE_CACHE_ORDER, index)
    end
    return nothing
end

"""Mark one cache key as most recently inserted/resolved."""
function cache_order_touch_key!(key::Tuple{String, Int32, Int32})
    cache_order_remove_key!(key)
    push!(PARSE_CACHE_ORDER, key)
    return nothing
end

"""Trim cache entries so at most `limit` entries remain."""
function prune_cache!(limit::Integer=PARSE_CACHE_MAX_ENTRIES)
    target = max(0, Int(limit))
    while length(PARSE_CACHE_ORDER) > target
        stale_key = popfirst!(PARSE_CACHE_ORDER)
        delete!(PARSE_CACHE, stale_key)
    end
    return cache_size()
end

"""Drop all cached entries for one exact source string."""
function invalidate_cache_for_source!(source::AbstractString)
    source_text = String(source)
    stale_keys = Tuple{String, Int32, Int32}[]
    for key in keys(PARSE_CACHE)
        if key[1] == source_text
            push!(stale_keys, key)
        end
    end

    for key in stale_keys
        delete!(PARSE_CACHE, key)
        cache_order_remove_key!(key)
    end
    return length(stale_keys)
end

"""Drop all cached entries for one style-profile id."""
function invalidate_cache_for_style!(style_profile::Integer)
    style_id = Int32(style_profile)
    stale_keys = Tuple{String, Int32, Int32}[]
    for key in keys(PARSE_CACHE)
        if key[3] == style_id
            push!(stale_keys, key)
        end
    end

    for key in stale_keys
        delete!(PARSE_CACHE, key)
        cache_order_remove_key!(key)
    end
    return length(stale_keys)
end

"""Drop all cached entries for one parser grammar version id."""
function invalidate_cache_for_grammar!(grammar_version::Integer)
    grammar_id = Int32(grammar_version)
    stale_keys = Tuple{String, Int32, Int32}[]
    for key in keys(PARSE_CACHE)
        if key[2] == grammar_id
            push!(stale_keys, key)
        end
    end

    for key in stale_keys
        delete!(PARSE_CACHE, key)
        cache_order_remove_key!(key)
    end
    return length(stale_keys)
end
