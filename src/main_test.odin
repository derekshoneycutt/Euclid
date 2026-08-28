#+test
package main

import core "core"
import evidence_session "evidence/session"

import "core:testing"

// Verify diagnostics paths are bounded and invalid values preserve prior settings.
@(test)
diagnostics_argument_configures_logging_path :: proc(t: ^testing.T) {
    settings: core.Euclid_Run_Settings

    parse_command_line_param("--diagnostics=.build/euclid.log", &settings)
    testing.expect_value(t, settings.diagnostics_path, ".build/euclid.log")

    parse_command_line_param("--diagnostics=", &settings)
    testing.expect_value(t, settings.diagnostics_path, ".build/euclid.log")
}

// Verify the Spall spelling and retained timing-profile alias select one output path.
@(test)
profile_arguments_configure_spall_path :: proc(t: ^testing.T) {
    settings: core.Euclid_Run_Settings

    parse_command_line_param("--profile=spall:.build/euclid.spall", &settings)
    testing.expect_value(t, settings.profile_path,
        ".build/euclid.spall")

    parse_command_line_param("--profile=spall:", &settings)
    testing.expect_value(t, settings.profile_path,
        ".build/euclid.spall")

    parse_command_line_param("--timing-profile=.build/legacy.spall", &settings)
    testing.expect_value(t, settings.profile_path,
        ".build/legacy.spall")
}

// Verify retained semantic-trace options configure the typed evidence session.
@(test)
semantic_trace_arguments_configure_evidence_policy :: proc(t: ^testing.T) {
    config := evidence_session.Config{lanes = evidence_session.ALL_LANES}

    handled, valid := parse_semantic_trace_argument("--semantic-trace", &config)
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect(t, config.enabled)
    testing.expect_value(t, config.output_mode, evidence_session.Output_Mode.Stdout)

    handled, valid = parse_semantic_trace_argument(
        "--semantic-trace-events=runtime,domain", &config)
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect(t, .Lifecycle in config.lanes)
    testing.expect(t, .Domain in config.lanes)

    handled, valid = parse_semantic_trace_argument(
        "--semantic-trace-output=/tmp/euclid-evidence.jsonl", &config)
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect_value(t, config.output_mode, evidence_session.Output_Mode.File)
    testing.expect_value(t, config.output_path, "/tmp/euclid-evidence.jsonl")

    handled, valid = parse_semantic_trace_argument(
        "--semantic-trace-strict", &config)
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect(t, config.strict)

    handled, valid = parse_semantic_trace_argument(
        "--semantic-trace-events=", &config)
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect_value(t, config.lanes, evidence_session.ALL_LANES)
}

// Verify invalid evidence selections are recognized without changing lane policy.
@(test)
semantic_trace_arguments_reject_unknown_lane :: proc(t: ^testing.T) {
    config := evidence_session.Config{lanes = evidence_session.ALL_LANES}
    original_lanes := config.lanes

    handled, valid := parse_semantic_trace_argument(
        "--semantic-trace-events=domain,unknown", &config)

    testing.expect(t, handled)
    testing.expect(t, !valid)
    testing.expect_value(t, config.lanes, original_lanes)

    handled, valid = parse_semantic_trace_argument(
        "--semantic-trace-output=", &config)
    testing.expect(t, handled)
    testing.expect(t, !valid)
}
