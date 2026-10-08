package app

import core "../core"
import diagnostics "../diagnostics"
import evidence_allocation "../evidence/allocation"
import evidence_session "../evidence/session"
import setting_model "../settings"
import user_data "../userdata"
import view "../view"
import fmt "core:fmt"
import log "core:log"
import os "core:os"
import strconv "core:strconv"
import strings "core:strings"

COMMAND_LINE_PATH_MAX_BYTES :: 4096
DIAGNOSTICS_OPTION_PREFIX :: "--diagnostics="
DUST_PARTICLE_MAX_PREFIX :: "--dust-particle-max="
WINDOW_PRESET_PREFIX :: "--window-preset="
WINDOW_SIZE_PREFIX :: "--window-size="
WINDOW_MODE_PREFIX :: "--window-mode="
LAYOUT_PREFIX :: "--layout="
TIMING_PROFILE_PREFIX :: "--timing-profile="
PROFILE_OPTION_PREFIX :: "--profile=spall:"
USER_DB_OPTION_PREFIX :: "--user-db="
SEMANTIC_TRACE_OUTPUT_PREFIX :: "--semantic-trace-output="
SEMANTIC_TRACE_EVENTS_PREFIX :: "--semantic-trace-events="
when core.SCENARIOS_ENABLED {
    SCENARIO_INPUT_PREFIX :: "--scenario="
    SCENARIO_ARTIFACT_PREFIX :: "--scenario-artifacts="
}

Launch_Parse_State :: struct {
    preference: setting_model.Window_Startup_Policy,
    custom_size_set: bool,
    preference_values: setting_model.Preferences,
    override_mask: setting_model.Setting_Set,
    invalid_preference: bool,
    persist_requested: bool,
    no_user_db: bool,
    custom_user_db_requested: bool,
    user_db_filename: string,
    invalid_launch_option: bool,
}

Launch_Configuration :: struct {
    run_settings: core.Euclid_Run_Settings,
    parse_state: Launch_Parse_State,
}

// Run the app coordinator from argument parsing through store teardown.
run_application :: proc(
    log_level: log.Level,
    process_allocations: ^evidence_allocation.Domain = nil) -> int {
    launch := parse_command_line(os.args[1:])
    if !launch.run_settings.do_run {
        return 0
    }
    return run_resolved_application(launch, log_level, process_allocations)
}

// Resolve saved settings and explicit overrides before creating the native window.
run_resolved_application :: proc(
    launch: Launch_Configuration,
    log_level: log.Level,
    process_allocations: ^evidence_allocation.Domain) -> int {
    state := launch.parse_state
    if !launch_options_valid(state) {
        fmt.eprintln("Invalid or conflicting user database launch options.")
        return 1
    }
    settings := launch.run_settings
    settings.evidence_allocations = process_allocations
    logging_state: diagnostics.Logging_State
    selected_logger := context.logger
    if len(settings.diagnostics_path) > 0 {
        if diagnostics.logging_start(
            &logging_state, settings.diagnostics_path, log_level) {
            selected_logger = logging_state.logger
        } else {
            fmt.eprintln("Unable to open diagnostics: ", settings.diagnostics_path)
        }
    }
    context.logger = selected_logger
    defer {
        context.logger = log.nil_logger()
        diagnostics.logging_stop(&logging_state)
    }
    fmt.println("Initiating Euclid...")
    log.info("application_start")
    exit_code := launch_run_session(launch, &settings)
    free_all(context.temp_allocator)
    log.infof("application_stop exit_code=%d", exit_code)
    fmt.println("Euclid ended")
    return exit_code
}

// Keep the resolved database alive until the view session has shut down.
launch_run_session :: proc(
    launch: Launch_Configuration,
    settings: ^core.Euclid_Run_Settings) -> int {
    resolved: setting_model.Preferences
    store: user_data.Store
    store_opened := false
    if !launch_prepare_preferences(
        launch, &resolved, &store, &store_opened) {
        return 1
    }
    return launch_run_view(settings, resolved, &store, &store_opened)
}

