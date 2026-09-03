package dynview

import "../core"

import rl "vendor:raylib"

//   Toggle Dynview rendering and invalidate all cache inputs when it changes.
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

//   Track canonical font and cell metrics, invalidating when text layout shifts.
track_font :: proc(
    runtime: ^core.Dynview_System,
    font_size, cell_width, cell_height: f32) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if font_size == cache^.last_font_size &&
        cell_width == cache^.last_cell_width &&
        cell_height == cache^.last_cell_height {
        return
    }

    cache^.last_font_size = font_size
    cache^.last_cell_width = cell_width
    cache^.last_cell_height = cell_height
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
