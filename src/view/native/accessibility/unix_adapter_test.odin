#+build linux

package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "core:testing"

// Verify native translation builds and transfers one complete root and child update.
@(test)
unix_tree_update_builds_complete_static_tree :: proc(t: ^testing.T) {
    publication: portable.Static_Publication
    testing.expect_value(t,
        portable.publication_build(&publication, 800, 600, true),
        portable.Publication_Status.Ok)
    update := unix_tree_update(&publication)
    testing.expect(t, update != nil)
    if update != nil {accesskit.accesskit_tree_update_free(update)}
}

// Verify native requests copy target, kind, and observed publication generation.
@(test)
unix_action_request_copies_into_bounded_queue :: proc(t: ^testing.T) {
    owner: Adapter
    testing.expect_value(t, portable.publication_build_button(
        &owner.publication.current, {
            present = true, child_id = 2, root_bounds = {0, 0, 800, 600},
            child_bounds = {16, 520, 48, 552}, label = "Restart animation",
            window_focused = true, child_enabled = true,
        }),
        portable.Publication_Status.Ok)
    request := accesskit.Action_Request{
        action = .Click,
        target_node = accesskit.Node_Id(2),
    }
    testing.expect_value(t, unix_copy_action_request(&owner, &request),
        portable.Action_Queue_Status.Ok)
    copied: portable.Queued_Action
    testing.expect(t, portable.action_queue_pop(&owner.actions, &copied))
    testing.expect_value(t, copied.kind, u16(accesskit.Action.Click))
    testing.expect_value(t, copied.target_native_id, u64(2))
    testing.expect_value(t, copied.publication_generation, u64(1))
}

// Verify stale requests reject and current clicks resolve the complete UI identity.
@(test)
unix_action_drain_validates_publication_generation :: proc(t: ^testing.T) {
    owner: Adapter
    identity := portable.Qualified_Identity{
        domain = .Ui, local_id = 2101, generation = 4,
    }
    input := portable.Button_Publication_Input{
        present = true, root_bounds = {0, 0, 800, 600},
        child_bounds = {16, 520, 48, 552}, label = "Restart animation",
        window_focused = true, child_enabled = true, child_focusable = true,
        child_supports_focus = true, child_supports_activate = true,
    }
    testing.expect(t, unix_adapter_create_button(&owner, input, identity))
    defer unix_adapter_destroy(&owner)
    stale := portable.Queued_Action{kind = u16(accesskit.Action.Click),
        target_native_id = owner.child_native_id, publication_generation = 0}
    testing.expect_value(t, portable.action_queue_push(&owner.actions, &stale),
        portable.Action_Queue_Status.Ok)
    action: Adapter_Action
    testing.expect_value(t, unix_adapter_drain_action(&owner, &action),
        Adapter_Action_Status.Stale_Generation)
    current := stale
    current.publication_generation = owner.publication.current.generation
    testing.expect_value(t, portable.action_queue_push(&owner.actions, &current),
        portable.Action_Queue_Status.Ok)
    testing.expect_value(t, unix_adapter_drain_action(&owner, &action),
        Adapter_Action_Status.Ok)
    testing.expect_value(t, action.kind, Adapter_Action_Kind.Activate)
    testing.expect_value(t, action.identity, identity)
}

// Verify removal retires the native ID and publishes a valid root-only tree.
@(test)
unix_button_removal_retires_identity :: proc(t: ^testing.T) {
    owner: Adapter
    identity := portable.Qualified_Identity{domain = .Ui, local_id = 2101}
    input := portable.Button_Publication_Input{
        present = true, root_bounds = {0, 0, 800, 600},
        child_bounds = {16, 520, 48, 552}, label = "Restart animation",
        child_enabled = true, child_focusable = true,
        child_supports_focus = true, child_supports_activate = true,
    }
    testing.expect(t, unix_adapter_create_button(&owner, input, identity))
    defer unix_adapter_destroy(&owner)
    retired_id := owner.child_native_id
    input.present = false
    testing.expect(t, unix_adapter_publish_button(&owner, input, {}))
    _, found := portable.native_id_lookup(&owner.native_ids, retired_id)
    testing.expect(t, !found)
    testing.expect(t, !owner.publication.current.child_present)
    update := unix_tree_update(&owner.publication.current)
    testing.expect(t, update != nil)
    if update != nil {accesskit.accesskit_tree_update_free(update)}
}

// Verify closing publication storage prevents a late activation callback.
@(test)
unix_activation_rejects_callback_after_close :: proc(t: ^testing.T) {
    owner: Adapter
    testing.expect_value(t,
        portable.protected_publish(&owner.publication, 800, 600, true),
        portable.Publication_Status.Ok)
    portable.protected_close(&owner.publication)
    testing.expect(t, unix_activation_callback(&owner) == nil)
    diagnostics := adapter_diagnostics_snapshot(&owner)
    testing.expect_value(t, diagnostics.activations, 1)
    testing.expect_value(t, diagnostics.rejected_callbacks, 1)
}

// Verify injected partial construction unwinds callback-visible publication.
@(test)
unix_adapter_unwinds_injected_construction_failure :: proc(t: ^testing.T) {
    owner: Adapter
    testing.expect(t, !unix_adapter_create(
        &owner, 800, 600, true, .After_Publication))
    testing.expect(t, owner.native == nil)
    testing.expect(t, unix_activation_callback(&owner) == nil)
    request := portable.Queued_Action{target_native_id = 2}
    testing.expect_value(t,
        portable.action_queue_push(&owner.actions, &request),
        portable.Action_Queue_Status.Closing)
    unix_adapter_destroy(&owner)
    diagnostics := adapter_diagnostics_snapshot(&owner)
    testing.expect_value(t, diagnostics.rejected_callbacks, 1)
    testing.expect_value(t, diagnostics.destroys, 1)
}

// Verify service deactivation remains observable without touching publication state.
@(test)
unix_adapter_records_service_deactivation :: proc(t: ^testing.T) {
    owner: Adapter
    testing.expect_value(t,
        portable.protected_publish(&owner.publication, 800, 600, true),
        portable.Publication_Status.Ok)
    unix_deactivation_callback(&owner)
    publication: portable.Static_Publication
    testing.expect(t,
        portable.protected_snapshot(&owner.publication, &publication))
    diagnostics := adapter_diagnostics_snapshot(&owner)
    testing.expect_value(t, diagnostics.deactivations, 1)
}