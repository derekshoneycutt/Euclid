using Test

include(joinpath(@__DIR__, "..", "evidence.jl"))
using .EuclidEvidence

"""Write one little-endian integer to a binary fixture."""
function write_little_endian(io::IO, value)
    write(io, htol(value))
end

"""Write one canonical fixed-width evidence event fixture."""
function write_event(io::IO, sequence::UInt64; kind::UInt16=UInt16(64),
    producer::UInt8=UInt8(3), lane::UInt8=UInt8(2), flags::UInt16=UInt16(0))
    for value in (sequence, UInt64(10), UInt64(20), UInt64(30), UInt64(40),
        UInt64(50))
        write_little_endian(io, value)
    end
    write(io, producer, lane, UInt8(3), UInt8(0))
    write_little_endian(io, kind)
    write_little_endian(io, flags)
    write_little_endian(io, UInt32(60))
    write_little_endian(io, UInt32(70))
end

"""Create a minimal canonical evidence bundle for tool tests."""
function write_bundle(directory::AbstractString)
    mkpath(directory)
    write(joinpath(directory, "manifest.json"), """
        {"schema_version":1,"result":"passed","reason":"complete",\
        "failed_step":0,"trace_complete":true,"last_trace_sequence":3,\
        "artifacts":{"trace":"evidence.bin","state":"state.json",\
        "allocations":"allocations.json"}}""")
    write(joinpath(directory, "state.json"), """
        {"runtime_generation":2,"animation_generation":3,\
        "animation_tick_sequence":4,"animation_last_committed_sequence":5}""")
    write(joinpath(directory, "allocations.json"), """
        {"live_allocations":0,"current_bytes":0,"peak_bytes":8,\
        "total_allocations":1,"bad_frees":0}""")
    open(joinpath(directory, "evidence.bin"), "w") do io
        write(io, EuclidEvidence.TRACE_MAGIC)
        write_little_endian(io, UInt16(1))
        write_little_endian(io, UInt16(64))
        write_event(io, UInt64(1))
        write_event(io, UInt64(2); kind=UInt16(184), flags=UInt16(2))
        write_event(io, UInt64(3))
    end
end

@testset "evidence capabilities and schema" begin
    @test "select_animation" in EuclidEvidence.capabilities().actions
    @test "inject_reload_failure" in EuclidEvidence.capabilities().actions
    @test "animation_cycle_boundary" in EuclidEvidence.scenario_schema().events
    @test "animation_tick_committed" in EuclidEvidence.scenario_schema().events
    @test "animation_loaded" in EuclidEvidence.scenario_schema().events
    @test "dynview_published" in EuclidEvidence.scenario_schema().events
    @test EuclidEvidence.capabilities().trace_event_bytes == 64
end

@testset "evidence bundle inspection" begin
    mktempdir() do directory
        write_bundle(directory)
        bundle = EuclidEvidence.inspect_bundle(directory)
        @test bundle.event_count == 3
        @test bundle.manifest.trace_complete

        tail = EuclidEvidence.query_trace(joinpath(directory, "evidence.bin"); limit=2)
        @test getproperty.(tail, :sequence) == UInt64[2, 3]

        trace_path = joinpath(directory, "evidence.bin")
        filters = (correlation=UInt64(20), generation=UInt64(30),
            kind="animation_tick_committed", producer="animation", lane="domain")
        @test EuclidEvidence.resolve_query_trace_path(directory) == trace_path
        @test EuclidEvidence.resolve_query_trace_path(trace_path) == trace_path
        @test EuclidEvidence.query_trace(
            EuclidEvidence.resolve_query_trace_path(directory); filters...) ==
            EuclidEvidence.query_trace(
                EuclidEvidence.resolve_query_trace_path(trace_path); filters...)

        failures = EuclidEvidence.query_trace(
            joinpath(directory, "evidence.bin"); failures=true)
        @test length(failures) == 1
        @test only(failures).kind == "constraint_solve_failed"
        @test only(failures).payload.type == "counts"

        summary = EuclidEvidence.bundle_summary(directory)
        @test summary.result == "passed"
        @test summary.bad_frees == 0
        @test length(summary.failure_events) == 1
    end
end

@testset "evidence rejects malformed bundles" begin
    mktempdir() do directory
        write_bundle(directory)
        open(joinpath(directory, "evidence.bin"), "a") do io
            write(io, UInt8(0))
        end
        @test_throws ErrorException EuclidEvidence.inspect_bundle(directory)
        @test_throws ErrorException EuclidEvidence.query_trace(
            joinpath(directory, "evidence.bin"))
    end

    mktemp() do path, io
        write(io, zeros(UInt8, EuclidEvidence.TRACE_HEADER_BYTES))
        close(io)
        @test_throws ErrorException EuclidEvidence.query_trace(path)
    end

    mktempdir() do directory
        write_bundle(directory)
        rm(joinpath(directory, "state.json"))
        @test_throws ErrorException EuclidEvidence.inspect_bundle(directory)
    end

    mktempdir() do directory
        write_bundle(directory)
        manifest_path = joinpath(directory, "manifest.json")
        manifest = replace(read(manifest_path, String),
            "\"last_trace_sequence\":3" => "\"last_trace_sequence\":2")
        write(manifest_path, manifest)
        @test_throws ErrorException EuclidEvidence.inspect_bundle(directory)
    end

    mktempdir() do directory
        write_bundle(directory)
        @test_throws ErrorException EuclidEvidence.query_trace(
            joinpath(directory, "evidence.bin"); kind="not_an_event")
    end

    mktempdir() do directory
        write_bundle(directory)
        manifest_path = joinpath(directory, "manifest.json")
        manifest = replace(read(manifest_path, String),
            "\"trace_complete\":true" => "\"trace_complete\":false")
        write(manifest_path, manifest)
        @test_throws ErrorException EuclidEvidence.inspect_bundle(directory)
    end
end
