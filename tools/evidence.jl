#!/usr/bin/env julia

module EuclidEvidence

using JSON3

const TRACE_MAGIC = UInt8['E', 'U', 'C', 'L']
const TRACE_HEADER_BYTES = 8
const TRACE_EVENT_BYTES = 64
const TRACE_SCHEMA_VERSION = 1
const ARTIFACT_SCHEMA_VERSION = 1
const DEFAULT_QUERY_LIMIT = 100
const MAX_QUERY_LIMIT = 1_000
const REQUIRED_ARTIFACTS = ("evidence.bin", "state.json", "allocations.json")
const REQUIRED_STATE_FIELDS = (
    :runtime_generation, :animation_generation, :animation_tick_sequence,
    :animation_last_committed_sequence)
const REQUIRED_ALLOCATION_FIELDS = (
    :live_allocations, :current_bytes, :peak_bytes, :total_allocations, :bad_frees)

const PRODUCER_NAMES = Dict{UInt8,String}(
    0 => "unknown", 1 => "display", 2 => "julia_host", 3 => "animation",
    4 => "simulation", 5 => "constraint_worker", 6 => "particle_worker",
    7 => "frame_preparation", 8 => "scenario", 9 => "shape_cache_worker",
    10 => "dynview_worker")

const LANE_NAMES = Dict{UInt8,String}(
    0 => "unknown", 1 => "lifecycle", 2 => "domain", 3 => "transport",
    4 => "presentation", 5 => "scenario", 6 => "diagnostic")

const CORRELATION_KIND_NAMES = Dict{UInt8,String}(
    0 => "none", 1 => "runtime_request", 2 => "animation",
    3 => "animation_tick", 4 => "scene_batch", 5 => "fixed_step",
    6 => "task", 7 => "capture", 8 => "checkpoint",
    9 => "scenario_action", 10 => "text")

const EVENT_NAMES = Dict{UInt16,String}(
    0 => "unknown", 1 => "session_started", 2 => "session_configured",
    3 => "session_finished", 4 => "trace_gap", 20 => "runtime_starting",
    21 => "runtime_ready", 22 => "runtime_reload_started",
    23 => "runtime_reload_committed", 24 => "runtime_reload_rolled_back",
    25 => "runtime_shutdown_started", 26 => "runtime_shutdown_complete",
    60 => "animation_reset_requested", 61 => "animation_reset_committed",
    62 => "animation_selected", 63 => "animation_tick_accepted",
    64 => "animation_tick_committed", 65 => "animation_tick_rejected",
    66 => "animation_cycle_boundary", 120 => "scene_batch_published",
    121 => "scene_batch_committed", 122 => "scene_batch_rejected",
    123 => "scene_command_rejected", 180 => "point_position_committed",
    181 => "point_style_committed", 182 => "point_visibility_committed",
    183 => "constraint_solve_completed", 184 => "constraint_solve_failed",
    260 => "pen_joint_committed", 261 => "pen_active_committed",
    262 => "pen_visibility_committed", 263 => "compass_joint_committed",
    264 => "compass_active_committed", 265 => "compass_visibility_committed",
    320 => "particle_emission_committed", 321 => "particle_emission_rejected",
    360 => "frame_presented", 361 => "dynview_published",
    362 => "capture_requested", 363 => "capture_completed",
    364 => "capture_failed", 365 => "gif_started", 366 => "gif_completed",
    367 => "gif_failed", 368 => "shape_cache_prepared",
    369 => "dynview_compiled", 420 => "checkpoint_requested",
    421 => "checkpoint_stored", 422 => "checkpoint_unavailable",
    423 => "checkpoint_evicted", 460 => "scenario_started",
    461 => "scenario_action_issued", 462 => "scenario_wait_satisfied",
    463 => "scenario_assertion_passed", 464 => "scenario_assertion_failed",
    465 => "scenario_passed", 466 => "scenario_failed",
    467 => "scenario_inconclusive", 520 => "allocation_checkpoint",
    521 => "allocation_baseline_matched", 522 => "allocation_baseline_mismatched",
    523 => "allocation_bad_free")

const POINT_EVENT_KINDS = Set(UInt16[180, 181, 182])
const REQUEST_EVENT_KINDS = Set(UInt16[65, 122, 123])
const HANDLE_EVENT_KINDS = Set(UInt16[421, 423])

const SCENARIO_ACTIONS = [
    "reset_animation", "select_animation", "reload_runtime", "scratchpad",
    "pause_simulation", "resume_simulation", "screenshot", "start_gif",
    "stop_gif", "wait_event", "wait_state", "assert_state", "checkpoint",
    "allocation_checkpoint", "assert_allocation_baseline",
    "assert_no_bad_frees", "shutdown"]

