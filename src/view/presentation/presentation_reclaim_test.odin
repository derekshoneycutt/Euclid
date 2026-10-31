package viewpresentation

import testing "core:testing"
import geometry "../../core/geometry"
import core "../../core"
import uidust "../../particles/ui_dust"
import viewfont "../font"
import uipresentation "../ui/presentation"

// Initialize one display-owned ink cache and valid visible reclaim viewport.
presentation_test_reclaim_init :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime) {
    testing.expect(t,
        viewfont.cache_ink_capture_init(&state^.font_cache, context.allocator))
    state^.ui_runtime.presentation.visible = true
    uidust.ui_dust_validate_context(&runtime^.dust, {
        visible = true,
        viewport = {0, 0, 200, 200},
        visual_signature = 1,
    })
}

// Verify the first-new-ink gate transfers live dust only after a valid target frame.
@(test)
presentation_reclaims_only_new_published_ink :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    testing.expect(t, uidust.ui_dust_emit(&runtime^.dust,
        {30, 40}, {80, 160, 240, 255}, 255, 1))
    presentation_test_publish_ink(state, {{10, 10}})
    uidust.ui_dust_begin_arrival(&runtime^.dust, 5, .Falling_Ink)
    runtime^.arrival_ink_serial = viewfont.cache_visible_ink_serial(&state^.font_cache)
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 200, 200},
        },
    }
    presentation_effects_update(state, runtime, 0, {
        presentation = frame,
        visual_signature = 1,
    })
    testing.expect(t, runtime^.dust.incoming_awaiting_targets)
    presentation_test_publish_ink(state, {{80, 90}, {90, 100}})
    presentation_effects_update(state, runtime, 0, {
        presentation = frame,
        visual_signature = 1,
    })
    testing.expect_value(t,
        runtime^.dust.particles.phase[0], uidust.Ui_Dust_Phase.Reclaimed_Arrival)
    testing.expect_value(t,
        runtime^.dust.particles.phase[1], uidust.Ui_Dust_Phase.Fresh_Arrival)
    testing.expect_value(t, runtime^.dust.live_count, 2)
    observed := presentation_effects_observe(runtime)
    testing.expect_value(t, observed.reclaimed_count, 1)
    testing.expect_value(t, observed.fresh_count, 1)
    testing.expect_value(t, observed.live_count, 2)
    testing.expect_value(t, observed.formation_reclaimed, 1)
    testing.expect_value(t, observed.formation_fresh, 1)
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 2)
    presentation_effects_update(state, runtime, 0.30, {
        presentation = frame,
        visual_signature = 1,
    })
    testing.expect_value(t, runtime^.dust.arrival_count, 0)
    testing.expect_value(t, uidust.ui_dust_incoming_alpha(&runtime^.dust), f32(1))
}

// Verify invalidation happens before transfer, not after sources have been claimed.
@(test)
presentation_context_change_precedes_reclamation :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    testing.expect(t, uidust.ui_dust_emit(&runtime^.dust,
        {30, 40}, {80, 160, 240, 255}, 255, 1))
    uidust.ui_dust_begin_arrival(&runtime^.dust, 5, .Falling_Ink)
    runtime^.arrival_ink_serial = viewfont.cache_visible_ink_serial(&state^.font_cache)
    presentation_test_publish_ink(state, {{80, 90}})
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = {0, 0, 100, 100},
        },
    }
    presentation_effects_update(state, runtime, 0, {
        presentation = frame,
        visual_signature = 1,
    })
    testing.expect_value(t, runtime^.dust.live_count, 0)
    testing.expect(t, !runtime^.dust.incoming_active)
    testing.expect_value(t, uidust.ui_dust_incoming_alpha(&runtime^.dust), f32(1))
}

// Verify interruption samples only revealed crisp ink, complementing released particles.
@(test)
presentation_replacement_does_not_double_masked_ink :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    uidust.ui_dust_begin_arrival(&runtime^.dust, 5, .Falling_Ink)
    uidust.ui_dust_begin_formation(&runtime^.dust)
    testing.expect(t, uidust.ui_dust_emit_arrival(&runtime^.dust,
        {80, 90}, {80, 160, 240, 255}, 255))
    uidust.ui_dust_advance(&runtime^.dust, 0.27)
    visible, _ := uidust.ui_dust_evaluate(&runtime^.dust, {0, 1})
    presentation_test_publish_ink(state, {{80, 90}})
    presentation_effects_begin_departure(state, runtime, 6)
    testing.expect_value(t, runtime^.dust.particle_count, 2)
    testing.expect_value(t, runtime^.dust.particles.pos_x[0], visible.position.x)
    alpha := uidust.ui_dust_particle_alpha(&runtime^.dust, 0) +
        uidust.ui_dust_particle_alpha(&runtime^.dust, 1)
    testing.expect(t, alpha <= 1 && alpha > 0.99)
    presentation_effects_begin_departure(state, runtime, 6)
    testing.expect_value(t, runtime^.dust.particle_count, 2)
    testing.expect_value(t,
        len(viewfont.cache_visible_ink_samples(&state^.font_cache)), 0)
}

// Verify blank snapshots cannot erase a visible arrival and hidden panes retire it.
@(test)
presentation_replacement_without_ink_preserves_forming_material :: proc(
    t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    uidust.ui_dust_begin_arrival(&runtime^.dust, 5, .Falling_Ink)
    uidust.ui_dust_begin_formation(&runtime^.dust)
    testing.expect(t, uidust.ui_dust_emit_arrival(&runtime^.dust,
        {80, 90}, {80, 160, 240, 255}, 255))
    uidust.ui_dust_advance(&runtime^.dust, 0.12)
    presentation_effects_begin_departure(state, runtime, 6)
    testing.expect_value(t,
        runtime^.dust.particles.phase[0], uidust.Ui_Dust_Phase.Airborne_Departure)
    testing.expect_value(t, runtime^.dust.live_count, 1)
    state^.ui_runtime.presentation.visible = false
    frame: uipresentation.Presentation_Preparation = {
        scroll = {
            view_rect = geometry.Rectangle{0, 0, 200, 200},
        },
    }
    presentation_effects_update(state, runtime, 0, {
        presentation = frame,
        visual_signature = 1,
    })
    testing.expect_value(t, runtime^.dust.live_count, 0)
}
