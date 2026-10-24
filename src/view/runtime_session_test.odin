package view

import core "../core"
import dynviewmodel "../dynview/model"
import input "input"
import uilibrary "ui/library"
import termhist "../terminal/history"
import testing "core:testing"

// Verify losing the editable owner cancels hidden preedit without changing source.
@(test)
runtime_text_owner_retirement_clears_hidden_compositions :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.terminal.history = &state^.terminal.history_storage
    state^.terminal.history.preedit_active = true
    state^.ui_runtime.library.search.input.preedit_active = true
    state^.ui_runtime.library.entry_name.input.preedit_active = true
    state^.ui_runtime.gif_path_input.preedit_active = true
    sdl_frame_retire_preedit(state, {
        kind = .Input_Box, id = uilibrary.LIBRARY_SEARCH_INPUT_ID,
    })
    testing.expect(t, state^.ui_runtime.library.search.input.preedit_active)
    testing.expect(t, !state^.ui_runtime.library.entry_name.input.preedit_active)
    testing.expect(t, !state^.ui_runtime.gif_path_input.preedit_active)
    testing.expect(t, !state^.terminal.history.preedit_active)
    sdl_frame_retire_preedit(state, {})
    testing.expect(t, !sdl_frame_composition_active(state))
    testing.expect_value(t, termhist.termhist_current_text(state^.terminal.history), "")
}

// Verify fixed runtime children and input history remain in the stable state root.
@(test)
runtime_session_fixed_children_are_root_owned :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    settings := core.Euclid_Run_Settings{
        dust_particle_max = 1024,
        window = {width = 800, height = 600, layout = .Landscape},
    }

    initialized := init_animations_state_resources(state, nil, &settings)
    testing.expect(t, initialized)
    if !initialized {
        return
    }

    testing.expect(t, state^.iso_scale.scale > 0)
    testing.expect(t, state^.draw_surface.edge_size > 0)
    testing.expect(t, state^.shape_world.transforms.count > 0)
    testing.expect(t, state^.particle_system.use_max_dust_particles == 1024)
    testing.expect(t,
        state^.ui_runtime.semantic_focus == &state^.semantic_focus)

    input_runtime := &state^.input_runtime
    current, changed := input.input_runtime_update_window_focus(input_runtime, true)
    testing.expect(t, current && !changed)
    testing.expect(t, input_runtime.window_focused)
    state^.fixed_step += 1
    testing.expect(t, state^.input_runtime.window_focused)
}

// Ensure a terminal-owner startup failure stops simulation work before root teardown.
@(test)
runtime_executor_failure_releases_task_owner :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    sentinel: u8
    state^.terminal_graphics_user_data = cast(rawptr)&sentinel

    initialized := init_runtime_executors(state)
    testing.expect(t, !initialized)
    testing.expect(t, state^.simulation_executor == nil)
    testing.expect_value(t, state^.dynview.cache_access_state,
        dynviewmodel.Dynview_Cache_Access_State.Uninitialized)
}
