package view_core

import "../../core"

import "core:strings"

import rl "vendor:raylib"

COPY_ICON_HOVER_SCALE_ADD :: 0.08
COPY_ICON_PRESS_SCALE_SUB :: 0.16
COPY_ICON_HOVER_SPEED :: 14.0
COPY_ICON_PRESS_RISE_SPEED :: 32.0
COPY_ICON_PRESS_FALL_SPEED :: 24.0
COPY_ICON_CLICK_LINGER_SECONDS :: 0.1

//   Move one copy-icon transition value toward its target at a bounded rate.
copy_icon_approach :: #force_inline proc(current, target, speed, dt: f32) -> f32 {
    t := clamp(speed * dt, 0.0, 1.0)
    return current + (target - current) * t
}

//   Draw soft hover backgrounds for copy-enabled dynview blocks.
draw_copy_hover_backgrounds :: proc(
    runtime: ^core.Dynview_System,
    mouse: rl.Vector2) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if cache^.copy_hit_target_count <= 0 {
        return
    }

    hover_bg := rl.Color{UI_BORDER_COLOR.r, UI_BORDER_COLOR.g, UI_BORDER_COLOR.b, 28}
    for i in 0..<cache^.copy_hit_target_count {
        target := cache^.copy_hit_targets[i]
        hovered_block := rl.CheckCollisionPointRec(mouse, target.hover_rect)
        hovered_icon := rl.CheckCollisionPointRec(mouse, target.rect)
        if !hovered_block && !hovered_icon {
            continue
        }

        rl.DrawRectangleRec(target.hover_rect, hover_bg)
    }
}

//   Reset all transient copy-icon animation state for frames without targets.
copy_icon_reset_animation_state :: proc(runtime: ^core.Dynview_System) {
    runtime^.copy_icon_hover_active = false
    runtime^.copy_icon_press_active = false
    runtime^.copy_icon_linger_active = false
    runtime^.copy_icon_hover_t = 0
    runtime^.copy_icon_press_t = 0
    runtime^.copy_icon_linger_remaining = 0
}

//   Return the first copy-icon target under the cursor, or -1 when none match.
copy_icon_find_hovered_index :: proc(
    cache: ^core.Dynview_Compile_Cache,
    mouse: rl.Vector2) -> int {

    for i in 0..<cache^.copy_hit_target_count {
        if rl.CheckCollisionPointRec(mouse, cache^.copy_hit_targets[i].rect) {
            return i
        }
    }

    return -1
}

//   Update runtime hover ownership to the currently hovered copy target.
copy_icon_update_hover_state :: proc(
    runtime: ^core.Dynview_System,
    cache: ^core.Dynview_Compile_Cache,
    hovered_index: int) {

    if hovered_index >= 0 {
        runtime^.copy_icon_hover_active = true
        runtime^.copy_icon_hover_block_id =
            cache^.copy_hit_targets[hovered_index].block_id
        return
    }

    runtime^.copy_icon_hover_active = false
}

//   Start press feedback when left-click begins on a copy-icon target.
copy_icon_begin_press_if_hovered :: proc(
    runtime: ^core.Dynview_System,
    cache: ^core.Dynview_Compile_Cache,
    hovered_index: int,
    mouse_input: Mouse_Input_State) {

    if !mouse_input.left_pressed || hovered_index < 0 {
        return
    }

    block_id := cache^.copy_hit_targets[hovered_index].block_id
    runtime^.copy_icon_press_active = true
    runtime^.copy_icon_press_block_id = block_id
    runtime^.copy_icon_linger_active = false
    runtime^.copy_icon_linger_remaining = 0
}

