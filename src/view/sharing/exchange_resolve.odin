package viewsharing

import sharingmodel "../../view/sharing/model"
import sharing "../../sharing"
import uuid "core:encoding/uuid"

Exchange_Installed_Proc :: #type proc(
    animation_id: uuid.Identifier, user_data: rawptr) -> bool

Exchange_Resolve_Result :: struct {
    collection_count: int,
    entry_count: int,
    omitted_entry_count: int,
}

Exchange_Resolve_Parent_Context :: struct {
    source: ^sharing.Staged_Collection,
    collection_index: int,
    is_installed: Exchange_Installed_Proc,
    user_data: rawptr,
    resolved: []sharingmodel.Exchange_Resolved_Entry,
}

// Resolve unavailable animation entries, promoting descendants in source order.
exchange_resolve :: proc(
    document: ^sharing.Staged_Document, is_installed: Exchange_Installed_Proc,
    user_data: rawptr, collections: []sharingmodel.Exchange_Resolved_Collection,
    entries: []sharingmodel.Exchange_Resolved_Entry) -> (Exchange_Resolve_Result, bool) {
    if document == nil || !document.initialized || is_installed == nil ||
        len(collections) < document.collection_count ||
        len(entries) < document.entry_total {
        return {}, false
    }
    result: Exchange_Resolve_Result
    for collection_index in 0..<document.collection_count {
        source := &document.collections[collection_index]
        parent_context: Exchange_Resolve_Parent_Context = {
            source = source,
            collection_index = collection_index,
            is_installed = is_installed,
            user_data = user_data,
        }
        resolved: sharingmodel.Exchange_Resolved_Collection = {
            source_index = collection_index,
        }
        for source_index in 0..<source.entry_count {
            entry := source.entries[source_index]
            if !is_installed(entry.animation_id, user_data) {
                resolved.omitted_entry_count += 1
                result.omitted_entry_count += 1
                continue
            }
            parent_context.resolved = entries[:result.entry_count]
            parent_index := exchange_resolve_parent(parent_context, entry.parent)
            sibling_order := exchange_resolve_sibling_order(
                entries[:result.entry_count], collection_index, parent_index)
            entries[result.entry_count] = {
                collection_index = collection_index,
                source_entry_index = source_index,
                parent_entry_index = parent_index,
                sibling_order = sibling_order,
            }
            result.entry_count += 1
            resolved.resolved_entry_count += 1
        }
        resolved.importable = source.importable && resolved.resolved_entry_count > 0
        collections[collection_index] = resolved
        result.collection_count += 1
    }
    return result, true
}

// Walk omitted ancestors until the nearest included source entry is found.
exchange_resolve_parent :: proc(
    ctx: Exchange_Resolve_Parent_Context, parent: int) -> int {
    current_parent := parent
    for current_parent >= 0 &&
        current_parent < ctx.source.entry_count {
        if ctx.is_installed(
            ctx.source.entries[current_parent].animation_id,
            ctx.user_data) {
            for index in 0..<len(ctx.resolved) {
                if ctx.resolved[index].collection_index ==
                    ctx.collection_index &&
                    ctx.resolved[index].source_entry_index == current_parent {
                    return index
                }
            }
        }
        current_parent = ctx.source.entries[current_parent].parent
    }
    return -1
}

// Assign dense sibling positions after omitted entries have been promoted.
exchange_resolve_sibling_order :: proc(
    entries: []sharingmodel.Exchange_Resolved_Entry,
    collection_index, parent_index: int) -> int {
    order := 0
    for entry in entries {
        if entry.collection_index == collection_index &&
            entry.parent_entry_index == parent_index {
            order += 1
        }
    }
    return order
}
