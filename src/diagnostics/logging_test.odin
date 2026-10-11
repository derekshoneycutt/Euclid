#+test
package diagnostics

import "core:log"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"

LOGGING_TEST_PATH :: ".build/diagnostics-test.log"
LOGGING_TEST_PRODUCERS :: 4
LOGGING_TEST_RECORDS_PER_PRODUCER :: 100

Logging_Test_Producer :: struct {
    id : int,
}

// Verify zero-valued diagnostics own no sink until explicitly started.
@(test)
logging_test_disabled_by_default :: proc(t: ^testing.T) {
    state: Logging_State

    testing.expect(t, !state.enabled)
    testing.expect(t, state.file == nil)
    testing.expect(t, state.logger.procedure == nil)
}

// Emit uniquely delimited records through one inherited synchronized logger.
logging_test_producer :: proc(thread_handle: ^thread.Thread) {
    producer := (^Logging_Test_Producer)(thread_handle.data)
    for record in 0..<LOGGING_TEST_RECORDS_PER_PRODUCER {
        log.infof("producer=%d record=%d end", producer^.id, record)
    }
}

// Run and join every producer sharing the installed synchronized logger.
logging_test_run_producers :: proc(t: ^testing.T) {
    producers: [LOGGING_TEST_PRODUCERS]Logging_Test_Producer
    threads: [LOGGING_TEST_PRODUCERS]^thread.Thread
    for producer_id in 0..<LOGGING_TEST_PRODUCERS {
        producers[producer_id].id = producer_id
        threads[producer_id] = thread.create(logging_test_producer)
        testing.expect(t, threads[producer_id] != nil)
        threads[producer_id].data = &producers[producer_id]
        threads[producer_id].init_context = context
        thread.start(threads[producer_id])
    }
    for producer in threads {
        thread.join(producer)
        thread.destroy(producer)
    }
}

// Verify filtering, source metadata, correlation text, serialization, and shutdown.
@(test)
logging_test_routing_and_lifecycle :: proc(t: ^testing.T) {
    state: Logging_State
    testing.expect(t, logging_start(&state, LOGGING_TEST_PATH, .Info))
    context.logger = state.logger

    log.debug("filtered diagnostic")
    log.info("request_id=42 routed diagnostic")

    logging_test_run_producers(t)

    log.info("application_stop exit_code=0")
    context.logger = log.nil_logger()
    logging_stop(&state)
    log.info("post-shutdown diagnostic")

    content_bytes, read_error := os.read_entire_file(
        LOGGING_TEST_PATH, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(content_bytes)
    defer os.remove(LOGGING_TEST_PATH)
    content := string(content_bytes)

    testing.expect(t, !strings.contains(content, "filtered diagnostic"))
    testing.expect(t, strings.contains(content, "[euclid]"))
    testing.expect(t, strings.contains(content, "request_id=42 routed diagnostic"))
    testing.expect(t, strings.contains(content, "application_stop exit_code=0"))
    testing.expect(t, strings.contains(content, "logging_test.odin"))
    testing.expect(t, !strings.contains(content, "post-shutdown diagnostic"))
    testing.expect_value(t, strings.count(content, " end\n"),
        LOGGING_TEST_PRODUCERS * LOGGING_TEST_RECORDS_PER_PRODUCER)
}
