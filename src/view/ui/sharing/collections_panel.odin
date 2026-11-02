package uisharing

import core "../../../core"
import contentdata "../../../core/content"
import geometry "../../../core/geometry"
import collections "../../../collections"
import log "core:log"
import uuid "core:encoding/uuid"
import native "../../native"
import input "../../input"
import viewfont "../../font"
import viewmessages "../../messages"
import viewmodel "../model"
import sharingmodel "../../sharing/model"
import viewsharing "../../sharing"
import sharinglayout "../layout/sharing"
import uisemantics "../semantics"
import uiwidgets "../widgets"
import uigif "../gif"
import uisettings "../settings"
import theme "../theme"
import viewtext "../text"

SHARE_COLLECTION_LIST_ID :: 6500
SHARE_EXPORT_BUTTON_ID :: 6501
SHARE_IMPORT_BUTTON_ID :: 6502
SHARE_IMPORT_LIST_ID :: 6503
SHARE_IMPORT_CONFIRM_ID :: 6504
SHARE_IMPORT_CANCEL_ID :: 6505
SHARE_EXPORT_ROW_ID_BASE :: 6600
SHARE_IMPORT_ROW_ID_BASE :: 1_000_000_000
SHARE_COLLECTION_TRAVERSAL_BASE :: 100

#assert(viewmodel.UI_SHARING_SELECTION_CAPACITY ==
    sharingmodel.EXCHANGE_SELECTION_CAPACITY)

Share_Collections_Preparation :: struct {
    counts: Share_Collection_Counts,
    export_button: uiwidgets.Text_Button_Result,
    import_button: uiwidgets.Text_Button_Result,
    import_confirm: uiwidgets.Text_Button_Result,
    import_cancel: uiwidgets.Text_Button_Result,
    export_enabled: bool,
    import_enabled: bool,
    import_confirm_enabled: bool,
    import_cancel_enabled: bool,
    import_selected_count: int,
}

Share_Collection_Checkbox_Params :: struct {
    row: geometry.Rectangle,
    panel: geometry.Rectangle,
    frame: input.Input_Frame,
    id: int,
    label: string,
    checked: bool,
    enabled: bool,
    traversal: u32,
}

Share_Button_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    label: string,
    enabled: bool,
    traversal: u32,
}

Share_Checkbox_Visual :: struct {
    id: int,
    label: string,
    checked: bool,
}

Share_Primary_Button_Visual :: struct {
    message: contentdata.Content_Message_Id,
    half: int,
    enabled: bool,
}

Share_Import_Preparation :: struct {
    confirm: uiwidgets.Text_Button_Result,
    cancel: uiwidgets.Text_Button_Result,
    selected_count: int,
    confirm_enabled: bool,
    cancel_enabled: bool,
}

Share_Collection_Counts :: struct {
    export_count: int,
    importable_count: int,
    warning_count: int,
    non_importable_count: int,
    has_import: bool,
}

// Count bounded exchange rows without creating storage in the frame path.
share_collection_counts :: proc(
    state: ^core.Euclid_General_State) -> Share_Collection_Counts {
    counts: Share_Collection_Counts
    if state == nil {
        return counts
    }
    set := &state^.preferences_runtime.collections_state
    for collection in set.collections[:set.collection_count] {
        if collection.role == .User {
            counts.export_count += 1
        }
    }
    exchange := viewsharing.exchange_runtime_get(state)
    if exchange == nil || exchange.phase != .Staged ||
        exchange.payload.staged == nil {
        return counts
    }
    counts.has_import = true
    for resolved in exchange.resolved_collections[:exchange.resolved_collection_count] {
        if resolved.importable {
            counts.importable_count += 1
            if resolved.omitted_entry_count > 0 {
                counts.warning_count += 1
            }
        } else {
            counts.non_importable_count += 1
        }
    }
    return counts
}

// Retain export choices by UUID and discard choices whose collections disappeared.
share_export_selection_prune :: proc(state: ^core.Euclid_General_State) {
    selection := &state^.ui_runtime.sharing
    set := &state^.preferences_runtime.collections_state
    output := 0
    for id in selection.export_selected_ids[:selection.export_selected_count] {
        index := collections.find_collection(set, id)
        if index < 0 || set.collections[index].role != .User {
            continue
        }
        selection.export_selected_ids[output] = id
        output += 1
    }
    for index in output..<selection.export_selected_count {
        selection.export_selected_ids[index] = {}
    }
    selection.export_selected_count = output
}

