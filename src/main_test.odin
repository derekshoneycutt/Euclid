#+test
package main

import core "core"
import evidence_session "evidence/session"

import "core:testing"

// Verify a no-argument launch retains the established fixed landscape-sized policy.
@(test)
window_policy_defaults_preserve_current_launch :: proc(t: ^testing.T) {
    policy := default_window_startup_policy()

    testing.expect_value(t, policy.width, 1280)
    testing.expect_value(t, policy.height, 720)
    testing.expect_value(t, policy.mode, core.Window_Mode.Fixed)
    testing.expect_value(t, policy.layout, core.Layout_Preference.Auto)
    testing.expect(t, !policy.custom_size_set)
}

// Verify all valid startup-window option classes produce typed settings.
@(test)
window_policy_arguments_parse_valid_values :: proc(t: ^testing.T) {
    policy := default_window_startup_policy()

    testing.expect(t, parse_window_policy_param(
        "--window-preset=portrait", &policy))
    testing.expect_value(t, policy.width, 640)
    testing.expect_value(t, policy.height, 720)
    parse_window_policy_param("--window-preset=landscape", &policy)
    testing.expect_value(t, policy.width, 1280)
    testing.expect(t, parse_window_policy_param(
        "--window-mode=resizable", &policy))
    testing.expect_value(t, policy.mode, core.Window_Mode.Resizable)
    parse_window_policy_param("--window-mode=fixed", &policy)
    testing.expect_value(t, policy.mode, core.Window_Mode.Fixed)
    testing.expect(t, parse_window_policy_param("--layout=portrait", &policy))
    testing.expect_value(t, policy.layout, core.Layout_Preference.Portrait)
    parse_window_policy_param("--layout=landscape", &policy)
    testing.expect_value(t, policy.layout, core.Layout_Preference.Landscape)
}

// Verify custom dimensions dominate presets while later custom dimensions win.
@(test)
window_policy_custom_size_has_preset_precedence :: proc(t: ^testing.T) {
    policy := default_window_startup_policy()

    parse_window_policy_param("--window-preset=portrait", &policy)
    parse_window_policy_param("--window-size=900x1100", &policy)
    parse_window_policy_param("--window-preset=landscape", &policy)
    testing.expect_value(t, policy.width, 900)
    testing.expect_value(t, policy.height, 1100)

    parse_window_policy_param("--window-size=1024x768", &policy)
    testing.expect_value(t, policy.width, 1024)
    testing.expect_value(t, policy.height, 768)
}

// Verify malformed options are handled atomically and retain prior valid values.
@(test)
window_policy_invalid_values_preserve_prior_policy :: proc(t: ^testing.T) {
    policy := default_window_startup_policy()
    parse_window_policy_param("--window-size=800x600", &policy)
    parse_window_policy_param("--window-size=100xgarbage", &policy)
    parse_window_policy_param("--window-size=319x240", &policy)
    parse_window_policy_param("--window-size=320x16385", &policy)
    parse_window_policy_param("--window-mode=fluid", &policy)
    parse_window_policy_param("--layout=square", &policy)
    parse_window_policy_param("--window-preset=wide", &policy)

    testing.expect_value(t, policy.width, 800)
    testing.expect_value(t, policy.height, 600)
    testing.expect_value(t, policy.mode, core.Window_Mode.Fixed)
    testing.expect_value(t, policy.layout, core.Layout_Preference.Auto)
    testing.expect(t, policy.custom_size_set)
}

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

// Verify repository test builds retain the debug-only scenario CLI capability.
@(test)
scenario_arguments_configure_debug_automation :: proc(t: ^testing.T) {
    testing.expect(t, core.SCENARIOS_ENABLED)
    settings: core.Euclid_Run_Settings

    parse_command_line_param("--scenario=tools/scenarios/example.jsonl", &settings)
    parse_command_line_param("--scenario-artifacts=.build/scenario", &settings)

    testing.expect_value(t, settings.scenario_input,
        "tools/scenarios/example.jsonl")
    testing.expect_value(t, settings.scenario_artifact_output, ".build/scenario")
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
