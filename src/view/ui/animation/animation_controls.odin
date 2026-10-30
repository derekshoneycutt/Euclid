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
import uioverlay "../overlay"
import bridgemodel "../../../bridge/model"
import collections "../../../collections"
import uuid "core:encoding/uuid"
import crypto "core:crypto"
import viewpreferences "../../preferences"
import log "core:log"
import contentdata "../../../core/content"
import animationmodel "../../../core/animation"

ANIMATION_REFRESH_BUTTON_ID :: 2101
ANIMATION_PAUSE_BUTTON_ID :: 2102
ANIMATION_FAVORITE_BUTTON_ID :: 2103
ANIMATION_MEMBERSHIP_BUTTON_ID :: uioverlay.MEMBERSHIP_CONTROL_ID
ANIMATION_VISIBILITY_BUTTON_ID :: 2105
ANIMATION_SPEED_BUTTON_ID :: 2106

// Fixed board-relative geometry for the animation controls.
Animation_Control_Slots :: struct {
    panel: geometry.Rectangle,
    favorite_panel: geometry.Rectangle,
    refresh: geometry.Rectangle,
    pause: geometry.Rectangle,
    favorite: geometry.Rectangle,
    membership: geometry.Rectangle,
    eye: geometry.Rectangle,
    speed: geometry.Rectangle,
}

// Prepared interaction state for the world animation controls.
Animation_Control_Preparation :: struct {
    visible: bool,
    overlay_visible: bool,
    eye: uiwidgets.Icon_Button_Result,
    speed: uiwidgets.Icon_Button_Result,
    speed_locked: bool,
    slots: Animation_Control_Slots,
    refresh: uiwidgets.Icon_Button_Result,
    pause: uiwidgets.Icon_Button_Result,
    favorite_visible: bool,
    favorite_active: bool,
    favorite: uiwidgets.Icon_Button_Result,
    membership_visible: bool,
    membership: uiwidgets.Icon_Button_Result,
}

// Actions emitted by one prepared animation-control frame.
Animation_Control_Hit :: struct {
    refresh_requested: bool,
    toggle_pause_requested: bool,
    cycle_speed_requested: bool,
}

// Overlay eligibility and session visibility shared by pointer routing.
Animation_Control_Visibility :: struct {
    favorite: bool,
    membership: bool,
    hidden: bool,
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
    order: u32,
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
    favorite_visible: bool, membership_visible := false,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) ->
    Animation_Control_Slots {
    scale := theme.ui_control_size_scale(control_size_percent)
    padding := theme.ANIMATION_CONTROL_PADDING * scale
    button_size := theme.ANIMATION_CONTROL_BUTTON_SIZE * scale
    button_gap := theme.ANIMATION_CONTROL_BUTTON_GAP * scale
    edge_inset := theme.ANIMATION_CONTROL_EDGE_INSET * scale
    panel_width := padding * 2 + button_size * 3 + button_gap * 2
    panel_height :=
        padding * 2 + button_size
    panel: geometry.Rectangle = {
        world_rect.x + edge_inset,
        world_rect.y + world_rect.height -
            edge_inset - panel_height,
        panel_width,
        panel_height,
    }
    button_y := panel.y + padding
    refresh: geometry.Rectangle = {panel.x + padding, button_y,
        button_size, button_size}
    pause := refresh
    pause.x += button_size + button_gap
    result: Animation_Control_Slots = {
        panel = panel,
        refresh = refresh,
        pause = pause,
    }
    result.speed = pause
    result.speed.x +=
        button_size + button_gap
    result.eye = {
        world_rect.x + world_rect.width - edge_inset - button_size,
        world_rect.y + edge_inset,
        button_size, button_size,
    }
    if favorite_visible {
        animation_collection_layout_slots(
            world_rect, membership_visible, scale, &result)
    }
    return result
}

