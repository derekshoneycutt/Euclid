package ui_dust

import geometry "../../core/geometry"
import math "core:math"
import testing "core:testing"

// Start one draw-in arrival over two separated ink lines of different widths.
ui_dust_test_reveal :: proc(system: ^Ui_Dust_System) -> bool {
    ui_dust_begin_arrival(system, 9, .Draw_In)
    for x in ([]f32{10, 55, 100}) {
        ui_dust_reveal_include(system, {x, 20})
    }
    ui_dust_reveal_include(system, {20, 60})
    ui_dust_reveal_include(system, {50, 60})
    ui_dust_begin_formation(system)
    return ui_dust_reveal_active(system)
}

// Verify ink bins merge into rows whose bands tile the viewport.
@(test)
ui_dust_reveal_rows_tile_viewport :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_reveal(system))
    testing.expect_value(t, system^.reveal_row_count, 2)
    first := system^.reveal_rows[0]
    second := system^.reveal_rows[1]
    testing.expect_value(t, first.top, f32(0))
    testing.expect_value(t, first.bottom, second.top)
    testing.expect_value(t, second.bottom, f32(200))
    testing.expect_value(t, first.left, f32(10))
    testing.expect_value(t, first.right, f32(100))
    testing.expect_value(t, second.left, f32(20))
    testing.expect(t, second.start > first.start)
    testing.expect(t, second.sweep < first.sweep)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
    testing.expect_value(t, ui_dust_arrival_budget(system), UI_DUST_DRAW_IN_ACCENT_MAX)
}

// Verify every row's front starts before its ink and finishes past it in time.
@(test)
ui_dust_reveal_front_sweeps_each_row :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_reveal(system))
    testing.expect_value(t, ui_dust_reveal_progress(system, 0), f32(0))
    testing.expect_value(t, ui_dust_reveal_front(system, 0),
        f32(10) - UI_DUST_DRAW_IN_FEATHER)
    ui_dust_advance(system, UI_DUST_DRAW_IN_DURATION)
    for index in 0..<system^.reveal_row_count {
        testing.expect_value(t, ui_dust_reveal_progress(system, index), f32(1))
    }
    testing.expect_value(t, ui_dust_reveal_front(system, 0), f32(100))
    ui_dust_advance(system, UI_DUST_DRAW_IN_ACCENT_LIFE)
    testing.expect(t, !system^.incoming_active)
    testing.expect_value(t, system^.reveal_row_count, 0)
}

// Verify accents deposit when the feather midpoint reaches their ink and expire.
@(test)
ui_dust_reveal_accents_follow_contact :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_reveal(system))
    target: geometry.Vector2 = {55, 20}
    testing.expect(t, ui_dust_emit_arrival(system, target, {20, 40, 60, 255}, 255))
    contact := system^.particles.delay[0]
    row := system^.reveal_rows[0]
    testing.expect(t, contact > row.start && contact < row.start + row.sweep)
    testing.expect_value(t, ui_dust_arrival_alpha(system, 0), f32(0))
    ui_dust_advance(system, contact)
    midpoint := ui_dust_reveal_front(system, 0) + UI_DUST_DRAW_IN_FEATHER / 2
    testing.expect(t, math.abs(midpoint - target.x) < 0.01)
    ui_dust_advance(system, UI_DUST_DRAW_IN_ACCENT_SETTLE + 0.01)
    testing.expect(t, ui_dust_arrival_alpha(system, 0) > 0)
    testing.expect_value(t, ui_dust_arrival_position(system, 0), target)
    ui_dust_advance(system, UI_DUST_DRAW_IN_ACCENT_LIFE)
    testing.expect_value(t, ui_dust_arrival_alpha(system, 0), f32(0))
}

// Verify draw-in without any ink samples degrades to the fade.
@(test)
ui_dust_reveal_without_ink_falls_back_to_fade :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    ui_dust_begin_arrival(system, 4, .Draw_In)
    ui_dust_begin_formation(system)
    testing.expect_value(t, system^.incoming_style, Ui_Dust_Arrival_Style.Fade)
    testing.expect(t, !ui_dust_reveal_active(system))
    testing.expect_value(t, ui_dust_arrival_budget(system), 0)
}
