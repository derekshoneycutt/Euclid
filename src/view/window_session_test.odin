package view

import testing "core:testing"
import thread "core:thread"
import julia "../bridge"
import bridgemodel "../bridge/model"

// Verify empty partial startup can be destroyed repeatedly without manufacturing a runtime failure.
@(test)
window_session_empty_cleanup_preserves_result :: proc(t: ^testing.T) {
    owner := new(Window_Session, context.allocator)
    defer free(owner, context.allocator)
    testing.expect_value(t, window_session_destroy(owner), 0)
    testing.expect_value(t, window_session_destroy(owner), 0)
    owner^.draw_ready = true
    testing.expect_value(t, window_session_release_runtime(owner), 0)
    owner^.failed = true
    testing.expect_value(t, window_session_release_runtime(owner), 1)
}

// window_startup_test_worker models a host still waiting for its first startup control.
window_startup_test_worker :: proc(worker: ^thread.Thread) {
    service := cast(^bridgemodel.Julia_Runtime_Service)worker.data
    for {
        message, available := julia.communication_link_try_recv(&service^.request_link)
        if !available {
            thread.yield()
            continue
        }
        request, shutdown := message^.(bridgemodel.Runtime_Shutdown_Requested)
        assert(shutdown)
        request_id := request.request_id
        assert(julia.communication_link_return(&service^.request_link, message))
        outcome := julia.send_typed_julia_completion(service, {
            protocol = .Runtime_Shutdown,
            request_kind = .Shutdown,
            request_id = request_id,
        }, {
            kind = .Shutdown_Complete,
            request_kind = .Shutdown,
            request_id = request_id,
            succeeded = true,
        })
        assert(outcome == .Sent)
        return
    }
}

// window_startup_test_start lends only stable service storage to the test host.
window_startup_test_start :: proc(data: rawptr) -> ^thread.Thread {
    worker := thread.create(window_startup_test_worker)
    if worker != nil {
        worker.data = data
        worker.init_context = context
        thread.start(worker)
    }
    return worker
}

// Verify close before runtime-state admission sends shutdown before joining the host worker.
@(test)
window_session_close_before_julia_initialization :: proc(t: ^testing.T) {
    owner := new(Window_Session, context.allocator)
    defer free(owner, context.allocator)
    service, err := julia.create_julia_runtime_service_with_worker(
        context.allocator, "", nil, window_startup_test_start)
    testing.expect(t, err == .None && service != nil)
    if service == nil {
        return
    }
    owner^.runtime.julia_service = service
    testing.expect_value(t, window_session_release_runtime(owner), 0)
    testing.expect(t, owner^.runtime.julia_service == nil)
    testing.expect_value(t, window_session_release_runtime(owner), 0)
}
