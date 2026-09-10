module EuclidReplEvaluation

using REPL
using Pkg
import ..Terminal
import ..Ticks
import ..TerminalContainer

include("eval/terminal.jl")
include("eval/types.jl")
include("eval/completion.jl")
include("eval/display.jl")
include("eval/modes.jl")
include("eval/streaming.jl")

end