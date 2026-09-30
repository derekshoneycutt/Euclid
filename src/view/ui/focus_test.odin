package ui

import viewmodel "../model"
import input "../input"

import "core:encoding/uuid"
import "core:testing"

// semantic_test_id constructs one static domain-qualified test identity.
semantic_test_id :: proc(
    domain: viewmodel.Ui_Node_Domain, local_id: u64,
    generation: u64 = 0) -> viewmodel.Ui_Node_Id {
    return {domain = domain, local_id = local_id, generation = generation}
}

// semantic_test_node constructs one visible and enabled focus candidate.
semantic_test_node :: proc(
    id: viewmodel.Ui_Node_Id, parent: viewmodel.Ui_Node_Id = {},
    region: viewmodel.Ui_Focus_Region = .Accordion_Content,
    order: u16 = 0) -> viewmodel.Ui_Semantic_Node {
    return {
        id = id,
        parent = parent,
        role = .Button,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Activate},
        region = region,
        traversal_order = order,
    }
}

// Verify complete domain, UUID, and generation identity prevents aliases.
@(test)
semantic_identity_is_domain_and_generation_qualified :: proc(t: ^testing.T) {
    stable_id, read_error := uuid.read("11111111-1111-4111-8111-111111111111")
    testing.expect(t, read_error == nil)
    base := viewmodel.Ui_Node_Id{
        domain = .Animation_Tree, stable_id = stable_id, generation = 1}
    other_domain := base
    other_domain.domain = .Presentation
    other_generation := base
    other_generation.generation = 2

    testing.expect(t, base != other_domain)
    testing.expect(t, base != other_generation)
    testing.expect(t, base == base)
}

// Verify registration owns UTF-8 and committed publication survives source mutation.
@(test)
semantic_registration_owns_utf8_and_publishes_atomically :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    label := [6]u8{'R', 'e', 's', 'u', 'm', 'e'}
    testing.expect(t, semantic_begin(state))
    status := semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Animation_Control, 1)),
        label = string(label[:]),
        value = "Ready",
    })
    label[0] = 'X'

    testing.expect_value(t, status, viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    snapshot := semantic_snapshot(state)
    node := snapshot^.nodes[0]
    testing.expect_value(t,
        semantic_node_text(snapshot, node.label_offset, node.label_length), "Resume")
    testing.expect_value(t,
        semantic_node_text(snapshot, node.value_offset, node.value_length), "Ready")
    testing.expect_value(t, snapshot^.generation, u64(1))
    testing.expect_value(t, state^.logical_focus, viewmodel.Ui_Node_Id{})
}

// Verify duplicate identity rejects the whole staging tree and retains the commit.
@(test)
semantic_duplicate_rejects_publication :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    id := semantic_test_id(.Settings_Control, 1)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state,
        {node = semantic_test_node(id), label = "First"}),
        viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    committed := state^.committed_index

    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state,
        {node = semantic_test_node(id), label = "First"}),
        viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state,
        {node = semantic_test_node(id), label = "Duplicate"}),
        viewmodel.Ui_Semantic_Status.Duplicate_Id)
    testing.expect_value(t, semantic_publish(state),
        viewmodel.Ui_Semantic_Status.Duplicate_Id)
    testing.expect_value(t, state^.committed_index, committed)
    testing.expect_value(t, semantic_snapshot(state)^.node_count, 1)
}

// Verify missing parents and colliding focus order reject complete publication.
@(test)
semantic_validation_rejects_invalid_relations :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    missing := semantic_test_id(.Accordion, 9)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Library_Control, 1), missing),
        label = "Search",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state),
        viewmodel.Ui_Semantic_Status.Missing_Parent)

    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Settings_Control, 1), {},
            .Accordion_Content, 4), label = "First",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Settings_Control, 2), {},
            .Accordion_Content, 4), label = "Second",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state),
        viewmodel.Ui_Semantic_Status.Traversal_Collision)
}