//   Advance press-release lifecycle, including short dark linger after release.
copy_icon_update_press_and_linger :: proc(
    runtime: ^core.Dynview_System,
    mouse_input: Mouse_Input_State,
    dt: f32) {

    if runtime^.copy_icon_press_active && !mouse_input.left_down {
        runtime^.copy_icon_press_active = false
        runtime^.copy_icon_linger_active = true
        runtime^.copy_icon_linger_block_id = runtime^.copy_icon_press_block_id
        runtime^.copy_icon_linger_remaining = COPY_ICON_CLICK_LINGER_SECONDS
    }

    if !runtime^.copy_icon_linger_active {
        return
    }

    runtime^.copy_icon_linger_remaining -= dt
    if runtime^.copy_icon_linger_remaining <= 0 {
        runtime^.copy_icon_linger_remaining = 0
        runtime^.copy_icon_linger_active = false
    }
}

//   Move hover and press transition values toward their current targets.
copy_icon_update_transition_values :: proc(runtime: ^core.Dynview_System, dt: f32) {
    hover_target: f32 = 0
    if runtime^.copy_icon_hover_active {
        hover_target = 1
    }

    runtime^.copy_icon_hover_t = copy_icon_approach(
        runtime^.copy_icon_hover_t,
        hover_target,
        COPY_ICON_HOVER_SPEED,
        dt)

    press_target: f32 = 0
    if runtime^.copy_icon_press_active {
        press_target = 1
    }

    press_speed: f32 = COPY_ICON_PRESS_FALL_SPEED
    if press_target > runtime^.copy_icon_press_t {
        press_speed = COPY_ICON_PRESS_RISE_SPEED
    }

    runtime^.copy_icon_press_t = copy_icon_approach(
        runtime^.copy_icon_press_t,
        press_target,
        press_speed,
        dt)
}

//   Compute normalized linger intensity for a specific copy-icon target.
copy_icon_linger_t :: #force_inline proc(
    runtime: ^core.Dynview_System, is_linger_target: bool) -> f32 {
    if !is_linger_target || COPY_ICON_CLICK_LINGER_SECONDS <= 0 {
        return 0
    }

    return clamp(
        runtime^.copy_icon_linger_remaining / COPY_ICON_CLICK_LINGER_SECONDS, 0.0, 1.0)
}

//   Resolve the foreground color for one copy icon press transition.
copy_icon_color :: #force_inline proc(press_t: f32) -> rl.Color {
    color := UI_TEXT_COLOR
    if press_t <= 0 {
        return color
    }
    factor := 1.0 - 0.45 * press_t
    return {u8(f32(BACKGROUND_COLOR.r) * factor),
        u8(f32(BACKGROUND_COLOR.g) * factor),
        u8(f32(BACKGROUND_COLOR.b) * factor), BACKGROUND_COLOR.a}
}

//   Draw a copy icon button using shared icon primitives with hover/press feedback.
draw_copy_icon_button :: proc(
    rect: rl.Rectangle,
    hover_t: f32,
    press_t: f32,
    hovered_icon: bool,
    mouse_input: Mouse_Input_State) -> bool {

    slot_rect := rect
    if slot_rect.width <= 0 || slot_rect.height <= 0 {
        return false
    }

    use_hover_t := clamp(hover_t, 0.0, 1.0)
    use_press_t := clamp(press_t, 0.0, 1.0)

    if use_press_t > 0 {
        rl.DrawRectangleRec(slot_rect, UI_BORDER_COLOR)
    }

    scale := 1.0 + COPY_ICON_HOVER_SCALE_ADD * use_hover_t -
        COPY_ICON_PRESS_SCALE_SUB * use_press_t
    cx := slot_rect.x + slot_rect.width * 0.5
    cy := slot_rect.y + slot_rect.height * 0.5
    icon_w := slot_rect.width * max(0.4, scale)
    icon_h := slot_rect.height * max(0.4, scale)
    icon_rect := rl.Rectangle{cx - icon_w * 0.5, cy - icon_h * 0.5, icon_w, icon_h}

    if use_press_t > 0 {
        icon_rect.x += 0.5
        icon_rect.y += 0.5
    }

    draw_copy_icon(icon_rect, copy_icon_color(use_press_t))
    return hovered_icon && mouse_input.left_released
}

