package dynview_core

import app_core "../../core"

import "core:testing"

//   Verify command and text views prefer immutable publication over staging.
@(test)
command_buffer_views_prefer_published_content :: proc(t: ^testing.T) {
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    buffer^.command_count = 1
    buffer^.commands[0] = {block_id = 3}
    copy(buffer^.text_bytes[:], "stage")
    buffer^.text_bytes_len = 5

    testing.expect_value(t, command_buffer_commands(buffer)[0].block_id, i32(3))
    testing.expect_value(t, string(command_buffer_text(buffer)), "stage")

    commands := [1]app_core.Dynview_Command{{block_id = 7}}
    published_text: string = "view"
    buffer^.command_view = commands[:]
    buffer^.text_view = transmute([]u8)published_text

    testing.expect_value(t, raw_data(command_buffer_commands(buffer)),
        raw_data(buffer^.command_view))
    testing.expect_value(t, raw_data(command_buffer_text(buffer)),
        raw_data(buffer^.text_view))
}

//   Verify bounded-builder outcomes map to the stable compile status surface.
@(test)
compiled_builder_status_maps_all_builder_outcomes :: proc(t: ^testing.T) {
    testing.expect_value(t, compiled_builder_status(.Ok), DYNVIEW_STATUS_OK)
    testing.expect_value(t, compiled_builder_status(.Limit_Exceeded),
        DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, compiled_builder_status(.Allocation_Failed),
        DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, compiled_builder_status(.Invalid_Argument),
        DYNVIEW_STATUS_ILLEGAL_STATE)
    testing.expect_value(t, compiled_builder_status(.Sealed),
        DYNVIEW_STATUS_ILLEGAL_STATE)
}