// Verify malformed UTF-8 and text overflow leave node and text counts unchanged.
@(test)
semantic_registration_rejects_text_atomically :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    invalid := [1]u8{0xff}
    testing.expect(t, semantic_begin(state))
    staging := semantic_staging_snapshot(state)
    staging^.text_count = viewmodel.UI_SEMANTIC_TEXT_CAPACITY - 1
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Gif_Control, 1)),
        label = "Too long",
    }), viewmodel.Ui_Semantic_Status.Text_Capacity)
    testing.expect_value(t, staging^.node_count, 0)
    testing.expect_value(t, staging^.text_count,
        viewmodel.UI_SEMANTIC_TEXT_CAPACITY - 1)

    testing.expect(t, semantic_begin(state))
    staging = semantic_staging_snapshot(state)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Gif_Control, 2)),
        label = string(invalid[:]),
    }), viewmodel.Ui_Semantic_Status.Invalid_Utf8)
    testing.expect_value(t, staging^.node_count, 0)
    testing.expect_value(t, staging^.text_count, 0)
}

// Verify maximum node capacity publishes and rejects one additional node atomically.
@(test)
semantic_registration_enforces_node_capacity :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, semantic_begin(state))
    for index in 0..<viewmodel.UI_SEMANTIC_NODE_CAPACITY {
        testing.expect_value(t, semantic_register_node(state, {
            node = semantic_test_node(semantic_test_id(.Application, u64(index + 1)),
                {}, .Animation_Overlay, u16(index)),
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_snapshot(state)^.node_count,
        viewmodel.UI_SEMANTIC_NODE_CAPACITY)
    testing.expect_value(t, state^.diagnostics.node_high_water,
        viewmodel.UI_SEMANTIC_NODE_CAPACITY)

    testing.expect(t, semantic_begin(state))
    staging := semantic_staging_snapshot(state)
    staging^.node_count = viewmodel.UI_SEMANTIC_NODE_CAPACITY
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Application, 9999)),
        label = "Overflow",
    }), viewmodel.Ui_Semantic_Status.Node_Capacity)
    testing.expect_value(t, staging^.node_count,
        viewmodel.UI_SEMANTIC_NODE_CAPACITY)
    testing.expect_value(t, staging^.text_count, 0)
}

// Verify the complete owned-text capacity is accepted and tracked as a high water.
@(test)
semantic_registration_accepts_maximum_text_capacity :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    half := viewmodel.UI_SEMANTIC_TEXT_CAPACITY / 2
    text := make([]u8, half, context.allocator)
    defer delete(text, context.allocator)
    for &byte in text {byte = 'a'}
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Application, 1), {},
            .Animation_Overlay, 0), label = string(text),
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(semantic_test_id(.Application, 2), {},
            .Animation_Overlay, 1), label = string(text),
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_snapshot(state)^.text_count,
        viewmodel.UI_SEMANTIC_TEXT_CAPACITY)
    testing.expect_value(t, state^.diagnostics.text_high_water,
        viewmodel.UI_SEMANTIC_TEXT_CAPACITY)
}