//   Draw one copy icon with hover and click feedback, returning click hit state.
copy_icon_draw_target :: proc(
    runtime: ^core.Dynview_System,
    target: core.Dynview_Copy_Hit_Target,
    mouse_input: Mouse_Input_State) -> bool {

    mouse := mouse_input.position

    hovered_block := rl.CheckCollisionPointRec(mouse, target.hover_rect)
    hovered_icon := rl.CheckCollisionPointRec(mouse, target.rect)
    is_hover_target := runtime^.copy_icon_hover_active &&
        runtime^.copy_icon_hover_block_id == target.block_id
    is_press_target := runtime^.copy_icon_press_active &&
        runtime^.copy_icon_press_block_id == target.block_id
    is_linger_target := runtime^.copy_icon_linger_active &&
        runtime^.copy_icon_linger_block_id == target.block_id

    if !hovered_block && !hovered_icon && !is_press_target && !is_linger_target {
        return false
    }

    hover_t: f32 = 0
    if is_hover_target {
        hover_t = runtime^.copy_icon_hover_t
    }

    press_t: f32 = 0
    if is_press_target {
        press_t = runtime^.copy_icon_press_t
    }

    press_visual := max(press_t, copy_icon_linger_t(runtime, is_linger_target))

    return draw_copy_icon_button(
        target.rect, hover_t, press_visual, hovered_icon, mouse_input)
}

//   Resolve per-frame copy-icon hover/press ownership and animation transitions.
copy_icon_update_runtime_state :: proc(
    runtime: ^core.Dynview_System,
    cache: ^core.Dynview_Compile_Cache,
    mouse_input: Mouse_Input_State,
    dt: f32) {

    mouse := mouse_input.position

    hovered_index := copy_icon_find_hovered_index(cache, mouse)
    copy_icon_update_hover_state(runtime, cache, hovered_index)
    copy_icon_begin_press_if_hovered(runtime, cache, hovered_index, mouse_input)
    copy_icon_update_press_and_linger(runtime, mouse_input, dt)
    copy_icon_update_transition_values(runtime, dt)
}

//   Return compiled copy payload string for one hit target index.
copy_target_payload :: proc(runtime: ^core.Dynview_System, target_index: int) -> string {
    if runtime == nil {
        return ""
    }

    cache := &runtime^.compile_cache
    if target_index < 0 || target_index >= cache^.copy_hit_target_count {
        return ""
    }

    target := cache^.copy_hit_targets[target_index]
    if target.payload_offset < 0 || target.payload_len <= 0 {
        return ""
    }
    if target.payload_offset + target.payload_len > cache^.compiled_copy_payload_len {
        return ""
    }

    return string(cache^.compiled_copy_payload[
        target.payload_offset:target.payload_offset + target.payload_len])
}

//   Draw per-block copy icons and return whether one was clicked.
draw_copy_icons :: proc(
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) -> bool {

    if runtime == nil {
        return false
    }

    _ = panel

    cache := &runtime^.compile_cache
    if cache^.copy_hit_target_count <= 0 {
        copy_icon_reset_animation_state(runtime)
        return false
    }

    dt := min(0.05, max(0.0, rl.GetFrameTime()))
    copy_icon_update_runtime_state(runtime, cache, mouse_input, dt)

    clicked_index := -1
    for i in 0..<cache^.copy_hit_target_count {
        if copy_icon_draw_target(runtime, cache^.copy_hit_targets[i], mouse_input) {
            clicked_index = i
        }
    }

    if clicked_index < 0 {
        return false
    }

    payload := copy_target_payload(runtime, clicked_index)
    if len(payload) <= 0 {
        return false
    }

    rl.SetClipboardText(strings.clone_to_cstring(payload, context.temp_allocator))
    return true
}
