package builderui

import buildermodel "../../../animation/builder"
import corecolor "../../../core/color"
import core "../../../core"
import contentdata "../../../core/content"
import geometry "../../../core/geometry"
import input "../../input"
import native "../../native"
import projection "../../world/projection"
import worldmodel "../../world/model"
import viewfont "../../font"
import viewmodel "../model"
import uisemantics "../semantics"
import theme "../theme"
import uiwidgets "../widgets"
import viewtext "../text"
import uipresentation "../presentation"
import uiaccordion "../layout/accordion"
import viewpresentation "../../presentation"
import viewmessages "../../messages"
import uioverlay "../overlay"
import math "core:math"

Builder_Command_Kind :: enum u8 {
    None,
    Edit_Style,
    Hide_Point,
    Show_Point,
}

BUILDER_SELECTION_BREATH_PERIOD_SECONDS :: f32(1.6)
BUILDER_SELECTION_BREATH_MAX_EXPANSION :: f32(0.6)

Builder_Command_Request :: struct {
    kind: Builder_Command_Kind,
    point: buildermodel.Point_Identity,
    style: buildermodel.Point_Style_Edit,
}

Builder_Placement_Request :: struct {
    active: bool,
    position: geometry.Vector3,
    color: corecolor.Color_RGBA8,
    brush_size: f32,
}

Builder_Surface_Layout :: struct {
    panel: geometry.Rectangle,
    panel_clip: geometry.Rectangle,
    tool_section: geometry.Rectangle,
    tool_clip: geometry.Rectangle,
    options_section: geometry.Rectangle,
    clip: geometry.Rectangle,
    select_tool: geometry.Rectangle,
    tool: geometry.Rectangle,
    palette: [4]geometry.Rectangle,
    brush_row_y: f32,
    hide: geometry.Rectangle,
    show: geometry.Rectangle,
    status_y: f32,
    text_size: f32,
    scale: f32,
    content_height: f32,
}

Builder_Options_Layout :: struct {
    palette: [4]geometry.Rectangle,
    brush_row_y: f32,
    hide: geometry.Rectangle,
    show: geometry.Rectangle,
    status_y: f32,
    content_height: f32,
}

Builder_Options_Layout_Request :: struct {
    section: geometry.Rectangle,
    section_y: f32,
    padding: f32,
    button_height: f32,
    text_size: f32,
    scale: f32,
}

Builder_Surface_Sections :: struct {
    panel_clip: geometry.Rectangle,
    tool_section: geometry.Rectangle,
    tool_clip: geometry.Rectangle,
    options_section: geometry.Rectangle,
    options_clip: geometry.Rectangle,
    toolbar: [2]geometry.Rectangle,
    options: Builder_Options_Layout,
}

Builder_Surface_Preparation :: struct {
    active: bool,
    layout: Builder_Surface_Layout,
    select_button: uiwidgets.Text_Button_Result,
    tool_button: uiwidgets.Text_Button_Result,
    palette_buttons: [4]uiwidgets.Text_Button_Result,
    brush: uiwidgets.Integer_Slider_Result,
    hide_button: uiwidgets.Text_Button_Result,
    show_button: uiwidgets.Text_Button_Result,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    tool_active: bool,
    contextual_options_visible: bool,
    command: Builder_Command_Request,
    placement: Builder_Placement_Request,
}

Builder_Button_Semantics_Input :: struct {
    id: int,
    label: string,
    order: u32,
    clip: geometry.Rectangle,
    interactive: bool,
    value: string,
    selected: bool,
}

Builder_Pointer_Gesture_Input :: struct {
    frame: input.Input_Frame,
    mouse: geometry.Vector2,
    over_board: bool,
    shake_enabled: bool,
}

Builder_Visibility_Button_Input :: struct {
    layout: Builder_Surface_Layout,
    interactive: bool,
    point_visible: bool,
    show: bool,
}

Builder_Brush_Slider_Input :: struct {
    frame: input.Input_Frame,
    layout: Builder_Surface_Layout,
    interactive: bool,
    brush_value: int,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
}

Builder_Point_Marker_Draw :: struct {
    position: geometry.Vector3,
    color: corecolor.Color_RGBA8,
    brush_size: f32,
    waiting: bool,
}

Builder_Text_Button_Draw :: struct {
    bounds: geometry.Rectangle,
    prepared: uiwidgets.Text_Button_Result,
    label: string,
    layout: Builder_Surface_Layout,
    selected: bool,
}

// Resolve one of the four fixed Builder palette colors.
builder_palette_color :: #force_inline proc(index: int) -> corecolor.Color_RGBA8 {
    switch index {
    case 0:
        return {70, 130, 180, 255}
    case 1:
        return {255, 130, 171, 255}
    case 2:
        return {205, 198, 115, 255}
    case 3:
        return {153, 153, 153, 255}
    }
    return buildermodel.BUILDER_DEFAULT_COLOR
}

// Resolve a Builder palette control's accessible name from the active locale.
builder_palette_name :: proc(
    state: ^core.Euclid_General_State, index: int) -> string {
    id := contentdata.Content_Message_Id.Builder_Palette_Steelblue
    switch index {
    case 1:
        id = .Builder_Palette_Palevioletred
    case 2:
        id = .Builder_Palette_Khaki
    case 3:
        id = .Builder_Palette_Grey
    }
    return viewmessages.shell_message(state, id)
}

// Prepare Builder controls, gestures, semantic nodes, and frame-local commands.
prepare_builder_surface :: proc(
    state: ^core.Euclid_General_State,
    frame: input.Input_Frame) -> Builder_Surface_Preparation {
    result: Builder_Surface_Preparation
    if state == nil {
        return result
    }
    if !is_builder_selected(state) {
        if builder_control_press_id(state^.ui_runtime.input.press_owner.id) {
            builder_release_surface_capture(state)
        }
        return result
    }
    runtime := &state^.ui_runtime
    builder := &state^.builder
    panel := geometry.Rectangle(runtime^.layout.ui_regions.text_rect)
    clip := geometry.Rectangle(uiaccordion.ui_presentation_clip(
        &runtime^.layout, panel))
    visible := uipresentation.ui_presentation_is_visible(&runtime^.presentation) &&
        clip.width > 0 && clip.height > 0
    interactive := builder_reconcile_surface_interaction(
        state, visible, frame.window_focused)
    surface_frame := frame
    if !interactive {
        surface_frame = input.input_frame_filter_pointer(frame, {.Screen_Position})
    }
    result.active = true
    result.layout = builder_surface_layout(state, panel, clip)
    builder_reconcile_capture_layout(state, panel, clip,
        geometry.Rectangle(runtime^.layout.ui_regions.world_rect))
    builder_prepare_surface_interactions(
        state, surface_frame, interactive,
        visible && !builder_surface_overlay_active(state), &result)
    result.tool_active = builder^.tool == .Point
    return result
}

// Prepare scrolling, semantics, controls, and board gestures for one surface frame.
builder_prepare_surface_interactions :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive, semantics_visible: bool,
    result: ^Builder_Surface_Preparation) {
    builder := &state^.builder
    builder_prepare_scroll(state, frame, interactive, result)
    builder_reconcile_waiting_point(builder)
    builder_prepare_selection_draft(builder)
    builder_prepare_pending_action(state, &result^.command)
    if result^.command.kind == .None && !builder_brush_slider_captured(state) {
        result^.command = builder_pending_style_request(builder)
    }
    builder_register_surface_semantics(
        state, semantics_visible, result^.layout.panel_clip)
    builder_prepare_surface_controls(state, frame, interactive, result)
    builder_prepare_board_gesture(state, frame, result)
}

