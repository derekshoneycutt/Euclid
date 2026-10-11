// Package termhyperlink owns validated terminal URI retention and activation records.
package termhyperlink

import "core:mem"
import "core:unicode/utf8"
import termmodel "../model"

HYPERLINK_REGISTRY_CAPACITY :: 64
HYPERLINK_URI_BYTE_CAPACITY :: 1024

// URI schemes accepted for user-initiated terminal hyperlink activation.
Hyperlink_Scheme :: enum u8 {
    Http,
    Https,
    Mailto,
    File,
}

// Validated scheme and byte offset of one URI's scheme-specific payload.
Hyperlink_Uri_Parse :: struct {
    scheme: Hyperlink_Scheme,
    payload_start: int,
}

// One validated URI retained without native resources.
Hyperlink_Entry :: struct {
    uri: [HYPERLINK_URI_BYTE_CAPACITY]u8,
    uri_byte_count: int,
    generation: u16,
    scheme: Hyperlink_Scheme,
}

// Terminal-owned bounded URI registry; admitted entries are never recycled.
Hyperlink_Registry :: struct {
    // Exclusively owned fixed entry storage and current terminal-lifetime occupancy.
    allocator: mem.Allocator,
    entries: []Hyperlink_Entry,
    count: int,

    // Transactional OSC 8 candidate storage owned outside the interpreter value.
    candidate: [HYPERLINK_URI_BYTE_CAPACITY]u8,
    candidate_byte_count: int,

    // Content-free admission and activation outcome totals retained for diagnostics.
    acceptance_count: u64,
    rejection_count: u64,
    activation_count: u64,
    activation_rejection_count: u64,
    acceptance_by_scheme: [Hyperlink_Scheme]u64,
    activation_by_scheme: [Hyperlink_Scheme]u64,

    // Compact inferred-link press identity; never occupies an admitted entry.
    detected_pressed_hash: u64,
    detected_pressed_line: int,
    detected_pressed_start: int,
    detected_pressed_end: int,
}

// Allocate fixed hyperlink entry storage for one terminal lifetime.
hyperlink_registry_init :: proc(
    registry: ^Hyperlink_Registry, allocator: mem.Allocator) -> bool {
    if registry == nil || len(registry.entries) != 0 {
        return false
    }
    entries, allocation_error := make(
        []Hyperlink_Entry, HYPERLINK_REGISTRY_CAPACITY, allocator)
    if allocation_error != nil {
        return false
    }
    registry^ = {allocator = allocator, entries = entries}
    return true
}

// Release registry storage and invalidate every issued handle.
hyperlink_registry_destroy :: proc(registry: ^Hyperlink_Registry) {
    if registry == nil {
        return
    }
    delete(registry.entries, registry.allocator)
    registry^ = {}
}

// Report whether a byte begins an ASCII control or whitespace code point.
hyperlink_uri_byte_rejected :: proc(byte: u8) -> bool {
    return byte <= 0x20 || byte == 0x7f
}

// Decode one exact supported URI scheme prefix.
hyperlink_uri_scheme :: proc(uri: string) -> (Hyperlink_Uri_Parse, bool) {
    bytes := transmute([]u8)uri
    schemes := [4]struct {
        text: string,
        scheme: Hyperlink_Scheme,
    }{
        {"http:", .Http}, {"https:", .Https},
        {"mailto:", .Mailto}, {"file:", .File},
    }
    for candidate in schemes {
        scheme_bytes := transmute([]u8)candidate.text
        if len(bytes) < len(scheme_bytes) {
            continue
        }
        matches := true
        for byte, index in scheme_bytes {
            if bytes[index] != byte {
                matches = false
                break
            }
        }
        if matches {
            return {
                scheme = candidate.scheme,
                payload_start = len(scheme_bytes),
            }, true
        }
    }
    return {}, false
}

// Return the end of an authority component beginning after `//`.
hyperlink_authority_end :: proc(bytes: []u8, start: int) -> int {
    end := start
    for end < len(bytes) && bytes[end] != '/' && bytes[end] != '?' &&
        bytes[end] != '#' {
        end += 1
    }
    return end
}

// Decode one ASCII hexadecimal digit; callers validate the input first.
hyperlink_hex_value :: proc(byte: u8) -> u8 {
    if byte <= '9' {
        return byte - '0'
    }
    if byte <= 'F' {
        return byte - 'A' + 10
    }
    return byte - 'a' + 10
}

// Reject file paths containing decoded dot segments or encoded separators.
hyperlink_file_path_canonical :: proc(bytes: []u8, start: int) -> bool {
    segment_length := 0
    segment_all_dots := true
    index := start + 1
    for index <= len(bytes) {
        if index == len(bytes) || bytes[index] == '/' {
            if segment_all_dots && (segment_length == 1 || segment_length == 2) {
                return false
            }
            segment_length = 0
            segment_all_dots = true
            index += 1
            continue
        }
        decoded := bytes[index]
        if decoded == '%' {
            decoded = hyperlink_hex_value(bytes[index + 1]) << 4 |
                hyperlink_hex_value(bytes[index + 2])
            if decoded == '/' || decoded == '\\' {
                return false
            }
            index += 2
        }
        segment_length += 1
        segment_all_dots = segment_all_dots && decoded == '.'
        index += 1
    }
    return true
}

