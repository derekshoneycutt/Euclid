#+test
package inputbackend

import testing "core:testing"
import "core:thread"
import input ".."
import native "../../native"
import sdl "vendor:sdl3"

// Sdl_Event_Inbox_Test_Producer owns thread results until the test joins its worker.
Sdl_Event_Inbox_Test_Producer :: struct {
    inbox: ^Sdl_Event_Inbox,
    accepted: bool,
}

// Verify transient commit/preedit buffers and event-time modifiers survive callbacks.
@(test)
sdl_event_inbox_test_copies_transient_payloads :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.state.focused = true
    runtime: input.Input_Runtime
    platform: native.Sdl_Platform
    _ = input.input_runtime_set_text_target(&runtime, .Terminal, 0)
    key: sdl.Event = {
        type = .KEY_DOWN,
    }
    key.key = {
        scancode = .A,
        mod = {.LSHIFT},
        down = true,
    }
    key.type = .KEY_DOWN
    testing.expect(t, sdl_event_inbox_push(inbox, &key))
    bytes: [4]u8 = {'a', 'b', 'c', 0}
    text: sdl.Event = {
        type = .TEXT_INPUT,
    }
    text.text.text = cstring(&bytes[0])
    testing.expect(t, sdl_event_inbox_push(inbox, &text))
    edit: sdl.Event = {
        type = .TEXT_EDITING,
    }
    edit.edit.text, edit.edit.start, edit.edit.length = cstring(&bytes[0]), 1, 2
    testing.expect(t, sdl_event_inbox_push(inbox, &edit))
    bytes[0] = 'z'
    testing.expect(t, inbox.entries[1].event.text.text == nil)
    testing.expect(t, inbox.entries[2].event.edit.text == nil)
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    events := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(events), 3)
    testing.expect_value(t, string(events[1].text[:events[1].text_length]), "abc")
    testing.expect_value(t, string(events[2].text[:events[2].text_length]), "abc")
    testing.expect_value(t, events[2].preedit_start, i32(1))
    testing.expect_value(t, events[2].preedit_length, i32(2))
    testing.expect(t, .Shift in events[1].modifiers && .Shift in events[2].modifiers)
}

// Verify bounded queue pressure is fatal/sticky and closing makes late ingress harmless.
@(test)
sdl_event_inbox_test_queue_overflow_and_close :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    platform: native.Sdl_Platform
    event: sdl.Event = {
        type = .KEY_DOWN,
    }
    event.key.scancode, event.key.down = .A, true
    for _ in 0..<SDL_EVENT_INBOX_CAPACITY {
        testing.expect(t, sdl_event_inbox_push(inbox, &event))
    }
    testing.expect(t, !sdl_event_inbox_push(inbox, &event))
    testing.expect_value(t, inbox.count, SDL_EVENT_INBOX_CAPACITY)
    testing.expect(t, sdl_event_inbox_failed(inbox))
    testing.expect(t, !sdl_event_inbox_service(inbox, &platform))
    testing.expect(t, !sdl_event_inbox_push(inbox, &event))
    sdl_event_inbox_close(inbox)
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect_value(t, inbox.count, 0)
    testing.expect(t, sdl_event_inbox_failed(inbox))
}

// Verify copied text admits the exact bounded limit but never silently truncates.
@(test)
sdl_event_inbox_test_payload_overflow_is_sticky :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    bytes: [SDL_EVENT_INBOX_TEXT_CAPACITY + 1]u8
    for &byte in bytes[:SDL_EVENT_INBOX_TEXT_CAPACITY - 1] {
        byte = 'x'
    }
    event: sdl.Event = {
        type = .TEXT_INPUT,
    }
    event.text.text = cstring(&bytes[0])
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect_value(t, inbox.count, 1)
    bytes[SDL_EVENT_INBOX_TEXT_CAPACITY - 1] = 'x'
    testing.expect(t, !sdl_event_inbox_push(inbox, &event))
    testing.expect_value(t, inbox.count, 1)
    testing.expect(t, sdl_event_inbox_failed(inbox))
}

// Verify unrelated pointer-bearing events and other-window text are never dereferenced.
@(test)
sdl_event_inbox_test_ignores_unowned_payloads :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.window_id = 7
    event: sdl.Event = {
        type = .DROP_TEXT,
    }
    ignored: [1]u8 = {0}
    event.drop.data = cstring(&ignored[0])
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .TEXT_INPUT,
    }
    event.text.windowID = 8
    event.text.text = cstring(&ignored[0])
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect_value(t, inbox.count, 0)
    testing.expect(t, !sdl_event_inbox_failed(inbox))
}

