module HighlightingServiceTests

using Test
using Main: EuclidHost, EuclidPolicy, EuclidActorRuntime, EuclidReplEvaluation

const H = EuclidReplEvaluation.SyntaxHighlighting
const P = EuclidPolicy
const A = EuclidActorRuntime

"""Construct a complete source/cache identity, with overrides for rejection fixtures."""
function identity(
    request=1; generation=1, target_id=0, revision=1, faces=1, target=0, mode=0)
    return P.HighlightIdentity(
        request, generation, target_id, revision, faces, target, mode)
end

"""Create isolated host actors without entering native display state."""
function host(; highlight_function=H.highlight_source)
    return EuclidHost.create_host_runtime(
        C_NULL, 100f0, 100f0; highlight_function)
end

"""Pump bounded actor turns to make admitted highlighting requests ready."""
pump(runtime) = EuclidHost.pump_for_host(runtime, Int32(128), UInt64(1_000_000_000))

"""Submit one fixture and return its ready native command."""
function resolve(runtime, id, source="x")
    EuclidHost.ingest_highlight_for_host(runtime, id, source)
    pump(runtime)
    return EuclidHost.take_highlight_for_host(runtime)
end

"""Assert a terminal failure preserves the exact identity and carries no success payload."""
function test_failure(command, id, reason)
    @test command.kind == 2
    @test command.identity == id
    @test command.failure_reason == Int32(reason)
    @test isempty(command.source) && isempty(command.runs)
end

"""Raise a deterministic adapter error without depending on Julia face customization."""
broken_adapter(_source) = throw(ArgumentError("fixture adapter failure"))

"""Return a malformed success-shaped adapter result for atomic rejection coverage."""
malformed_adapter(_source) = H.HighlightRun[]

@testset "native ABI layout and limits" begin
    @test isbitstype(P.HighlightIdentity)
    @test sizeof(P.HighlightIdentity) == 48
    @test fieldoffset.(Ref(P.HighlightIdentity), 1:7) == UInt[0, 8, 16, 24, 32, 40, 44]
    @test isbitstype(EuclidHost.NativeHighlightRun)
    @test sizeof(EuclidHost.NativeHighlightRun) == 28
    @test fieldoffset.(Ref(EuclidHost.NativeHighlightRun), 1:13) ==
        UInt[0, 4, 8, 12, 16, 20, 21, 22, 23, 24, 25, 26, 27]
    @test H.MAX_SOURCE_BYTES == 65536 && H.MAX_STYLE_RUNS == 4096
    @test P.HIGHLIGHT_MAILBOX_CAPACITY == 8
end

@testset "complete source and live/history identity survive host egress" begin
    runtime = host()
    for id in (identity(), identity(2; target=1, target_id=17, revision=8, faces=3))
        source = "α = \"🙂\"\0\n"
        command = resolve(runtime, id, source)
        @test command.kind == 1 && command.failure_reason == 0
        @test command.identity == id
        @test command.source == source
        @test command.source_byte_count == ncodeunits(source)
        @test first(command.runs).start_byte == 0
        @test last(command.runs).end_byte == ncodeunits(source)
        @test !haskey(runtime.actors.pending_requests, P.highlight_request_key(id))
        @test EuclidHost.take_highlight_for_host(runtime).kind == 0
    end
    empty = resolve(runtime, identity(3), "")
    @test empty.kind == 1 && isempty(empty.runs)
end

@testset "invalid mode, source, target, and stopped generation" begin
    runtime = host()
    for id in (
        identity(0), identity(; target=2), identity(; target_id=3),
        identity(; target=1), identity(; revision=0), identity(; faces=0),
        identity(; mode=1), identity(; mode=2), identity(; mode=3),
        identity(; mode=typemax(Int32)))
        test_failure(resolve(runtime, id), id, P.HighlightInvalidRequest)
    end
    for source in ("x" ^ (H.MAX_SOURCE_BYTES + 1), String(UInt8[0xff]))
        test_failure(resolve(runtime, identity(), source),
            identity(), P.HighlightInvalidRequest)
    end
    stale = identity(; generation=2)
    test_failure(resolve(runtime, stale), stale, P.HighlightRuntimeStopped)
    A.stop!(runtime.actors, runtime.highlight_service)
    test_failure(resolve(runtime, identity()), identity(), P.HighlightActorStopped)
