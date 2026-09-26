package ui_dynview

import viewmodel "../../model"
import native "../../native"
import dynviewmodel "../../../dynview/model"
import color "../../../core/color"
import geometry "../../../core/geometry"

import "core:testing"

import input "../../input"

// Verify selection boundaries normalize forward and reverse drags.
@(test)
dynview_selection_test_orders_unit_boundaries :: proc(t: ^testing.T) {
    first := dynviewmodel.Dynview_Selection_Position{unit_index = 1}
    last := dynviewmodel.Dynview_Selection_Position{unit_index = 4}

    start, end := dynview_selection_ordered(last, first)

    testing.expect_value(t, start, first)
    testing.expect_value(t, end, last)
}

// Verify mixed prose clusters and one atomic math source compose in target order.
@(test)
dynview_selection_test_composes_document_units :: proc(t: ^testing.T) {
    source: string = "α + \\frac{a}{b} = c"
    text := transmute([]u8)source
    targets := []dynviewmodel.Dynview_Document_Layout_Copy_Target{
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
    targets := []dynviewmodel.Dynview_Document_Layout_Copy_Target{
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
    targets := []dynviewmodel.Dynview_Document_Layout_Copy_Target{
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

// Verify generated list labels copy beside bodies with one newline per item.
@(test)
dynview_selection_test_composes_list_items :: proc(t: ^testing.T) {
    source: string = "1.alph2.bet"
    text := transmute([]u8)source
    targets := []dynviewmodel.Dynview_Document_Layout_Copy_Target{
        {offset = 0, count = 2, canonical_text = true},
        {offset = 2, count = 4, canonical_text = true,
            separator_before = .Space},
        {offset = 6, count = 2, canonical_text = true,
            separator_before = .Item},
        {offset = 8, count = 3, canonical_text = true,
            separator_before = .Space},
    }

    selected := dynview_document_selection_text(text, targets,
        {unit_index = 4}, {unit_index = 0})

    testing.expect_value(t, selected, "1. alph\n2. bet")
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
    selection := dynviewmodel.Dynview_Selection_State{
        mode = .Wrapped_Text, active = true,
        anchor = {unit_index = 1}, head = {unit_index = 4},
    }

    testing.expect_value(t,
        dynview_selection_text(nil, selection, "a\nbc"), "\nbc")
}

// Verify semantic selection reads the immutable published document bytes.
@(test)
dynview_selection_test_uses_published_document_text :: proc(t: ^testing.T) {
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    published := []u8{'r', 'i', 'g', 'h', 't'}
    runtime^.content.document_text = published[:]
    runtime^.compile_cache.document_text[0] = 'x'
    runtime^.compile_cache.document_layout_copy_targets =
        []dynviewmodel.Dynview_Document_Layout_Copy_Target{{offset = 0, count = 5}}
    selection := dynviewmodel.Dynview_Selection_State{
        mode = .Semantic_Document, active = true,
        anchor = {unit_index = 0}, head = {unit_index = 1},
    }

    testing.expect_value(t,
        dynview_selection_text(runtime, selection, ""), "right")
}

// Verify semantic hit testing chooses the nearest half-open target boundary.
@(test)
dynview_selection_test_hits_semantic_boundaries :: proc(t: ^testing.T) {
    targets := []dynviewmodel.Dynview_Document_Layout_Copy_Target{
        {x = 0, y = 0, width = 10, height = 12},
        {x = 10, y = 0, width = 20, height = 12},
    }
    view := Dynview_Selection_View{
        panel = {x = 100, y = 50, width = 100, height = 30},
        text_padding = 5,
    }

    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, geometry.Vector2{106, 56}).unit_index, 0)
    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, geometry.Vector2{112, 56}).unit_index, 1)
    testing.expect_value(t, dynview_document_hit_boundary(
        targets, view, geometry.Vector2{129, 56}).unit_index, 2)
}

// Verify content revision and mode changes retire stale logical boundaries.
@(test)
dynview_selection_test_reconciles_content_identity :: proc(t: ^testing.T) {
    selection := dynviewmodel.Dynview_Selection_State{
        mode = .Semantic_Document, revision = 4,
        anchor = {unit_index = 1}, head = {unit_index = 3}, active = true,
    }

    dynview_selection_reconcile(&selection, {.Semantic_Document, 5, 4})

    testing.expect(t, !selection.active)
    testing.expect_value(t, selection.mode,
        dynviewmodel.Dynview_Selection_Mode.Semantic_Document)
    testing.expect_value(t, selection.revision, u64(5))
}