// Locate one accepted collection UUID in the bounded export selection.
share_export_selection_index :: proc(
    state: ^core.Euclid_General_State, id: uuid.Identifier) -> int {
    selection := &state^.ui_runtime.sharing
    for selected, index in selection.export_selected_ids[
        :selection.export_selected_count] {
        if selected == id {
            return index
        }
    }
    return -1
}

// Toggle one export choice without exceeding the worker's fixed selection buffer.
share_export_selection_toggle :: proc(
    state: ^core.Euclid_General_State, id: uuid.Identifier) {
    selection := &state^.ui_runtime.sharing
    index := share_export_selection_index(state, id)
    if index >= 0 {
        for move in index..<selection.export_selected_count - 1 {
            selection.export_selected_ids[move] =
                selection.export_selected_ids[move + 1]
        }
        selection.export_selected_count -= 1
        selection.export_selected_ids[selection.export_selected_count] = {}
        return
    }
    if selection.export_selected_count >= len(selection.export_selected_ids) {
        return
    }
    selection.export_selected_ids[selection.export_selected_count] = id
    selection.export_selected_count += 1
}

// Initialize a newly staged document with all collections that can be imported.
share_import_selection_initialize :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    selection := &state^.ui_runtime.sharing
    if selection.import_selection_initialized {
        return
    }
    selection.import_selected = {}
    selection.import_selected_count = 0
    if exchange.resolved_collection_count > len(selection.import_selected) {
        log.error("sharing_import_selection_capacity_exceeded")
        return
    }
    for resolved, index in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        selection.import_selected[index] = resolved.importable
        if resolved.importable {
            selection.import_selected_count += 1
        }
    }
    selection.import_selection_initialized = true
}

// Resolve a checkbox row using shared interaction and semantic behavior.
share_collection_checkbox :: proc(
    state: ^core.Euclid_General_State,
    checkbox: Share_Collection_Checkbox_Params) -> uiwidgets.Checkbox_Result {
    scale := theme.ui_control_size_scale(
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    font := viewfont.cache_borrow(&state^.font_cache, .Regular)
    font_size := theme.ui_font_size(
        state^.ui_runtime.preferences.values.interface.text_size_percent)
    params: uiwidgets.Checkbox_Params = {
        id = checkbox.id,
        rect = {
            checkbox.row.x + 2*scale,
            checkbox.row.y + (checkbox.row.height - 18*scale)*0.5,
            18*scale, 18*scale},
        checked = checkbox.checked,
        enabled = checkbox.enabled,
        mouse = checkbox.frame,
        interaction_space_rect = checkbox.panel,
        interaction_enabled = true,
        label = checkbox.label,
        font = font,
        label_font_size = font_size,
        label_offset_x = 8*scale,
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantic_focus = state^.ui_runtime.semantic_focus,
        semantic_domain = .Sharing_Control,
        semantic_order = checkbox.traversal,
        semantic_clip = checkbox.panel,
        semantic_value = "true" if checkbox.checked else "false",
    }
    return uiwidgets.prepare_checkbox(
        params, &state^.ui_runtime.input.press_owner, true)
}

// Publish one scrollable checklist as an accessible panel.
share_register_list :: proc(
    state: ^core.Euclid_General_State, id: int,
    rect, clip: geometry.Rectangle, label: string) {
    if rect.height <= 0 {
        return
    }
    traversal := u32(10)
    if id == SHARE_IMPORT_LIST_ID {
        traversal = 500
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = uisemantics.semantic_control_id(.Sharing_Control, id),
        role = .Panel,
        states = {.Visible, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll, .Set_Value},
        region = .Accordion_Content,
        traversal_order = traversal,
        bounds = rect,
        clip_bounds = clip,
        label = label,
        value = label,
    })
}

// Prepare an accessible sharing button and preserve the common disabled-state behavior.
share_button :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame,
    button: Share_Button_Params) -> uiwidgets.Text_Button_Result {
    return uiwidgets.prepare_text_button({
        id = button.id,
        rect = button.rect,
        label = button.label,
        enabled = button.enabled,
        mouse = frame,
        interaction_space_rect = panel,
        interaction_enabled = true,
        font = viewfont.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state^.font_cache),
        semantics = {
            publish = true,
            focus = state^.ui_runtime.semantic_focus,
            id = uisemantics.semantic_control_id(
                .Sharing_Control, button.id),
            role = .Button,
            states = uiwidgets.button_semantic_states(button.enabled),
            region = .Accordion_Content,
            traversal_order = button.traversal,
            clip_bounds = panel,
            label = button.label,
            value = button.label,
        },
    }, &state^.ui_runtime.input.press_owner, true)
}