// Verify pacing service preserves pointer edges until one accepted input drain.
@(test)
sdl_event_inbox_test_service_retains_edges :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.state.focused = true
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    event: sdl.Event = {
        type = .MOUSE_BUTTON_DOWN,
    }
    event.button.button, event.button.down, event.button.clicks = sdl.BUTTON_LEFT, true, 2
    event.button.x, event.button.y = 25, 30
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .WINDOW_RESIZED,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .MOUSE_BUTTON_UP,
    }
    event.button.button = sdl.BUTTON_LEFT
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    for _ in 0..<10 {
        testing.expect(t, sdl_event_inbox_service(inbox, &platform))
    }
    testing.expect(t, platform.resize_pending)
    testing.expect_value(t, inbox.count, 2)
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    accumulation := sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect(t, .Left in accumulation.mouse_pressed)
    testing.expect(t, .Left in accumulation.mouse_released)
    testing.expect_value(t, accumulation.mouse_left_clicks, u8(2))
    testing.expect(t, .Left not_in accumulation.mouse_down)
    next := sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, next.mouse_pressed, input.Input_Mouse_Buttons{})
    testing.expect_value(t, next.mouse_released, input.Input_Mouse_Buttons{})
}

// Verify device overflow becomes a retained ordered prefix, not portable input loss.
@(test)
sdl_event_inbox_test_large_burst_retains_order :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.read_index = SDL_EVENT_INBOX_CAPACITY - 2
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    event: sdl.Event = {
        type = .KEY_DOWN,
    }
    event.key.scancode, event.key.down = .A, true
    for _ in 0..<input.INPUT_EVENT_CAPACITY + 1 {
        testing.expect(t, sdl_event_inbox_push(inbox, &event))
    }
    event.type, event.key.down = .KEY_UP, false
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.event_count, input.INPUT_EVENT_CAPACITY)
    testing.expect_value(t, inbox.count, 2)
    testing.expect_value(t, runtime.event_overflow_count, u64(0))
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.event_count, 2)
    testing.expect_value(t, runtime.events[0].kind, input.Input_Event_Kind.Press)
    testing.expect_value(t, runtime.events[1].kind, input.Input_Event_Kind.Release)
    testing.expect_value(t, inbox.count, 0)
}

// Verify synthetic capacity pressure does not consume any queued device facts.
@(test)
sdl_event_inbox_test_injected_frame_retains_device_events :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    runtime.injected_event_count = input.INPUT_EVENT_CAPACITY
    event: sdl.Event = {
        type = .KEY_DOWN,
    }
    event.key.scancode, event.key.down = .B, true
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, inbox.count, 1)
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.event_count, 1)
    testing.expect_value(t, runtime.events[0].key, input.Input_Key.B)
    testing.expect_value(t, runtime.event_overflow_count, u64(0))
}

// Verify focus loss cancels IME in order, releases held buttons and gates later text.
@(test)
sdl_event_inbox_test_focus_cancels_ordered_composition :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.state.focused = true
    inbox.state.mouse_down = {.Left}
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    _ = input.input_runtime_set_text_target(&runtime, .Terminal, 0)
    event: sdl.Event = {
        type = .TEXT_EDITING,
    }
    event.edit.text = "abc"
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .WINDOW_FOCUS_LOST,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .TEXT_INPUT,
    }
    event.text.text = "ignored"
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, sdl_event_inbox_service(inbox, &platform))
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    accumulation := sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.event_count, 2)
    testing.expect_value(t, runtime.events[0].kind, input.Input_Event_Kind.Text_Preedit)
    testing.expect_value(t, runtime.events[1].kind, input.Input_Event_Kind.Text_Cancel)
    testing.expect_value(t, runtime.text_target.kind, input.Input_Text_Target_Kind.None)
    testing.expect(t, !accumulation.focused)
    testing.expect(t, .Left in accumulation.mouse_released)
    testing.expect(t, .Left not_in accumulation.mouse_down)
}

// Verify loading drains input with nil runtime, leaving only current owner state.
@(test)
sdl_event_inbox_test_loading_services_without_runtime :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    platform: native.Sdl_Platform
    event: sdl.Event = {
        type = .WINDOW_FOCUS_LOST,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .WINDOW_FOCUS_GAINED,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .MOUSE_MOTION,
    }
    event.motion.x, event.motion.y = 23, 45
    for _ in 0..<SDL_EVENT_INBOX_CAPACITY * 2 {
        testing.expect(t, sdl_event_inbox_push(inbox, &event))
    }
    testing.expect_value(t, inbox.count, 3)
    event = {
        type = .QUIT,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, sdl_event_inbox_service(inbox, &platform, loading = true))
    testing.expect(t, platform.close_requested && inbox.state.focused)
    testing.expect_value(t, inbox.state.mouse_position.x, f32(23))
    testing.expect_value(t, inbox.count, 0)
    testing.expect(t, !sdl_event_inbox_failed(inbox))
}

