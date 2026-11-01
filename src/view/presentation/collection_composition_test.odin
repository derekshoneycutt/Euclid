package viewpresentation

import animation_model "../../core/animation"
import bridge "../../bridge"
import bridgemodel "../../bridge/model"
import presentation_model "../../bridge/presentation"
import dynviewmodel "../../dynview/model"
import testing "core:testing"
import thread "core:thread"
import core "../../core"

// Install a generation-owned active-placement source without involving persistence.
presentation_test_note :: proc(
    t: ^testing.T, fixture: Presentation_Test_Fixture, source: string, on_top: bool) {
    buffer, ready := animation_model.animation_memory_note_buffer(
        &fixture.state^.animation_memory)
    testing.expect(t, ready)
    copy(buffer, source)
    fixture.state^.ui_runtime.library.collection_note = {
        status = .Ready,
        generation = fixture.state^.animation_memory.generation,
        request_id = 1,
        revision = 1,
        text_length = len(source),
        notes_on_top = on_top,
    }
}

// Bound the wait for one local composition, including its owner-side parse commit.
presentation_test_composition_wait :: proc(
    t: ^testing.T, fixture: Presentation_Test_Fixture) {
    for _ in 0..<100000 {
        presentation_service_composition(fixture.state, fixture.presentation)
        composition := &fixture.presentation^.composition
        if !composition^.work.submitted && !composition^.dirty {
            return
        }
        thread.yield()
    }
    testing.expect(t, false, "composition did not settle")
}

// Check exact source order in the authoritative, pointer-free composed document.
presentation_test_document_source :: proc(
    t: ^testing.T, fixture: Presentation_Test_Fixture, index: int, source: string) {
    content := &fixture.state^.dynview.content
    testing.expect(t, index < len(content^.documents))
    if index >= len(content^.documents) {
        return
    }
    document := content^.documents[index]
    testing.expect_value(t, string(content^.document_text[
        document.source_offset:document.source_offset+document.source_count]), source)
}

// Notes render semantic math in either order, including without a producer event.
@(test)
presentation_collection_notes_are_ordered_semantic_bodies :: proc(t: ^testing.T) {
    orders: [2]bool = {false, true}
    for on_top in orders {
        fixture := presentation_test_fixture_create(t)
        defer presentation_test_fixture_destroy(fixture)
        note := "\\textbf{Note} $x_1^2$"
        producer := "Original $y$"
        presentation_test_note(t, fixture, note, on_top)
        content: bridgemodel.View_Content_Ready = {
            runtime_generation = 3,
            animation_generation = 5,
            presentation_generation = 1,
            animation = fixture.state^.julia_interface^.current_animation,
            content = {.Text_Latex, transmute([]u8)producer},
        }
        presentation_composition_accept(fixture.presentation, content)
        fixture.presentation^.composition.producer_ready = true
        presentation_test_composition_wait(t, fixture)
        testing.expect_value(t, len(fixture.state^.dynview.content.documents), 2)
        testing.expect(t, !fixture.state^.dynview.content.documents[0].separated_body)
        testing.expect(t, fixture.state^.dynview.content.documents[1].separated_body)
        presentation_test_document_source(t, fixture, 0, note if on_top else producer)
        presentation_test_document_source(t, fixture, 1, producer if on_top else note)
        math_count := 0
        for item in fixture.state^.dynview.content.document_inlines {
            if item.kind == .Math {
                math_count += 1
            }
        }
        testing.expect_value(t, math_count, 2)
    }
}

// A note-only placement publishes through Dynview without requiring animation text.
@(test)
presentation_collection_notes_publish_without_animation_text :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    source := "Only notes $\\frac{a}{b}$"
    presentation_test_note(t, fixture, source, false)
    presentation_test_composition_wait(t, fixture)
    testing.expect_value(t, len(fixture.state^.dynview.content.documents), 1)
    presentation_test_document_source(t, fixture, 0, source)
    testing.expect_value(t, bridge.current_view_snapshot_text(fixture.state), source)
}