// Prepare bounded collection checklists and commit the actions accepted this frame.
prepare_share_collections :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    layout: sharinglayout.Sharing_Layout, frame: input.Input_Frame,
    interactive: bool) -> Share_Collections_Preparation {
    counts := share_collection_counts(state)
    result: Share_Collections_Preparation = {
        counts = counts,
    }
    exchange := viewsharing.exchange_runtime_get(state)
    share_reconcile_collection_selections(state, exchange)
    if !interactive {
        return result
    }
    share_register_list(state, SHARE_COLLECTION_LIST_ID, layout.export_list,
        panel, viewmessages.shell_message(state, .Share_Collections_Heading))
    share_prepare_export_rows(state, panel, layout.export_list, frame, exchange)
    result.export_enabled = share_export_button_enabled(state)
    result.import_enabled = share_import_button_enabled(state)
    result.export_button = share_prepare_export_button(
        state, panel, layout.export_buttons, frame, exchange)
    result.import_button = share_prepare_import_button(
        state, panel, layout.export_buttons, frame, exchange)
    if counts.has_import {
        imported := share_prepare_import_preview(
            state, panel, layout, frame, exchange)
        result.import_confirm = imported.confirm
        result.import_cancel = imported.cancel
        result.import_selected_count = imported.selected_count
        result.import_confirm_enabled = imported.confirm_enabled
        result.import_cancel_enabled = imported.cancel_enabled
    }
    share_register_status(state, panel, layout)
    share_clear_omission_indicator(state, panel, frame)
    return result
}

// Drop retired export identities and initialize choices only for a newly staged import.
share_reconcile_collection_selections :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) {
    share_export_selection_prune(state)
    if exchange != nil && exchange.phase == .Staged {
        share_import_selection_initialize(state, exchange)
    } else {
        state^.ui_runtime.sharing.import_selection_initialized = false
    }
}

// Prepare staged import rows and actions from one resolved exchange snapshot.
share_prepare_import_preview :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    layout: sharinglayout.Sharing_Layout, frame: input.Input_Frame,
    exchange: ^sharingmodel.Exchange_Runtime) -> Share_Import_Preparation {
    result: Share_Import_Preparation
    share_register_list(state, SHARE_IMPORT_LIST_ID, layout.import_list,
        panel, viewmessages.shell_message(state, .Share_Import))
    share_prepare_import_rows(state, panel, layout.import_list, frame, exchange)
    result.selected_count = state^.ui_runtime.sharing.import_selected_count
    result.confirm_enabled = result.selected_count > 0 &&
        exchange != nil && exchange.phase == .Staged
    result.cancel_enabled = exchange != nil && exchange.phase == .Staged
    if exchange != nil && share_non_importable_count(exchange) > 0 {
        share_prepare_non_importable_rows(
            state, panel, layout.not_importable_list, exchange)
    }
    result.confirm, result.cancel =
        share_prepare_import_actions(state, panel, layout, frame, exchange)
    return result
}

// Publish exchange feedback as a live status for assistive technology.
share_register_status :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    layout: sharinglayout.Sharing_Layout) {
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    status := share_status_message(state, storage[:])
    if len(status) == 0 {
        return
    }
    _ = uisemantics.semantic_register_control(
        state^.ui_runtime.semantic_focus, {
            id = uisemantics.semantic_control_id(.Sharing_Control, 6510),
            role = .Status,
            states = {.Visible},
            region = .Accordion_Content,
            bounds = {layout.export_list.x, layout.collections_status_y,
                layout.export_list.width, theme.ui_font_size(
                    state^.ui_runtime.preferences.values.interface.text_size_percent)},
            clip_bounds = panel,
            label = status,
            value = status,
        })
}

