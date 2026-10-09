package uianimation

import native "../../native"
import core "../../../core"
import color "../../../core/color"
import geometry "../../../core/geometry"
import math "core:math"
import capturemodel "../../capture/model"
import viewmodel "../model"
import viewmessages "../../messages"
import viewcapture "../../capture"
import uiwidgets "../widgets"
import theme "../theme"
import input "../../input"
import uisemantics "../semantics"
import worldmodel "../../world/model"
import uioverlay "../overlay"
import bridgemodel "../../../bridge/model"
import collections "../../../collections"
import uuid "core:encoding/uuid"
import crypto "core:crypto"
import viewpreferences "../../preferences"
import log "core:log"
import contentdata "../../../core/content"

ANIMATION_REFRESH_BUTTON_ID :: 2101
ANIMATION_PAUSE_BUTTON_ID :: 2102
ANIMATION_FAVORITE_BUTTON_ID :: 2103

// Fixed board-relative geometry for the animation controls.
Animation_Control_Slots :: struct {
    panel: geometry.Rectangle,
    favorite_panel: geometry.Rectangle,
    refresh: geometry.Rectangle,
    pause: geometry.Rectangle,
    favorite: geometry.Rectangle,
}

// Prepared interaction state for the world animation controls.
Animation_Control_Preparation :: struct {
    visible: bool,
    slots: Animation_Control_Slots,
    refresh: uiwidgets.Icon_Button_Result,
    pause: uiwidgets.Icon_Button_Result,
    favorite_visible: bool,
    favorite_active: bool,
    favorite: uiwidgets.Icon_Button_Result,
}

// Actions emitted by one prepared animation-control frame.
Animation_Control_Hit :: struct {
    refresh_requested: bool,
    toggle_pause_requested: bool,
}

ANIMATION_CONTROL_CORNER_SEGMENTS :: native.DRAW_CIRCLE_SEGMENTS / 4
ANIMATION_CONTROL_HOVER_POINTS :: 4 * (ANIMATION_CONTROL_CORNER_SEGMENTS + 1)

// Convex rounded hover boundary, independent from control hit bounds.
Animation_Control_Hover_Geometry :: struct {
    center: geometry.Vector2,
    boundary: [ANIMATION_CONTROL_HOVER_POINTS]geometry.Vector2,
    radius: f32,
}

// Animation_Control_Descriptor describes one overlay button instance.
Animation_Control_Descriptor :: struct {
    id: int,
    rect: geometry.Rectangle,
    icon_id: uiwidgets.Icon_Button_Id,
    toggle: bool,
    label: string,
    order: u16,
}

// Report whether animation controls should be presented and interactive.
animation_controls_visible :: #force_inline proc(
    phase: capturemodel.Gif_Capture_Phase) -> bool {
    return phase != .Recording
}

// Resolve the selected canonical animation eligible for Favorites membership.
animation_favorite_target :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface) ->
    ^bridgemodel.Euclid_Julia_Animation_Interface {
    if ji == nil || ji^.selected_animation == nil {
        return nil
    }
    animation := ji^.selected_animation
    if animation^.node_kind != .Animation ||
        animation^.stable_id == (uuid.Identifier{}) {
        return nil
    }
    return animation
}

// Report whether the current selection can be placed in Favorites.
animation_favorite_eligible :: #force_inline proc(
    ji: ^bridgemodel.Euclid_Julia_Interface) -> bool {
    return animation_favorite_target(ji) != nil
}

