package main

import "core"
import "files"
import "julia"
import "view"

import "core:fmt"
import "core:os"

// The main entry point for the Euclid application
main :: proc() {
    settings := parse_command_line()
    if !settings.do_run {
        return
    }

    fmt.println("Initiating Euclid...")

    files.ensure_packaged_assets_unpacked_root()

    julia.initiate_julia()

    view.run_window_loop(&settings)

    julia.end_julia()
    files.cleanup_packaged_assets_dir()
    free_all(context.temp_allocator)
    
    fmt.println("Euclid ended")
}



//  Parse a single command line argument, updating settings accordingly
parse_command_line_param :: proc(arg: string, settings: ^core.Euclid_Run_Settings) {
    switch arg {
    case "--no-vsync":
        settings.do_vsync = false
    case "--vsync":
        settings.do_vsync = true
    case "--no-antialiasing":
        settings.do_antialiasing = false
    case "--antialiasing":
        settings.do_antialiasing = true
    case "--help":
        fmt.println("Usage: ./euclid [options]")
        fmt.println("")
        fmt.println("Options:")
        fmt.println("  --vsync              Enable VSYNC. (default)")
        fmt.println("  --no-vsync           Disable VSYNC.")
        fmt.println("  --antialiasing       Enable anti-aliasing. (default)")
        fmt.println("  --no-antialiasing    Disable anti-aliasing.")
        fmt.println("  --help               Show this help text.")

        settings.do_run = false
    case:
        fmt.println("Unrecognized parameter: ", arg)
    }
}

//  Parse the command line parameters, getting settings to run the app according to
parse_command_line :: proc() -> core.Euclid_Run_Settings {
    settings := core.Euclid_Run_Settings{ true, true, true }

    for i in 1..<len(os.args) {
        arg := os.args[i]
        parse_command_line_param(arg, &settings)
    }

    if settings.do_run {
        fmt.println("Using antialiasing: ", settings.do_antialiasing)
        fmt.println("Using vsync: ", settings.do_vsync)
    }

    return settings
}
