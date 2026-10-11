#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>

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

#if defined(ACCESSKIT_MACOS)
    printf("macos_symbols=%u\n", (unsigned)(
        &accesskit_macos_queued_events_raise != NULL &&
        &accesskit_macos_subclassing_adapter_new != NULL &&
        &accesskit_macos_subclassing_adapter_for_window != NULL &&
        &accesskit_macos_subclassing_adapter_free != NULL &&
        &accesskit_macos_subclassing_adapter_update_if_active != NULL &&
        &accesskit_macos_subclassing_adapter_update_view_focus_state != NULL &&
        &accesskit_macos_add_focus_forwarder_to_window_class != NULL &&
        &accesskit_macos_add_focus_forwarder_to_window_class_with_length != NULL));
#endif

#if defined(_WIN32)
    void (*raise_events)(accesskit_windows_queued_events *) =
        accesskit_windows_queued_events_raise;
    accesskit_windows_subclassing_adapter *(*new_subclassing_adapter)(
        HWND, accesskit_activation_handler_callback, void *,
        accesskit_action_handler_callback, void *) =
        accesskit_windows_subclassing_adapter_new;
    void (*free_subclassing_adapter)(accesskit_windows_subclassing_adapter *) =
        accesskit_windows_subclassing_adapter_free;
    accesskit_windows_queued_events *(*update_subclassing_adapter)(
        accesskit_windows_subclassing_adapter *, accesskit_tree_update_factory,
        void *) = accesskit_windows_subclassing_adapter_update_if_active;
    printf("windows_symbols=%u\n", (unsigned)(
        raise_events != NULL &&
        new_subclassing_adapter != NULL &&
        free_subclassing_adapter != NULL &&
        update_subclassing_adapter != NULL));

    wchar_t executable_path[MAX_PATH];
    wchar_t module_path[MAX_PATH];
    HMODULE module = GetModuleHandleW(L"accesskit.dll");
    DWORD executable_length = GetModuleFileNameW(
        NULL, executable_path, MAX_PATH);
    DWORD module_length = GetModuleFileNameW(
        module, module_path, MAX_PATH);
    wchar_t *executable_separator = wcsrchr(executable_path, L'\\');
    wchar_t *module_separator = wcsrchr(module_path, L'\\');
    unsigned module_adjacent = module != NULL && executable_length > 0 &&
        executable_length < MAX_PATH && module_length > 0 &&
        module_length < MAX_PATH && executable_separator != NULL &&
        module_separator != NULL;
    if (module_adjacent) {
        *executable_separator = L'\0';
        *module_separator = L'\0';
        module_adjacent = _wcsicmp(executable_path, module_path) == 0;
    }
    printf("windows_module_adjacent=%u\n", module_adjacent);
#endif

    accesskit_node *node = accesskit_node_new(ACCESSKIT_ROLE_BUTTON);
    if (node == NULL || accesskit_node_role(node) != ACCESSKIT_ROLE_BUTTON) {
        return 2;
    }
    accesskit_node_free(node);
    return 0;
}