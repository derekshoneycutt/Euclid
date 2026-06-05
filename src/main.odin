package main

import "view"

main :: proc() {
    /* // This loads julia code; we will use this later to drive animations once the
    //      core structure and methods are in place for trade with Julia scripts
    fmt.println("[Odin] Starting application.")
    julia.initiate_julia()
    _ = julia.jl_eval_string("include(\"./julia/script.jl\")")
    julia.end_julia()
    fmt.println("[Odin] End application.")*/

    view.run_window_loop()
}