const SCENARIO_EVENTS = [
    "runtime_ready", "runtime_reload_committed", "runtime_reload_rolled_back",
    "animation_selected", "animation_cycle_boundary", "scene_batch_committed",
    "constraint_solve_completed", "dynview_published", "frame_presented",
    "capture_completed", "gif_completed", "checkpoint_stored",
    "runtime_shutdown_complete"]

const SCENARIO_STATES = [
    "runtime_ready", "runtime_idle", "animation_idle", "scratchpad_idle",
    "simulation_paused", "simulation_running", "dynview_enabled",
    "gif_active", "gif_idle"]

struct TraceEvent
    sequence::UInt64
    timestamp_ns::UInt64
    correlation::UInt64
    generation::UInt64
    tick::UInt64
    revision::UInt64
    producer::UInt8
    lane::UInt8
    correlation_kind::UInt8
    kind::UInt16
    flags::UInt16
    payload_first::UInt32
    payload_second::UInt32
end

"""Return the stable machine-readable evidence and scenario capabilities."""
function capabilities()
    return (
        schema_version=1,
        artifact_schema_version=ARTIFACT_SCHEMA_VERSION,
        trace_schema_version=TRACE_SCHEMA_VERSION,
        trace_event_bytes=TRACE_EVENT_BYTES,
        actions=SCENARIO_ACTIONS,
        events=SCENARIO_EVENTS,
        states=SCENARIO_STATES,
        captures=["screenshot", "gif", "trace", "state", "allocations", "manifest"],
        query_limit=MAX_QUERY_LIMIT)
end

"""Return the public bounded JSON Lines scenario schema."""
function scenario_schema()
    return (
        schema_version=1,
        format="jsonl",
        maximum_commands=128,
        maximum_source_bytes=64 * 1024,
        maximum_line_bytes=1024,
        maximum_text_bytes=256,
        maximum_name_bytes=64,
        maximum_timeout_ms=60_000,
        actions=SCENARIO_ACTIONS,
        events=SCENARIO_EVENTS,
        states=SCENARIO_STATES,
        optional_fields=["as", "correlation", "timeout_ms"])
end

"""Read one fixed-width little-endian trace event."""
function read_event(io::IO)
    sequence = ltoh(read(io, UInt64))
    timestamp_ns = ltoh(read(io, UInt64))
    correlation = ltoh(read(io, UInt64))
    generation = ltoh(read(io, UInt64))
    tick = ltoh(read(io, UInt64))
    revision = ltoh(read(io, UInt64))
    producer = read(io, UInt8)
    lane = read(io, UInt8)
    correlation_kind = read(io, UInt8)
    read(io, UInt8)
    kind = ltoh(read(io, UInt16))
    flags = ltoh(read(io, UInt16))
    payload_first = ltoh(read(io, UInt32))
    payload_second = ltoh(read(io, UInt32))
    return TraceEvent(sequence, timestamp_ns, correlation, generation, tick,
        revision, producer, lane, correlation_kind, kind, flags,
        payload_first, payload_second)
end

"""Return a compact stable JSON representation of one trace event."""
function event_record(event::TraceEvent)
    return (
        sequence=event.sequence,
        timestamp_ns=event.timestamp_ns,
        producer_id=event.producer,
        producer=get(PRODUCER_NAMES, event.producer, "unknown"),
        lane_id=event.lane,
        lane=get(LANE_NAMES, event.lane, "unknown"),
        kind_id=event.kind,
        kind=get(EVENT_NAMES, event.kind, "unknown"),
        correlation_kind_id=event.correlation_kind,
        correlation_kind=get(
            CORRELATION_KIND_NAMES, event.correlation_kind, "unknown"),
        correlation=event.correlation,
        generation=event.generation,
        tick=event.tick,
        revision=event.revision,
        flags=event.flags,
        payload=payload_record(event))
end

"""Decode one event's fixed payload according to its semantic kind."""
function payload_record(event::TraceEvent)
    first = event.payload_first
    second = event.payload_second
    if event.kind in POINT_EVENT_KINDS
        return (type="point", point_index=first, field=UInt16(second & 0xffff),
            visible=UInt8((second >> 16) & 0xff))
    elseif event.kind in REQUEST_EVENT_KINDS
        return (type="request", status=UInt16(first & 0xffff),
            reason=UInt16(first >> 16), slot=second)
    elseif event.kind in HANDLE_EVENT_KINDS
        return (type="handle", slot=UInt16(first & 0xffff),
            generation=UInt16(first >> 16), flags=UInt16(second & 0xffff))
    end
    return (type="counts", first, second)
end

