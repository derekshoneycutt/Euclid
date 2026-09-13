package presentation_model

// Maximum canonical presentation source admitted by native transport.
PRESENTATION_MAX_SOURCE_BYTES :: 32 * 1024

// Presentation_Mime identifies the language of canonical presentation bytes.
Presentation_Mime :: enum u8 {
    Text_Plain,
    Text_Latex,
}

// Presented_Text borrows exact bytes from its containing producer-owned envelope.
Presented_Text :: struct {
    mime: Presentation_Mime,
    bytes: []u8,
}