#+test
package view

import core "../core"
import geometry "../core/geometry"
import input "input"
import uilibrary "ui/library"
import viewmodel "ui/model"
import uisemantics "ui/semantics"
import uiterminal "ui/terminal"
import termhist "../terminal/history"
import viewmagnifier "magnifier"
import testing "core:testing"

// Native collection-name eligibility uses qualified semantic focus, not a local-ID alias.
@(test)
sdl_text_input_collection_name_qualified_focus :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    editor: viewmodel.Ui_Node_Id = {
        domain = .Library_Action,
        local_id = uilibrary.TREE_ENTRY_NAME_INPUT,
        generation = 7,
    }
    editor.stable_id[0] = 42
    testing.expect(t, uisemantics.semantic_begin(semantic))
    for index in 0..<2 {
        id := editor
        id.stable_id[0] += u8(index)
        testing.expect_value(t, uisemantics.semantic_register_control(semantic, {
            id = id,
            role = .Input,
            states = {.Visible, .Enabled, .Focusable},
            bounds = {0, 0, 200, 30},
            clip_bounds = {0, 0, 200, 30},
            text_input_area = {f32(index + 10), 2, 1, 20},
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, uisemantics.semantic_publish(semantic),
        viewmodel.Ui_Semantic_Status.Ok)
    semantic^.logical_focus = editor
    state^.ui_runtime.input.interaction_frame.effective_focus = {
        kind = .Input_Box,
        id = uilibrary.TREE_ENTRY_NAME_INPUT_ID,
    }
    sdl_text_input_test_name_target(t, state)
}

// Terminal lock uses the current editable caret and its prepared visible clip.
@(test)
sdl_text_input_terminal_caret_target :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    history: termhist.Termhist_State
    state^.terminal.history = &history
    state^.ui_runtime.input.interaction_frame.effective_focus = {
        kind = .Terminal,
        id = 1,
    }
    terminal_frame: uiterminal.Terminal_Prepared_Frame = {
        available = true,
        editable_descriptor = {
            mode = .Editable,
        },
        editable_geometry = {
            control = {
                clip_bounds = {20, 30, 200, 120},
            },
            caret = {80, 90, 2, 20},
        },
    }
    target := sdl_frame_resolve_text_input_target(state, true, terminal_frame)
    testing.expect_value(t, target.kind, input.Input_Text_Target_Kind.Terminal)
    testing.expect_value(t, target.area, geometry.Rectangle{80, 90, 2, 20})
    testing.expect_value(t, target.clip_bounds, geometry.Rectangle{20, 30, 200, 120})

    locked := viewmagnifier.magnifier_prepare(
        &state^.ui_runtime.magnifier, {
            enabled = true,
            input_lock = true,
            caret_anchor = target.area,
            caret_clip = target.clip_bounds,
            caret_valid = target.kind != .None,
            window_focused = true,
            width = 320,
            height = 240,
        })
    testing.expect(t, locked.visible)
    testing.expect_value(t, locked.source, geometry.Vector2{81, 100})
}

// Resolve only the focused enabled mutable node and stop native input on blur or retirement.
sdl_text_input_test_name_target :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    semantic := state^.ui_runtime.semantic_focus
    target := sdl_frame_resolve_text_input_target(state, true, {})
    testing.expect_value(t, target.kind, input.Input_Text_Target_Kind.Input_Box)
    testing.expect_value(t, target.id, uilibrary.TREE_ENTRY_NAME_INPUT_ID)
    testing.expect_value(t, target.area, geometry.Rectangle{10, 2, 1, 20})
    testing.expect_value(t, target.clip_bounds, geometry.Rectangle{0, 0, 200, 30})
    locked := viewmagnifier.magnifier_prepare(
        &state^.ui_runtime.magnifier, {
            enabled = true,
            input_lock = true,
            caret_anchor = target.area,
            caret_clip = target.clip_bounds,
            caret_valid = target.kind != .None,
            window_focused = true,
            width = 320,
            height = 240,
        })
    testing.expect(t, locked.visible)
    testing.expect_value(t, locked.source, geometry.Vector2{10.5, 12})
    semantic^.logical_focus.stable_id[0] += 1
    target = sdl_frame_resolve_text_input_target(state, true, {})
    testing.expect_value(t, target.area, geometry.Rectangle{11, 2, 1, 20})
    snapshot := uisemantics.semantic_snapshot(semantic)
    snapshot^.nodes[1].states += {.Read_Only}
    testing.expect_value(t, sdl_frame_resolve_text_input_target(state, true, {}).kind,
        input.Input_Text_Target_Kind.None)
    snapshot^.nodes[1].states -= {.Read_Only, .Enabled}
    testing.expect_value(t, sdl_frame_resolve_text_input_target(state, true, {}).kind,
        input.Input_Text_Target_Kind.None)
    snapshot^.nodes[1].states += {.Enabled}
    testing.expect_value(t, sdl_frame_resolve_text_input_target(state, false, {}).kind,
        input.Input_Text_Target_Kind.None)
    semantic^.logical_focus.generation += 1
    testing.expect_value(t, sdl_frame_resolve_text_input_target(state, true, {}).kind,
        input.Input_Text_Target_Kind.None)
}
