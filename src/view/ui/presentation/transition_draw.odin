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
}

// presentation_draw_effects reveals new content and renders pane-clipped dust.
presentation_draw_effects :: proc(
    encoder: ^native.Draw_Encoder, dust: ^uidust.Ui_Dust_System,
    viewport: geometry.Rectangle, dust_atlas: rawptr) {
    if encoder == nil || dust == nil || viewport.width <= 0 ||
        viewport.height <= 0 || !native.draw_encoder_push_scissor(encoder, viewport) {
        return
    }
    presentation_draw_fade_mask(encoder, dust, viewport)
    presentation_draw_reveal_mask(encoder, dust, viewport)
    presentation_draw_dust(encoder, dust, dust_atlas)
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
    encoder: ^native.Draw_Encoder, dust: ^uidust.Ui_Dust_System,
    dust_atlas: rawptr) {
    if dust_atlas == nil || dust^.particle_count + dust^.arrival_count == 0 {
        return
    }
    staging := native.draw_encoder_dust_staging(encoder)
    count := 0
    for index in 0..<dust^.particle_count {
        alpha := uidust.ui_dust_particle_alpha(dust, index)
        if alpha <= 0 || count >= len(staging) {
            continue
        }
        staging[count] = presentation_dust_instance(
            {dust^.particles.pos_x[index], dust^.particles.pos_y[index]},
            dust^.particles.size[index], dust^.particles.color[index], alpha,
            dust^.particles.dust_sprite_index[index])
        count += 1
    }
    for index in 0..<dust^.arrival_count {
        alpha := uidust.ui_dust_arrival_alpha(dust, index)
        if alpha <= 0 || count >= len(staging) {
            continue
        }
        staging[count] = presentation_dust_instance(
            uidust.ui_dust_arrival_position(dust, index),
            dust^.arrivals.size[index], dust^.arrivals.color[index], alpha,
            dust^.arrivals.dust_sprite_index[index])
        count += 1
    }
    _ = native.draw_encoder_commit_dust(encoder, count, dust_atlas)
}

// presentation_dust_instance converts one pane fragment into a dust atlas instance.
presentation_dust_instance :: #force_inline proc(
    center: geometry.Vector2, size: f32, tint: color.Color_RGBA8, alpha: f32,
    sprite_index: u8) -> native.Dust_Instance {
    return {
        center_diameter = {center.x, center.y, max(size * 2, 1)},
        color = {f32(tint.r) / 255, f32(tint.g) / 255, f32(tint.b) / 255, alpha},
        sprite_index = f32(sprite_index),
    }
}
