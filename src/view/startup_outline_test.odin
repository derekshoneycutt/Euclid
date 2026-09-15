package view

import viewmodel "model"

import "core:testing"

// Verify the startup silhouette covers every intended stable UI boundary.
@(test)
startup_outline_contains_bounded_nonempty_segments :: proc(t: ^testing.T) {
    outline := startup_outline_create()

    testing.expect(t, outline.segment_count <= STARTUP_OUTLINE_SEGMENT_CAP)
    testing.expect_value(t, outline.segment_count, 32)
    testing.expect(t, outline.total_length > 0)
    for index in 0..<outline.segment_count {
        testing.expect(t, outline.segments[index].length > 0)
    }
}

// Verify portrait startup geometry fits bounded storage and follows live dimensions.
@(test)
startup_outline_portrait_uses_live_geometry :: proc(t: ^testing.T) {
    outline := startup_outline_create({640, 900}, .Portrait, .Auto)

    testing.expect_value(t, outline.segment_count, STARTUP_OUTLINE_SEGMENT_CAP)
    testing.expect_value(t, outline.metrics.width, 640)
    testing.expect_value(t, outline.metrics.height, 900)
    testing.expect_value(t, outline.layout, viewmodel.Ui_Layout_Mode.Portrait)
    for index in 0..<outline.segment_count {
        testing.expect(t, outline.segments[index].length > 0)
    }
}

// Verify reveal motion respects clamped loading milestones without overshoot.
@(test)
startup_outline_reveal_tracks_bounded_target :: proc(t: ^testing.T) {
    outline := startup_outline_create()
    startup_outline_set_target(&outline, 0.35)
    startup_outline_advance(&outline, STARTUP_OUTLINE_SECONDS)

    testing.expect_value(t, outline.reveal_distance, outline.total_length * 0.35)
    startup_outline_set_target(&outline, 2)
    startup_outline_advance(&outline, STARTUP_OUTLINE_SECONDS)
    testing.expect_value(t, outline.reveal_distance, outline.total_length)
    testing.expect_value(t, outline.target_distance, outline.total_length)
}

// Verify resize and automatic orientation rebuild preserve normalized progress.
@(test)
startup_outline_rebuild_preserves_progress_fractions :: proc(t: ^testing.T) {
    outline := startup_outline_create({1280, 720}, .Landscape, .Auto)
    startup_outline_set_target(&outline, 0.65)
    outline.reveal_distance = outline.total_length * 0.35

    testing.expect(t, startup_outline_reconcile(&outline, {640, 900}))
    testing.expect_value(t, outline.layout, viewmodel.Ui_Layout_Mode.Portrait)
    testing.expect_value(t, outline.metrics, viewmodel.Ui_Window_Metrics{640, 900})
    testing.expect(t, abs(outline.reveal_distance / outline.total_length - 0.35) < 0.0001)
    testing.expect(t, abs(outline.target_distance / outline.total_length - 0.65) < 0.0001)
    testing.expect(t, !startup_outline_reconcile(&outline, {640, 900}))
}

// Verify forced startup layout remains fixed while its live extent rebuilds.
@(test)
startup_outline_forced_layout_survives_resize :: proc(t: ^testing.T) {
    outline := startup_outline_create({1280, 720}, .Landscape, .Landscape)

    testing.expect(t, startup_outline_reconcile(&outline, {640, 900}))
    testing.expect_value(t, outline.layout, viewmodel.Ui_Layout_Mode.Landscape)
}

// Verify the fallback Julia warning centers from the current logical extent.
@(test)
startup_warning_centers_from_live_metrics :: proc(t: ^testing.T) {
    position := startup_warning_position({640, 900}, 200, 20)

    testing.expect_value(t, position.x, f32(220))
    testing.expect_value(t, position.y, f32(440))
}