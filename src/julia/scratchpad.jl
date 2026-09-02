module Scratchpad

using ..OdinJuliaBridge
using ..EuclidLatex
using REPL

export init_euclid_scripts_scratchpad!, prime_repl!, get_view_text, initialize, clean!,
    loop, classify_input, complete_backslash, complete_input, queue_input,
    register_frame_hook, remove_frame_hook, clear_frame_hooks, list_frame_hooks,
    save_history_to_file, history_previous, history_next, history_reset_cursor

include("scratchpad/model_state.jl")
include("scratchpad/parsing_completion.jl")
include("scratchpad/hooks_history.jl")
include("scratchpad/presentation_help.jl")
include("scratchpad/runtime_loop.jl")

end
