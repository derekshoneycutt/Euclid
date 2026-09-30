package accessibility

import "core:testing"

// Verify mixed ordinary controls retain complete native-ready semantic facts.
@(test)
control_tree_builds_mixed_ordinary_controls :: proc(t: ^testing.T) {
    controls := [3]Control_Publication_Input{
        {native_id = 2, role = .Button, bounds = {10, 10, 40, 30},
            label = "Restart animation", actions = {.Focus, .Activate},
            enabled = true, focusable = true, focused = true},
        {native_id = 3, role = .Checkbox, bounds = {10, 40, 160, 64},
            label = "Limit frame rate", actions = {.Focus, .Toggle},
            enabled = true, focusable = true, checked = true},
        {native_id = 4, role = .Slider, bounds = {10, 70, 180, 94},
            label = "Maximum dust", value = "50000",
            actions = {.Focus, .Increment, .Decrement, .Set_To_Bound},
            range = {0, 100000, 50000, 1000, false, true},
            enabled = true, focusable = true},
    }
    value: Control_Tree_Publication
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, window_focused = true,
        controls = controls[:],
    }), Publication_Status.Ok)
    testing.expect_value(t, value.control_count, 3)
    testing.expect_value(t, value.controls[0].role, Publication_Role.Button)
    testing.expect(t, value.controls[1].checked)
    testing.expect_value(t, value.controls[2].range.current, f64(50000))
    testing.expect_value(t, control_publication_text(&value,
        value.controls[2].value_offset, value.controls[2].value_length), "50000")
}

// Verify nested Phase 4 controls retain hierarchy and active descendant identity.
@(test)
control_tree_builds_search_and_tree_hierarchy :: proc(t: ^testing.T) {
    controls := [5]Control_Publication_Input{
        {native_id = 2, controls_native_id = 3, role = .Search_Input,
            bounds = {10, 10, 220, 40}, label = "Search animations",
            enabled = true, focusable = true, text_present = true},
        {native_id = 6, parent_native_id = 2, role = .Text_Run,
            bounds = {14, 14, 216, 36}, value = "axiom",
            enabled = true, text_present = true},
        {native_id = 3, role = .Tree, bounds = {10, 48, 280, 400},
            label = "Animation library", active_descendant_native_id = 5,
            enabled = true, focusable = true},
        {native_id = 4, parent_native_id = 3, role = .Tree_Item,
            bounds = {10, 48, 280, 72}, label = "Elements", enabled = true},
        {native_id = 5, parent_native_id = 4, role = .Tree_Item,
            bounds = {26, 72, 280, 96}, label = "Proposition I",
            enabled = true, selected = true},
    }
    value: Control_Tree_Publication
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Ok)
    testing.expect_value(t, value.controls[0].parent_native_id, value.root_id)
    testing.expect_value(t, value.controls[4].parent_native_id, u64(4))
    testing.expect_value(t, value.controls[2].active_descendant_native_id, u64(5))
    testing.expect_value(t, value.controls[0].controls_native_id, u64(3))
    testing.expect_value(t, value.controls[1].parent_native_id, u64(2))
    testing.expect_value(t, value.controls[1].role, Publication_Role.Text_Run)
}

// Verify editable text copies UTF-8 widths and byte selections as characters.
@(test)
control_tree_builds_utf8_editable_text :: proc(t: ^testing.T) {
    controls := [1]Control_Publication_Input{{
        native_id = 2, role = .Search_Input, bounds = {10, 10, 220, 40},
        label = "Search animations", value = "aβc", placeholder = "Search",
        enabled = true, focusable = true, text_present = true,
        text_cursor_byte = 3, text_anchor_byte = 1,
    }}
    value: Control_Tree_Publication
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Ok)
    text := value.controls[0]
    testing.expect_value(t, text.character_count, u16(3))
    testing.expect_value(t, value.character_lengths[0], u8(1))
    testing.expect_value(t, value.character_lengths[1], u8(2))
    testing.expect_value(t, value.character_lengths[2], u8(1))
    testing.expect_value(t, text.cursor_character, u16(2))
    testing.expect_value(t, text.anchor_character, u16(1))
    testing.expect_value(t, text.word_start_count, u16(1))
    testing.expect_value(t, value.word_starts[text.word_start_offset], u8(0))
    testing.expect_value(t, control_publication_text(&value,
        text.placeholder_offset, text.placeholder_length), "Search")
}

// Verify editable text rejects selection offsets inside a UTF-8 sequence.
@(test)
control_tree_rejects_non_boundary_text_selection :: proc(t: ^testing.T) {
    controls := [1]Control_Publication_Input{{
        native_id = 2, role = .Search_Input, bounds = {10, 10, 220, 40},
        value = "aβc", text_present = true,
        text_cursor_byte = 2, text_anchor_byte = 0,
    }}
    value: Control_Tree_Publication
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Invalid_Utf8)
}

// Verify malformed Phase 4 hierarchy cannot replace a complete publication.
@(test)
control_tree_rejects_dangling_cycles_and_unrelated_active_descendants :: proc(
    t: ^testing.T) {
    controls := [2]Control_Publication_Input{
        {native_id = 2, role = .Tree, bounds = {0, 0, 200, 200},
            label = "Library", enabled = true},
        {native_id = 3, parent_native_id = 2, role = .Tree_Item,
            bounds = {0, 0, 200, 24}, label = "Item", enabled = true},
    }
    value: Control_Tree_Publication
    controls[1].parent_native_id = 99
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Missing_Parent)
    controls[0].parent_native_id = 3
    controls[1].parent_native_id = 2
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Cycle)
    controls[0].parent_native_id = 0
    controls[0].active_descendant_native_id = 3
    controls[1].parent_native_id = 0
    testing.expect_value(t, control_tree_build(&value, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), Publication_Status.Unreachable_Node)
}

// Verify identical trees suppress generations and invalid ranges preserve state.
@(test)
protected_control_tree_suppresses_and_preserves :: proc(t: ^testing.T) {
    controls := [1]Control_Publication_Input{{
        native_id = 2, role = .Slider, bounds = {10, 10, 180, 34},
        label = "Output scale", actions = {.Focus, .Increment, .Decrement},
        range = {1, 8, 2, 1, false, true}, enabled = true, focusable = true,
    }}
    protected: Protected_Control_Publication
    input := Tree_Publication_Input{
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }
    testing.expect_value(t, protected_publish_controls(&protected, input),
        Publication_Status.Ok)
    testing.expect_value(t, protected_publish_controls(&protected, input),
        Publication_Status.Ok)
    testing.expect_value(t, protected.current.generation, u64(1))
    controls[0].range.current = 9
    testing.expect_value(t, protected_publish_controls(&protected, input),
        Publication_Status.Invalid_Bounds)
    testing.expect_value(t, protected.current.generation, u64(1))
}

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