package bridge

import dynviewmodel "../dynview/model"
import dyncore "../dynview/core"

// Import exact literal bytes as document prose, never as executable TeX syntax.
dynview_native_import_literal_document :: proc(
    runtime: ^dynviewmodel.Dynview_System, source: string) -> i32 {
    cache := &runtime^.compile_cache
    if cache^.document_count >= dynviewmodel.DYNVIEW_MAX_DOCUMENTS ||
        cache^.document_block_count >= dynviewmodel.DYNVIEW_MAX_DOCUMENT_BLOCKS ||
        len(source)*2 >
            dynviewmodel.DYNVIEW_MAX_DOCUMENT_BYTES-cache^.document_text_count {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    document: dyncore.Dynview_Document = {
        source = source,
        text = transmute([]u8)source,
    }
    source_offset, text_offset := dynview_native_copy_document_text(cache, &document)
    inline_start := cache^.document_inline_count
    status := dynview_native_literal_inlines(cache, source, source_offset, text_offset)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    block_start := cache^.document_block_count
    cache^.document_blocks[block_start] = {
        kind = .Paragraph,
        inline_start = inline_start,
        inline_count = cache^.document_inline_count-inline_start,
        source_offset = source_offset,
        source_count = len(source),
        no_indent = true,
    }
    cache^.document_block_count += 1
    cache^.documents[cache^.document_count] = {
        source_offset = source_offset,
        source_count = len(source),
        text_offset = text_offset,
        text_count = len(source),
        block_start = block_start,
        block_count = 1,
        inline_start = inline_start,
        inline_count = cache^.document_inline_count-inline_start,
    }
    cache^.document_count += 1
    return BRIDGE_STATUS_OK
}

// Split literal prose at spaces and line breaks to preserve wrapping and source mapping.
dynview_native_literal_inlines :: proc(
    cache: ^dynviewmodel.Dynview_Compile_Cache,
    source: string, source_offset, text_offset: int) -> i32 {
    start := 0
    for start < len(source) {
        if cache^.document_inline_count >= dynviewmodel.DYNVIEW_MAX_DOCUMENT_INLINES {
            return BRIDGE_STATUS_OUT_OF_CAPACITY
        }
        end := start+1
        kind := dynviewmodel.Dynview_Document_Inline_Kind.Text
        if source[start] == '\n' || source[start] == '\r' {
            kind = .Forced_Break
        } else if source[start] == ' ' || source[start] == '\t' {
            kind = .Space
        } else {
            for end < len(source) && source[end] != ' ' && source[end] != '\t' &&
                source[end] != '\n' && source[end] != '\r' {
                end += 1
            }
        }
        cache^.document_inlines[cache^.document_inline_count] = {
            kind = kind,
            source_offset = source_offset+start,
            source_count = end-start,
            text_offset = text_offset+start,
            text_count = end-start,
            font_flags = 4,
            math_program_id = -1,
            space_kind = .Breakable,
        }
        cache^.document_inline_count += 1
        start = end
    }
    return BRIDGE_STATUS_OK
}