"""Validate and return the canonical manifest for one evidence bundle."""
function read_manifest(directory::AbstractString)
    path = joinpath(directory, "manifest.json")
    isfile(path) || error("missing artifact: manifest.json")
    manifest = JSON3.read(read(path, String))
    manifest.schema_version == ARTIFACT_SCHEMA_VERSION || error(
        "unsupported manifest schema: $(manifest.schema_version)")
    manifest.result in ("passed", "failed", "inconclusive") || error(
        "unsupported manifest result: $(manifest.result)")
    String(manifest.artifacts.trace) == "evidence.bin" || error(
        "manifest trace artifact must be evidence.bin")
    String(manifest.artifacts.state) == "state.json" || error(
        "manifest state artifact must be state.json")
    String(manifest.artifacts.allocations) == "allocations.json" || error(
        "manifest allocations artifact must be allocations.json")
    for filename in REQUIRED_ARTIFACTS
        isfile(joinpath(directory, filename)) || error("missing artifact: $filename")
    end
    return manifest
end

"""Read and validate one canonical trace header."""
function read_trace_header(io::IO)
    read(io, 4) == TRACE_MAGIC || error("invalid trace magic")
    schema_version = Int(ltoh(read(io, UInt16)))
    event_size = Int(ltoh(read(io, UInt16)))
    schema_version == TRACE_SCHEMA_VERSION || error(
        "unsupported trace schema: $schema_version")
    event_size == TRACE_EVENT_BYTES || error("unsupported event size: $event_size")
    return (; schema_version, event_size)
end

"""Return whether one event satisfies all requested query filters."""
function event_matches(event::TraceEvent; correlation=nothing, generation=nothing,
    kind=nothing, producer=nothing, lane=nothing, failures::Bool=false)
    checks = (
        correlation === nothing || event.correlation == correlation,
        generation === nothing || event.generation == generation,
        kind === nothing || get(EVENT_NAMES, event.kind, "unknown") == kind,
        producer === nothing || get(
            PRODUCER_NAMES, event.producer, "unknown") == producer,
        lane === nothing || get(LANE_NAMES, event.lane, "unknown") == lane,
        !failures || event.flags & UInt16(2) != 0)
    return all(checks)
end

"""Reject an unknown optional query name before scanning the trace."""
function validate_query_name(value, names, description::AbstractString)
    value === nothing && return nothing
    value in values(names) || error("unknown $description: $value")
    return nothing
end

"""Scan a validated trace while retaining only a bounded matching tail."""
function query_trace(path::AbstractString; correlation=nothing, generation=nothing,
    kind=nothing, producer=nothing, lane=nothing, failures::Bool=false,
    limit::Int=DEFAULT_QUERY_LIMIT)
    1 <= limit <= MAX_QUERY_LIMIT || throw(ArgumentError("invalid query limit"))
    validate_query_name(kind, EVENT_NAMES, "event kind")
    validate_query_name(producer, PRODUCER_NAMES, "producer")
    validate_query_name(lane, LANE_NAMES, "lane")
    file_size = filesize(path)
    file_size >= TRACE_HEADER_BYTES || error("truncated trace header")
    (file_size - TRACE_HEADER_BYTES) % TRACE_EVENT_BYTES == 0 || error(
        "trace payload is not record-aligned")
    return open(path, "r") do io
        read_trace_header(io)
        retained = TraceEvent[]
        while !eof(io)
            event = read_event(io)
            event_matches(event; correlation, generation, kind, producer, lane,
                failures) || continue
            length(retained) == limit && popfirst!(retained)
            push!(retained, event)
        end
        return event_record.(retained)
    end
end

"""Validate a complete bundle and return its canonical documents and event count."""
function inspect_bundle(directory::AbstractString)
    manifest = read_manifest(directory)
    trace_path = joinpath(directory, String(manifest.artifacts.trace))
    state_path = joinpath(directory, String(manifest.artifacts.state))
    allocations_path = joinpath(directory, String(manifest.artifacts.allocations))
    for path in (trace_path, state_path, allocations_path)
        isfile(path) || error("manifest references missing artifact: $(basename(path))")
    end
    state = JSON3.read(read(state_path, String))
    allocations = JSON3.read(read(allocations_path, String))
    all(haskey(state, field) for field in REQUIRED_STATE_FIELDS) || error(
        "state artifact is missing required fields")
    all(haskey(allocations, field) for field in REQUIRED_ALLOCATION_FIELDS) || error(
        "allocations artifact is missing required fields")
    event_count, last_sequence = open(trace_path, "r") do io
        read_trace_header(io)
        payload_bytes = filesize(trace_path) - TRACE_HEADER_BYTES
        payload_bytes % TRACE_EVENT_BYTES == 0 || error(
            "trace payload is not record-aligned")
        count = payload_bytes ÷ TRACE_EVENT_BYTES
        sequence = UInt64(0)
        for _ in 1:count
            sequence = read_event(io).sequence
        end
        return count, sequence
    end
    UInt64(manifest.last_trace_sequence) == last_sequence || error(
        "manifest last trace sequence does not match evidence.bin")
    manifest.result == "passed" && !manifest.trace_complete && error(
        "passing bundle has an incomplete trace")
    return (; manifest, state, allocations, event_count)
