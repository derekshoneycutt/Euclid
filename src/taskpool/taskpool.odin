package taskpool

import "core:mem"
import tlsf "core:mem/tlsf"
import vmem "core:mem/virtual"
import "core:os"
import "core:sync"
import "core:thread"

// Default occupancy reserves four finite task slots per worker.
TASK_POOL_TASKS_PER_WORKER :: 4

// Terminal result written by a task procedure and consumed exactly once at join.
Task_Result :: enum {
    Succeeded,
    Failed,
    Cancelled,
}

// Result of attempting to acquire a bounded task slot.
Task_Submit_Outcome :: enum {
    Queued,
    Queue_Full,
    Pool_Stopped,
}

// Non-consuming observation of a generational task handle.
Task_Poll_Outcome :: enum {
    Pending,
    Ready,
    Stale_Handle,
}

// Result of consuming one task's terminal state.
Task_Join_Outcome :: enum {
    Joined,
    Stale_Handle,
}

// Result of requesting cancellation for one live task generation.
Task_Cancel_Outcome :: enum {
    Requested,
    Already_Requested,
    Stale_Handle,
}

// Limits which executor may claim one accepted task generation.
Task_Execution_Policy :: enum u8 {
    Helpable,
    Worker_Only,
}

// Owner-visible lifecycle of one reusable task slot.
Task_Slot_State :: enum {
    Available,
    Queued,
    Completed,
}

// Admission and teardown lifecycle of the task-pool service.
Task_Pool_State :: enum {
    Uninitialized,
    Running,
    Stopping,
    Stopped,
}

// Read-only cooperative cancellation capability valid only during task execution.
Task_Cancellation_Token :: struct {
    requested: ^bool,
}

// Worker entry point for finite work over caller-owned payload storage.
// The payload and every writable object reachable from it must remain exclusively
// task-owned from successful submission through join. The token may be polled at
// bounded interruption points but does not shorten payload ownership.
Task_Procedure :: #type proc(
    payload: rawptr, token: Task_Cancellation_Token) -> Task_Result

// Generational capability identifying one live slot lifetime.
// Reuse keeps the index but increments generation so old handles become stale.
Task_Handle :: struct {
    index : int,
    generation : u64,
}

// Internal storage shared across the owner/worker handoff.
// Workers access procedure, payload, policy, and result only while owning dispatch.
Task_Slot :: struct {
    generation : u64,
    state : Task_Slot_State,
    procedure : Task_Procedure,
    payload : rawptr,
    result : Task_Result,
    execution_policy : Task_Execution_Policy,
    cancellation_requested : bool,
}

// Fixed-capacity ring storing slot indices, never task-owned payloads.
Task_Index_Queue :: struct {
    items : []int,
    head : int,
    count : int,
}

// Per-thread stable entry context for one repository-owned worker.
Task_Worker_Data :: struct {
    pool : ^Task_Pool,
}

// Owner-side group of handles joined in deterministic submission order.
// Handle storage comes from the pool allocator and is released by `task_fence_wait`.
Task_Fence :: struct {
    handles : []Task_Handle,
    count : int,
}

// Fixed-capacity task service owned and coordinated by one application thread.
//
// Workers execute task procedures, but slot admission, polling, joining, fences,
// and lifecycle transitions are owner-thread operations. All backend allocations
// come from one mutex-wrapped TLSF allocator over a virtual-memory region sized
// before startup. Scheduler state is protected independently from slot lifecycle.
Task_Pool :: struct {
    // Pool-owned workers, policy queues, completion publication, and task slots.
    workers : []^thread.Thread,
    worker_data : []Task_Worker_Data,
    slots : []Task_Slot,
    helpable_ready : Task_Index_Queue,
    worker_only_ready : Task_Index_Queue,
    completions : Task_Index_Queue,

    // Worker/owner dispatch synchronization; workers never mutate owner lifecycle.
    scheduler_mutex : sync.Mutex,
    scheduler_changed : sync.Cond,
    worker_exit : bool,
    worker_started_count : int,
    executing_count : int,
    next_worker_policy : Task_Execution_Policy,

    // Fixed allocator ownership. `backing` owns the region managed by TLSF;
    // Synchronized access is required for startup and fence allocation.
    backing : []byte,
    tlsf_allocator : tlsf.Allocator,
    synchronized_allocator : mem.Mutex_Allocator,
    allocator_capacity : int,

    // Owner-controlled lifecycle and bounded occupancy.
    state : Task_Pool_State,
    worker_count : int,
    outstanding_count : int,

    // Cumulative diagnostics for owner-side helping and abandoned joined results.
    helping_execution_count : u64,
    abandoned_terminal_count : u64,
}

