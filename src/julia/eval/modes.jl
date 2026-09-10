"""Return the persistent session's current REPL source label."""
repl_source_name(session::EvaluationSession) = "REPL[$(session.input_number)]"

"""Return whether a call target names one supported exit function."""
function is_exit_callee(callee)::Bool
    if callee === :exit || callee === :quit
        return true
    end
    return callee isa Expr && callee.head === :. && length(callee.args) == 2 &&
        callee.args[1] === :Base && callee.args[2] isa QuoteNode &&
        callee.args[2].value === :exit
end

"""Extract an AST's only top-level expression, if it has exactly one."""
function single_toplevel_expression(ast)
    ast isa Expr && ast.head === :toplevel || return ast
    expressions = filter(item -> !(item isa LineNumberNode), ast.args)
    return length(expressions) == 1 ? only(expressions) : nothing
end

"""Return whether an AST is a direct request to exit the embedded REPL."""
function is_exit_request(ast)::Bool
    expression = single_toplevel_expression(ast)
    if expression isa Expr && expression.head === :block
        expressions = filter(item -> !(item isa LineNumberNode), expression.args)
        expression = length(expressions) == 1 ? only(expressions) : nothing
    end
    return expression isa Expr && expression.head === :call &&
        is_exit_callee(first(expression.args))
end

"""Parse input with its REPL source label and classify incomplete or exit input."""
function classify_input(session::EvaluationSession, code::AbstractString)
    ast = Base.parse_input_line(
        code; filename=repl_source_name(session), depwarn=false)
    if ast isa Expr && ast.head === :incomplete
        return ast, Evaluation_Incomplete
    end
    if is_exit_request(ast)
        session.input_number += 1
        return ast, Evaluation_Exit
    end
    return ast, Evaluation_Complete
end

"""Evaluate normal Julia input in one persistent REPL session."""
function evaluate_input(
    session::EvaluationSession, code::AbstractString)::EvaluationResult
    ast, status = classify_input(session, code)
    status != Evaluation_Complete && return EvaluationResult(status, "")
    return EvaluationResult(Evaluation_Complete, run_ast(session, _ -> ast, code))
end

"""Evaluate one help-mode query in the persistent REPL session."""
function evaluate_help(
    session::EvaluationSession, code::AbstractString)::EvaluationResult
    output = run_ast(
        session,
        io -> REPL.helpmode(io, code, session.context_module), code)
    return EvaluationResult(Evaluation_Complete, output)
end

"""Run one Pkg REPL-mode command with output directed to the given stream."""
function run_pkg_command(code::AbstractString, io::IO)
    previous_warning_state = Pkg.REPLMode.PRINTED_REPL_WARNING[]
    Pkg.REPLMode.PRINTED_REPL_WARNING[] = true
    try
        context = IOContext(io, :color => true, :limit => true)
        commands = Pkg.REPLMode.prepare_cmd(String(code))
        Pkg.REPLMode.do_cmds(commands, context)
    finally
        Pkg.REPLMode.PRINTED_REPL_WARNING[] = previous_warning_state
    end
end

"""Evaluate one Pkg REPL-mode command and capture its output."""
function evaluate_pkg(code::AbstractString)::EvaluationResult
    output = mktemp() do _path, io
        redirect_stdout(io) do
            redirect_stderr(io) do
                try
                    run_pkg_command(code, io)
                catch error
                    showerror(io, error, catch_backtrace())
                end
            end
        end
        flush(io)
        seekstart(io)
        return read(io, String)
    end
    return EvaluationResult(Evaluation_Complete, output)
end