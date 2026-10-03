#+test
package ui

import app_core "../../core"
import contentdata "../../core/content"
import view_core "../core"
import "core:testing"

// Allocate a stable complete content owner behind ordinary shell consumers.
make_shell_test_state :: proc(t: ^testing.T) -> ^app_core.Euclid_General_State {
    state := new(app_core.Euclid_General_State, context.allocator)
    service := new(contentdata.Content_Service, context.allocator)
    service.active_generation = contentdata.content_message_test_generation(t)
    service.running = true
    service.index_generation = service.active_generation.generation
    state.content_service = service
    return state
}

// Release synthetic service ownership without attempting to join a nonexistent worker.
destroy_shell_test_state :: proc(state: ^app_core.Euclid_General_State) {
    contentdata.content_message_test_destroy(state.content_service.active_generation)
    free(state.content_service, context.allocator)
    free(state, context.allocator)
}

// Cached labels and owned status copies survive content retirement without escaped pointers.
@(test)
shell_message_copies_survive_generation_retirement :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    label := view_core.shell_message(state, .Navigation_Library)
    view_core.set_gif_status_note(&state.ui_runtime,
        view_core.shell_message(state, .Gif_Error_Finalize))
    generation := state.content_service.active_generation
    testing.expect_value(t, contentdata.content_generation_reset(generation),
        contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, label, "Library")
    testing.expect_value(t,
        string(state.ui_runtime.gif_status_note[:state.ui_runtime.gif_status_note_len]),
        "Error: failed to finalize GIF file.")
}

// Alternate admitted prose reaches both layouts and semantic controls, not literal fallbacks.
@(test)
shell_message_consumers_use_generation_prose :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    generation := state.content_service.active_generation
    reference := generation.data.translations[0].template
    copy(generation.text_bytes[reference.offset:reference.offset + reference.length], "Changed")
    landscape := accordion_landscape_sections(state)
    portrait := accordion_portrait_sections("", state)
    testing.expect_value(t, landscape.items[0].label, "Changed")
    testing.expect_value(t, portrait.items[1].label, "Changed")
    testing.expect_value(t, portrait.items[0].label, "Animation")
    params := library_search_input_params(state, {}, {}, {})
    testing.expect_value(t, params.descriptor.label, "Search animations")
}
