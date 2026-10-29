package inputbackend

import "core:sync"
import input ".."
import native "../../native"
import sdl "vendor:sdl3"

// Fixed callback ingress limits; excess events or payload bytes are fatal, not truncated.
SDL_EVENT_INBOX_CAPACITY :: 1024
SDL_EVENT_INBOX_TEXT_CAPACITY :: 256

// Sdl_Queued_Event owns transient SDL text; stored event text pointers stay nil.
Sdl_Queued_Event :: struct {
    event: sdl.Event,
    text: [SDL_EVENT_INBOX_TEXT_CAPACITY]u8,
    text_present: bool,
}

// Sdl_Event_Inbox is fixed application-owner storage; never copy it after first use.
// The mutex protects ingress, draining, failure and closing. State is display-applied.
// Initialize before enabling callbacks; close and quiesce callbacks before retirement.
Sdl_Event_Inbox :: struct {
    mutex: sync.Mutex,
    entries: [SDL_EVENT_INBOX_CAPACITY]Sdl_Queued_Event,
    read_index: int,
    count: int,
    window_id: sdl.WindowID,
    overflowed: bool,
    closing: bool,
    state: Sdl_Input_Accumulation,
}

// sdl_event_inbox_init samples initial state on the display owner before callbacks.
// Storage must be fresh/zeroed, at its final address, and not concurrently accessible.
sdl_event_inbox_init :: proc(
    inbox: ^Sdl_Event_Inbox, platform: ^native.Sdl_Platform) {
    inbox^.window_id = sdl.GetWindowID(platform^.window)
    inbox^.state.focused = .INPUT_FOCUS in sdl.GetWindowFlags(platform^.window)
    inbox^.state.modifiers = sdl_input_modifiers(sdl.GetModState())
    inbox^.state.mouse_down = sdl_input_mouse_buttons(sdl.GetMouseState(
        &inbox^.state.mouse_position.x, &inbox^.state.mouse_position.y))
}

// sdl_event_inbox_relevant filters before touching any transient event payload.
sdl_event_inbox_relevant :: proc "contextless" (
    event: ^sdl.Event, window_id: sdl.WindowID) -> bool {
    #partial switch event^.type {
    case .QUIT:
        return true
    case .WINDOW_CLOSE_REQUESTED, .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED,
         .WINDOW_DISPLAY_SCALE_CHANGED, .WINDOW_FOCUS_GAINED, .WINDOW_FOCUS_LOST:
        return event^.window.windowID == window_id
    case .KEY_DOWN, .KEY_UP:
        return event^.key.windowID == window_id
    case .TEXT_INPUT:
        return event^.text.windowID == window_id
    case .TEXT_EDITING:
        return event^.edit.windowID == window_id
    case .MOUSE_MOTION:
        return event^.motion.windowID == window_id
    case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
        return event^.button.windowID == window_id
    case .MOUSE_WHEEL:
        return event^.wheel.windowID == window_id
    }
    return false
}

// sdl_event_inbox_copy_text copies at most one fixed payload including its terminator.
// False means the complete native payload cannot fit; no truncated event is admitted.
sdl_event_inbox_copy_text :: proc "contextless" (
    destination: ^Sdl_Queued_Event, source: cstring) -> bool {
    if source == nil {
        return true
    }
    bytes := cast([^]u8)source
    for index in 0..<len(destination^.text) {
        destination^.text[index] = bytes[index]
        if bytes[index] == 0 {
            return true
        }
    }
    return false
}

// sdl_event_inbox_store owns relevant event bytes without retaining SDL text pointers.
sdl_event_inbox_store :: proc "contextless" (
    destination: ^Sdl_Queued_Event, event: ^sdl.Event) -> bool {
    destination^ = {event = event^}
    if event^.type == .TEXT_INPUT {
        destination^.event.text.text = nil
        destination^.text_present = event^.text.text != nil
        return sdl_event_inbox_copy_text(destination, event^.text.text)
    }
    if event^.type == .TEXT_EDITING {
        destination^.event.edit.text = nil
        destination^.text_present = event^.edit.text != nil
        return sdl_event_inbox_copy_text(destination, event^.edit.text)
    }
    return true
}

