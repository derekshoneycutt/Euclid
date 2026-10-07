package view

import "../core"
import viewmodel "model"
import "ui"
import "input"
import terminalview "terminal"
import termemulator "../terminal/emulator"
import "core:log"

// execute_context_menu_paste uses the same bounded owner paths as keyboard paste.
execute_context_menu_paste :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime) {
    if !ui.context_menu_paste_available(state) {
        log.warn("context_menu_paste_rejected reason=input_unavailable")
        return
    }
    text, read := input.input_read_clipboard_text()
    if !read || len(text) == 0 {
        return
    }
    accepted := false
    if state^.shell.phase == .Running && runtime != nil {
        _ = input.input_runtime_set_owner(runtime, {
            kind = .Terminal_Session,
            id = u64(state^.shell.operation_id.slot),
            generation = state^.shell.operation_id.generation})
        mode := termemulator.interpreter_input_mode(&state^.terminal.output_interpreter)
        accepted = input.input_terminal_enqueue_paste(runtime, text, mode.bracketed_paste)
    } else if state^.shell.phase == .Inactive {
        accepted = terminalview.terminal_insert_clipboard_text(&state^.terminal, text)
    }
    if !accepted {
        log.warn("context_menu_paste_rejected reason=admission")
    }
}

// execute_context_menu_command revalidates the retained target before owner mutation.
execute_context_menu_command :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime) {
    menu := &state^.ui_runtime.context_menu
    command := menu^.pending
    menu^.pending = .None
    if command == .None {
        return
    }
    if !ui.context_menu_target_valid(state) {
        log.warn("context_menu_command_rejected reason=stale_target")
        return
    }
    if menu^.target.domain == .Presentation {
        ui.context_menu_execute_presentation(state, command)
        return
    }
    if command == viewmodel.Ui_Context_Command.Paste {
        execute_context_menu_paste(state, runtime)
    } else if command == .Copy {
        if !terminalview.terminal_copy_view_selection(&state^.terminal) {
            log.warn("context_menu_copy_rejected")
        }
    }
}
