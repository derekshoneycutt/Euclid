package input

/* TODO: Commented out because we didn't bring over the full terminal module etc yet
import gfxprotocol "../../terminal/graphics/protocol"
import termemulator "../../terminal/emulator"
import termmodel "../../terminal/model"
import termpalette "../../terminal/palette"

import "core:unicode/utf8"

INPUT_TERMINAL_ORDINARY_KEY_CODEPOINTS ::
    " ',-./0123456789;=abcdefghijklmnopqrstuvwxyz[\\]`"
#assert(len(INPUT_TERMINAL_ORDINARY_KEY_CODEPOINTS) ==
    int(Input_Key.Grave) - int(Input_Key.Space) + 1)

// Outcome of attempting one negotiated keyboard-protocol encoding.
Input_Protocol_Key_Outcome :: enum {
    Not_Applicable,
    Consumed,
    Blocked,
}

// Interpreter-owned modes used while encoding one terminal input frame.
Input_Terminal_Encoding_Mode :: struct {
    terminal: termmodel.Terminal_Input_Mode,
    modify_other_keys_level: u8,
    kitty_keyboard_flags: u8,
}

// Canonical Kitty number and final byte for one functional key.
Input_Terminal_Kitty_Functional_Key :: struct {
    number: int,
    final:  u8,
}

// Validated frame-local run of committed text associated with one physical key.
Input_Terminal_Kitty_Associated_Text :: struct {
    start: int,
    count: int,
    available: bool,
}

// Enqueue one complete string without exposing ring storage.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - sequence: Nonempty byte string copied before return.
//
// Returns:
//   - True when the complete sequence enters the queue; false for invalid input or
//     insufficient capacity.
//
// Side effects:
//   - Appends atomically through the runtime queue and updates its pressure accounting.
input_terminal_enqueue_string :: proc(
    runtime: ^Input_Runtime, sequence: string) -> bool {
    return input_runtime_enqueue_bytes(runtime, transmute([]u8)sequence)
}

// Atomically admit one bounded clipboard payload and optional DEC wrappers.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving the paste transaction.
//   - text: Clipboard bytes copied without interpretation.
//   - bracketed: Whether to surround the payload with DEC 2004 delimiters.
//
// Returns:
//   - True when the complete payload and required wrappers fit; false without partial
//     admission when runtime is nil, the payload is oversized, or capacity is short.
//
// Notes:
//   - Clipboard bytes that resemble bracket delimiters remain ordinary payload bytes.
//
// Side effects:
//   - Appends the complete paste transaction and increments exactly one paste admission
//     or rejection counter for a non-nil runtime.
input_terminal_enqueue_paste :: proc(
    runtime: ^Input_Runtime, text: string, bracketed: bool) -> bool {
    if runtime == nil {
        return false
    }
    maximum := len(runtime.byte_queue)
    if bracketed {
        maximum = INPUT_PASTE_MAX_BYTES
    }
    if len(text) > maximum {
        runtime.paste_rejection_count += 1
        return false
    }
    prefix := ""
    suffix := ""
    if bracketed {
        prefix = "\e[200~"
        suffix = "\e[201~"
    }
    total := len(prefix) + len(text) + len(suffix)
    if total > len(runtime.byte_queue) - runtime.byte_queue_count {
        runtime.paste_rejection_count += 1
        return false
    }
    input_runtime_enqueue_bytes(runtime, transmute([]u8)prefix)
    input_runtime_enqueue_bytes(runtime, transmute([]u8)text)
    input_runtime_enqueue_bytes(runtime, transmute([]u8)suffix)
    runtime.paste_admission_count += 1
    return true
}

// Return the xterm modifier parameter, where one represents no modifiers.
//
// Parameters:
//   - modifiers: Portable modifier snapshot to encode.
//
// Returns:
//   - The xterm parameter `1 + Shift + 2*Alt + 4*Control`; Super is ignored.
input_terminal_modifier_parameter :: proc(modifiers: Input_Modifiers) -> u8 {
    parameter: u8 = 1
    if .Shift in modifiers { parameter += 1 }
    if .Alt in modifiers { parameter += 2 }
    if .Control in modifiers { parameter += 4 }
    return parameter
}

// Enqueue CSI 1;modifier plus one final byte.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving the encoded sequence.
//   - final: CSI final byte identifying the navigation or function key.
//   - modifiers: Portable modifiers encoded in xterm parameter form.
//
// Returns:
//   - True when the complete six-byte sequence is queued atomically.
//
// Side effects:
//   - Appends through the runtime queue and records queue pressure on rejection.
input_terminal_enqueue_modified_final :: proc(
    runtime: ^Input_Runtime, final: u8, modifiers: Input_Modifiers) -> bool {
    parameter := input_terminal_modifier_parameter(modifiers)
    bytes := [6]u8{'\e', '[', '1', ';', '0' + parameter, final}
    return input_runtime_enqueue_bytes(runtime, bytes[:])
}

// Enqueue CSI number;modifier~ for editing and higher function keys.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving the encoded sequence.
//   - number: One- or two-digit xterm key number.
//   - modifiers: Portable modifiers encoded in xterm parameter form.
//
// Returns:
//   - True when the complete sequence is queued atomically.
//
// Side effects:
//   - Formats into fixed stack storage, then appends through the runtime queue.
input_terminal_enqueue_modified_tilde :: proc(
    runtime: ^Input_Runtime, number: int,
    modifiers: Input_Modifiers) -> bool {
    parameter := input_terminal_modifier_parameter(modifiers)
    bytes: [8]u8
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    if number >= 10 {
        bytes[count] = u8('0' + number / 10); count += 1
    }
    bytes[count] = u8('0' + number % 10); count += 1
    bytes[count] = ';'; count += 1
    bytes[count] = '0' + parameter; count += 1
    bytes[count] = '~'; count += 1
    return input_runtime_enqueue_bytes(runtime, bytes[:count])
}

// Map one non-alphabetic key to its conventional terminal control byte.
//
// Parameters:
//   - key: Portable physical key paired with Control.
//
// Returns:
//   - The conventional control byte and true, or zero and false when unsupported.
input_terminal_special_control_byte :: proc(key: Input_Key) -> (u8, bool) {
    #partial switch key {
    case .Space, .Digit2: return 0, true
    case .Left_Bracket:   return 27, true
    case .Backslash:      return 28, true
    case .Right_Bracket:  return 29, true
    case .Digit6:         return 30, true
    case .Minus:          return 31, true
    case .Slash:          return 127, true
    case:                 return 0, false
    }
}

// Map conventional Ctrl chords to one terminal control byte.
//
// Parameters:
//   - key: Portable physical key from the captured event.
//   - modifiers: Modifier snapshot captured with that key.
//
// Returns:
//   - The conventional ASCII control byte and true when Control plus a supported key
//     is present; otherwise zero and false.
input_terminal_control_byte :: proc(
    key: Input_Key, modifiers: Input_Modifiers) -> (u8, bool) {
    if .Control not_in modifiers {
        return 0, false
    }
    if key >= .A && key <= .Z {
        return u8(int(key) - int(Input_Key.A) + 1), true
    }
    return input_terminal_special_control_byte(key)
}

// Enqueue one control byte, with the conventional Alt ESC prefix when present.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Physical key event with its atomic modifier snapshot.
//
// Returns:
//   - True when the event maps to a terminal control chord; false when it does not.
//
// Notes:
//   - A true return means the event was recognized. Queue pressure is recorded by the
//     runtime but does not make the event eligible for another encoding path.
//
// Side effects:
//   - Queues one control byte, or an ESC-prefixed pair when Alt is also present.
input_terminal_enqueue_control :: proc(
    runtime: ^Input_Runtime, event: Input_Event) -> bool {
    byte, mapped := input_terminal_control_byte(event.key, event.modifiers)
    if !mapped {
        return false
    }
    if .Alt in event.modifiers {
        bytes := [2]u8{'\e', byte}
        input_runtime_enqueue_bytes(runtime, bytes[:])
    } else {
        bytes := [1]u8{byte}
        input_runtime_enqueue_bytes(runtime, bytes[:])
    }
    return true
}

// Enqueue cursor/navigation keys using DECCKM and xterm modifier forms.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Candidate cursor, Home, or End key event.
//   - mode: Interpreter-owned input modes active for this frame.
//
// Returns:
//   - True when the key belongs to the supported navigation set; otherwise false.
//
// Notes:
//   - Modified keys use CSI parameter form regardless of DECCKM. A true return denotes
//     recognition even if queue pressure rejects the sequence.
//
// Side effects:
//   - Queues one complete modified CSI, application SS3, or ordinary CSI sequence.
input_terminal_enqueue_navigation_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event,
    mode: termmodel.Terminal_Input_Mode) -> bool {
    final: u8
    #partial switch event.key {
    case .Up:    final = 'A'
    case .Down:  final = 'B'
    case .Right: final = 'C'
    case .Left:  final = 'D'
    case .Home:  final = 'H'
    case .End:   final = 'F'
    case:        return false
    }
    if card(event.modifiers) > 0 {
        input_terminal_enqueue_modified_final(runtime, final, event.modifiers)
    } else if mode.cursor_keys_application {
        bytes := [3]u8{'\e', 'O', final}
        input_runtime_enqueue_bytes(runtime, bytes[:])
    } else {
        bytes := [3]u8{'\e', '[', final}
        input_runtime_enqueue_bytes(runtime, bytes[:])
    }
    return true
}

// Enqueue Insert/Delete/Page keys using ordinary or modified CSI forms.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Candidate editing or page-navigation key event.
//
// Returns:
//   - True when the key is Insert, Delete, Page Up, or Page Down; otherwise false.
//
// Notes:
//   - A true return denotes recognition even if queue pressure rejects the sequence.
//
// Side effects:
//   - Queues the corresponding ordinary or modifier-qualified tilde sequence.
input_terminal_enqueue_editing_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event) -> bool {
    number := 0
    #partial switch event.key {
    case .Insert:    number = 2
    case .Delete:    number = 3
    case .Page_Up:   number = 5
    case .Page_Down: number = 6
    case:            return false
    }
    if card(event.modifiers) > 0 {
        input_terminal_enqueue_modified_tilde(runtime, number, event.modifiers)
    } else {
        bytes := [4]u8{'\e', '[', u8('0' + number), '~'}
        input_runtime_enqueue_bytes(runtime, bytes[:])
    }
    return true
}

// Enqueue F1-F12 using xterm SS3/CSI conventions.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Candidate function-key event and captured modifiers.
//
// Returns:
//   - True for F1 through F12; false for every other key.
//
// Notes:
//   - F1-F4 use SS3 when unmodified; F5-F12 use numbered CSI tilde forms. A true
//     return denotes recognition even if queue pressure rejects the sequence.
//
// Side effects:
//   - Queues one complete ordinary or modifier-qualified function-key sequence.
input_terminal_enqueue_function_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event) -> bool {
    if event.key < .F1 || event.key > .F12 {
        return false
    }
    index := int(event.key) - int(Input_Key.F1)
    if index < 4 {
        final := u8('P' + index)
        if card(event.modifiers) > 0 {
            input_terminal_enqueue_modified_final(runtime, final, event.modifiers)
        } else {
            bytes := [3]u8{'\e', 'O', final}
            input_runtime_enqueue_bytes(runtime, bytes[:])
        }
        return true
    }
    numbers := [8]int{15, 17, 18, 19, 20, 21, 23, 24}
    number := numbers[index - 4]
    if card(event.modifiers) > 0 {
        input_terminal_enqueue_modified_tilde(runtime, number, event.modifiers)
    } else {
        bytes: [5]u8
        bytes[0] = '\e'; bytes[1] = '['
        bytes[2] = u8('0' + number / 10)
        bytes[3] = u8('0' + number % 10)
        bytes[4] = '~'
        input_runtime_enqueue_bytes(runtime, bytes[:])
    }
    return true
}

// Enqueue application-keypad forms, leaving numeric-mode text to Text events.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Candidate keypad event.
//   - mode: Interpreter-owned input modes active for this frame.
//
// Returns:
//   - True for every supported keypad key; false for non-keypad events.
//
// Notes:
//   - Numeric keypad glyphs arrive separately as Text events. In numeric mode only
//     keypad Enter requires explicit physical-key encoding.
//
// Side effects:
//   - Queues keypad Enter as carriage return in numeric mode, or an SS3 application
//     sequence for any keypad key in application mode.
input_terminal_enqueue_keypad_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event,
    mode: termmodel.Terminal_Input_Mode) -> bool {
    if event.key < .Keypad0 || event.key > .Keypad_Equal {
        return false
    }
    if !mode.keypad_application {
        if event.key == .Keypad_Enter {
            input_terminal_enqueue_string(runtime, "\r")
        }
        return true
    }
    finals := [17]u8{
        'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
        'n', 'o', 'j', 'm', 'k', 'M', 'X',
    }
    final := finals[int(event.key) - int(Input_Key.Keypad0)]
    bytes := [3]u8{'\e', 'O', final}
    input_runtime_enqueue_bytes(runtime, bytes[:])
    return true
}

// Enqueue one physical key event while preserving event order.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Press or repeat event to encode once.
//   - mode: Interpreter-owned input modes active for this frame.
//
// Notes:
//   - Encoding priority is control chord, navigation, editing, function key, keypad,
//     then the small direct-key set. The first recognized category consumes the event.
//
// Side effects:
//   - Queues at most one complete terminal sequence for the event.
input_terminal_enqueue_key_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event,
    mode: termmodel.Terminal_Input_Mode) {
    if input_terminal_enqueue_control(runtime, event) ||
        input_terminal_enqueue_navigation_event(runtime, event, mode) ||
        input_terminal_enqueue_editing_event(runtime, event) ||
        input_terminal_enqueue_function_event(runtime, event) ||
        input_terminal_enqueue_keypad_event(runtime, event, mode) {
        return
    }
    #partial switch event.key {
    case .Escape:   input_terminal_enqueue_string(runtime, "\e")
    case .Enter:    input_terminal_enqueue_string(runtime, "\r")
    case .Backspace: input_terminal_enqueue_string(runtime, "\x7f")
    case .Tab:
        if .Shift in event.modifiers {
            input_terminal_enqueue_string(runtime, "\e[Z")
        } else if .Alt in event.modifiers {
            input_terminal_enqueue_string(runtime, "\e\t")
        } else {
            input_terminal_enqueue_string(runtime, "\t")
        }
    case:
    }
}

// Enqueue one Unicode text event, adding an Alt/meta ESC prefix atomically.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving encoded bytes.
//   - event: Unicode text event with its captured modifier snapshot.
//
// Notes:
//   - Control-qualified text is suppressed because its physical key event owns control
//     encoding. Alt adds a metadata ESC prefix; Shift and Super do not alter UTF-8.
//
// Side effects:
//   - Encodes one rune into fixed stack storage and atomically queues its UTF-8 bytes
//     with an optional ESC prefix.
input_terminal_enqueue_text_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event) {
    if .Control in event.modifiers {
        return
    }
    encoded, count := utf8.encode_rune(event.codepoint)
    bytes: [5]u8
    start := 0
    if .Alt in event.modifiers {
        bytes[0] = '\e'
        start = 1
    }
    copy(bytes[start:], encoded[:count])
    input_runtime_enqueue_bytes(runtime, bytes[:start + count])
}

// Append one nonnegative decimal integer to fixed byte storage.
//
// Parameters:
//   - bytes: Caller-owned fixed storage with enough remaining capacity.
//   - count: In/out index naming the next byte to write.
//   - value: Nonnegative integer to encode in base ten.
//
// Notes:
//   - Callers validate capacity and value domain; this low-level formatter performs no
//     bounds checks and emits zero as one digit.
//
// Side effects:
//   - Writes decimal digits at bytes[count^:] and advances count past the result.
input_terminal_append_decimal :: proc(
    bytes: []u8, count: ^int, value: int) {
    divisor := 1
    for value / divisor >= 10 {
        divisor *= 10
    }
    for divisor > 0 {
        bytes[count^] = u8('0' + value / divisor % 10)
        count^ += 1
        divisor /= 10
    }
}

// Return whether one interpreter producer is the runtime's current input owner.
input_terminal_producer_matches_owner :: proc(
    producer: termmodel.Terminal_Producer, owner: Input_Owner) -> bool {
    switch producer.kind {
    case .Terminal_Session:
        return owner.kind == .Terminal_Session && owner.id == producer.id &&
            owner.generation == producer.generation
    case .Julia_Evaluation:
        return owner.kind == .Julia_Interactive && owner.id == producer.id
    case .None:
        return false
    }
    return false
}

// Format one keyboard-negotiation response into caller-owned fixed storage.
input_terminal_format_keyboard_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    count := 0
    #partial switch response.kind {
    case .Modify_Other_Keys:
        bytes[count] = '\e'; count += 1
        bytes[count] = '['; count += 1
        bytes[count] = '>'; count += 1
        bytes[count] = '4'; count += 1
        bytes[count] = ';'; count += 1
        input_terminal_append_decimal(bytes[:], &count, int(response.first))
        bytes[count] = 'm'; count += 1
    case .Kitty_Keyboard:
        bytes[count] = '\e'; count += 1
        bytes[count] = '['; count += 1
        bytes[count] = '?'; count += 1
        input_terminal_append_decimal(bytes[:], &count, int(response.first))
        bytes[count] = 'u'; count += 1
    }
    return count
}

// Copy one fixed identity or status response into caller-owned storage.
input_terminal_format_static_response :: proc(
    bytes: []u8, kind: termmodel.Terminal_Response_Kind) -> int {
    value: string
    #partial switch kind {
    case .Primary_Device_Attributes:
        value = "\e[?62;4c"
    case .Secondary_Device_Attributes:
        value = "\e[>1;0;0c"
    case .Device_Status:
        value = "\e[0n"
    }
    copy(bytes, transmute([]u8)value)
    return len(value)
}

// Format one cursor or private-mode status response into fixed storage.
input_terminal_format_status_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    if response.kind == .Private_Mode_Status {
        bytes[count] = '?'; count += 1
    }
    input_terminal_append_decimal(bytes, &count, int(response.first))
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes, &count, int(response.second))
    if response.kind == .Cursor_Position {
        bytes[count] = 'R'; count += 1
    } else {
        bytes[count] = '$'; count += 1
        bytes[count] = 'y'; count += 1
    }
    return count
}

// Append one semantic SGR color reference to a DECRQSS parameter list.
input_terminal_append_sgr_color :: proc(
    bytes: []u8, count: ^int, color: termmodel.Terminal_Color_Reference,
    foreground: bool) {
    kind := termpalette.terminal_color_kind(color)
    if kind == .Default { return }
    bytes[count^] = ';'; count^ += 1
    input_terminal_append_decimal(bytes, count, 38 if foreground else 48)
    bytes[count^] = ';'; count^ += 1
    if kind == .Indexed {
        bytes[count^] = '5'; count^ += 1
        bytes[count^] = ';'; count^ += 1
        input_terminal_append_decimal(
            bytes, count, int(termpalette.terminal_color_value(color)))
        return
    }
    bytes[count^] = '2'; count^ += 1
    value := termpalette.terminal_color_value(color)
    for shift := 16; shift >= 0; shift -= 8 {
        bytes[count^] = ';'; count^ += 1
        input_terminal_append_decimal(
            bytes, count, int(value >> u32(shift) & 0xff))
    }
}

// Format one positive DECRQSS payload after its fixed response introducer.
input_terminal_format_decrqss_payload :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    count := 0
    #partial switch response.kind {
    case .Decrqss_Sgr:
        bytes[count] = '0'; count += 1
        attributes := response.first
        flags := [3]u32{
            termemulator.TERMINAL_SGR_BOLD,
            termemulator.TERMINAL_SGR_ITALIC,
            termemulator.TERMINAL_SGR_UNDERLINE,
        }
        parameters := [3]int{1, 3, 4}
        for flag, index in flags {
            if attributes & flag == 0 { continue }
            bytes[count] = ';'; count += 1
            input_terminal_append_decimal(bytes, &count, parameters[index])
        }
        input_terminal_append_sgr_color(
            bytes, &count, termmodel.Terminal_Color_Reference(response.second), true)
        input_terminal_append_sgr_color(
            bytes, &count, termmodel.Terminal_Color_Reference(response.third), false)
        bytes[count] = 'm'; count += 1
    case .Decrqss_Cursor_Style:
        copy(bytes[count:], "0 q")
        count += 3
    case .Decrqss_Margins:
        input_terminal_append_decimal(bytes, &count, int(response.first))
        bytes[count] = ';'; count += 1
        input_terminal_append_decimal(bytes, &count, int(response.second))
        bytes[count] = 'r'; count += 1
    case:
    }
    return count
}

// Format one DECRQSS positive or standard negative response.
input_terminal_format_decrqss_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    copy(bytes, "\eP")
    count := 2
    if response.kind == .Decrqss_Unsupported {
        copy(bytes[count:], "0$r\e\\")
        return count + 5
    }
    copy(bytes[count:], "1$r")
    count += 3
    count += input_terminal_format_decrqss_payload(bytes[count:], response)
    bytes[count] = '\e'; count += 1
    bytes[count] = '\\'; count += 1
    return count
}

// Append packed validated XTGETTCAP name bytes from one semantic response.
input_terminal_append_capability_name :: proc(
    bytes: []u8, count: ^int, response: termmodel.Terminal_Response) {
    words := [2]u32{response.second, response.third}
    for word in words {
        for index in 0..<4 {
            byte := u8(word >> u32(index * 8))
            if byte == 0 { return }
            bytes[count^] = byte
            count^ += 1
        }
    }
}

// Format one allowlisted or valid-unknown XTGETTCAP response.
input_terminal_format_xtgetcap_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    kind := termemulator.Terminal_Capability_Kind(response.first)
    value: string
    switch kind {
    case .Terminal_Name: value = "\eP1+r544e=746963746163637261776c\e\\"
    case .Colors: value = "\eP1+r436f=323536\e\\"
    case .Rgb: value = "\eP1+r524742=38\e\\"
    case .Truecolor: value = "\eP1+r5463\e\\"
    case .Unknown:
        copy(bytes, "\eP0+r")
        count := 5
        input_terminal_append_capability_name(bytes, &count, response)
        bytes[count] = '\e'; count += 1
        bytes[count] = '\\'; count += 1
        return count
    }
    copy(bytes, value)
    return len(value)
}

// Format one terminal-size response with its xterm report selector.
input_terminal_format_size_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    selector: u8
    #partial switch response.kind {
    case .Window_Pixels: selector = '4'
    case .Cell_Pixels: selector = '6'
    case .Text_Area_Size: selector = '8'
    }
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    bytes[count] = selector; count += 1
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes, &count, int(response.first))
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes, &count, int(response.second))
    bytes[count] = 't'; count += 1
    return count
}

// Append one lowercase four-digit hexadecimal channel to fixed storage.
input_terminal_append_hex_channel :: proc(
    bytes: []u8, count: ^int, channel: u32) {
    digits := "0123456789abcdef"
    value := channel * 0x101
    for shift := 12; shift >= 0; shift -= 4 {
        bytes[count^] = digits[int(value >> u32(shift) & 0xf)]
        count^ += 1
    }
}

// Format one xterm dynamic-color query reply into fixed storage.
input_terminal_format_color_response :: proc(
    bytes: []u8, response: termmodel.Terminal_Response) -> int {
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = ']'; count += 1
    input_terminal_append_decimal(bytes, &count, int(response.first))
    bytes[count] = ';'; count += 1
    if response.first == 4 {
        input_terminal_append_decimal(bytes, &count, int(response.second))
        bytes[count] = ';'; count += 1
    }
    copy(bytes[count:], "rgb:")
    count += 4
    input_terminal_append_hex_channel(bytes, &count, response.third >> 24)
    bytes[count] = '/'; count += 1
    input_terminal_append_hex_channel(bytes, &count, response.third >> 16 & 0xff)
    bytes[count] = '/'; count += 1
    input_terminal_append_hex_channel(bytes, &count, response.third >> 8 & 0xff)
    bytes[count] = '\e'; count += 1
    bytes[count] = '\\'; count += 1
    return count
}

// Encode one parsed semantic response into fixed stack storage.
input_terminal_enqueue_response :: proc(
    runtime: ^Input_Runtime, response: termmodel.Terminal_Response) -> bool {
    bytes: [96]u8
    count: int
    #partial switch response.kind {
    case .Modify_Other_Keys, .Kitty_Keyboard:
        count = input_terminal_format_keyboard_response(bytes[:], response)
    case .Primary_Device_Attributes, .Secondary_Device_Attributes, .Device_Status:
        count = input_terminal_format_static_response(bytes[:], response.kind)
    case .Cursor_Position, .Private_Mode_Status, .Mode_Status:
        count = input_terminal_format_status_response(bytes[:], response)
    case .Window_Pixels, .Cell_Pixels, .Text_Area_Size:
        count = input_terminal_format_size_response(bytes[:], response)
    case .Osc_Color:
        count = input_terminal_format_color_response(bytes[:], response)
    case .Decrqss_Sgr, .Decrqss_Cursor_Style, .Decrqss_Margins,
         .Decrqss_Unsupported:
        count = input_terminal_format_decrqss_response(bytes[:], response)
    case .Xtgetcap:
        count = input_terminal_format_xtgetcap_response(bytes[:], response)
    }
    return input_runtime_enqueue_bytes(runtime, bytes[:count])
}

// Format one structured Kitty graphics acknowledgement into fixed storage.
input_terminal_format_kitty_graphics_response :: proc(
    bytes: []u8, response: gfxprotocol.Kitty_Graphics_Response) -> int {
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '_'; count += 1
    bytes[count] = 'G'; count += 1
    if response.image_id != 0 {
        bytes[count] = 'i'; count += 1
        bytes[count] = '='; count += 1
        input_terminal_append_decimal(bytes, &count, int(response.image_id))
    } else if response.image_number != 0 {
        bytes[count] = 'I'; count += 1
        bytes[count] = '='; count += 1
        input_terminal_append_decimal(bytes, &count, int(response.image_number))
    }
    if response.placement_id != 0 {
        if count > 3 { bytes[count] = ','; count += 1 }
        bytes[count] = 'p'; count += 1
        bytes[count] = '='; count += 1
        input_terminal_append_decimal(bytes, &count, int(response.placement_id))
    }
    bytes[count] = ';'; count += 1
    status := "OK"
    #partial switch response.status {
    case .Ok: status = "OK"
    case .Invalid: status = "EINVAL"
    case .Not_Found: status = "ENOENT"
    case .Unsupported: status = "ENOTSUP"
    case .Capacity_Exceeded: status = "ENOSPC"
    }
    copy(bytes[count:], transmute([]u8)status)
    count += len(status)
    bytes[count] = '\e'; count += 1
    bytes[count] = '\\'; count += 1
    return count
}

// Drain owner-matched Kitty graphics replies after ordinary semantic responses.
input_terminal_drain_graphics_responses :: proc(
    runtime: ^Input_Runtime, interpreter: ^termemulator.Interpreter) -> bool {
    if interpreter.title_state == nil || interpreter.title_state.graphics == nil {
        return true
    }
    graphics := interpreter.title_state.graphics
    for {
        response, present := gfxprotocol.graphics_parser_peek_kitty_response(graphics)
        if !present { return true }
        if !input_terminal_producer_matches_owner(response.producer, runtime.owner) {
            if response.producer.kind == .Julia_Evaluation { return true }
            graphics.kitty_response_stale_discard_count += 1
            gfxprotocol.graphics_parser_pop_kitty_response(graphics)
            continue
        }
        bytes: [64]u8
        count := input_terminal_format_kitty_graphics_response(bytes[:], response)
        if !input_runtime_enqueue_bytes(runtime, bytes[:count]) { return false }
        gfxprotocol.graphics_parser_pop_kitty_response(graphics)
    }
}

// Resolve whether the semantic response head is ready for the current owner.
//
// Returns:
//   - Ready and waiting flags. Both false means a stale response was discarded.
//
// Side effects:
//   - Pops stale non-Julia responses and increments their count-only diagnostic.
input_terminal_response_ready :: proc(
    interpreter: ^termemulator.Interpreter, response: termmodel.Terminal_Response,
    owner: Input_Owner) -> (ready, waiting: bool) {
    if input_terminal_producer_matches_owner(response.producer, owner) {
        return true, false
    }
    if response.producer.kind == .Julia_Evaluation {
        return false, true
    }
    if interpreter.title_state != nil {
        interpreter.title_state.response_stale_discard_count += 1
    }
    termemulator.interpreter_pop_response(interpreter)
    return false, false
}

// Drain owner-matched semantic replies before admitting new frame input.
//
// Returns:
//   - True when no matching response is blocked by byte-ring pressure.
//
// Side effects:
//   - Discards stale producer records and pops matching records only after complete
//     byte admission. Existing ring bytes remain ahead of newly admitted replies.
input_terminal_drain_responses :: proc(
    runtime: ^Input_Runtime, interpreter: ^termemulator.Interpreter) -> bool {
    if runtime == nil || interpreter == nil || runtime.owner.kind == .None {
        return true
    }
    for {
        response, present := termemulator.interpreter_peek_response(interpreter)
        if !present {
            return input_terminal_drain_graphics_responses(runtime, interpreter)
        }
        ready, waiting := input_terminal_response_ready(
            interpreter, response, runtime.owner)
        if waiting { return true }
        if !ready {
            continue
        }
        if !input_terminal_enqueue_response(runtime, response) {
            return false
        }
        termemulator.interpreter_pop_response(interpreter)
    }
}

// Drain semantic replies and then encode one frame under interpreter-owned modes.
//
// Side effects:
//   - Appends matching replies before newly encoded focus, mouse, key, and text bytes.
input_terminal_enqueue_interpreter_frame :: proc(
    runtime: ^Input_Runtime, interpreter: ^termemulator.Interpreter,
    frame: Input_Frame) {
    if !input_terminal_drain_responses(runtime, interpreter) {
        return
    }
    input_terminal_enqueue_frame(
        runtime, frame, termemulator.interpreter_input_mode(interpreter),
        termemulator.interpreter_modify_other_keys_level(interpreter),
        termemulator.interpreter_kitty_keyboard_flags(interpreter))
}

// Map one ordinary physical key to its stable unshifted ASCII identity.
input_terminal_ordinary_key_codepoint :: proc(key: Input_Key) -> (rune, bool) {
    if key < .Space || key > .Grave {
        return 0, false
    }
    index := int(key) - int(Input_Key.Space)
    codepoints := INPUT_TERMINAL_ORDINARY_KEY_CODEPOINTS
    return rune(codepoints[index]), true
}

// Return whether the selected xterm level extends one modifier combination.
input_terminal_modify_other_keys_applies :: proc(
    level: u8, event: Input_Event) -> bool {
    if level == 0 || card(event.modifiers) == 0 || .Super in event.modifiers {
        return false
    }
    if level == 2 {
        return true
    }
    if level != 1 {
        return false
    }
    if .Alt in event.modifiers {
        return true
    }
    _, conventional_control := input_terminal_control_byte(
        event.key, event.modifiers)
    return .Control in event.modifiers && !conventional_control
}

// Resolve the xterm codepoint from paired text or stable physical identity.
input_terminal_modify_other_keys_codepoint :: proc(
    frame: Input_Frame, event_index: int) -> (rune, bool) {
    event := frame.events[event_index]
    if event.key == .Tab {
        return '\t', true
    }
    if event.correlation.valid {
        partner := int(event.correlation.partner_index)
        if partner >= 0 && partner < len(frame.events) &&
            frame.events[partner].kind == .Text {
            return frame.events[partner].codepoint, true
        }
    }
    if .Shift not_in event.modifiers &&
        (.Control in event.modifiers ||
            .Alt in event.modifiers && !input_terminal_frame_has_text(frame)) {
        return input_terminal_ordinary_key_codepoint(event.key)
    }
    return 0, false
}

// Format one xterm modifyOtherKeys sequence into caller-owned fixed storage.
//
// Returns:
//   - Number of initialized bytes in `bytes`.
//
// Side effects:
//   - Writes `CSI 27 ; modifier ; codepoint ~` without allocation.
input_terminal_format_modify_other_key :: proc(
    bytes: []u8, modifiers: Input_Modifiers, codepoint: rune) -> int {
    count := 0
    prefix := [5]u8{'\e', '[', '2', '7', ';'}
    copy(bytes, prefix[:])
    count += len(prefix)
    input_terminal_append_decimal(bytes, &count,
        int(input_terminal_modifier_parameter(modifiers)))
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes, &count, int(codepoint))
    bytes[count] = '~'; count += 1
    return count
}

// Atomically claim and admit one resolved modifyOtherKeys event.
//
// Returns:
//   - True only after valid reciprocal claims and complete byte admission.
//
// Side effects:
//   - Appends one complete sequence and publishes correlated claims on success.
input_terminal_admit_modify_other_key :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    codepoint: rune, claims: ^Input_Event_Claim_State) -> bool {
    event := frame.events[event_index]
    admitted_claims := claims^
    if event.correlation.valid &&
        !input_event_claim_pair(frame, event_index, &admitted_claims) {
        return false
    }
    bytes: [24]u8
    count := input_terminal_format_modify_other_key(
        bytes[:], event.modifiers, codepoint)
    if !input_runtime_enqueue_bytes(runtime, bytes[:count]) {
        return false
    }
    if event.correlation.valid { claims^ = admitted_claims }
    return true
}

// Admit one xterm modifyOtherKeys sequence and claim correlated duplicates.
//
// Returns:
//   - Consumed after complete admission and claims, Blocked on admission or claim
//     failure, or Not_Applicable when legacy encoding remains authoritative.
input_terminal_enqueue_modify_other_key :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    level: u8, claims: ^Input_Event_Claim_State) -> Input_Protocol_Key_Outcome {
    event := frame.events[event_index]
    if !input_terminal_modify_other_keys_applies(level, event) {
        return .Not_Applicable
    }
    codepoint, available := input_terminal_modify_other_keys_codepoint(
        frame, event_index)
    if !available {
        return .Not_Applicable
    }
    if !input_terminal_admit_modify_other_key(
        runtime, frame, event_index, codepoint, claims) {
        return .Blocked
    }
    return .Consumed
}

// Return the Kitty modifier parameter, including the supported Super bit.
input_terminal_kitty_modifier_parameter :: proc(modifiers: Input_Modifiers) -> u8 {
    parameter := input_terminal_modifier_parameter(modifiers)
    if .Super in modifiers { parameter += 8 }
    return parameter
}

// Return the Kitty event-type value for one physical event.
input_terminal_kitty_event_type :: proc(kind: Input_Event_Kind) -> (u8, bool) {
    switch kind {
    case .Press:   return 1, true
    case .Repeat:  return 2, true
    case .Release: return 3, true
    case .Text:    return 0, false
    }
    return 0, false
}

// Resolve one physical event's validated contiguous associated-text run.
input_terminal_kitty_associated_text :: proc(
    frame: Input_Frame,
    event_index: int) -> Input_Terminal_Kitty_Associated_Text {
    if event_index < 0 || event_index >= len(frame.events) {
        return {}
    }
    event := frame.events[event_index]
    result := Input_Terminal_Kitty_Associated_Text{
        start = int(event.correlation.partner_index),
        count = max(int(event.correlation.partner_count), 1),
    }
    if !event.correlation.valid || event.kind == .Text || result.start < 0 ||
        result.start + result.count > len(frame.events) {
        return {}
    }
    for index in result.start..<result.start + result.count {
        text := frame.events[index]
        if text.kind != .Text || !text.correlation.valid ||
            text.correlation.partner_index != u16(event_index) {
            return {}
        }
    }
    result.available = true
    return result
}

// Append a Kitty modifier field and optional non-press event type.
input_terminal_append_kitty_modifiers :: proc(
    bytes: []u8, count: ^int, event: Input_Event, flags: u8,
    force: bool = false) {
    report_type := flags & 2 != 0 && event.kind != .Press
    if card(event.modifiers) == 0 && !report_type && !force { return }
    bytes[count^] = ';'; count^ += 1
    input_terminal_append_decimal(bytes, count,
        int(input_terminal_kitty_modifier_parameter(event.modifiers)))
    if report_type {
        event_type, _ := input_terminal_kitty_event_type(event.kind)
        bytes[count^] = ':'; count^ += 1
        bytes[count^] = '0' + event_type; count^ += 1
    }
}

// Format one Kitty CSI-u key sequence into caller-owned fixed storage.
input_terminal_format_kitty_key :: proc(
    bytes: []u8, codepoint: rune, frame: Input_Frame,
    event_index: int, flags: u8) -> int {
    event := frame.events[event_index]
    associated := input_terminal_kitty_associated_text(frame, event_index)
    report_text := flags & 16 != 0 && event.kind != .Release &&
        associated.available
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    input_terminal_append_decimal(bytes, &count, int(codepoint))
    if flags & 4 != 0 && .Shift in event.modifiers && associated.available &&
        frame.events[associated.start].codepoint != codepoint {
        bytes[count] = ':'; count += 1
        input_terminal_append_decimal(
            bytes, &count, int(frame.events[associated.start].codepoint))
    }
    input_terminal_append_kitty_modifiers(
        bytes, &count, event, flags, force = report_text)
    if report_text {
        bytes[count] = ';'; count += 1
        for offset in 0..<associated.count {
            if offset > 0 { bytes[count] = ':'; count += 1 }
            input_terminal_append_decimal(bytes, &count,
                int(frame.events[associated.start + offset].codepoint))
        }
    }
    bytes[count] = 'u'; count += 1
    return count
}

// Resolve one navigation, editing, or function key to its canonical Kitty form.
input_terminal_kitty_functional_key :: proc(
    key: Input_Key) -> Input_Terminal_Kitty_Functional_Key {
    if key >= .Insert && key <= .End {
        numbers := [10]int{2, 3, 1, 1, 1, 1, 5, 6, 1, 1}
        finals := [10]u8{'~', '~', 'C', 'D', 'B', 'A', '~', '~', 'H', 'F'}
        index := int(key) - int(Input_Key.Insert)
        return {number = numbers[index], final = finals[index]}
    }
    if key < .F1 || key > .F12 { return {} }
    numbers := [12]int{1, 1, 13, 1, 15, 17, 18, 19, 20, 21, 23, 24}
    finals := [12]u8{'P', 'Q', '~', 'S', '~', '~', '~', '~', '~', '~', '~', '~'}
    index := int(key) - int(Input_Key.F1)
    return {number = numbers[index], final = finals[index]}
}

// Format one canonical Kitty functional key with a non-press event type.
input_terminal_format_kitty_functional :: proc(
    bytes: []u8, event: Input_Event, flags: u8) -> (int, bool) {
    key := input_terminal_kitty_functional_key(event.key)
    if key.final == 0 { return 0, false }
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    input_terminal_append_decimal(bytes, &count, key.number)
    input_terminal_append_kitty_modifiers(bytes, &count, event, flags)
    bytes[count] = key.final; count += 1
    return count, true
}

// Map one distinct keypad key to its Kitty private-use codepoint.
input_terminal_kitty_keypad_codepoint :: proc(key: Input_Key) -> (rune, bool) {
    if key < .Keypad0 || key > .Keypad_Equal {
        return 0, false
    }
    return rune(57399 + int(key) - int(Input_Key.Keypad0)), true
}

// Return whether a frame contains any unclaimed text evidence.
input_terminal_frame_has_text :: proc(frame: Input_Frame) -> bool {
    for event in frame.events {
        if event.kind == .Text { return true }
    }
    return false
}

// Return whether accepted Kitty reporting flags require one ordinary key identity.
input_terminal_kitty_reports_ordinary :: proc(
    frame: Input_Frame, event: Input_Event, flags: u8) -> bool {
    if flags & 8 != 0 { return true }
    if flags & (4 | 16) != 0 && event.correlation.valid { return true }
    if card(event.modifiers) == 0 || event.modifiers == {.Shift} { return false }
    return event.correlation.valid || .Control in event.modifiers ||
        !input_terminal_frame_has_text(frame)
}

// Resolve one key represented in CSI-u form by accepted Kitty flags.
input_terminal_kitty_codepoint :: proc(
    frame: Input_Frame, event_index: int, flags: u8) -> (rune, bool) {
    event := frame.events[event_index]
    if event.key == .Escape {
        return 27, true
    }
    if codepoint, keypad := input_terminal_kitty_keypad_codepoint(event.key); keypad {
        return codepoint, true
    }
    if flags & 8 != 0 {
        #partial switch event.key {
        case .Enter:     return 13, true
        case .Tab:       return 9, true
        case .Backspace: return 127, true
        case:            // Continue with ordinary physical identities.
        }
    }
    codepoint, ordinary := input_terminal_ordinary_key_codepoint(event.key)
    if !ordinary {
        return 0, false
    }
    return codepoint, input_terminal_kitty_reports_ordinary(frame, event, flags)
}

// Atomically admit one Kitty CSI-u key and its correlated text claim.
input_terminal_admit_kitty_key :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    flags: u8, claims: ^Input_Event_Claim_State) -> bool {
    event := frame.events[event_index]
    codepoint, _ := input_terminal_kitty_codepoint(frame, event_index, flags)
    admitted_claims := claims^
    if event.correlation.valid &&
        !input_event_claim_pair(frame, event_index, &admitted_claims) {
        return false
    }
    bytes: [INPUT_EVENT_CAPACITY * 12 + 32]u8
    count := input_terminal_format_kitty_key(
        bytes[:], codepoint, frame, event_index, flags)
    if !input_runtime_enqueue_bytes(runtime, bytes[:count]) {
        return false
    }
    if event.correlation.valid { claims^ = admitted_claims }
    return true
}

// Admit a canonical functional repeat or release with Kitty event type.
input_terminal_admit_kitty_functional :: proc(
    runtime: ^Input_Runtime, event: Input_Event, flags: u8) -> bool {
    bytes: [24]u8
    count, valid := input_terminal_format_kitty_functional(bytes[:], event, flags)
    return valid && input_runtime_enqueue_bytes(runtime, bytes[:count])
}

// Encode a canonical functional repeat or release when Kitty flag 2 applies.
input_terminal_enqueue_kitty_functional :: proc(
    runtime: ^Input_Runtime, event: Input_Event,
    flags: u8) -> Input_Protocol_Key_Outcome {
    if flags & 2 == 0 || event.kind == .Press {
        return .Not_Applicable
    }
    key := input_terminal_kitty_functional_key(event.key)
    if key.final == 0 { return .Not_Applicable }
    return .Consumed if input_terminal_admit_kitty_functional(
        runtime, event, flags) else .Blocked
}

// Return whether accepted Kitty flags represent this physical event kind.
input_terminal_kitty_event_applies :: proc(
    event: Input_Event, flags: u8) -> bool {
    report_type := flags & 2 != 0
    report_key := flags & (1 | 8) != 0 ||
        flags & (4 | 16) != 0 && event.correlation.valid
    if event.kind == .Release { return report_type }
    if event.kind == .Press { return report_key }
    return event.kind == .Repeat && (report_type || report_key)
}

// Encode one key under accepted Kitty disambiguation and event-type flags.
input_terminal_enqueue_kitty_key :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    flags: u8, claims: ^Input_Event_Claim_State) -> Input_Protocol_Key_Outcome {
    event := frame.events[event_index]
    if !input_terminal_kitty_event_applies(event, flags) {
        return .Not_Applicable
    }
    _, available := input_terminal_kitty_codepoint(frame, event_index, flags)
    if available {
        if !input_terminal_admit_kitty_key(
            runtime, frame, event_index, flags, claims) {
            return .Blocked
        }
        return .Consumed
    }
    return input_terminal_enqueue_kitty_functional(runtime, event, flags)
}

// Apply negotiated keyboard precedence for one physical key event.
input_terminal_enqueue_protocol_key :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    mode: Input_Terminal_Encoding_Mode,
    claims: ^Input_Event_Claim_State) -> Input_Protocol_Key_Outcome {
    if mode.kitty_keyboard_flags != 0 {
        outcome := input_terminal_enqueue_kitty_key(
            runtime, frame, event_index, mode.kitty_keyboard_flags, claims)
        event := frame.events[event_index]
        if outcome == .Not_Applicable &&
            mode.kitty_keyboard_flags & (4 | 16) != 0 &&
            event.key >= .Space && event.key <= .Grave &&
            !event.correlation.valid {
            runtime.input_fallback_count += 1
        }
        if outcome == .Blocked {
            runtime.input_atomic_rejection_count += 1
        }
        return outcome
    }
    outcome := input_terminal_enqueue_modify_other_key(
        runtime, frame, event_index, mode.modify_other_keys_level, claims)
    if outcome == .Blocked {
        runtime.input_atomic_rejection_count += 1
    }
    return outcome
}

// Consume the reserved terminal clipboard chord when present.
//
// Returns:
//   - True when the event is Ctrl+Shift+V and owns one paste transaction.
input_terminal_enqueue_clipboard_chord :: proc(
    runtime: ^Input_Runtime, event: Input_Event,
    mode: termmodel.Terminal_Input_Mode) -> bool {
    if event.kind != .Press || event.key != .V ||
        event.modifiers != {.Control, .Shift} {
        return false
    }
    input_terminal_enqueue_paste(
        runtime, input_get_clipboard_text(), mode.bracketed_paste)
    return true
}

// Atomically enqueue one SGR mouse report.
//
// Parameters:
//   - runtime: Owner-bound input runtime receiving the report.
//   - code: Nonnegative SGR `Cb` value including button, motion, and modifiers.
//   - position: One-based live-grid column and row.
//   - released: Whether to use lowercase release final `m` instead of `M`.
//
// Returns:
//   - True when the complete report enters the queue; false without partial admission.
//
// Side effects:
//   - Formats `CSI < Cb ; Cx ; Cy M/m` in fixed stack storage and appends it through
//     the runtime queue, including ordinary pressure accounting.
input_terminal_enqueue_mouse_report :: proc(
    runtime: ^Input_Runtime, code: int, position: Input_Terminal_Position,
    released: bool) -> bool {
    bytes: [32]u8
    count := 0
    bytes[count] = '\e'; count += 1
    bytes[count] = '['; count += 1
    bytes[count] = '<'; count += 1
    input_terminal_append_decimal(bytes[:], &count, code)
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes[:], &count, position.column)
    bytes[count] = ';'; count += 1
    input_terminal_append_decimal(bytes[:], &count, position.row)
    bytes[count] = 'm' if released else 'M'; count += 1
    return input_runtime_enqueue_bytes(runtime, bytes[:count])
}

// Return the SGR base code for one supported mouse button.
//
// Parameters:
//   - button: Portable button identity to encode.
//
// Returns:
//   - Zero for left, one for middle, or two for right.
input_terminal_mouse_button_code :: proc(button: Input_Mouse_Button) -> int {
    switch button {
    case .Left: return 0
    case .Middle: return 1
    case .Right: return 2
    }
    return 0
}

// Add protocol-supported keyboard modifiers to one SGR mouse code.
//
// Parameters:
//   - modifiers: Modifier snapshot captured with mouse activity.
//
// Returns:
//   - Eight for Alt plus sixteen for Control when present; Shift and Super are ignored.
//
// Notes:
//   - Shift is reserved for local selection and scrolling before protocol encoding.
input_terminal_mouse_modifier_code :: proc(modifiers: Input_Modifiers) -> int {
    code := 0
    if .Alt in modifiers { code += 8 }
    if .Control in modifiers { code += 16 }
    return code
}

// Retry captured releases before accepting newer mouse activity.
//
// Parameters:
//   - runtime: Owner-bound mouse capture and byte-queue state.
//   - modifiers: Current frame modifiers applied to retried release reports.
//
// Returns:
//   - True after every pending release is admitted; false at the first queue rejection.
//
// Notes:
//   - Buttons retry in stable left, middle, right order. Later pending releases remain
//     untouched when an earlier report cannot be admitted.
//
// Side effects:
//   - Queues release reports and clears each corresponding pending and captured bit only
//     after successful admission.
input_terminal_retry_mouse_releases :: proc(
    runtime: ^Input_Runtime, modifiers: Input_Modifiers) -> bool {
    buttons := [3]Input_Mouse_Button{.Left, .Middle, .Right}
    for button in buttons {
        if button not_in runtime.mouse_pending_releases {
            continue
        }
        code := input_terminal_mouse_button_code(button) +
            input_terminal_mouse_modifier_code(modifiers)
        if !input_terminal_enqueue_mouse_report(
            runtime, code, runtime.mouse_release_positions[int(button)], true) {
            return false
        }
        runtime.mouse_pending_releases -= {button}
        runtime.mouse_captured -= {button}
    }
    return true
}

// Encode button transitions and update application capture state.
//
// Parameters:
//   - runtime: Owner-bound mouse capture and byte-queue state.
//   - frame: Resolved frame containing button edges, ownership, and live-grid position.
//   - modifier_code: Precomputed SGR Alt and Control bits.
//
// Notes:
//   - Presses capture only after an inside, application-owned report is admitted.
//     Releases apply only to captured buttons and remain eligible outside the grid.
//
// Side effects:
//   - Queues button press and release reports, updates captured and last-position state,
//     and retains rejected releases with their clamped positions for retry.
input_terminal_enqueue_mouse_buttons :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, modifier_code: int) {
    position := frame.terminal_mouse_position
    buttons := [3]Input_Mouse_Button{.Left, .Middle, .Right}
    for button in buttons {
        if button in frame.mouse_pressed && frame.terminal_mouse_inside &&
            frame.terminal_mouse_owned {
            code := input_terminal_mouse_button_code(button) + modifier_code
            if input_terminal_enqueue_mouse_report(runtime, code, position, false) {
                runtime.mouse_captured += {button}
                runtime.mouse_last_position = position
                runtime.mouse_last_position_valid = true
            }
        }
        if button in frame.mouse_released && button in runtime.mouse_captured {
            code := input_terminal_mouse_button_code(button) + modifier_code
            if input_terminal_enqueue_mouse_report(runtime, code, position, true) {
                runtime.mouse_captured -= {button}
            } else {
                runtime.mouse_pending_releases += {button}
                runtime.mouse_release_positions[int(button)] = position
            }
        }
    }
}

// Resolve the SGR motion code for the first captured button or no-button motion.
//
// Parameters:
//   - runtime: Owner-bound mouse capture state.
//
// Returns:
//   - Motion base code for the first captured button, or 35 when none is captured.
input_terminal_mouse_motion_code :: proc(runtime: ^Input_Runtime) -> int {
    buttons := [3]Input_Mouse_Button{.Left, .Middle, .Right}
    for button in buttons {
        if button in runtime.mouse_captured {
            return input_terminal_mouse_button_code(button) + 32
        }
    }
    return 35
}

// Encode at most one changed-cell motion report.
//
// Parameters:
//   - runtime: Owner-bound mouse capture, coalescing, and byte-queue state.
//   - frame: Resolved application-owned frame and current live-grid position.
//   - tracking: Active tracking mode controlling button and movement requirements.
//   - modifier_code: Precomputed SGR Alt and Control bits.
//
// Notes:
//   - Motion is coalesced by terminal cell. Button-motion requires capture. Any-motion
//     requires actual pointer movement and uses code 35 when no button is captured.
//
// Side effects:
//   - Queues one drag report when ownership and position changed, then advances the last
//     reported position only after successful queue admission.
input_terminal_enqueue_mouse_motion :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame,
    tracking: termmodel.Terminal_Mouse_Tracking_Mode, modifier_code: int) {
    captured := card(runtime.mouse_captured) > 0
    if !frame.terminal_mouse_owned ||
        tracking == .Button_Motion && !captured ||
        tracking == .Any_Motion && (!frame.mouse_moved ||
            !captured && !frame.terminal_mouse_inside) ||
        runtime.mouse_last_position_valid &&
        runtime.mouse_last_position == frame.terminal_mouse_position {
        return
    }
    code := input_terminal_mouse_motion_code(runtime) + modifier_code
    if input_terminal_enqueue_mouse_report(
        runtime, code, frame.terminal_mouse_position, false) {
        runtime.mouse_last_position = frame.terminal_mouse_position
        runtime.mouse_last_position_valid = true
    }
}

// Encode at most one wheel report from this frame's signed delta.
//
// Parameters:
//   - runtime: Owner-bound byte queue receiving the wheel report.
//   - frame: Resolved frame containing wheel delta, ownership, and grid position.
//   - modifier_code: Precomputed SGR Alt and Control bits.
//
// Notes:
//   - Delta magnitude is intentionally collapsed to one report: positive is wheel up
//     and negative is wheel down.
//
// Side effects:
//   - Queues one wheel report only while the application owns an inside-grid pointer.
input_terminal_enqueue_mouse_wheel :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, modifier_code: int) {
    if frame.terminal_mouse_owned && frame.terminal_mouse_inside &&
        frame.mouse_wheel_delta != 0 {
        code := 64 if frame.mouse_wheel_delta > 0 else 65
        input_terminal_enqueue_mouse_report(
            runtime, code + modifier_code, frame.terminal_mouse_position, false)
    }
}

// Select the UI-resolved coordinate space negotiated for SGR reporting.
input_terminal_select_mouse_position :: proc(
    frame: Input_Frame, pixel_coordinates: bool) -> Input_Frame {
    result := frame
    if pixel_coordinates {
        result.terminal_mouse_position = frame.terminal_mouse_pixel_position
    }
    return result
}

// Encode resolved SGR mouse activity and retain capture across frames.
//
// Parameters:
//   - runtime: Owner-bound mouse capture and byte-queue state.
//   - frame: UI-resolved mouse frame with one-based cell and content-pixel coordinates.
//   - mode: Interpreter-owned tracking and SGR-encoding modes.
//
// Notes:
//   - Pending releases run before new transitions. Button mode emits edges and wheel;
//     button-motion mode additionally emits captured drags; any-motion emits real
//     changed-position movement with or without a captured button. Coordinate-mode
//     changes invalidate coalescing without releasing captured buttons.
//
// Side effects:
//   - Clears capture when reporting is disabled, retries deferred releases, and may queue
//     button, motion, and wheel reports while updating capture and coalescing state.
input_terminal_enqueue_mouse :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame,
    mode: termmodel.Terminal_Input_Mode) {
    enabled := mode.mouse_tracking != .None && mode.mouse_sgr_encoding
    if !enabled {
        runtime.mouse_captured = {}
        runtime.mouse_pending_releases = {}
        runtime.mouse_last_position_valid = false
        return
    }
    if runtime.mouse_last_position_valid &&
        runtime.mouse_last_pixel_coordinates != mode.mouse_pixel_coordinates {
        runtime.mouse_last_position_valid = false
    }
    runtime.mouse_last_pixel_coordinates = mode.mouse_pixel_coordinates
    selected := input_terminal_select_mouse_position(
        frame, mode.mouse_pixel_coordinates)
    if !input_terminal_retry_mouse_releases(runtime, selected.mouse_modifiers) ||
        !selected.terminal_mouse_position_valid {
        return
    }
    modifier_code := input_terminal_mouse_modifier_code(selected.mouse_modifiers)
    input_terminal_enqueue_mouse_buttons(runtime, selected, modifier_code)
    if mode.mouse_tracking == .Button_Motion ||
        mode.mouse_tracking == .Any_Motion {
        input_terminal_enqueue_mouse_motion(
            runtime, selected, mode.mouse_tracking, modifier_code)
    }
    input_terminal_enqueue_mouse_wheel(runtime, selected, modifier_code)
}

// Encode one retained event through clipboard, negotiated, and legacy paths.
//
// Returns:
//   - False only when a recognized negotiated key is blocked by queue pressure.
input_terminal_enqueue_frame_event :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame, event_index: int,
    mode: Input_Terminal_Encoding_Mode,
    claims: ^Input_Event_Claim_State) -> bool {
    event := frame.events[event_index]
    if claims.claimed[event_index] ||
        input_terminal_enqueue_clipboard_chord(runtime, event, mode.terminal) {
        return true
    }
    switch event.kind {
    case .Press, .Repeat, .Release:
        outcome := input_terminal_enqueue_protocol_key(
            runtime, frame, event_index, mode, claims)
        if outcome == .Blocked { return false }
        if outcome == .Not_Applicable && event.kind != .Release {
            input_terminal_enqueue_key_event(runtime, event, mode.terminal)
        }
    case .Text:
        input_terminal_enqueue_text_event(runtime, event)
    }
    return true
}

// Encode frame events in retained order into the runtime-owned byte ring.
//
// Parameters:
//   - runtime: Exclusive owner-bound input runtime receiving all encoded bytes.
//   - frame: Once-per-frame focus, resolved mouse, key, and text snapshot.
//   - mode: Interpreter-owned input modes authoritative for this frame.
//
// Notes:
//   - Encoding order is focus transition, mouse activity, then retained keyboard/text
//     events. Physical release events produce no terminal bytes.
//   - Ctrl+Shift+V is consumed as one clipboard transaction and never falls through to
//     ordinary key encoding.
//
// Side effects:
//   - Appends zero or more complete protocol sequences to the owner-bound queue, updates
//     mouse capture and paste diagnostics, and reads clipboard text for the paste chord.
input_terminal_enqueue_frame :: proc(
    runtime: ^Input_Runtime, frame: Input_Frame,
    mode: termmodel.Terminal_Input_Mode,
    modify_other_keys_level: u8 = 0,
    kitty_keyboard_flags: u8 = 0) {
    if mode.focus_reporting && frame.window_focus_changed {
        sequence := "\e[I" if frame.window_focused else "\e[O"
        input_terminal_enqueue_string(runtime, sequence)
    }
    input_terminal_enqueue_mouse(runtime, frame, mode)
    claims: Input_Event_Claim_State
    encoding_mode := Input_Terminal_Encoding_Mode{
        mode, modify_other_keys_level, kitty_keyboard_flags}
    for _, event_index in frame.events {
        if !input_terminal_enqueue_frame_event(
            runtime, frame, event_index, encoding_mode, &claims) {
            return
        }
    }
}
*/
