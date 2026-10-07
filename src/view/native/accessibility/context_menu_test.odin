#+test
package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"
import "core:testing"

// Verify pinned menu roles and context-opening action translate without content exposure.
@(test)
accesskit_context_menu_roles_and_actions :: proc(t: ^testing.T) {
    testing.expect_value(t, accesskit_control_role(.Menu), accesskit.Role.Menu)
    testing.expect_value(t, accesskit_control_role(.Menu_Item), accesskit.Role.Menu_Item)
    node := accesskit.accesskit_node_new(.Pane)
    testing.expect(t, node != nil)
    if node == nil { return }
    defer accesskit.accesskit_node_free(node)
    accesskit_configure_control_actions(node, {.Focus, .Show_Context_Menu})
    testing.expect(t, accesskit.accesskit_node_supports_action(node, .Show_Context_Menu))
    mapping := adapter_simple_action_mapping(.Show_Context_Menu)
    testing.expect(t, mapping.supported)
    testing.expect_value(t, mapping.mapped, Adapter_Action_Kind.Show_Context_Menu)
}

// Verify rooted menu hierarchy and disabled/stale native action rejection.
@(test)
accesskit_context_menu_validates_owner_requests :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    pane := portable.Qualified_Identity{domain = .Ui, owner_domain = 9, generation = 1}
    menu := portable.Qualified_Identity{domain = .Ui, owner_domain = 11, generation = 1}
    item := menu
    item.local_id = 1
    controls := [3]Adapter_Control_Input{
        {identity = pane, control = {role = .Panel, bounds = {0, 0, 600, 400},
            label = "Presentation", enabled = true, focusable = true,
            actions = {.Focus, .Show_Context_Menu}}},
        {identity = menu, parent_identity = pane, control = {
            role = .Menu, bounds = {20, 20, 180, 100},
            label = "Context menu", enabled = true}},
        {identity = item, parent_identity = menu, control = {
            role = .Menu_Item, bounds = {28, 28, 172, 56}, label = "Copy",
            actions = {.Focus, .Activate}, enabled = false, focusable = true}}}
    testing.expect(t, adapter_publish_controls(owner, {
        root_bounds = {0, 0, 600, 400}, controls = controls[:]}))
    publication := &owner^.control_publication.current
    request := portable.Queued_Action{kind = u16(accesskit.Action.Show_Context_Menu),
        target_native_id = owner^.control_native_ids[0],
        publication_generation = publication^.generation}
    action: Adapter_Action
    testing.expect_value(t,
        adapter_validate_control_action(owner, request, publication, &action),
        Adapter_Action_Status.Ok)
    request.kind = u16(accesskit.Action.Click)
    request.target_native_id = owner^.control_native_ids[2]
    testing.expect_value(t,
        adapter_validate_control_action(owner, request, publication, &action),
        Adapter_Action_Status.Disabled_Target)
    request.publication_generation -= 1
    testing.expect_value(t,
        adapter_validate_control_action(owner, request, publication, &action),
        Adapter_Action_Status.Stale_Generation)
}
