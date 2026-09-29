#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "accesskit.h"

#define PRINT_SIZE(name, type) printf(name "=%zu\n", sizeof(type))

int main(void) {
    printf("action_click=%u\n", (unsigned)ACCESSKIT_ACTION_CLICK);
    printf("action_focus=%u\n", (unsigned)ACCESSKIT_ACTION_FOCUS);
    printf("role_button=%u\n", (unsigned)ACCESSKIT_ROLE_BUTTON);
    PRINT_SIZE("action", accesskit_action);
    PRINT_SIZE("role", accesskit_role);
    PRINT_SIZE("node_id", accesskit_node_id);
    PRINT_SIZE("tree_id", accesskit_tree_id);
    PRINT_SIZE("optional_node_id", accesskit_opt_node_id);
    PRINT_SIZE("optional_double", accesskit_opt_double);
    PRINT_SIZE("optional_index", accesskit_opt_index);
    PRINT_SIZE("rect", accesskit_rect);
    PRINT_SIZE("text_position", accesskit_text_position);
    PRINT_SIZE("text_selection", accesskit_text_selection);
    PRINT_SIZE("action_data_tag", accesskit_action_data_Tag);
    PRINT_SIZE("action_data", accesskit_action_data);
    PRINT_SIZE("optional_action_data", accesskit_opt_action_data);
    PRINT_SIZE("action_request", accesskit_action_request);
    printf("action_request_data_offset=%zu\n",
        offsetof(accesskit_action_request, data));

    accesskit_node *node = accesskit_node_new(ACCESSKIT_ROLE_BUTTON);
    if (node == NULL || accesskit_node_role(node) != ACCESSKIT_ROLE_BUTTON) {
        return 2;
    }
    accesskit_node_free(node);
    return 0;
}