// Release Builder captures and gate input behind focus loss or modal overlays.
builder_reconcile_surface_interaction :: proc(
    state: ^core.Euclid_General_State, visible, window_focused: bool) -> bool {
    interactive := visible && window_focused &&
        !builder_surface_overlay_active(state)
    if !interactive {
        builder_release_surface_capture(state)
    }
    return interactive
}

// Identify UI overlays that must own all pointer and keyboard interaction.
builder_surface_overlay_active :: #force_inline proc(
    state: ^core.Euclid_General_State) -> bool {
    runtime := &state^.ui_runtime
    return runtime^.context_menu.active || runtime^.membership.active
}

// Compute compact Builder panel geometry using the active UI scale.
builder_surface_layout :: proc(
    state: ^core.Euclid_General_State,
    panel, clip: geometry.Rectangle) -> Builder_Surface_Layout {
    prefs := state^.ui_runtime.preferences.values.interface
    scale := theme.ui_control_size_scale(prefs.control_size_percent)
    text_size := theme.ui_font_size(prefs.text_size_percent)
    sections := builder_surface_layout_sections(panel, clip, text_size, scale)
    return builder_surface_layout_result(panel, sections, text_size, scale)
}

// Compute fixed sections, toolbar controls, and contextual control geometry.
builder_surface_layout_sections :: proc(
    panel, clip: geometry.Rectangle, text_size, scale: f32) ->
    Builder_Surface_Sections {
    inset := 6 * scale
    button_height := max(26 * scale, text_size + 8 * scale)
    section_padding := 6 * scale
    section_gap := 8 * scale
    inner_width := max(f32(0), panel.width - inset * 2)
    tool_section: geometry.Rectangle = {
        panel.x + inset, panel.y + inset, inner_width,
        button_height + section_padding * 2,
    }
    toolbar := builder_toolbar_buttons_layout(
        tool_section, section_padding, button_height, 6 * scale)
    options_y := tool_section.y + tool_section.height + section_gap
    options_section: geometry.Rectangle = {
        panel.x + inset, options_y, inner_width,
        max(f32(0), panel.y + panel.height - inset - options_y),
    }
    options := builder_options_layout({
        section = options_section,
        section_y = options_y,
        padding = section_padding,
        button_height = button_height,
        text_size = text_size,
        scale = scale,
    })
    panel_clip := geometry.Rectangle(clip)
    tool_clip := builder_rectangle_intersection(tool_section, panel_clip)
    options_clip := builder_rectangle_intersection(options_section, panel_clip)
    return {
        panel_clip = panel_clip,
        tool_section = tool_section,
        tool_clip = tool_clip,
        options_section = options_section,
        options_clip = options_clip,
        toolbar = toolbar,
        options = options,
    }
}

// Assemble all prepared Builder geometry into its public layout record.
builder_surface_layout_result :: proc(
    panel: geometry.Rectangle, sections: Builder_Surface_Sections,
    text_size, scale: f32) -> Builder_Surface_Layout {
    return {
        panel = panel,
        panel_clip = sections.panel_clip,
        tool_section = sections.tool_section,
        tool_clip = sections.tool_clip,
        options_section = sections.options_section,
        clip = sections.options_clip,
        select_tool = sections.toolbar[0],
        tool = sections.toolbar[1],
        palette = sections.options.palette,
        brush_row_y = sections.options.brush_row_y,
        hide = sections.options.hide,
        show = sections.options.show,
        status_y = sections.options.status_y,
        text_size = text_size,
        scale = scale,
        content_height = sections.options.content_height,
    }
}

// Lay out the fixed neutral and Point controls in their shared toolbar row.
builder_toolbar_buttons_layout :: proc(
    section: geometry.Rectangle,
    padding, button_size, gap: f32) -> [2]geometry.Rectangle {
    x := section.x + padding
    y := section.y + padding
    return {
        {x, y, button_size, button_size},
        {x + button_size + gap, y, button_size, button_size},
    }
}

// Lay out style controls within the contextual Builder section.
builder_options_layout :: proc(
    request: Builder_Options_Layout_Request) -> Builder_Options_Layout {
    gap := 6 * request.scale
    control_width := max(f32(0), request.section.width -
        request.padding * 2 - theme.SCROLLBAR_WIDTH * request.scale)
    palette_width := max(f32(0), (control_width - gap * 3) / 4)
    palette_y := request.section_y + request.padding
    palette := builder_palette_layout(
        request.section.x + request.padding, palette_y, palette_width, gap,
        request.button_height)
    brush_row_y := palette_y + request.button_height +
        request.text_size + 10 * request.scale
    action_y := brush_row_y + request.text_size + 38 * request.scale
    action_width := max(f32(0), (control_width - gap) * 0.5)
    status_y := action_y + request.button_height + 12 * request.scale
    return {
        palette = palette,
        brush_row_y = brush_row_y,
        hide = {
            request.section.x + request.padding,
            action_y,
            action_width,
            request.button_height,
        },
        show = {
            request.section.x + request.padding + action_width + gap,
            action_y,
            action_width,
            request.button_height,
        },
        status_y = status_y,
        content_height = status_y + request.text_size +
            request.padding - request.section_y,
    }
}

// Lay out the four equally sized Builder palette swatches.
builder_palette_layout :: proc(
    x, y, width, gap, height: f32) -> [4]geometry.Rectangle {
    palette: [4]geometry.Rectangle
    for index in 0..<4 {
        palette[index] = {
            x + f32(index) * (width + gap),
            y,
            width,
            height,
        }
    }
    return palette
}

// Intersect a fixed Builder section with the visible presentation clip.
builder_rectangle_intersection :: #force_inline proc(
    rect, clip: geometry.Rectangle) -> geometry.Rectangle {
    left := max(rect.x, clip.x)
    top := max(rect.y, clip.y)
    right := min(rect.x + rect.width, clip.x + clip.width)
    bottom := min(rect.y + rect.height, clip.y + clip.height)
    return {left, top, max(f32(0), right - left), max(f32(0), bottom - top)}
}

// Prepare the contextual section's scroll range without moving the fixed header.
builder_prepare_scroll :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    ui := &state^.ui_runtime
    builder_ui := &ui^.builder
    layout := &result^.layout
    content_height := f32(0)
    if builder_contextual_options_visible(&state^.builder) {
        content_height = layout^.content_height
    }
    if interactive {
        step := layout^.text_size * theme.WHEEL_SCROLL_MULTIPLIER
        result^.scroll = uiwidgets.scroll_container_update({
            id = BUILDER_SCROLLBAR_ID,
            rect = layout^.clip,
            scroll_y_in = builder_ui^.scroll_y,
            content_height = content_height,
            mouse_input = frame,
            interaction_space_rect = layout^.clip,
            wheel_step = step,
            control_size_percent = ui^.preferences.values.interface.control_size_percent,
            press_owner = &ui^.input.press_owner,
            state_in = {
                builder_ui^.scroll_dragging,
                builder_ui^.scroll_drag_off,
            },
            semantic_focus = ui^.semantic_focus,
            semantic_id = uisemantics.semantic_control_id(
                .Builder, BUILDER_SURFACE_SEMANTIC_ID),
        })
    } else {
        result^.scroll = uiwidgets.scroll_container_visual(
            layout^.clip, content_height, builder_ui^.scroll_y,
            layout^.text_size * theme.WHEEL_SCROLL_MULTIPLIER,
            ui^.preferences.values.interface.control_size_percent)
        builder_ui^.scroll_dragging = false
        builder_ui^.scroll_drag_off = 0
    }
    builder_ui^.scroll_y = result^.scroll.scroll_y_out
    builder_ui^.scroll_dragging = result^.scroll.state_out.is_dragging_thumb
    builder_ui^.scroll_drag_off = result^.scroll.state_out.drag_offset_y
    builder_scroll_layout(layout, result^.scroll.scroll_y_out)
}

