package ui_dust

import testing "core:testing"

// Verify crisp opacity and forming opacity remain complementary during handoff.
@(test)
ui_dust_visibility_preserves_complementary_handoff :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_formation(system, 1, {80, 90}))
    system^.particles.delay[0] = 0
    system^.particles.duration[0] = UI_DUST_ARRIVAL_FALL_MIN
    ui_dust_advance(system,
        (UI_DUST_ARRIVAL_HANDOFF_START + UI_DUST_ARRIVAL_HANDOFF_END) / 2)
    visibility := ui_dust_crisp_visibility(system)
    crisp := ui_dust_crisp_sample_alpha(&visibility, {80, 90})
    testing.expect_value(t, crisp + ui_dust_arrival_alpha(system, 0), f32(1))
    ui_dust_begin_departure(system, 2)
    testing.expect_value(t, ui_dust_crisp_sample_alpha(&visibility, {80, 90}), crisp)
}

// Verify draw-in departure samples mirror hidden, feathered and fully revealed ink.
@(test)
ui_dust_visibility_tracks_draw_in_masks :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_reveal(system))
    visibility := ui_dust_crisp_visibility(system)
    testing.expect_value(t, ui_dust_crisp_sample_alpha(&visibility, {55, 20}), f32(0))
    ui_dust_advance(system, system^.reveal_rows[0].sweep / 2)
    visibility = ui_dust_crisp_visibility(system)
    front := visibility.fronts[0]
    testing.expect_value(t,
        ui_dust_crisp_sample_alpha(&visibility, {front-1, 20}), f32(1))
    testing.expect_value(t,
        ui_dust_crisp_sample_alpha(&visibility, {front+11, 20}), f32(0))
    alpha := ui_dust_crisp_sample_alpha(&visibility, {front+1, 20})
    testing.expect_value(t, alpha, 1 - f32(51) / 255)
    ui_dust_advance(system, UI_DUST_DRAW_IN_DURATION)
    visibility = ui_dust_crisp_visibility(system)
    testing.expect_value(t, ui_dust_crisp_sample_alpha(&visibility, {55, 20}), f32(1))
}
