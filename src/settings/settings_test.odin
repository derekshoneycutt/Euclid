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
    testing.expect(t, !setting_value(preferences, .Interface_Reduce_Motion).boolean)
    testing.expect(t, !setting_value(preferences, .Interface_Increased_Contrast).boolean)
    testing.expect_value(t,
        setting_value(preferences, .Interface_Text_Size).integer, 100)
    testing.expect(t, !setting_value(preferences, .Interface_Hover_Focus).boolean)
    testing.expect_value(t,
        setting_value(preferences, .Interface_Control_Size).integer, 100)
    testing.expect(t, !setting_value(preferences, .Interface_Show_Magnifier).boolean)
    testing.expect(t, !setting_value(
        preferences, .Interface_Magnifier_Input_Lock).boolean)
    testing.expect(t, !setting_value(preferences, .Persist_Terminal_History).boolean)
    testing.expect_value(t,
        setting_value(preferences, .Animation_Scale_Percent).integer, 100)
    testing.expect(t, !setting_value(preferences, .Animation_Monochrome).boolean)
}

// Keep the pointer magnifier opt-in and persist it as an interface preference.
@(test)
show_magnifier_uses_typed_persisted_preference :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Show_Magnifier)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "show_magnifier")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Boolean)

    preferences := default_preferences()
    testing.expect(t, !preferences.interface.show_magnifier)
    testing.expect(t, apply_setting_value(
        &preferences, .Interface_Show_Magnifier, boolean_value(true), .Saved))
    testing.expect(t, preferences.interface.show_magnifier)
    testing.expect(t, .Interface_Show_Magnifier in preferences.present)
    changes: Change_Set
    testing.expect(t, change_set_reset(&changes, .Interface_Show_Magnifier))
}

// Keep caret-lock opt-in and persist it as a typed interface preference.
@(test)
magnifier_input_lock_uses_typed_persisted_preference :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Magnifier_Input_Lock)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "magnifier_input_lock")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Boolean)

    preferences := default_preferences()
    testing.expect(t, !preferences.interface.magnifier_input_lock)
    testing.expect(t, apply_setting_value(
        &preferences, .Interface_Magnifier_Input_Lock, boolean_value(true), .Saved))
    testing.expect(t, preferences.interface.magnifier_input_lock)
    testing.expect(t, .Interface_Magnifier_Input_Lock in preferences.present)
    changes: Change_Set
    testing.expect(t,
        change_set_reset(&changes, .Interface_Magnifier_Input_Lock))
}

// Keep control size bounded, discrete, persisted, and separate from text size.
@(test)
control_size_uses_five_supported_persisted_stops :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Control_Size)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "control_size_percent")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Integer)
    for percent in ([5]int{100, 125, 150, 175, 200}) {
        preferences := default_preferences()
        testing.expect(t, apply_setting_value(
            &preferences, .Interface_Control_Size, integer_value(percent), .Saved))
        testing.expect_value(t,
            setting_value(preferences, .Interface_Control_Size).integer, percent)
        testing.expect_value(t,
            preferences.interface.text_size_percent, 100)
        testing.expect(t, .Interface_Control_Size in preferences.present)
    }
    preferences := default_preferences()
    testing.expect(t, apply_setting_value(
        &preferences, .Interface_Control_Size, integer_value(175), .Override))
    testing.expect(t, .Interface_Control_Size in preferences.overrides)
    for percent in ([4]int{99, 101, 124, 201}) {
        testing.expect(t, !apply_setting_value(
            &preferences, .Interface_Control_Size, integer_value(percent), .Saved))
    }
    testing.expect(t, !apply_setting_value(
        &preferences, .Interface_Control_Size, boolean_value(true), .Saved))
}

// Keep animation style defaults, identities, typed access, and validation stable.
@(test)
animation_style_preferences_are_typed_and_bounded :: proc(t: ^testing.T) {
    scale_definition, scale_valid := setting_definition(.Animation_Scale_Percent)
    testing.expect(t, scale_valid)
    testing.expect_value(t, scale_definition.namespace, "animation")
    testing.expect_value(t, scale_definition.key, "scale_percent")
    testing.expect_value(t, scale_definition.storage_kind, Setting_Storage_Kind.Integer)
    monochrome_definition, monochrome_valid :=
        setting_definition(.Animation_Monochrome)
    testing.expect(t, monochrome_valid)
    testing.expect_value(t, monochrome_definition.namespace, "animation")
    testing.expect_value(t, monochrome_definition.key, "monochrome")
    testing.expect_value(t, monochrome_definition.storage_kind,
        Setting_Storage_Kind.Boolean)

    for percent in ([3]int{50, 100, 200}) {
        preferences := default_preferences()
        testing.expect(t, apply_setting_value(
            &preferences, .Animation_Scale_Percent, integer_value(percent), .Saved))
        testing.expect_value(t,
            setting_value(preferences, .Animation_Scale_Percent).integer, percent)
        testing.expect(t, .Animation_Scale_Percent in preferences.present)
    }
    preferences := default_preferences()
    testing.expect(t, apply_setting_value(
        &preferences, .Animation_Monochrome, boolean_value(true), .Override))
    testing.expect(t, setting_value(preferences, .Animation_Monochrome).boolean)
    testing.expect(t, .Animation_Monochrome in preferences.overrides)
    for percent in ([4]int{49, 201, 52, 198}) {
        testing.expect(t, !apply_setting_value(
            &preferences, .Animation_Scale_Percent, integer_value(percent), .Saved))
    }
    testing.expect(t, !apply_setting_value(
        &preferences, .Animation_Monochrome, integer_value(1), .Saved))
}