// Route export row checkbox changes into the persistent UUID selection.
share_prepare_export_rows :: proc(
    state: ^core.Euclid_General_State, panel, list: geometry.Rectangle,
    frame: input.Input_Frame, exchange: ^sharingmodel.Exchange_Runtime) {
    set := &state^.preferences_runtime.collections_state
    row_count := share_collection_counts(state).export_count
    row_height := list.height/f32(max(1, row_count))
    selection_locked := state^.ui_runtime.sharing.exchange_dialog_intent != .None ||
        state^.ui_runtime.sharing.exchange_dialog_request != .None ||
        exchange != nil && exchange.phase != .Idle
    row_index := 0
    for collection, collection_index in set.collections[:set.collection_count] {
        if collection.role != .User {
            continue
        }
        row: geometry.Rectangle = {
            list.x, list.y + f32(row_index)*row_height, list.width, row_height,
        }
        selected := share_export_selection_index(state, collection.id) >= 0
        enabled := !selection_locked &&
            (selected || state^.ui_runtime.sharing.export_selected_count <
                len(state^.ui_runtime.sharing.export_selected_ids))
        checkbox: Share_Collection_Checkbox_Params = {
            row = row,
            panel = panel,
            frame = frame,
            id = SHARE_EXPORT_ROW_ID_BASE + collection_index,
            label = string(collection.name[:collection.name_length]),
            checked = selected,
            enabled = enabled,
            traversal = SHARE_COLLECTION_TRAVERSAL_BASE + u32(row_index),
        }
        checked := share_collection_checkbox(state, checkbox)
        if checked.toggled {
            share_export_selection_toggle(state, collection.id)
        }
        row_index += 1
    }
}

// Prepare the two export and file-import actions using the shared button widget.
share_prepare_export_button :: proc(
    state: ^core.Euclid_General_State,
    panel, row: geometry.Rectangle,
    frame: input.Input_Frame,
    exchange: ^sharingmodel.Exchange_Runtime) -> uiwidgets.Text_Button_Result {
    gap := theme.ui_control_size_metric(8,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    width := max(f32(0), (row.width - gap)*0.5)
    enabled := share_collection_counts(state).export_count > 0 &&
        state^.ui_runtime.sharing.export_selected_count > 0 &&
        state^.ui_runtime.sharing.exchange_dialog_intent == .None &&
        state^.ui_runtime.sharing.exchange_dialog_request == .None &&
        (exchange == nil || exchange.phase == .Idle)
    button: Share_Button_Params = {
        id = SHARE_EXPORT_BUTTON_ID,
        rect = {row.x, row.y, width, row.height},
        label = viewmessages.shell_message(state, .Share_Export),
        enabled = enabled,
        traversal = 400,
    }
    result := share_button(state, panel, frame, button)
    if result.action.activated {
        state^.ui_runtime.sharing.exchange_dialog_request = .Export
    }
    return result
}

// Enable replacement imports only when no other request or commit is active.
share_prepare_import_button :: proc(
    state: ^core.Euclid_General_State,
    panel, row: geometry.Rectangle,
    frame: input.Input_Frame,
    exchange: ^sharingmodel.Exchange_Runtime) -> uiwidgets.Text_Button_Result {
    gap := theme.ui_control_size_metric(8,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    width := max(f32(0), (row.width - gap)*0.5)
    enabled := state^.ui_runtime.sharing.exchange_dialog_intent == .None &&
        state^.ui_runtime.sharing.exchange_dialog_request == .None &&
        (exchange == nil || exchange.phase == .Idle || exchange.phase == .Staged)
    button: Share_Button_Params = {
        id = SHARE_IMPORT_BUTTON_ID,
        rect = {row.x + width + gap, row.y, width, row.height},
        label = viewmessages.shell_message(state, .Share_Import),
        enabled = enabled,
        traversal = 401,
    }
    result := share_button(state, panel, frame, button)
    if result.action.activated {
        state^.ui_runtime.sharing.exchange_dialog_request = .Import
    }
    return result
}

// Route staged checkbox changes and warnings in source collection order.
share_prepare_import_rows :: proc(
    state: ^core.Euclid_General_State, panel, list: geometry.Rectangle,
    frame: input.Input_Frame, exchange: ^sharingmodel.Exchange_Runtime) {
    if exchange == nil || exchange.payload.staged == nil {
        return
    }
    collection_y := list.y
    row_height := list.height/f32(max(1, share_import_layout_row_count(exchange)))
    for resolved, index in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if !resolved.importable {
            continue
        }
        source := exchange.payload.staged.collections[resolved.source_index]
        row: geometry.Rectangle = {
            list.x, collection_y, list.width, row_height,
        }
        checkbox: Share_Collection_Checkbox_Params = {
            row = row,
            panel = panel,
            frame = frame,
            id = SHARE_IMPORT_ROW_ID_BASE + index,
            label = string(source.name),
            checked = state^.ui_runtime.sharing.import_selected[index],
            enabled = exchange.phase == .Staged,
            traversal = 600 + u32(index),
        }
        checked := share_collection_checkbox(state, checkbox)
        if checked.toggled {
            state^.ui_runtime.sharing.import_selected[index] = checked.checked_out
            state^.ui_runtime.sharing.import_selected_count +=
                1 if checked.checked_out else -1
        }
        collection_y += row.height
        if resolved.omitted_entry_count > 0 {
            share_register_import_warning(state, panel,
                {list.x, collection_y, list.width, row.height},
                index, resolved.omitted_entry_count)
            collection_y += row.height
        }
    }
}

// Publish one collection's omission warning with copied localized semantic text.
share_register_import_warning :: proc(
    state: ^core.Euclid_General_State, panel, row: geometry.Rectangle,
    index, omitted_entry_count: int) {
    warning_storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    warning := share_count_message(state, .Share_Missing_Animations,
        omitted_entry_count, warning_storage[:])
    _ = uisemantics.semantic_register_control(
        state^.ui_runtime.semantic_focus, {
            id = uisemantics.semantic_control_id(
                .Sharing_Control, SHARE_IMPORT_ROW_ID_BASE + index + 512),
            role = .Status,
            states = {.Visible},
            region = .Accordion_Content,
            traversal_order = u32(700 + index),
            bounds = row,
            clip_bounds = panel,
            label = warning,
            value = warning,
        })
}

// Return the weighted number of importable and warning rows in the preview.
share_import_layout_row_count :: proc(
    exchange: ^sharingmodel.Exchange_Runtime) -> int {
    count := 0
    for resolved in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if !resolved.importable {
            continue
        }
        count += 1
        if resolved.omitted_entry_count > 0 {
            count += 1
        }
    }
    return count
}