// sdl_event_inbox_push is allocation/context-free ingress, including foreign threads.
// True includes ignored unrelated events and harmless callbacks after close.
// False requires termination.
// Queue/payload overflow is sticky: subsequent relevant events are rejected, not lost
// silently. SDL retains ownership of the source; all borrowed bytes are copied here.
// Adjacent motion samples coalesce to their latest level/position, never across edges.
sdl_event_inbox_push :: proc "contextless" (
    inbox: ^Sdl_Event_Inbox, event: ^sdl.Event) -> bool {
    if inbox == nil || event == nil {
        return false
    }
    sync.mutex_lock(&inbox^.mutex)
    defer sync.mutex_unlock(&inbox^.mutex)
    if inbox^.closing {
        return true
    }
    if !sdl_event_inbox_relevant(event, inbox^.window_id) {
        return true
    }
    if !inbox^.overflowed && inbox^.count > 0 && event^.type == .MOUSE_MOTION {
        previous := (inbox^.read_index + inbox^.count - 1) % len(inbox^.entries)
        if inbox^.entries[previous].event.type == .MOUSE_MOTION {
            inbox^.entries[previous].event = event^
            return true
        }
    }
    if inbox^.overflowed || inbox^.count == len(inbox^.entries) {
        inbox^.overflowed = true
        return false
    }
    index := (inbox^.read_index + inbox^.count) % len(inbox^.entries)
    if !sdl_event_inbox_store(&inbox^.entries[index], event) {
        inbox^.overflowed = true
        return false
    }
    inbox^.count += 1
    return true
}

// sdl_event_inbox_failed reads sticky fatal input loss under the ingress mutex.
// The app owner must terminate on true, including while pacing or loading.
sdl_event_inbox_failed :: proc "contextless" (inbox: ^Sdl_Event_Inbox) -> bool {
    sync.mutex_lock(&inbox^.mutex)
    defer sync.mutex_unlock(&inbox^.mutex)
    return inbox^.overflowed
}

// sdl_event_inbox_apply lends owned text only while synchronously translating it.
sdl_event_inbox_apply :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    queued: ^Sdl_Queued_Event, window_id: sdl.WindowID,
    accumulation: ^Sdl_Input_Accumulation) {
    event := queued^.event
    if event.type == .TEXT_INPUT && queued^.text_present {
        event.text.text = cstring(&queued^.text[0])
    } else if event.type == .TEXT_EDITING && queued^.text_present {
        event.edit.text = cstring(&queued^.text[0])
    }
    sdl_platform_handle_event(platform, runtime, &event, window_id, accumulation)
}

// sdl_event_inbox_drain applies an ordered prefix only on the display owner.
// Caller begins runtime's frame first. Full portable storage retains the remaining
// native events for a later accepted frame, including when injected events fill it.
// A nil runtime is loading-only: lifecycle/pointer state applies, input is discarded.
sdl_event_inbox_drain :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    inbox: ^Sdl_Event_Inbox) -> Sdl_Input_Accumulation {
    sync.mutex_lock(&inbox^.mutex)
    defer sync.mutex_unlock(&inbox^.mutex)
    accumulation := inbox^.state
    if inbox^.closing || inbox^.overflowed {
        platform^.close_requested = true
        return accumulation
    }
    for inbox^.count > 0 {
        if runtime != nil && runtime^.event_count >= input.INPUT_EVENT_CAPACITY {
            break
        }
        sdl_event_inbox_apply(platform, runtime,
            &inbox^.entries[inbox^.read_index], inbox^.window_id, &accumulation)
        inbox^.read_index = (inbox^.read_index + 1) % len(inbox^.entries)
        inbox^.count -= 1
    }
    inbox^.state = {
        modifiers = accumulation.modifiers,
        focused = accumulation.focused,
        mouse_position = accumulation.mouse_position,
        mouse_down = accumulation.mouse_down,
    }
    return accumulation
}

