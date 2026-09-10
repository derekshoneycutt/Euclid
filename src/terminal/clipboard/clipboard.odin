// Package termclipboard owns validated OSC 52 clipboard actions.
package termclipboard

import "core:encoding/base64"
import "core:mem"
import "core:unicode/utf8"
import termmodel "../model"

CLIPBOARD_ACTION_CAPACITY :: 4
CLIPBOARD_TEXT_BYTE_CAPACITY :: 3072
CLIPBOARD_CANDIDATE_BYTE_CAPACITY :: 4096

// One validated terminal clipboard write awaiting display-thread publication.
Clipboard_Action :: struct {
    bytes: [CLIPBOARD_TEXT_BYTE_CAPACITY]u8,
    byte_count: int,
    producer: termmodel.Terminal_Producer,
}

// Terminal-owned bounded FIFO and transactional OSC 52 candidate storage.
Clipboard_Action_Queue :: struct {
    // Exclusively owned fixed action storage and circular queue topology.
    allocator: mem.Allocator,
    actions: []Clipboard_Action,
    start: int,
    count: int,

    // Encoded OSC candidate retained only until validation and queue admission.
    candidate: [CLIPBOARD_CANDIDATE_BYTE_CAPACITY]u8,
    candidate_byte_count: int,

    // Content-free lifetime outcomes retained for diagnostics.
    acceptance_count: u64,
    accepted_byte_count: u64,
    rejection_count: u64,
    rejected_byte_count: u64,
    stale_discard_count: u64,
    stale_discard_byte_count: u64,
    publication_count: u64,
    published_byte_count: u64,
    publication_rejection_count: u64,
}

// Allocate fixed clipboard action storage for one terminal lifetime.
clipboard_action_queue_init :: proc(
    queue: ^Clipboard_Action_Queue, allocator: mem.Allocator) -> bool {
    if queue == nil || len(queue.actions) != 0 {
        return false
    }
    actions, allocation_error := make(
        []Clipboard_Action, CLIPBOARD_ACTION_CAPACITY, allocator)
    if allocation_error != nil {
        return false
    }
    queue^ = {allocator = allocator, actions = actions}
    return true
}

// Release clipboard action storage and invalidate queued payloads.
clipboard_action_queue_destroy :: proc(queue: ^Clipboard_Action_Queue) {
    if queue == nil {
        return
    }
    delete(queue.actions, queue.allocator)
    queue^ = {}
}

// Return whether decoded UTF-8 excludes NUL and disallowed C0/C1 controls.
clipboard_text_valid :: proc(text: string) -> bool {
    offset := 0
    for offset < len(text) {
        codepoint, width := utf8.decode_rune(text[offset:])
        if codepoint < 0x20 && codepoint != '\t' && codepoint != '\n' &&
            codepoint != '\r' || codepoint >= 0x7f && codepoint <= 0x9f {
            return false
        }
        offset += width
    }
    return true
}

// Return whether one byte belongs to the standard Base64 alphabet.
clipboard_base64_value :: proc(byte: u8) -> (u8, bool) {
    if byte >= 'A' && byte <= 'Z' {
        return byte - 'A', true
    }
    if byte >= 'a' && byte <= 'z' {
        return byte - 'a' + 26, true
    }
    if byte >= '0' && byte <= '9' {
        return byte - '0' + 52, true
    }
    if byte == '+' {
        return 62, true
    }
    if byte == '/' {
        return 63, true
    }
    return 0, false
}

// Validate the alphabet and terminal padding of one Base64 byte sequence.
clipboard_base64_spelling_valid :: proc(encoded: []u8, padding: int) -> bool {
    for byte, index in encoded {
        if index >= len(encoded) - padding {
            if byte != '=' { return false }
        } else if _, valid := clipboard_base64_value(byte); !valid {
            return false
        }
    }
    return true
}

// Validate canonical padded Base64 spelling, including zero tail bits.
clipboard_base64_canonical :: proc(encoded: []u8) -> bool {
    if len(encoded) == 0 {
        return true
    }
    if len(encoded) % 4 != 0 {
        return false
    }
    padding := 0
    if encoded[len(encoded) - 1] == '=' {
        padding = 1
        if encoded[len(encoded) - 2] == '=' {
            padding = 2
        }
    }
    if !clipboard_base64_spelling_valid(encoded, padding) { return false }
    if padding == 2 {
        value, _ := clipboard_base64_value(encoded[len(encoded) - 3])
        return value & 0x0f == 0
    }
    if padding == 1 {
        value, _ := clipboard_base64_value(encoded[len(encoded) - 2])
        return value & 0x03 == 0
    }
    return true
}

// Decode and validate one canonical OSC 52 payload into caller-owned storage.
clipboard_decode_payload :: proc(
    payload: []u8, destination: []u8) -> (int, bool) {
    separator := -1
    for byte, index in payload {
        if byte == ';' {
            separator = index
            break
        }
    }
    if separator < 0 {
        return 0, false
    }
    selection := payload[:separator]
    if len(selection) != 0 && string(selection) != "c" {
        return 0, false
    }
    encoded := payload[separator + 1:]
    if len(encoded) == 1 && encoded[0] == '?' ||
        !clipboard_base64_canonical(encoded) {
        return 0, false
    }
    decoded, decode_error := base64.decode_into_buf(
        destination, string(encoded))
    if decode_error != nil || len(decoded) > CLIPBOARD_TEXT_BYTE_CAPACITY ||
        !utf8.valid_string(string(decoded)) {
        return 0, false
    }
    if !clipboard_text_valid(string(decoded)) {
        return 0, false
    }
    return len(decoded), true
}

// Validate and enqueue one complete OSC 52 candidate without partial commit.
clipboard_action_queue_admit :: proc(
    queue: ^Clipboard_Action_Queue,
    producer: termmodel.Terminal_Producer) -> bool {
    if queue == nil || queue.count >= len(queue.actions) {
        if queue != nil {
            queue.rejection_count += 1
            queue.rejected_byte_count += u64(queue.candidate_byte_count)
        }
        return false
    }
    slot := (queue.start + queue.count) % len(queue.actions)
    action := &queue.actions[slot]
    byte_count, valid := clipboard_decode_payload(
        queue.candidate[:queue.candidate_byte_count], action.bytes[:])
    if !valid {
        queue.rejection_count += 1
        queue.rejected_byte_count += u64(queue.candidate_byte_count)
        action^ = {}
        return false
    }
    action.byte_count = byte_count
    action.producer = producer
    queue.count += 1
    queue.acceptance_count += 1
    queue.accepted_byte_count += u64(byte_count)
    return true
}

// Borrow the oldest queued clipboard action without consuming it.
clipboard_action_queue_peek :: proc(
    queue: ^Clipboard_Action_Queue) -> (^Clipboard_Action, bool) {
    if queue == nil || queue.count == 0 {
        return nil, false
    }
    return &queue.actions[queue.start], true
}

// Consume the oldest queued clipboard action and clear retained content.
clipboard_action_queue_pop :: proc(queue: ^Clipboard_Action_Queue) {
    if queue == nil || queue.count == 0 {
        return
    }
    queue.actions[queue.start] = {}
    queue.start = (queue.start + 1) % len(queue.actions)
    queue.count -= 1
}