// Anchor transport controls bottom-left and eligible Favorites bottom-right.
animation_control_layout_slots :: proc(
    world_rect: geometry.Rectangle,
    favorite_visible: bool) -> Animation_Control_Slots {
    panel_width := theme.ANIMATION_CONTROL_PADDING * 2 +
        theme.ANIMATION_CONTROL_BUTTON_SIZE * 2 + theme.ANIMATION_CONTROL_BUTTON_GAP
    panel_height :=
        theme.ANIMATION_CONTROL_PADDING * 2 + theme.ANIMATION_CONTROL_BUTTON_SIZE
    panel := geometry.Rectangle{
        world_rect.x + theme.ANIMATION_CONTROL_EDGE_INSET,
        world_rect.y + world_rect.height -
            theme.ANIMATION_CONTROL_EDGE_INSET - panel_height,
        panel_width,
        panel_height,
    }
    button_y := panel.y + theme.ANIMATION_CONTROL_PADDING
    refresh := geometry.Rectangle{panel.x + theme.ANIMATION_CONTROL_PADDING, button_y,
        theme.ANIMATION_CONTROL_BUTTON_SIZE, theme.ANIMATION_CONTROL_BUTTON_SIZE}
    pause := refresh
    pause.x += theme.ANIMATION_CONTROL_BUTTON_SIZE + theme.ANIMATION_CONTROL_BUTTON_GAP
    favorite_panel := geometry.Rectangle{}
    favorite := geometry.Rectangle{}
    if favorite_visible {
        favorite_panel = {world_rect.x + world_rect.width -
            theme.ANIMATION_CONTROL_EDGE_INSET - panel_height,
            panel.y, panel_height, panel_height}
        favorite = {favorite_panel.x + theme.ANIMATION_CONTROL_PADDING,
            button_y, theme.ANIMATION_CONTROL_BUTTON_SIZE,
            theme.ANIMATION_CONTROL_BUTTON_SIZE}
    }
    return {panel = panel, favorite_panel = favorite_panel,
        refresh = refresh, pause = pause, favorite = favorite}
}

// Return the animation-control identity under one screen-space point.
animation_control_hit_test :: proc(
    world_rect: geometry.Rectangle,
    phase: capturemodel.Gif_Capture_Phase,
    favorite_visible: bool,
    point: geometry.Vector2) -> (int, bool) {
    if !animation_controls_visible(phase) {
        return 0, false
    }
    slots := animation_control_layout_slots(world_rect, favorite_visible)
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.refresh), point) {
        return ANIMATION_REFRESH_BUTTON_ID, true
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.pause), point) {
        return ANIMATION_PAUSE_BUTTON_ID, true
    }
    if favorite_visible && geometry.rectangle_contains(
        geometry.Rectangle(slots.favorite), point) {
        return ANIMATION_FAVORITE_BUTTON_ID, true
    }
    return 0, false
}

// Tessellate a clockwise rounded boundary for a non-overlapping triangle fan.
animation_control_hover_geometry :: proc(
    rectangle: geometry.Rectangle) -> Animation_Control_Hover_Geometry {
    radius := min(rectangle.width, rectangle.height) * 0.22
    shape := Animation_Control_Hover_Geometry{
        center = {rectangle.x + rectangle.width * 0.5,
            rectangle.y + rectangle.height * 0.5},
        radius = radius,
    }
    corners := [4]geometry.Vector2{
        {rectangle.x + radius, rectangle.y + radius},
        {rectangle.x + rectangle.width - radius, rectangle.y + radius},
        {rectangle.x + rectangle.width - radius,
            rectangle.y + rectangle.height - radius},
        {rectangle.x + radius, rectangle.y + rectangle.height - radius},
    }
    for center, corner in corners {
        for step in 0..=ANIMATION_CONTROL_CORNER_SEGMENTS {
            angle := math.PI + f64(corner) * math.PI * 0.5 +
                f64(step) * math.PI / (2 * ANIMATION_CONTROL_CORNER_SEGMENTS)
            index := corner * (ANIMATION_CONTROL_CORNER_SEGMENTS + 1) + step
            shape.boundary[index] = center + geometry.Vector2{
                radius * f32(math.cos(angle)), radius * f32(math.sin(angle))}
        }
    }
    return shape
}

// Report whether one widget identity belongs to the animation overlay.
animation_control_id :: #force_inline proc(id: int) -> bool {
    return id == ANIMATION_REFRESH_BUTTON_ID || id == ANIMATION_PAUSE_BUTTON_ID ||
        id == ANIMATION_FAVORITE_BUTTON_ID
}