// Publish non-importable entries at the bottom with their reason as a separate line.
share_prepare_non_importable_rows :: proc(
    state: ^core.Euclid_General_State, panel, list: geometry.Rectangle,
    exchange: ^sharingmodel.Exchange_Runtime) {
    if exchange == nil || exchange.payload.staged == nil {
        return
    }
    row_height := list.height/f32(max(1, share_non_importable_count(exchange)))
    row_y := list.y
    for resolved, index in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if resolved.importable {
            continue
        }
        source := exchange.payload.staged.collections[resolved.source_index]
        label := string(source.name)
        reason := viewmessages.shell_message(state, .Share_Reason_Invalid)
        if source.reason == .Empty {
            reason = viewmessages.shell_message(state, .Share_Reason_Empty)
        }
        _ = uisemantics.semantic_register_control(
            state^.ui_runtime.semantic_focus, {
                id = uisemantics.semantic_control_id(
                    .Sharing_Control, SHARE_IMPORT_ROW_ID_BASE + index + 768),
                role = .Status,
                states = {.Visible},
                region = .Accordion_Content,
                traversal_order = u32(800 + index),
                bounds = {list.x, row_y, list.width, row_height},
                clip_bounds = panel,
                label = label,
                value = reason,
            })
        row_y += row_height
    }
}

// Count staged collections that are displayed below the importable checklist.
share_non_importable_count :: proc(
    exchange: ^sharingmodel.Exchange_Runtime) -> int {
    count := 0
    for resolved in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if !resolved.importable {
            count += 1
        }
    }
    return count
}

