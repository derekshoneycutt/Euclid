package presentation_source

import presentation_model "../../../bridge/presentation"
import dynparse "../../../dynview/parse"

// Presentation_Source_Mode selects literal, standalone-math, or document handling.
Presentation_Source_Mode :: enum u8 {
    Plain,
    Math,
    Document,
    Rejected,
}

// Classify canonical presentation bytes without changing their source representation.
presentation_source_mode :: proc(
    mime: presentation_model.Presentation_Mime,
    source: string) -> Presentation_Source_Mode {
    switch mime {
    case .Text_Plain:
        return .Plain
    case .Text_Latex:
        text := dynparse.tex_document_trim(source)
        return .Math if dynparse.tex_document_whole_math(text).present else .Document
    }
    return .Rejected
}

// Borrow exact canonical bytes for copy text and literal parse-failure rendering.
presentation_literal_source :: proc(
    content: presentation_model.Presented_Text) -> string {
    return transmute(string)content.bytes
}
