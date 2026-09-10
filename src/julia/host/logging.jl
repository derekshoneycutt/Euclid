const HOST_DIAGNOSTIC_MAX_BYTES = 4096

"""Julia logger that forwards bounded host-only records to an owned sink."""
struct HostDiagnosticLogger{F} <: AbstractLogger
    sink::F
    minimum_level::LogLevel
end

"""Create a host logger when the active bridge exposes a native diagnostic sink."""
function host_diagnostic_logger(
    states::Ptr{Cvoid}; minimum_level=Logging.Debug)::AbstractLogger
    isdefined(OdinJuliaBridge, :emit_diagnostic) || return NullLogger()
    emit_diagnostic = getfield(OdinJuliaBridge, :emit_diagnostic)
    return HostDiagnosticLogger(
        (level, message, file, line) -> emit_diagnostic(
            states, Int32(level.level), message, file, Int32(line)),
        minimum_level)
end

"""Return the least severe record accepted by a host diagnostic logger."""
Logging.min_enabled_level(logger::HostDiagnosticLogger) = logger.minimum_level

"""Return whether one record passes the host logger's level filter."""
Logging.shouldlog(
    logger::HostDiagnosticLogger, level, _module, group, id) =
    level >= logger.minimum_level

"""Require host logger failures to remain visible to the owning Julia call."""
Logging.catch_exceptions(_logger::HostDiagnosticLogger) = false

"""Return a valid UTF-8 prefix within the host diagnostic byte capacity."""
function bounded_host_diagnostic(text::String)::String
    ncodeunits(text) <= HOST_DIAGNOSTIC_MAX_BYTES && return text
    retained = HOST_DIAGNOSTIC_MAX_BYTES
    while retained > 0 && !isvalid(String, @view(codeunits(text)[1:retained]))
        retained -= 1
    end
    return String(@view(codeunits(text)[1:retained]))
end

"""Format source and structured metadata before forwarding one host record."""
function Logging.handle_message(
    logger::HostDiagnosticLogger, level, message, _module, group, id, file, line;
    kwargs...)
    output = IOBuffer()
    print(output, message)
    for (key, value) in kwargs
        print(output, ' ', key, '=', value)
    end
    logger.sink(
        level, bounded_host_diagnostic(String(take!(output))),
        String(file), line)
    return nothing
end

"""Emit one host-owned diagnostic while retaining the macro call location."""
macro host_log(runtime, level, message, metadata...)
    source_file = String(__source__.file)
    source_line = __source__.line
    return esc(quote
        let logger = $(runtime).logger, selected_level = $(level)
            with_logger(logger) do
                if Logging.shouldlog(
                    logger, selected_level, $(QuoteNode(__module__)),
                    :host, :host)
                    Logging.handle_message(
                        logger, selected_level, $(message),
                        $(QuoteNode(__module__)), :host, :host,
                        $source_file, $source_line; $(metadata...))
                end
            end
        end
    end)
end
