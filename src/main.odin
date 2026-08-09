package main

import "core"
import "files"
import "view"

import "core:fmt"
import "core:os"
import "core:strconv"

DUST_PARTICLE_MAX_PREFIX :: "--dust-particle-max="

// The main entry point for the Euclid application
main :: proc() {
    settings := parse_command_line()
    if !settings.do_run {
        return
    }

    fmt.println("Initiating Euclid...")

    view.run_window_loop(&settings)

    files.cleanup_packaged_assets_dir()
    free_all(context.temp_allocator)
    
    fmt.println("Euclid ended")
}



//  Parse one bounded dust-capacity option and report whether it matched.
parse_dust_particle_max_param :: proc(arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
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

//  Apply one runtime-performance flag and report whether it matched.
parse_runtime_flag :: proc(arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
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
parse_short_enable_flag :: proc(flag: rune, settings: ^core.Euclid_Run_Settings) -> bool {
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
parse_short_disable_flag :: proc(flag: rune, settings: ^core.Euclid_Run_Settings) -> bool {
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
    if parse_short_enable_flag(flag, settings) || parse_short_disable_flag(flag, settings) {
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
parse_short_flags_param :: proc(arg: string, settings: ^core.Euclid_Run_Settings) -> bool {
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
    fmt.println("  -s, --simd               Enable SIMD projection when available. (default)")
    fmt.println("  -S, --no-simd            Disable SIMD projection.")
    fmt.println("  -g, --gpu-dust-instancing Enable GPU dust instancing when available. (default)")
    fmt.println("  -G, --no-gpu-dust-instancing Disable GPU dust instancing.")
    fmt.println("  -h, --help               Show this help text.")
    fmt.println("")
    fmt.println("Short options can be combined, for example: -vasg or -VAFSG")
}

//  Parse a single command line argument, updating settings accordingly.
parse_command_line_param :: proc(arg: string, settings: ^core.Euclid_Run_Settings) {
    if parse_short_flags_param(arg, settings) || parse_dust_particle_max_param(arg, settings) ||
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
    }

    for i in 1..<len(os.args) {
        arg := os.args[i]
        parse_command_line_param(arg, &settings)
    }

    if settings.do_run {
        fmt.println("Using antialiasing: ", settings.do_antialiasing)
        fmt.println("Using vsync: ", settings.do_vsync)
        fmt.println("Maximum dust particles: ", settings.dust_particle_max)
        fmt.println("Limiting FPS: ", settings.limit_fps)
        fmt.println("Using SIMD projection when available: ", settings.use_simd_batch_projection)
        fmt.println("Using GPU dust instancing when available: ", settings.use_gpu_dust_instancing)
    }

    return settings
}
