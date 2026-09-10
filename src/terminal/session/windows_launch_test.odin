#+test
package termsession

import "core:testing"

// Encode one fixture and compare it with its expected Windows command line.
windows_terminal_test_command_line :: proc(
    t: ^testing.T, arguments: []string, expected: string) {
    result := process_plan_build(arguments, "/tmp", nil)
    testing.expect_value(t, result.kind, Process_Plan_Result_Kind.Success)
    destination: [PROCESS_PLAN_ARGUMENT_TOTAL_MAX_BYTES * 2]u8
    count, valid := windows_terminal_encode_command_line(
        &result.plan, destination[:])
    testing.expect(t, valid)
    testing.expect_value(t, string(destination[:count]), expected)
}

// Verify quoting for empty, whitespace, quote, slash, and metacharacter cases.
@(test)
windows_terminal_test_command_line_quoting :: proc(t: ^testing.T) {
    empty := [2]string{"program", ""}
    windows_terminal_test_command_line(t, empty[:], "program \"\"")

    whitespace := [3]string{"program", "two words", "tab\tvalue"}
    windows_terminal_test_command_line(
        t, whitespace[:], "program \"two words\" \"tab\tvalue\"")

    quotes := [2]string{"program", "a\"b"}
    windows_terminal_test_command_line(t, quotes[:], "program \"a\\\"b\"")

    trailing := [2]string{"program", "C:\\path with space\\"}
    windows_terminal_test_command_line(
        t, trailing[:], "program \"C:\\path with space\\\\\"")

    metacharacters := [3]string{"program", "$|", "line\nbreak"}
    windows_terminal_test_command_line(
        t, metacharacters[:], "program $| line\nbreak")
}

// Verify command-line encoding rejects an undersized destination.
@(test)
windows_terminal_test_command_line_capacity :: proc(t: ^testing.T) {
    arguments := [2]string{"program", "two words"}
    result := process_plan_build(arguments[:], "/tmp", nil)
    destination: [8]u8
    _, valid := windows_terminal_encode_command_line(
        &result.plan, destination[:])
    testing.expect(t, !valid)
}