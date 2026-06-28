package main

import "files"
import "julia"
import "view"

main :: proc() {
    files.ensure_packaged_assets_unpacked_root()
    defer files.cleanup_packaged_assets_dir()

    julia.initiate_julia()
    defer julia.end_julia()

    view.run_window_loop()
}
