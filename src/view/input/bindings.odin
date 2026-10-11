package input

// Report whether a frame contains a key event of one kind.
input_key_event_present :: proc(
    frame: Input_Frame, key: Input_Key, kind: Input_Event_Kind) -> bool {
    for event in frame.events {
        if event.kind == kind && event.key == key {
            return true
        }
    }
    return false
}

// Report whether a key has a press edge in this frame.
input_key_pressed :: proc(frame: Input_Frame, key: Input_Key) -> bool {
    return input_key_event_present(frame, key, .Press)
}

// Report whether a key has a release edge in this frame.
input_key_released :: proc(frame: Input_Frame, key: Input_Key) -> bool {
    return input_key_event_present(frame, key, .Release)
}

// Report whether one pressed key event contains every required modifier.
input_chord_pressed :: proc(
    frame: Input_Frame, key: Input_Key, required: Input_Modifiers) -> bool {
    for event in frame.events {
        if event.kind == .Press && event.key == key &&
            required & event.modifiers == required {
            return true
        }
    }
    return false
}

// Report whether a key was pressed or auto-repeated this frame.
input_key_pressed_or_repeat :: proc(frame: Input_Frame, key: Input_Key) -> bool {
    return input_key_event_present(frame, key, .Press) ||
        input_key_event_present(frame, key, .Repeat)
}

// Resolve the first active semantic chord pressed in deterministic event order.
input_registry_action_pressed :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame,
    reserved_global_only: bool) -> (Input_Hotkey_Match, bool) {
    if runtime == nil {
        return {}, false
    }
    for event, event_index in frame.events {
        if event.kind != .Press {
            continue
        }
        for binding in runtime.active_bindings[:runtime.active_binding_count] {
            if reserved_global_only && binding.scope != .Reserved_Global {
                continue
            }
            if event.key == binding.key && event.modifiers == binding.modifiers {
                return {action = binding.action, event_index = event_index}, true
            }
        }
    }
    return {}, false
}

// Remove one consumed event while preserving the order of all remaining input.
input_frame_remove_event :: proc(frame: Input_Frame, event_index: int) -> Input_Frame {
    if event_index < 0 || event_index >= len(frame.events) {
        return frame
    }
    result := frame
    for index in event_index..<len(result.events) - 1 {
        result.events[index] = result.events[index + 1]
    }
    result.events = result.events[:len(result.events) - 1]
    for &event in result.events {
        if !event.correlation.valid {
            continue
        }
        partner_index := int(event.correlation.partner_index)
        if partner_index == event_index {
            event.correlation = {}
        } else if partner_index > event_index {
            event.correlation.partner_index -= 1
        }
    }
    return result
}
