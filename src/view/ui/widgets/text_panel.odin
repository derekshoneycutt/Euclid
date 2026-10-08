package uiwidgets

import geometry "../../../core/geometry"

// Compute the shared bordered viewport used by text and Terminal presentations.
text_content_panel :: proc(panel: geometry.Rectangle) -> geometry.Rectangle {
    panel_geometry := container_geometry(panel, 1)
    text_panel := geometry.Rectangle{
        panel_geometry.inner_rect.x + 5,
        panel_geometry.inner_rect.y + 5,
        panel_geometry.inner_rect.width - 10,
        panel_geometry.inner_rect.height - 10,
    }
    return container_geometry(text_panel, 1).drawn_rect
}