// Build shared icon-button parameters for one animation control.
animation_control_button_params :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    descriptor: Animation_Control_Descriptor,
    mouse_input: input.Input_Frame,
    clip: geometry.Rectangle) -> uiwidgets.Icon_Button_Params {
    states := viewmodel.Ui_Node_State{.Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.toggle {
        states += {.Checked}
    }
    return {
        id = descriptor.id,
        rect = descriptor.rect,
        icon_id = descriptor.icon_id,
        toggle = descriptor.toggle,
        mouse = mouse_input,
        interaction_space_rect = descriptor.rect,
        interaction_enabled = true,
        inset_scale = theme.ANIMATION_CONTROL_ICON_SCALE,
        semantics = {
            publish = true,
            focus = runtime^.semantic_focus,
            id = uisemantics.semantic_control_id(.Animation_Control, descriptor.id),
            role = .Button,
            states = states,
            region = .Animation_Overlay,
            traversal_order = descriptor.order,
            clip_bounds = geometry.Rectangle(clip),
            label = descriptor.label,
        },
    }
}

// Resolve one animation-control button and offer its label as the tooltip text.
//
// A pointer press dismisses the control's tooltip until the pointer leaves it.
prepare_animation_control_button :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    descriptor: Animation_Control_Descriptor,
    mouse_input: input.Input_Frame,
    clip: geometry.Rectangle) -> uiwidgets.Icon_Button_Result {
    result := uiwidgets.update_icon_button(
        animation_control_button_params(runtime, descriptor, mouse_input, clip),
        &runtime^.ui_press_owner)
    owner := uisemantics.semantic_control_id(.Animation_Control, descriptor.id)
    if result.pressed || result.clicked {
        uioverlay.tooltip_dismiss(&runtime^.tooltip, owner)
    }
    uioverlay.tooltip_offer(&runtime^.tooltip, {
        owner = owner,
        source = uioverlay.tooltip_control_source(runtime, owner, descriptor.id),
        anchor = descriptor.rect,
        text = descriptor.label,
    })
    return result
}

// Find one existing Favorites placement for the selected canonical animation.
animation_favorite_entry :: proc(
    set: ^collections.Set,
    animation_id: uuid.Identifier) -> (uuid.Identifier, bool) {
    if set == nil || animation_id == (uuid.Identifier{}) ||
        set^.entry_count < 0 || set^.entry_count > len(set^.entries) {
        return {}, false
    }
    for entry in set^.entries[:set^.entry_count] {
        if entry.collection_id == collections.FAVORITES_COLLECTION_ID &&
            entry.animation_id == animation_id {
            return entry.id, true
        }
    }
    return {}, false
}

// Generate a collision-checked random identity for one new placement.
animation_favorite_new_entry_id :: proc(
    set: ^collections.Set) -> (uuid.Identifier, bool) {
    if !crypto.HAS_RAND_BYTES {
        return {}, false
    }
    for _ in 0..<4 {
        candidate: uuid.Identifier
        {
            context.random_generator = crypto.random_generator()
            candidate = uuid.generate_v4()
        }
        if candidate != (uuid.Identifier{}) &&
            collections.find_entry(set, candidate) < 0 {
            return candidate, true
        }
    }
    return {}, false
}

// Prepare the Favorites control only for a canonical eligible selection.
prepare_animation_favorite_control :: proc(
    state: ^core.Euclid_General_State,
    target: ^bridgemodel.Euclid_Julia_Animation_Interface,
    slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame) ->
    (uiwidgets.Icon_Button_Result, bool) {
    if target == nil {
        return {}, false
    }
    _, active := animation_favorite_entry(
        &state^.preferences_runtime.collections_state, target^.stable_id)
    label_id := contentdata.Content_Message_Id.Animation_Add_Favorite
    if active {
        label_id = .Animation_Remove_Favorite
    }
    result := prepare_animation_control_button(&state^.ui_runtime,
        {ANIMATION_FAVORITE_BUTTON_ID, slots.favorite, .Star, true,
            viewmessages.shell_message(state, label_id), 2},
        mouse_input, slots.favorite_panel)
    return result, active
}