// Plain producer syntax remains literal and rejected TeX cannot erase a valid note.
@(test)
presentation_collection_notes_isolate_literal_and_rejected_bodies :: proc(t: ^testing.T) {
    modes: [2]presentation_model.Presentation_Mime = {.Text_Plain, .Text_Latex}
    for mode in modes {
        fixture := presentation_test_fixture_create(t)
        defer presentation_test_fixture_destroy(fixture)
        producer := "\\definitelyunsupported{literal} $"
        note := "Valid $x$"
        presentation_test_note(t, fixture, note, false)
        presentation_composition_accept(fixture.presentation, {
            runtime_generation = 3,
            animation_generation = 5,
            presentation_generation = 1,
            animation = fixture.state^.julia_interface^.current_animation,
            content = {mode, transmute([]u8)producer},
        })
        fixture.presentation^.composition.producer_ready = true
        presentation_test_composition_wait(t, fixture)
        testing.expect_value(t, len(fixture.state^.dynview.content.documents), 2)
        presentation_test_document_source(t, fixture, 0, producer)
        presentation_test_document_source(t, fixture, 1, note)
        math_count := 0
        for item in fixture.state^.dynview.content.document_inlines {
            if item.kind == .Math {
                math_count += 1
            }
        }
        testing.expect_value(t, math_count, 1)
    }
}

// Editor input changes cannot mutate the snapshot retained by a running composition parse.
@(test)
presentation_collection_note_parse_borrows_immutable_owner_bytes :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation_test_note(t, fixture, "Before $x$", false)
    presentation_service_composition(fixture.state, fixture.presentation)
    work := &fixture.presentation^.composition.work
    testing.expect_value(t, work^.sources[0], "Before $x$")
    buffer := fixture.state^.animation_memory.note_buffer
    copy(buffer, "After! $y$")
    testing.expect_value(t, work^.sources[0], "Before $x$")
    fixture.state^.ui_runtime.library.collection_note.revision += 1
    presentation_test_composition_wait(t, fixture)
    presentation_test_document_source(t, fixture, 0, "After! $y$")
}

// Reading-order changes replace a composition even when the note source is unchanged.
@(test)
presentation_collection_note_order_invalidates_without_producer_event :: proc(
    t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation_test_note(t, fixture, "Note", false)
    presentation_composition_accept(fixture.presentation, {
        runtime_generation = 3,
        animation_generation = 5,
        presentation_generation = 1,
        animation = fixture.state^.julia_interface^.current_animation,
        content = {.Text_Latex, transmute([]u8)string("Original")},
    })
    fixture.presentation^.composition.producer_ready = true
    presentation_test_composition_wait(t, fixture)
    fixture.state^.ui_runtime.library.collection_note.notes_on_top = true
    fixture.state^.ui_runtime.library.collection_note.revision += 1
    presentation_test_composition_wait(t, fixture)
    presentation_test_document_source(t, fixture, 0, "Note")
    presentation_test_document_source(t, fixture, 1, "Original")
}

// Maximum legal body inputs fit native composition bytes without widening producer limits.
@(test)
presentation_collection_note_composition_capacity_covers_both_inputs :: proc(
    t: ^testing.T) {
    work := new(Presentation_Composition_Work, context.allocator)
    defer free(work, context.allocator)
    producer: [presentation_model.PRESENTATION_MAX_SOURCE_BYTES]u8
    note: [animation_model.ANIMATION_NOTE_BUFFER_CAPACITY]u8
    for &byte in producer[:] {
        byte = 'a'
    }
    for &byte in note[:] {
        byte = 'b'
    }
    work^.has_notes = true
    presentation_composition_append(work, string(producer[:]), .Text_Plain)
    presentation_composition_append(work, string(note[:]), .Text_Latex)
    testing.expect_value(t, work^.count, len(producer)+len(note)+2)
    testing.expect_value(t, len(work^.sources[0]), len(producer))
    testing.expect_value(t, len(work^.sources[1]), len(note))
    testing.expect_value(t, dynviewmodel.DYNVIEW_MAX_TEXT_BYTES, len(work^.bytes))
}

// Typing and changing reading order do not replace the original-only authoring preview.
@(test)
presentation_collection_note_authoring_keeps_original_preview :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation_test_note(t, fixture, "Draft", false)
    note := &fixture.state^.ui_runtime.library.collection_note
    note^.editing = true
    before := presentation_note_revision(fixture.state)
    note^.revision += 1
    note^.notes_on_top = true
    testing.expect_value(t, presentation_note_revision(fixture.state), before)
    note^.editing = false
    testing.expect(t, presentation_note_revision(fixture.state) != before)
}

