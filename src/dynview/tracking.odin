package dynview

import "../core"

import rl "vendor:raylib"

set_enabled :: proc(runtime: ^core.Dynview_System, enabled: bool) {
    if runtime^.enabled == enabled {
        return
    }

    runtime^.enabled = enabled
    invalidate(runtime,
        DYNVIEW_INVALIDATE_CONTENT |
        DYNVIEW_INVALIDATE_PANEL |
        DYNVIEW_INVALIDATE_FONT |
        DYNVIEW_INVALIDATE_STYLE)
}

//   Mark compile cache invalid and accumulate invalidation reasons.
invalidate :: proc(runtime: ^core.Dynview_System, mask: u32) {
    if runtime == nil {
        return
    }

    runtime^.pending_invalidation_mask |= mask
    runtime^.compile_cache.is_valid = false
}

//   Reset per-frame command storage while advancing stream revision.
reset_command_buffer :: proc(runtime: ^core.Dynview_System) {
    if runtime == nil {
        return
    }

    runtime^.command_buffer.command_count = 0
    runtime^.command_buffer.text_bytes_len = 0
    runtime^.command_buffer.has_stream_error = false
    runtime^.command_buffer.stream_open_block = false
    runtime^.command_buffer.stream_open_block_id = -1
    runtime^.compile_cache.math_program_count = 0
    runtime^.compile_cache.math_command_count = 0
    runtime^.compile_cache.math_node_count = 0
    runtime^.compile_cache.copy_hit_target_count = 0
    runtime^.command_buffer.revision += 1
}

//   Mark stream invalid and preserve first error code for diagnostics/fallback.
mark_stream_error :: proc(runtime: ^core.Dynview_System, code: i32) {
    if runtime == nil {
        return
    }

    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == DYNVIEW_STATUS_OK {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
}

//   Compute a stable FNV-1a hash used for content-change tracking.
hash_text :: proc(text: string) -> u64 {
    hash: u64 = 1469598103934665603
    for b in text {
        hash = (hash ~ u64(b)) * 1099511628211
    }
    return hash
}

//   Track text content keys and invalidate when text identity changes.
track_content :: proc(runtime: ^core.Dynview_System, text: string) {
    if runtime == nil {
        return
    }

    content_hash := hash_text(text)
    content_len := len(text)
    cache := &runtime^.compile_cache
    if content_hash == cache^.last_content_hash &&
        content_len == cache^.last_content_len {
        return
    }

    cache^.last_content_hash = content_hash
    cache^.last_content_len = content_len
    invalidate(runtime, DYNVIEW_INVALIDATE_CONTENT)
}

//   Track panel dimensions and invalidate when layout bounds change.
track_panel :: proc(runtime: ^core.Dynview_System, panel: rl.Rectangle) {
    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if panel.width == cache^.last_panel_width &&
        panel.height == cache^.last_panel_height {
        return
    }

    cache^.last_panel_width = panel.width
    cache^.last_panel_height = panel.height
    invalidate(runtime, DYNVIEW_INVALIDATE_PANEL)
}

//   Track font/wrap metrics and invalidate when text layout metrics shift.
track_font :: proc(runtime: ^core.Dynview_System, font_size, wrap_advance: f32) {
    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if font_size == cache^.last_font_size && wrap_advance == cache^.last_wrap_advance {
        return
    }

    cache^.last_font_size = font_size
    cache^.last_wrap_advance = wrap_advance
    invalidate(runtime, DYNVIEW_INVALIDATE_FONT)
}

//   Track style schema version and invalidate when style mapping changes.
track_style :: proc(runtime: ^core.Dynview_System, style_revision: u64) {
    if runtime == nil {
        return
    }

    if runtime^.compile_cache.last_style_revision == style_revision {
        return
    }

    runtime^.compile_cache.last_style_revision = style_revision
    invalidate(runtime, DYNVIEW_INVALIDATE_STYLE)
}