// Run the view with resolved inputs and close the borrowed store afterward.
launch_run_view :: proc(
    settings: ^core.Euclid_Run_Settings,
    preferences: setting_model.Preferences,
    store: ^user_data.Store,
    store_opened: ^bool) -> int {
    launch_apply_preferences(settings, preferences)
    print_startup_settings(settings)
    startup := view.Session_Startup_Inputs{
        preferences = preferences,
        user_store = store_opened^ ? store : nil,
    }
    exit_code := view.run_window_loop(settings, &startup)
    if !store_opened^ {
        return exit_code
    }
    close_error := user_data.store_close(store)
    store_opened^ = false
    if close_error.kind != .None {
        fmt.eprintln("Unable to close settings database: ", close_error.kind)
        return exit_code == 0 ? 1 : exit_code
    }
    return exit_code
}

// Validate launch-only conflicts before any durable path or database work.
launch_options_valid :: proc(state: Launch_Parse_State) -> bool {
    return !state.invalid_launch_option &&
        !(state.no_user_db &&
            (state.persist_requested || state.custom_user_db_requested)) &&
        !(state.persist_requested && state.invalid_preference)
}

// Resolve saved values, explicit overrides, and optional transactional persistence.
launch_prepare_preferences :: proc(
    launch: Launch_Configuration,
    preferences: ^setting_model.Preferences,
    store: ^user_data.Store,
    store_opened: ^bool) -> bool {
    state := launch.parse_state
    if !launch_options_valid(state) {
        return false
    }
    preferences^ = setting_model.default_preferences()
    if !state.no_user_db {
        store_available := launch_open_store(store, state, store_opened)
        if !store_available &&
            (state.custom_user_db_requested || state.persist_requested) {
            return false
        }
        if store_opened^ && !launch_load_preferences(
            store, state, preferences, store_opened) {
            return false
        }
    }
    launch_apply_overrides(preferences, state)
    return !state.persist_requested ||
        launch_commit_overrides(store, state, store_opened)
}

// Load saved rows, falling back only for an unavailable default store.
launch_load_preferences :: proc(
    store: ^user_data.Store,
    state: Launch_Parse_State,
    preferences: ^setting_model.Preferences,
    store_opened: ^bool) -> bool {
    loaded := user_data.store_load_settings(store, preferences)
    if loaded.failure.kind == .None {
        for index in 0..<loaded.invalid_count {
            log.warnf("saved_setting_ignored setting=%d reason=%d",
                int(loaded.invalid_values[index].id),
                int(loaded.invalid_values[index].reason))
        }
        return true
    }
    fmt.eprintln("Unable to load saved settings: ", loaded.failure.kind)
    _ = user_data.store_close(store)
    store_opened^ = false
    if state.custom_user_db_requested || state.persist_requested {
        return false
    }
    preferences^ = setting_model.default_preferences()
    return true
}

// Commit only the validated explicit preference values for this invocation.
launch_commit_overrides :: proc(
    store: ^user_data.Store,
    state: Launch_Parse_State,
    store_opened: ^bool) -> bool {
    if !launch_has_overrides(state) {
        return true
    }
    if !store_opened^ {
        return false
    }
    committed := user_data.store_commit_batch(store, launch_override_batch(state))
    if committed.outcome == .Committed {
        return true
    }
    fmt.eprintln("Unable to persist explicit settings: ", committed.failure.kind)
    _ = user_data.store_close(store)
    store_opened^ = false
    return false
}

// Report whether any preference was explicitly supplied on this invocation.
launch_has_overrides :: proc(state: Launch_Parse_State) -> bool {
    for id in setting_model.ALL_SETTING_IDS {
        if id in state.override_mask {
            return true
        }
    }
    return false
}

