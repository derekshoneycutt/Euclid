package main

import "../bridge"
import "../core"
import "../files"
import "../view"

import "core:encoding/uuid"
import "core:fmt"
import "core:os"
import "core:strconv"

Harness_Options :: struct {
    asset_root: string,
    animation_id_text: string,
    trace_output: string,
    scenario_name: string,
    steps: int,
}

//   Print the supported headless harness options.
print_usage :: proc() {
    fmt.println(
        "Usage: euclid_harness --asset-root=PATH --animation-id=UUID --steps=N " +
        "--trace-output=PATH [--scenario=NAME]")
}

//   Parse one `--name=value` argument into its value payload.
parse_option_value :: proc(arg: string, prefix: string) -> (string, bool) {
    if len(arg) <= len(prefix) || arg[:len(prefix)] != prefix {
        return "", false
    }
    return arg[len(prefix):], true
}

//   Parse harness arguments into a validated options block.
parse_args :: proc() -> (Harness_Options, bool) {
    options := Harness_Options{}
    for index in 1..<len(os.args) {
        arg := os.args[index]
        if value, ok := parse_option_value(arg, "--asset-root="); ok {
            options.asset_root = value
            continue
        }
        if value, ok := parse_option_value(arg, "--animation-id="); ok {
            options.animation_id_text = value
            continue
        }
        if value, ok := parse_option_value(arg, "--trace-output="); ok {
            options.trace_output = value
            continue
        }
        if value, ok := parse_option_value(arg, "--scenario="); ok {
            options.scenario_name = value
            continue
        }
        if value, ok := parse_option_value(arg, "--steps="); ok {
            steps, parse_ok := strconv.parse_i64_of_base(value, 10)
            if !parse_ok || steps <= 0 {
                return {}, false
            }
            options.steps = int(steps)
            continue
        }
        if arg == "--help" {
            print_usage()
            return {}, false
        }
        return {}, false
    }

    return options, len(options.asset_root) > 0 && len(options.animation_id_text) > 0 &&
        len(options.trace_output) > 0 && options.steps > 0
}

//   Run one deterministic headless harness scenario.
main :: proc() {
    options, ok := parse_args()
    if !ok {
        print_usage()
        os.exit(1)
    }

    files.set_asset_root_override(options.asset_root)
    defer files.clear_asset_root_override()
    if !files.reload_packaged_assets_root() {
        fmt.eprintln("Failed to refresh packaged assets for harness run.")
        os.exit(1)
    }

    settings := core.Euclid_Run_Settings{
        do_run = true,
        do_antialiasing = false,
        do_vsync = false,
        dust_particle_max = core.MAX_LOW_PARTICLES,
        limit_fps = false,
        use_simd_batch_projection = false,
        use_gpu_dust_instancing = false,
        semantic_trace_enabled = true,
        semantic_trace_strict = true,
        semantic_trace_output = options.trace_output,
        semantic_trace_events = "",
    }

    session, session_ok := view.create_runtime_session(&settings)
    if !session_ok {
        fmt.eprintln("Failed to initialize headless runtime session.")
        os.exit(1)
    }
    defer view.shutdown_runtime_session(session)

    stable_id, read_error := uuid.read(options.animation_id_text)
    if read_error != .None {
        fmt.eprintln("Invalid animation UUID: ", options.animation_id_text)
        os.exit(1)
    }
    if !bridge.select_animation_by_stable_id(session.state, stable_id) {
        fmt.eprintln("Animation UUID not found: ", options.animation_id_text)
        os.exit(1)
    }

    for _ in 0..<options.steps {
        if !view.run_deterministic_fixed_step(session.state, view.FIXED_DT) {
            fmt.eprintln("Deterministic fixed-step execution failed.")
            os.exit(1)
        }
    }

    if len(options.scenario_name) > 0 &&
        !bridge.invoke_harness_scenario(session.state, options.scenario_name, options.steps) {
        fmt.eprintln("Harness scenario failed: ", options.scenario_name)
        os.exit(1)
    }

    if session.julia_service^.animation_ticks_stale != 0 {
        fmt.eprintln("Harness observed rejected animation ticks.")
        os.exit(1)
    }
}
