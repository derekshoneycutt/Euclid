package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"
import "core:testing"
import storage "../../../core/storage"

// Verify large native control trees preserve hierarchy and unchanged owner storage.
@(test)
native_publication_scales_and_reuses_unchanged_updates :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    controls := make([]Adapter_Control_Input, 5000, context.allocator)
    defer delete(controls, context.allocator)
    native_publication_fill_large_tree(controls)
    input := Adapter_Tree_Input{controls = controls}
    testing.expect(t, adapter_publish_controls(owner, input))
    lease := portable.protected_control_acquire(&owner^.control_publication)
    testing.expect_value(t, lease^.value.control_count, 5000)
    testing.expect_value(t, lease^.value.child_counts[1], 4999)
    testing.expect_value(t, lease^.value.controls[4999].parent_native_id,
        lease^.value.controls[0].native_id)
    testing.expect_value(t, lease^.value.controls[0].active_descendant_native_id,
        lease^.value.controls[4999].native_id)
    testing.expect(t, lease^.value.controls[4999].selected)
    update := accesskit_activation_callback(owner)
    testing.expect(t, update != nil)
    accesskit.accesskit_tree_update_free(update)
    constructions := adapter_diagnostics_snapshot(owner)
    testing.expect_value(t, constructions.control_tree_updates, u64(1))
    testing.expect_value(t, constructions.control_tree_nodes, u64(5001))
    peak := owner^.memory.peak_allocation_count
    for _ in 0..<1000 {
        testing.expect(t, adapter_publish_controls(owner, input))
    }
    testing.expect(t, lease == owner^.control_publication.active)
    testing.expect_value(t, owner^.memory.peak_allocation_count, peak)
    testing.expect_value(t, adapter_diagnostics_snapshot(owner).control_tree_updates,
        constructions.control_tree_updates)
    portable.protected_control_release(&owner^.control_publication, lease)
    adapter_close_admission(owner)
    testing.expect(t, adapter_drain_memory(owner))
    testing.expect(t, !owner^.memory.initialized)
}

// Populate a large sibling set with an offscreen selected active descendant.
native_publication_fill_large_tree :: proc(controls: []Adapter_Control_Input) {
    controls[0] = {
        identity = {domain = .Ui, local_id = 1, generation = 1},
        control = {role = .Tree, label = "Library", enabled = true},
    }
    last := len(controls) - 1
    for index in 1..<len(controls) {
        controls[index] = {
            identity = {domain = .Ui, local_id = u64(index + 1), generation = 1},
            parent_identity = controls[0].identity,
            control = {
                role = .Tree_Item, label = "Committed Library item",
                enabled = true, selected = index == last, actions = {.Select},
                level = 2, position_in_set = u32(index), set_size = u32(last),
            },
        }
    }
    controls[0].active_descendant_identity = controls[last].identity
}

// Two publication batches retain current IDs and reclaim all retired descriptor bytes.
@(test)
native_publication_two_thousand_edits_reuse_live_pressure :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    native_publication_edit_batch(t, owner)
    before := storage.tlsf_owner_diagnostics(&owner^.memory)
    identity := owner^.control_native_ids[0]
    native_publication_edit_batch(t, owner)
    after := storage.tlsf_owner_diagnostics(&owner^.memory)
    testing.expect_value(t, owner^.control_native_ids[0], identity)
    testing.expect_value(t, after.retained_bytes, before.retained_bytes)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, after.peak_live_bytes, before.peak_live_bytes)
    testing.expect_value(t, after.peak_allocation_count, before.peak_allocation_count)
    adapter_close_admission(owner)
    testing.expect(t, adapter_drain_memory(owner))
}

// Publish alternating labels at fixed live identity and text demand.
native_publication_edit_batch :: proc(t: ^testing.T, owner: ^Adapter) {
    control := [1]Adapter_Control_Input{{
        identity = {domain = .Ui, local_id = 1, generation = 1},
        control = {role = .Button, enabled = true},
    }}
    for index in 0..<1000 {
        control[0].control.label = "Edited one" if index % 2 == 0 else "Edited two"
        testing.expect(t, adapter_publish_controls(owner, {controls = control[:]}))
    }
}

