package termsession

import "../shell"
import "core:testing"

// Verify a successful plan owns every byte after transient inputs change.
@(test)
termsession_test_process_plan_owns_input :: proc(t: ^testing.T) {
    executable := [4]u8{'j', 'u', 'l', 'i'}
    directory := [4]u8{'/', 't', 'm', 'p'}
    key := [4]u8{'M', 'O', 'D', 'E'}
    value := [4]u8{'t', 'e', 's', 't'}
    arguments := [2]string{string(executable[:]), "a b|c"}
    environment := [1]Environment_Change{{
        kind = .Set,
        key = string(key[:]),
        value = string(value[:]),
    }}

    result := process_plan_build(arguments[:], string(directory[:]), environment[:])
    executable[0] = 'x'
    directory[1] = 'x'
    key[0] = 'X'
    value[0] = 'X'

    testing.expect_value(t, result.kind, Process_Plan_Result_Kind.Success)
    testing.expect_value(t, process_plan_argument(&result.plan, 0), "juli")
    testing.expect_value(t, process_plan_argument(&result.plan, 1), "a b|c")
    testing.expect_value(t, process_plan_working_directory(&result.plan), "/tmp")
    change, found := process_plan_environment_change(&result.plan, 0)
    testing.expect(t, found)
    testing.expect_value(t, change.key, "MODE")
    testing.expect_value(t, change.value, "test")
}

// Verify malformed semantic data is rejected before a backend can observe it.
@(test)
termsession_test_process_plan_rejects_invalid_data :: proc(t: ^testing.T) {
    empty := process_plan_build([]string{}, "/tmp", nil)
    testing.expect_value(t, empty.error, Process_Plan_Error.Empty_Arguments)

    empty_executable := [1]string{""}
    invalid_executable := process_plan_build(empty_executable[:], "/tmp", nil)
    testing.expect_value(t, invalid_executable.error,
        Process_Plan_Error.Empty_Executable)

    arguments := [1]string{"tool"}
    relative := process_plan_build(arguments[:], "relative", nil)
    testing.expect_value(t, relative.error,
        Process_Plan_Error.Invalid_Working_Directory)

    invalid_environment := [1]Environment_Change{{
        kind = .Set,
        key = "BAD=KEY",
        value = "value",
    }}
    environment := process_plan_build(
        arguments[:], "/tmp", invalid_environment[:])
    testing.expect_value(t, environment.error,
        Process_Plan_Error.Invalid_Environment_Key)
}

// Verify shell resolution freezes directly into the process-plan owner.
@(test)
termsession_test_process_plan_builds_from_resolved_command :: proc(t: ^testing.T) {
    command: shell.Resolved_Command
    copy(command.bytes[:], "toola b")
    command.byte_count = 7
    command.arguments[0] = {text_start = 0, text_end = 4}
    command.arguments[1] = {text_start = 4, text_end = 7}
    command.argument_count = 2

    result := process_plan_build_resolved(&command, "/tmp", nil)

    testing.expect_value(t, result.kind, Process_Plan_Result_Kind.Success)
    testing.expect_value(t, process_plan_argument(&result.plan, 0), "tool")
    testing.expect_value(t, process_plan_argument(&result.plan, 1), "a b")
}

// Verify forged environment spans fail canonical validation without slicing.
@(test)
termsession_test_process_plan_rejects_forged_environment_span :: proc(t: ^testing.T) {
    arguments := [1]string{"tool"}
    result := process_plan_build(arguments[:], "/tmp", nil)
    result.plan.environment_count = 1
    result.plan.environment[0].key = {start = 0, end = 9}

    error := process_plan_validate(&result.plan)

    testing.expect_value(t, error, Process_Plan_Error.Environment_Too_Long)
}