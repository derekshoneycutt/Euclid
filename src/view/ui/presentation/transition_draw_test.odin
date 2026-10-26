#+test
package uipresentation

import "core:testing"

import geometry "../../../core/geometry"
import native "../../native"
import uidust "../../../particles/ui_dust"

// Presentation_Dust_Test_Draw keeps maximum-capacity encoder storage off the stack.
Presentation_Dust_Test_Draw :: struct {
    vertices: [16]native.Draw_Vertex,
    indices: [24]u32,
    batches: [4]native.Draw_Batch,
    commands: [4]native.Draw_Command,
    instances: [uidust.UI_DUST_TOTAL_PARTICLES]native.Dust_Instance,
    draws: [2]native.Dust_Draw,
    custom: native.Draw_Custom_Storage,
    encoder: native.Draw_Encoder,
}

// Allocate one encoder with exactly the shared pane capacity and no native resources.
presentation_test_dust_draw :: proc(t: ^testing.T) -> ^Presentation_Dust_Test_Draw {
    draw := new(Presentation_Dust_Test_Draw, context.allocator)
    draw^.custom = {
        dust_instances = draw^.instances[:],
        dust_draws = draw^.draws[:],
    }
    testing.expect(t, native.draw_encoder_begin(&draw^.encoder,
        {draw^.vertices[:], draw^.indices[:], draw^.batches[:], draw^.commands[:],
            &draw^.custom},
        {5000, 100}, {5000, 100}))
    native.draw_encoder_enable_dust_instancing(&draw^.encoder, true)
    return draw
}

// Fill all phases and force hole reuse, transfer, and eviction before drawing.
presentation_test_fill_mixed_dust :: proc(
    t: ^testing.T, dust: ^uidust.Ui_Dust_System) {
    phases: [4]uidust.Ui_Dust_Phase = {
        .Airborne_Departure, .Resting_Departure, .Fresh_Arrival, .Reclaimed_Arrival}
    for index in 0..<uidust.UI_DUST_TOTAL_PARTICLES {
        _ = uidust.ui_dust_slot_emit(dust, {
            phase = phases[index % 4],
            pos_x = f32(index),
            pos_y = 50,
            target_x = f32(index),
            target_y = 50,
            life = 1,
            size = 1,
            target_size = 1,
            target_color = {20, 40, 60, 255},
            captured = true,
            captured_alpha = 1,
            color = {20, 40, 60, 255},
        })
    }
    testing.expect(t, uidust.ui_dust_slot_reassign(dust,
        {2, dust^.order[2].generation}, .Reclaimed_Arrival))
    testing.expect(t, uidust.ui_dust_slot_retire(dust,
        {5, dust^.order[5].generation}))
    _ = uidust.ui_dust_slot_emit(dust, {
        phase = .Airborne_Departure,
        pos_x = 5,
        size = 1,
        color = {20, 40, 60, 255},
    })
    _ = uidust.ui_dust_slot_emit(dust, {
        phase = .Airborne_Departure,
        pos_x = 0,
        size = 1,
        color = {20, 40, 60, 255},
    })
}

// Verify every live phase is drawn once after hole reuse, transfer, and eviction.
@(test)
presentation_effects_draw_shared_pool_without_duplicates :: proc(t: ^testing.T) {
    draw := presentation_test_dust_draw(t)
    defer free(draw, context.allocator)
    dust := new(uidust.Ui_Dust_System, context.allocator)
    defer free(dust, context.allocator)
    viewport: geometry.Rectangle = {0, 0, 5000, 100}
    uidust.ui_dust_validate_context(dust, {
        visible = true,
        viewport = viewport,
    })
    uidust.ui_dust_begin_arrival(dust, 1, .Falling_Ink)
    uidust.ui_dust_begin_formation(dust)
    dust^.incoming_elapsed = (uidust.UI_DUST_ARRIVAL_HANDOFF_START +
        uidust.UI_DUST_ARRIVAL_HANDOFF_END) / 2
    presentation_test_fill_mixed_dust(t, dust)
    presentation_draw_effects(&draw^.encoder, dust, viewport, rawptr(uintptr(1)))
    testing.expect_value(t, draw^.encoder.dust_instance_count,
        uidust.UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, draw^.encoder.dust_draw_count, 1)
    testing.expect_value(t, draw^.draws[0].scissor, native.Draw_Scissor{0, 0, 5000, 100})
    seen: [uidust.UI_DUST_TOTAL_PARTICLES]bool
    for instance in draw^.instances {
        index := int(instance.center_diameter.x)
        testing.expect(t, !seen[index])
        seen[index] = true
    }
}