// Open the selected store while preserving explicit-path versus default policy.
launch_open_store :: proc(
    store: ^user_data.Store,
    state: Launch_Parse_State,
    opened: ^bool) -> bool {
    if state.custom_user_db_requested {
        failure := user_data.store_open(store, state.user_db_filename)
        if failure.kind != .None {
            fmt.eprintln("Unable to open requested settings database: ", failure.kind)
            return false
        }
        opened^ = true
        return true
    }
    path, path_error := user_data.default_database_path(context.allocator)
    if path_error != .None {
        fmt.eprintln("Unable to resolve default settings database path: ", path_error)
        return false
    }
    defer delete(path, context.allocator)
    failure := user_data.store_open(store, path)
    if failure.kind != .None {
        log.warnf("default_settings_store_unavailable error=%d", int(failure.kind))
        return false
    }
    opened^ = true
    return true
}

// Apply only explicitly supplied values after saved settings have been loaded.
launch_apply_overrides :: proc(
    preferences: ^setting_model.Preferences, state: Launch_Parse_State) {
    for id in setting_model.ALL_SETTING_IDS {
        if id in state.override_mask {
            _ = setting_model.apply_setting_value(
                preferences, id,
                setting_model.setting_value(state.preference_values, id), .Override)
        }
    }
}

// Build the bounded transaction from explicit preference arguments only.
launch_override_batch :: proc(state: Launch_Parse_State) -> setting_model.Change_Set {
    changes: setting_model.Change_Set
    for id in setting_model.ALL_SETTING_IDS {
        if id in state.override_mask {
            _ = setting_model.change_set_set(
                &changes, id, setting_model.setting_value(state.preference_values, id))
        }
    }
    return changes
}

// Copy resolved user preferences into the native run configuration.
launch_apply_preferences :: proc(
    run: ^core.Euclid_Run_Settings, preferences: setting_model.Preferences) {
    run^.window = preferences.window
    run^.do_vsync = preferences.rendering.vsync
    run^.do_antialiasing = preferences.rendering.antialiasing
    run^.limit_fps = preferences.rendering.limit_fps
    run^.use_simd_batch_projection = preferences.rendering.simd
    run^.use_gpu_dust_instancing = preferences.rendering.gpu_dust_instancing
    run^.dust_particle_max = preferences.drawing.dust_limit
}


//  Parse one bounded dust-capacity option and report whether it matched.
parse_dust_particle_max_param :: proc(
    arg: string, settings: ^core.Euclid_Run_Settings,
    state: ^Launch_Parse_State) -> bool {
    if len(arg) < len(DUST_PARTICLE_MAX_PREFIX) ||
        arg[:len(DUST_PARTICLE_MAX_PREFIX)] != DUST_PARTICLE_MAX_PREFIX {
        return false
    }

    value_text := arg[len(DUST_PARTICLE_MAX_PREFIX):]
    value, ok := strconv.parse_i64_of_base(value_text, 10)
    if !ok || !setting_model.valid_dust_limit(value) {
        state^.invalid_preference = true
        fmt.println(fmt.tprintf(
            "Invalid --dust-particle-max value: %s. Expected 0-%d.",
            value_text,
            setting_model.DUST_LIMIT_MAX))
        return true
    }

    settings.dust_particle_max = int(value)
    launch_record_override(
        state, .Drawing_Dust_Limit, setting_model.integer_value(int(value)))
    return true
}

// Keep argument-only sizing precedence separate from persistent preference data.
default_window_parse_state :: proc() -> Launch_Parse_State {
    defaults := setting_model.default_preferences()
    return {
        preference = defaults.window,
        preference_values = defaults,
    }
}

//  Apply one semantic window-size preset without overriding a custom size.
parse_window_preset_param :: proc(
    arg: string, state: ^Launch_Parse_State) -> bool {
    if !strings.has_prefix(arg, WINDOW_PRESET_PREFIX) {
        return false
    }
    value := arg[len(WINDOW_PRESET_PREFIX):]
    if value != "landscape" && value != "portrait" {
        state^.invalid_preference = true
        fmt.println("Invalid --window-preset value: ", value)
        return true
    }
    if state^.custom_size_set {
        return true
    }
    if value == "landscape" {
        state^.preference.width = setting_model.WINDOW_LANDSCAPE_WIDTH
        state^.preference.height = setting_model.WINDOW_LANDSCAPE_HEIGHT
    } else {
        state^.preference.width = setting_model.WINDOW_PORTRAIT_WIDTH
        state^.preference.height = setting_model.WINDOW_PORTRAIT_HEIGHT
    }
    launch_record_window_size_override(state)
    return true
}