// Verify retired and disabled focus repairs by prior region order, then clears on empty.
@(test)
semantic_focus_repairs_deterministically :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    first := semantic_test_id(.Settings_Control, 1)
    middle := semantic_test_id(.Settings_Control, 2)
    last := semantic_test_id(.Settings_Control, 3)
    ids := [3]viewmodel.Ui_Node_Id{first, middle, last}
    testing.expect(t, semantic_begin(state))
    for id, index in ids {
        testing.expect_value(t, semantic_register_node(state, {
            node = semantic_test_node(id, {}, .Accordion_Content, u16(index)),
            label = "Control",
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = middle
    state^.focus_origin = .Keyboard

    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(first, {}, .Accordion_Content, 0), label = "First",
    }), viewmodel.Ui_Semantic_Status.Ok)
    disabled_middle := semantic_test_node(middle, {}, .Accordion_Content, 1)
    disabled_middle.states -= {.Enabled}
    testing.expect_value(t, semantic_register_node(state, {
        node = disabled_middle, label = "Disabled",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(last, {}, .Accordion_Content, 2), label = "Last",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, state^.logical_focus, last)
    testing.expect_value(t, state^.focus_origin, viewmodel.Ui_Focus_Origin.Keyboard)

    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, state^.logical_focus, viewmodel.Ui_Node_Id{})
}

// Verify a retired focused child repairs to its nearest sibling before its parent.
@(test)
semantic_focus_repairs_within_composite_first :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    parent := semantic_test_id(.Animation_Tree, 1)
    first := semantic_test_id(.Animation_Tree, 2)
    middle := semantic_test_id(.Animation_Tree, 3)
    last := semantic_test_id(.Animation_Tree, 4)
    testing.expect(t, semantic_begin(state))
    ids := [4]viewmodel.Ui_Node_Id{parent, first, middle, last}
    for id, index in ids {
        node_parent := index == 0 ? viewmodel.Ui_Node_Id{} : parent
        testing.expect_value(t, semantic_register_node(state, {
            node = semantic_test_node(id, node_parent, .Accordion_Content,
                u16(index)), label = "Tree node",
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = middle

    testing.expect(t, semantic_begin(state))
    remaining := [3]viewmodel.Ui_Node_Id{parent, first, last}
    orders := [3]u16{0, 1, 3}
    for id, index in remaining {
        node_parent := index == 0 ? viewmodel.Ui_Node_Id{} : parent
        testing.expect_value(t, semantic_register_node(state, {
            node = semantic_test_node(id, node_parent, .Accordion_Content,
                orders[index]), label = "Tree node",
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, state^.logical_focus, last)
}

// Verify global traversal follows explicit region order, reverses, and wraps.
@(test)
semantic_keyboard_traversal_is_ordered_and_bounded :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    first := semantic_test_id(.Animation_Control, 1)
    second := semantic_test_id(.Accordion, 1)
    third := semantic_test_id(.Settings_Control, 1)
    testing.expect(t, semantic_begin(state))
    nodes := [3]viewmodel.Ui_Semantic_Node{
        semantic_test_node(third, {}, .Accordion_Content, 0),
        semantic_test_node(first, {}, .Animation_Overlay, 4),
        semantic_test_node(second, {}, .Accordion_Headers, 2),
    }
    for node in nodes {
        testing.expect_value(t, semantic_register_node(state,
            {node = node, label = "Control"}), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    events := [1]input.Input_Event{{kind = .Press, key = .Tab}}

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, claims.claimed[0])
    testing.expect_value(t, state^.logical_focus, first)
    _ = semantic_route_keyboard(state, {events = events[:]})
    testing.expect_value(t, state^.logical_focus, second)
    events[0].modifiers = {.Shift}
    _ = semantic_route_keyboard(state, {events = events[:]})
    testing.expect_value(t, state^.logical_focus, first)
    _ = semantic_route_keyboard(state, {events = events[:]})
    testing.expect_value(t, state^.logical_focus, third)
}

// Verify tree descendants anchor traversal at their containing global stop.
@(test)
semantic_keyboard_traversal_uses_composite_anchor :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    tree := semantic_test_id(.Animation_Tree, 1)
    item := semantic_test_id(.Animation_Tree, 2)
    after := semantic_test_id(.Settings_Control, 1)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(tree, {}, .Accordion_Content, 1),
        label = "Animations",
    }), viewmodel.Ui_Semantic_Status.Ok)
    item_node := semantic_test_node(item, tree, .Accordion_Content, 1)
    item_node.states -= {.Tab_Stop}
    testing.expect_value(t, semantic_register_node(state,
        {node = item_node, label = "Item"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(after, {}, .Accordion_Content, 2),
        label = "After",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = item
    events := [1]input.Input_Event{{kind = .Press, key = .Tab}}

    _ = semantic_route_keyboard(state, {events = events[:]})
    testing.expect_value(t, state^.logical_focus, after)
}

// Verify Terminal keeps plain Tab while Ctrl+Tab escapes without an action leak.
@(test)
semantic_terminal_escape_preserves_plain_tab :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    terminal := semantic_test_id(.Terminal, 1)
    after := semantic_test_id(.Accordion, 1)
    testing.expect(t, semantic_begin(state))
    terminal_node := semantic_test_node(terminal, {}, .Presentation, 1)
    terminal_node.role = .Terminal
    testing.expect_value(t, semantic_register_node(state,
        {node = terminal_node, label = "Terminal"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(after, {}, .Animation_Overlay, 1), label = "After",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = terminal
    events := [1]input.Input_Event{{kind = .Press, key = .Tab}}

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, !claims.claimed[0])
    testing.expect_value(t, state^.logical_focus, terminal)
    events[0].modifiers = {.Control}
    claims = semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, claims.claimed[0])
    testing.expect_value(t, state^.logical_focus, after)
}

// Verify role commands claim one event and remain addressed to current focus.
@(test)
semantic_keyboard_routes_role_commands :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    slider := semantic_test_id(.Settings_Control, 1)
    testing.expect(t, semantic_begin(state))
    node := semantic_test_node(slider)
    node.role = .Slider
    node.actions = {.Focus, .Increment, .Decrement, .Set_To_Bound}
    testing.expect_value(t, semantic_register_node(state,
        {node = node, label = "Maximum particles"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = slider
    events := [2]input.Input_Event{
        {kind = .Repeat, key = .Right},
        {kind = .Press, key = .Page_Down},
    }

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, claims.claimed[0] && claims.claimed[1])
    testing.expect_value(t, state^.command_count, 2)
    testing.expect_value(t, state^.commands[0].kind,
        viewmodel.Ui_Focus_Command_Kind.Increment)
    testing.expect_value(t, state^.commands[1].kind,
        viewmodel.Ui_Focus_Command_Kind.Page_Step)
    testing.expect_value(t, state^.commands[1].amount, i32(-1))
    testing.expect_value(t, state^.commands[1].target, slider)
}

// Verify absent semantic stops never intercept ordinary or legacy Terminal Tab.
@(test)
semantic_keyboard_leaves_tab_unclaimed_without_target :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    events := [1]input.Input_Event{{kind = .Press, key = .Tab}}

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, !claims.claimed[0])
    claims = semantic_route_keyboard(state, {events = events[:]}, true)
    testing.expect(t, !claims.claimed[0])
}

// Verify Terminal ownership suppresses commands addressed to stale control focus.
@(test)
semantic_terminal_ownership_suppresses_control_commands :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    button := semantic_test_id(.Accordion, 1)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(button), label = "Library",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = button
    events := [1]input.Input_Event{{kind = .Press, key = .Enter}}

    claims := semantic_route_keyboard(state, {events = events[:]}, true)
    testing.expect(t, !claims.claimed[0])
    testing.expect_value(t, state^.command_count, 0)
}

// Verify publication marks only effective keyboard-origin focus as visible.
@(test)
semantic_publication_marks_keyboard_focus_visible :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    button := semantic_test_id(.Animation_Control, 1)
    state^.logical_focus = button
    state^.focus_origin = .Keyboard
    state^.window_focused = true
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_control(state, {
        id = button, role = .Button,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Activate}, region = .Animation_Overlay,
        label = "Restart animation",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, .Focus_Visible in semantic_snapshot(state)^.nodes[0].states)

    state^.focus_origin = .Pointer
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_control(state, {
        id = button, role = .Button,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Activate}, region = .Animation_Overlay,
        label = "Restart animation",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, .Focus_Visible not_in semantic_snapshot(state)^.nodes[0].states)
}

// Verify native-style focus and activation converge through current semantic facts.
@(test)
semantic_external_button_actions_validate_and_coalesce :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    button := semantic_test_id(.Animation_Control, 2101)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_control(state, {
        id = button, role = .Button,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Activate}, region = .Animation_Overlay,
        label = "Restart animation",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, semantic_apply_external_action(state, button, .Focus))
    testing.expect_value(t, state.logical_focus, button)
    testing.expect(t, semantic_apply_external_action(state, button, .Activate))
    testing.expect(t, semantic_apply_external_action(state, button, .Activate))
    testing.expect(t, semantic_command_requested(state, button, .Activate))
    action := button_resolve_action({
        semantics = {focus = state, id = button,
            states = {.Visible, .Enabled, .Focusable}},
        pointer_activated = true,
    })
    testing.expect(t, action.activated)
    testing.expect(t, .Pointer in action.sources && .Semantic in action.sources)
}

// Verify native ranged values retain their exact payload for the current owner.
@(test)
semantic_external_slider_value_retains_payload :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    slider := semantic_test_id(.Settings_Control, 6101)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_control(state, {
        id = slider, role = .Slider,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Increment, .Decrement, .Set_Value},
        numeric_range = {0, 100, 25, 1, .Horizontal, true},
        label = "Maximum Dust particles",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, semantic_apply_external_action(state, slider, .Set_Value, 42))
    testing.expect_value(t, state^.command_count, 1)
    testing.expect_value(t, state^.commands[0].numeric_value, f64(42))
}

// Verify disabled and stale external targets cannot focus or activate.
@(test)
semantic_external_button_actions_reject_invalid_targets :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    button := semantic_test_id(.Animation_Control, 2101)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_control(state, {
        id = button, role = .Button, states = {.Visible, .Focusable},
        actions = {.Focus, .Activate}, label = "Restart animation",
    }), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, !semantic_apply_external_action(state, button, .Focus))
    testing.expect(t, !semantic_apply_external_action(state, button, .Activate))
    stale := button
    stale.generation += 1
    testing.expect(t, !semantic_apply_external_action(state, stale, .Activate))
}

