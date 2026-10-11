package evidence_trace

import "core:time"

// Fixed number of complete event records retained by one producer ring.
TRACE_RING_CAPACITY :: 256

// Producer-owned bounded circular storage with explicit loss evidence.
//
// Recording and draining are unsynchronized owner operations. Other threads may inspect
// or drain a ring only after establishing an ownership or lifecycle boundary.
Ring :: struct {
    // Inline circular storage and producer identity assigned to retained events.
    events : [TRACE_RING_CAPACITY]Event,
    producer : Producer,

    // Circular read/write positions and number of currently retained records.
    read_index : int,
    write_index : int,
    count : int,

    // Next owner-local sequence, including identities consumed by dropped events.
    next_sequence : u64,

    // Drops awaiting a synthesized Trace_Gap and sticky correctness-evidence loss.
    pending_drops : u64,
    required_evidence_lost : bool,
}

//   Initialize empty storage for one runtime producer.
//
// Parameters:
//   - ring: Destination storage owned by the calling producer.
//   - producer: Stable identity assigned to every recorded event.
//
// Side effects:
//   - Discards prior ring contents and loss state.
//
// Notes:
//   - The first recorded or dropped event receives sequence one.
ring_init :: proc(ring: ^Ring, producer: Producer) {
    ring^ = {producer = producer, next_sequence = 1}
}

//   Append one event when bounded capacity permits.
//
// Parameters:
//   - ring: Producer-owned destination.
//   - event: Primitive event; sequence and producer are assigned by the ring.
//
// Returns:
//   - True when retained; false when dropped under pressure.
//
// Side effects:
//   - Assigns producer, timestamp, and sequence metadata to the local event copy.
//   - Counts dropped events and makes required-evidence loss sticky.
//
// Notes:
//   - A missing timestamp is sampled from the monotonic process clock.
//   - Dropped events still consume owner-local sequence identities.
//   - Pending drops become one bounded Trace_Gap when two slots are available: one for
//     the gap and one for the current event. Otherwise loss remains pending.
ring_record :: proc(ring: ^Ring, event: Event) -> bool {
    event := event
    event.producer = ring.producer
    if event.timestamp_ns == 0 {
        event.timestamp_ns = u64(i64(time.tick_since({})))
    }

    if ring.count == TRACE_RING_CAPACITY {
        event.sequence = ring.next_sequence
        ring.next_sequence += 1
        ring.pending_drops += 1
        if .Required in event.flags {
            ring.required_evidence_lost = true
        }
        return false
    }

    if ring.pending_drops > 0 && ring.count < TRACE_RING_CAPACITY - 1 {
        gap := Event{
            sequence = ring.next_sequence,
            timestamp_ns = event.timestamp_ns,
            producer = ring.producer,
            lane = .Diagnostic,
            kind = .Trace_Gap,
            flags = {.Failure},
            payload = {counts = {
                first = u32(min(ring.pending_drops, u64(max(u32)))),
            }},
        }
        ring.next_sequence += 1
        ring_append(ring, gap)
        ring.pending_drops = 0
    }

    event.sequence = ring.next_sequence
    ring.next_sequence += 1
    ring_append(ring, event)
    return true
}

//   Return whether no required event has been dropped from this ring lifetime.
//
// Parameters:
//   - ring: Producer-owned storage to inspect at a synchronized boundary.
//
// Returns:
//   - False permanently after the first required event is dropped.
//
// Notes:
//   - Ordinary dropped events and pending gap emission do not by themselves make
//     required evidence incomplete.
ring_evidence_complete :: proc(ring: ^Ring) -> bool {
    return !ring.required_evidence_lost
}

//   Report completeness across synchronized producer rings.
//
// Parameters:
//   - rings: Producer rings inspected after their owner boundaries are established.
//
// Returns:
//   - True when every producer retained all required evidence.
session_evidence_complete :: proc(rings: []^Ring) -> bool {
    for ring in rings {
        if ring == nil || !ring_evidence_complete(ring) {
            return false
        }
    }
    return true
}

//   Drain retained events in owner-local sequence order.
//
// Parameters:
//   - ring: Producer-owned source.
//   - destination: Caller-owned fixed storage.
//
// Returns:
//   - Number of events copied into destination.
//
// Side effects:
//   - Removes copied events from the ring without allocating or blocking.
//
// Notes:
//   - Draining preserves owner-local sequence order and leaves excess records retained
//     when destination is smaller than the current count.
//   - Pending drop accounting and sticky required-evidence loss are not cleared.
ring_drain :: proc(ring: ^Ring, destination: []Event) -> int {
    drained := min(ring.count, len(destination))
    for index in 0..<drained {
        destination[index] = ring.events[ring.read_index]
        ring.read_index = (ring.read_index + 1) % TRACE_RING_CAPACITY
    }
    ring.count -= drained
    return drained
}

//   Merge two already ordered producer snapshots into caller-owned storage.
//
// Parameters:
//   - destination: Output storage; may truncate the merged snapshot.
//   - left: First producer's owner-local ordered events.
//   - right: Second producer's owner-local ordered events.
//
// Returns:
//   - Number of events copied.
//
// Side effects:
//   - Overwrites only the returned prefix of destination; source snapshots are unchanged.
//
// Notes:
//   - Nonzero timestamps order events across producers. Ties and absent timestamps
//     use producer then local sequence for deterministic display, not causality.
//   - Inputs must already be ordered according to the same producer-local comparison.
//     Destination truncation retains the earliest selected prefix.
merge_events :: proc(destination, left, right: []Event) -> int {
    left_index, right_index, output_index := 0, 0, 0
    for output_index < len(destination) &&
        (left_index < len(left) || right_index < len(right)) {
        take_left := right_index == len(right)
        if left_index < len(left) && right_index < len(right) {
            take_left = event_precedes(left[left_index], right[right_index])
        }
        if take_left {
            destination[output_index] = left[left_index]
            left_index += 1
        } else {
            destination[output_index] = right[right_index]
            right_index += 1
        }
        output_index += 1
    }
    return output_index
}

//   Append one event after the caller establishes available capacity.
//
// Parameters:
//   - ring: Producer-owned ring with at least one free slot.
//   - event: Fully attributed event to retain without further metadata changes.
//
// Side effects:
//   - Writes at the current circular position, advances it, and increments count.
//
// Notes:
//   - This internal helper does not enforce capacity or assign sequence metadata.
ring_append :: proc(ring: ^Ring, event: Event) {
    ring.events[ring.write_index] = event
    ring.write_index = (ring.write_index + 1) % TRACE_RING_CAPACITY
    ring.count += 1
}

//   Return deterministic merge order for two producer-local events.
//
// Parameters:
//   - left: Candidate event from the first ordered snapshot.
//   - right: Candidate event from the second ordered snapshot.
//
// Returns:
//   - True when left precedes right by timestamp, producer, and local sequence.
//
// Notes:
//   - Equal keys prefer left, preserving deterministic merge stability.
//   - This comparison establishes presentation order only and does not infer causality.
event_precedes :: proc(left, right: Event) -> bool {
    if left.timestamp_ns != 0 && right.timestamp_ns != 0 &&
        left.timestamp_ns != right.timestamp_ns {
        return left.timestamp_ns < right.timestamp_ns
    }
    if left.producer != right.producer {
        return left.producer < right.producer
    }
    return left.sequence <= right.sequence
}