// Prepare the always-visible refresh and pause animation controls.
prepare_animation_transport_controls :: proc(
    state: ^core.Euclid_General_State,
    slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame) ->
    (uiwidgets.Icon_Button_Result, uiwidgets.Icon_Button_Result) {
    runtime := &state^.ui_runtime
    pause_icon := uiwidgets.Icon_Button_Id.Play if runtime^.simulation_paused else .Pause
    pause_label := viewmessages.shell_message(state, .Animation_Pause)
    if runtime^.simulation_paused {
        pause_label = viewmessages.shell_message(state, .Animation_Resume)
    }
    refresh := prepare_animation_control_button(runtime,
        {ANIMATION_REFRESH_BUTTON_ID, slots.refresh, .Refresh, false,
            viewmessages.shell_message(state, .Animation_Restart), 0},
        mouse_input, slots.panel)
    pause := prepare_animation_control_button(runtime,
        {ANIMATION_PAUSE_BUTTON_ID, slots.pause, pause_icon,
            runtime^.simulation_paused, pause_label, 1},
        mouse_input, slots.panel)
    return refresh, pause
}

// Toggle membership through the existing accepted-edit and ordered-save flow.
toggle_animation_favorite :: proc(
    state: ^core.Euclid_General_State,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) -> (bool, bool) {
    if state == nil || animation == nil ||
        animation^.node_kind != .Animation {
        return false, false
    }
    set := &state^.preferences_runtime.collections_state
    if collections.validate(set) != .None {
        log.error("animation_favorite_toggle_invalid_collection_state")
        return false, false
    }
    entry_id, active := animation_favorite_entry(set, animation^.stable_id)
    mutation := collections.Mutation{animation_id = animation^.stable_id}
    if active {
        mutation.kind = .Remove_Favorite
        mutation.entry_id = entry_id
    } else {
        mutation.kind = .Add_Favorite
        new_entry_id, found := animation_favorite_new_entry_id(set)
        if !found {
            log.error("animation_favorite_identity_unavailable")
            return false, false
        }
        mutation.entry_id = new_entry_id
    }
    result := viewpreferences.settings_save_collection_mutation(state, mutation)
    if result != .None {
        log.errorf("animation_favorite_toggle_rejected error=%v", result)
        return active, false
    }
    return !active, true
}

// Resolve animation-control interaction and commit its actions before simulation.
prepare_animation_controls :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: input.Input_Frame) -> Animation_Control_Preparation {
    ui_runtime := &state^.ui_runtime
    if !animation_controls_visible(state^.gif_capture_status.gif_capture_phase) {
        return {}
    }
    favorite_target := animation_favorite_target(state^.julia_interface)
    favorite_visible := favorite_target != nil
    slots := animation_control_layout_slots(
        geometry.Rectangle(ui_runtime^.ui_regions.world_rect), favorite_visible)
    refresh, pause := prepare_animation_transport_controls(
        state, slots, mouse_input)
    favorite, favorite_active := prepare_animation_favorite_control(
        state, favorite_target, slots, mouse_input)
    hit := Animation_Control_Hit{
        refresh.action.activated,
        pause.action.activated,
    }
    apply_animation_control_hit(state, hit)
    if favorite.action.activated {
        if updated, accepted := toggle_animation_favorite(state, favorite_target);
            accepted {
            favorite_active = updated
        }
    }
    return {
        visible = true, slots = slots, refresh = refresh, pause = pause,
        favorite_visible = favorite_visible, favorite_active = favorite_active,
        favorite = favorite,
    }
}

// Apply reset and pause requests to their display-owned animation state.
apply_animation_control_hit :: proc(
    state: ^core.Euclid_General_State,
    hit: Animation_Control_Hit) {
    ui_runtime := &state^.ui_runtime
    if hit.refresh_requested {
        cancel_gif_capture_if_paused_mid_capture(state, ui_runtime)
        ui_runtime^.simulation_paused = false
        state^.julia_interface^.pending_animation_reset = true
    }
    if hit.toggle_pause_requested {
        ui_runtime^.simulation_paused = !ui_runtime^.simulation_paused
    }
}

// Cancel an in-flight GIF capture when refresh interrupts a paused capture.
cancel_gif_capture_if_paused_mid_capture :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if !ui_runtime^.simulation_paused {
        return
    }
    phase := state^.gif_capture_status.gif_capture_phase
    if phase == .Armed || phase == .Recording || phase == .Finalizing {
        viewcapture.cancel_gif_capture_with_note(state,
            viewmessages.shell_message(state, .Gif_Cancelled_During_Pause))
    }
}