// Reserve one or two bottom-right slots without changing legacy star-only geometry.
animation_collection_layout_slots :: proc(
    world: geometry.Rectangle, membership: bool, scale: f32,
    slots: ^Animation_Control_Slots) {
    height := slots.panel.height
    width := height
    extra := (theme.ANIMATION_CONTROL_BUTTON_SIZE +
        theme.ANIMATION_CONTROL_BUTTON_GAP) * scale
    if membership {
        width += extra
    }
    slots.favorite_panel = {
        world.x + world.width - theme.ANIMATION_CONTROL_EDGE_INSET * scale - width,
        slots.panel.y,
        width, height,
    }
    slots.favorite = {slots.favorite_panel.x + theme.ANIMATION_CONTROL_PADDING,
        slots.panel.y + theme.ANIMATION_CONTROL_PADDING,
        theme.ANIMATION_CONTROL_BUTTON_SIZE * scale,
        theme.ANIMATION_CONTROL_BUTTON_SIZE * scale}
    if membership {
        slots.membership = slots.favorite
        slots.membership.x += extra
    }
}

// Return the animation-control identity under one screen-space point.
animation_control_hit_test :: proc(
    world_rect: geometry.Rectangle,
    phase: capturemodel.Gif_Capture_Phase,
    point: geometry.Vector2,
    visibility: Animation_Control_Visibility,
    control_size_percent := theme.CONTROL_SIZE_DEFAULT_PERCENT) -> (int, bool) {
    if !animation_controls_visible(phase) {
        return 0, false
    }
    slots := animation_control_layout_slots(
        world_rect, visibility.favorite, visibility.membership,
        control_size_percent)
    if geometry.rectangle_contains(slots.eye, point) {
        return ANIMATION_VISIBILITY_BUTTON_ID, true
    }
    return animation_control_hit_test_remaining(slots, point, visibility)
}

// Resolve visible non-eye controls after visibility and layout have been established.
animation_control_hit_test_remaining :: proc(
    slots: Animation_Control_Slots,
    point: geometry.Vector2,
    visibility: Animation_Control_Visibility) -> (int, bool) {
    if visibility.hidden {
        return 0, false
    }
    if geometry.rectangle_contains(slots.speed, point) {
        return ANIMATION_SPEED_BUTTON_ID, true
    }
    if visibility.membership && geometry.rectangle_contains(slots.membership, point) {
        return ANIMATION_MEMBERSHIP_BUTTON_ID, true
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.refresh), point) {
        return ANIMATION_REFRESH_BUTTON_ID, true
    }
    if geometry.rectangle_contains(
        geometry.Rectangle(slots.pause), point) {
        return ANIMATION_PAUSE_BUTTON_ID, true
    }
    if visibility.favorite && geometry.rectangle_contains(
        geometry.Rectangle(slots.favorite), point) {
        return ANIMATION_FAVORITE_BUTTON_ID, true
    }
    return 0, false
}

