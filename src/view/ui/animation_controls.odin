package ui

import viewmodel "../model"
import native "../native"

import "../../core"
import color "../../core/color"
import geometry "../../core/geometry"
import view_core "../core"

import "core:math"

ANIMATION_REFRESH_BUTTON_ID :: 2101
ANIMATION_PAUSE_BUTTON_ID :: 2102

// Fixed board-relative geometry for the animation controls.
Animation_Control_Slots :: struct {
    panel: geometry.Rectangle,
    refresh: geometry.Rectangle,
    pause: geometry.Rectangle,
}

// Prepared interaction state for the world animation controls.
Animation_Control_Preparation :: struct {
    visible: bool,
    slots: Animation_Control_Slots,
    refresh: Icon_Button_Result,
    pause: Icon_Button_Result,
}

// Actions emitted by one prepared animation-control frame.
Animation_Control_Hit :: struct {
    refresh_requested: bool,
    toggle_pause_requested: bool,
}

// Report whether animation controls should be presented and interactive.
animation_controls_visible :: #force_inline proc(
    phase: viewmodel.Gif_Capture_Phase) -> bool {
    return phase != .Recording
}

// Place animation controls against the bottom-left edge of the current world.
animation_control_layout_slots :: proc(
    world_rect: geometry.Rectangle) -> Animation_Control_Slots {
    panel_width := ANIMATION_CONTROL_PADDING * 2 +
        ANIMATION_CONTROL_BUTTON_SIZE * 2 + ANIMATION_CONTROL_BUTTON_GAP
    panel_height := ANIMATION_CONTROL_PADDING * 2 + ANIMATION_CONTROL_BUTTON_SIZE
    panel := geometry.Rectangle{
        world_rect.x + ANIMATION_CONTROL_EDGE_INSET,
        world_rect.y + world_rect.height - ANIMATION_CONTROL_EDGE_INSET - panel_height,
        panel_width,
        panel_height,
    }
    button_y := panel.y + ANIMATION_CONTROL_PADDING
    refresh := geometry.Rectangle{panel.x + ANIMATION_CONTROL_PADDING, button_y,
        ANIMATION_CONTROL_BUTTON_SIZE, ANIMATION_CONTROL_BUTTON_SIZE}
    pause := refresh
    pause.x += ANIMATION_CONTROL_BUTTON_SIZE + ANIMATION_CONTROL_BUTTON_GAP
    return {panel = panel, refresh = refresh, pause = pause}
}

// Return the animation-control identity under one screen-space point.
animation_control_hit_test :: proc(
    world_rect: geometry.Rectangle,
    phase: viewmodel.Gif_Capture_Phase,
    point: geometry.Vector2) -> (int, bool) {
    if !animation_controls_visible(phase) {
        return 0, false
    }
    slots := animation_control_layout_slots(world_rect)
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.refresh), point) {
        return ANIMATION_REFRESH_BUTTON_ID, true
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.pause), point) {
        return ANIMATION_PAUSE_BUTTON_ID, true
    }
    return 0, false
}

// Report whether one widget identity belongs to the animation overlay.
animation_control_id :: #force_inline proc(id: int) -> bool {
    return id == ANIMATION_REFRESH_BUTTON_ID || id == ANIMATION_PAUSE_BUTTON_ID
}

// Build shared icon-button parameters for one animation control.
animation_control_button_params :: #force_inline proc(
    id: int,
    rect: geometry.Rectangle,
    icon_id: Icon_Button_Id,
    toggle: bool,
    mouse_input: Input_Frame) -> Icon_Button_Params {
    return {
        id = id,
        rect = rect,
        icon_id = icon_id,
        toggle = toggle,
        mouse = mouse_input,
        interaction_space_rect = rect,
        interaction_enabled = true,
        inset_scale = ANIMATION_CONTROL_ICON_SCALE,
    }
}

