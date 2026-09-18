package view

import "../core"
import "../taskpool"
import viewgraphics "graphics"

import "core:time"

// Unbind one Terminal generation through the opaque core lifecycle capability.
terminal_graphics_release_callback :: proc(
    user_data: rawptr, pool: ^taskpool.Task_Pool) {
    viewgraphics.service_unbind_session(cast(^viewgraphics.Service)user_data, pool)
}

// Permanently stop terminal graphics through the opaque core lifecycle capability.
terminal_graphics_shutdown_callback :: proc(
    user_data: rawptr, pool: ^taskpool.Task_Pool) {
    viewgraphics.service_shutdown(cast(^viewgraphics.Service)user_data, pool)
}

// Allocate the reusable display-owned graphics service.
terminal_graphics_runtime_init :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.terminal_graphics_user_data != nil {
        return false
    }
    service := new(viewgraphics.Service, context.allocator)
    if service == nil {
        return false
    }
    state^.terminal_graphics_user_data = service
    state^.terminal_graphics_release = terminal_graphics_release_callback
    state^.terminal_graphics_shutdown = terminal_graphics_shutdown_callback
    return true
}

// Bind one fresh Terminal generation to its parser and attachment store.
terminal_graphics_bind_generation :: proc(
    state: ^core.Euclid_General_State, generation: u64) -> bool {
    if state == nil || generation == 0 {
        return false
    }
    if state^.terminal_graphics_user_data == nil {
        state^.terminal.raster_renderer = {}
        return true
    }
    service := cast(^viewgraphics.Service)state^.terminal_graphics_user_data
    if !viewgraphics.service_bind_session(
        service, generation,
        state^.terminal.output_interpreter.title_state.graphics,
        state^.terminal.synchronized_output.attachments,
        &state^.evidence_ring) {
        return false
    }
    state^.terminal.raster_renderer = viewgraphics.service_renderer(service)
    return true
}

// Advance terminal graphics preparation, publication, and playback once per frame.
terminal_graphics_update :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.simulation_executor == nil ||
       state^.terminal_graphics_user_data == nil {
        return
    }
    viewgraphics.service_update(
        cast(^viewgraphics.Service)state^.terminal_graphics_user_data,
        &state^.simulation_executor^.pool, u64(time.tick_since({})))
}

// Stop and release the reusable graphics service before its taskpool owner.
terminal_graphics_runtime_destroy :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.terminal_graphics_user_data == nil {
        return
    }
    service := cast(^viewgraphics.Service)state^.terminal_graphics_user_data
    if state^.simulation_executor != nil {
        viewgraphics.service_shutdown(service, &state^.simulation_executor^.pool)
    }
    free(service, context.allocator)
    state^.terminal_graphics_user_data = nil
    state^.terminal_graphics_release = nil
    state^.terminal_graphics_shutdown = nil
}