// Verify unsupported role actions remain available to later input consumers.
@(test)
semantic_keyboard_rejects_unadvertised_action :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    button := semantic_test_id(.Gif_Control, 1)
    testing.expect(t, semantic_begin(state))
    node := semantic_test_node(button)
    node.actions = {.Focus}
    testing.expect_value(t, semantic_register_node(state,
        {node = node, label = "Save"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = button
    events := [1]input.Input_Event{{kind = .Press, key = .Enter}}

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, !claims.claimed[0])
    testing.expect_value(t, state^.command_count, 0)
}

// Verify Ctrl+Shift+Tab leaves Terminal in reverse global order.
@(test)
semantic_terminal_reverse_escape_wraps_backward :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    first := semantic_test_id(.Animation_Control, 1)
    terminal := semantic_test_id(.Terminal, 1)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(first, {}, .Animation_Overlay, 1), label = "First",
    }), viewmodel.Ui_Semantic_Status.Ok)
    terminal_node := semantic_test_node(terminal, {}, .Presentation, 1)
    terminal_node.role = .Terminal
    testing.expect_value(t, semantic_register_node(state,
        {node = terminal_node, label = "Terminal"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = terminal
    events := [1]input.Input_Event{{
        kind = .Press, key = .Tab, modifiers = {.Control, .Shift}}}

    claims := semantic_route_keyboard(state, {events = events[:]})
    testing.expect(t, claims.claimed[0])
    testing.expect_value(t, state^.logical_focus, first)
}

// Verify semantic traversal updates transitional Terminal and accordion eligibility.
@(test)
semantic_traversal_updates_surface_focus_same_frame :: proc(t: ^testing.T) {
    state := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(state, context.allocator)
    settings := semantic_test_id(.Settings_Control, 1)
    terminal := semantic_test_id(.Terminal, 1)
    testing.expect(t, semantic_begin(state))
    testing.expect_value(t, semantic_register_node(state, {
        node = semantic_test_node(settings, {}, .Accordion_Content, 1),
        label = "Settings",
    }), viewmodel.Ui_Semantic_Status.Ok)
    terminal_node := semantic_test_node(terminal, {}, .Presentation, 1)
    terminal_node.role = .Terminal
    testing.expect_value(t, semantic_register_node(state,
        {node = terminal_node, label = "Terminal"}), viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, semantic_publish(state), viewmodel.Ui_Semantic_Status.Ok)
    state^.logical_focus = terminal
    runtime := viewmodel.Euclid_Ui_Runtime_State{
        semantic_focus = state,
        presentation_visible = true,
        interaction = {
            logical_focus = {kind = .Terminal},
            terminal_effectively_focused = true,
        },
        interaction_frame = {terminal_focused = true},
    }
    events := [1]input.Input_Event{{
        kind = .Press, key = .Tab, modifiers = {.Control}}}
    frame := input.Input_Frame{events = events[:], window_focused = true}

    _ = semantic_route_keyboard(state, frame, true)
    ui_apply_semantic_focus(&runtime, frame, true)
    testing.expect_value(t, runtime.interaction_frame.logical_focus.kind,
        viewmodel.Ui_Focus_Kind.Accordion)
    testing.expect(t, runtime.interaction_frame.accordion.keyboard)
    testing.expect(t, !runtime.interaction_frame.terminal_focused)
    testing.expect(t, runtime.interaction_frame.terminal_focus_changed)
}