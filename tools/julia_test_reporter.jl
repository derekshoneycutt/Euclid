#!/usr/bin/env julia

module EuclidJuliaTestReporter

using Serialization
using Test

mutable struct StructuredTestSet <: Test.AbstractTestSet
    description::String
    path::Vector{String}
    source::Union{Nothing, LineNumberNode}
    results::Vector{Any}
end

"""Create one structured testset, inheriting the parent description path."""
function (::Type{StructuredTestSet})(description::AbstractString;
    source=nothing, kwargs...)
    parent = Test.get_testset()
    inherited = parent isa StructuredTestSet ? parent.path : String[]
    path = !isempty(inherited) && inherited[end] == description ?
        copy(inherited) : [inherited; String(description)]
    return StructuredTestSet(String(description), path, source, Any[])
end

"""Retain one Julia leaf result for structured reporting."""
function Test.record(testset::StructuredTestSet,
    result::Union{Test.Pass,Test.Fail,Test.Error,Test.Broken})
    push!(testset.results, result)
    return result
end

"""Retain one completed child testset beneath its structured parent."""
function Test.record(testset::StructuredTestSet, child::Test.AbstractTestSet)
    push!(testset.results, child)
    return child
end

"""Return the stable status name for one Julia test result."""
function result_status(result)
    result isa Test.Pass && return "passed"
    result isa Test.Fail && return "failed"
    result isa Test.Error && return "error"
    return "broken"
end

"""Return source metadata carried by a result or its containing testset."""
function result_source(result, testset::StructuredTestSet)
    source = hasproperty(result, :source) ? result.source : testset.source
    source isa LineNumberNode || return (file="", line=0)
    file = String(source.file)
    return (file=isempty(file) || file == "none" ? "" : file, line=source.line)
end

"""Return a diagnostic message only for a non-passing Julia result."""
function result_message(result)
    result isa Test.Pass && return nothing
    return sprint(show, MIME("text/plain"), result)
end

"""Flatten one structured testset into stable leaf records."""
function test_records(testset::StructuredTestSet)
    records = NamedTuple[]
    for result in testset.results
        if result isa StructuredTestSet
            append!(records, test_records(result))
            continue
        end
        source = result_source(result, testset)
        expression = hasproperty(result, :orig_expr) ? string(result.orig_expr) : ""
        push!(records, (
            name=join([testset.path; expression], " > "),
            package=length(testset.path) > 1 ? testset.path[2] : testset.description,
            file=source.file,
            line=source.line,
            status=result_status(result),
            elapsed_ns=nothing,
            message=result_message(result)))
    end
    return records
end

"""Give repeated loop-generated result names stable execution-order suffixes."""
function disambiguate_records(records)
    totals = Dict{String,Int}()
    for record in records
        totals[record.name] = get(totals, record.name, 0) + 1
    end
    seen = Dict{String,Int}()
    return map(records) do record
        totals[record.name] == 1 && return record
        ordinal = get(seen, record.name, 0) + 1
        seen[record.name] = ordinal
        return merge(record, (name="$(record.name) [case $ordinal]",))
    end
end

"""Serialize the root result set, propagating nested sets to their parent."""
function Test.finish(testset::StructuredTestSet)
    if Test.get_testset_depth() > 0
        Test.record(Test.get_testset(), testset)
        return testset
    end
    records = disambiguate_records(test_records(testset))
    report_path = get(ENV, "EUCLID_JULIA_TEST_REPORT", "")
    isempty(report_path) && error("EUCLID_JULIA_TEST_REPORT is required")
    open(report_path, "w") do io
        serialize(io, records)
    end
    failed = filter(record -> record.status in ("failed", "error"), records)
    isempty(failed) || error("$(length(failed)) Julia tests failed")
    return testset
end

end

using .EuclidJuliaTestReporter: StructuredTestSet
using Test

const EUCLID_JULIA_TEST_PATH = normpath(
    joinpath(@__DIR__, "..", "src", "julia", "test"))

if abspath(PROGRAM_FILE) == @__FILE__
    @testset StructuredTestSet "EuclidApp Julia Tests" begin
        include(joinpath(EUCLID_JULIA_TEST_PATH, "runtests.jl"))
    end
end