// Verify lifecycle compaction across ring wrap does not reorder retained key edges.
@(test)
sdl_event_inbox_test_lifecycle_compaction_wraps :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.read_index = SDL_EVENT_INBOX_CAPACITY - 1
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    event: sdl.Event = {
        type = .WINDOW_RESIZED,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .KEY_DOWN,
    }
    event.key.scancode, event.key.down = .A, true
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .QUIT,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .KEY_UP,
    }
    event.key.scancode = .A
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, sdl_event_inbox_service(inbox, &platform))
    testing.expect(t, platform.close_requested && platform.resize_pending)
    testing.expect_value(t, inbox.count, 2)
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.events[0].kind, input.Input_Event_Kind.Press)
    testing.expect_value(t, runtime.events[1].kind, input.Input_Event_Kind.Release)
}

// Verify absent text remains absent while an empty preedit still ends composition.
@(test)
sdl_event_inbox_test_preserves_nil_and_empty_text :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    inbox.state.focused = true
    platform: native.Sdl_Platform
    runtime: input.Input_Runtime
    _ = input.input_runtime_set_text_target(&runtime, .Terminal, 0)
    event: sdl.Event = {
        type = .TEXT_INPUT,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .TEXT_EDITING,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event.edit.text = ""
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = sdl_event_inbox_drain(&platform, &runtime, inbox)
    testing.expect_value(t, runtime.event_count, 1)
    testing.expect_value(t, runtime.events[0].kind, input.Input_Event_Kind.Text_Preedit)
    testing.expect_value(t, runtime.events[0].text_length, u8(0))
}

// sdl_event_inbox_test_produce proves ingress does not require an Odin context.
sdl_event_inbox_test_produce :: proc "contextless" (
    inbox: ^Sdl_Event_Inbox) -> bool {
    event: sdl.Event = {
        type = .KEY_DOWN,
    }
    event.key.scancode, event.key.down = .A, true
    for _ in 0..<input.INPUT_EVENT_CAPACITY {
        if !sdl_event_inbox_push(inbox, &event) {
            return false
        }
    }
    return true
}

// sdl_event_inbox_test_worker submits only contextless input before publishing results.
sdl_event_inbox_test_worker :: proc(worker: ^thread.Thread) {
    producer := (^Sdl_Event_Inbox_Test_Producer)(worker.data)
    producer^.accepted = sdl_event_inbox_test_produce(producer^.inbox)
}

// Verify concurrent callback producers synchronize admission without losing events.
@(test)
sdl_event_inbox_test_concurrent_producers :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    producers: [2]Sdl_Event_Inbox_Test_Producer
    workers: [2]^thread.Thread
    for &worker, index in workers {
        producers[index].inbox = inbox
        worker = thread.create(sdl_event_inbox_test_worker)
        testing.expect(t, worker != nil)
        if worker != nil {
            worker.data = &producers[index]
            thread.start(worker)
        }
    }
    for worker in workers {
        if worker != nil {
            thread.join(worker)
            thread.destroy(worker)
        }
    }
    testing.expect(t, producers[0].accepted && producers[1].accepted)
    testing.expect_value(t, inbox.count, 2 * input.INPUT_EVENT_CAPACITY)
    testing.expect(t, !sdl_event_inbox_failed(inbox))
}

// Verify window filtering reads the event's active SDL member for each input family.
@(test)
sdl_event_inbox_test_filters_active_window_members :: proc(t: ^testing.T) {
    events: [7]sdl.Event
    events[0].window = {
        windowID = 7,
    }
    events[0].type = .WINDOW_RESIZED
    events[1].key = {
        windowID = 7,
    }
    events[1].type = .KEY_DOWN
    events[2].text = {
        windowID = 7,
    }
    events[2].type = .TEXT_INPUT
    events[3].edit = {
        windowID = 7,
    }
    events[3].type = .TEXT_EDITING
    events[4].motion = {
        windowID = 7,
    }
    events[4].type = .MOUSE_MOTION
    events[5].button = {
        windowID = 7,
    }
    events[5].type = .MOUSE_BUTTON_UP
    events[6].wheel = {
        windowID = 7,
    }
    events[6].type = .MOUSE_WHEEL
    for &event in events {
        testing.expect(t, sdl_event_inbox_relevant(&event, 7))
        testing.expect(t, !sdl_event_inbox_relevant(&event, 8))
    }
}

// Verify lifecycle service leaves flags sticky and metrics transactionally untouched.
@(test)
sdl_event_inbox_test_service_preserves_metrics_and_flags :: proc(t: ^testing.T) {
    inbox := new(Sdl_Event_Inbox, context.allocator)
    defer free(inbox, context.allocator)
    platform: native.Sdl_Platform
    metrics := platform.metrics
    event: sdl.Event = {
        type = .WINDOW_PIXEL_SIZE_CHANGED,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    event = {
        type = .WINDOW_CLOSE_REQUESTED,
    }
    testing.expect(t, sdl_event_inbox_push(inbox, &event))
    testing.expect(t, sdl_event_inbox_service(inbox, &platform))
    testing.expect(t, platform.resize_pending && platform.close_requested)
    testing.expect(t, sdl_event_inbox_service(inbox, &platform))
    testing.expect(t, platform.resize_pending && platform.close_requested)
    testing.expect_value(t, platform.metrics, metrics)
}