end

@testset "duplicate ownership and independent completion correlation" begin
    runtime = host()
    id = identity(41)
    EuclidHost.ingest_completion_preview_for_host(
        runtime, id.request_id, "printl", Int32(6))
    EuclidHost.ingest_highlight_for_host(runtime, id, "# comment")
    EuclidHost.ingest_highlight_for_host(runtime, id, "different source")
    test_failure(EuclidHost.take_highlight_for_host(runtime),
        id, P.HighlightDuplicateRequest)
    pump(runtime)
    result = EuclidHost.take_highlight_for_host(runtime)
    @test result.kind == 1 && result.source == "# comment"
    @test EuclidHost.take_completion_for_host(runtime).request_id == id.request_id
    @test EuclidHost.take_highlight_for_host(runtime).kind == 0
    @test A.pending_request_count(runtime.actors) == 0
end

@testset "mailbox saturation resolves only the rejected registration" begin
    runtime = host()
    for request in 1:P.HIGHLIGHT_MAILBOX_CAPACITY
        EuclidHost.ingest_highlight_for_host(runtime, identity(request), "x")
    end
    rejected = identity(P.HIGHLIGHT_MAILBOX_CAPACITY + 1)
    EuclidHost.ingest_highlight_for_host(runtime, rejected, "x")
    test_failure(EuclidHost.take_highlight_for_host(runtime),
        rejected, P.HighlightMailboxFull)
    @test A.pending_request_count(runtime.actors) == P.HIGHLIGHT_MAILBOX_CAPACITY
    pump(runtime)
    for request in 1:P.HIGHLIGHT_MAILBOX_CAPACITY
        result = EuclidHost.take_highlight_for_host(runtime)
        @test result.kind == 1 && result.identity == identity(request)
    end
    @test A.pending_request_count(runtime.actors) == 0
end

@testset "adapter failure and malformed success become one failure" begin
    for adapter in (broken_adapter, malformed_adapter)
        runtime = host(; highlight_function=adapter)
        id = identity()
        test_failure(resolve(runtime, id), id, P.HighlightInternalFailure)
        @test isempty(runtime.actors.failures)
        @test A.pending_request_count(runtime.actors) == 0
        @test EuclidHost.take_highlight_for_host(runtime).kind == 0
    end
end

@testset "session close waits for terminal outcomes before quiescence" begin
    runtime = host()
    pending = identity(1)
    ready = identity(2)
    @test resolve(runtime, ready).kind == 1
    EuclidHost.ingest_highlight_for_host(runtime, pending, "x")
    @test EuclidHost.close_session_for_host(runtime, UInt64(1))
    pump(runtime)
    @test runtime.session.phase === EuclidHost.HostSessionClosing
    test_failure(EuclidHost.take_highlight_for_host(runtime),
        pending, P.HighlightRuntimeStopped)
    A.take_outgoing!(runtime.actors)
    pump(runtime)
    @test runtime.session.phase === EuclidHost.HostSessionQuiescent
    @test !A.is_live(runtime.actors, runtime.highlight_service)
    @test EuclidHost.start_session_for_host(runtime, UInt64(2))
    test_failure(resolve(runtime, pending), pending, P.HighlightRuntimeStopped)
    next = identity(1; generation=2)
    @test resolve(runtime, next).identity == next
end

@testset "shutdown rejects queued and future requests exactly once" begin
    runtime = host()
    id = identity()
    EuclidHost.ingest_highlight_for_host(runtime, id, "x")
    EuclidHost.request_shutdown_for_host(runtime)
    test_failure(EuclidHost.take_highlight_for_host(runtime),
        id, P.HighlightRuntimeStopped)
    @test !haskey(runtime.actors.pending_requests, P.highlight_request_key(id))
    next = identity(2)
    test_failure(resolve(runtime, next), next, P.HighlightRuntimeStopped)
    for _ in 1:32
        A.take_outgoing!(runtime.actors)
        pump(runtime).shutdown_ready && break
    end
    @test !A.is_live(runtime.actors, runtime.highlight_service)
    @test EuclidHost.take_highlight_for_host(runtime).kind == 0
end

end
