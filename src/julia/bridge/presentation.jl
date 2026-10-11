const PRESENTATION_MAX_SOURCE_BYTES = 32 * 1024

@enum PresentationMime::UInt8 begin
    TextPlain = 0
    TextLatex = 1
end

"""One canonical MIME selection and its exact serialized UTF-8 bytes."""
struct PresentedText
    mime::PresentationMime
    bytes::String
end

"""Reject one serialized value when its exact UTF-8 representation exceeds the limit."""
function validate_presented_text_size(bytes::String)
    ncodeunits(bytes) <= PRESENTATION_MAX_SOURCE_BYTES ||
        throw(ArgumentError("presentation exceeds byte capacity"))
    return bytes
end

"""Render one displayable through a bounded deterministic MIME context."""
function serialize_presented_text(value, mime::MIME)
    buffer = IOBuffer(; maxsize=PRESENTATION_MAX_SOURCE_BYTES + 1)
    context = IOContext(buffer, :color => false, :limit => true, :compact => false)
    show(context, mime, value)
    return validate_presented_text_size(String(take!(buffer)))
end

"""Select and serialize one Julia displayable into Euclid's canonical MIME value."""
function presented_text(value)
    latex_mime = MIME"text/latex"()
    if showable(latex_mime, value)
        return PresentedText(TextLatex, serialize_presented_text(value, latex_mime))
    end
    if value isa AbstractString
        return PresentedText(TextPlain, validate_presented_text_size(String(value)))
    end
    plain_mime = MIME"text/plain"()
    return PresentedText(TextPlain, serialize_presented_text(value, plain_mime))
end

"""Clone one canonical presentation value into the Julia-owned host egress pool."""
function publish_presented_text(state_ptr::Ptr{Cvoid}, presentation::PresentedText)
    bytes = presentation.bytes
    byte_count = ncodeunits(bytes)
    byte_count <= PRESENTATION_MAX_SOURCE_BYTES ||
        throw(ArgumentError("presentation exceeds byte capacity"))
    GC.@preserve bytes begin
        return @ccall publish_presented_text(
            state_ptr::Ptr{Cvoid},
            Int32(presentation.mime)::Int32,
            pointer(bytes)::Ptr{UInt8},
            Int32(byte_count)::Int32)::Int32
    end
end

"""Serialize and publish one value through the supplied presentation boundary."""
function _present_with(
    state_ptr::Ptr{Cvoid}, value, publisher::Function)

    status = publisher(state_ptr, presented_text(value))
    status == BRIDGE_STATUS_OK ||
        error("publish_presented_text failed with bridge status $status")
    return status
end

"""Serialize and publish one value through Euclid's canonical MIME boundary."""
function present(state_ptr::Ptr{Cvoid}, value)
    return _present_with(state_ptr, value, publish_presented_text)
end

"""Invoke one producer and pass its value to the supplied presentation boundary."""
function _publish_view_content_with(
    state_ptr::Ptr{Cvoid}, producer::Function, presenter::Function)

    return presenter(state_ptr, producer(state_ptr))
end

"""Serialize and publish the value returned by one view-content producer."""
function publish_view_content(state_ptr::Ptr{Cvoid}, producer::Function)
    return _publish_view_content_with(state_ptr, producer, present)
end