// Offset only contextual controls; the panel, sections, and toolbar stay fixed.
builder_scroll_layout :: proc(layout: ^Builder_Surface_Layout, scroll_y: f32) {
    for &palette in layout^.palette {
        palette.y -= scroll_y
    }
    layout^.brush_row_y -= scroll_y
    layout^.hide.y -= scroll_y
    layout^.show.y -= scroll_y
    layout^.status_y -= scroll_y
}

// Register the scrollable Builder surface as the accessible keyboard target.
builder_register_surface_semantics :: proc(
    state: ^core.Euclid_General_State, visible: bool,
    clip: geometry.Rectangle) {
    if !visible {
        return
    }
    label := viewmessages.shell_message(state, .Builder_Status_Idle)
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = uisemantics.semantic_control_id(.Builder, BUILDER_SURFACE_SEMANTIC_ID),
        role = .Panel,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll, .Set_Value},
        region = .Presentation,
        traversal_order = 0,
        bounds = clip,
        clip_bounds = clip,
        label = label,
        value = label,
    })
}

// Invalidate Builder captures when its panel or world geometry changes.
builder_reconcile_capture_layout :: proc(
    state: ^core.Euclid_General_State,
    panel, clip, world_rect: geometry.Rectangle) {
    ui := &state^.ui_runtime.builder
    changed := ui^.layout_initialized &&
        (ui^.last_panel != panel || ui^.last_clip != clip ||
            ui^.last_world != world_rect)
    if changed {
        builder_release_surface_capture(state)
    }
    ui^.layout_initialized = true
    ui^.last_panel = panel
    ui^.last_clip = clip
    ui^.last_world = world_rect
}

// Release only a Builder-owned gesture or scrollbar capture.
builder_release_surface_capture :: proc(state: ^core.Euclid_General_State) {
    builder_cancel_gesture(state)
    ui := &state^.ui_runtime
    uiwidgets.scroll_container_release_press(
        &ui^.input.press_owner, BUILDER_SCROLLBAR_ID,
        &ui^.builder.scroll_dragging, &ui^.builder.scroll_drag_off)
    if ui^.input.press_owner.active &&
        builder_control_press_id(ui^.input.press_owner.id) {
        ui^.input.press_owner = {}
    }
}

// Prepare Builder buttons and the brush slider without owning frame submission.
builder_prepare_surface_controls :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    visible: bool, result: ^Builder_Surface_Preparation) {
    builder_prepare_select_button(state, frame, visible, result)
    builder_prepare_tool_button(state, frame, visible, result)
    result^.contextual_options_visible =
        builder_contextual_options_visible(&state^.builder)
    if !result^.contextual_options_visible {
        return
    }
    builder_prepare_palette_buttons(state, frame, visible, result)
    builder_prepare_brush_slider(state, frame, visible, result)
    builder_prepare_visibility_buttons(state, frame, visible, result)
}

// Prepare the neutral selection control and clear selection on activation.
builder_prepare_select_button :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    runtime := &state^.ui_runtime
    builder := &state^.builder
    layout := result^.layout
    label := viewmessages.shell_message(state, .Builder_Tool_Select)
    selected := builder^.tool == .None &&
        builder^.selected_point.generation == 0
    result^.select_button = uiwidgets.prepare_text_button({
        id = BUILDER_SELECT_BUTTON_ID,
        rect = layout.select_tool,
        label = label,
        enabled = true,
        mouse = frame,
        interaction_space_rect = layout.tool_clip,
        interaction_enabled = interactive,
        font = viewfont.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantics = builder_button_semantics(runtime, {
            id = BUILDER_SELECT_BUTTON_ID,
            label = label,
            order = 1,
            clip = layout.tool_clip,
            interactive = interactive,
            value = builder_tool_semantic_value(state, builder^.tool),
            selected = selected,
        }),
    }, &runtime^.input.press_owner, interactive)
    builder_offer_toolbar_tooltip(state, BUILDER_SELECT_BUTTON_ID, label,
        layout.select_tool, result^.select_button)
    if result^.select_button.action.activated {
        builder_apply_select_button_activation(state, result)
    }
}

// Show style controls only while placing or inspecting a point.
builder_contextual_options_visible :: #force_inline proc(
    builder: ^buildermodel.Runtime) -> bool {
    return builder^.tool == .Point ||
        builder^.selected_point.generation != 0 ||
        builder^.placement_phase != .Idle
}

// Prepare and apply the Builder tool button for one surface frame.
builder_prepare_tool_button :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    runtime := &state^.ui_runtime
    builder := &state^.builder
    layout := result^.layout
    tool_label := viewmessages.shell_message(state, .Builder_Tool_Point)
    tool_value := builder_tool_semantic_value(state, builder^.tool)
    result^.tool_button = uiwidgets.prepare_text_button({
        id = BUILDER_TOOL_BUTTON_ID,
        rect = layout.tool,
        label = tool_label,
        enabled = true,
        mouse = frame,
        interaction_space_rect = result^.layout.tool_clip,
        interaction_enabled = interactive,
        font = viewfont.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantics = builder_button_semantics(runtime, {
            id = BUILDER_TOOL_BUTTON_ID,
            label = tool_label,
            order = 2,
            clip = layout.tool_clip,
            interactive = interactive,
            value = tool_value,
            selected = builder^.tool == .Point,
        }),
    }, &runtime^.input.press_owner, interactive)
    builder_offer_toolbar_tooltip(state, BUILDER_TOOL_BUTTON_ID, tool_label,
        layout.tool, result^.tool_button)
    if result^.tool_button.action.activated {
        builder_apply_tool_button_activation(state, result)
    }
}

// Offer a localized toolbar label as the shared pointer and keyboard tooltip.
builder_offer_toolbar_tooltip :: proc(
    state: ^core.Euclid_General_State, id: int, label: string,
    bounds: geometry.Rectangle, button: uiwidgets.Text_Button_Result) {
    runtime := &state^.ui_runtime
    owner := uisemantics.semantic_control_id(.Builder, id)
    if button.pressed || button.action.activated {
        uioverlay.tooltip_dismiss(&runtime^.tooltip, owner)
    }
    uioverlay.tooltip_offer(&runtime^.tooltip, {
        owner = owner,
        source = uioverlay.tooltip_control_source(
            &runtime^.input, runtime^.semantic_focus, owner, id),
        anchor = bounds,
        prefer_above = true,
        text = label,
    })
}

// Preserve inspector edits before clearing selection or disarming the Point tool.
builder_apply_select_button_activation :: proc(
    state: ^core.Euclid_General_State,
    result: ^Builder_Surface_Preparation) {
    builder := &state^.builder
    if builder^.style_draft_color_dirty || builder^.style_draft_brush_dirty {
        builder_defer_action(state, .Clear_Selection, builder^.selected_point)
        if !builder_brush_slider_captured(state) {
            result^.command = builder_pending_style_request(builder)
        }
        return
    }
    builder_clear_selection(builder)
}

// Return to neutral selection mode without discarding the next-point style.
builder_clear_selection :: proc(builder: ^buildermodel.Runtime) {
    builder^.tool = .None
    builder^.selected_point = {}
    builder^.style_draft_point = {}
    builder^.style_draft_color_dirty = false
    builder^.style_draft_brush_dirty = false
    if builder^.placement_phase != .Waiting {
        builder^.placement_phase = .Idle
        builder^.placement_status = .Ready
    }
}

// Preserve a dirty point-style draft before toggling the construction tool.
builder_apply_tool_button_activation :: proc(
    state: ^core.Euclid_General_State,
    result: ^Builder_Surface_Preparation) {
    builder := &state^.builder
    if builder^.style_draft_color_dirty || builder^.style_draft_brush_dirty {
        builder_defer_action(state, .Toggle_Tool, {})
        if !builder_brush_slider_captured(state) {
            result^.command = builder_pending_style_request(builder)
        }
        return
    }
    builder_toggle_tool(builder)
}

