#+test
package app

import core "../core"
import evidence_session "../evidence/session"
import setting_model "../settings"
import user_data "../userdata"
import collections "../collections"
import uuid "core:encoding/uuid"

import "core:testing"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Launch_Test_Path :: struct {
    directory: string,
    filename: string,
    valid: bool,
}

// Create a deterministic UUID for persisted collection launch fixtures.
launch_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Save one Favorite fixture before exercising the startup loader.
launch_test_save_favorite :: proc(store: ^user_data.Store) -> bool {
    snapshot: collections.Set
    collections.initialize(&snapshot)
    snapshot.entries[0] = {
        id = launch_test_id(1),
        collection_id = collections.FAVORITES_COLLECTION_ID,
        kind = .Animation,
        animation_id = launch_test_id(2),
    }
    snapshot.entry_count = 1
    return user_data.store_replace_collections(store, &snapshot).kind == .None
}

// Create an isolated durable path for coordinator/store integration tests.
launch_test_path :: proc(t: ^testing.T) -> Launch_Test_Path {
    result: Launch_Test_Path
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return result
    }
    result.directory, _ = filepath.join(
        []string{temporary_directory, fmt.tprintf("euclid-launch-%x", uintptr(t))},
        context.temp_allocator)
    if len(result.directory) == 0 ||
        os.make_directory_all(result.directory) != nil {
        return result
    }
    result.filename, _ = filepath.join(
        []string{result.directory, "settings.sqlite3"}, context.temp_allocator)
    result.valid = len(result.filename) > 0
    return result
}

// Remove one isolated database fixture and its containing directory.
launch_test_path_destroy :: proc(path: Launch_Test_Path) {
    if len(path.directory) > 0 {
        _ = os.remove_all(path.directory)
    }
}

// Keep the durable store substrate reachable from the application test root.
@(test)
user_data_path_is_available_to_test_host :: proc(t: ^testing.T) {
    path, failure := user_data.default_database_path(context.temp_allocator)
    testing.expect_value(t, failure, user_data.Path_Error.None)
    testing.expect(t, len(path) > 0)
}

// Verify a no-argument launch retains the established fixed landscape-sized policy.
@(test)
window_policy_defaults_preserve_current_launch :: proc(t: ^testing.T) {
    state := default_window_parse_state()

    testing.expect_value(t, state.preference.width, 1280)
    testing.expect_value(t, state.preference.height, 720)
    testing.expect_value(t, state.preference.mode, setting_model.Window_Mode.Fixed)
    testing.expect_value(t, state.preference.layout, setting_model.Layout_Preference.Auto)
    testing.expect(t, !state.custom_size_set)
}

// Verify all valid startup-window option classes produce typed settings.
@(test)
window_policy_arguments_parse_valid_values :: proc(t: ^testing.T) {
    state := default_window_parse_state()

    testing.expect(t, parse_window_policy_param(
        "--window-preset=portrait", &state))
    testing.expect_value(t, state.preference.width, 640)
    testing.expect_value(t, state.preference.height, 720)
    parse_window_policy_param("--window-preset=landscape", &state)
    testing.expect_value(t, state.preference.width, 1280)
    testing.expect(t, parse_window_policy_param(
        "--window-mode=resizable", &state))
    testing.expect_value(t, state.preference.mode, setting_model.Window_Mode.Resizable)
    parse_window_policy_param("--window-mode=fixed", &state)
    testing.expect_value(t, state.preference.mode, setting_model.Window_Mode.Fixed)
    testing.expect(t, parse_window_policy_param("--layout=portrait", &state))
    testing.expect_value(t, state.preference.layout,
        setting_model.Layout_Preference.Portrait)
    parse_window_policy_param("--layout=landscape", &state)
    testing.expect_value(t, state.preference.layout,
        setting_model.Layout_Preference.Landscape)
}

