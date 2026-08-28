package main

import "core"
import "diagnostics"
import evidence_session "evidence/session"
import "files"
import "view"

import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"

COMMAND_LINE_PATH_MAX_BYTES :: 4096
DIAGNOSTICS_OPTION_PREFIX :: "--diagnostics="
DUST_PARTICLE_MAX_PREFIX :: "--dust-particle-max="
TIMING_PROFILE_PREFIX :: "--timing-profile="
PROFILE_OPTION_PREFIX :: "--profile=spall:"
SCENARIO_INPUT_PREFIX :: "--scenario="
SCENARIO_ARTIFACT_PREFIX :: "--scenario-artifacts="
SEMANTIC_TRACE_OUTPUT_PREFIX :: "--semantic-trace-output="
SEMANTIC_TRACE_EVENTS_PREFIX :: "--semantic-trace-events="

// The main entry point for the Euclid application
main :: proc() {
    settings := parse_command_line()
    if !settings.do_run {
        return
    }

    logging_state: diagnostics.Logging_State
    selected_logger := context.logger
    if len(settings.diagnostics_path) > 0 {
        if diagnostics.logging_start(
            &logging_state, settings.diagnostics_path, .Debug) {
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

    exit_code := view.run_window_loop(&settings)

    files.cleanup_packaged_assets_dir()
    free_all(context.temp_allocator)

    log.infof("application_stop exit_code=%d", exit_code)
    context.logger = log.nil_logger()
    diagnostics.logging_stop(&logging_state)
    fmt.println("Euclid ended")
    if exit_code != 0 {
        os.exit(exit_code)
    }
}



//  Parse one bounded dust-capacity option and report whether it matched.
parse_dust_particle_max_param :: proc(
    arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
    if len(arg) < len(DUST_PARTICLE_MAX_PREFIX) ||
        arg[:len(DUST_PARTICLE_MAX_PREFIX)] != DUST_PARTICLE_MAX_PREFIX {
        return false
    }

    value_text := arg[len(DUST_PARTICLE_MAX_PREFIX):]
    value, ok := strconv.parse_i64_of_base(value_text, 10)
    if !ok || value < 0 || value > core.MAX_LOW_PARTICLES {
        fmt.println(fmt.tprintf(
            "Invalid --dust-particle-max value: %s. Expected 0-%d.",
            value_text,
            core.MAX_LOW_PARTICLES))
        return true
    }

    settings.dust_particle_max = int(value)
    return true
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

//  Print supported application options and their defaults.
print_command_line_help :: proc() {
    fmt.println("Usage: ./euclid [options]")
    fmt.println("")
    fmt.println("Options:")
    fmt.println("  -v, --vsync              Enable VSYNC. (default)")
    fmt.println("  -V, --no-vsync           Disable VSYNC.")
    fmt.println("  -a, --antialiasing       Enable anti-aliasing. (default)")
    fmt.println("  -A, --no-antialiasing    Disable anti-aliasing.")
    fmt.println(fmt.tprintf(
        "  --dust-particle-max=N    Set maximum dust particles, 0-%d. (default: %d)",
        core.MAX_LOW_PARTICLES,
        core.MAX_LOW_PARTICLES))
    fmt.println("  -f, --limit-fps          Limit rendering to 60 FPS. (default)")
    fmt.println("  -F, --no-limit-fps       Disable the 60 FPS limit.")
    fmt.println(
        "  -s, --simd               Enable SIMD projection when available. (default)")
    fmt.println("  -S, --no-simd            Disable SIMD projection.")
    fmt.println(
        "  -g, --gpu-dust-instancing Enable GPU dust instancing when available. (default)")
    fmt.println("  -G, --no-gpu-dust-instancing Disable GPU dust instancing.")
    fmt.println("  --diagnostics=PATH       Write synchronized diagnostic logs.")
    fmt.println("  --profile=spall:PATH     Write display and worker Spall timelines.")
    fmt.println("  --semantic-trace         Enable semantic trace output.")
    fmt.println("  --semantic-trace-output=PATH  Write semantic trace JSONL to PATH.")
    fmt.println("  --semantic-trace-events=LIST   Limit evidence lanes (lifecycle,domain,transport,presentation,scenario,diagnostic).")
    fmt.println("  --semantic-trace-strict  Fail on required evidence loss or export failure.")
    fmt.println("  --timing-profile=PATH    Alias for --profile=spall:PATH.")
    fmt.println("  --scenario=PATH          Run a bounded semantic scenario from JSONL.")
    fmt.println("  --scenario-artifacts=DIR Write the scenario evidence bundle to DIR.")
    fmt.println("  -h, --help               Show this help text.")
    fmt.println("")
    fmt.println("Short options can be combined, for example: -vasg or -VAFSG")
}

//  Parse a single command line argument, updating settings accordingly.
parse_command_line_param :: proc(arg: string, settings: ^core.Euclid_Run_Settings) {
    handled_trace, valid_trace := parse_semantic_trace_argument(arg, &settings.evidence)
    if handled_trace {
        if !valid_trace {
            fmt.println("Invalid semantic trace parameter: ", arg)
        }
        return
    }
    if parse_short_flags_param(arg, settings) ||
        parse_dust_particle_max_param(arg, settings) ||
        parse_window_flag(arg, settings) || parse_runtime_flag(arg, settings) {
        return
    }
    if arg == "--help" {
        print_command_line_help()
        settings.do_run = false
        return
    }
    fmt.println("Unrecognized parameter: ", arg)
}

//  Parse command-line parameters into complete application startup settings.
parse_command_line :: proc() -> core.Euclid_Run_Settings {
    settings := core.Euclid_Run_Settings{
        do_run = true,
        do_antialiasing = true,
        do_vsync = true,
        dust_particle_max = core.MAX_LOW_PARTICLES,
        limit_fps = true,
        use_simd_batch_projection = true,
        use_gpu_dust_instancing = true,
        evidence = {
            lanes = evidence_session.ALL_LANES,
        },
    }

    for i in 1..<len(os.args) {
        arg := os.args[i]
        parse_command_line_param(arg, &settings)
    }

    if len(settings.scenario_input) > 0 {
        settings.evidence.enabled = true
        if len(settings.evidence.output_path) == 0 {
            settings.evidence.output_mode = .Sink
        }
    }

    if settings.do_run {
        fmt.println("Using antialiasing: ", settings.do_antialiasing)
        fmt.println("Using vsync: ", settings.do_vsync)
        fmt.println("Maximum dust particles: ", settings.dust_particle_max)
        fmt.println("Limiting FPS: ", settings.limit_fps)
        fmt.println("Using SIMD projection when available: ",
            settings.use_simd_batch_projection)
        fmt.println("Using GPU dust instancing when available: ",
            settings.use_gpu_dust_instancing)
    }

    return settings
}