// Tessellate a clockwise rounded boundary for a non-overlapping triangle fan.
animation_control_hover_geometry :: proc(
    rectangle: geometry.Rectangle) -> Animation_Control_Hover_Geometry {
    radius := min(rectangle.width, rectangle.height) * 0.22
    shape: Animation_Control_Hover_Geometry = {
        center = {rectangle.x + rectangle.width * 0.5,
            rectangle.y + rectangle.height * 0.5},
        radius = radius,
    }
    corners: [4]geometry.Vector2 = {
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
        id == ANIMATION_FAVORITE_BUTTON_ID || id == ANIMATION_MEMBERSHIP_BUTTON_ID ||
        id == ANIMATION_VISIBILITY_BUTTON_ID || id == ANIMATION_SPEED_BUTTON_ID
}

// Build shared icon-button parameters for one animation control.
animation_control_button_params :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    descriptor: Animation_Control_Descriptor,
    mouse_input: input.Input_Frame,
    clip: geometry.Rectangle, enabled := true) -> uiwidgets.Icon_Button_Params {
    states: viewmodel.Ui_Node_State = {.Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.toggle {
        states += {.Checked}
    }
    if !enabled {
        states -= {.Enabled}
    }
    return {
        id = descriptor.id,
        rect = descriptor.rect,
        icon_id = descriptor.icon_id,
        toggle = descriptor.toggle,
        mouse = mouse_input,
        interaction_space_rect = descriptor.rect,
        interaction_enabled = enabled,
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
    clip: geometry.Rectangle, enabled := true) -> uiwidgets.Icon_Button_Result {
    result := uiwidgets.update_icon_button(
        animation_control_button_params(runtime, descriptor, mouse_input, clip, enabled),
        &runtime^.input.press_owner)
    owner := uisemantics.semantic_control_id(.Animation_Control, descriptor.id)
    if result.pressed || result.action.activated {
        uioverlay.tooltip_dismiss(&runtime^.tooltip, owner)
    }
    uioverlay.tooltip_offer(&runtime^.tooltip, {
        owner = owner,
        source = uioverlay.tooltip_control_source(
            &runtime^.input, runtime^.semantic_focus, owner, descriptor.id),
        anchor = descriptor.rect,
        prefer_above = true,
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
            viewmessages.shell_message(state, label_id), 3},
        mouse_input, slots.favorite_panel)
    return result, active
}

// Prepare refresh and pause while the animation overlay is expanded.
prepare_animation_transport_controls :: proc(
    state: ^core.Euclid_General_State,
    slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame) ->
    (uiwidgets.Icon_Button_Result, uiwidgets.Icon_Button_Result) {
    runtime := &state^.ui_runtime
    pause_icon :=
        uiwidgets.Icon_Button_Id.Play if runtime^.playback.simulation_paused else .Pause
    pause_label := viewmessages.shell_message(state, .Animation_Pause)
    if runtime^.playback.simulation_paused {
        pause_label = viewmessages.shell_message(state, .Animation_Resume)
    }
    refresh := prepare_animation_control_button(runtime,
        {ANIMATION_REFRESH_BUTTON_ID, slots.refresh, .Refresh, false,
            viewmessages.shell_message(state, .Animation_Restart), 0},
        mouse_input, slots.panel)
    pause := prepare_animation_control_button(runtime,
        {ANIMATION_PAUSE_BUTTON_ID, slots.pause, pause_icon,
            runtime^.playback.simulation_paused, pause_label, 1},
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
    mutation, mutation_valid := animation_favorite_make_mutation(
        set, animation^.stable_id, entry_id, active)
    if !mutation_valid {
        return active, false
    }
    result := viewpreferences.settings_save_collection_mutation(
        state, mutation, animation^.name)
    if result != .None {
        log.errorf("animation_favorite_toggle_rejected error=%v", result)
        return active, false
    }
    return !active, true
}

// Build an identity-qualified mutation for the current favorite membership.
animation_favorite_make_mutation :: proc(
    set: ^collections.Set,
    animation_id: uuid.Identifier,
    entry_id: uuid.Identifier,
    active: bool) -> (collections.Mutation, bool) {
    mutation: collections.Mutation = {
        animation_id = animation_id,
    }
    if active {
        mutation.kind = .Remove_Favorite
        mutation.entry_id = entry_id
        identity, identity_error :=
            collections.placement_identity_for_entry(set, entry_id)
        if identity_error != .None {
            log.errorf("animation_favorite_identity_rejected policy=%v",
                identity_error)
            return {}, false
        }
        mutation.placement = identity
    } else {
        mutation.kind = .Add_Favorite
        new_entry_id, found := animation_favorite_new_entry_id(set)
        if !found {
            log.error("animation_favorite_identity_unavailable")
            return {}, false
        }
        mutation.entry_id = new_entry_id
        mutation.placement = {
            collection_id = collections.FAVORITES_COLLECTION_ID,
            entry_id = new_entry_id,
        }
    }
    return mutation, true
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
    membership_visible := favorite_visible && uioverlay.membership_available(state)
    slots := animation_control_layout_slots(
        geometry.Rectangle(ui_runtime^.layout.ui_regions.world_rect),
        favorite_visible, membership_visible,
        ui_runtime^.preferences.values.interface.control_size_percent)
    eye := prepare_animation_visibility_control(state, slots, mouse_input)
    if ui_runtime^.playback.controls_hidden {
        return {
            visible = true,
            slots = slots,
            eye = eye,
        }
    }
    prepared: Animation_Control_Preparation = {
        visible = true,
        overlay_visible = true,
        slots = slots,
        eye = eye,
        favorite_visible = favorite_visible,
        membership_visible = membership_visible,
    }
    prepare_animation_overlay(state, mouse_input, favorite_target, &prepared)
    return prepared
}

// Prepare expanded controls and commit their transport and collection actions.
prepare_animation_overlay :: proc(
    state: ^core.Euclid_General_State, mouse_input: input.Input_Frame,
    favorite_target: ^bridgemodel.Euclid_Julia_Animation_Interface,
    prepared: ^Animation_Control_Preparation) {
    slots := prepared.slots
    refresh, pause := prepare_animation_transport_controls(
        state, slots, mouse_input)
    speed, speed_locked := prepare_animation_speed_control(state, slots, mouse_input)
    favorite, favorite_active := prepare_animation_favorite_control(
        state, favorite_target, slots, mouse_input)
    membership := prepare_animation_membership_control(
        state, slots, mouse_input, prepared.membership_visible)
    hit: Animation_Control_Hit = {
        refresh.action.activated,
        pause.action.activated,
        speed.action.activated,
    }
    apply_animation_control_hit(state, hit)
    if favorite.action.activated {
        if updated, accepted := toggle_animation_favorite(state, favorite_target);
            accepted {
            favorite_active = updated
        }
    }
    prepared.refresh = refresh
    prepared.pause = pause
    prepared.speed = speed
    prepared.speed_locked = speed_locked
    prepared.favorite_active = favorite_active
    prepared.favorite = favorite
    prepared.membership = membership
}

// Toggle overlay visibility without changing playback or collection membership.
prepare_animation_visibility_control :: proc(
    state: ^core.Euclid_General_State, slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame) -> uiwidgets.Icon_Button_Result {
    label := contentdata.Content_Message_Id.Animation_Hide_Controls
    if state.ui_runtime.playback.controls_hidden {
        label = .Animation_Show_Controls
    }
    result := prepare_animation_control_button(&state.ui_runtime, {
        ANIMATION_VISIBILITY_BUTTON_ID, slots.eye, .None, false,
        viewmessages.shell_message(state, label), 5,
    }, mouse_input, slots.eye)
    if result.action.activated {
        state.ui_runtime.playback.controls_hidden =
            !state.ui_runtime.playback.controls_hidden
        if state.ui_runtime.playback.controls_hidden {
            animation_controls_retire_overlay(state)
        }
    }
    return result
}

// Retire hidden popup, press and tooltip owners before their controls are prepared.
animation_controls_retire_overlay :: proc(state: ^core.Euclid_General_State) {
    runtime := &state.ui_runtime
    focus := runtime.semantic_focus
    transfer := focus != nil &&
        (focus.logical_focus.domain == .Animation_Control ||
            focus.logical_focus.domain == .Collection_Membership)
    uioverlay.membership_close(state, false)
    owner := &runtime.input.press_owner
    if owner.active && animation_control_id(owner.id) {
        owner^ = {}
    }
    if runtime.tooltip.shown.owner.domain == .Animation_Control {
        runtime.tooltip.visible = false
        uioverlay.tooltip_dismiss(&runtime.tooltip, runtime.tooltip.shown.owner)
    }
    if transfer {
        focus.logical_focus = uisemantics.semantic_control_id(
            .Animation_Control, ANIMATION_VISIBILITY_BUTTON_ID)
    }
}

// Open a selection-bound destination popup from the star-adjacent ellipsis.
prepare_animation_membership_control :: proc(
    state: ^core.Euclid_General_State, slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame,
    visible: bool) -> uiwidgets.Icon_Button_Result {
    if !visible {
        return {}
    }
    result := prepare_animation_control_button(&state.ui_runtime, {
            ANIMATION_MEMBERSHIP_BUTTON_ID, slots.membership, .None, false,
            viewmessages.shell_message(state, .Animation_Add_Collections), 4,
        },
        mouse_input, slots.favorite_panel)
    if result.action.activated {
        _ = uioverlay.membership_open(state, slots.membership)
    }
    return result
}

// Publish current rate and disable all speed activation routes during GIF capture.
prepare_animation_speed_control :: proc(
    state: ^core.Euclid_General_State, slots: Animation_Control_Slots,
    mouse_input: input.Input_Frame) -> (uiwidgets.Icon_Button_Result, bool) {
    locked := capturemodel.gif_capture_locks_playback_rate(
        state.gif_capture_status.gif_capture_phase,
        state.gif_capture_status.save_gif_requested)
    label := contentdata.Content_Message_Id.Animation_Speed_Normal
    if locked {
        label = .Animation_Speed_Capture
    } else {
        switch state.ui_runtime.playback.rate {
        case .Normal:
        case .Double:
            label = .Animation_Speed_Double
        case .Quadruple:
            label = .Animation_Speed_Quadruple
        }
    }
    result := prepare_animation_control_button(&state.ui_runtime, {
        ANIMATION_SPEED_BUTTON_ID, slots.speed, .None, false,
        viewmessages.shell_message(state, label), 2,
    }, mouse_input, slots.panel, !locked)
    return result, locked
}

// Apply reset and pause requests to their display-owned animation state.
apply_animation_control_hit :: proc(
    state: ^core.Euclid_General_State,
    hit: Animation_Control_Hit) {
    ui_runtime := &state^.ui_runtime
    if hit.refresh_requested {
        cancel_gif_capture_if_paused_mid_capture(state, ui_runtime)
        ui_runtime^.playback.simulation_paused = false
        state^.julia_interface^.pending_animation_reset = true
    }
    if hit.toggle_pause_requested {
        ui_runtime^.playback.simulation_paused = !ui_runtime^.playback.simulation_paused
    }
    if hit.cycle_speed_requested {
        if capturemodel.gif_capture_locks_playback_rate(
            state.gif_capture_status.gif_capture_phase,
            state.gif_capture_status.save_gif_requested) {
            log.warn("animation_speed_change_rejected_during_capture")
        } else {
            ui_runtime.playback.rate =
                animationmodel.playback_rate_next(ui_runtime.playback.rate)
        }
    }
}

// Cancel an in-flight GIF capture when refresh interrupts a paused capture.
cancel_gif_capture_if_paused_mid_capture :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if !ui_runtime^.playback.simulation_paused {
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
    center: geometry.Vector2 = {rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5}
    radius := min(rectangle.width, rectangle.height) * 0.34
    starts: [2]f32 = {math.PI / 3.0, math.PI * (4.0 / 3.0)}
    ends: [2]f32 = {math.PI * (10.0 / 9.0), math.PI * (19.0 / 9.0)}
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
        radial: geometry.Vector2 = {f32(math.cos(f64(ends[arc_index]))),
            f32(math.sin(f64(ends[arc_index])))}
        tangent: geometry.Vector2 = {-radial.y, radial.x}
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
    center: geometry.Vector2 = {
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
        encoder, positions[:], indices[:], draw_color, {
            pipeline = .Colored,
        })
}

// Draw the animation-control backing state below its existing glyph.
draw_encoded_animation_control_backing :: proc(
    encoder: ^native.Draw_Encoder,
    rectangle: geometry.Rectangle,
    hovered, pressed: bool,
    toggle_active: bool) -> color.Color_RGBA8 {
    draw_color := theme.draw_color(encoder, .Text)
    if hovered {
        draw_encoded_animation_control_hover(encoder, rectangle, theme.UI_HOVER_COLOR)
    }
    if pressed || toggle_active {
        _ = native.draw_encoder_rectangle(
            encoder, rectangle, theme.draw_color(encoder, .Selection_Background))
        draw_color = theme.draw_color(encoder, .Selection_Text)
    }
    return draw_color
}

// Draw matching background and border chrome for either animation-control group.
draw_encoded_animation_control_panel :: proc(
    encoder: ^native.Draw_Encoder, panel: geometry.Rectangle,
    scale := f32(1)) {
    _ = uiwidgets.surface_shadow_draw(encoder, panel, .Medium)
    _ = native.draw_encoder_rectangle(encoder, panel, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, panel, scale, theme.UI_BORDER_COLOR)
}

// Encode the prepared overlay with font-independent transport and visibility glyphs.
draw_encoded_animation_controls :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Animation_Control_Preparation) {
    if !prepared.visible {
        return
    }
    control_scale := theme.ui_control_size_scale(
        state.ui_runtime.preferences.values.interface.control_size_percent)
    draw_encoded_animation_eye(encoder, prepared.eye,
        state.ui_runtime.playback.controls_hidden)
    if !prepared.overlay_visible {
        return
    }
    draw_encoded_animation_transport(state, encoder, prepared)
    if prepared.favorite_visible {
        draw_encoded_animation_control_panel(
            encoder, prepared.slots.favorite_panel, control_scale)
        _ = draw_encoded_animation_control_backing(
            encoder, prepared.slots.favorite, prepared.favorite.hovered,
            prepared.favorite.pressed, false)
        draw_encoded_control_glyph(
            encoder, .Star, prepared.favorite.icon_drawn_rect,
            theme.draw_color(encoder, .Text), prepared.favorite_active)
    }
    if prepared.membership_visible {
        draw_encoded_membership_control(encoder, prepared)
    }
}

// Encode the transport panel and its restart, pause and speed controls.
draw_encoded_animation_transport :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Animation_Control_Preparation) {
    draw_encoded_animation_control_panel(
        encoder, prepared.slots.panel,
        theme.ui_control_size_scale(
            state^.ui_runtime.preferences.values.interface.control_size_percent))
    results: [2]uiwidgets.Icon_Button_Result = {prepared.refresh, prepared.pause}
    icons: [2]uiwidgets.Icon_Button_Id = {.Refresh,
        state^.ui_runtime.playback.simulation_paused ? .Play : .Pause}
    slots: [2]geometry.Rectangle = {prepared.slots.refresh, prepared.slots.pause}
    for index in 0..<2 {
        toggle_active := index == 1 && state^.ui_runtime.playback.simulation_paused
        draw_color := draw_encoded_animation_control_backing(
            encoder, slots[index], results[index].hovered,
            results[index].pressed, toggle_active)
        draw_encoded_control_glyph(
            encoder, icons[index], results[index].icon_drawn_rect, draw_color)
    }
    draw_encoded_animation_speed(state, encoder, prepared)
}

// Draw one compact speed button using the same slot size as restart and pause.
draw_encoded_animation_speed :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Animation_Control_Preparation) {
    rect := prepared.slots.speed
    tint := draw_encoded_animation_control_backing(encoder, rect,
        prepared.speed.hovered, prepared.speed.pressed, false)
    if prepared.speed_locked {
        tint = theme.draw_color(encoder, .Disabled_Text)
    }
    rate := capturemodel.gif_capture_playback_rate(state.ui_runtime.playback.rate,
        state.gif_capture_status.gif_capture_phase,
        state.gif_capture_status.save_gif_requested)
    draw_encoded_speed_glyph(encoder, prepared.speed.icon_drawn_rect, tint, rate,
        prepared.slots.speed.width / theme.ANIMATION_CONTROL_BUTTON_SIZE)
}