// Describe the localized active or inactive tool value for accessibility.
builder_tool_semantic_value :: proc(
    state: ^core.Euclid_General_State, tool: buildermodel.Tool_Mode) -> string {
    if tool == .Point {
        return viewmessages.shell_message(state, .Builder_Tool_Active)
    }
    return viewmessages.shell_message(state, .Builder_Tool_Inactive)
}

// Prepare the fixed palette buttons and apply any selected color.
builder_prepare_palette_buttons :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    runtime := &state^.ui_runtime
    builder := &state^.builder
    font := viewfont.cache_borrow(&state^.font_cache, .Regular)
    resolver := viewfont.cache_terminal_resolver(&state^.font_cache)
    for index in 0..<BUILDER_PALETTE_BUTTON_COUNT {
        id := BUILDER_PALETTE_BUTTON_BASE_ID + index
        label := builder_palette_name(state, index)
        result^.palette_buttons[index] = uiwidgets.prepare_text_button({
            id = id,
            rect = result^.layout.palette[index],
            label = label,
            enabled = true,
            mouse = frame,
            interaction_space_rect = result^.layout.clip,
            interaction_enabled = interactive,
            font = font,
            font_resolver = resolver,
            semantics = builder_button_semantics(runtime, {
                id = id,
                label = label,
                order = u32(index + 2),
                clip = result^.layout.clip,
                interactive = interactive,
                selected = builder_palette_is_selected(builder, index),
            }),
        }, &runtime^.input.press_owner, interactive)
        if !result^.palette_buttons[index].action.activated {
            continue
        }
        builder_apply_palette_choice(builder, index, &result^.command)
    }
}

// Build semantic button metadata for one control in the Builder surface.
builder_button_semantics :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    request: Builder_Button_Semantics_Input) -> uiwidgets.Button_Semantics {
    states := uiwidgets.button_semantic_states(true)
    if request.selected {
        states += {.Selected}
    }
    return {
        publish = request.interactive,
        focus = runtime^.semantic_focus,
        id = uisemantics.semantic_control_id(.Builder, request.id),
        role = .Button,
        states = states,
        region = .Presentation,
        traversal_order = request.order,
        clip_bounds = request.clip,
        label = request.label,
        value = request.value,
    }
}

// Describe which palette color is currently applied to the active style draft.
builder_palette_is_selected :: #force_inline proc(
    builder: ^buildermodel.Runtime, index: int) -> bool {
    color := builder^.color
    if builder^.selected_point.generation != 0 {
        color = builder^.style_draft_color
    }
    return color == builder_palette_color(index)
}

// Apply a Point tool toggle and relinquish a prior point selection when arming it.
builder_toggle_tool :: proc(builder: ^buildermodel.Runtime) {
    if builder^.tool == .Point {
        builder^.tool = .None
        return
    }
    builder^.tool = .Point
    builder^.selected_point = {}
    builder^.style_draft_point = {}
    builder^.style_draft_color_dirty = false
    builder^.style_draft_brush_dirty = false
}

// Retain the exact user action until the dirty style draft is admitted.
builder_defer_action :: proc(
    state: ^core.Euclid_General_State,
    action: viewmodel.Ui_Builder_Pending_Action,
    point: buildermodel.Point_Identity) {
    pending := &state^.ui_runtime.builder
    pending^.pending_action = action
    pending^.pending_point_generation = point.generation
    pending^.pending_point_id = point.id
}

// Apply deferred navigation only after all style fields have entered the FIFO.
builder_prepare_pending_action :: proc(
    state: ^core.Euclid_General_State,
    command: ^Builder_Command_Request) {
    pending := &state^.ui_runtime.builder
    builder := &state^.builder
    if pending^.pending_action == .None {
        return
    }
    if pending^.pending_point_generation != 0 &&
        pending^.pending_point_generation != builder^.generation {
        builder_clear_pending_action(pending)
        return
    }
    if builder^.style_draft_color_dirty || builder^.style_draft_brush_dirty {
        if !builder_brush_slider_captured(state) {
            command^ = builder_pending_style_request(builder)
        }
        return
    }
    builder_apply_pending_navigation(builder, pending, command)
}

// Apply one admitted deferred selection, tool toggle, or visibility request.
builder_apply_pending_navigation :: proc(
    builder: ^buildermodel.Runtime,
    pending: ^viewmodel.Ui_Builder_Interaction_State,
    command: ^Builder_Command_Request) {
    switch pending^.pending_action {
    case .Select_Point:
        identity := builder_pending_action_point(pending)
        if builder_find_record(builder, identity) != nil {
            builder_select_point(builder, identity)
        }
        builder_clear_pending_action(pending)
    case .Toggle_Tool:
        builder_toggle_tool(builder)
        builder_clear_pending_action(pending)
    case .Clear_Selection:
        builder_clear_selection(builder)
        builder_clear_pending_action(pending)
    case .Hide_Point:
        command^ = {
            kind = .Hide_Point,
            point = builder_pending_action_point(pending),
        }
    case .Show_Point:
        command^ = {
            kind = .Show_Point,
            point = builder_pending_action_point(pending),
        }
    case .None:
    }
}

// Clear one completed deferred command without disturbing scroll state.
builder_clear_pending_action :: proc(pending: ^viewmodel.Ui_Builder_Interaction_State) {
    pending^.pending_action = .None
    pending^.pending_point_generation = 0
    pending^.pending_point_id = 0
}

// Rebuild the stable point identity retained by one deferred action.
builder_pending_action_point :: #force_inline proc(
    pending: ^viewmodel.Ui_Builder_Interaction_State) -> buildermodel.Point_Identity {
    return {
        generation = pending^.pending_point_generation,
        id = pending^.pending_point_id,
    }
}

// Apply a palette action to either the next-point style or selected-point draft.
builder_apply_palette_choice :: proc(
    builder: ^buildermodel.Runtime, index: int,
    command: ^Builder_Command_Request) {
    if builder^.selected_point.generation == 0 {
        builder^.color = builder_palette_color(index)
        builder^.palette_index = index
        return
    }
    if builder^.style_draft_point != builder^.selected_point {
        builder_prepare_selection_draft(builder)
    }
    builder^.style_draft_color = builder_palette_color(index)
    builder^.style_draft_color_dirty = true
    builder^.palette_index = index
    command^ = builder_pending_style_request(builder)
}

// Prepare a bounded brush slider and coalesce selected-point edits until release.
builder_prepare_brush_slider :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    runtime := &state^.ui_runtime
    builder := &state^.builder
    selected := builder^.selected_point.generation != 0
    brush_value := int(builder^.brush_size)
    if selected {
        brush_value = int(builder^.style_draft_brush_size)
    }
    owner := &runtime^.input.press_owner
    owned_before := owner^.active && owner^.kind == .Slider &&
        owner^.id == BUILDER_BRUSH_SLIDER_ID
    params := builder_brush_slider_params(state, {
        frame = builder_brush_slider_input_frame(
            frame, result^.layout.clip, owned_before),
        layout = result^.layout,
        interactive = interactive,
        brush_value = brush_value,
        press_owner = owner,
    })
    result^.brush = uiwidgets.prepare_integer_slider(params, interactive)
    builder_apply_brush_slider_change(state, frame, owned_before, result)
}

// Keep captured slider motion local and filter pointer samples outside its clip.
builder_brush_slider_input_frame :: proc(
    frame: input.Input_Frame, clip: geometry.Rectangle,
    owned_before: bool) -> input.Input_Frame {
    if owned_before || geometry.rectangle_contains(
        clip, uiwidgets.input_frame_mouse_position(frame)) {
        return frame
    }
    filtered := frame
    filtered.mouse_position = {-1, -1}
    filtered.mouse_pressed = {}
    filtered.mouse_released = {}
    filtered.mouse_down = {}
    filtered.mouse_wheel_delta = 0
    return filtered
}

