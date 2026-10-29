package app

import core "../core"
import view "../view"
import inputbackend "../view/input/backend"
import c "core:c"
import log "core:log"
import runtime "base:runtime"
import sdl "vendor:sdl3"

// Desktop_Application outlives every SDL callback, including events concurrent with AppQuit.
Desktop_Application :: struct {
    window: view.Window_Session,
    callback_context: runtime.Context,
    cleanup_result: int,
    callback_limit: bool,
}

// Only AppInit reads this early handoff; RunApp is entered once on the process main thread.
desktop_bootstrap: ^Desktop_Application

// run_desktop_application keeps borrowed launch/store inputs alive until SDL has fully shut down.
run_desktop_application :: proc(
    settings: ^core.Euclid_Run_Settings, startup: ^view.Session_Startup_Inputs) -> int {
    if desktop_bootstrap != nil {
        log.error("desktop_callback_runner_already_active")
        return 1
    }
    owner := new(Desktop_Application, context.allocator)
    defer free(owner, context.allocator)
    owner^.window.settings = settings^
    owner^.window.startup_inputs = startup^
    owner^.callback_context = context
    desktop_bootstrap = owner
    defer desktop_bootstrap = nil
    result := int(sdl.RunApp(0, nil, desktop_sdl_main, nil))
    if result != 0 {
        return result
    }
    return owner^.cleanup_result
}

// desktop_sdl_main is SDL's foreign-language main trampoline, not an initialized window loop.
desktop_sdl_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
    return sdl.EnterAppMainCallbacks(
        argc, argv, desktop_init, desktop_iterate, desktop_event, desktop_quit)
}

// desktop_init restores the process context before admitting callback-owned display resources.
desktop_init :: proc "c" (
    appstate: ^rawptr, _: c.int, _: [^]cstring) -> sdl.AppResult {
    owner := desktop_bootstrap
    appstate^ = owner
    context = owner^.callback_context
    desktop_update_pacing(owner, true)
    if !view.window_session_begin(&owner^.window) {
        owner^.window.failed = true
        log.error("display_callback_init_failed")
        return .FAILURE
    }
    return .CONTINUE
}

// desktop_result converts owner step outcomes without losing runtime failures.
desktop_result :: proc(running, succeeded: bool) -> sdl.AppResult {
    if !succeeded {
        return .FAILURE
    }
    return .CONTINUE if running else .SUCCESS
}

// desktop_iterate enters one guarded startup or ready-state iteration on the display owner.
desktop_iterate :: proc "c" (appstate: rawptr) -> sdl.AppResult {
    owner := cast(^Desktop_Application)appstate
    context = owner^.callback_context
    limited := !owner^.window.ready || owner^.window.drawable_unavailable ||
        owner^.window.runtime.state^.ui_runtime.rendering.limit_fps
    desktop_update_pacing(owner, limited)
    running, succeeded := view.window_session_step(&owner^.window)
    if !succeeded {
        owner^.window.failed = true
        log.error("display_callback_iteration_failed")
    }
    return desktop_result(running, succeeded)
}

// desktop_update_pacing asks SDL to pace callbacks; the display deadline also covers ignored hints.
desktop_update_pacing :: proc(owner: ^Desktop_Application, limited: bool) {
    if owner^.callback_limit == limited {
        return
    }
    owner^.callback_limit = limited
    rate: cstring = "60" if limited else "0"
    if !sdl.SetHint(sdl.HINT_MAIN_CALLBACK_RATE, rate) {
        log.warn("sdl_callback_rate_hint_rejected")
    }
}

// desktop_event copies bounded input only; SDL may invoke it on a non-display thread.
desktop_event :: proc "c" (appstate: rawptr, event: ^sdl.Event) -> sdl.AppResult {
    owner := cast(^Desktop_Application)appstate
    if !inputbackend.sdl_event_inbox_push(&owner^.window.events, event) {
        return .FAILURE
    }
    return .CONTINUE
}

// desktop_quit closes event admission and releases native owners before SDL's final global quit.
desktop_quit :: proc "c" (appstate: rawptr, result: sdl.AppResult) {
    owner := cast(^Desktop_Application)appstate
    if owner == nil {
        return
    }
    context = owner^.callback_context
    if inputbackend.sdl_event_inbox_failed(&owner^.window.events) {
        log.error("sdl_callback_event_handoff_failed")
    }
    inputbackend.sdl_event_inbox_close(&owner^.window.events)
    owner^.window.failed = owner^.window.failed || result == .FAILURE
    owner^.cleanup_result = view.window_session_destroy(&owner^.window)
    free_all(context.temp_allocator)
}