// Encode crossed-out fast-forward at normal speed, otherwise an inset circular rate badge.
draw_encoded_speed_glyph :: proc(
    encoder: ^native.Draw_Encoder, rect: geometry.Rectangle,
    tint: color.Color_RGBA8, rate: animationmodel.Playback_Rate,
    scale := f32(1)) {
    for index in 0..<2 {
        x := rect.x + rect.width*(0.12 + f32(index)*0.36)
        _ = native.draw_encoder_triangle(encoder,
            {x, rect.y + rect.height*0.20},
            {x, rect.y + rect.height*0.72},
            {x + rect.width*0.34, rect.y + rect.height*0.46}, tint)
    }
    if rate == .Normal {
        _ = native.draw_encoder_line(encoder,
            {rect.x + rect.width*0.18, rect.y + rect.height*0.12},
            {rect.x + rect.width*0.86, rect.y + rect.height*0.84}, 1.8*scale, tint)
    } else {
        draw_encoded_playback_badge(encoder, rect, tint, rate)
    }
}

// Draw a contrasting 2 or 4 inside the glyph's bottom-right circle without font residency.
draw_encoded_playback_badge :: proc(
    encoder: ^native.Draw_Encoder, rect: geometry.Rectangle,
    tint: color.Color_RGBA8, rate: animationmodel.Playback_Rate) {
    radius := min(rect.width, rect.height)*0.25
    center: geometry.Vector2 = {rect.x + rect.width*0.75, rect.y + rect.height*0.75}
    ink := theme.UI_COMPONENT_BACKGROUND_COLOR
    _ = native.draw_encoder_circle(encoder, center, radius + 1, ink)
    _ = native.draw_encoder_circle(encoder, center, radius, tint)
    points: [6]geometry.Vector2 = {
        {-0.32, -0.48}, {0.32, -0.48}, {0.32, 0},
        {-0.32, 0}, {-0.32, 0.48}, {0.32, 0.48},
    }
    if rate == .Quadruple {
        points = {{-0.32, -0.48}, {-0.32, 0}, {0.32, 0},
            {0.32, -0.48}, {0.32, 0.48}, {0.32, 0.48}}
    }
    for index in 0..<len(points)-1 {
        if points[index] != points[index + 1] {
            _ = native.draw_encoder_line(encoder, center + points[index]*radius,
                center + points[index + 1]*radius, max(f32(1), radius*0.18), ink)
        }
    }
}