// Build the slider contract from the prepared Builder surface and owner state.
builder_brush_slider_params :: proc(
    state: ^core.Euclid_General_State,
    request: Builder_Brush_Slider_Input) -> uiwidgets.Integer_Slider_Params {
    runtime := &state^.ui_runtime
    domain := viewmodel.Ui_Node_Domain.None
    if request.interactive {
        domain = .Builder
    }
    return {
        panel = request.layout.clip,
        row_y = request.layout.brush_row_y,
        mouse_input = request.frame,
        press_owner = request.press_owner,
        semantic_focus = runtime^.semantic_focus,
        press_id = BUILDER_BRUSH_SLIDER_ID,
        label = viewmessages.shell_message(state, .Builder_Brush_Label),
        value = request.brush_value,
        min_value = 1,
        max_value = 20,
        step = 1,
        value_suffix = "",
        text_size_percent = runtime^.preferences.values.interface.text_size_percent,
        control_size_percent = runtime^.preferences.values.interface.control_size_percent,
        font = viewfont.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantic_domain = domain,
        semantic_order = 6,
    }
}

// Preserve next-point values and selected-point drafts after slider input.
builder_apply_brush_slider_change :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    owned_before: bool, result: ^Builder_Surface_Preparation) {
    if !result^.brush.changed {
        return
    }
    builder := &state^.builder
    selected := builder^.selected_point.generation != 0
    if !selected {
        builder^.brush_size = f32(result^.brush.value)
        return
    }
    builder^.style_draft_brush_size = f32(result^.brush.value)
    builder^.style_draft_brush_dirty = true
    semantic_change := .Semantic in result^.brush.sources
    released := owned_before && uiwidgets.input_frame_left_released(frame)
    if semantic_change || released {
        result^.command = builder_pending_style_request(builder)
    }
}

// Keep a pointer brush gesture in the inspector draft until its release frame.
builder_brush_slider_captured :: #force_inline proc(
    state: ^core.Euclid_General_State) -> bool {
    owner := state^.ui_runtime.input.press_owner
    return owner.active && owner.id == BUILDER_BRUSH_SLIDER_ID
}

// Prepare Hide and Show without allowing a dirty style edit to be overtaken.
builder_prepare_visibility_buttons :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    interactive: bool, result: ^Builder_Surface_Preparation) {
    builder := &state^.builder
    if builder^.selected_point.generation == 0 {
        return
    }
    record := builder_find_record(builder, builder^.selected_point)
    if record == nil {
        return
    }
    result^.hide_button = builder_prepare_visibility_button(
        state, frame, {
            layout = result^.layout,
            interactive = interactive,
            point_visible = record^.visible,
        })
    result^.show_button = builder_prepare_visibility_button(
        state, frame, {
            layout = result^.layout,
            interactive = interactive,
            point_visible = record^.visible,
            show = true,
        })
    if result^.hide_button.action.activated {
        builder_prepare_visibility_request(
            state, builder, false, &result^.command)
    }
    if result^.show_button.action.activated {
        builder_prepare_visibility_request(
            state, builder, true, &result^.command)
    }
}

// Prepare one enabled Hide or Show control from the current point visibility.
builder_prepare_visibility_button :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    request: Builder_Visibility_Button_Input) -> uiwidgets.Text_Button_Result {
    runtime := &state^.ui_runtime
    id := BUILDER_HIDE_BUTTON_ID
    bounds := request.layout.hide
    message := contentdata.Content_Message_Id.Builder_Hide
    order := u32(7)
    enabled := request.point_visible
    if request.show {
        id = BUILDER_SHOW_BUTTON_ID
        bounds = request.layout.show
        message = .Builder_Show
        order = 8
        enabled = !request.point_visible
    }
    label := viewmessages.shell_message(state, message)
    return uiwidgets.prepare_text_button({
        id = id,
        rect = bounds,
        label = label,
        enabled = enabled,
        mouse = frame,
        interaction_space_rect = request.layout.clip,
        interaction_enabled = request.interactive,
        font = viewfont.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantics = builder_button_semantics(runtime, {
            id = id,
            label = label,
            order = order,
            clip = request.layout.clip,
            interactive = request.interactive && enabled,
        }),
    }, &runtime^.input.press_owner, request.interactive)
}

// Preserve style-before-visibility FIFO ordering for selected-point actions.
builder_prepare_visibility_request :: proc(
    state: ^core.Euclid_General_State, builder: ^buildermodel.Runtime, visible: bool,
    command: ^Builder_Command_Request) {
    if builder^.style_draft_color_dirty || builder^.style_draft_brush_dirty {
        action := viewmodel.Ui_Builder_Pending_Action.Hide_Point
        if visible {
            action = .Show_Point
        }
        builder_defer_action(state, action, builder^.selected_point)
        if !builder_brush_slider_captured(state) {
            command^ = builder_pending_style_request(builder)
        }
        return
    }
    command.kind = Builder_Command_Kind.Hide_Point
    if visible {
        command.kind = .Show_Point
    }
    command.point = builder^.selected_point
}

// Build the next retryable style request from only fields edited but not admitted.
builder_pending_style_request :: proc(
    builder: ^buildermodel.Runtime) -> Builder_Command_Request {
    if builder^.selected_point.generation == 0 ||
        (!builder^.style_draft_color_dirty && !builder^.style_draft_brush_dirty) {
        return {}
    }
    return {
        kind = .Edit_Style,
        point = builder^.selected_point,
        style = {
            color_set = builder^.style_draft_color_dirty,
            color = builder^.style_draft_color,
            brush_set = builder^.style_draft_brush_dirty,
            brush_size = builder^.style_draft_brush_size,
        },
    }
}

// Resolve a frame's point selection, placement gesture, or one-shot placement.
builder_prepare_board_gesture :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    result: ^Builder_Surface_Preparation) {
    runtime := &state^.ui_runtime
    world_rect := geometry.Rectangle(runtime^.layout.ui_regions.world_rect)
    mouse := uiwidgets.input_frame_mouse_position(frame)
    over_board := geometry.rectangle_contains(world_rect, mouse)
    shake_enabled :=
        state^.gif_capture_status.gif_capture_phase != .Recording &&
        !viewpresentation.presentation_reduced_motion_enabled(state)
    if builder_escape_pressed(frame) || !frame.window_focused {
        builder_cancel_gesture(state)
    }
    if builder_continue_pointer_gesture(state, {
        frame = frame,
        mouse = mouse,
        over_board = over_board,
        shake_enabled = shake_enabled,
    }, result) {
        return
    }
    if uiwidgets.input_frame_left_pressed(frame) && over_board {
        builder_begin_pointer_gesture(state, mouse, shake_enabled, result)
        return
    }
    builder_update_placement_preview(state, mouse, over_board, shake_enabled)
}

// Continue a captured placement and publish only a valid in-board release.
builder_continue_pointer_gesture :: proc(
    state: ^core.Euclid_General_State, gesture: Builder_Pointer_Gesture_Input,
    result: ^Builder_Surface_Preparation) -> bool {
    runtime := &state^.ui_runtime
    builder := &state^.builder
    owns_gesture := runtime^.input.press_owner.active &&
        runtime^.input.press_owner.kind == .Builder_Placement &&
        runtime^.input.press_owner.id == BUILDER_PLACEMENT_PRESS_ID
    if !owns_gesture || !builder^.gesture_active {
        return false
    }
    if uiwidgets.input_frame_left_down(gesture.frame) && gesture.over_board {
        position, valid := projection.cartesian_to_iso_board(
            gesture.mouse, state^.iso_scale, gesture.shake_enabled)
        if valid && builder_board_position_valid(position) {
            builder^.placement_position = position
        }
    }
    if uiwidgets.input_frame_left_released(gesture.frame) {
        builder_finish_pointer_gesture(state, gesture, result)
    }
    return true
}

