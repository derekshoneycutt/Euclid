#+test
package settings

import particlemodel "../particles/model"

import "core:testing"

// Preserve every established no-database preference default.
@(test)
preference_defaults_match_existing_behavior :: proc(t: ^testing.T) {
    preferences := default_preferences()
    for id in ALL_SETTING_IDS {
        testing.expect(t, id not_in preferences.present)
        testing.expect(t, id not_in preferences.overrides)
        testing.expect(t, valid_setting_value(id, setting_value(preferences, id)))
    }
    testing.expect_value(t, setting_value(preferences, .Window_Width).integer, 1280)
    testing.expect_value(t, setting_value(preferences, .Window_Height).integer, 720)
    testing.expect_value(t,
        setting_value(preferences, .Window_Mode).window_mode, Window_Mode.Fixed)
    testing.expect_value(t,
        setting_value(preferences, .Window_Layout).layout, Layout_Preference.Auto)
    testing.expect(t, setting_value(preferences, .Rendering_Vsync).boolean)
    testing.expect(t, setting_value(preferences, .Rendering_Antialiasing).boolean)
    testing.expect(t, setting_value(preferences, .Rendering_Limit_Fps).boolean)
    testing.expect(t, setting_value(preferences, .Rendering_Simd).boolean)
    testing.expect(t, setting_value(preferences, .Rendering_Gpu_Dust_Instancing).boolean)
    testing.expect_value(t, setting_value(preferences, .Drawing_Dust_Limit).integer,
        particlemodel.MAX_LOW_PARTICLES)
    testing.expect(t, !setting_value(preferences, .Drawing_Sound_Enabled).boolean)
    testing.expect(t, !setting_value(preferences, .Interface_Display_Fps).boolean)
}

// Validate window dimensions, enum domains, and particle capacity bounds.
@(test)
preference_validation_preserves_existing_bounds :: proc(t: ^testing.T) {
    testing.expect(t, valid_window_dimensions(320, 240))
    testing.expect(t, valid_window_dimensions(16384, 16384))
    testing.expect(t, !valid_window_dimensions(319, 240))
    testing.expect(t, !valid_window_dimensions(320, 239))
    testing.expect(t, !valid_window_dimensions(16385, 240))
    testing.expect(t, !valid_window_dimensions(320, 16385))
    testing.expect(t, valid_window_mode(.Fixed))
    testing.expect(t, valid_window_mode(.Resizable))
    testing.expect(t, !valid_window_mode(Window_Mode(255)))
    testing.expect(t, valid_layout_preference(.Auto))
    testing.expect(t, valid_layout_preference(.Landscape))
    testing.expect(t, valid_layout_preference(.Portrait))
    testing.expect(t, !valid_layout_preference(Layout_Preference(255)))
    testing.expect(t, valid_dust_limit(0))
    testing.expect(t, valid_dust_limit(particlemodel.MAX_LOW_PARTICLES))
    testing.expect(t, !valid_dust_limit(-1))
    testing.expect(t, !valid_dust_limit(particlemodel.MAX_LOW_PARTICLES + 1))
}

// Keep durable identities complete and unique across the fixed setting catalog.
@(test)
setting_definitions_are_complete_and_unique :: proc(t: ^testing.T) {
    ids := ALL_SETTING_IDS
    for first_index in 0..<SETTING_COUNT {
        first, first_valid := setting_definition(ids[first_index])
        testing.expect(t, first_valid)
        testing.expect_value(t, first.id, ids[first_index])
        testing.expect(t, len(first.namespace) > 0 && len(first.key) > 0)
        for second_index in first_index + 1..<SETTING_COUNT {
            second, second_valid := setting_definition(ids[second_index])
            testing.expect(t, second_valid)
            testing.expect(t,
                first.namespace != second.namespace || first.key != second.key)
        }
    }
    _, invalid := setting_definition(Setting_Id(255))
    testing.expect(t, !invalid)
}