//   Derive a worker count while reserving processors for display and Julia work.
//
// Returns:
//   - Logical processor count minus two, clamped to at least one worker.
task_pool_default_worker_count :: proc() -> int {
    available := os.get_processor_core_count() - 2
    return max(available, 1)
}

//   Derive default bounded task capacity from worker count.
//
// Parameters:
//   - worker_count: Requested number of executing workers.
//
// Returns:
//   - Four slots per worker, treating nonpositive input as one worker.
task_pool_default_capacity :: proc(worker_count: int) -> int {
    return max(worker_count, 1) * TASK_POOL_TASKS_PER_WORKER
}

//   Add one allocation class and TLSF metadata to a backing-store budget.
//
// Parameters:
//   - budget: Running byte total updated in place.
//   - count: Number of equal allocations in this class.
//   - size: Payload bytes per allocation.
//   - alignment: Required alignment for each allocation.
//
// Side effects:
//   - Increases `budget` by TLSF's conservative pool-size estimate.
task_pool_budget_allocation :: proc(
    budget: ^int, count, size, alignment: int) {
    budget^ += tlsf.estimate_pool_size(count, size, alignment)
}

//   Calculate fixed storage for owned workers, queues, slots, and one maximal fence.
//
// Notes:
//   - The result is rounded up to a virtual-memory page boundary.
//
// Parameters:
//   - worker_count: Final positive worker count.
//   - task_capacity: Final slot and fully reserved queue capacity.
//
// Returns:
//   - Conservative byte capacity for the pool-owned TLSF region.
task_pool_allocator_capacity :: proc(worker_count, task_capacity: int) -> int {
    budget := 0
    task_pool_budget_allocation(
        &budget, 1, task_capacity * size_of(Task_Slot), align_of(Task_Slot))
    task_pool_budget_allocation(
        &budget, 1, task_capacity * size_of(Task_Handle), align_of(Task_Handle))
    task_pool_budget_allocation(
        &budget, 3, task_capacity * size_of(int), align_of(int))
    task_pool_budget_allocation(
        &budget, 1, worker_count * size_of(^thread.Thread), align_of(^thread.Thread))
    task_pool_budget_allocation(
        &budget, 1, worker_count * size_of(Task_Worker_Data),
        align_of(Task_Worker_Data))
    task_pool_budget_allocation(
        &budget, worker_count, size_of(thread.Thread), align_of(thread.Thread))
    page_size := int(mem.PAGE_SIZE)
    return ((budget + page_size - 1) / page_size) * page_size
}

//   Release the pool-owned allocator after every allocation user has stopped.
//
// Parameters:
//   - pool: A stopped pool whose dispatcher and fence allocations are no longer live.
//
// Side effects:
//   - Destroys TLSF, releases virtual memory, and clears allocator metadata.
task_pool_release_allocator :: proc(pool: ^Task_Pool) {
    tlsf.destroy(&pool.tlsf_allocator)
    if pool.backing != nil {
        vmem.release(raw_data(pool.backing), uint(len(pool.backing)))
    }
    pool.backing = nil
    pool.allocator_capacity = 0
}