// Admit a valid release point or end the placement without submitting it.
builder_finish_pointer_gesture :: proc(
    state: ^core.Euclid_General_State, gesture: Builder_Pointer_Gesture_Input,
    result: ^Builder_Surface_Preparation) {
    builder := &state^.builder
    position, valid := projection.cartesian_to_iso_board(
        gesture.mouse, state^.iso_scale, gesture.shake_enabled)
    if gesture.over_board && valid && builder_board_position_valid(position) &&
        !builder^.style_draft_color_dirty &&
        !builder^.style_draft_brush_dirty {
        result^.placement = {
            active = true,
            position = position,
            color = builder^.gesture_style.color,
            brush_size = builder^.gesture_style.brush_size,
        }
        builder^.placement_position = position
        builder^.placement_phase = .Waiting
    } else {
        builder^.placement_phase = .Idle
    }
    builder_cancel_gesture(state)
}

// Capture an eligible board press or select the point beneath it.
builder_begin_pointer_gesture :: proc(
    state: ^core.Euclid_General_State, mouse: geometry.Vector2,
    shake_enabled: bool, result: ^Builder_Surface_Preparation) {
    if state^.ui_runtime.input.press_owner.active {
        return
    }
    builder := &state^.builder
    hit := builder_hit_test(state, mouse)
    if hit.generation != 0 {
        if builder^.style_draft_color_dirty ||
            builder^.style_draft_brush_dirty {
            builder_defer_action(state, .Select_Point, hit)
            if result^.command.kind == .None {
                result^.command = builder_pending_style_request(builder)
            }
        } else {
            builder_select_point(builder, hit)
        }
        return
    }
    if builder^.tool != .Point || builder^.style_draft_color_dirty ||
        builder^.style_draft_brush_dirty {
        return
    }
    position, valid := projection.cartesian_to_iso_board(
        mouse, state^.iso_scale, shake_enabled)
    if !valid || !builder_board_position_valid(position) {
        return
    }
    builder^.gesture_active = true
    builder^.gesture_style = {
        color_set = true,
        color = builder^.color,
        brush_set = true,
        brush_size = builder^.brush_size,
    }
    builder^.placement_position = position
    builder^.placement_phase = .Held
    state^.ui_runtime.input.press_owner = {
        active = true,
        kind = .Builder_Placement,
        id = BUILDER_PLACEMENT_PRESS_ID,
    }
}

// Update the idle placement preview without disturbing a pending release.
builder_update_placement_preview :: proc(
    state: ^core.Euclid_General_State, mouse: geometry.Vector2,
    over_board, shake_enabled: bool) {
    builder := &state^.builder
    if builder^.gesture_active {
        builder_cancel_gesture(state)
        return
    }
    if builder^.tool == .Point && over_board {
        position, valid := projection.cartesian_to_iso_board(
            mouse, state^.iso_scale, shake_enabled)
        if valid && builder_board_position_valid(position) {
            builder^.placement_position = position
            builder^.placement_phase = .Hover
            return
        }
    }
    if builder^.placement_phase != .Waiting {
        builder^.placement_phase = .Idle
    }
}

// Confirm that an inverse-projected position lies on the bounded drawing board.
builder_board_position_valid :: #force_inline proc(position: geometry.Vector3) -> bool {
    return position.x >= 0 && position.x <= 1 &&
        position.y >= 0 && position.y <= 1
}

// Select the nearest completed visible point under the pointer.
builder_hit_test :: proc(
    state: ^core.Euclid_General_State,
    mouse: geometry.Vector2) -> buildermodel.Point_Identity {
    builder := &state^.builder
    scale := state^.iso_scale
    shake_enabled :=
        state^.gif_capture_status.gif_capture_phase != .Recording &&
        !viewpresentation.presentation_reduced_motion_enabled(state)
    _ = projection.screenshake_apply_origin(&scale, shake_enabled)
    best: buildermodel.Point_Identity
    best_distance := f32(1.0e30)
    for index in 0..<builder^.point_count {
        point := &builder^.points[index]
        if point^.state != .Ready || !point^.visible ||
            point^.identity.generation != builder^.generation {
            continue
        }
        projected := projection.iso_to_cartesian(point^.position, scale)
        dx := projected.x - mouse.x
        dy := projected.y - mouse.y
        radius := max(f32(8), projection.effective_ink_size(
            point^.brush_size, state^.iso_scale,
            state^.ui_runtime.preferences.values.animation.scale_percent) + 6)
        distance := dx * dx + dy * dy
        if distance <= radius * radius &&
            (distance < best_distance ||
                distance == best_distance && point^.identity.id > best.id) {
            best = point^.identity
            best_distance = distance
        }
    }
    return best
}

// Apply a new selection and initialize its inspector draft from committed style.
builder_select_point :: proc(
    builder: ^buildermodel.Runtime, identity: buildermodel.Point_Identity) {
    record := builder_find_record(builder, identity)
    if record == nil {
        return
    }
    builder^.selected_point = identity
    builder^.tool = .None
    builder^.style_draft_point = identity
    builder^.style_draft_color = record^.color
    builder^.style_draft_brush_size = record^.brush_size
    builder^.style_draft_color_dirty = false
    builder^.style_draft_brush_dirty = false
    builder^.palette_index = builder_palette_index(record^.color)
}

// Find the compact palette index matching a committed point color.
builder_palette_index :: proc(value: corecolor.Color_RGBA8) -> int {
    for index in 0..<BUILDER_PALETTE_BUTTON_COUNT {
        if value == builder_palette_color(index) {
            return index
        }
    }
    return 0
}

// Rebase an inspector draft after the selected point changes or commits style.
builder_prepare_selection_draft :: proc(builder: ^buildermodel.Runtime) {
    if builder^.selected_point.generation == 0 {
        return
    }
    if builder^.style_draft_point == builder^.selected_point {
        return
    }
    record := builder_find_record(builder, builder^.selected_point)
    if record == nil {
        builder^.selected_point = {}
        builder^.style_draft_point = {}
        return
    }
    builder^.style_draft_point = builder^.selected_point
    builder^.style_draft_color = record^.color
    builder^.style_draft_brush_size = record^.brush_size
    builder^.style_draft_color_dirty = false
    builder^.style_draft_brush_dirty = false
}

// Find one retained logical point without exposing a slot as its public identity.
builder_find_record :: proc(
    builder: ^buildermodel.Runtime,
    identity: buildermodel.Point_Identity) -> ^buildermodel.Point_Record {
    for index in 0..<builder^.point_count {
        if builder^.points[index].identity == identity {
            return &builder^.points[index]
        }
    }
    return nil
}

// Clear the transient waiting marker once its native operation completes.
builder_reconcile_waiting_point :: proc(builder: ^buildermodel.Runtime) {
    if builder^.waiting_point.generation == 0 {
        return
    }
    point := builder_find_record(builder, builder^.waiting_point)
    if point == nil || point^.state == .Ready || point^.state == .Failed {
        builder^.waiting_point = {}
        if builder^.placement_phase == .Waiting {
            builder^.placement_phase = .Idle
        }
    }
}

// Cancel only the active pointer gesture and its owner capture.
builder_cancel_gesture :: proc(state: ^core.Euclid_General_State) {
    builder := &state^.builder
    builder^.gesture_active = false
    if builder^.placement_phase == .Held {
        builder^.placement_phase = .Idle
    }
    owner := &state^.ui_runtime.input.press_owner
    if owner^.active && owner^.kind == .Builder_Placement &&
        owner^.id == BUILDER_PLACEMENT_PRESS_ID {
        owner^ = {}
    }
}

