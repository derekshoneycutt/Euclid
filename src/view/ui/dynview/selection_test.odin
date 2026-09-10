package ui_dynview

import "core:testing"

import core "../../../core"
import input "../../input"

import rl "vendor:raylib"

// Verify selection boundaries normalize forward and reverse drags.
@(test)
dynview_selection_test_orders_unit_boundaries :: proc(t: ^testing.T) {
    first := core.Dynview_Selection_Position{unit_index = 1}
    last := core.Dynview_Selection_Position{unit_index = 4}

    start, end := dynview_selection_ordered(last, first)

    testing.expect_value(t, start, first)
    testing.expect_value(t, end, last)
}

// Verify mixed prose clusters and one atomic math source compose in target order.
@(test)
dynview_selection_test_composes_document_units :: proc(t: ^testing.T) {
    source: string = "α + \\frac{a}{b} = c"
    text := transmute([]u8)source
    targets := []core.Dynview_Document_Layout_Copy_Target{
        {offset = 0, count = 2, canonical_text = true},
        {offset = 2, count = 3, canonical_text = true},
        {offset = 5, count = 11},
        {offset = 16, count = 4, canonical_text = true},
    }

    selected := dynview_document_selection_text(text, targets,
        {unit_index = 1}, {unit_index = 4})

    testing.expect_value(t, selected, " + \\frac{a}{b} = c")
}

// Verify collapsed and invalid semantic ranges never expose partial storage.
@(test)
dynview_selection_test_rejects_invalid_document_ranges :: proc(t: ^testing.T) {
    text := []u8{'a', 'b'}
    targets := []core.Dynview_Document_Layout_Copy_Target{
        {offset = 0, count = 1},
        {offset = 2, count = 1},
    }

    testing.expect_value(t, dynview_document_selection_text(
        text, targets, {unit_index = 1}, {unit_index = 1}), "")
    testing.expect_value(t, dynview_document_selection_text(
        text, targets, {unit_index = 0}, {unit_index = 2}), "")
}

// Verify authored separators copy while soft visual line changes remain invisible.
@(test)
dynview_selection_test_composes_only_authored_separators :: proc(t: ^testing.T) {
    text := []u8{'a', 'b', 'c', 'd'}
    targets := []core.Dynview_Document_Layout_Copy_Target{
        {offset = 0, count = 1},
        {offset = 1, count = 1},
        {offset = 2, count = 1, separator_before = .Line},
        {offset = 3, count = 1, separator_before = .Block},
    }

    selected := dynview_document_selection_text(text, targets,
        {unit_index = 0}, {unit_index = 4})

    testing.expect_value(t, selected, "ab\nc\n\nd")
    testing.expect_value(t, dynview_document_selection_text(
        text, targets, {unit_index = 2}, {unit_index = 4}), "c\n\nd")
}

// Verify UTF-8 unit boundaries map back to exact source byte boundaries.
@(test)
dynview_selection_test_maps_utf8_unit_boundaries :: proc(t: ^testing.T) {
    text := "aαb"

    testing.expect_value(t, dynview_text_byte_boundary(text, 0), 0)
    testing.expect_value(t, dynview_text_byte_boundary(text, 1), 1)
    testing.expect_value(t, dynview_text_byte_boundary(text, 2), 3)
    testing.expect_value(t, dynview_text_byte_boundary(text, 3), 4)
}

// Verify wrapped fallback selection preserves exact authored newline bytes.
@(test)
dynview_selection_test_wrapped_copy_preserves_newlines :: proc(t: ^testing.T) {
    selection := core.Dynview_Selection_State{
        mode = .Wrapped_Text, active = true,
        anchor = {unit_index = 1}, head = {unit_index = 4},
    }

    testing.expect_value(t,
        dynview_selection_text(nil, selection, "a\nbc"), "\nbc")
}

// Verify semantic selection reads the immutable published document bytes.
@(test)
dynview_selection_test_uses_published_document_text :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    published := []u8{'r', 'i', 'g', 'h', 't'}
    runtime^.content.document_text = published[:]
    runtime^.compile_cache.document_text[0] = 'x'
    runtime^.compile_cache.document_layout_copy_targets =
        []core.Dynview_Document_Layout_Copy_Target{{offset = 0, count = 5}}
    selection := core.Dynview_Selection_State{
        mode = .Semantic_Document, active = true,
        anchor = {unit_index = 0}, head = {unit_index = 1},
    }

    testing.expect_value(t,
        dynview_selection_text(runtime, selection, ""), "right")
}