//  Apply one custom WIDTHxHEIGHT option transactionally.
parse_window_size_param :: proc(
    arg: string, state: ^Launch_Parse_State) -> bool {
    if !strings.has_prefix(arg, WINDOW_SIZE_PREFIX) {
        return false
    }
    value := arg[len(WINDOW_SIZE_PREFIX):]
    separator := strings.index_byte(value, 'x')
    if separator < 1 || separator == len(value) - 1 {
        state^.invalid_preference = true
        fmt.println("Invalid --window-size value: ", value)
        return true
    }
    width, width_ok := strconv.parse_i64_of_base(value[:separator], 10)
    height, height_ok := strconv.parse_i64_of_base(value[separator + 1:], 10)
    if !width_ok || !height_ok || !setting_model.valid_window_dimensions(width, height) {
        state^.invalid_preference = true
        fmt.println("Invalid --window-size value: ", value)
        return true
    }
    state^.preference.width = int(width)
    state^.preference.height = int(height)
    state^.custom_size_set = true
    launch_record_window_size_override(state)
    return true
}

//  Apply one fixed or resizable window policy option.
parse_window_mode_param :: proc(
    arg: string, state: ^Launch_Parse_State) -> bool {
    if !strings.has_prefix(arg, WINDOW_MODE_PREFIX) {
        return false
    }
    switch arg[len(WINDOW_MODE_PREFIX):] {
    case "fixed":
        state^.preference.mode = .Fixed
    case "resizable":
        state^.preference.mode = .Resizable
    case:
        state^.invalid_preference = true
        fmt.println("Invalid --window-mode value: ", arg[len(WINDOW_MODE_PREFIX):])
    }
    mode_argument := arg[len(WINDOW_MODE_PREFIX):]
    if mode_argument == "fixed" || mode_argument == "resizable" {
        launch_record_override(
            state, .Window_Mode,
            setting_model.window_mode_value(state^.preference.mode))
    }
    return true
}

//  Apply one automatic or forced layout preference option.
parse_layout_param :: proc(
    arg: string, state: ^Launch_Parse_State) -> bool {
    if !strings.has_prefix(arg, LAYOUT_PREFIX) {
        return false
    }
    switch arg[len(LAYOUT_PREFIX):] {
    case "auto":
        state^.preference.layout = .Auto
    case "landscape":
        state^.preference.layout = .Landscape
    case "portrait":
        state^.preference.layout = .Portrait
    case:
        state^.invalid_preference = true
        fmt.println("Invalid --layout value: ", arg[len(LAYOUT_PREFIX):])
    }
    layout_argument := arg[len(LAYOUT_PREFIX):]
    if layout_argument == "auto" || layout_argument == "landscape" ||
        layout_argument == "portrait" {
        launch_record_override(
            state, .Window_Layout,
            setting_model.layout_preference_value(state^.preference.layout))
    }
    return true
}

//  Apply one typed startup-window option and report whether it matched.
parse_window_policy_param :: proc(
    arg: string, state: ^Launch_Parse_State) -> bool {
    return parse_window_preset_param(arg, state) ||
        parse_window_size_param(arg, state) ||
        parse_window_mode_param(arg, state) || parse_layout_param(arg, state)
}

// Print the database-selection and preference-persistence options.
print_user_database_help :: proc() {
    fmt.println("  --user-db=FILENAME       Use a custom settings database.")
    fmt.println("  --no-user-db             Disable saved settings for this run.")
    fmt.println("  --persist                Save explicit preference arguments.")
}