//   Allocate slots and fully reserve policy/completion queues before workers start.
//
// Parameters:
//   - pool: The pool with allocator and worker count already initialized.
//   - task_capacity: Required slot and dispatch queue capacity.
//
// Returns:
//   - True when all storage is ready; false after rolling back partial setup.
//
// Side effects:
//   - Initializes fixed dispatch storage and starts no threads.
task_pool_init_backend :: proc(pool: ^Task_Pool, task_capacity: int) -> bool {
    allocator := mem.mutex_allocator(&pool.synchronized_allocator)
    slots, slots_error := make([]Task_Slot, task_capacity, allocator)
    if slots_error != nil {
        return false
    }
    pool.slots = slots
    helpable, helpable_error := make([]int, task_capacity, allocator)
    worker_only, worker_only_error := make([]int, task_capacity, allocator)
    completions, completion_error := make([]int, task_capacity, allocator)
    workers, workers_error := make([]^thread.Thread, pool.worker_count, allocator)
    worker_data, worker_data_error := make(
        []Task_Worker_Data, pool.worker_count, allocator)
    if helpable_error != nil || worker_only_error != nil ||
       completion_error != nil || workers_error != nil ||
       worker_data_error != nil {
        delete(worker_data, allocator)
        delete(workers, allocator)
        delete(completions, allocator)
        delete(worker_only, allocator)
        delete(helpable, allocator)
        delete(pool.slots, allocator)
        pool.slots = nil
        return false
    }
    pool.helpable_ready.items = helpable
    pool.worker_only_ready.items = worker_only
    pool.completions.items = completions
    pool.workers = workers
    pool.worker_data = worker_data
    return true
}

//   Insert one slot identity into a bounded ring queue.
task_pool_queue_push :: proc(queue: ^Task_Index_Queue, index: int) {
    tail := (queue.head + queue.count) % len(queue.items)
    queue.items[tail] = index
    queue.count += 1
}

//   Remove the oldest slot identity from a nonempty bounded ring queue.
task_pool_queue_pop :: proc(queue: ^Task_Index_Queue) -> int {
    index := queue.items[queue.head]
    queue.head = (queue.head + 1) % len(queue.items)
    queue.count -= 1
    return index
}

//   Select a worker queue, alternating classes whenever both contain ready work.
task_pool_worker_queue :: proc(pool: ^Task_Pool) -> ^Task_Index_Queue {
    helpable_ready := pool.helpable_ready.count > 0
    worker_only_ready := pool.worker_only_ready.count > 0
    if helpable_ready && worker_only_ready {
        selected := &pool.helpable_ready
        if pool.next_worker_policy == .Helpable {
            pool.next_worker_policy = .Worker_Only
        } else {
            selected = &pool.worker_only_ready
            pool.next_worker_policy = .Helpable
        }
        return selected
    }
    return &pool.helpable_ready if helpable_ready else &pool.worker_only_ready
}

//   Resolve optional worker and task capacities to valid production values.
task_pool_resolve_capacities :: proc(
    worker_count, task_capacity: int) -> (int, int) {
    selected_worker_count := worker_count
    if selected_worker_count == 0 {
        selected_worker_count = task_pool_default_worker_count()
    }
    selected_worker_count = max(selected_worker_count, 1)
    selected_capacity := task_capacity
    if selected_capacity == 0 {
        selected_capacity = task_pool_default_capacity(selected_worker_count)
    }
    return selected_worker_count, max(selected_capacity, selected_worker_count)
}

//   Free fixed dispatcher storage after every worker has stopped.
task_pool_release_backend_storage :: proc(pool: ^Task_Pool) {
    allocator := mem.mutex_allocator(&pool.synchronized_allocator)
    delete(pool.worker_data, allocator)
    delete(pool.workers, allocator)
    delete(pool.completions.items, allocator)
    delete(pool.worker_only_ready.items, allocator)
    delete(pool.helpable_ready.items, allocator)
    delete(pool.slots, allocator)
    pool.worker_data = nil
    pool.workers = nil
    pool.completions = {}
    pool.worker_only_ready = {}
    pool.helpable_ready = {}
    pool.slots = nil
}

//   Stop and join every worker already started during initialization or shutdown.
task_pool_stop_workers :: proc(pool: ^Task_Pool) {
    sync.mutex_lock(&pool.scheduler_mutex)
    pool.worker_exit = true
    sync.cond_broadcast(&pool.scheduler_changed)
    sync.mutex_unlock(&pool.scheduler_mutex)
    for index in 0..<pool.worker_started_count {
        worker := pool.workers[index]
        thread.join(worker)
        thread.destroy(worker)
        pool.workers[index] = nil
    }
    pool.worker_started_count = 0
}

