#+test
package taskpool

import "core:mem"
import "core:os"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

Task_Test_Payload :: struct {
    input : int,
    output : int,
    executed : bool,
    fail : bool,
    execution_count : int,
    thread_id : int,
}

Task_Test_Stopped_Observation :: struct {
    blocker : Task_Handle,
    protected : Task_Handle,
    release_signal : Task_Handle,
    protected_payload : ^Task_Test_Payload,
    owner_id : int,
}

Task_Test_Gate :: struct {
    mutex : sync.Mutex,
    changed : sync.Cond,
    worker_started : bool,
    worker_released : bool,
    release_requested : bool,
}

// Compute one isolated test result without touching pool or application state.
task_test_execute :: proc(
    payload: rawptr, _: Task_Cancellation_Token) -> Task_Result {
    task := (^Task_Test_Payload)(payload)
    task.output = task.input * task.input
    task.executed = true
    task.execution_count += 1
    task.thread_id = sync.current_thread_id()
    return .Failed if task.fail else .Succeeded
}

// Occupy one worker until the owner explicitly releases it.
task_test_wait_at_gate :: proc(
    payload: rawptr, _: Task_Cancellation_Token) -> Task_Result {
    gate := (^Task_Test_Gate)(payload)
    sync.mutex_lock(&gate.mutex)
    gate.worker_started = true
    sync.cond_broadcast(&gate.changed)
    for !gate.worker_released {
        sync.cond_wait(&gate.changed, &gate.mutex)
    }
    sync.mutex_unlock(&gate.mutex)
    return .Succeeded
}

// Wait for cancellation and expose that cooperative observation to the owner.
task_test_wait_for_cancellation :: proc(
    payload: rawptr, token: Task_Cancellation_Token) -> Task_Result {
    task := (^Task_Test_Payload)(payload)
    for !task_cancellation_requested(token) {
        thread.yield()
    }
    task.executed = true
    task.execution_count += 1
    task.thread_id = sync.current_thread_id()
    return .Cancelled
}

// Wait until the sole worker has entered the blocking fixture.
task_test_wait_for_worker :: proc(gate: ^Task_Test_Gate) -> bool {
    deadline := time.tick_since({}) + 5 * time.Second
    for time.tick_since({}) < deadline {
        sync.mutex_lock(&gate.mutex)
        started := gate.worker_started
        sync.mutex_unlock(&gate.mutex)
        if started {
            return true
        }
        thread.yield()
    }
    return false
}

// Release the worker after owner-thread helping has been observed.
task_test_release_worker :: proc(gate: ^Task_Test_Gate) {
    sync.mutex_lock(&gate.mutex)
    gate.worker_released = true
    gate.release_requested = true
    sync.cond_broadcast(&gate.changed)
    sync.mutex_unlock(&gate.mutex)
}

// Request a gate release from an independent thread after shutdown begins draining.
task_test_release_gate_when_requested :: proc(worker: ^thread.Thread) {
    gate := (^Task_Test_Gate)(worker.data)
    sync.mutex_lock(&gate.mutex)
    for !gate.release_requested {
        sync.cond_wait(&gate.changed, &gate.mutex)
    }
    gate.worker_released = true
    sync.cond_broadcast(&gate.changed)
    sync.mutex_unlock(&gate.mutex)
}

// Release a test gate from an independent thread after the owner starts waiting.
task_test_release_gate_immediately :: proc(worker: ^thread.Thread) {
    task_test_release_worker((^Task_Test_Gate)(worker.data))
}

// Wake the independent gate releaser from a Helpable task executed by the owner.
task_test_request_gate_release :: proc(
    payload: rawptr, _: Task_Cancellation_Token) -> Task_Result {
    gate := (^Task_Test_Gate)(payload)
    sync.mutex_lock(&gate.mutex)
    gate.release_requested = true
    sync.cond_broadcast(&gate.changed)
    sync.mutex_unlock(&gate.mutex)
    return .Succeeded
}

// Start the independent release fixture and retain it for deterministic joining.
task_test_start_gate_releaser :: proc(gate: ^Task_Test_Gate) -> ^thread.Thread {
    releaser := thread.create(task_test_release_gate_when_requested)
    if releaser == nil {
        return nil
    }
    releaser.data = gate
    thread.start(releaser)
    return releaser
}