// Validate supported scheme-specific authority and path requirements.
hyperlink_uri_shape_valid :: proc(
    bytes: []u8, scheme: Hyperlink_Scheme, payload_start: int) -> bool {
    if scheme == .Mailto {
        return payload_start < len(bytes)
    }
    if payload_start + 2 > len(bytes) ||
        bytes[payload_start] != '/' || bytes[payload_start + 1] != '/' {
        return false
    }
    authority_start := payload_start + 2
    authority_end := hyperlink_authority_end(bytes, authority_start)
    authority := bytes[authority_start:authority_end]
    if scheme == .File {
        local := string(authority)
        return (len(authority) == 0 || local == "localhost") &&
            authority_end < len(bytes) && bytes[authority_end] == '/' &&
            hyperlink_file_path_canonical(bytes, authority_end)
    }
    if len(authority) == 0 {
        return false
    }
    for byte in authority {
        if byte == '@' {
            return false
        }
    }
    return true
}

// Accept empty OSC 8 parameters or one bounded `id=` parameter.
hyperlink_parameters_valid :: proc(parameters: []u8) -> bool {
    if len(parameters) == 0 {
        return true
    }
    if len(parameters) < 4 || len(parameters) > 128 ||
        parameters[0] != 'i' || parameters[1] != 'd' ||
        parameters[2] != '=' {
        return false
    }
    for byte in parameters[3:] {
        if byte <= 0x20 || byte >= 0x7f || byte == ':' || byte == ';' {
            return false
        }
    }
    return true
}

// Validate one bounded absolute URI before it enters retained terminal storage.
hyperlink_uri_valid :: proc(uri: string) -> bool {
    if len(uri) == 0 || len(uri) >= HYPERLINK_URI_BYTE_CAPACITY ||
        !utf8.valid_string(uri) {
        return false
    }
    bytes := transmute([]u8)uri
    parsed, supported := hyperlink_uri_scheme(uri)
    if !supported {
        return false
    }
    for byte, index in bytes {
        if hyperlink_uri_byte_rejected(byte) {
            return false
        }
        if byte == '%' &&
            (index + 2 >= len(bytes) || !ascii_is_hex_digit(bytes[index + 1]) ||
             !ascii_is_hex_digit(bytes[index + 2])) {
            return false
        }
    }
    return hyperlink_uri_shape_valid(
        bytes, parsed.scheme, parsed.payload_start)
}

// Return whether one ASCII byte is a hexadecimal digit.
ascii_is_hex_digit :: proc(byte: u8) -> bool {
    return byte >= '0' && byte <= '9' || byte >= 'A' && byte <= 'F' ||
        byte >= 'a' && byte <= 'f'
}

// Return the stable handle for one admitted URI, reusing an exact existing entry.
hyperlink_registry_admit :: proc(
    registry: ^Hyperlink_Registry,
    uri: string) -> (termmodel.Hyperlink_Handle, bool) {
    if registry == nil || !hyperlink_uri_valid(uri) {
        if registry != nil {
            registry.rejection_count += 1
        }
        return 0, false
    }
    bytes := transmute([]u8)uri
    parsed, _ := hyperlink_uri_scheme(uri)
    for index in 0..<registry.count {
        entry := &registry.entries[index]
        if entry.uri_byte_count == len(bytes) &&
            string(entry.uri[:entry.uri_byte_count]) == uri {
            return termmodel.Hyperlink_Handle(u32(index + 1) |
                u32(entry.generation) << 16), true
        }
    }
    if registry.count >= len(registry.entries) {
        registry.rejection_count += 1
        return 0, false
    }
    index := registry.count
    entry := &registry.entries[index]
    entry.generation = 1
    entry.scheme = parsed.scheme
    copy(entry.uri[:], bytes)
    entry.uri_byte_count = len(bytes)
    registry.count += 1
    registry.acceptance_count += 1
    registry.acceptance_by_scheme[parsed.scheme] += 1
    return termmodel.Hyperlink_Handle(
        u32(index + 1) | u32(entry.generation) << 16), true
}

// Borrow the validated URI named by one current registry handle.
hyperlink_registry_uri :: proc(
    registry: ^Hyperlink_Registry,
    handle: termmodel.Hyperlink_Handle) -> (string, bool) {
    value := u32(handle)
    slot := int(value & 0xffff)
    generation := u16(value >> 16)
    if registry == nil || slot == 0 || slot > registry.count {
        return "", false
    }
    entry := &registry.entries[slot - 1]
    if entry.generation != generation {
        return "", false
    }
    return string(entry.uri[:entry.uri_byte_count]), true
}

// Borrow the NUL-terminated URI named by one current registry handle.
hyperlink_registry_cstring :: proc(
    registry: ^Hyperlink_Registry,
    handle: termmodel.Hyperlink_Handle) -> (cstring, bool) {
    value := u32(handle)
    slot := int(value & 0xffff)
    generation := u16(value >> 16)
    if registry == nil || slot == 0 || slot > registry.count {
        return nil, false
    }
    entry := &registry.entries[slot - 1]
    if entry.generation != generation {
        return nil, false
    }
    return cstring(&entry.uri[0]), true
}

// Record one display-thread activation outcome without retaining user content.
hyperlink_registry_note_activation :: proc(
    registry: ^Hyperlink_Registry, handle: termmodel.Hyperlink_Handle,
    accepted: bool) {
    value := u32(handle)
    slot := int(value & 0xffff)
    generation := u16(value >> 16)
    if registry == nil || slot == 0 || slot > registry.count ||
        registry.entries[slot - 1].generation != generation {
        if registry != nil {
            registry.activation_rejection_count += 1
        }
        return
    }
    if !accepted {
        registry.activation_rejection_count += 1
        return
    }
    registry.activation_count += 1
    registry.activation_by_scheme[registry.entries[slot - 1].scheme] += 1
}