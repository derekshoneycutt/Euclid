package uipresentation

import color "../../../core/color"
import geometry "../../../core/geometry"
import native "../../native"
import uidust "../../../particles/ui_dust"
import theme "../theme"

#assert(native.DUST_UI_INSTANCE_RESERVE >= uidust.UI_DUST_TOTAL_PARTICLES)
#assert(native.DUST_ATLAS_COLUMNS * native.DUST_ATLAS_ROWS ==
    uidust.UI_DUST_SPRITE_VARIANT_COUNT)

// Presentation_Effects_Draw_Params groups display-owned effect draw inputs.
Presentation_Effects_Draw_Params :: struct {
    dust: ^uidust.Ui_Dust_System,
    dust_atlas: rawptr,
    monochrome: bool,
    effective_contrast: bool,
}

Presentation_Dust_Instance_Params :: struct {
    center: geometry.Vector2,
    size: f32,
    tint: color.Color_RGBA8,
    alpha: f32,
    sprite_index: u8,
    ink_style: uidust.Ui_Dust_Ink,
    monochrome: bool,
    effective_contrast: bool,
}

// presentation_draw_effects reveals new content and renders pane-clipped dust.
presentation_draw_effects :: proc(
    encoder: ^native.Draw_Encoder, viewport: geometry.Rectangle,
    params: Presentation_Effects_Draw_Params) {
    if encoder == nil || params.dust == nil || viewport.width <= 0 ||
        viewport.height <= 0 || !native.draw_encoder_push_scissor(encoder, viewport) {
        return
    }
    presentation_draw_fade_mask(encoder, params.dust, viewport)
    presentation_draw_reveal_mask(encoder, params.dust, viewport)
    presentation_draw_dust(encoder, params)
    _ = native.draw_encoder_pop_scissor(encoder)
}

// presentation_draw_reveal_mask covers each unfinished draw-in row from its
// feathered front to the pane's right edge. Rows tile the viewport, so content
// without ink samples still waits for its band.
presentation_draw_reveal_mask :: proc(
    encoder: ^native.Draw_Encoder, dust: ^uidust.Ui_Dust_System,
    viewport: geometry.Rectangle) {
    if !uidust.ui_dust_reveal_active(dust) {
        return
    }
    right := viewport.x + viewport.width
    for index in 0..<dust^.reveal_row_count {
        progress := uidust.ui_dust_reveal_progress(dust, index)
        if progress >= 1 {
            continue
        }
        row := dust^.reveal_rows[index]
        cover_x := viewport.x
        if progress > 0 {
            front := uidust.ui_dust_reveal_front(dust, index)
            presentation_draw_reveal_feather(encoder, row, front)
            cover_x = front + uidust.UI_DUST_DRAW_IN_FEATHER
        }
        if cover_x < right {
            _ = native.draw_encoder_rectangle(encoder,
                {cover_x, row.top, right - cover_x, row.bottom - row.top},
                theme.UI_COMPONENT_BACKGROUND_COLOR)
        }
    }
}

// presentation_draw_reveal_feather approximates a soft front with stepped
// translucent strips whose coverage rises toward the opaque cover.
presentation_draw_reveal_feather :: proc(
    encoder: ^native.Draw_Encoder, row: uidust.Ui_Dust_Reveal_Row, front: f32) {
    step_count := uidust.UI_DUST_DRAW_IN_FEATHER_STEPS
    step_width := uidust.UI_DUST_DRAW_IN_FEATHER / f32(step_count)
    for step in 0..<step_count {
        mask_color := theme.UI_COMPONENT_BACKGROUND_COLOR
        mask_color.a = u8(255 * (step + 1) / (step_count + 1))
        _ = native.draw_encoder_rectangle(encoder,
            {front + f32(step) * step_width, row.top, step_width,
                row.bottom - row.top},
            mask_color)
    }
}

// presentation_draw_fade_mask exposes structured content over a fixed layout.
presentation_draw_fade_mask :: proc(
    encoder: ^native.Draw_Encoder, dust: ^uidust.Ui_Dust_System,
    viewport: geometry.Rectangle) {
    opacity := uidust.ui_dust_incoming_alpha(dust)
    if opacity >= 1 {
        return
    }
    mask_color := theme.UI_COMPONENT_BACKGROUND_COLOR
    mask_color.a = u8(clamp((1 - opacity) * 255, 0, 255))
    _ = native.draw_encoder_rectangle(encoder, viewport, mask_color)
}

// presentation_draw_dust stages live outgoing and incoming fragments and commits
// one atlas dust draw. The draw inherits the active pane scissor through the
// shared dust pipeline.
presentation_draw_dust :: proc(
    encoder: ^native.Draw_Encoder, params: Presentation_Effects_Draw_Params) {
    dust := params.dust
    if params.dust_atlas == nil || dust^.live_count == 0 {
        return
    }
    staging := native.draw_encoder_dust_staging(encoder)
    count := 0
    cursor := dust^.live_head
    for cursor != 0 {
        index := cursor - 1
        cursor = dust^.order[index].next
        appearance, valid := uidust.ui_dust_evaluate(
            dust, {index, dust^.order[index].generation})
        if !valid || appearance.alpha <= 0 || count >= len(staging) {
            continue
        }
        staging[count] = presentation_dust_instance(
            {
                center = appearance.position,
                size = appearance.size,
                tint = appearance.tint,
                alpha = appearance.alpha,
                sprite_index = appearance.sprite_index,
                ink_style = appearance.ink_style,
                monochrome = params.monochrome,
                effective_contrast = params.effective_contrast,
            })
        count += 1
    }
    _ = native.draw_encoder_commit_dust(encoder, count, params.dust_atlas)
}

// presentation_dust_instance converts one pane fragment into a dust atlas instance.
presentation_dust_instance :: #force_inline proc(
    params: Presentation_Dust_Instance_Params) -> native.Dust_Instance {
    resolved_tint := params.tint
    if params.monochrome && params.ink_style.authored {
        resolved_tint = params.ink_style.monochrome
        if params.effective_contrast {
            resolved_tint = params.ink_style.increased
        }
    }
    return {
        center_diameter = {
            params.center.x, params.center.y, max(params.size * 2, 1),
        },
        color = {f32(resolved_tint.r) / 255, f32(resolved_tint.g) / 255,
            f32(resolved_tint.b) / 255, params.alpha},
        sprite_index = f32(params.sprite_index),
    }
}