// draw_encoded_refresh_glyph encodes the two-arrow refresh symbol.
draw_encoded_refresh_glyph :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle,
    draw_color: color.Color_RGBA8) {
    center := geometry.Vector2{rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5}
    radius := min(rectangle.width, rectangle.height) * 0.34
    starts := [2]f32{math.PI / 3.0, math.PI * (4.0 / 3.0)}
    ends := [2]f32{math.PI * (10.0 / 9.0), math.PI * (19.0 / 9.0)}
    for arc_index in 0..<2 {
        previous := center +
            geometry.Vector2{
                radius * f32(math.cos(f64(starts[arc_index]))),
                radius * f32(math.sin(f64(starts[arc_index]))),
            }
        for segment in 1..=10 {
            angle := starts[arc_index] +
                (ends[arc_index] - starts[arc_index]) * f32(segment) / 10
            current := center + geometry.Vector2{radius * f32(math.cos(f64(angle))),
                radius * f32(math.sin(f64(angle)))}
            _ = native.draw_encoder_line(encoder, previous, current, 1.6, draw_color)
            previous = current
        }
        radial := geometry.Vector2{f32(math.cos(f64(ends[arc_index]))),
            f32(math.sin(f64(ends[arc_index])))}
        tangent := geometry.Vector2{-radial.y, radial.x}
        head_base := previous - tangent * (radius * 0.32)
        head_wing := radial * (radius * 0.24)
        _ = native.draw_encoder_line(
            encoder, head_base + head_wing, previous, 1.6, draw_color)
        _ = native.draw_encoder_line(
            encoder, head_base - head_wing, previous, 1.6, draw_color)
    }
}

// draw_encoded_control_glyph encodes one refresh, pause, or play symbol.
draw_encoded_control_glyph :: proc(
    encoder: ^native.Draw_Encoder, icon: uiwidgets.Icon_Button_Id,
    rectangle: geometry.Rectangle, draw_color: color.Color_RGBA8,
    favorite_active := false) {
    if icon == .Star {
        draw_encoded_favorite_star(encoder, rectangle, draw_color, favorite_active)
        return
    }
    if icon == .Refresh {
        draw_encoded_refresh_glyph(encoder, rectangle, draw_color)
        return
    }
    if icon == .Pause {
        width := max(f32(2), rectangle.width * 0.18)
        gap := max(f32(2), rectangle.width * 0.14)
        left := rectangle.x + (rectangle.width - width * 2 - gap) * 0.5
        top := rectangle.y + rectangle.height * 0.24
        height := rectangle.height * 0.52
        _ = native.draw_encoder_rectangle(encoder, {left, top, width, height}, draw_color)
        _ = native.draw_encoder_rectangle(
            encoder, {left + width + gap, top, width, height}, draw_color)
        return
    }
    if icon == .Play {
        _ = native.draw_encoder_triangle(encoder,
            {rectangle.x + rectangle.width * 0.34, rectangle.y + rectangle.height * 0.24},
            {rectangle.x + rectangle.width * 0.34, rectangle.y + rectangle.height * 0.76},
            {rectangle.x + rectangle.width * 0.72, rectangle.y + rectangle.height * 0.5},
            draw_color)
    }
}

// Draw one outlined or filled five-point Favorites star.
draw_encoded_favorite_star :: proc(
    encoder: ^native.Draw_Encoder,
    rectangle: geometry.Rectangle,
    outline_color: color.Color_RGBA8,
    active: bool) {
    center := geometry.Vector2{
        rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5,
    }
    outer_radius := min(rectangle.width, rectangle.height) * 0.38
    inner_radius := outer_radius * 0.44
    vertices: [10]geometry.Vector2
    for index in 0..<len(vertices) {
        angle := -math.PI * 0.5 + math.PI * f64(index) / 5
        radius := outer_radius
        if index % 2 != 0 {
            radius = inner_radius
        }
        vertices[index] = center + geometry.Vector2{
            radius * f32(math.cos(angle)), radius * f32(math.sin(angle))}
    }
    if active {
        for index in 0..<len(vertices) {
            next := (index + 1) % len(vertices)
            _ = native.draw_encoder_triangle(
                encoder, center, vertices[index], vertices[next],
                theme.ANIMATION_FAVORITE_COLOR)
        }
        return
    }
    line_width := max(f32(1), min(rectangle.width, rectangle.height) * 0.055)
    for index in 0..<len(vertices) {
        next := (index + 1) % len(vertices)
        _ = native.draw_encoder_line(
            encoder, vertices[index], vertices[next], line_width, outline_color)
    }
}