// Release and join an optional fixture thread without leaving a blocked task behind.
task_test_finish_gate_releaser :: proc(
    gate: ^Task_Test_Gate, releaser: ^thread.Thread) {
    task_test_release_worker(gate)
    if releaser != nil {
        thread.join(releaser)
        thread.destroy(releaser)
    }
}

// Verify production defaults reserve display and Julia execution capacity.
@(test)
task_pool_test_default_worker_count :: proc(t: ^testing.T) {
    expected := max(os.get_processor_core_count() - 2, 1)

    testing.expect_value(t, task_pool_default_worker_count(), expected)
    testing.expect_value(t, task_pool_default_capacity(expected),
        expected * TASK_POOL_TASKS_PER_WORKER)
}

// Verify the pool exclusively owns a fixed allocator region until destruction.
@(test)
task_pool_test_allocator_ownership :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 8))

    testing.expect(t, pool.backing != nil)
    testing.expect_value(t, len(pool.backing), pool.allocator_capacity)
    testing.expect(t, pool.allocator_capacity > 0)
    allocator := mem.mutex_allocator(&pool.synchronized_allocator)
    testing.expect(t, allocator.data == &pool.synchronized_allocator)

    task_pool_destroy(&pool)

    testing.expect(t, pool.backing == nil)
    testing.expect_value(t, pool.allocator_capacity, 0)
}

// Verify stale handles cannot observe a slot reused by a later task lifetime.
@(test)
task_pool_test_handle_generation :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    first_payload := Task_Test_Payload{input = 2}
    first, _ := task_pool_submit(&pool, task_test_execute, &first_payload)
    task_pool_wait(&pool, first)
    second_payload := Task_Test_Payload{input = 3}
    second, _ := task_pool_submit(&pool, task_test_execute, &second_payload)

    testing.expect_value(t, first.index, second.index)
    testing.expect(t, first.generation != second.generation)
    testing.expect_value(t, task_pool_poll(&pool, first),
        Task_Poll_Outcome.Stale_Handle)
    task_pool_wait(&pool, second)
}

// Verify immediate waiting exposes output only after terminal observation.
@(test)
task_pool_test_immediate_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 4}
    handle, outcome := task_pool_submit(&pool, task_test_execute, &payload)

    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 16)
}

// Verify caller work may overlap safely before joining task-owned output.
@(test)
task_pool_test_overlapped_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 5}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)
    independent_result := 7 * 6

    task_pool_wait(&pool, handle)

    testing.expect_value(t, independent_result, 42)
    testing.expect_value(t, payload.output, 25)
}

// Verify polling across an owner tick does not consume the terminal result.
@(test)
task_pool_test_cross_tick_poll_join :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 6}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)

    poll := task_pool_poll(&pool, handle)
    owner_tick := 1
    result, joined := task_pool_wait(&pool, handle)

    testing.expect(t, poll != .Stale_Handle)
    testing.expect_value(t, owner_tick, 1)
    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 36)
}

// Verify fences join grouped disjoint outputs before deterministic observation.
@(test)
task_pool_test_fence :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    defer task_pool_destroy(&pool)
    payloads := [4]Task_Test_Payload{{input = 1}, {input = 2}, {input = 3}, {input = 4}}
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    for &payload in payloads {
        testing.expect_value(t,
            task_fence_submit(&pool, &fence, task_test_execute, &payload),
            Task_Submit_Outcome.Queued)
    }

    testing.expect_value(t, task_fence_wait(&pool, &fence), Task_Result.Succeeded)
    testing.expect_value(t, payloads[0].output, 1)
    testing.expect_value(t, payloads[1].output, 4)
    testing.expect_value(t, payloads[2].output, 9)
    testing.expect_value(t, payloads[3].output, 16)
}

