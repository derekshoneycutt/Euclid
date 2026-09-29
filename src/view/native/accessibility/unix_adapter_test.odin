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