// Record one final explicit value without changing its persistent identity.
launch_record_override :: proc(
    state: ^Launch_Parse_State,
    id: setting_model.Setting_Id,
    value: setting_model.Setting_Value) {
    _ = setting_model.apply_setting_value(
        &state^.preference_values, id, value, .Override)
    state^.override_mask += setting_model.Setting_Set{id}
}

// Record both dimensions as one explicit result of a preset or custom size.
launch_record_window_size_override :: proc(state: ^Launch_Parse_State) {
    launch_record_override(state, .Window_Width,
        setting_model.integer_value(state^.preference.width))
    launch_record_override(state, .Window_Height,
        setting_model.integer_value(state^.preference.height))
}

// Record every recognized boolean CLI preference after applying its argument.
launch_record_boolean_overrides :: proc(
    arg: string, run: core.Euclid_Run_Settings, state: ^Launch_Parse_State) {
    if arg == "--vsync" || arg == "--no-vsync" || arg == "-v" || arg == "-V" {
        launch_record_override(state, .Rendering_Vsync,
            setting_model.boolean_value(run.do_vsync))
    }
    if arg == "--antialiasing" || arg == "--no-antialiasing" ||
        arg == "-a" || arg == "-A" {
        launch_record_override(state, .Rendering_Antialiasing,
            setting_model.boolean_value(run.do_antialiasing))
    }
    if arg == "--limit-fps" || arg == "--no-limit-fps" ||
        arg == "-f" || arg == "-F" {
        launch_record_override(state, .Rendering_Limit_Fps,
            setting_model.boolean_value(run.limit_fps))
    }
    if arg == "--simd" || arg == "--no-simd" || arg == "-s" || arg == "-S" {
        launch_record_override(state, .Rendering_Simd,
            setting_model.boolean_value(run.use_simd_batch_projection))
    }
    if arg == "--gpu-dust-instancing" || arg == "--no-gpu-dust-instancing" ||
        arg == "-g" || arg == "-G" {
        launch_record_override(state, .Rendering_Gpu_Dust_Instancing,
            setting_model.boolean_value(run.use_gpu_dust_instancing))
    }
    if len(arg) > 2 && arg[0] == '-' && arg[1] != '-' {
        for flag in arg[1:] {
            launch_record_boolean_overrides(rune_to_flag(flag), run, state)
        }
    }
}

// Translate one short-option rune to the ordinary flag path for override capture.
rune_to_flag :: proc(flag: rune) -> string {
    if strings.index_byte("vVaAfFsSgG", u8(flag)) >= 0 {
        return fmt.tprintf("-%c", flag)
    }
    return ""
}

//  Apply one window-configuration flag and report whether it matched.
parse_window_flag :: proc(arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
    switch arg {
    case "--no-vsync":
        settings.do_vsync = false
    case "--vsync":
        settings.do_vsync = true
    case "--no-antialiasing":
        settings.do_antialiasing = false
    case "--antialiasing":
        settings.do_antialiasing = true
    case:
        return false
    }
    return true
}

//  Parse one bounded nonempty path option without replacing a prior valid value.
parse_command_line_path :: proc(
    arg: string, prefix: string, invalid_message: string,
    destination: ^string) -> bool {
    if len(arg) < len(prefix) || arg[:len(prefix)] != prefix {
        return false
    }
    path := arg[len(prefix):]
    if len(path) > 0 && len(path) <= COMMAND_LINE_PATH_MAX_BYTES {
        destination^ = path
    } else {
        fmt.println(invalid_message)
    }
    return true
}