//   Start pool-owned worker threads, rolling back every partial startup.
task_pool_start_workers :: proc(pool: ^Task_Pool) -> bool {
    pool.worker_exit = false
    pool.executing_count = 0
    pool.worker_started_count = 0
    pool.next_worker_policy = .Helpable
    saved_context := context
    context.allocator = mem.mutex_allocator(&pool.synchronized_allocator)
    for index in 0..<pool.worker_count {
        pool.worker_data[index].pool = pool
        worker := thread.create(task_pool_worker)
        if worker == nil {
            context = saved_context
            task_pool_stop_workers(pool)
            return false
        }
        worker.data = &pool.worker_data[index]
        pool.workers[index] = worker
        thread.start(worker)
        pool.worker_started_count += 1
    }
    context = saved_context
    return true
}

//   Initialize the fixed allocator, slots, queues, and worker threads transactionally.
//
// Parameters:
//   - pool: Zero-valued, uninitialized storage owned by the caller.
//   - worker_count: Worker count, or zero to derive the production default.
//   - task_capacity: Slot capacity, or zero to derive it from worker count.
//
// Returns:
//   - True with the pool running, or false with no live backing/backend resources.
//
// Side effects:
//   - Reserves virtual memory and starts at least one worker on success.
task_pool_init :: proc(
    pool: ^Task_Pool, worker_count := 0, task_capacity := 0) -> bool {
    if pool == nil || pool.state != .Uninitialized {
        return false
    }
    selected_worker_count, selected_capacity := task_pool_resolve_capacities(
        worker_count, task_capacity)
    pool.worker_count = selected_worker_count
    pool.allocator_capacity = task_pool_allocator_capacity(
        pool.worker_count, selected_capacity)
    backing, backing_error := vmem.reserve_and_commit(
        uint(pool.allocator_capacity))
    if backing_error != nil {
        pool.allocator_capacity = 0
        return false
    }
    pool.backing = backing
    if tlsf.init_from_buffer(&pool.tlsf_allocator, pool.backing) != .None {
        task_pool_release_allocator(pool)
        return false
    }
    mem.mutex_allocator_init(
        &pool.synchronized_allocator, tlsf.allocator(&pool.tlsf_allocator))
    if !task_pool_init_backend(pool, selected_capacity) {
        task_pool_release_allocator(pool)
        return false
    }
    if !task_pool_start_workers(pool) {
        task_pool_release_backend_storage(pool)
        task_pool_release_allocator(pool)
        return false
    }
    pool.state = .Running
    return true
}

//   Execute one task procedure with the pool's restricted allocation context.
//
// Parameters:
//   - pool: The pool owning the claimed slot.
//   - index: Claimed slot identity.
//
// Returns:
//   - The procedure's terminal result, not yet published to the owner.
task_pool_execute_slot :: proc(pool: ^Task_Pool, index: int) -> Task_Result {
    slot := &pool.slots[index]
    saved_allocator := context.allocator
    context.allocator = mem.nil_allocator()
    result := slot.procedure(slot.payload, {
        requested = &slot.cancellation_requested,
    })
    context.allocator = saved_allocator
    return result
}

//   Publish one terminal result and wake owner waiters and worker drainers.
task_pool_publish_completion :: proc(
    pool: ^Task_Pool, index: int, result: Task_Result) {
    sync.mutex_lock(&pool.scheduler_mutex)
    pool.slots[index].result = result
    task_pool_queue_push(&pool.completions, index)
    pool.executing_count -= 1
    sync.cond_broadcast(&pool.scheduler_changed)
    sync.mutex_unlock(&pool.scheduler_mutex)
}

//   Run claimed procedures until shutdown has drained accepted work.
task_pool_worker :: proc(worker: ^thread.Thread) {
    data := (^Task_Worker_Data)(worker.data)
    pool := data.pool
    for {
        sync.mutex_lock(&pool.scheduler_mutex)
        for pool.helpable_ready.count == 0 &&
            pool.worker_only_ready.count == 0 && !pool.worker_exit {
            sync.cond_wait(&pool.scheduler_changed, &pool.scheduler_mutex)
        }
        if pool.worker_exit && pool.helpable_ready.count == 0 &&
           pool.worker_only_ready.count == 0 {
            sync.mutex_unlock(&pool.scheduler_mutex)
            return
        }
        queue := task_pool_worker_queue(pool)
        index := task_pool_queue_pop(queue)
        pool.executing_count += 1
        sync.mutex_unlock(&pool.scheduler_mutex)
        result := task_pool_execute_slot(pool, index)
        task_pool_publish_completion(pool, index, result)
    }
}