// Enable confirmation only when at least one staged collection remains selected.
share_prepare_import_actions :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    layout: sharinglayout.Sharing_Layout, frame: input.Input_Frame,
    exchange: ^sharingmodel.Exchange_Runtime) -> (
        uiwidgets.Text_Button_Result, uiwidgets.Text_Button_Result) {
    gap := theme.ui_control_size_metric(8,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    width := max(f32(0), (layout.import_buttons.width - gap)*0.5)
    count := state^.ui_runtime.sharing.import_selected_count
    label_storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    label := share_count_message(
        state, .Share_Import_Selected, count, label_storage[:])
    confirm_params: Share_Button_Params = {
        id = SHARE_IMPORT_CONFIRM_ID,
        rect = {
            layout.import_buttons.x, layout.import_buttons.y, width,
            layout.import_buttons.height,
        },
        label = label,
        enabled = count > 0 && exchange != nil && exchange.phase == .Staged,
        traversal = 900,
    }
    cancel_params: Share_Button_Params = {
        id = SHARE_IMPORT_CANCEL_ID,
        rect = {
            layout.import_buttons.x + width + gap, layout.import_buttons.y,
            width, layout.import_buttons.height,
        },
        label = viewmessages.shell_message(state, .Share_Cancel),
        enabled = exchange != nil && exchange.phase == .Staged,
        traversal = 901,
    }
    confirm := share_button(state, panel, frame, confirm_params)
    cancel := share_button(state, panel, frame, cancel_params)
    if confirm.action.activated {
        if viewsharing.exchange_runtime_confirm_import(
            state, state^.ui_runtime.sharing.import_selected[
                :exchange.resolved_collection_count]) != .Started {
            state^.ui_runtime.sharing.exchange_error = .Write
        }
    }
    if cancel.action.activated {
        if state^.simulation_executor != nil {
            _ = viewsharing.exchange_runtime_cancel(
                state, &state^.simulation_executor^.pool)
        }
        state^.ui_runtime.sharing.import_selection_initialized = false
    }
    return confirm, cancel
}

// Convert a count message into short-lived localized text using caller-owned storage.
share_count_message :: proc(
    state: ^core.Euclid_General_State, id: contentdata.Content_Message_Id,
    count: int, storage: []u8) -> string {
    return viewmessages.shell_format(state, id,
        []contentdata.Content_Format_Argument{{"count", u32(max(0, count))}},
        storage)
}

// Resolve the current exchange feedback without hiding parser or writer failures.
share_status_message :: proc(
    state: ^core.Euclid_General_State, storage: []u8) -> string {
    selection := &state^.ui_runtime.sharing
    switch selection.exchange_error {
    case .Read:
        return viewmessages.shell_message(state, .Share_Error_Read)
    case .Unsupported:
        return viewmessages.shell_message(state, .Share_Error_Unsupported)
    case .Write:
        return viewmessages.shell_message(state, .Share_Error_Write)
    case .None:
    }
    exchange := viewsharing.exchange_runtime_get(state)
    if exchange == nil || exchange.phase != .Idle ||
        exchange.payload.result.kind == .None {
        return ""
    }
    return share_exchange_result_message(state, exchange, storage)
}

// Map a joined exchange result to its localized terminal status.
share_exchange_result_message :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime, storage: []u8) -> string {
    switch exchange.payload.result.kind {
    case .Succeeded:
        return share_exchange_success_message(state, exchange, storage)
    case .Read_Failed, .Allocation_Failed, .Invalid_Document:
        return share_exchange_read_failure_message(state, exchange)
    case .Write_Failed, .Persistence_Failed:
        return share_exchange_write_failure_message(state, exchange)
    case .Cancelled, .None:
    }
    return ""
}

// Format the accepted export or import result, including omitted entries.
share_exchange_success_message :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime, storage: []u8) -> string {
    selection := &state^.ui_runtime.sharing
    if selection.exchange_last_action == .Export {
        return share_count_message(
            state, .Share_Exported, exchange.exported_collection_count, storage)
    }
    if selection.exchange_last_action != .Import {
        return ""
    }
    if selection.last_import_omitted_entry_count > 0 {
        return share_count_message(state, .Share_Imported_With_Omissions,
            selection.last_import_omitted_entry_count, storage)
    }
    return share_count_message(
        state, .Share_Imported, exchange.imported_collection_count, storage)
}

// Distinguish unsupported files from other staged-import read failures.
share_exchange_read_failure_message :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) -> string {
    if exchange.payload.result.sharing_rule == .Unsupported_Schema ||
        exchange.payload.result.sharing_rule == .Unknown_Requirement {
        return viewmessages.shell_message(state, .Share_Error_Unsupported)
    }
    return viewmessages.shell_message(state, .Share_Error_Read)
}

// Keep import persistence errors on the import-facing read-error message.
share_exchange_write_failure_message :: proc(
    state: ^core.Euclid_General_State,
    exchange: ^sharingmodel.Exchange_Runtime) -> string {
    if state^.ui_runtime.sharing.exchange_last_action == .Import {
        return viewmessages.shell_message(state, .Share_Error_Read)
    }
    return viewmessages.shell_message(state, .Share_Error_Write)
}

// Clear the omission indicator only for a press or activation inside Sharing.
share_clear_omission_indicator :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame) {
    sharing_ui := &state^.ui_runtime.sharing
    if !sharing_ui.import_left_out_entries {
        return
    }
    mouse := uiwidgets.input_frame_mouse_position(frame)
    if uiwidgets.input_frame_left_pressed(frame) &&
        geometry.rectangle_contains(panel, mouse) {
        sharing_ui.import_left_out_entries = false
        return
    }
    focus := state^.ui_runtime.semantic_focus
    if focus == nil || focus.logical_focus.domain != .Sharing_Control &&
        focus.logical_focus.domain != .Gif_Control {
        return
    }
    for event in frame.events {
        if event.kind == .Press && (event.key == .Enter || event.key == .Space) {
            sharing_ui.import_left_out_entries = false
            return
        }
    }
}

