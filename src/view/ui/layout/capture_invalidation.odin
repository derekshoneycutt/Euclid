package uilayout

import viewmodel "../model"

// Release display-owned pointer state whose geometry is invalid after a resize.
ui_release_geometry_capture :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    runtime^.ui_press_owner = {}
    runtime^.tree_scroll_dragging = false
    runtime^.tree_scroll_drag_off = 0
    runtime^.settings_scroll_dragging = false
    runtime^.settings_scroll_drag_off = 0
    runtime^.settings_slider_dragging = false
    runtime^.settings_slider_drag_offset_x = 0
    runtime^.text_scroll_dragging = false
    runtime^.text_scroll_drag_off = 0
    runtime^.terminal_scroll_dragging = false
    runtime^.terminal_scroll_drag_off = 0
    runtime^.dynview_selection.dragging = false
    runtime^.splitter_drag_offset = 0
    runtime^.vertical_split_hover = 0
    runtime^.horizontal_split_hover = 0
}