//   Report whether cancellation has been requested for the executing task.
//
// Parameters:
//   - token: Pool-issued capability valid only during one task invocation.
//
// Returns:
//   - True after an owner release-stores cancellation; false for nil or active tokens.
task_cancellation_requested :: proc(token: Task_Cancellation_Token) -> bool {
    return token.requested != nil &&
        sync.atomic_load_explicit(token.requested, .Acquire)
}

//   Publish synchronized completions into owner-visible slot state.
//
// Parameters:
//   - pool: The owner-thread pool whose completion queue is drained.
//
// Side effects:
//   - Marks queued slots completed without consuming their handles or results.
task_pool_collect_completed :: proc(pool: ^Task_Pool) {
    sync.mutex_lock(&pool.scheduler_mutex)
    for pool.completions.count > 0 {
        index := task_pool_queue_pop(&pool.completions)
        slot := &pool.slots[index]
        if slot.state == .Queued {
            slot.state = .Completed
        }
    }
    sync.mutex_unlock(&pool.scheduler_mutex)
}

//   Resolve one generational handle to its current live slot.
//
// Parameters:
//   - pool: The owner-thread pool containing the slot table.
//   - handle: The slot index and lifetime generation to validate.
//
// Returns:
//   - The borrowed live slot and true, or nil and false for stale/invalid handles.
task_pool_slot :: proc(
    pool: ^Task_Pool, handle: Task_Handle) -> (^Task_Slot, bool) {
    if handle.index < 0 || handle.index >= len(pool.slots) {
        return nil, false
    }
    slot := &pool.slots[handle.index]
    if slot.state == .Available || slot.generation != handle.generation {
        return nil, false
    }
    return slot, true
}

//   Submit finite work with explicit owner-help eligibility.
//
// Notes:
//   - Payload storage and writable outputs become task-owned until successful join.
//   - The owner must eventually join every successfully returned handle.
//   - Existing calls default to Helpable execution.
//
// Parameters:
//   - pool: The running owner-thread pool.
//   - procedure: The worker entry point to execute once.
//   - payload: Opaque task data whose lifetime extends through join.
//   - execution: Whether the owner may claim this task while helping.
//
// Returns:
//   - A live handle and `Queued`, or a zero handle with the rejection outcome.
//
// Side effects:
//   - Reuses one slot generation, increments outstanding count, and queues work.
task_pool_submit :: proc(
    pool: ^Task_Pool, procedure: Task_Procedure,
    payload: rawptr,
    execution := Task_Execution_Policy.Helpable) ->
    (Task_Handle, Task_Submit_Outcome) {
    if pool == nil || pool.state != .Running {
        return {}, .Pool_Stopped
    }
    task_pool_collect_completed(pool)
    for &slot, index in pool.slots {
        if slot.state != .Available {
            continue
        }
        slot.generation += 1
        slot.state = .Queued
        slot.procedure = procedure
        slot.payload = payload
        slot.result = .Failed
        slot.execution_policy = execution
        sync.atomic_store_explicit(
            &slot.cancellation_requested, false, .Release)
        pool.outstanding_count += 1
        sync.mutex_lock(&pool.scheduler_mutex)
        queue := &pool.worker_only_ready
        if execution == .Helpable {
            queue = &pool.helpable_ready
        }
        task_pool_queue_push(queue, index)
        sync.cond_signal(&pool.scheduler_changed)
        sync.mutex_unlock(&pool.scheduler_mutex)
        return {index = index, generation = slot.generation}, .Queued
    }
    return {}, .Queue_Full
}

//   Request cooperative cancellation for one live task generation.
//
// Notes:
//   - Cancellation remains valid through completion until join consumes the handle.
//   - The task retains payload ownership and must still be joined exactly once.
//
// Returns:
//   - `Requested`, `Already_Requested`, or `Stale_Handle`.
//
// Side effects:
//   - Release-stores the slot cancellation flag for worker and join observation.
task_pool_cancel :: proc(
    pool: ^Task_Pool, handle: Task_Handle) -> Task_Cancel_Outcome {
    if pool == nil {
        return .Stale_Handle
    }
    task_pool_collect_completed(pool)
    slot, live := task_pool_slot(pool, handle)
    if !live {
        return .Stale_Handle
    }
    if sync.atomic_load_explicit(&slot.cancellation_requested, .Acquire) {
        return .Already_Requested
    }
    sync.atomic_store_explicit(
        &slot.cancellation_requested, true, .Release)
    return .Requested
}