// Detect an unmodified Escape press in the immutable device frame.
builder_escape_pressed :: proc(frame: input.Input_Frame) -> bool {
    for event in frame.events {
        if event.kind == .Press && event.key == .Escape {
            return true
        }
    }
    return false
}

// Apply the frame-owner admission result to the waiting point and feedback state.
builder_placement_result :: proc(
    builder: ^buildermodel.Runtime,
    identity: buildermodel.Point_Identity,
    status: buildermodel.Placement_Status) {
    builder^.placement_status = status
    if status != .Point_Queued || identity.generation == 0 {
        builder^.waiting_point = {}
        if builder^.placement_phase == .Waiting {
            builder^.placement_phase = .Idle
        }
        return
    }
    builder^.selected_point = identity
    builder^.tool = .None
    builder^.waiting_point = identity
    builder^.style_draft_point = {}
}

// Clear only the style fields admitted by the shared Builder scheduler.
builder_style_command_result :: proc(
    builder: ^buildermodel.Runtime, request: Builder_Command_Request,
    admitted: bool) {
    if !admitted || request.kind != .Edit_Style ||
        request.point != builder^.selected_point {
        return
    }
    if request.style.color_set &&
        request.style.color == builder^.style_draft_color {
        builder^.style_draft_color_dirty = false
    }
    if request.style.brush_set &&
        request.style.brush_size == builder^.style_draft_brush_size {
        builder^.style_draft_brush_dirty = false
    }
    builder^.placement_status = .Point_Queued
}

// Retire a deferred visibility intent only after its exact FIFO command is admitted.
builder_command_result :: proc(
    state: ^core.Euclid_General_State,
    request: Builder_Command_Request, admitted: bool) {
    builder_style_command_result(&state^.builder, request, admitted)
    if !admitted {
        return
    }
    pending := &state^.ui_runtime.builder
    point := builder_pending_action_point(pending)
    if request.point == point &&
        ((pending^.pending_action == .Hide_Point &&
            request.kind == .Hide_Point) ||
            (pending^.pending_action == .Show_Point &&
                request.kind == .Show_Point)) {
        builder_clear_pending_action(pending)
    }
}

// Draw Builder's waiting marker on the board below tools and their shadows.
draw_world_waiting_marker :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    if !is_builder_selected(state) {
        return
    }
    builder_draw_waiting_marker(state, encoder, &state^.builder)
}

// Draw Builder's clipped preview and selected-point markers.
draw_world_marker :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    if !is_builder_selected(state) {
        return
    }
    builder := &state^.builder
    builder_draw_placement_markers(state, encoder, builder)
    builder_draw_selected_point_marker(state, encoder, builder)
}

// Draw the transient placement preview for the active Builder.
builder_draw_placement_markers :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    builder: ^buildermodel.Runtime) {
    if builder^.tool == .Point &&
        (builder^.placement_phase == .Hover ||
            builder^.placement_phase == .Held) {
        alpha := u8(110)
        if builder^.placement_phase == .Held {
            alpha = 255
        }
        preview_color := builder^.color
        preview_color[3] = alpha
        builder_draw_point_marker(state, encoder, {
            position = builder^.placement_position,
            color = preview_color,
            brush_size = builder^.brush_size,
        })
    }
}

// Draw the pending construction marker until its operation finishes.
builder_draw_waiting_marker :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    builder: ^buildermodel.Runtime) {
    waiting := builder_find_record(builder, builder^.waiting_point)
    if waiting != nil && waiting^.state != .Ready && waiting^.state != .Failed {
        marker_color := waiting^.color
        marker_color[3] = 120
        builder_draw_point_marker(state, encoder, {
            position = waiting^.position,
            color = marker_color,
            brush_size = waiting^.brush_size,
            waiting = true,
        })
    }
}

// Draw the selected point's pulse without changing its authored base style.
builder_draw_selected_point_marker :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    builder: ^buildermodel.Runtime) {
    selected := builder_find_record(builder, builder^.selected_point)
    if selected != nil && selected^.state == .Ready && selected^.visible {
        prefs := state^.ui_runtime.preferences.values
        projected := projection.iso_to_cartesian(selected^.position, state^.iso_scale)
        radius := projection.effective_ink_size(selected^.brush_size,
            state^.iso_scale, prefs.animation.scale_percent)
        reduced_motion := viewpresentation.presentation_reduced_motion_enabled(state)
        radius *= builder_selection_breathing_scale(
            state^.simulation_time, reduced_motion)
        _ = native.draw_encoder_circle(encoder, projected, radius, selected^.color)
    }
}

// Return the visible radius scale for one selected-point breathing cycle.
builder_selection_breathing_scale :: #force_inline proc(
    simulation_time: f32, reduced_motion: bool) -> f32 {
    if reduced_motion {
        return 1
    }
    phase := simulation_time * f32(2 * math.PI) /
        BUILDER_SELECTION_BREATH_PERIOD_SECONDS
    pulse := (1 - f32(math.cos(f64(phase)))) * 0.5
    return 1 + BUILDER_SELECTION_BREATH_MAX_EXPANSION * pulse
}

// Draw one preview or waiting marker in the same projected ink scale as points.
builder_draw_point_marker :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    marker: Builder_Point_Marker_Draw) {
    projected := projection.iso_to_cartesian(marker.position, state^.iso_scale)
    radius := projection.effective_ink_size(marker.brush_size, state^.iso_scale,
        state^.ui_runtime.preferences.values.animation.scale_percent)
    _ = native.draw_encoder_circle(encoder, projected, radius, marker.color)
    if marker.waiting {
        outlined_color := marker.color
        outlined_color[3] = 210
        _ = native.draw_encoder_ring(encoder, projected, radius + 2, radius + 4,
            outlined_color)
    }
}

// Draw the Builder controls and status inside the presentation panel clip.
draw_encoded_builder_surface :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Builder_Surface_Preparation) {
    if !prepared.active {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, prepared.layout.panel_clip)
    builder_draw_surface_sections(encoder, prepared.layout)
    _ = native.draw_encoder_push_scissor(encoder, prepared.layout.tool_clip)
    builder_draw_toolbar_controls(state, encoder, prepared)
    _ = native.draw_encoder_pop_scissor(encoder)
    _ = native.draw_encoder_push_scissor(encoder, prepared.layout.clip)
    builder_draw_contextual_controls(state, encoder, prepared)
    uiwidgets.draw_encoded_scrollbar(encoder, prepared.scroll.scrollbar)
    _ = native.draw_encoder_pop_scissor(encoder)
    _ = native.draw_encoder_pop_scissor(encoder)
}

