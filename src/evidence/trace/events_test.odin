#+test
package evidence_trace

import "core:testing"

// Verify the serialized schema keeps its fixed primitive layout and stable discriminants.
@(test)
trace_test_event_schema :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(Event), TRACE_EVENT_SIZE_BYTES)
    testing.expect_value(t, size_of(Event_Payload), 8)
    testing.expect_value(t, TRACE_SCHEMA_VERSION, u16(1))
    testing.expect_value(t, u16(Kind.Session_Started), u16(1))
    testing.expect_value(t, u16(Kind.Animation_Tick_Committed), u16(64))
    testing.expect_value(t, u16(Kind.Scene_Batch_Published), u16(120))
    testing.expect_value(t, u16(Kind.Checkpoint_Stored), u16(421))
    testing.expect_value(t, u16(Kind.Allocation_Bad_Free), u16(523))
}

// Verify correlation keeps an existing identity domain, value, and generation.
@(test)
trace_test_identity_is_primitive :: proc(t: ^testing.T) {
    identity := Identity{
        kind = .Animation_Tick,
        id = 17,
        generation = 4,
    }

    testing.expect_value(t, identity.kind, Correlation_Kind.Animation_Tick)
    testing.expect_value(t, identity.id, u64(17))
    testing.expect_value(t, identity.generation, u64(4))

    event := Event{
        correlation = identity.id,
        generation = identity.generation,
        correlation_kind = identity.kind,
    }
    testing.expect(t, event_correlates(event, identity))
    testing.expect(t, !event_correlates(event,
        Identity{kind = .Animation_Tick, id = 17, generation = 5}))
}
