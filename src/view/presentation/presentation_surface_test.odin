#+test
package viewpresentation

import testing "core:testing"
import core "../../core"
import viewfont "../font"
import uidust "../../particles/ui_dust"
import uipresentation "../ui/presentation"
import uiterminal "../ui/terminal"

// presentation_test_surface_frame resolves surface navigation through the production updater.
presentation_test_surface_frame :: proc(
    state: ^core.Euclid_General_State, runtime: ^Presentation_Runtime,
    surface: viewfont.Font_Ink_Surface, dt: f32 = 0) {
    if surface == .Dynview {
        state^.julia_interface^.selected_animation = nil
    } else {
        state^.julia_interface^.null_animation.node_kind = .Terminal
        state^.julia_interface^.selected_animation =
            &state^.julia_interface^.null_animation
    }
    terminal: uiterminal.Terminal_Prepared_Frame = {
        available = true,
        explorer_active = surface == .History,
        scroll = {
            view_rect = {5, 5, 190, 190},
        },
        explorer = {
            bounds = {2, 2, 196, 196},
        },
    }
    frame: uipresentation.Presentation_Preparation = {
        active = true,
        scroll = {
            view_rect = {0, 0, 200, 200},
        },
    }
    presentation_effects_update(state, runtime, dt, {
        presentation = frame,
        terminal = terminal,
        visual_signature = 1,
    })
}

// Every directed surface switch reclaims only its destination's presented ink.
@(test)
presentation_surface_switches_share_reclaim_and_timing :: proc(t: ^testing.T) {
    for source in viewfont.Font_Ink_Surface {
        for destination in viewfont.Font_Ink_Surface {
            if source == destination {
                continue
            }
            fixture := presentation_test_fixture_create(t)
            state, runtime := fixture.state, fixture.presentation
            presentation_test_reclaim_init(t, state, runtime)
            presentation_test_publish_ink(state, {{30, 40}}, source)
            presentation_test_surface_frame(state, runtime, source)
            presentation_test_surface_frame(state, runtime, destination)
            testing.expect_value(t, runtime^.dust.particle_count, 1)
            testing.expect(t, runtime^.dust.incoming_awaiting_targets)
            presentation_test_publish_ink(state, {{50, 60}}, source)
            presentation_test_surface_frame(state, runtime, destination)
            testing.expect(t, runtime^.dust.incoming_awaiting_targets)
            presentation_test_publish_ink(state, {{80, 90}}, destination)
            presentation_test_surface_frame(state, runtime, destination)
            testing.expect_value(t, runtime^.dust.formation_reclaimed, 1)
            testing.expect_value(t, runtime^.dust.live_count, 1)
            presentation_test_surface_frame(state, runtime, destination, 0.30)
            testing.expect(t, !runtime^.dust.incoming_active)
            testing.expect_value(t, runtime^.dust.arrival_count, 0)
            testing.expect_value(t, uidust.ui_dust_incoming_alpha(&runtime^.dust), f32(1))
            viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
            presentation_test_fixture_destroy(fixture)
        }
    }
}

// Same-surface captures, asynchronous results, and History help never arm a new transition.
@(test)
presentation_surface_updates_do_not_replay_arrival :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    for surface in ([2]viewfont.Font_Ink_Surface{.Terminal, .History}) {
        runtime^.surface_observed = false
        presentation_test_publish_ink(state, {{30, 40}}, surface)
        presentation_test_surface_frame(state, runtime, surface)
        for _ in 0..<4 {
            presentation_test_publish_ink(state, {{50, 60}}, surface)
            presentation_test_surface_frame(state, runtime, surface, 0.05)
            testing.expect(t, !runtime^.dust.incoming_active)
            testing.expect_value(t, runtime^.dust.live_count, 0)
            testing.expect_value(t, runtime^.surface_switch_count, u64(0))
        }
    }
}

// Suppression applies at entry and when enabled during an active transfer, without replay.
@(test)
presentation_surface_motion_policies_retire_all_material :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    for policy in 0..<3 {
        presentation_test_publish_ink(state, {{30, 40}}, .Terminal)
        runtime^.surface = .Terminal
        runtime^.surface_observed = true
        presentation_test_surface_frame(state, runtime, .History)
        testing.expect(t, runtime^.dust.incoming_active)
        state^.ui_runtime.preferences.values.interface.reduce_motion = policy == 0
        state^.ui_runtime.platform_reduce_motion = policy == 1
        state^.ui_runtime.preferences.values.interface.enable_particle_effects =
            policy != 2
        presentation_test_surface_frame(state, runtime, .History)
        testing.expect_value(t, runtime^.dust.live_count, 0)
        testing.expect(t, !runtime^.dust.incoming_active)
        presentation_test_surface_frame(state, runtime, .Terminal)
        testing.expect(t, !runtime^.dust.incoming_active)
        state^.ui_runtime.preferences.values.interface.reduce_motion = false
        state^.ui_runtime.platform_reduce_motion = false
        state^.ui_runtime.preferences.values.interface.enable_particle_effects = true
        presentation_test_surface_frame(state, runtime, .Terminal)
        testing.expect_value(t, runtime^.dust.live_count, 0)
        testing.expect(t, !runtime^.dust.incoming_active)
    }
}

// Hidden document publications and playback completion cannot cancel a History transfer.
@(test)
presentation_surface_arrival_ignores_hidden_document_policy :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    presentation_test_publish_ink(state, {{30, 40}}, .Terminal)
    presentation_test_surface_frame(state, runtime, .Terminal)
    state^.ui_runtime.playback.completed = true
    presentation_test_surface_frame(state, runtime, .History)
    testing.expect(t, !presentation_document_effects_visible(state))
    presentation_document_arrival(state, runtime, 123)
    testing.expect(t, runtime^.dust.incoming_active)
    testing.expect_value(t, runtime^.arrival_ink_serial, u64(1))
    presentation_test_publish_ink(state, {{50, 60}}, .History)
    presentation_test_surface_frame(state, runtime, .History)
    testing.expect_value(t, runtime^.dust.formation_reclaimed, 1)
}

// A switch during handoff preserves visible material rather than emitting opaque ink twice.
@(test)
presentation_surface_interruption_releases_forming_ink :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, runtime := fixture.state, fixture.presentation
    presentation_test_reclaim_init(t, state, runtime)
    defer viewfont.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    presentation_test_publish_ink(state, {{30, 40}}, .Terminal)
    presentation_test_surface_frame(state, runtime, .Terminal)
    presentation_test_surface_frame(state, runtime, .History)
    presentation_test_publish_ink(state, {{80, 90}}, .History)
    presentation_test_surface_frame(state, runtime, .History, 0.27)
    presentation_test_surface_frame(state, runtime, .Terminal)
    testing.expect(t, runtime^.dust.live_count <= 2)
    alpha := f32(0)
    for index in 0..<runtime^.dust.initialized_slots {
        alpha += uidust.ui_dust_particle_alpha(&runtime^.dust, index)
    }
    testing.expect(t, alpha > 0.98 && alpha <= 1)
    presentation_test_publish_ink(state, {{40, 50}}, .Terminal)
    presentation_test_surface_frame(state, runtime, .Terminal)
    testing.expect_value(t, runtime^.dust.formation_reclaimed, 1)
    testing.expect(t, runtime^.dust.live_count <= uidust.UI_DUST_TOTAL_PARTICLES)
}