//  Apply one runtime option carrying a string value.
parse_runtime_value_flag :: proc(
    arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
    if parse_command_line_path(arg, DIAGNOSTICS_OPTION_PREFIX,
        "Invalid diagnostics path", &settings.diagnostics_path) {
        return true
    }
    if parse_command_line_path(arg, PROFILE_OPTION_PREFIX,
        "Invalid profile path", &settings.profile_path) {
        return true
    }
    if parse_command_line_path(arg, TIMING_PROFILE_PREFIX,
        "Invalid timing profile path", &settings.profile_path) {
        return true
    }
    when core.SCENARIOS_ENABLED {
        if len(arg) > len(SCENARIO_INPUT_PREFIX) &&
            arg[:len(SCENARIO_INPUT_PREFIX)] == SCENARIO_INPUT_PREFIX {
            settings.scenario_input = arg[len(SCENARIO_INPUT_PREFIX):]
            return true
        }
        if len(arg) > len(SCENARIO_ARTIFACT_PREFIX) &&
            arg[:len(SCENARIO_ARTIFACT_PREFIX)] == SCENARIO_ARTIFACT_PREFIX {
            settings.scenario_artifact_output = arg[len(SCENARIO_ARTIFACT_PREFIX):]
            return true
        }
    }
    return false
}

//  Apply one runtime-performance flag and report whether it matched.
parse_runtime_flag :: proc(arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
    if parse_runtime_value_flag(arg, settings) {
        return true
    }
    switch arg {
    case "--limit-fps":
        settings.limit_fps = true
    case "--no-limit-fps":
        settings.limit_fps = false
    case "--simd":
        settings.use_simd_batch_projection = true
    case "--no-simd":
        settings.use_simd_batch_projection = false
    case "--gpu-dust-instancing":
        settings.use_gpu_dust_instancing = true
    case "--no-gpu-dust-instancing":
        settings.use_gpu_dust_instancing = false
    case:
        return false
    }
    return true
}

//  Apply one lowercase short flag that enables an application setting.
parse_short_enable_flag :: proc(
    flag: rune, settings: ^core.Euclid_Run_Settings) -> bool {
    switch flag {
    case 'v':
        settings.do_vsync = true
    case 'a':
        settings.do_antialiasing = true
    case 'f':
        settings.limit_fps = true
    case 's':
        settings.use_simd_batch_projection = true
    case 'g':
        settings.use_gpu_dust_instancing = true
    case:
        return false
    }
    return true
}

//  Apply one uppercase short flag that disables an application setting.
parse_short_disable_flag :: proc(
    flag: rune, settings: ^core.Euclid_Run_Settings) -> bool {
    switch flag {
    case 'V':
        settings.do_vsync = false
    case 'A':
        settings.do_antialiasing = false
    case 'F':
        settings.limit_fps = false
    case 'S':
        settings.use_simd_batch_projection = false
    case 'G':
        settings.use_gpu_dust_instancing = false
    case:
        return false
    }
    return true
}

//  Apply one short flag, including the non-setting help flag.
parse_short_flag :: proc(flag: rune, settings: ^core.Euclid_Run_Settings) -> bool {
    if parse_short_enable_flag(flag, settings) ||
        parse_short_disable_flag(flag, settings) {
        return true
    }
    if flag == 'h' {
        print_command_line_help()
        settings.do_run = false
        return true
    }
    return false
}

//  Parse one combined short-option argument such as -vasg.
parse_short_flags_param :: proc(
    arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
    if len(arg) < 2 || arg[0] != '-' || arg[1] == '-' {
        return false
    }

    for flag in arg[1:] {
        if !parse_short_flag(flag, settings) {
            fmt.println(fmt.tprintf("Unrecognized short parameter: -%c", flag))
        }
    }
    return true
}

//  Enable evidence recording and select stdout when no destination is configured.
enable_semantic_evidence :: proc(config: ^evidence_session.Config) {
    config.enabled = true
    if config.output_mode == .Disabled {
        config.output_mode = .Stdout
    }
}