// Verify Ctrl+A selects every unit and Ctrl+C preserves active selection state.
@(test)
dynview_selection_test_keyboard_selects_all :: proc(t: ^testing.T) {
    events := [1]input.Input_Event{{
        kind = .Press, key = .A, modifiers = {.Control},
    }}
    selection := dynviewmodel.Dynview_Selection_State{
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
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.compile_cache.copy_hit_targets = []dynviewmodel.Dynview_Copy_Hit_Target{{
        rect = {x = 10, y = 10, width = 20, height = 20},
    }}
    selection: dynviewmodel.Dynview_Selection_State
    owner: viewmodel.Ui_Press_Owner_State
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
    selection := dynviewmodel.Dynview_Selection_State{
        mode = .Wrapped_Text, revision = 1,
    }
    owner: viewmodel.Ui_Press_Owner_State
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

// Verify adjacent semantic targets merge into one full-line-height underlay.
@(test)
dynview_selection_test_draws_merged_document_line :: proc(t: ^testing.T) {
    vertices: [4]native.Draw_Vertex
    indices: [6]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {200, 100}, {200, 100}))
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.compile_cache.document_layout_lines =
        []dynviewmodel.Dynview_Document_Layout_Line{{top = 2, bottom = 20}}
    runtime^.compile_cache.document_layout_copy_targets =
        []dynviewmodel.Dynview_Document_Layout_Copy_Target{
            {line_index = 0, x = 10, y = 7, width = 8, height = 9},
            {line_index = 0, x = 22, y = 7, width = 12, height = 9},
        }

    dynview_draw_selection({
        encoder = &encoder, runtime = runtime,
        selection = {.Semantic_Document, 0, {0}, {2}, true, false},
        view = {panel = {100, 40, 80, 50}, text_padding = 5, scroll_y = 3},
        color = color.WHITE,
    })

    testing.expect_value(t, encoder.vertex_count, 4)
    testing.expect_value(t, vertices[0].position, geometry.Vector2{115, 44})
    testing.expect_value(t, vertices[2].position, geometry.Vector2{139, 62})
}

// Verify multi-line semantic selection extends only continuation edges.
@(test)
dynview_selection_test_draws_document_continuation_bands :: proc(t: ^testing.T) {
    vertices: [12]native.Draw_Vertex
    indices: [18]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {200, 100}, {200, 100}))
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.compile_cache.document_layout_lines =
        []dynviewmodel.Dynview_Document_Layout_Line{
            {top = 0, bottom = 10}, {top = 14, bottom = 24},
            {top = 28, bottom = 38},
        }
    runtime^.compile_cache.document_layout_copy_targets =
        []dynviewmodel.Dynview_Document_Layout_Copy_Target{
            {line_index = 0, x = 20, width = 10},
            {line_index = 1, x = 6, width = 8},
            {line_index = 2, x = 12, width = 9},
        }

    dynview_draw_selection({
        encoder = &encoder, runtime = runtime,
        selection = {.Semantic_Document, 0, {0}, {3}, true, false},
        view = {panel = {10, 20, 100, 60}, text_padding = 5},
        color = color.WHITE,
    })

    testing.expect_value(t, encoder.vertex_count, 12)
    testing.expect_value(t, vertices[0].position, geometry.Vector2{35, 25})
    testing.expect_value(t, vertices[2].position, geometry.Vector2{105, 35})
    testing.expect_value(t, vertices[4].position, geometry.Vector2{15, 39})
    testing.expect_value(t, vertices[6].position, geometry.Vector2{105, 49})
    testing.expect_value(t, vertices[8].position, geometry.Vector2{15, 53})
    testing.expect_value(t, vertices[10].position, geometry.Vector2{36, 63})
}

// Verify wrapped selection uses full rows with partial outer fragments.
@(test)
dynview_selection_test_draws_wrapped_row_bands :: proc(t: ^testing.T) {
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    dynview_draw_selection({
        encoder = &encoder,
        selection = {.Wrapped_Text, 0, {1}, {5}, true, false},
        view = {
            panel = {10, 20, 40, 60}, text_padding = 5, row_height = 20,
            wrap_advance = 10, fallback_text = "abcdef",
        },
        color = color.WHITE,
    })

    testing.expect_value(t, encoder.vertex_count, 8)
    testing.expect_value(t, vertices[0].position, geometry.Vector2{25, 25})
    testing.expect_value(t, vertices[2].position, geometry.Vector2{45, 45})
    testing.expect_value(t, vertices[4].position, geometry.Vector2{15, 45})
    testing.expect_value(t, vertices[6].position, geometry.Vector2{35, 65})
}