// Verify a waiting owner can execute useful queued work itself.
@(test)
task_pool_test_helping_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 8))
    defer task_pool_destroy(&pool)
    gate: Task_Test_Gate
    worker_handle, worker_outcome := task_pool_submit(
        &pool, task_test_wait_at_gate, &gate)
    testing.expect_value(t, worker_outcome, Task_Submit_Outcome.Queued)
    testing.expect(t, task_test_wait_for_worker(&gate))

    payload := Task_Test_Payload{input = 9}
    helped_handle, helped_outcome := task_pool_submit(
        &pool, task_test_execute, &payload)
    testing.expect_value(t, helped_outcome, Task_Submit_Outcome.Queued)

    result, joined := task_pool_wait(&pool, helped_handle)

    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 81)
    testing.expect_value(t, payload.thread_id, sync.current_thread_id())
    testing.expect_value(t, pool.helping_execution_count, u64(1))

    task_test_release_worker(&gate)
    task_pool_wait(&pool, worker_handle)
}

// Verify unrelated owner helping skips Worker_Only work until its worker is free.
@(test)
task_pool_test_helping_skips_worker_only :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 8))
    defer task_pool_destroy(&pool)
    gate: Task_Test_Gate
    defer task_test_finish_gate_releaser(&gate, nil)
    blocker, blocker_outcome := task_pool_submit(
        &pool, task_test_wait_at_gate, &gate)
    testing.expect_value(t, blocker_outcome, Task_Submit_Outcome.Queued)
    testing.expect(t, task_test_wait_for_worker(&gate))

    protected_payload: Task_Test_Payload
    protected, protected_outcome := task_pool_submit(
        &pool, task_test_execute, &protected_payload, .Worker_Only)
    helpable_payload := Task_Test_Payload{input = 9}
    helpable, helpable_outcome := task_pool_submit(
        &pool, task_test_execute, &helpable_payload)
    testing.expect_value(t, protected_outcome, Task_Submit_Outcome.Queued)
    testing.expect_value(t, helpable_outcome, Task_Submit_Outcome.Queued)
    owner_id := sync.current_thread_id()

    result, joined := task_pool_wait(&pool, helpable)
    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, helpable_payload.thread_id, owner_id)
    testing.expect_value(t, pool.helping_execution_count, u64(1))
    testing.expect(t, !protected_payload.executed)

    task_test_release_worker(&gate)
    _, blocker_joined := task_pool_wait(&pool, blocker)
    protected_result, protected_joined := task_pool_wait(&pool, protected)
    testing.expect_value(t, blocker_joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, protected_result, Task_Result.Succeeded)
    testing.expect_value(t, protected_joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, protected_payload.execution_count, 1)
    testing.expect(t, protected_payload.thread_id != owner_id)
    testing.expect_value(t, pool.helping_execution_count, u64(1))
}

// Verify waiting for protected work blocks for worker progress instead of helping it.
@(test)
task_pool_test_worker_only_wait :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 4))
    defer task_pool_destroy(&pool)
    gate: Task_Test_Gate
    defer task_test_finish_gate_releaser(&gate, nil)
    blocker, _ := task_pool_submit(&pool, task_test_wait_at_gate, &gate)
    testing.expect(t, task_test_wait_for_worker(&gate))
    payload := Task_Test_Payload{input = 11}
    handle, outcome := task_pool_submit(
        &pool, task_test_execute, &payload, .Worker_Only)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    releaser := thread.create(task_test_release_gate_immediately)
    if releaser != nil {
        releaser.data = &gate
        thread.start(releaser)
    } else {
        task_test_release_worker(&gate)
    }
    owner_id := sync.current_thread_id()

    result, joined := task_pool_wait(&pool, handle)
    testing.expect_value(t, result, Task_Result.Succeeded)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.execution_count, 1)
    testing.expect(t, payload.thread_id != owner_id)
    testing.expect_value(t, pool.helping_execution_count, u64(0))
    _, blocker_joined := task_pool_wait(&pool, blocker)
    testing.expect_value(t, blocker_joined, Task_Join_Outcome.Joined)
    if releaser != nil {
        thread.join(releaser)
        thread.destroy(releaser)
    }
}