// Renaming and sibling movement retain native identity while updating published facts.
@(test)
native_publication_rename_and_move_keep_mapping_identity :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    controls := native_publication_sibling_controls()
    testing.expect(t, adapter_publish_controls(owner, {controls = controls[:]}))
    identity := owner^.control_native_ids[1]
    controls[1].control.label = "After"
    controls[1], controls[2] = controls[2], controls[1]
    controls[1].control.position_in_set = 1
    controls[2].control.position_in_set = 2
    testing.expect(t, adapter_publish_controls(owner, {controls = controls[:]}))
    testing.expect_value(t, owner^.control_native_ids[2], identity)
    lease := portable.protected_control_acquire(&owner^.control_publication)
    testing.expect_value(t, lease^.value.controls[2].native_id, identity)
    testing.expect_value(t, lease^.value.controls[2].position_in_set, u32(2))
    testing.expect_value(t, portable.control_publication_text(
        &lease^.value, lease^.value.controls[2].label_offset,
        lease^.value.controls[2].label_length), "After")
    portable.protected_control_release(&owner^.control_publication, lease)
    adapter_close_admission(owner)
    testing.expect(t, adapter_drain_memory(owner))
}

// Describe two committed siblings under one Library root before local edits.
native_publication_sibling_controls :: proc() -> [3]Adapter_Control_Input {
    return {
        {
            identity = {domain = .Ui, local_id = 1},
            control = {role = .Tree, label = "Library"},
        },
        {
            identity = {domain = .Ui, local_id = 2},
            parent_identity = {domain = .Ui, local_id = 1},
            control = {
                role = .Tree_Item, label = "Before",
                position_in_set = 1, set_size = 2,
            },
        },
        {
            identity = {domain = .Ui, local_id = 3},
            parent_identity = {domain = .Ui, local_id = 1},
            control = {
                role = .Tree_Item, label = "Other",
                position_in_set = 2, set_size = 2,
            },
        },
    }
}

// Verify mapping slots recycle while stale native IDs never target replacement records.
@(test)
native_publication_mapping_churn_and_close_preserve_leases :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    controls := [1]Adapter_Control_Input{{
        identity = {domain = .Ui, local_id = 1, generation = 1},
        control = {role = .Button, label = "Item", enabled = true, actions = {.Activate}},
    }}
    input := Adapter_Tree_Input{controls = controls[:]}
    testing.expect(t, adapter_publish_controls(owner, input))
    old_id := owner^.control_native_ids[0]
    previous := old_id
    for generation in 2..=5000 {
        controls[0].identity.generation = u64(generation)
        testing.expect(t, adapter_publish_controls(owner, input))
        testing.expect(t, owner^.control_native_ids[0] > previous)
        previous = owner^.control_native_ids[0]
    }
    testing.expect(t, owner^.native_ids.count <= 3)
    request := portable.Queued_Action{kind = u16(accesskit.Action.Click),
        target_native_id = old_id,
        publication_generation = owner^.control_publication.current.generation}
    testing.expect_value(t, portable.action_queue_push(&owner^.actions, &request),
        portable.Action_Queue_Status.Ok)
    action: Adapter_Action
    testing.expect_value(t,
        adapter_drain_action(owner, &action), Adapter_Action_Status.Unknown_Target)
    lease := portable.protected_control_acquire(&owner^.control_publication)
    adapter_close_admission(owner)
    testing.expect(t, !adapter_drain_memory(owner))
    testing.expect(t, owner^.memory.initialized)
    testing.expect(t, accesskit_activation_callback(owner) == nil)
    portable.protected_control_release(&owner^.control_publication, lease)
    testing.expect(t, adapter_drain_memory(owner))
}
