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


//  Parse the command line parameters, getting settings to run the app according to
parse_command_line :: proc() -> core.Euclid_Run_Settings {
    settings := core.Euclid_Run_Settings{ true, true, true }

    for i in 1..<len(os.args) {
        arg := os.args[i]
        if arg == "--no-vsync" {
            settings.do_vsync = false
        } else if arg == "--vsync" {
            settings.do_vsync = true
        } else if arg == "--no-antialiasing" {
            settings.do_antialiasing = false
        } else if arg == "--antialiasing" {
            settings.do_antialiasing = true
        } else if arg == "--help" {
            fmt.println("Usage: ./euclid [options]")
            fmt.println("")
            fmt.println("Options:")
            fmt.println("  --vsync              Enable VSYNC. (default)")
            fmt.println("  --no-vsync           Disable VSYNC.")
            fmt.println("  --antialiasing       Enable anti-aliasing. (default)")
            fmt.println("  --no-antialiasing    Disable anti-aliasing.")
            fmt.println("  --help               Show this help text.")

            settings.do_run = false
        } else {
            fmt.println("Unrecognized parameter: ", arg)
        }
    }

    if settings.do_run {
        fmt.println("Using antialiasing: ", settings.do_antialiasing)
        fmt.println("Using vsync: ", settings.do_vsync)
    }

    return settings
}