// Keep durable Terminal history opt-in and typed as a boolean setting.
@(test)
terminal_history_persistence_is_opt_in :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Persist_Terminal_History)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "terminal")
    testing.expect_value(t, definition.key, "persist_history")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Boolean)
    preferences := default_preferences()
    testing.expect(t, apply_setting_value(
        &preferences, .Persist_Terminal_History, boolean_value(true), .Saved))
    testing.expect(t, preferences.terminal.persist_history)
    testing.expect(t, .Persist_Terminal_History in preferences.present)
    testing.expect(t, !apply_setting_value(
        &preferences, .Persist_Terminal_History, integer_value(1), .Override))
}

// Keep contrast optional by default and retain its stable boolean persistence identity.
@(test)
increased_contrast_uses_typed_persisted_preference :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Increased_Contrast)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "increased_contrast")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Boolean)
    preferences := default_preferences()
    testing.expect(t, !apply_setting_value(&preferences,
        .Interface_Increased_Contrast, integer_value(1), .Saved))
    testing.expect(t, apply_setting_value(&preferences,
        .Interface_Increased_Contrast, boolean_value(true), .Saved))
    testing.expect(t, preferences.interface.increased_contrast)
    testing.expect(t, .Interface_Increased_Contrast in preferences.present)
    testing.expect(t, .Interface_Increased_Contrast not_in preferences.overrides)
    testing.expect(t, apply_setting_value(&preferences,
        .Interface_Increased_Contrast, boolean_value(false), .Override))
    testing.expect(t, !setting_value(preferences, .Interface_Increased_Contrast).boolean)
    testing.expect(t, .Interface_Increased_Contrast in preferences.overrides)
}

// Keep hover focus opt-in and independently typed as a boolean preference.
@(test)
hover_focus_uses_typed_persisted_preference :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Hover_Focus)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "hover_focus")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Boolean)
    preferences := default_preferences()
    testing.expect(t, !preferences.interface.hover_focus)
    testing.expect(t, apply_setting_value(&preferences,
        .Interface_Hover_Focus, boolean_value(true), .Saved))
    testing.expect(t, preferences.interface.hover_focus)
    testing.expect(t, .Interface_Hover_Focus in preferences.present)
    testing.expect(t, apply_setting_value(&preferences,
        .Interface_Hover_Focus, boolean_value(false), .Override))
    testing.expect(t, !preferences.interface.hover_focus)
    testing.expect(t, .Interface_Hover_Focus in preferences.overrides)
    testing.expect(t, !apply_setting_value(&preferences,
        .Interface_Hover_Focus, integer_value(1), .Saved))
}

// Keep all supported text-size stops stable as typed persisted integer values.
@(test)
text_size_uses_four_supported_persisted_stops :: proc(t: ^testing.T) {
    definition, valid := setting_definition(.Interface_Text_Size)
    testing.expect(t, valid)
    testing.expect_value(t, definition.namespace, "interface")
    testing.expect_value(t, definition.key, "text_size_percent")
    testing.expect_value(t, definition.storage_kind, Setting_Storage_Kind.Integer)
    for percent in ([4]int{100, 125, 150, 175}) {
        preferences := default_preferences()
        testing.expect(t, apply_setting_value(
            &preferences, .Interface_Text_Size, integer_value(percent), .Saved))
        testing.expect_value(t,
            setting_value(preferences, .Interface_Text_Size).integer, percent)
        testing.expect(t, .Interface_Text_Size in preferences.present)
    }
    preferences := default_preferences()
    for percent in ([3]int{99, 124, 176}) {
        testing.expect(t, !apply_setting_value(
            &preferences, .Interface_Text_Size, integer_value(percent), .Override))
    }
    testing.expect(t, !apply_setting_value(
        &preferences, .Interface_Text_Size, boolean_value(true), .Saved))
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