// Track saved-row presence separately from explicit invocation overrides.
@(test)
saved_and_override_presence_are_explicit :: proc(t: ^testing.T) {
    preferences := default_preferences()
    testing.expect(t, apply_setting_value(
        &preferences, .Rendering_Vsync, boolean_value(false), .Saved))
    testing.expect(t, .Rendering_Vsync in preferences.present)
    testing.expect(t, .Rendering_Vsync not_in preferences.overrides)
    testing.expect(t, !setting_value(preferences, .Rendering_Vsync).boolean)

    testing.expect(t, apply_setting_value(
        &preferences, .Rendering_Antialiasing, boolean_value(true), .Override))
    testing.expect(t, .Rendering_Antialiasing not_in preferences.present)
    testing.expect(t, .Rendering_Antialiasing in preferences.overrides)
    testing.expect(t, setting_value(preferences, .Rendering_Antialiasing).boolean)
    testing.expect(t, !apply_setting_value(
        &preferences, .Window_Width, integer_value(319), .Override))
    testing.expect(t, !apply_setting_value(
        &preferences, .Window_Mode, boolean_value(false), .Override))
}

// Keep one newest Set or Reset operation per setting in a bounded change set.
@(test)
change_sets_coalesce_set_and_reset :: proc(t: ^testing.T) {
    changes: Change_Set
    testing.expect(t, change_set_set(
        &changes, .Drawing_Dust_Limit, integer_value(20000)))
    testing.expect(t, change_set_set(
        &changes, .Drawing_Dust_Limit, integer_value(10000)))
    testing.expect_value(t, changes.count, 1)
    testing.expect_value(t, changes.changes[0].kind, Change_Kind.Set)
    testing.expect_value(t, changes.changes[0].value.integer, 10000)

    testing.expect(t, change_set_reset(&changes, .Drawing_Dust_Limit))
    testing.expect_value(t, changes.count, 1)
    testing.expect_value(t, changes.changes[0].kind, Change_Kind.Reset)
    testing.expect(t, !change_set_set(
        &changes, .Drawing_Dust_Limit, integer_value(-1)))
}

// Keep the complete known catalog within the fixed maximum batch capacity.
@(test)
change_sets_accept_each_known_setting_once :: proc(t: ^testing.T) {
    preferences := default_preferences()
    changes: Change_Set
    for id in ALL_SETTING_IDS {
        testing.expect(t, change_set_set(
            &changes, id, setting_value(preferences, id)))
    }
    testing.expect_value(t, changes.count, SETTING_COUNT)
    testing.expect(t, !change_set_reset(&changes, Setting_Id(255)))
}

// Retain failed older work without overwriting newer pending edits.
@(test)
failed_batch_merge_keeps_newer_pending_value :: proc(t: ^testing.T) {
    failed: Change_Set
    pending: Change_Set
    testing.expect(t, change_set_set(
        &failed, .Drawing_Dust_Limit, integer_value(20000)))
    testing.expect(t, change_set_set(
        &failed, .Rendering_Vsync, boolean_value(false)))
    testing.expect(t, change_set_set(
        &pending, .Drawing_Dust_Limit, integer_value(10000)))
    testing.expect(t, change_set_reset(&pending, .Rendering_Antialiasing))

    testing.expect(t, merge_failed_batch(&pending, failed))
    testing.expect_value(t, pending.count, 3)
    dust_index := change_index(&pending, .Drawing_Dust_Limit)
    vsync_index := change_index(&pending, .Rendering_Vsync)
    aa_index := change_index(&pending, .Rendering_Antialiasing)
    testing.expect_value(t, pending.changes[dust_index].value.integer, 10000)
    testing.expect_value(t, pending.changes[vsync_index].value.boolean, false)
    testing.expect_value(t, pending.changes[aa_index].kind, Change_Kind.Reset)
}

// Merge newer batches by key while retaining unrelated prior operations.
@(test)
newer_batch_merge_replaces_only_matching_keys :: proc(t: ^testing.T) {
    older: Change_Set
    newer: Change_Set
    testing.expect(t, change_set_set(
        &older, .Drawing_Dust_Limit, integer_value(20000)))
    testing.expect(t, change_set_set(&older, .Rendering_Vsync, boolean_value(false)))
    testing.expect(t, change_set_reset(&newer, .Drawing_Dust_Limit))
    testing.expect(t, change_set_set(
        &newer, .Rendering_Antialiasing, boolean_value(false)))

    testing.expect(t, change_set_merge_newer(&older, newer))
    testing.expect_value(t, older.count, 3)
    testing.expect_value(t,
        older.changes[change_index(&older, .Drawing_Dust_Limit)].kind,
        Change_Kind.Reset)
    testing.expect_value(t,
        older.changes[change_index(&older, .Rendering_Vsync)].value.boolean, false)
}
