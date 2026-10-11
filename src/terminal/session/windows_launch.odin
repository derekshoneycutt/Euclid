package termsession

//   Return whether one argv element requires Microsoft CRT quoting.
//
// Returns:
//   - True for empty text or text containing space, tab, or a double quote.
windows_terminal_argument_needs_quotes :: proc(argument: string) -> bool {
    if len(argument) == 0 {
        return true
    }
    for byte in transmute([]u8)argument {
        if byte == ' ' || byte == '\t' || byte == '"' {
            return true
        }
    }
    return false
}

//   Append one command-line byte without exceeding caller-owned storage.
//
// Returns:
//   - True after append; false without advancing `used` when destination is full.
windows_terminal_append_command_byte :: proc(
    destination: []u8, used: ^int, byte: u8) -> bool {
    if used^ >= len(destination) {
        return false
    }
    destination[used^] = byte
    used^ += 1
    return true
}

//   Append one byte repeatedly without exceeding caller-owned storage.
windows_terminal_append_repeated_byte :: proc(
    destination: []u8, used: ^int, byte: u8, count: int) -> bool {
    for _ in 0..<count {
        if !windows_terminal_append_command_byte(destination, used, byte) {
            return false
        }
    }
    return true
}

//   Append one argv element using Microsoft CRT backslash and quote rules.
//
// Notes:
//   - Backslashes before embedded or closing quotes are doubled as required for the
//     CRT parser to reconstruct the original argument exactly.
//
// Returns:
//   - True after complete encoding; false when destination capacity is exhausted.
//
// Side effects:
//   - May leave a partial encoded argument in destination on failure.
windows_terminal_append_quoted_argument :: proc(
    destination: []u8, used: ^int, argument: string) -> bool {
    quoted := windows_terminal_argument_needs_quotes(argument)
    if quoted && !windows_terminal_append_command_byte(destination, used, '"') {
        return false
    }
    backslashes := 0
    for byte in transmute([]u8)argument {
        if byte == '\\' {
            backslashes += 1
            continue
        }
        repeat := backslashes
        if byte == '"' {
            repeat = backslashes * 2 + 1
        }
        if !windows_terminal_append_repeated_byte(
            destination, used, '\\', repeat) {
            return false
        }
        backslashes = 0
        if !windows_terminal_append_command_byte(destination, used, byte) {
            return false
        }
    }
    if quoted {
        if !windows_terminal_append_repeated_byte(
            destination, used, '\\', backslashes * 2) {
            return false
        }
        return windows_terminal_append_command_byte(destination, used, '"')
    }
    return windows_terminal_append_repeated_byte(
        destination, used, '\\', backslashes)
}

//   Encode a process plan as one bounded Windows command line.
//
// Parameters:
//   - plan: Valid owned plan whose argument order is preserved.
//   - destination: Caller-owned UTF-8 command-line buffer.
//
// Returns:
//   - Encoded byte count and true, or zero and false when capacity is insufficient.
//
// Notes:
//   - Destination may contain a partial prefix on failure; callers must ignore it.
windows_terminal_encode_command_line :: proc(
    plan: ^Process_Plan, destination: []u8) -> (int, bool) {
    used := 0
    for index in 0..<plan.argument_count {
        if index > 0 &&
           !windows_terminal_append_command_byte(destination, &used, ' ') {
            return 0, false
        }
        if !windows_terminal_append_quoted_argument(
            destination, &used, process_plan_argument(plan, index)) {
            return 0, false
        }
    }
    return used, true
}