#+test
package evidence_export

import trace "../trace"

import "core:testing"

// Verify the exact version-one typed JSONL envelope and stable event spelling.
@(test)
jsonl_test_representative_event_contract :: proc(t: ^testing.T) {
    event := trace.Event{
        sequence = 7,
        producer = .Display,
        lane = .Lifecycle,
        correlation_kind = .Runtime_Request,
        correlation = 42,
        generation = 3,
        tick = 9,
        revision = 2,
        kind = .Runtime_Ready,
        flags = {.Required},
        payload = {counts = {first = 4, second = 5}},
    }
    actual := jsonl_event("run-test", event)
    expected := "{\"schema\":\"euclid.semantic-evidence\",\"version\":1," +
        "\"event\":\"runtime.ready\",\"seq\":7,\"run_id\":\"run-test\"," +
        "\"producer\":1,\"lane\":1,\"correlation_kind\":1," +
        "\"correlation\":42,\"generation\":3,\"tick\":9,\"revision\":2," +
        "\"flags\":1,\"payload_a\":4,\"payload_b\":5}\n"
    testing.expect_value(t, actual, expected)
}