end

"""Return a compact operational summary of one validated evidence bundle."""
function bundle_summary(directory::AbstractString)
    bundle = inspect_bundle(directory)
    failures = query_trace(joinpath(directory, "evidence.bin"); failures=true)
    return (
        result=bundle.manifest.result,
        reason=bundle.manifest.reason,
        failed_step=bundle.manifest.failed_step,
        trace_complete=bundle.manifest.trace_complete,
        last_trace_sequence=bundle.manifest.last_trace_sequence,
        event_count=bundle.event_count,
        runtime_generation=bundle.state.runtime_generation,
        animation_generation=bundle.state.animation_generation,
        animation_tick_sequence=bundle.state.animation_tick_sequence,
        animation_last_committed_sequence=
            bundle.state.animation_last_committed_sequence,
        bad_frees=bundle.allocations.bad_frees,
        failure_events=failures)
end

"""Write concise command usage for the evidence CLI."""
function usage(io::IO=stdout)
    println(io, "Usage: julia tools/evidence.jl COMMAND [ARGUMENTS]")
    println(io, "Commands: capabilities, schema, manifest BUNDLE, summary BUNDLE")
    println(io, "          query BUNDLE [--kind=NAME] [--producer=NAME] [--lane=NAME]")
    println(io, "                       [--correlation=ID] [--generation=ID]")
    println(io, "                       [--failures] [--limit=N]")
end

"""Parse one bounded trace query and print its matching event tail."""
function run_query(arguments::Vector{String})
    isempty(arguments) && return 2
    directory = first(arguments)
    options = Dict{Symbol,Any}(:failures => false, :limit => DEFAULT_QUERY_LIMIT)
    for argument in arguments[2:end]
        if argument == "--failures"
            options[:failures] = true
        elseif startswith(argument, "--correlation=")
            options[:correlation] = parse(UInt64, split(argument, "="; limit=2)[2])
        elseif startswith(argument, "--generation=")
            options[:generation] = parse(UInt64, split(argument, "="; limit=2)[2])
        elseif startswith(argument, "--limit=")
            options[:limit] = parse(Int, split(argument, "="; limit=2)[2])
        elseif startswith(argument, "--kind=")
            options[:kind] = split(argument, "="; limit=2)[2]
        elseif startswith(argument, "--producer=")
            options[:producer] = split(argument, "="; limit=2)[2]
        elseif startswith(argument, "--lane=")
            options[:lane] = split(argument, "="; limit=2)[2]
        else
            error("unknown query option: $argument")
        end
    end
    inspect_bundle(directory)
    println(JSON3.write(query_trace(joinpath(directory, "evidence.bin"); options...)))
    return 0
end

"""Run one argument-free discovery command."""
function run_discovery_command(command::AbstractString)
    records = Dict("capabilities" => capabilities, "schema" => scenario_schema)
    handler = get(records, command, nothing)
    handler === nothing && return nothing
    println(JSON3.write(handler()))
    return 0
end

"""Run one command that consumes exactly one evidence bundle path."""
function run_bundle_command(command::AbstractString, directory::AbstractString)
    handlers = Dict(
        "manifest" => path -> inspect_bundle(path).manifest,
        "summary" => bundle_summary)
    handler = get(handlers, command, nothing)
    handler === nothing && return nothing
    println(JSON3.write(handler(directory)))
    return 0
end

"""Run one evidence command and emit machine-readable JSON."""
function main(arguments::Vector{String}=collect(ARGS))
    isempty(arguments) && (usage(stderr); return 2)
    command = first(arguments)
    rest = arguments[2:end]
    isempty(rest) && (status = run_discovery_command(command)) !== nothing &&
        return status
    length(rest) == 1 &&
        (status = run_bundle_command(command, only(rest))) !== nothing && return status
    command == "query" && return run_query(rest)
    usage(stderr)
    return 2
end

"""Run the CLI boundary with concise process-style error reporting."""
function cli_main(arguments::Vector{String}=collect(ARGS))
    return try
        main(arguments)
    catch error_value
        println(stderr, sprint(showerror, error_value))
        1
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(cli_main())
end

end