// Verify custom dimensions dominate presets while later custom dimensions win.
@(test)
window_policy_custom_size_has_preset_precedence :: proc(t: ^testing.T) {
    state := default_window_parse_state()

    parse_window_policy_param("--window-preset=portrait", &state)
    parse_window_policy_param("--window-size=900x1100", &state)
    parse_window_policy_param("--window-preset=landscape", &state)
    testing.expect_value(t, state.preference.width, 900)
    testing.expect_value(t, state.preference.height, 1100)

    parse_window_policy_param("--window-size=1024x768", &state)
    testing.expect_value(t, state.preference.width, 1024)
    testing.expect_value(t, state.preference.height, 768)
}

// Verify malformed options are handled atomically and retain prior valid values.
@(test)
window_policy_invalid_values_preserve_prior_policy :: proc(t: ^testing.T) {
    state := default_window_parse_state()
    parse_window_policy_param("--window-size=800x600", &state)
    parse_window_policy_param("--window-size=100xgarbage", &state)
    parse_window_policy_param("--window-size=319x240", &state)
    parse_window_policy_param("--window-size=320x16385", &state)
    parse_window_policy_param("--window-mode=fluid", &state)
    parse_window_policy_param("--layout=square", &state)
    parse_window_policy_param("--window-preset=wide", &state)

    testing.expect_value(t, state.preference.width, 800)
    testing.expect_value(t, state.preference.height, 600)
    testing.expect_value(t, state.preference.mode, setting_model.Window_Mode.Fixed)
    testing.expect_value(t, state.preference.layout, setting_model.Layout_Preference.Auto)
    testing.expect(t, state.custom_size_set)
}

// Verify diagnostics paths are bounded and invalid values preserve prior settings.
@(test)
diagnostics_argument_configures_logging_path :: proc(t: ^testing.T) {
    settings: core.Euclid_Run_Settings

    window_state := default_window_parse_state()
    parse_command_line_param("--diagnostics=.build/euclid.log", &settings, &window_state)
    testing.expect_value(t, settings.diagnostics_path, ".build/euclid.log")

    parse_command_line_param("--diagnostics=", &settings, &window_state)
    testing.expect_value(t, settings.diagnostics_path, ".build/euclid.log")
}

// Verify the Spall spelling and retained timing-profile alias select one output path.
@(test)
profile_arguments_configure_spall_path :: proc(t: ^testing.T) {
    settings: core.Euclid_Run_Settings

    window_state := default_window_parse_state()
    parse_command_line_param(
        "--profile=spall:.build/euclid.spall", &settings, &window_state)
    testing.expect_value(t, settings.profile_path,
        ".build/euclid.spall")

    parse_command_line_param("--profile=spall:", &settings, &window_state)
    testing.expect_value(t, settings.profile_path,
        ".build/euclid.spall")

    parse_command_line_param(
        "--timing-profile=.build/legacy.spall", &settings, &window_state)
    testing.expect_value(t, settings.profile_path,
        ".build/legacy.spall")
}