// Verify cancellation remains cooperative for protected worker execution.
@(test)
task_pool_test_worker_only_cancellation :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 2))
    defer task_pool_destroy(&pool)
    payload: Task_Test_Payload
    owner_id := sync.current_thread_id()
    handle, outcome := task_pool_submit(
        &pool, task_test_wait_for_cancellation, &payload, .Worker_Only)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Requested)

    result, joined := task_pool_wait(&pool, handle)
    testing.expect_value(t, result, Task_Result.Cancelled)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.execution_count, 1)
    testing.expect(t, payload.thread_id != owner_id)
    testing.expect_value(t, pool.helping_execution_count, u64(0))
}

// Verify mixed-policy fences retain eligibility and deterministic joins.
@(test)
task_pool_test_mixed_policy_fence :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 4))
    defer task_pool_destroy(&pool)
    payloads := [3]Task_Test_Payload{
        {input = 2},
        {input = 3},
        {input = 4, fail = true},
    }
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &payloads[0], .Worker_Only),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &payloads[1], .Helpable),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &payloads[2], .Worker_Only),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t,
        pool.slots[fence.handles[0].index].execution_policy,
        Task_Execution_Policy.Worker_Only)
    testing.expect_value(t,
        pool.slots[fence.handles[1].index].execution_policy,
        Task_Execution_Policy.Helpable)
    testing.expect_value(t,
        pool.slots[fence.handles[2].index].execution_policy,
        Task_Execution_Policy.Worker_Only)

    testing.expect_value(t, task_fence_wait(&pool, &fence), Task_Result.Failed)
    for index in 0..<len(payloads) {
        testing.expect_value(t, payloads[index].execution_count, 1)
        testing.expect_value(t, payloads[index].output,
            payloads[index].input * payloads[index].input)
    }
}

// Verify workers alternate policy classes while both bounded queues stay ready.
@(test)
task_pool_test_worker_dispatch_alternates_policies :: proc(t: ^testing.T) {
    helpable_items: [3]int
    worker_only_items: [3]int
    pool := Task_Pool{
        helpable_ready = {items = helpable_items[:]},
        worker_only_ready = {items = worker_only_items[:]},
        next_worker_policy = .Helpable,
    }
    for index in 0..<len(helpable_items) {
        task_pool_queue_push(&pool.helpable_ready, index)
        task_pool_queue_push(&pool.worker_only_ready, index + 3)
    }
    expected_helpable := true
    for _ in 0..<3 {
        selected := task_pool_worker_queue(&pool)
        testing.expect_value(t, selected == &pool.helpable_ready, expected_helpable)
        _ = task_pool_queue_pop(selected)
        expected_helpable = !expected_helpable
    }
}

// Verify repeated protected submissions cannot be stranded or completed twice.
@(test)
task_pool_test_worker_only_wakeup_and_completion_cycles :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 8))
    defer task_pool_destroy(&pool)
    payloads: [8]Task_Test_Payload
    handles: [8]Task_Handle
    owner_id := sync.current_thread_id()
    for cycle in 0..<16 {
        for index in 0..<len(payloads) {
            payloads[index] = {input = cycle * len(payloads) + index}
            execution := Task_Execution_Policy.Worker_Only
            if (cycle + index) % 2 == 0 {
                execution = .Helpable
            }
            handle, outcome := task_pool_submit(
                &pool, task_test_execute, &payloads[index], execution)
            testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
            handles[index] = handle
        }
        for index in 0..<len(handles) {
            result, joined := task_pool_wait(&pool, handles[index])
            testing.expect_value(t, result, Task_Result.Succeeded)
            testing.expect_value(t, joined, Task_Join_Outcome.Joined)
            testing.expect_value(t, payloads[index].execution_count, 1)
            testing.expect_value(t, payloads[index].output,
                payloads[index].input * payloads[index].input)
            if pool.slots[handles[index].index].execution_policy ==
               .Worker_Only {
                testing.expect(t, payloads[index].thread_id != owner_id)
            }
        }
    }
}

