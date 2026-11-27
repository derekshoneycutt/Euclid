package builderui

import core "../../../core"

BUILDER_TOOL_BUTTON_ID :: 8801
BUILDER_SELECT_BUTTON_ID :: 8804
BUILDER_PALETTE_BUTTON_BASE_ID :: 8810
BUILDER_PALETTE_BUTTON_COUNT :: 4
BUILDER_BRUSH_SLIDER_ID :: 8820
BUILDER_SURFACE_SEMANTIC_ID :: 8800
BUILDER_SCROLLBAR_ID :: 8803
BUILDER_PLACEMENT_PRESS_ID :: 8830
BUILDER_HIDE_BUTTON_ID :: 8831
BUILDER_SHOW_BUTTON_ID :: 8832
BUILDER_DRAG_PRESS_ID :: 8833

// Return whether the selected catalogue node owns the Builder surface.
is_builder_selected :: #force_inline proc(state: ^core.Euclid_General_State) -> bool {
    return state != nil && state^.julia_interface != nil &&
        state^.julia_interface^.selected_animation != nil &&
        state^.julia_interface^.selected_animation^.node_kind == .Builder
}

// Identify a Builder control capture by its stable frame-local control id.
builder_control_press_id :: #force_inline proc(id: int) -> bool {
    return id == BUILDER_TOOL_BUTTON_ID || id == BUILDER_SELECT_BUTTON_ID ||
        id >= BUILDER_PALETTE_BUTTON_BASE_ID &&
        id < BUILDER_PALETTE_BUTTON_BASE_ID + BUILDER_PALETTE_BUTTON_COUNT ||
        id == BUILDER_BRUSH_SLIDER_ID ||
        id == BUILDER_PLACEMENT_PRESS_ID ||
        id == BUILDER_DRAG_PRESS_ID ||
        id == BUILDER_SCROLLBAR_ID ||
        id == BUILDER_HIDE_BUTTON_ID || id == BUILDER_SHOW_BUTTON_ID
}