// Literal bodies at both input ceilings fit a fully validated native snapshot.
@(test)
presentation_collection_note_maximum_bodies_publish :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    producer: [presentation_model.PRESENTATION_MAX_SOURCE_BYTES]u8
    note: [animation_model.ANIMATION_NOTE_BUFFER_CAPACITY]u8
    for &byte in producer[:] {
        byte = 'a'
    }
    for &byte in note[:] {
        byte = 'b'
    }
    work := &fixture.presentation^.composition.work
    presentation_composition_append(work, string(producer[:]), .Text_Plain)
    presentation_composition_append(work, string(note[:]), .Text_Plain)
    bodies: [2]bridge.Presentation_Snapshot_Body = {
        {
            source = work^.sources[0],
        },
        {
            source = work^.sources[1],
        },
    }
    testing.expect(t, bridge.publish_presentation_snapshot(
        fixture.state, fixture.presentation^.staging, {
            content = {
                runtime_generation = 3,
                animation_generation = 5,
                animation = fixture.state^.julia_interface^.current_animation,
                content = {
                    mime = .Text_Latex,
                },
            },
            source = string(work^.bytes[:work^.count]),
            bodies = bodies[:],
        }))
    testing.expect_value(t, len(bridge.current_view_snapshot_text(fixture.state)),
        len(producer)+len(note)+2)
    presentation_test_document_source(t, fixture, 0, string(producer[:]))
    presentation_test_document_source(t, fixture, 1, string(note[:]))
}

// Aggregate record overflow cannot expose a partial body or retire the last valid snapshot.
@(test)
presentation_collection_note_overflow_keeps_previous_snapshot :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation_test_note(t, fixture, "Baseline", false)
    presentation_test_composition_wait(t, fixture)
    bytes: [3000]u8
    for &byte, index in bytes[:] {
        byte = 'a' if index%2 == 0 else ' '
    }
    body: bridge.Presentation_Snapshot_Body = {
        source = string(bytes[:]),
    }
    testing.expect(t, !bridge.publish_presentation_snapshot(
        fixture.state, fixture.presentation^.staging, {
            content = {
                runtime_generation = 3,
                animation_generation = 5,
                animation = fixture.state^.julia_interface^.current_animation,
                content = {
                    mime = .Text_Latex,
                },
            },
            source = body.source,
            bodies = []bridge.Presentation_Snapshot_Body{body},
        }))
    testing.expect_value(t, bridge.current_view_snapshot_text(fixture.state), "Baseline")
    presentation_test_document_source(t, fixture, 0, "Baseline")
}

// Evidence collection remains safe after the Julia interface is detached at shutdown.
@(test)
presentation_collection_note_observation_after_detachment :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, !presentation_note_revision(state).ready)
}

// A preserved producer completion restores retained source after lifecycle retirement.
@(test)
presentation_collection_note_materialization_restores_producer :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    presentation_test_note(t, fixture, "Note", false)
    source := "$$\\frac{a}{b}$$"
    fixture.presentation^.newest_generation = 1
    presentation_materialize(fixture.state, fixture.presentation, {
        content = {
            runtime_generation = 3,
            animation_generation = 5,
            presentation_generation = 1,
            animation = fixture.state^.julia_interface^.current_animation,
            content = {.Text_Latex, transmute([]u8)source},
        },
        source = source,
        mode = .Math,
    })
    presentation_test_composition_wait(t, fixture)
    testing.expect_value(t, len(fixture.state^.dynview.content.documents), 2)
    presentation_test_document_source(t, fixture, 0, source)
    presentation_test_document_source(t, fixture, 1, "Note")
    testing.expect_value(t, fixture.state^.dynview.content.document_blocks[0].kind,
        dynviewmodel.Dynview_Document_Block_Kind.Display)
}

// Malformed note syntax falls back without preventing the producer's valid math import.
@(test)
presentation_collection_note_rejection_keeps_producer_math :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    note := "\\notrecognized{"
    producer := "Original $x$"
    presentation_test_note(t, fixture, note, true)
    presentation_composition_accept(fixture.presentation, {
        runtime_generation = 3,
        animation_generation = 5,
        presentation_generation = 1,
        animation = fixture.state^.julia_interface^.current_animation,
        content = {.Text_Latex, transmute([]u8)producer},
    })
    fixture.presentation^.composition.producer_ready = true
    presentation_test_composition_wait(t, fixture)
    testing.expect_value(t, len(fixture.state^.dynview.content.documents), 2)
    presentation_test_document_source(t, fixture, 0, note)
    presentation_test_document_source(t, fixture, 1, producer)
    math_count := 0
    for item in fixture.state^.dynview.content.document_inlines {
        if item.kind == .Math {
            math_count += 1
        }
    }
    testing.expect_value(t, math_count, 1)
}