//   Check task readiness without consuming its terminal result.
//
// Parameters:
//   - pool: The owner-thread pool.
//   - handle: The generational task capability to inspect.
//
// Returns:
//   - `Pending`, `Ready`, or `Stale_Handle`; readiness does not consume the handle.
//
// Side effects:
//   - Collects any backend completions before inspecting the requested slot.
task_pool_poll :: proc(
    pool: ^Task_Pool, handle: Task_Handle) -> Task_Poll_Outcome {
    task_pool_collect_completed(pool)
    slot, live := task_pool_slot(pool, handle)
    if !live {
        return .Stale_Handle
    }
    return .Ready if slot.state == .Completed else .Pending
}

//   Execute one Helpable task on the owner when available.
//
// Parameters:
//   - pool: The pool whose Helpable queue may be helped.
//
// Returns:
//   - True when one task was executed; false when no Helpable task was available.
//
// Side effects:
//   - Executes eligible work synchronously and increments helping telemetry.
task_pool_help_once :: proc(pool: ^Task_Pool) -> bool {
    sync.mutex_lock(&pool.scheduler_mutex)
    if pool.helpable_ready.count == 0 {
        sync.mutex_unlock(&pool.scheduler_mutex)
        return false
    }
    index := task_pool_queue_pop(&pool.helpable_ready)
    pool.executing_count += 1
    sync.mutex_unlock(&pool.scheduler_mutex)
    result := task_pool_execute_slot(pool, index)
    task_pool_publish_completion(pool, index, result)
    pool.helping_execution_count += 1
    return true
}

//   Wait for a queue or completion change without missing a concurrent signal.
task_pool_wait_for_progress :: proc(pool: ^Task_Pool) {
    sync.mutex_lock(&pool.scheduler_mutex)
    if pool.helpable_ready.count == 0 && pool.completions.count == 0 {
        sync.cond_wait(&pool.scheduler_changed, &pool.scheduler_mutex)
    }
    sync.mutex_unlock(&pool.scheduler_mutex)
}

//   Wait for and consume one task's exactly-once terminal result.
//
// Notes:
//   - While blocked, the owner executes Helpable work or waits for progress.
//   - A successful join ends task ownership of the caller's payload and outputs.
//
// Parameters:
//   - pool: The owner-thread pool.
//   - handle: The live generational task capability to consume.
//
// Returns:
//   - The task result and `Joined`, or `Failed` and `Stale_Handle`.
//
// Side effects:
//   - Releases the slot for reuse and decrements outstanding count on join.
task_pool_wait :: proc(
    pool: ^Task_Pool, handle: Task_Handle) -> (Task_Result, Task_Join_Outcome) {
    for {
        task_pool_collect_completed(pool)
        slot, live := task_pool_slot(pool, handle)
        if !live {
            return .Failed, .Stale_Handle
        }
        if slot.state == .Completed {
            result := slot.result
            if sync.atomic_load_explicit(
                &slot.cancellation_requested, .Acquire) {
                result = .Cancelled
            }
            slot.state = .Available
            slot.procedure = nil
            slot.payload = nil
            pool.outstanding_count -= 1
            return result, .Joined
        }
        if !task_pool_help_once(pool) {
            task_pool_wait_for_progress(pool)
        }
    }
}

//   Allocate owner-side handle storage for one deterministic task group.
//
// Notes:
//   - Every successful begin must reach `task_fence_wait`, even with no submissions.
//
// Parameters:
//   - pool: The running pool whose allocator and slot capacity size the fence.
//
// Returns:
//   - An empty fence and true, or a zero fence and false on state/allocation failure.
//
// Side effects:
//   - Allocates one handle array from the pool's synchronized allocator.
task_fence_begin :: proc(pool: ^Task_Pool) -> (Task_Fence, bool) {
    if pool == nil || pool.state != .Running {
        return {}, false
    }
    allocator := mem.mutex_allocator(&pool.synchronized_allocator)
    handles, alloc_error := make([]Task_Handle, len(pool.slots), allocator)
    if alloc_error != nil {
        return {}, false
    }
    return {handles = handles}, true
}

