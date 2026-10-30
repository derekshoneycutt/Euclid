package app

import testing "core:testing"
import sdl "vendor:sdl3"

// Verify the argv prefix retains its owner without replacing valid C argument strings.
@(test)
desktop_callback_entry_owner_handoff :: proc(t: ^testing.T) {
    owner := new(Desktop_Application, context.allocator)
    defer free(owner, context.allocator)
    entry: Desktop_Entry = {
        arguments = {"Euclid", nil},
        application = owner,
    }
    argv := raw_data(entry.arguments[:])
    received := cast(^Desktop_Entry)argv
    testing.expect_value(t, received^.application, owner)
    testing.expect_value(t, string(argv[0]), "Euclid")
    testing.expect(t, argv[1] == nil)
}

// Verify close/scenario success and startup/runtime failure map to distinct SDL outcomes.
@(test)
desktop_callback_result_mapping :: proc(t: ^testing.T) {
    testing.expect_value(t, desktop_result(true, true), sdl.AppResult.CONTINUE)
    testing.expect_value(t, desktop_result(false, true), sdl.AppResult.SUCCESS)
    testing.expect_value(t, desktop_result(false, false), sdl.AppResult.FAILURE)
    testing.expect_value(t, desktop_result(true, false), sdl.AppResult.FAILURE)
}
