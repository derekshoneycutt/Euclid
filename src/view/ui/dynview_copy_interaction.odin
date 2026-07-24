package ui

import "../../core"

import "core:strings"

import rl "vendor:raylib"

COPY_ICON_HOVER_SCALE_ADD :: f32(0.08)
COPY_ICON_PRESS_SCALE_SUB :: f32(0.16)
COPY_ICON_HOVER_SPEED :: f32(14.0)
COPY_ICON_PRESS_RISE_SPEED :: f32(32.0)
COPY_ICON_PRESS_FALL_SPEED :: f32(24.0)
COPY_ICON_CLICK_LINGER_SECONDS :: f32(0.1)

copy_icon_clamp01 :: #force_inline proc(v: f32) -> f32 {
    return max(0.0, min(1.0, v))
}

copy_icon_approach :: #force_inline proc(current, target, speed, dt: f32) -> f32 {
    t := copy_icon_clamp01(speed * dt)
    return current + (target - current) * t
}

copy_icon_scaled_rect :: #force_inline proc(rect: rl.Rectangle, scale: f32) -> rl.Rectangle {
    use_scale := max(0.4, scale)
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5
    width := rect.width * use_scale
    height := rect.height * use_scale

    return rl.Rectangle{
        cx - width * 0.5,
        cy - height * 0.5,
        width,
        height,
    }
}

copy_icon_darken :: #force_inline proc(color: rl.Color, amount: f32) -> rl.Color {
    t := copy_icon_clamp01(amount)
    factor := 1.0 - (0.45 * t)
    return rl.Color{
        u8(f32(color.r) * factor),
        u8(f32(color.g) * factor),
        u8(f32(color.b) * factor),
        color.a,
    }
}

//   Draw soft hover backgrounds for copy-enabled dynview blocks.
draw_dynview_copy_hover_backgrounds :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
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
copy_icon_reset_animation_state :: proc(runtime: ^core.Ui_Dynview_Runtime) {
    runtime^.copy_icon_hover_active = false
    runtime^.copy_icon_press_active = false
    runtime^.copy_icon_linger_active = false
    runtime^.copy_icon_hover_t = 0
    runtime^.copy_icon_press_t = 0
    runtime^.copy_icon_linger_remaining = 0
}

//   Return the first copy-icon target under the cursor, or -1 when none match.
copy_icon_find_hovered_index :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
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
    runtime: ^core.Ui_Dynview_Runtime,
    cache: ^core.Ui_Dynview_Compile_Cache,
    hovered_index: int) {

    if hovered_index >= 0 {
        runtime^.copy_icon_hover_active = true
        runtime^.copy_icon_hover_block_id = cache^.copy_hit_targets[hovered_index].block_id
        return
    }

    runtime^.copy_icon_hover_active = false
}

//   Start press feedback when left-click begins on a copy-icon target.
copy_icon_begin_press_if_hovered :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    cache: ^core.Ui_Dynview_Compile_Cache,
    hovered_index: int) {

    if !rl.IsMouseButtonPressed(.LEFT) || hovered_index < 0 {
        return
    }

    block_id := cache^.copy_hit_targets[hovered_index].block_id
    runtime^.copy_icon_press_active = true
    runtime^.copy_icon_press_block_id = block_id
    runtime^.copy_icon_linger_active = false
    runtime^.copy_icon_linger_remaining = 0
}

//   Advance press-release lifecycle, including short dark linger after release.
copy_icon_update_press_and_linger :: proc(runtime: ^core.Ui_Dynview_Runtime, dt: f32) {
    if runtime^.copy_icon_press_active && !rl.IsMouseButtonDown(.LEFT) {
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
copy_icon_update_transition_values :: proc(runtime: ^core.Ui_Dynview_Runtime, dt: f32) {
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
copy_icon_linger_t :: #force_inline proc(runtime: ^core.Ui_Dynview_Runtime, is_linger_target: bool) -> f32 {
    if !is_linger_target || COPY_ICON_CLICK_LINGER_SECONDS <= 0 {
        return 0
    }

    return copy_icon_clamp01(runtime^.copy_icon_linger_remaining / COPY_ICON_CLICK_LINGER_SECONDS)
}

//   Draw one copy icon with hover and click feedback, returning click hit state.
copy_icon_draw_target :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    target: core.Ui_Dynview_Copy_Hit_Target,
    mouse: rl.Vector2) -> bool {

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
    scale := 1.0 + COPY_ICON_HOVER_SCALE_ADD * hover_t - COPY_ICON_PRESS_SCALE_SUB * press_visual
    draw_rect := copy_icon_scaled_rect(target.rect, scale)

    icon_color := UI_TEXT_COLOR
    if press_visual > 0 {
        icon_color = copy_icon_darken(icon_color, press_visual)
    }

    draw_copy_icon(draw_rect, icon_color)
    return hovered_icon && rl.IsMouseButtonPressed(.LEFT)
}

//   Resolve per-frame copy-icon hover/press ownership and animation transitions.
copy_icon_update_runtime_state :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    cache: ^core.Ui_Dynview_Compile_Cache,
    mouse: rl.Vector2,
    dt: f32) {

    hovered_index := copy_icon_find_hovered_index(cache, mouse)
    copy_icon_update_hover_state(runtime, cache, hovered_index)
    copy_icon_begin_press_if_hovered(runtime, cache, hovered_index)
    copy_icon_update_press_and_linger(runtime, dt)
    copy_icon_update_transition_values(runtime, dt)
}

//   Draw per-block copy icons and return whether one was clicked.
draw_dynview_copy_icons :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    mouse: rl.Vector2) -> bool {

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
    copy_icon_update_runtime_state(runtime, cache, mouse, dt)

    clicked_index := -1
    for i in 0..<cache^.copy_hit_target_count {
        if copy_icon_draw_target(runtime, cache^.copy_hit_targets[i], mouse) {
            clicked_index = i
        }
    }

    if clicked_index < 0 {
        return false
    }

    payload := dynview_copy_target_payload(runtime, clicked_index)
    if len(payload) <= 0 {
        return false
    }

    rl.SetClipboardText(strings.clone_to_cstring(payload, context.temp_allocator))
    return true
}