// Check stopped-pool observation, cancellation, and exactly-once handle consumption.
task_pool_test_verify_stopped_handles :: proc(
    t: ^testing.T, pool: ^Task_Pool, observed: Task_Test_Stopped_Observation) {
    testing.expect_value(
        t, task_pool_poll(pool, observed.blocker), Task_Poll_Outcome.Ready)
    testing.expect_value(
        t, task_pool_poll(pool, observed.protected), Task_Poll_Outcome.Ready)
    testing.expect_value(
        t, task_pool_poll(pool, observed.release_signal), Task_Poll_Outcome.Ready)
    testing.expect_value(t, task_pool_cancel(pool, observed.protected),
        Task_Cancel_Outcome.Requested)
    _, stopped_outcome := task_pool_submit(
        pool, task_test_execute, observed.protected_payload)
    testing.expect_value(t, stopped_outcome, Task_Submit_Outcome.Pool_Stopped)
    testing.expect_value(t, observed.protected_payload.execution_count, 1)
    testing.expect(t, observed.protected_payload.thread_id != observed.owner_id)
    testing.expect_value(t, pool.helping_execution_count, u64(1))
    _, blocker_joined := task_pool_wait(pool, observed.blocker)
    protected_result, protected_joined := task_pool_wait(pool, observed.protected)
    _, release_joined := task_pool_wait(pool, observed.release_signal)
    testing.expect_value(t, blocker_joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, protected_result, Task_Result.Cancelled)
    testing.expect_value(t, protected_joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, release_joined, Task_Join_Outcome.Joined)
}

// Verify shutdown drains protected work on workers and preserves stopped handles.
@(test)
task_pool_test_shutdown_drains_worker_only :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 4))
    defer task_pool_destroy(&pool)
    gate: Task_Test_Gate
    releaser := task_test_start_gate_releaser(&gate)
    testing.expect(t, releaser != nil)
    if releaser == nil {
        task_test_release_worker(&gate)
    }
    defer task_test_finish_gate_releaser(&gate, releaser)
    blocker, _ := task_pool_submit(&pool, task_test_wait_at_gate, &gate)
    testing.expect(t, task_test_wait_for_worker(&gate))
    protected_payload := Task_Test_Payload{input = 12}
    protected, protected_outcome := task_pool_submit(
        &pool, task_test_execute, &protected_payload, .Worker_Only)
    release_signal, signal_outcome := task_pool_submit(
        &pool, task_test_request_gate_release, &gate)
    testing.expect_value(t, protected_outcome, Task_Submit_Outcome.Queued)
    testing.expect_value(t, signal_outcome, Task_Submit_Outcome.Queued)
    owner_id := sync.current_thread_id()

    task_pool_shutdown(&pool)

    testing.expect_value(t, pool.state, Task_Pool_State.Stopped)
    task_pool_test_verify_stopped_handles(t, &pool, {
        blocker = blocker,
        protected = protected,
        release_signal = release_signal,
        protected_payload = &protected_payload,
        owner_id = owner_id,
    })
}

// Verify bounded occupancy reports queue pressure without losing ownership.
@(test)
task_pool_test_queue_full :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1, 8))
    defer task_pool_destroy(&pool)
    payloads := [9]Task_Test_Payload{}
    handles: [8]Task_Handle
    for index in 0..<len(pool.slots) {
        execution := Task_Execution_Policy.Worker_Only
        if index % 2 != 0 {
            execution = .Helpable
        }
        handles[index], _ = task_pool_submit(
            &pool, task_test_execute, &payloads[index], execution)
    }

    _, outcome := task_pool_submit(
        &pool, task_test_execute, &payloads[len(pool.slots)])

    testing.expect_value(t, outcome, Task_Submit_Outcome.Queue_Full)
    for handle in handles {
        task_pool_wait(&pool, handle)
    }
    reused, reused_outcome := task_pool_submit(
        &pool, task_test_execute, &payloads[len(pool.slots)], .Helpable)
    testing.expect_value(t, reused_outcome, Task_Submit_Outcome.Queued)
    testing.expect_value(t, reused.index, handles[0].index)
    testing.expect(t, reused.generation != handles[0].generation)
    testing.expect_value(t, pool.slots[reused.index].execution_policy,
        Task_Execution_Policy.Helpable)
    task_pool_wait(&pool, reused)
}

