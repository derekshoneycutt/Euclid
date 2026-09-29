package accessibility

import "core:testing"

// Verify the Phase 1 fixture is complete, stable, and snapshot-owned.
@(test)
publication_builds_static_root_and_child :: proc(t: ^testing.T) {
    value: Static_Publication
    testing.expect_value(t, publication_build(&value, 800, 600, true),
        Publication_Status.Ok)
    testing.expect_value(t, value.root_id, SYNTHETIC_ROOT_ID)
    testing.expect(t, value.child_present)
    testing.expect_value(t, value.child_parent_id, value.root_id)
    testing.expect_value(t, value.generation, 1)
    testing.expect(t, value.window_focused)
    testing.expect_value(t,
        string(value.label[:value.label_length]), "Euclid workspace")
}

// Verify identical button frames are suppressed and removal publishes a root-only tree.
@(test)
protected_button_publication_differences_complete_records :: proc(t: ^testing.T) {
    protected: Protected_Publication
    input := Button_Publication_Input{
        present = true,
        child_id = 2,
        root_bounds = {0, 0, 800, 600},
        child_bounds = {16, 520, 48, 552},
        label = "Restart animation",
        window_focused = true,
        child_enabled = true,
        child_focusable = true,
        child_supports_focus = true,
        child_supports_activate = true,
    }
    testing.expect_value(t, protected_publish_button(&protected, input),
        Publication_Status.Ok)
    testing.expect_value(t, protected.current.generation, u64(1))
    testing.expect_value(t, protected_publish_button(&protected, input),
        Publication_Status.Ok)
    testing.expect_value(t, protected.current.generation, u64(1))
    input.present = false
    testing.expect_value(t, protected_publish_button(&protected, input),
        Publication_Status.Ok)
    testing.expect_value(t, protected.current.generation, u64(2))
    testing.expect(t, !protected.current.child_present)
    testing.expect_value(t, publication_validate(&protected.current),
        Publication_Status.Ok)
}

// Verify the Phase 2 fixture retains exact real-button role, state, and actions.
@(test)
publication_builds_real_button :: proc(t: ^testing.T) {
    value: Static_Publication
    status := publication_build_button(&value, {
        present = true, child_id = 12, root_bounds = {0, 0, 800, 600},
        child_bounds = {16, 520, 48, 552}, label = "Restart animation",
        window_focused = true, child_enabled = true, child_focused = true,
    })
    testing.expect_value(t, status, Publication_Status.Ok)
    testing.expect_value(t, value.child_role, Publication_Role.Button)
    testing.expect_value(t, value.child_id, u64(12))
    testing.expect(t, value.window_focused)
    testing.expect(t, value.child_enabled)
    testing.expect(t, value.child_focusable)
    testing.expect(t, value.child_focused)
    testing.expect(t, value.child_supports_focus)
    testing.expect(t, value.child_supports_activate)
    testing.expect_value(t,
        string(value.label[:value.label_length]), "Restart animation")
}

// Verify each malformed static-tree class is rejected before native translation.
@(test)
publication_rejects_malformed_tree_facts :: proc(t: ^testing.T) {
    valid: Static_Publication
    testing.expect_value(t, publication_build(&valid, 800, 600, true),
        Publication_Status.Ok)
    candidate := valid
    candidate.child_id = candidate.root_id
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Duplicate_Id)
    candidate = valid
    candidate.child_parent_id = 0
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Missing_Parent)
    candidate = valid
    candidate.child_parent_id = candidate.child_id
    testing.expect_value(t, publication_validate(&candidate), Publication_Status.Cycle)
    candidate = valid
    candidate.child_parent_id = 99
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Unreachable_Node)
    candidate = valid
    candidate.label[0] = 0xff
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Invalid_Utf8)
    candidate = valid
    candidate.label_length = STATIC_LABEL_CAPACITY + 1
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Capacity)
    candidate = valid
    candidate.child_bounds.x0 = 2
    candidate.child_bounds.x1 = 1
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Invalid_Bounds)
    candidate = valid
    candidate.root_bounds.x0 = transmute(f64)u64(0x7ff8000000000000)
    testing.expect_value(t, publication_validate(&candidate),
        Publication_Status.Invalid_Bounds)
}

// Verify invalid replacement preserves the last good protected generation.
@(test)
protected_publication_preserves_last_good_value :: proc(t: ^testing.T) {
    protected: Protected_Publication
    testing.expect_value(t, protected_publish(&protected, 800, 600, false),
        Publication_Status.Ok)
    testing.expect_value(t,
        protected_publish(&protected,
            transmute(f64)u64(0x7ff8000000000000), 600, true),
        Publication_Status.Invalid_Bounds)
    snapshot: Static_Publication
    testing.expect(t, protected_snapshot(&protected, &snapshot))
    testing.expect_value(t, snapshot.generation, 1)
    testing.expect(t, !snapshot.window_focused)
    testing.expect_value(t, protected_publish(&protected, 800, 600, false),
        Publication_Status.Ok)
    testing.expect(t, protected_snapshot(&protected, &snapshot))
    testing.expect_value(t, snapshot.generation, 1)
    protected_close(&protected)
    testing.expect(t, !protected_snapshot(&protected, &snapshot))
}

// Verify meaningful host bounds and focus changes advance publication generations.
@(test)
protected_publication_tracks_bounds_and_host_focus :: proc(t: ^testing.T) {
    protected: Protected_Publication
    testing.expect_value(t, protected_publish(&protected, 800, 600, false),
        Publication_Status.Ok)
    snapshot: Static_Publication
    testing.expect(t, protected_snapshot(&protected, &snapshot))
    testing.expect_value(t, snapshot.generation, 1)
    testing.expect_value(t, protected_publish(&protected, 1024, 768, false),
        Publication_Status.Ok)
    testing.expect(t, protected_snapshot(&protected, &snapshot))
    testing.expect_value(t, snapshot.generation, 2)
    testing.expect_value(t, snapshot.root_bounds.x1, f64(1024))
    testing.expect_value(t, protected_publish(&protected, 1024, 768, true),
        Publication_Status.Ok)
    testing.expect(t, protected_snapshot(&protected, &snapshot))
    testing.expect_value(t, snapshot.generation, 3)
    testing.expect(t, snapshot.window_focused)
}