// Verify repository test builds retain the debug-only scenario CLI capability.
@(test)
scenario_arguments_configure_debug_automation :: proc(t: ^testing.T) {
    testing.expect(t, core.SCENARIOS_ENABLED)
    settings: core.Euclid_Run_Settings
    window_state := default_window_parse_state()

    parse_command_line_param(
        "--scenario=tools/scenarios/example.jsonl", &settings, &window_state)
    parse_command_line_param(
        "--scenario-artifacts=.build/scenario", &settings, &window_state)

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

// Verify final command-line values and presence masks cover every CLI preference.
launch_expect_cli_override_ids :: proc(
    t: ^testing.T, overrides: setting_model.Setting_Set) {
    ids := [10]setting_model.Setting_Id{
        .Window_Width, .Window_Height, .Window_Mode, .Window_Layout,
        .Rendering_Vsync, .Rendering_Antialiasing, .Rendering_Limit_Fps,
        .Rendering_Simd, .Rendering_Gpu_Dust_Instancing, .Drawing_Dust_Limit,
    }
    for id in ids {
        testing.expect(t, id in overrides)
    }
}

// Verify final command-line values and masks cover every CLI-backed setting.
@(test)
cli_preferences_capture_explicit_final_values :: proc(t: ^testing.T) {
    launch := parse_command_line([]string{
        "--window-preset=portrait",
        "--window-size=900x1000",
        "--window-preset=landscape",
        "--window-mode=resizable",
        "--layout=landscape",
        "--vsync",
        "--no-vsync",
        "--no-antialiasing",
        "--no-limit-fps",
        "--no-simd",
        "--no-gpu-dust-instancing",
        "--dust-particle-max=1000",
    })
    state := launch.parse_state
    launch_expect_cli_override_ids(t, state.override_mask)
    testing.expect_value(t, state.preference.width, 900)
    testing.expect_value(t, state.preference.height, 1000)
    testing.expect_value(t, state.preference.mode,
        setting_model.Window_Mode.Resizable)
    testing.expect_value(t, state.preference.layout,
        setting_model.Layout_Preference.Landscape)
    testing.expect(t, !launch.run_settings.do_vsync)
    testing.expect(t, !launch.run_settings.do_antialiasing)
    testing.expect(t, !launch.run_settings.limit_fps)
    testing.expect(t, !launch.run_settings.use_simd_batch_projection)
    testing.expect(t, !launch.run_settings.use_gpu_dust_instancing)
    testing.expect_value(t, launch.run_settings.dust_particle_max, 1000)
    changes := launch_override_batch(state)
    testing.expect_value(t, changes.count, 10)
}

// Verify operational flags never enter a persisted preference change batch.
@(test)
operational_arguments_are_excluded_from_persistence :: proc(t: ^testing.T) {
    launch := parse_command_line([]string{
        "--persist",
        "--user-db=.build/launch-test.sqlite3",
        "--diagnostics=.build/launch.log",
        "--profile=spall:.build/launch.spall",
        "--semantic-trace",
        "--scenario=tools/scenarios/example.jsonl",
    })
    testing.expect(t, !launch_has_overrides(launch.parse_state))
    testing.expect_value(t, launch_override_batch(launch.parse_state).count, 0)
}

// Verify invalid persisted arguments and DB conflicts fail before opening paths.
@(test)
persist_validation_rejects_without_database_side_effects :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        "--persist",
        "--window-size=invalid",
        fmt.tprintf("--user-db=%s", path.filename),
    })
    preferences: setting_model.Preferences
    store: user_data.Store
    opened := false
    testing.expect(t, !launch_prepare_preferences(
        launch, &preferences, &store, &opened))
    testing.expect(t, !opened)
    testing.expect(t, !os.exists(path.filename))

    conflict := parse_command_line([]string{
        "--no-user-db",
        fmt.tprintf("--user-db=%s", path.filename),
    })
    testing.expect(t, !launch_prepare_preferences(
        conflict, &preferences, &store, &opened))
    testing.expect(t, !os.exists(path.filename))
    launch_test_path_destroy(path)
}

// Verify help exits before any custom database path can be admitted.
@(test)
help_precedes_database_side_effects :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        "--help",
        fmt.tprintf("--user-db=%s", path.filename),
    })
    testing.expect(t, !launch.run_settings.do_run)
    testing.expect(t, !os.exists(path.filename))
    launch_test_path_destroy(path)
}

// Verify --persist with no explicit preferences opens no write transaction.
@(test)
persist_without_overrides_is_noop :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        "--persist",
        fmt.tprintf("--user-db=%s", path.filename),
    })
    preferences: setting_model.Preferences
    store: user_data.Store
    opened := false
    testing.expect(t, launch_prepare_preferences(
        launch, &preferences, &store, &opened))
    testing.expect(t, opened)
    testing.expect_value(t, preferences.present, setting_model.Setting_Set{})
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
    failure := user_data.store_open(&store, path.filename)
    testing.expect_value(t, failure.kind, user_data.Store_Error_Kind.None)
    loaded_preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(&store, &loaded_preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect_value(t, loaded_preferences.present, setting_model.Setting_Set{})
    _ = user_data.store_close(&store)
    launch_test_path_destroy(path)
}