// Verify outgoing and falling-ink dust share one draw clipped to the pane.
@(test)
presentation_effects_draw_clips_outgoing_and_incoming_dust :: proc(t: ^testing.T) {
    vertices: [16]native.Draw_Vertex
    indices: [24]u32
    batches: [4]native.Draw_Batch
    commands: [4]native.Draw_Command
    instances: [8]native.Dust_Instance
    draws: [2]native.Dust_Draw
    custom: native.Draw_Custom_Storage = {
        dust_instances = instances[:],
        dust_draws = draws[:],
    }
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], &custom},
        {100, 100}, {100, 100}))
    native.draw_encoder_enable_dust_instancing(&encoder, true)
    dust := new(uidust.Ui_Dust_System, context.allocator)
    defer free(dust, context.allocator)
    viewport: geometry.Rectangle = {10, 20, 50, 40}
    uidust.ui_dust_validate_context(dust, {
        visible = true,
        viewport = viewport,
    })
    uidust.ui_dust_begin_departure(dust, 1)
    testing.expect(t, uidust.ui_dust_emit(dust, {20, 30}, {1, 2, 3, 255}, 255, 1))
    uidust.ui_dust_begin_arrival(dust, 2, .Falling_Ink)
    uidust.ui_dust_begin_formation(dust)
    testing.expect(t, uidust.ui_dust_emit_arrival(
        dust, {40, 50}, {4, 5, 6, 255}, 255))
    uidust.ui_dust_advance(dust, uidust.UI_DUST_ARRIVAL_DELAY_MAX + 0.05)

    presentation_draw_effects(&encoder, dust, viewport, rawptr(uintptr(1)))

    testing.expect_value(t, encoder.dust_instance_count, 2)
    testing.expect_value(t, draws[0].count, u32(2))
    testing.expect_value(t, draws[0].scissor, native.Draw_Scissor{10, 20, 50, 40})
    testing.expect(t, instances[1].center_diameter.y < 50)
    testing.expect(t, encoder.vertex_count > 0)
}

// Count vertices emitted by one effects draw of a draw-in reveal mask.
presentation_test_reveal_vertices :: proc(
    t: ^testing.T, dust: ^uidust.Ui_Dust_System, viewport: geometry.Rectangle) -> int {
    vertices: [32]native.Draw_Vertex
    indices: [48]u32
    batches: [4]native.Draw_Batch
    commands: [4]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    presentation_draw_effects(&encoder, dust, viewport, nil)
    return encoder.vertex_count
}

// Verify draw-in covers an unstarted row, feathers its moving front, and clears.
@(test)
presentation_effects_draw_reveals_rows_behind_front :: proc(t: ^testing.T) {
    dust := new(uidust.Ui_Dust_System, context.allocator)
    defer free(dust, context.allocator)
    viewport: geometry.Rectangle = {10, 20, 50, 40}
    uidust.ui_dust_validate_context(dust, {
        visible = true,
        viewport = viewport,
    })
    uidust.ui_dust_begin_arrival(dust, 3, .Draw_In)
    uidust.ui_dust_reveal_include(dust, {20, 30})
    uidust.ui_dust_reveal_include(dust, {50, 30})
    uidust.ui_dust_begin_formation(dust)

    cover := presentation_test_reveal_vertices(t, dust, viewport)
    testing.expect(t, cover > 0)
    uidust.ui_dust_advance(dust, dust^.reveal_rows[0].sweep / 2)
    feathered := presentation_test_reveal_vertices(t, dust, viewport)
    testing.expect_value(t, feathered,
        cover * (uidust.UI_DUST_DRAW_IN_FEATHER_STEPS + 1))
    uidust.ui_dust_advance(dust, uidust.UI_DUST_DRAW_IN_DURATION)
    testing.expect_value(t, presentation_test_reveal_vertices(t, dust, viewport), 0)
}
