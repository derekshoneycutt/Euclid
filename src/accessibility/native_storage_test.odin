package accessibility

import "core:testing"

// Verify native IDs are monotonic, reversible, retired, and never reused.
@(test)
native_id_registry_preserves_session_identity :: proc(t: ^testing.T) {
    registry: Native_Id_Registry
    native_id_registry_init(&registry)
    root, root_ok := native_id_lookup(&registry, SYNTHETIC_NATIVE_ID)
    testing.expect(t, root_ok)
    testing.expect_value(t, root.domain, Identity_Domain.Synthetic)
    child := Qualified_Identity{domain = .Ui, local_id = 42, generation = 3}
    child_id, child_ok := native_id_resolve(&registry, child)
    testing.expect(t, child_ok)
    testing.expect_value(t, child_id, u64(2))
    duplicate_id, duplicate_ok := native_id_resolve(&registry, child)
    testing.expect(t, duplicate_ok)
    testing.expect_value(t, duplicate_id, child_id)
    testing.expect(t, native_id_retire(&registry, child_id))
    _, retired_ok := native_id_lookup(&registry, child_id)
    testing.expect(t, !retired_ok)
    replacement := child
    replacement.generation += 1
    replacement_id, replacement_ok := native_id_resolve(&registry, replacement)
    testing.expect(t, replacement_ok)
    testing.expect_value(t, replacement_id, child_id + 1)
    testing.expect_value(t, registry.diagnostics.retired, 1)
}

// Verify the registry rejects exhaustion without wrapping or retargeting IDs.
@(test)
native_id_registry_rejects_capacity_exhaustion :: proc(t: ^testing.T) {
    registry: Native_Id_Registry
    native_id_registry_init(&registry)
    for local_id in 2..=NATIVE_ID_CAPACITY {
        _, ok := native_id_resolve(&registry, {
            domain = .Ui,
            local_id = u64(local_id),
        })
        testing.expect(t, ok)
    }
    native_id, ok := native_id_resolve(&registry, {
        domain = .Ui,
        local_id = u64(NATIVE_ID_CAPACITY + 1),
    })
    testing.expect(t, !ok)
    testing.expect_value(t, native_id, u64(0))
    testing.expect_value(t, registry.diagnostics.exhaustion, 1)
}

// Verify callback ingress is FIFO, bounded, and denied after close.
@(test)
action_queue_is_bounded_and_closeable :: proc(t: ^testing.T) {
    queue: Action_Queue
    first := Queued_Action{kind = 1, target_native_id = 2,
        publication_generation = 7}
    second := Queued_Action{kind = 2, target_native_id = 3,
        publication_generation = 7}
    testing.expect_value(t, action_queue_push(&queue, &first),
        Action_Queue_Status.Ok)
    testing.expect_value(t, action_queue_push(&queue, &second),
        Action_Queue_Status.Ok)
    drained: Queued_Action
    testing.expect(t, action_queue_pop(&queue, &drained))
    testing.expect_value(t, drained.kind, u16(1))
    action_queue_close(&queue)
    testing.expect_value(t, action_queue_push(&queue, &first),
        Action_Queue_Status.Closing)
    testing.expect(t, action_queue_pop(&queue, &drained))
    testing.expect_value(t, drained.kind, u16(2))
    diagnostics := action_queue_diagnostics_snapshot(&queue)
    testing.expect_value(t, diagnostics.accepted, 2)
    testing.expect_value(t, diagnostics.drained, 2)
    testing.expect_value(t, diagnostics.closing_rejections, 1)
}

// Verify malformed payloads and full queues are rejected without overwrite.
@(test)
action_queue_rejects_invalid_and_overflowing_requests :: proc(t: ^testing.T) {
    queue: Action_Queue
    invalid := Queued_Action{target_native_id = 2,
        payload_length = ACTION_PAYLOAD_CAPACITY + 1}
    testing.expect_value(t, action_queue_push(&queue, &invalid),
        Action_Queue_Status.Payload_Overflow)
    request := Queued_Action{target_native_id = 2}
    for _ in 0..<ACTION_QUEUE_CAPACITY {
        testing.expect_value(t, action_queue_push(&queue, &request),
            Action_Queue_Status.Ok)
    }
    testing.expect_value(t, action_queue_push(&queue, &request),
        Action_Queue_Status.Full)
    diagnostics := action_queue_diagnostics_snapshot(&queue)
    testing.expect_value(t, diagnostics.invalid_requests, 1)
    testing.expect_value(t, diagnostics.overflows, 1)
    testing.expect_value(t, diagnostics.peak_count, ACTION_QUEUE_CAPACITY)
}