// Encode a borderless eye with a diagonal slash only while controls are hidden.
draw_encoded_animation_eye :: proc(
    encoder: ^native.Draw_Encoder,
    result: uiwidgets.Icon_Button_Result, hidden: bool) {
    scale := result.control_geometry.bounds.width /
        theme.ANIMATION_CONTROL_BUTTON_SIZE
    tint := draw_encoded_animation_control_backing(encoder,
        result.control_geometry.bounds, result.hovered, result.pressed, false)
    rect := result.icon_drawn_rect
    center: geometry.Vector2 = {rect.x + rect.width*0.5, rect.y + rect.height*0.5}
    for side in 0..<2 {
        previous: geometry.Vector2 = {rect.x + rect.width*0.12, center.y}
        for step in 1..=16 {
            t := f32(step)/16
            sign := f32(-1) if side == 0 else f32(1)
            current: geometry.Vector2 = {
                rect.x + rect.width*(0.12 + 0.76*t),
                center.y + sign*rect.height*0.25*f32(math.sin(f64(t)*math.PI)),
            }
            _ = native.draw_encoder_line(encoder, previous, current, 1.6*scale, tint)
            previous = current
        }
    }
    _ = native.draw_encoder_circle(encoder, center, rect.width*0.10, tint)
    if hidden {
        _ = native.draw_encoder_line(encoder,
            {rect.x + rect.width*0.16, rect.y + rect.height*0.16},
            {rect.x + rect.width*0.84, rect.y + rect.height*0.84}, 2*scale, tint)
    }
}

// Draw a vertical ellipsis, preserving the same backing, hit geometry and focus as other controls.
draw_encoded_membership_control :: proc(
    encoder: ^native.Draw_Encoder, prepared: Animation_Control_Preparation) {
    tint := draw_encoded_animation_control_backing(encoder, prepared.slots.membership,
        prepared.membership.hovered, prepared.membership.pressed, false)
    rect := prepared.membership.icon_drawn_rect
    for index in 0..<3 {
        _ = native.draw_encoder_rectangle(encoder, {
            rect.x + rect.width*0.5 - 1.5,
            rect.y + rect.height*(0.25 + f32(index)*0.25) - 1.5,
            3, 3,
        }, tint)
    }
}