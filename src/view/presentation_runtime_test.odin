package view

import bridge "../bridge"
import "../core"
import "../taskpool"

import "base:runtime"
import "core:testing"
import "core:thread"

// Presentation_Test_Fixture owns the heap-backed state used by Phase 4 tests.
Presentation_Test_Fixture :: struct {
    state: ^core.Euclid_General_State,
    service: ^core.Julia_Runtime_Service,
    presentation: ^Presentation_Runtime,
}

//   Allocate the minimal typed state needed to exercise presentation admission.
presentation_test_fixture_create :: proc(t: ^testing.T) -> Presentation_Test_Fixture {
    state := new(core.Euclid_General_State, context.allocator)
    service := new(core.Julia_Runtime_Service, context.allocator)
    presentation := create_presentation_runtime()
    testing.expect(t, state != nil && service != nil && presentation != nil)
    link_error := bridge.communication_link_init(
        &service^.event_link, bridge.JULIA_EVENT_CAPACITY,
        bridge.JULIA_EVENT_LINK_POOL_CAPACITY)
    testing.expect_value(t, link_error, runtime.Allocator_Error.None)
    state^.julia_runtime_service = service
    state^.julia_interface = new(core.Euclid_Julia_Interface, context.allocator)
    state^.simulation_executor = new(core.Simulation_Executor, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    testing.expect(t, core.animation_storage_init(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents))
    testing.expect_value(t, core.animation_storage_begin_generation(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents, 3), core.Animation_Memory_Status.Ok)
    testing.expect(t, taskpool.task_pool_init(
        &state^.simulation_executor^.pool, 1, 2))
    testing.expect(t, bridge.view_snapshot_slots_init(service))
    service^.runtime_generation = 3
    service^.animation_generation = 5
    service^.lifecycle = .Ready
    service^.reload_state = .Idle
    service^.published_view_snapshot_index = 0
    service^.view_snapshots[0].state = .Published
    state^.dynview.content.commands = []core.Dynview_Command{{kind = .Divider}}
    return {state = state, service = service, presentation = presentation}
}

//   Release all test-owned transport and runtime storage after returned envelopes drain.
presentation_test_fixture_destroy :: proc(
    fixture: Presentation_Test_Fixture) {
    state := fixture.state
    service := fixture.service
    presentation := fixture.presentation
    quiesce_presentation_runtime(state, presentation)
    for {
        message, returned := bridge.communication_link_try_take_return(
            &service^.event_link)
        if !returned {
            break
        }
        free(message)
    }
    destroy_presentation_runtime(presentation)
    taskpool.task_pool_destroy(&state^.simulation_executor^.pool)
    free(state^.simulation_executor)
    bridge.view_snapshot_slots_destroy(service)
    bridge.communication_link_destroy(&service^.event_link)
    core.animation_storage_destroy(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents)
    free(state^.julia_interface)
    free(service)
    free(state)
}

//   Allocate one test envelope whose source bytes outlive presentation admission.
presentation_test_message :: proc(
    state: ^core.Euclid_General_State,
    generation: u64,
    bytes: []u8) -> ^core.Julia_Host_Egress {
    message := new(core.Julia_Host_Egress, context.allocator)
    message^ = core.Julia_Host_Egress(core.View_Content_Ready{
        runtime_generation = 3,
        animation_generation = 5,
        presentation_generation = generation,
        animation = state^.julia_interface^.current_animation,
        content = {mime = .Text_Latex, bytes = bytes},
    })
    return message
}

//   Compare exact bytes without treating embedded zero as a terminator.
presentation_test_bytes_equal :: proc(left, right: []u8) -> bool {
    if len(left) != len(right) {
        return false
    }
    for value, index in left {
        if value != right[index] {
            return false
        }
    }
    return true
}

//   Advance nonblocking polls until one test operation joins or the bound expires.
presentation_test_wait_for_idle :: proc(
    state: ^core.Euclid_General_State,
    presentation: ^Presentation_Runtime) {
    for _ in 0..<100000 {
        presentation_poll_active(state, presentation)
        if !presentation^.active.submitted {
            return
        }
        thread.yield()
    }
}

//   Verify literal staging preserves embedded zero bytes for visible text.
@(test)
presentation_literal_staging_preserves_exact_bytes :: proc(t: ^testing.T) {
    staging := new(core.Dynview_System, context.allocator)
    defer free(staging)
    staging^.enabled = true
    source_bytes := []u8{'a', 0, '\\', 'b'}
    source := transmute(string)source_bytes

    testing.expect(t, bridge.stage_presentation_snapshot(
        staging, {source = source, mode = .Plain}))
    testing.expect_value(t, staging^.command_buffer.command_count, 3)
    text_command := staging^.command_buffer.commands[1]
    testing.expect_value(t, text_command.kind, core.Dynview_Command_Kind.Text_Run)
    testing.expect(t, presentation_test_bytes_equal(
        staging^.command_buffer.text_bytes[
            text_command.text_offset:text_command.text_offset+text_command.text_len],
        source_bytes))
}

//   Verify admission retains only the newest message and clears published aliases.
@(test)
presentation_admission_is_bounded_and_clears_visible_state :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    first_bytes := []u8{'$', 'x', '$'}
    second_bytes := []u8{'$', 'y', '$'}
    first := presentation_test_message(state, 11, first_bytes)
    second := presentation_test_message(state, 12, second_bytes)

    first_content, _ := first^.(core.View_Content_Ready)
    presentation_admit(state, presentation, first, first_content)
    testing.expect(t, presentation^.pending == first)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)

    second_content, _ := second^.(core.View_Content_Ready)
    presentation_admit(state, presentation, second, second_content)
    testing.expect(t, presentation^.pending == second)
    testing.expect_value(t, presentation^.newest_generation, u64(12))
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == first)
    free(returned)
}