// Load the persisted collection snapshot at the application startup boundary.
@(test)
launch_loads_saved_collections_before_runtime_handoff :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    if !path.valid {
        return
    }
    defer launch_test_path_destroy(path)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    testing.expect(t, launch_test_save_favorite(&store))
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)

    launch := parse_command_line([]string{
        fmt.tprintf("--user-db=%s", path.filename),
    })
    preferences: setting_model.Preferences
    loaded_collections: collections.Set
    opened := false
    testing.expect(t, launch_prepare_preferences(
        launch, &preferences, &store, &opened, &loaded_collections))
    testing.expect(t, opened)
    testing.expect_value(t, loaded_collections.entry_count, 1)
    testing.expect_value(t, loaded_collections.entries[0].id, launch_test_id(1))
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
}

// Verify explicitly passing a default value persists and is restored as saved.
@(test)
explicit_default_override_is_persisted :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        "--persist",
        "--vsync",
        fmt.tprintf("--user-db=%s", path.filename),
    })
    preferences: setting_model.Preferences
    store: user_data.Store
    opened := false
    testing.expect(t, launch_prepare_preferences(
        launch, &preferences, &store, &opened))
    testing.expect(t, opened)
    testing.expect(t, .Rendering_Vsync in preferences.overrides)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)

    failure := user_data.store_open(&store, path.filename)
    testing.expect_value(t, failure.kind, user_data.Store_Error_Kind.None)
    loaded_preferences := setting_model.default_preferences()
    loaded := user_data.store_load_settings(&store, &loaded_preferences)
    testing.expect_value(t, loaded.failure.kind, user_data.Store_Error_Kind.None)
    testing.expect(t, .Rendering_Vsync in loaded_preferences.present)
    testing.expect(t, loaded_preferences.rendering.vsync)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
    launch_test_path_destroy(path)
}

// Verify no-user-db leaves the store untouched and preference edits in memory.
@(test)
disabled_database_uses_defaults_without_opening_store :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        "--no-user-db",
        "--window-size=900x700",
    })
    preferences: setting_model.Preferences
    store: user_data.Store
    opened := false
    testing.expect(t, launch_prepare_preferences(
        launch, &preferences, &store, &opened))
    testing.expect(t, !opened)
    testing.expect(t, !os.exists(path.filename))
    testing.expect_value(t, preferences.window.width, 900)
    launch_test_path_destroy(path)
}

// Verify a relative custom path is resolved and isolated from the default store.
@(test)
custom_relative_database_path_isolated :: proc(t: ^testing.T) {
    relative_path := fmt.tprintf(".build/launch-%x.sqlite3", uintptr(t))
    launch := parse_command_line([]string{
        fmt.tprintf("--user-db=%s", relative_path),
    })
    store: user_data.Store
    opened := false
    testing.expect(t, launch_open_store(&store, launch.parse_state, &opened))
    testing.expect(t, opened)
    expected_path, path_error := user_data.resolve_database_path(
        relative_path, context.temp_allocator)
    testing.expect_value(t, path_error, user_data.Path_Error.None)
    testing.expect_value(t, string(store.path[:store.path_length]), expected_path)
    testing.expect_value(t, user_data.store_close(&store).kind,
        user_data.Store_Error_Kind.None)
    _ = os.remove(relative_path)
}

// Verify a rejected custom database is fatal and never falls back to defaults.
@(test)
invalid_custom_database_fails_launch_preparation :: proc(t: ^testing.T) {
    path := launch_test_path(t)
    testing.expect(t, path.valid)
    launch := parse_command_line([]string{
        fmt.tprintf("--user-db=%s", path.directory),
    })
    preferences: setting_model.Preferences
    store: user_data.Store
    opened := false
    testing.expect(t, !launch_prepare_preferences(
        launch, &preferences, &store, &opened))
    testing.expect(t, !opened)
    launch_test_path_destroy(path)
}