// Draw a visible checkbox and its label using the prepared panel row geometry.
share_draw_checkbox :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    row: geometry.Rectangle, visual: Share_Checkbox_Visual) {
    scale := theme.ui_control_size_scale(
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    font_size := theme.ui_font_size(
        state^.ui_runtime.preferences.values.interface.text_size_percent)
    box: geometry.Rectangle = {
        row.x + 2*scale,
        row.y + (row.height - 18*scale)*0.5,
        18*scale,
        18*scale,
    }
    uiwidgets.draw_encoded_checkbox_geometry(
        encoder, box, visual.checked, scale)
    if state^.ui_runtime.semantic_focus != nil &&
        state^.ui_runtime.semantic_focus.logical_focus ==
            uisemantics.semantic_control_id(.Sharing_Control, visual.id) &&
        state^.ui_runtime.semantic_focus.focus_origin == .Keyboard {
        uiwidgets.draw_encoded_focus_ring(encoder,
            {row.x, row.y, row.width, row.height}, scale)
    }
    viewtext.draw_encoded_label(&state^.font_cache, encoder, visual.label,
        box.x + box.width + 8*scale, row.y + (row.height - font_size)*0.5)
}

// Draw the bounded collection selection and optional staged-import details.
draw_encoded_share_collections :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: sharinglayout.Sharing_Layout,
    prepared: Share_Collections_Preparation) {
    inset_x := layout.export_list.x
    uisettings.draw_encoded_settings_section_heading(
        state, encoder, .Share_Collections_Heading, inset_x,
        layout.collections_heading_y)
    share_draw_export_rows(
        state, encoder, layout.export_list, prepared.counts.export_count)
    export_visual: Share_Primary_Button_Visual = {
        message = .Share_Export,
        half = 0,
        enabled = prepared.export_enabled,
    }
    share_draw_button(state, encoder, layout.export_buttons, export_visual)
    import_visual: Share_Primary_Button_Visual = {
        message = .Share_Import,
        half = 1,
        enabled = prepared.import_enabled,
    }
    share_draw_button(state, encoder, layout.export_buttons, import_visual)
    if prepared.counts.has_import {
        uisettings.draw_encoded_settings_section_heading(
            state, encoder, .Share_Import, inset_x, layout.import_heading_y)
        share_draw_import_rows(state, encoder, layout)
        if prepared.counts.non_importable_count > 0 {
            viewtext.draw_encoded_label(&state^.font_cache, encoder,
                viewmessages.shell_message(state, .Share_Not_Importable),
                inset_x, layout.not_importable_heading_y)
            share_draw_non_importable_rows(state, encoder, layout)
        }
        share_draw_import_actions(state, encoder, layout, prepared)
    }
    status_storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    status := share_status_message(state, status_storage[:])
    if len(status) > 0 {
        viewtext.draw_encoded_label(&state^.font_cache, encoder, status,
            inset_x, layout.collections_status_y)
    }
}

// Draw each custom collection checkbox in persisted collection order.
share_draw_export_rows :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    list: geometry.Rectangle, row_count: int) {
    set := &state^.preferences_runtime.collections_state
    if row_count <= 0 {
        return
    }
    row_height := list.height/f32(row_count)
    row_index := 0
    for collection, index in set.collections[:set.collection_count] {
        if row_index >= row_count {
            break
        }
        if collection.role != .User {
            continue
        }
        id := SHARE_EXPORT_ROW_ID_BASE + index
        row: geometry.Rectangle = {
            list.x, list.y + f32(row_index)*row_height, list.width, row_height,
        }
        visual: Share_Checkbox_Visual = {
            id = id,
            label = string(collection.name[:collection.name_length]),
            checked = share_export_selection_index(state, collection.id) >= 0,
        }
        share_draw_checkbox(state, encoder, row, visual)
        row_index += 1
    }
}