//  Parse one retained semantic-trace CLI option into typed evidence policy.
parse_semantic_trace_argument :: proc(
    arg: string, config: ^evidence_session.Config) -> (bool, bool) {
    switch arg {
    case "--semantic-trace":
        enable_semantic_evidence(config)
        return true, true
    case "--semantic-trace-strict":
        enable_semantic_evidence(config)
        config.strict = true
        return true, true
    }
    if len(arg) >= len(SEMANTIC_TRACE_OUTPUT_PREFIX) &&
        arg[:len(SEMANTIC_TRACE_OUTPUT_PREFIX)] == SEMANTIC_TRACE_OUTPUT_PREFIX {
        config.enabled = true
        config.output_mode = .File
        config.output_path = arg[len(SEMANTIC_TRACE_OUTPUT_PREFIX):]
        return true, len(config.output_path) > 0
    }
    if len(arg) >= len(SEMANTIC_TRACE_EVENTS_PREFIX) &&
        arg[:len(SEMANTIC_TRACE_EVENTS_PREFIX)] == SEMANTIC_TRACE_EVENTS_PREFIX {
        lanes, valid := evidence_session.parse_lane_selection(
            arg[len(SEMANTIC_TRACE_EVENTS_PREFIX):])
        if valid {
            enable_semantic_evidence(config)
            config.lanes = lanes
        }
        return true, valid
    }
    return false, false
}

//  Print startup-window options and their default policy.
print_window_policy_help :: proc() {
    fmt.println("  --window-preset=landscape|portrait  Set initial window size.")
    fmt.println("  --window-size=WIDTHxHEIGHT           Set a custom initial size.")
    fmt.println("  --window-mode=fixed|resizable        Set resize policy. (default: fixed)")
    fmt.println("  --layout=auto|landscape|portrait     Set layout policy. (default: auto)")
}

//  Print supported application options and their defaults.
print_command_line_help :: proc() {
    fmt.println("Usage: ./euclid [options]")
    fmt.println("")
    fmt.println("Options:")
    fmt.println("  -v, --vsync              Enable VSYNC. (default)")
    fmt.println("  -V, --no-vsync           Disable VSYNC.")
    fmt.println("  -a, --antialiasing       Enable anti-aliasing. (default)")
    fmt.println("  -A, --no-antialiasing    Disable anti-aliasing.")
    print_window_policy_help()
    fmt.println(fmt.tprintf(
        "  --dust-particle-max=N    Set maximum dust particles, 0-%d. (default: %d)",
        setting_model.DUST_LIMIT_MAX,
        setting_model.DUST_LIMIT_MAX))
    fmt.println("  -f, --limit-fps          Limit rendering to 60 FPS. (default)")
    fmt.println("  -F, --no-limit-fps       Disable the 60 FPS limit.")
    fmt.println(
        "  -s, --simd               Enable SIMD projection when available. (default)")
    fmt.println("  -S, --no-simd            Disable SIMD projection.")
    fmt.println(
        "  -g, --gpu-dust-instancing Enable GPU dust instancing when available. (default)")
    fmt.println("  -G, --no-gpu-dust-instancing Disable GPU dust instancing.")
    fmt.println("  --diagnostics=PATH       Write synchronized diagnostic logs.")
    print_user_database_help()
    fmt.println("  --profile=spall:PATH     Write display and worker Spall timelines.")
    fmt.println("  --semantic-trace         Enable semantic trace output.")
    fmt.println("  --semantic-trace-output=PATH  Write semantic trace JSONL to PATH.")
    fmt.println("  --semantic-trace-events=LIST   Limit evidence lanes (lifecycle,domain,transport,presentation,scenario,diagnostic).")
    fmt.println("  --semantic-trace-strict  Fail on required evidence loss or export failure.")
    fmt.println("  --timing-profile=PATH    Alias for --profile=spall:PATH.")
    when core.SCENARIOS_ENABLED {
        fmt.println("  --scenario=PATH          Run a bounded semantic scenario from JSONL.")
        fmt.println("  --scenario-artifacts=DIR Write the scenario evidence bundle to DIR.")
    }
    fmt.println("  -h, --help               Show this help text.")
    fmt.println("")
    fmt.println("Short options can be combined, for example: -vasg or -VAFSG")
}

