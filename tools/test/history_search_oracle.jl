#!/usr/bin/env julia

using Dates
using REPL
using SHA
using REPL.History: ConditionSet, FilterSpec, HistEntry, filterchunkrev!, matchregions

const HISTORY_SEARCH_ORACLE_CASES = (
    ("foo bar", :julia, "bar and FOO", true),
    ("foo BAR", :julia, "foo BAR", true),
    ("foo BAR", :julia, "FOO BAR", false),
    ("foo; BAR", :julia, "FOO BAR", true),
    ("=exact text", :julia, "prefix exact text suffix", true),
    ("!exclude", :julia, "keep this", true),
    ("!exclude", :julia, "exclude this", false),
    ("word\\;part", :julia, "WORD;PART", true),
    ("foo\\\\;bar", :julia, "foo\\\\;bar", true),
    ("\\=literal", :julia, "=literal", true),
    ("shell>", :shell, "ls -la", true),
    ("help>;shell>", :shell, "ls -la", true),
    ("unknown>", :julia, "source", false),
    ("unknown>;shell>", :shell, "source", true),
    ("/[", :julia, "anything", true),
    ("needle;/[", :julia, "needle here", true),
    ("needle;/[", :julia, "other", false),
    ("/(?<=\\p{Greek})(a)\\1", :julia, "λaa", true),
    ("`fb", :julia, "foo_bar", true),
    ("`fb", :julia, "afoo bar", false),
    ("`λf", :julia, "λx fy", true),
    ("~cs", :julia, "test case", true),
    ("~CS", :julia, "test case", false),
    ("~λx", :julia, "λabcx", true),
    ("~ß", :julia, "ß", true),
    ("~ẞ", :julia, "ß", false),
    ("foo ß", :julia, "FOO ß", true),
    ("foo ß", :julia, "foo ss", false),
    ("=   ", :julia, "x   y", true),
    ("!   ", :julia, "x   y", false),
    ("!   ", :julia, "x y", true),
    ("/   ", :julia, "x   y", true),
    ("=αβ;=γδ", :julia, "αβ γδ", true),
    ("=st;=test", :julia, "test", true),
    ("=test;=test", :julia, "test", true),
    ("test\\; test\\;", :julia, "test test;", true),
    ("/(?=a)|a", :julia, "a", true),
    ("/(?<=a)b", :julia, "ab", true))

"""Return Julia's REPL filter decision for one source and mode."""
function history_search_oracle_matches(query::String, mode::Symbol, source::String)
    entries = [HistEntry(mode, DateTime(2000), source, 1)]
    matches = HistEntry[]
    filterchunkrev!(matches, entries, FilterSpec(ConditionSet(query)))
    return !isempty(matches)
end

"""Convert Julia character-index ranges to Euclid's zero-based UTF-8 byte ranges."""
function history_search_oracle_ranges(source::String, query::String)
    ranges = matchregions(FilterSpec(ConditionSet(query)), source)
    return map(ranges) do range
        first_byte = first(range) - 1
        end_byte = nextind(source, last(range)) - 1
        "$first_byte-$end_byte"
    end
end

"""Write a bounded TSV corpus with the precise Julia runtime and source identity."""
function write_history_search_oracle(path::String)
    repl_path = pathof(REPL)
    history_dir = joinpath(dirname(repl_path), "History")
    source_files = [
        joinpath(history_dir, "resumablefiltering.jl"),
        joinpath(history_dir, "search.jl"),
    ]
    source_digest = bytes2hex(sha256(vcat(read.(source_files)...)))
    mkpath(dirname(path))
    open(path, "w") do output
        println(output,
            "# Julia REPL.History version=$(VERSION) source_sha256=$source_digest")
        for (query, mode, source, expected) in HISTORY_SEARCH_ORACLE_CASES
            actual = history_search_oracle_matches(query, mode, source)
            actual == expected ||
                error("Julia oracle case disagrees with its expected row")
            ranges = join(history_search_oracle_ranges(source, query), ",")
            mode_index = findfirst(==(mode), (:julia, :help, :pkg, :shell)) - 1
            println(output, join(("R", bytes2hex(codeunits(query)), string(mode_index),
                bytes2hex(codeunits(source)), actual ? "1" : "0", ranges), '\t'))
        end
    end
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("expected one output path")
    write_history_search_oracle(ARGS[1])
end