//   Submit one task and retain its handle in deterministic fence order.
//
// Parameters:
//   - pool: The running owner-thread pool.
//   - fence: A live fence created by `task_fence_begin`.
//   - procedure: The worker entry point to execute once.
//   - payload: Opaque task-owned data that remains live through fence wait.
//
// Returns:
//   - The underlying submission outcome; a full fence reports `Queue_Full`.
//
// Side effects:
//   - On success, appends the live handle to the fence.
task_fence_submit :: proc(
    pool: ^Task_Pool, fence: ^Task_Fence, procedure: Task_Procedure,
    payload: rawptr,
    execution := Task_Execution_Policy.Helpable) -> Task_Submit_Outcome {
    if fence.count >= len(fence.handles) {
        return .Queue_Full
    }
    handle, outcome := task_pool_submit(pool, procedure, payload, execution)
    if outcome == .Queued {
        fence.handles[fence.count] = handle
        fence.count += 1
    }
    return outcome
}

//   Join every fenced task in submission order and release fence storage.
//
// Parameters:
//   - pool: The owner-thread pool that issued the handles.
//   - fence: The live fence to consume, including an empty fence.
//
// Returns:
//   - `Succeeded` only when every handle joins with a successful task result.
//
// Side effects:
//   - Consumes all handles, frees their array, and resets the fence to empty.
task_fence_wait :: proc(pool: ^Task_Pool, fence: ^Task_Fence) -> Task_Result {
    aggregate := Task_Result.Succeeded
    for index in 0..<fence.count {
        result, outcome := task_pool_wait(pool, fence.handles[index])
        if outcome != .Joined || result == .Failed {
            aggregate = .Failed
        } else if result == .Cancelled && aggregate == .Succeeded {
            aggregate = .Cancelled
        }
    }
    delete(fence.handles,
        mem.mutex_allocator(&pool.synchronized_allocator))
    fence.handles = nil
    fence.count = 0
    return aggregate
}

//   Stop admission, drain accepted procedures, and then join pool workers.
//
// Parameters:
//   - pool: The running pool to stop; nil or any other state is a no-op.
//
// Side effects:
//   - Owner drain helping executes Helpable work only; workers execute either class.
//   - Leaves terminal slots available for owner observation in `Stopped`.
task_pool_shutdown :: proc(pool: ^Task_Pool) {
    if pool == nil || pool.state != .Running {
        return
    }
    pool.state = .Stopping
    for {
        task_pool_collect_completed(pool)
        sync.mutex_lock(&pool.scheduler_mutex)
        drained := pool.helpable_ready.count == 0 &&
            pool.worker_only_ready.count == 0 && pool.executing_count == 0
        sync.mutex_unlock(&pool.scheduler_mutex)
        if drained {
            break
        }
        if !task_pool_help_once(pool) {
            task_pool_wait_for_progress(pool)
        }
    }
    task_pool_stop_workers(pool)
    task_pool_collect_completed(pool)
    pool.state = .Stopped
}

//   Stop the pool, abandon unjoined handles, and release every owned resource.
//
// Notes:
//   - Caller payloads are no longer worker-owned after shutdown finishes.
//   - Each still-live slot increments abandoned-terminal telemetry before release.
//
// Parameters:
//   - pool: The initialized pool to destroy; nil or uninitialized is a no-op.
//
// Side effects:
//   - Joins workers, destroys owned dispatch storage, releases virtual memory,
//     and resets the pool to `Uninitialized`.
task_pool_destroy :: proc(pool: ^Task_Pool) {
    if pool == nil || pool.state == .Uninitialized {
        return
    }
    task_pool_shutdown(pool)
    for &slot in pool.slots {
        if slot.state != .Available {
            slot.state = .Available
            pool.abandoned_terminal_count += 1
        }
    }
    pool.outstanding_count = 0
    task_pool_release_backend_storage(pool)
    task_pool_release_allocator(pool)
    pool.state = .Uninitialized
}