// Parse persistence-control options without touching any filesystem path.
parse_launch_control_argument :: proc(arg: string, state: ^Launch_Parse_State) -> bool {
    if arg == "--persist" {
        state^.persist_requested = true
        return true
    }
    if arg == "--no-user-db" {
        state^.no_user_db = true
        return true
    }
    if len(arg) >= len(USER_DB_OPTION_PREFIX) &&
        arg[:len(USER_DB_OPTION_PREFIX)] == USER_DB_OPTION_PREFIX {
        filename := arg[len(USER_DB_OPTION_PREFIX):]
        if len(filename) == 0 || len(filename) > user_data.DATABASE_PATH_MAX_BYTES {
            state^.invalid_launch_option = true
            fmt.println("Invalid --user-db filename")
        } else {
            state^.custom_user_db_requested = true
            state^.user_db_filename = filename
        }
        return true
    }
    return false
}

//  Parse a single command line argument, updating settings accordingly.
parse_command_line_param :: proc(
    arg: string,
    settings: ^core.Euclid_Run_Settings,
    state: ^Launch_Parse_State) {
    if parse_launch_control_argument(arg, state) {
        return
    }
    handled_trace, valid_trace := parse_semantic_trace_argument(arg, &settings.evidence)
    if handled_trace {
        if !valid_trace {
            fmt.println("Invalid semantic trace parameter: ", arg)
        }
        return
    }
    was_short_flag := parse_short_flags_param(arg, settings)
    if was_short_flag {
        launch_record_boolean_overrides(arg, settings^, state)
        return
    }
    if parse_dust_particle_max_param(arg, settings, state) ||
        parse_window_policy_param(arg, state) {
        return
    }
    if parse_window_flag(arg, settings) || parse_runtime_flag(arg, settings) {
        launch_record_boolean_overrides(arg, settings^, state)
        return
    }
    if arg == "--help" {
        print_command_line_help()
        settings.do_run = false
        return
    }
    fmt.println("Unrecognized parameter: ", arg)
}

//  Report the resolved application startup settings before opening the window.
print_startup_settings :: proc(settings: ^core.Euclid_Run_Settings) {
    fmt.println("Using antialiasing: ", settings.do_antialiasing)
    fmt.println("Using vsync: ", settings.do_vsync)
    fmt.println("Maximum dust particles: ", settings.dust_particle_max)
    fmt.println("Limiting FPS: ", settings.limit_fps)
    fmt.println("Using SIMD projection when available: ",
        settings.use_simd_batch_projection)
    fmt.println("Using GPU dust instancing when available: ",
        settings.use_gpu_dust_instancing)
    fmt.println(fmt.tprintf(
        "Window startup policy: %dx%d, %v, layout %v",
        settings.window.width,
        settings.window.height,
        settings.window.mode,
        settings.window.layout))
}

//  Parse supplied arguments into settings and explicit launch intent.
parse_command_line :: proc(args: []string) -> Launch_Configuration {
    defaults := setting_model.default_preferences()
    settings := core.Euclid_Run_Settings{
        do_run = true,
        do_antialiasing = defaults.rendering.antialiasing,
        do_vsync = defaults.rendering.vsync,
        dust_particle_max = defaults.drawing.dust_limit,
        limit_fps = defaults.rendering.limit_fps,
        use_simd_batch_projection = defaults.rendering.simd,
        use_gpu_dust_instancing = defaults.rendering.gpu_dust_instancing,
        window = defaults.window,
        evidence = {
            lanes = evidence_session.ALL_LANES,
        },
    }
    state := default_window_parse_state()
    for arg in args {
        parse_command_line_param(arg, &settings, &state)
    }
    settings.window = state.preference
    state.preference_values.window = state.preference

    when core.SCENARIOS_ENABLED {
        if len(settings.scenario_input) > 0 {
            settings.evidence.enabled = true
            if len(settings.evidence.output_path) == 0 {
                settings.evidence.output_mode = .Sink
            }
        }
    }

    state.invalid_launch_option = state.invalid_launch_option ||
        (state.no_user_db && (state.persist_requested || state.custom_user_db_requested))
    return {run_settings = settings, parse_state = state}
}