// Draw the Builder panel and its two outlined component sections.
builder_draw_surface_sections :: proc(
    encoder: ^native.Draw_Encoder, layout: Builder_Surface_Layout) {
    _ = native.draw_encoder_rectangle(
        encoder, layout.panel, worldmodel.BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, layout.panel, layout.scale, theme.UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle(
        encoder, layout.tool_section, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, layout.tool_section, 1, theme.UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle(
        encoder, layout.options_section, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, layout.options_section, 1, theme.UI_BORDER_COLOR)
}

// Draw the neutral cursor and Point controls with shared hover feedback.
builder_draw_toolbar_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Builder_Surface_Preparation) {
    select_active := state^.builder.tool == .None &&
        state^.builder.selected_point.generation == 0
    builder_draw_toolbar_button(
        encoder, prepared.layout.select_tool, prepared.select_button,
        select_active, prepared.layout.scale)
    builder_draw_cursor_icon(encoder, prepared.layout.select_tool,
        theme.draw_color(encoder, .Text))
    builder_draw_toolbar_button(
        encoder, prepared.layout.tool, prepared.tool_button,
        prepared.tool_active, prepared.layout.scale)
    builder_draw_point_icon(encoder, prepared.layout.tool,
        theme.draw_color(encoder, .Text))
}

// Draw contextual style controls, point visibility actions, and status.
builder_draw_contextual_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Builder_Surface_Preparation) {
    if prepared.contextual_options_visible {
        builder_draw_palette(state, encoder, prepared)
        builder_draw_slider(state, encoder, prepared.brush, prepared.layout)
        if state^.builder.selected_point.generation != 0 {
            builder_draw_text_button(state, encoder, {
                bounds = prepared.layout.hide,
                prepared = prepared.hide_button,
                label = viewmessages.shell_message(state, .Builder_Hide),
                layout = prepared.layout,
            })
            builder_draw_text_button(state, encoder, {
                bounds = prepared.layout.show,
                prepared = prepared.show_button,
                label = viewmessages.shell_message(state, .Builder_Show),
                layout = prepared.layout,
            })
        }
        builder_draw_status(state, encoder, prepared)
    }
}

// Draw a compact square toolbar button with the shared selected and hover feedback.
builder_draw_toolbar_button :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle,
    prepared: uiwidgets.Text_Button_Result, selected: bool, scale: f32) {
    fill := theme.UI_COMPONENT_BACKGROUND_COLOR
    if selected || prepared.pressed || prepared.hovered {
        fill = theme.draw_color(encoder, .Control_Border)
    }
    _ = native.draw_encoder_rectangle(encoder, bounds, fill)
    _ = native.draw_encoder_rectangle_outline(
        encoder, bounds, scale, theme.UI_BORDER_COLOR)
}

// Draw the Point tool's filled-dot icon.
builder_draw_point_icon :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle,
    color: corecolor.Color_RGBA8) {
    center: geometry.Vector2 = {
        bounds.x + bounds.width * 0.5,
        bounds.y + bounds.height * 0.5,
    }
    radius := min(bounds.width, bounds.height) * 0.16
    _ = native.draw_encoder_circle(encoder, center, radius, color)
}

// Draw a stemless cursor with a subtle inward notch along its lower edge.
builder_draw_cursor_icon :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle,
    color: corecolor.Color_RGBA8) {
    tip: geometry.Vector2 = {
        bounds.x + bounds.width * 0.28,
        bounds.y + bounds.height * 0.16,
    }
    base: geometry.Vector2 = {
        bounds.x + bounds.width * 0.34,
        bounds.y + bounds.height * 0.78,
    }
    notch: geometry.Vector2 = {
        bounds.x + bounds.width * 0.52,
        bounds.y + bounds.height * 0.61,
    }
    shoulder: geometry.Vector2 = {
        bounds.x + bounds.width * 0.76,
        bounds.y + bounds.height * 0.52,
    }
    _ = native.draw_encoder_triangle(encoder, tip, base, notch, color)
    _ = native.draw_encoder_triangle(encoder, tip, notch, shoulder, color)
}

// Draw fixed palette swatches and indicate the active next-point color.
builder_draw_palette :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Builder_Surface_Preparation) {
    for index in 0..<len(prepared.palette_buttons) {
        bounds := prepared.layout.palette[index]
        _ = native.draw_encoder_rectangle(encoder, bounds,
            theme.UI_COMPONENT_BACKGROUND_COLOR)
        color_rect: geometry.Rectangle = {bounds.x + 3, bounds.y + 3,
            max(f32(0), bounds.width - 6), max(f32(0), bounds.height - 6)}
        _ = native.draw_encoder_rectangle(
            encoder, color_rect, builder_palette_color(index))
        selected := builder_palette_is_selected(&state^.builder, index)
        if selected {
            _ = native.draw_encoder_rectangle_outline(encoder, bounds, 1,
                theme.UI_BORDER_COLOR)
        }
    }
}

// Draw one Builder text button using prepared action geometry.
builder_draw_text_button :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    draw: Builder_Text_Button_Draw) {
    fill := theme.UI_COMPONENT_BACKGROUND_COLOR
    if draw.selected || draw.prepared.pressed || draw.prepared.hovered {
        fill = theme.draw_color(encoder, .Control_Border)
    }
    _ = native.draw_encoder_rectangle(encoder, draw.bounds, fill)
    _ = native.draw_encoder_rectangle_outline(
        encoder, draw.bounds, draw.layout.scale,
        theme.UI_BORDER_COLOR)
    viewtext.draw_encoded_label(&state^.font_cache, encoder, draw.label,
        draw.bounds.x + 7 * draw.layout.scale,
        draw.bounds.y + (draw.bounds.height - draw.layout.text_size) * 0.5)
}

// Draw the captured brush range and its current value.
builder_draw_slider :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    slider: uiwidgets.Integer_Slider_Result, layout: Builder_Surface_Layout) {
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    value := viewmessages.shell_format(state, .Builder_Brush_Value,
        []contentdata.Content_Format_Argument{{"value", u32(slider.value)}},
        storage[:])
    viewtext.draw_encoded_label(&state^.font_cache, encoder, value,
        layout.options_section.x + 8 * layout.scale, layout.brush_row_y)
    scale := slider.track.height / theme.SETTINGS_TRACK_HEIGHT
    knob_center_x := slider.knob.x + slider.knob.width * 0.5
    _ = native.draw_encoder_rectangle(encoder, slider.track,
        worldmodel.BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle(encoder, {
        slider.track.x, slider.track.y,
        max(f32(0), knob_center_x - slider.track.x), slider.track.height,
    }, theme.draw_color(encoder, .Control_Border))
    _ = native.draw_encoder_rectangle(encoder, slider.knob,
        theme.draw_color(encoder, .Text))
    _ = native.draw_encoder_rectangle_outline(encoder, slider.track, scale,
        theme.draw_color(encoder, .Control_Border))
}

// Draw the selected-point and placement status without changing scheduler state.
builder_draw_status :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Builder_Surface_Preparation) {
    message_id := builder_status_message(&state^.builder)
    message_id = builder_status_override(&state^.builder, message_id)
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, message_id),
        prepared.layout.options_section.x + 8 * prepared.layout.scale,
        prepared.layout.status_y)
}

// Select the localized status implied by the active point and selection.
builder_status_message :: proc(
    builder: ^buildermodel.Runtime) -> contentdata.Content_Message_Id {
    message_id := contentdata.Content_Message_Id.Builder_Status_Idle
    if builder^.tool == .Point {
        message_id = .Builder_Status_Armed
    }
    if builder^.selected_point.generation != 0 {
        point := builder_find_record(builder, builder^.selected_point)
        if point != nil {
            message_id = .Builder_Status_Selected
            if point^.state == .Pending || point^.state == .Constructing {
                message_id = .Builder_Status_Constructing
            } else if point^.state == .Failed {
                message_id = .Builder_Status_Point_Failed
            } else if !point^.visible {
                message_id = .Builder_Status_Hidden
            } else if builder^.job_count > 0 {
                message_id = .Builder_Status_Queued
            }
        }
    }
    return message_id
}

// Give queue and capacity failures precedence over ordinary point status.
builder_status_override :: proc(
    builder: ^buildermodel.Runtime,
    current: contentdata.Content_Message_Id) -> contentdata.Content_Message_Id {
    message_id := current
    if builder^.placement_status == .Queue_Full {
        message_id = .Builder_Status_Queue_Full
    } else if builder^.placement_status == .Point_Capacity_Full {
        message_id = .Builder_Status_Point_Capacity
    } else if builder^.placement_status == .Failed {
        message_id = .Builder_Status_Failed
    }
    return message_id
}
