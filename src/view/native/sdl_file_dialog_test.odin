#+test
package native

import "core:testing"
import "core:thread"

Sdl_File_Dialog_Test_Callback :: struct {
    dialog: ^Sdl_File_Dialog,
    path: cstring,
}

// Invoke one SDL-style completion callback from a secondary thread.
sdl_file_dialog_test_callback_worker :: proc(worker: ^thread.Thread) {
    callback := cast(^Sdl_File_Dialog_Test_Callback)worker.data
    files: [2]cstring = {callback^.path, nil}
    sdl_file_dialog_callback(rawptr(callback^.dialog), &files[0], -1)
}

// Verify one active request, cross-thread path ownership, and poll clearing.
@(test)
sdl_file_dialog_test_chosen_path_is_owned_and_poll_clears :: proc(t: ^testing.T) {
    dialog := new(Sdl_File_Dialog, context.allocator)
    defer free(dialog, context.allocator)
    testing.expect_value(t, sdl_file_dialog_reserve(dialog, "/tmp"),
        Sdl_File_Dialog_Start_Result.Started)
    testing.expect_value(t, sdl_file_dialog_reserve(dialog, "/tmp/again"),
        Sdl_File_Dialog_Start_Result.Busy)
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Pending)

    path: [17]u8 = {
        '/', 't', 'm', 'p', '/', 's', 'h', 'a', 'r', 'e', '.',
        'e', 'u', 'c', 'l', 'i', 'd',
    }
    terminated: [18]u8
    copy(terminated[:], path[:])
    terminated[17] = 0
    callback: Sdl_File_Dialog_Test_Callback = {
        dialog = dialog,
        path = cstring(&terminated[0]),
    }
    worker := thread.create(sdl_file_dialog_test_callback_worker)
    testing.expect(t, worker != nil)
    if worker == nil {
        return
    }
    worker.data = &callback
    thread.start(worker)
    thread.join(worker)
    thread.destroy(worker)
    terminated[0] = 'x'

    result := sdl_file_dialog_poll(dialog)
    testing.expect_value(t, result.kind, Sdl_File_Dialog_Result_Kind.Chosen)
    testing.expect_value(t, result.path_length, 17)
    testing.expect_value(t, string(result.path[:result.path_length]),
        "/tmp/share.euclid")
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Idle)
}

// Verify cancellation and native callback errors become distinct poll results.
@(test)
sdl_file_dialog_test_cancel_and_failure_results :: proc(t: ^testing.T) {
    dialog := new(Sdl_File_Dialog, context.allocator)
    defer free(dialog, context.allocator)

    testing.expect_value(t, sdl_file_dialog_reserve(dialog, ""),
        Sdl_File_Dialog_Start_Result.Started)
    no_files: [1]cstring = {nil}
    sdl_file_dialog_callback(rawptr(dialog), &no_files[0], -1)
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Cancelled)

    testing.expect_value(t, sdl_file_dialog_reserve(dialog, ""),
        Sdl_File_Dialog_Start_Result.Started)
    sdl_file_dialog_callback(rawptr(dialog), nil, -1)
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Failed)
}

// Verify path length boundaries reject truncation and accept the exact capacity.
@(test)
sdl_file_dialog_test_path_capacity_is_exact :: proc(t: ^testing.T) {
    dialog := new(Sdl_File_Dialog, context.allocator)
    defer free(dialog, context.allocator)
    path: [SDL_FILE_DIALOG_PATH_CAPACITY + 1]u8
    for index in 0..<SDL_FILE_DIALOG_PATH_CAPACITY {
        path[index] = 'x'
    }
    path[SDL_FILE_DIALOG_PATH_CAPACITY] = 0
    files: [2]cstring = {cstring(&path[0]), nil}

    testing.expect_value(t, sdl_file_dialog_reserve(dialog, ""),
        Sdl_File_Dialog_Start_Result.Started)
    sdl_file_dialog_callback(rawptr(dialog), &files[0], -1)
    result := sdl_file_dialog_poll(dialog)
    testing.expect_value(t, result.kind, Sdl_File_Dialog_Result_Kind.Chosen)
    testing.expect_value(t, result.path_length, SDL_FILE_DIALOG_PATH_CAPACITY)

    path[SDL_FILE_DIALOG_PATH_CAPACITY] = 'x'
    testing.expect_value(t, sdl_file_dialog_reserve(dialog, ""),
        Sdl_File_Dialog_Start_Result.Started)
    sdl_file_dialog_callback(rawptr(dialog), &files[0], -1)
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Failed)
}

// Reject invalid default locations before opening the dialog state machine.
@(test)
sdl_file_dialog_test_rejects_invalid_locations :: proc(t: ^testing.T) {
    dialog := new(Sdl_File_Dialog, context.allocator)
    defer free(dialog, context.allocator)
    testing.expect_value(t, sdl_file_dialog_reserve(dialog, "bad\x00path"),
        Sdl_File_Dialog_Start_Result.Invalid_Request)
    oversized: [SDL_FILE_DIALOG_LOCATION_CAPACITY + 1]u8
    for &byte in oversized[:] {
        byte = 'x'
    }
    testing.expect_value(t,
        sdl_file_dialog_reserve(dialog, string(oversized[:])),
        Sdl_File_Dialog_Start_Result.Invalid_Request)
    testing.expect_value(t, sdl_file_dialog_poll(dialog).kind,
        Sdl_File_Dialog_Result_Kind.Idle)
}
