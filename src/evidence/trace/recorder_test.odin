#+test
package evidence_trace

import "core:mem"
import "core:testing"

// Verify saturation never overwrites retained evidence and reports later loss.
@(test)
trace_test_ring_pressure_and_gap :: proc(t: ^testing.T) {
    ring: Ring
    ring_init(&ring, .Display)
    for index in 0..<TRACE_RING_CAPACITY {
        testing.expect(t, ring_record(&ring, Event{
            kind = .Point_Position_Committed,
            payload = {point = {point_index = u32(index)}},
        }))
    }
    testing.expect(t, !ring_record(&ring, Event{
        kind = .Animation_Tick_Committed,
        flags = {.Required},
    }))
    testing.expect(t, ring.required_evidence_lost)
    testing.expect(t, !ring_evidence_complete(&ring))
    testing.expect_value(t, ring.pending_drops, u64(1))

    first: [2]Event
    testing.expect_value(t, ring_drain(&ring, first[:]), 2)
    testing.expect_value(t, first[0].sequence, u64(1))
    testing.expect_value(t, first[1].sequence, u64(2))

    testing.expect(t, ring_record(&ring, Event{kind = .Runtime_Ready}))
    remainder: [TRACE_RING_CAPACITY]Event
    count := ring_drain(&ring, remainder[:])
    testing.expect_value(t, count, TRACE_RING_CAPACITY)
    testing.expect_value(t, remainder[count - 2].kind, Kind.Trace_Gap)
    testing.expect_value(t, remainder[count - 2].payload.counts.first, u32(1))
    testing.expect(t, remainder[count - 2].sequence < remainder[count - 1].sequence)
    testing.expect_value(t, remainder[count - 1].kind, Kind.Runtime_Ready)
    testing.expect_value(t, remainder[count - 1].sequence, u64(259))
}

// Verify wraparound retains owner-local order after partial draining.
@(test)
trace_test_ring_wraparound :: proc(t: ^testing.T) {
    ring: Ring
    ring_init(&ring, .Julia_Host)
    for _ in 0..<TRACE_RING_CAPACITY {
        testing.expect(t, ring_record(&ring, Event{kind = .Dynview_Published}))
    }
    drained: [128]Event
    testing.expect_value(t, ring_drain(&ring, drained[:]), len(drained))
    for _ in 0..<len(drained) {
        testing.expect(t, ring_record(&ring, Event{kind = .Dynview_Published}))
    }
    remaining: [TRACE_RING_CAPACITY]Event
    count := ring_drain(&ring, remaining[:])
    for index in 1..<count {
        testing.expect(t, remaining[index - 1].sequence < remaining[index].sequence)
    }
}

// Verify deterministic merge preserves each producer's local sequence order.
@(test)
trace_test_deterministic_merge :: proc(t: ^testing.T) {
    left := [2]Event{
        {sequence = 1, timestamp_ns = 20, producer = .Display},
        {sequence = 2, timestamp_ns = 40, producer = .Display},
    }
    right := [2]Event{
        {sequence = 1, timestamp_ns = 10, producer = .Julia_Host},
        {sequence = 2, timestamp_ns = 30, producer = .Julia_Host},
    }
    merged: [4]Event
    count := merge_events(merged[:], left[:], right[:])

    testing.expect_value(t, count, len(merged))
    testing.expect_value(t, merged[0].producer, Producer.Julia_Host)
    testing.expect_value(t, merged[1].producer, Producer.Display)
    testing.expect_value(t, merged[2].producer, Producer.Julia_Host)
    testing.expect_value(t, merged[3].producer, Producer.Display)
}

// Verify session completeness is independent of draining and export.
@(test)
trace_test_session_completeness_across_producers :: proc(t: ^testing.T) {
    display, julia_host: Ring
    ring_init(&display, .Display)
    ring_init(&julia_host, .Julia_Host)
    rings := [2]^Ring{&display, &julia_host}
    testing.expect(t, session_evidence_complete(rings[:]))

    julia_host.required_evidence_lost = true
    testing.expect(t, !session_evidence_complete(rings[:]))
}

// Verify recording, draining, and merging do not allocate through the context allocator.
@(test)
trace_test_record_drain_merge_allocate_nothing :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    previous_allocator := context.allocator
    context.allocator = mem.tracking_allocator(&tracker)
    defer context.allocator = previous_allocator

    display, julia_host: Ring
    ring_init(&display, .Display)
    ring_init(&julia_host, .Julia_Host)
    testing.expect(t, ring_record(&display, Event{kind = .Frame_Presented}))
    testing.expect(t, ring_record(&julia_host, Event{kind = .Runtime_Ready}))
    display_events, julia_events: [1]Event
    testing.expect_value(t, ring_drain(&display, display_events[:]), 1)
    testing.expect_value(t, ring_drain(&julia_host, julia_events[:]), 1)
    merged: [2]Event
    testing.expect_value(t,
        merge_events(merged[:], display_events[:], julia_events[:]), 2)
    testing.expect_value(t, tracker.total_allocation_count, i64(0))
}
