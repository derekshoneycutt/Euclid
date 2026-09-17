package ui

import viewmodel "../model"

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

ANIMATION_REFRESH_BUTTON_ID :: 2101
ANIMATION_PAUSE_BUTTON_ID :: 2102

// Fixed board-relative geometry for the animation controls.
Animation_Control_Slots :: struct {
    panel: rl.Rectangle,
    refresh: rl.Rectangle,
    pause: rl.Rectangle,
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
    world_rect: rl.Rectangle) -> Animation_Control_Slots {
    panel_width := ANIMATION_CONTROL_PADDING * 2 +
        ANIMATION_CONTROL_BUTTON_SIZE * 2 + ANIMATION_CONTROL_BUTTON_GAP
    panel_height := ANIMATION_CONTROL_PADDING * 2 + ANIMATION_CONTROL_BUTTON_SIZE
    panel := rl.Rectangle{
        world_rect.x + ANIMATION_CONTROL_EDGE_INSET,
        world_rect.y + world_rect.height - ANIMATION_CONTROL_EDGE_INSET - panel_height,
        panel_width,
        panel_height,
    }
    button_y := panel.y + ANIMATION_CONTROL_PADDING
    refresh := rl.Rectangle{panel.x + ANIMATION_CONTROL_PADDING, button_y,
        ANIMATION_CONTROL_BUTTON_SIZE, ANIMATION_CONTROL_BUTTON_SIZE}
    pause := refresh
    pause.x += ANIMATION_CONTROL_BUTTON_SIZE + ANIMATION_CONTROL_BUTTON_GAP
    return {panel = panel, refresh = refresh, pause = pause}
}

// Return the animation-control identity under one screen-space point.
animation_control_hit_test :: proc(
    world_rect: rl.Rectangle,
    phase: viewmodel.Gif_Capture_Phase,
    point: rl.Vector2) -> (int, bool) {
    if !animation_controls_visible(phase) {
        return 0, false
    }
    slots := animation_control_layout_slots(world_rect)
    if rl.CheckCollisionPointRec(point, slots.refresh) {
        return ANIMATION_REFRESH_BUTTON_ID, true
    }
    if rl.CheckCollisionPointRec(point, slots.pause) {
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
    rect: rl.Rectangle,
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
        ui_raylib_rectangle(ui_runtime^.ui_regions.world_rect))
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

// Draw prepared animation controls over the lower-left corner of the world.
draw_animation_controls :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: Input_Frame,
    prepared: Animation_Control_Preparation) {
    if !prepared.visible {
        return
    }
    ui_runtime := &state^.ui_runtime
    _ = draw_container(prepared.slots.panel, .Grey)
    pause_icon := ui_runtime^.simulation_paused ? Icon_Button_Id.Play : .Pause
    draw_icon_button_prepared(animation_control_button_params(
        ANIMATION_REFRESH_BUTTON_ID, prepared.slots.refresh, .Refresh, false,
        mouse_input), prepared.refresh)
    draw_icon_button_prepared(animation_control_button_params(
        ANIMATION_PAUSE_BUTTON_ID, prepared.slots.pause, pause_icon,
        ui_runtime^.simulation_paused, mouse_input),
        prepared.pause)
}