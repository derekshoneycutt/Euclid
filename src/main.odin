package main

import "julia"
import "view"

main :: proc() {
    julia.initiate_julia()
    defer julia.end_julia()

    view.run_window_loop()
}