// Verify many workers mutate only their exclusive output partitions.
@(test)
task_pool_test_disjoint_writes_under_stress :: proc(t: ^testing.T) {
    TASK_COUNT :: 128
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 4, TASK_COUNT))
    defer task_pool_destroy(&pool)
    payloads: [TASK_COUNT]Task_Test_Payload
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    for &payload, index in payloads {
        payload.input = index
        testing.expect_value(t,
            task_fence_submit(&pool, &fence, task_test_execute, &payload),
            Task_Submit_Outcome.Queued)
    }

    testing.expect_value(t, task_fence_wait(&pool, &fence),
        Task_Result.Succeeded)
    for payload, index in payloads {
        testing.expect_value(t, payload.output, index * index)
    }
}

// Verify explicit allocator-backed capacity is not constrained by legacy limits.
@(test)
task_pool_test_capacity_scales_past_sixty_four :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2, 128))
    defer task_pool_destroy(&pool)

    testing.expect_value(t, len(pool.slots), 128)
}

// Verify failure remains visible through the exactly-once terminal join.
@(test)
task_pool_test_failure_is_visible :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{fail = true}
    handle, _ := task_pool_submit(&pool, task_test_execute, &payload)

    result, outcome := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Failed)
    testing.expect_value(t, outcome, Task_Join_Outcome.Joined)
    _, second_outcome := task_pool_wait(&pool, handle)
    testing.expect_value(t, second_outcome, Task_Join_Outcome.Stale_Handle)
}

// Verify cancellation after worker completion wins until join consumes authority.
@(test)
task_pool_test_cancellation_wins_until_join :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload := Task_Test_Payload{input = 7}
    handle, outcome := task_pool_submit(&pool, task_test_execute, &payload)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)
    for task_pool_poll(&pool, handle) == .Pending {
        thread.yield()
    }

    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Already_Requested)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Cancelled)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect_value(t, payload.output, 49)
    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Stale_Handle)
}

// Verify a running task may observe cancellation without surrendering ownership early.
@(test)
task_pool_test_cooperative_cancellation :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 1))
    defer task_pool_destroy(&pool)
    payload: Task_Test_Payload
    handle, outcome := task_pool_submit(
        &pool, task_test_wait_for_cancellation, &payload)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Queued)

    testing.expect_value(t, task_pool_cancel(&pool, handle),
        Task_Cancel_Outcome.Requested)
    result, joined := task_pool_wait(&pool, handle)

    testing.expect_value(t, result, Task_Result.Cancelled)
    testing.expect_value(t, joined, Task_Join_Outcome.Joined)
    testing.expect(t, payload.executed)
}

// Verify fence aggregation reports cancellation unless any joined task failed.
@(test)
task_pool_test_fence_result_precedence :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    defer task_pool_destroy(&pool)
    cancelled_payload := Task_Test_Payload{input = 2}
    succeeded_payload := Task_Test_Payload{input = 3}
    fence, initialized := task_fence_begin(&pool)
    testing.expect(t, initialized)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &cancelled_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &succeeded_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_pool_cancel(&pool, fence.handles[0]),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_fence_wait(&pool, &fence),
        Task_Result.Cancelled)

    cancelled_payload = {input = 4}
    failed_payload := Task_Test_Payload{fail = true}
    fence, initialized = task_fence_begin(&pool)
    testing.expect(t, initialized)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &cancelled_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_fence_submit(
        &pool, &fence, task_test_execute, &failed_payload),
        Task_Submit_Outcome.Queued)
    testing.expect_value(t, task_pool_cancel(&pool, fence.handles[0]),
        Task_Cancel_Outcome.Requested)
    testing.expect_value(t, task_fence_wait(&pool, &fence), Task_Result.Failed)
}

// Verify shutdown rejects new work after finishing every accepted task.
@(test)
task_pool_test_shutdown :: proc(t: ^testing.T) {
    pool: Task_Pool
    testing.expect(t, task_pool_init(&pool, 2))
    payloads := [8]Task_Test_Payload{}
    for &payload in payloads {
        task_pool_submit(&pool, task_test_execute, &payload)
    }

    task_pool_shutdown(&pool)
    _, outcome := task_pool_submit(&pool, task_test_execute, &payloads[0])

    testing.expect_value(t, pool.state, Task_Pool_State.Stopped)
    testing.expect_value(t, outcome, Task_Submit_Outcome.Pool_Stopped)
    for payload in payloads {
        testing.expect(t, payload.executed)
    }
    task_pool_destroy(&pool)
}