// Draw the two primary actions using their accepted accessibility labels.
share_draw_button :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    row: geometry.Rectangle, visual: Share_Primary_Button_Visual) {
    gap := theme.ui_control_size_metric(8,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    width := max(f32(0), (row.width - gap)*0.5)
    rect: geometry.Rectangle = {row.x, row.y, width, row.height}
    if visual.half == 1 {
        rect.x += width + gap
    }
    label := viewmessages.shell_message(state, visual.message)
    _ = native.draw_encoder_rectangle(encoder, rect,
        theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, rect, 1, theme.draw_color(encoder, .Control_Border))
    uigif.draw_encoded_gif_button_text(
        state, encoder, label, rect, !visual.enabled)
}

// Re-evaluate the exact state used by the export button's enabled semantics.
share_export_button_enabled :: proc(state: ^core.Euclid_General_State) -> bool {
    exchange := viewsharing.exchange_runtime_get(state)
    return share_collection_counts(state).export_count > 0 &&
        state^.ui_runtime.sharing.export_selected_count > 0 &&
        state^.ui_runtime.sharing.exchange_dialog_intent == .None &&
        state^.ui_runtime.sharing.exchange_dialog_request == .None &&
        (exchange == nil || exchange.phase == .Idle)
}

// Re-evaluate the exact state used by the import button's enabled semantics.
share_import_button_enabled :: proc(state: ^core.Euclid_General_State) -> bool {
    exchange := viewsharing.exchange_runtime_get(state)
    return state^.ui_runtime.sharing.exchange_dialog_intent == .None &&
        state^.ui_runtime.sharing.exchange_dialog_request == .None &&
        (exchange == nil || exchange.phase == .Idle || exchange.phase == .Staged)
}

// Draw warnings, selected rows, and their overflow-safe source names.
share_draw_import_rows :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: sharinglayout.Sharing_Layout) {
    exchange := viewsharing.exchange_runtime_get(state)
    if exchange == nil || exchange.payload.staged == nil {
        return
    }
    row_height := layout.collection_row_height
    row_y := layout.import_list.y
    for resolved, index in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if !resolved.importable {
            continue
        }
        source := exchange.payload.staged.collections[resolved.source_index]
        row: geometry.Rectangle = {
            layout.import_list.x, row_y, layout.import_list.width, row_height,
        }
        visual: Share_Checkbox_Visual = {
            id = SHARE_IMPORT_ROW_ID_BASE + index,
            label = string(source.name),
            checked = state^.ui_runtime.sharing.import_selected[index],
        }
        share_draw_checkbox(state, encoder, row, visual)
        row_y += row_height
        if resolved.omitted_entry_count > 0 {
            warning_storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
            warning := share_count_message(state, .Share_Missing_Animations,
                resolved.omitted_entry_count, warning_storage[:])
            viewtext.draw_encoded_label(&state^.font_cache, encoder, warning,
                row.x + 28,
                row_y + (row_height - theme.ui_font_size(
                    state^.ui_runtime.preferences.values.interface.text_size_percent)) *
                    0.5)
            row_y += row_height
        }
    }
}

// Draw non-importable names followed by their localized reason.
share_draw_non_importable_rows :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: sharinglayout.Sharing_Layout) {
    exchange := viewsharing.exchange_runtime_get(state)
    if exchange == nil || exchange.payload.staged == nil {
        return
    }
    font := theme.ui_font_size(
        state^.ui_runtime.preferences.values.interface.text_size_percent)
    row_height := layout.collection_row_height
    row_y := layout.not_importable_list.y
    for resolved in exchange.resolved_collections[
        :exchange.resolved_collection_count] {
        if resolved.importable {
            continue
        }
        source := exchange.payload.staged.collections[resolved.source_index]
        reason := viewmessages.shell_message(state, .Share_Reason_Invalid)
        if source.reason == .Empty {
            reason = viewmessages.shell_message(state, .Share_Reason_Empty)
        }
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            string(source.name), layout.not_importable_list.x, row_y)
        viewtext.draw_encoded_label(&state^.font_cache, encoder, reason,
            layout.not_importable_list.x + 20, row_y + font)
        row_y += row_height*2
    }
}

// Draw commit and cancellation actions with their count-aware labels.
share_draw_import_actions :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: sharinglayout.Sharing_Layout,
    prepared: Share_Collections_Preparation) {
    gap := theme.ui_control_size_metric(8,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    row := layout.import_buttons
    width := max(f32(0), (row.width - gap)*0.5)
    confirm: geometry.Rectangle = {row.x, row.y, width, row.height}
    cancel: geometry.Rectangle = {
        row.x + width + gap, row.y, width, row.height,
    }
    label_storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    label := share_count_message(
        state, .Share_Import_Selected, prepared.import_selected_count,
        label_storage[:])
    share_draw_action_button(
        state, encoder, confirm, label, prepared.import_confirm_enabled)
    share_draw_action_button(state, encoder, cancel,
        viewmessages.shell_message(state, .Share_Cancel),
        prepared.import_cancel_enabled)
}

// Draw one labeled action button in the staged-import command row.
share_draw_action_button :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    rect: geometry.Rectangle, label: string, enabled: bool) {
    _ = native.draw_encoder_rectangle(
        encoder, rect, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, rect, 1, theme.draw_color(encoder, .Control_Border))
    uigif.draw_encoded_gif_button_text(state, encoder, label, rect, !enabled)
}