// Verify semantic hit testing chooses the nearest half-open target boundary.
@(test)
dynview_selection_test_hits_semantic_boundaries :: proc(t: ^testing.T) {
    targets := []core.Dynview_Document_Layout_Copy_Target{
        {x = 0, y = 0, width = 10, height = 12},
        {x = 10, y = 0, width = 20, height = 12},
    }
    view := Dynview_Selection_View{
        panel = {x = 100, y = 50, width = 100, height = 30},
        text_padding = 5,
    }

    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, rl.Vector2{106, 56}).unit_index, 0)
    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, rl.Vector2{112, 56}).unit_index, 1)
    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, rl.Vector2{129, 56}).unit_index, 2)
}

// Verify content revision and mode changes retire stale logical boundaries.
@(test)
dynview_selection_test_reconciles_content_identity :: proc(t: ^testing.T) {
    selection := core.Dynview_Selection_State{
        mode = .Semantic_Document, revision = 4,
        anchor = {unit_index = 1}, head = {unit_index = 3}, active = true,
    }

    dynview_selection_reconcile(&selection, {.Semantic_Document, 5, 4})

    testing.expect(t, !selection.active)
    testing.expect_value(t, selection.mode,
        core.Dynview_Selection_Mode.Semantic_Document)
    testing.expect_value(t, selection.revision, u64(5))
}

// Verify Ctrl+A selects every unit and Ctrl+C preserves active selection state.
@(test)
dynview_selection_test_keyboard_selects_all :: proc(t: ^testing.T) {
    events := [1]input.Input_Event{{
        kind = .Press, key = .A, modifiers = {.Control},
    }}
    selection := core.Dynview_Selection_State{
        mode = .Wrapped_Text, revision = 2,
    }

    dynview_selection_update_keyboard(nil, &selection,
        {.Wrapped_Text, 2, 4}, "test", {events = events[:]})

    testing.expect(t, selection.active)
    testing.expect_value(t, selection.anchor.unit_index, 0)
    testing.expect_value(t, selection.head.unit_index, 4)
    testing.expect_value(t, dynview_selection_text(nil, selection, "test"), "test")
}

// Verify a copy-icon press cannot claim Dynview selection ownership.
@(test)
dynview_selection_test_copy_icon_has_pointer_priority :: proc(t: ^testing.T) {
    runtime := new(core.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.compile_cache.copy_hit_targets = []core.Dynview_Copy_Hit_Target{{
        rect = {x = 10, y = 10, width = 20, height = 20},
    }}
    selection: core.Dynview_Selection_State
    owner: core.Ui_Press_Owner_State
    frame := input.Input_Frame{
        mouse_position = {15, 15}, mouse_pressed = {.Left}, mouse_down = {.Left},
    }

    dynview_selection_update_mouse({
        runtime = runtime, selection = &selection, press_owner = &owner,
        content = {.Wrapped_Text, 1, 4}, view = {
            panel = {0, 0, 100, 100}, row_height = 20,
            wrap_advance = 8, fallback_text = "test",
        }, frame = frame,
    })

    testing.expect(t, !selection.dragging)
    testing.expect(t, !owner.active)
}

// Verify a pointer drag captures ownership and finalizes a nonempty range.
@(test)
dynview_selection_test_drag_finalizes_wrapped_range :: proc(t: ^testing.T) {
    selection := core.Dynview_Selection_State{
        mode = .Wrapped_Text, revision = 1,
    }
    owner: core.Ui_Press_Owner_State
    view := Dynview_Selection_View{
        panel = {0, 0, 100, 30}, row_height = 20,
        wrap_advance = 8, fallback_text = "test",
    }
    dynview_selection_update_mouse({
        selection = &selection, press_owner = &owner,
        content = {.Wrapped_Text, 1, 4}, view = view,
        frame = {mouse_position = {1, 5}, mouse_pressed = {.Left},
            mouse_down = {.Left}},
    })
    dynview_selection_update_mouse({
        selection = &selection, press_owner = &owner,
        content = {.Wrapped_Text, 1, 4}, view = view,
        frame = {mouse_position = {25, 5}, mouse_released = {.Left}},
    })

    testing.expect(t, selection.active && !selection.dragging)
    testing.expect(t, !owner.active)
    testing.expect_value(t, dynview_selection_text(nil, selection, "test"), "tes")
}