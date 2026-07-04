package main

import "files"
import "julia"
import "view"

import "core:fmt"

// The main entry point for the Euclid application
main :: proc() {
    fmt.println("Initiating Euclid...")
    defer fmt.println("Euclid ended")

    defer free_all(context.temp_allocator)

    files.ensure_packaged_assets_unpacked_root()
    defer files.cleanup_packaged_assets_dir()

    julia.initiate_julia()
    defer julia.end_julia()

    view.run_window_loop()
}