// Encode one atomic rounded fill; disjoint fan triangles keep alpha uniform.
draw_encoded_animation_control_hover :: proc(
    encoder: ^native.Draw_Encoder,
    rectangle: geometry.Rectangle,
    draw_color: color.Color_RGBA8) {
    shape := animation_control_hover_geometry(rectangle)
    if shape.radius <= 0 {
        return
    }
    positions: [ANIMATION_CONTROL_HOVER_POINTS + 1]geometry.Vector2
    indices: [ANIMATION_CONTROL_HOVER_POINTS * 3]u32
    positions[0] = shape.center
    for point, index in shape.boundary {
        positions[index + 1] = point
        indices[index * 3] = 0
        indices[index * 3 + 1] = u32(index + 1)
        indices[index * 3 + 2] = u32((index + 1) % len(shape.boundary) + 1)
    }
    _ = native.draw_encoder_commit(
        encoder, positions[:], indices[:], draw_color, {pipeline = .Colored})
}

// Draw the animation-control backing state below its existing glyph.
draw_encoded_animation_control_backing :: proc(
    encoder: ^native.Draw_Encoder,
    rectangle: geometry.Rectangle,
    hovered, pressed: bool,
    toggle_active: bool) -> color.Color_RGBA8 {
    draw_color := theme.UI_TEXT_COLOR
    if hovered {
        highlight := theme.UI_TEXT_COLOR
        highlight.a = 24
        draw_encoded_animation_control_hover(encoder, rectangle, highlight)
    }
    if pressed || toggle_active {
        _ = native.draw_encoder_rectangle(encoder, rectangle, theme.UI_BORDER_COLOR)
        draw_color = worldmodel.BACKGROUND_COLOR
    }
    return draw_color
}

// Draw matching background and border chrome for either animation-control group.
draw_encoded_animation_control_panel :: proc(
    encoder: ^native.Draw_Encoder, panel: geometry.Rectangle) {
    _ = native.draw_encoder_rectangle(encoder, panel, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder, panel, 1, theme.UI_BORDER_COLOR)
}

// draw_encoded_animation_controls encodes the prepared font-independent overlay.
draw_encoded_animation_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Animation_Control_Preparation) {
    if !prepared.visible {
        return
    }
    draw_encoded_animation_control_panel(encoder, prepared.slots.panel)
    results := [2]uiwidgets.Icon_Button_Result{prepared.refresh, prepared.pause}
    icons := [2]uiwidgets.Icon_Button_Id{.Refresh,
        state^.ui_runtime.simulation_paused ? .Play : .Pause}
    slots := [2]geometry.Rectangle{prepared.slots.refresh, prepared.slots.pause}
    for index in 0..<2 {
        toggle_active := index == 1 && state^.ui_runtime.simulation_paused
        draw_color := draw_encoded_animation_control_backing(
            encoder, slots[index], results[index].hovered,
            results[index].pressed, toggle_active)
        draw_encoded_control_glyph(
            encoder, icons[index], results[index].icon_drawn_rect, draw_color)
    }
    if prepared.favorite_visible {
        draw_encoded_animation_control_panel(encoder, prepared.slots.favorite_panel)
        _ = draw_encoded_animation_control_backing(
            encoder, prepared.slots.favorite, prepared.favorite.hovered,
            prepared.favorite.pressed, false)
        draw_encoded_control_glyph(
            encoder, .Star, prepared.favorite.icon_drawn_rect,
            theme.UI_TEXT_COLOR, prepared.favorite_active)
    }
}