// sdl_event_inbox_lifecycle identifies events safe to apply ahead of retained input.
// Focus stays in input order so IME cancellation cannot overtake preceding commits.
sdl_event_inbox_lifecycle :: proc "contextless" (event: ^sdl.Event) -> bool {
    return event^.type == .QUIT || event^.type == .WINDOW_CLOSE_REQUESTED ||
        event^.type == .WINDOW_RESIZED || event^.type == .WINDOW_PIXEL_SIZE_CHANGED ||
        event^.type == .WINDOW_DISPLAY_SCALE_CHANGED
}

// sdl_event_inbox_service_locked compacts retained input without reordering it.
// Loading applies/discards all events because no application target exists yet.
sdl_event_inbox_service_locked :: proc(
    inbox: ^Sdl_Event_Inbox, platform: ^native.Sdl_Platform, loading: bool) -> bool {
    if inbox^.overflowed {
        return false
    }
    if inbox^.closing {
        return true
    }
    retained := 0
    for offset in 0..<inbox^.count {
        index := (inbox^.read_index + offset) % len(inbox^.entries)
        queued := &inbox^.entries[index]
        if loading || sdl_event_inbox_lifecycle(&queued^.event) {
            sdl_event_inbox_apply(platform, nil, queued,
                inbox^.window_id, &inbox^.state)
        } else {
            destination := (inbox^.read_index + retained) % len(inbox^.entries)
            if destination != index {
                inbox^.entries[destination] = queued^
            }
            retained += 1
        }
    }
    inbox^.count = retained
    inbox^.state.diagnostics = {}
    inbox^.state.mouse_pressed = {}
    inbox^.state.mouse_released = {}
    inbox^.state.mouse_left_clicks = 0
    inbox^.state.mouse_wheel_delta = 0
    return true
}

// sdl_event_inbox_service runs on the display owner before pacing/target admission.
// It applies close/resize only, preserving ordered input until an accepted frame.
// Loading drains input too; false means sticky queue/payload overflow (terminate).
sdl_event_inbox_service :: proc(
    inbox: ^Sdl_Event_Inbox, platform: ^native.Sdl_Platform,
    loading: bool = false) -> bool {
    sync.mutex_lock(&inbox^.mutex)
    defer sync.mutex_unlock(&inbox^.mutex)
    return sdl_event_inbox_service_locked(inbox, platform, loading)
}

// sdl_input_callback_frame begins/drains/publishes exactly one accepted owner frame.
// Never call during a pacing skip, nor combine with SDL polling in callback mode.
// Nil runtime supports loading lifecycle service without creating an input frame.
sdl_input_callback_frame :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    inbox: ^Sdl_Event_Inbox) -> input.Input_Frame {
    if runtime != nil && !input.input_runtime_begin_frame(runtime) {
        return {}
    }
    accumulation := sdl_event_inbox_drain(platform, runtime, inbox)
    native.sdl_platform_service_accessibility(platform, accumulation.focused)
    if runtime == nil {
        return {}
    }
    return sdl_input_finish_frame(platform, runtime, accumulation)
}

// sdl_event_inbox_close joins current ingress and discards queued bytes before teardown.
// Later pushes are successful no-ops. No allocation/destructor is needed; retain the
// stable inbox through RunApp return (SDL_Quit), not merely through AppQuit.
// Never zero/reinitialize storage while callbacks can still access its mutex.
sdl_event_inbox_close :: proc "contextless" (inbox: ^Sdl_Event_Inbox) {
    sync.mutex_lock(&inbox^.mutex)
    defer sync.mutex_unlock(&inbox^.mutex)
    inbox^.closing = true
    inbox^.count = 0
}
