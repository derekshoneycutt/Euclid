package uiaccordion

import uilayout ".."
import geometry "../../../../core/geometry"
import viewmodel "../../model"

// ui_presentation_clip restricts portrait View without changing its full layout size.
ui_presentation_clip :: proc(
    layout: ^viewmodel.Ui_Layout_State,
    panel: geometry.Rectangle) -> geometry.Rectangle {
    if layout^.current_layout_mode != .Portrait {
        return panel
    }
    clip := accordion_content_clip(layout, .View)
    return uilayout.stack_panel_clamp_x(uilayout.stack_panel_clamp_y(panel, clip), clip)
}