//   Verify a miss publishes after poll/join and its exact repeat uses the cache.
@(test)
presentation_parse_miss_then_cache_hit_publishes :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    source_bytes := []u8{'$', 'x', '^', '2', '$'}
    first := presentation_test_message(state, 21, source_bytes)
    first_content, _ := first^.(core.View_Content_Ready)
    presentation_admit(state, presentation, first, first_content)
    presentation_start_pending(state, presentation)
    testing.expect(t, presentation^.active.submitted)

    presentation_test_wait_for_idle(state, presentation)
    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    testing.expect(t, state^.dynview.compile_cache.math_program_count > 0)
    returned, first_returned := bridge.communication_link_try_take_return(
        &service^.event_link)
    testing.expect(t, first_returned && returned == first)
    free(returned)

    second := presentation_test_message(state, 22, source_bytes)
    second_content, _ := second^.(core.View_Content_Ready)
    presentation_admit(state, presentation, second, second_content)
    presentation_start_pending(state, presentation)
    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, presentation^.pending == nil)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    second_returned: bool
    returned, second_returned = bridge.communication_link_try_take_return(
        &service^.event_link)
    testing.expect(t, second_returned && returned == second)
    free(returned)
}

//   Verify a current rejected document publishes its exact source as visible text.
@(test)
presentation_rejected_tex_publishes_exact_literal :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    source_bytes := []u8{'\\', 't', 'e', 'x', 't', 'b', 'f', '{', 'x'}
    message := presentation_test_message(state, 31, source_bytes)
    content, _ := message^.(core.View_Content_Ready)
    presentation_admit(state, presentation, message, content)
    presentation_start_pending(state, presentation)
    presentation_test_wait_for_idle(state, presentation)

    testing.expect(t, !presentation^.active.submitted)
    testing.expect(t, service^.published_view_snapshot_index >= 0)
    commands := state^.dynview.content.commands
    testing.expect_value(t, len(commands), 3)
    literal := commands[1]
    testing.expect_value(t, literal.kind, core.Dynview_Command_Kind.Text_Run)
    testing.expect_value(t, state^.dynview.content.presentation_mime,
        core.Presentation_Mime.Text_Latex)
    testing.expect(t, presentation_test_bytes_equal(
        state^.dynview.content.presentation_bytes, source_bytes))
    testing.expect(t, presentation_test_bytes_equal(
        state^.dynview.content.text_bytes[
            literal.text_offset:literal.text_offset+literal.text_len],
        source_bytes))
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == message)
    free(returned)
}

//   Verify a lifecycle generation change clears content and retires stale parse work.
@(test)
presentation_lifecycle_change_cancels_stale_parse :: proc(t: ^testing.T) {
    fixture := presentation_test_fixture_create(t)
    defer presentation_test_fixture_destroy(fixture)
    state, service, presentation :=
        fixture.state, fixture.service, fixture.presentation
    presentation_sync_lifecycle(state, presentation)
    source_bytes := []u8{'$', '\\', 'f', 'r', 'a', 'c', '{', '1', '}', '{', '2', '}', '$'}
    message := presentation_test_message(state, 41, source_bytes)
    content, _ := message^.(core.View_Content_Ready)
    presentation_admit(state, presentation, message, content)
    presentation_start_pending(state, presentation)
    testing.expect(t, presentation^.active.submitted)

    service^.animation_generation += 1
    presentation_sync_lifecycle(state, presentation)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)
    testing.expect(t, presentation^.active.cancellation_requested)
    testing.expect_value(t, presentation^.newest_generation, 0)
    presentation_test_wait_for_idle(state, presentation)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    returned, ok := bridge.communication_link_try_take_return(&service^.event_link)
    testing.expect(t, ok && returned == message)
    free(returned)
}