// Resolve animation-control interaction and commit its actions before simulation.
prepare_animation_controls :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: Input_Frame) -> Animation_Control_Preparation {
    ui_runtime := &state^.ui_runtime
    if !animation_controls_visible(ui_runtime^.gif_capture_phase) {
        return {}
    }
    slots := animation_control_layout_slots(
        geometry.Rectangle(ui_runtime^.ui_regions.world_rect))
    pause_icon := ui_runtime^.simulation_paused ? Icon_Button_Id.Play : .Pause
    refresh := update_icon_button(animation_control_button_params(
        ANIMATION_REFRESH_BUTTON_ID, slots.refresh, .Refresh, false,
        mouse_input), &ui_runtime^.ui_press_owner)
    pause := update_icon_button(animation_control_button_params(
        ANIMATION_PAUSE_BUTTON_ID, slots.pause, pause_icon,
        ui_runtime^.simulation_paused, mouse_input),
        &ui_runtime^.ui_press_owner)
    hit := Animation_Control_Hit{refresh.clicked, pause.clicked}
    apply_animation_control_hit(state, hit)
    return {visible = true, slots = slots, refresh = refresh, pause = pause}
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
    phase := ui_runtime^.gif_capture_phase
    if phase == .Armed || phase == .Recording || phase == .Finalizing {
        view_core.cancel_gif_capture_with_note(state,
            "Canceled: refresh during pause interrupts GIF capture.")
    }
}

// draw_encoded_refresh_glyph encodes the two-arrow refresh symbol.
draw_encoded_refresh_glyph :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle,
    draw_color: color.Color_RGBA8) {
    center := geometry.Vector2{rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5}
    radius := min(rectangle.width, rectangle.height) * 0.34
    starts := [2]f32{math.PI * (2.0 / 9.0), math.PI * (11.0 / 9.0)}
    ends := [2]f32{math.PI * (10.0 / 9.0), math.PI * (19.0 / 9.0)}
    for arc_index in 0..<2 {
        previous := center +
            geometry.Vector2{
                radius * f32(math.cos(f64(starts[arc_index]))),
                radius * f32(math.sin(f64(starts[arc_index])))
            }
        for segment in 1..=10 {
            angle := starts[arc_index] +
                (ends[arc_index] - starts[arc_index]) * f32(segment) / 10
            current := center + geometry.Vector2{radius * f32(math.cos(f64(angle))),
                radius * f32(math.sin(f64(angle)))}
            _ = native.draw_encoder_line(encoder, previous, current, 1.6, draw_color)
            previous = current
        }
    }
}

// draw_encoded_control_glyph encodes one refresh, pause, or play symbol.
draw_encoded_control_glyph :: proc(
    encoder: ^native.Draw_Encoder, icon: Icon_Button_Id,
    rectangle: geometry.Rectangle, draw_color: color.Color_RGBA8) {
    if icon == .Refresh {
        draw_encoded_refresh_glyph(encoder, rectangle, draw_color);
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

// draw_encoded_animation_controls encodes the prepared font-independent overlay.
draw_encoded_animation_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Animation_Control_Preparation) {
    if !prepared.visible {return}
    panel := prepared.slots.panel
    _ = native.draw_encoder_rectangle(encoder, panel, UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder, panel, 1, UI_BORDER_COLOR)
    results := [2]Icon_Button_Result{prepared.refresh, prepared.pause}
    icons := [2]Icon_Button_Id{.Refresh,
        state^.ui_runtime.simulation_paused ? .Play : .Pause}
    slots := [2]geometry.Rectangle{prepared.slots.refresh, prepared.slots.pause}
    for index in 0..<2 {
        draw_color := UI_TEXT_COLOR
        if results[index].pressed || (index == 1 && state^.ui_runtime.simulation_paused) {
            _ = native.draw_encoder_rectangle(
                encoder, slots[index], UI_BORDER_COLOR)
            draw_color = BACKGROUND_COLOR
        }
        draw_encoded_control_glyph(
            encoder, icons[index], results[index].icon_drawn_rect, draw_color)
    }
}