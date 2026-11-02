package sharingmodel

import storage "../../../core/storage"
import userdata "../../../persistence/userdata"
import sharing "../../../sharing"
import taskpool "../../../taskpool"
import uuid "core:encoding/uuid"

EXCHANGE_PATH_CAPACITY :: 4096
EXCHANGE_CHUNK_CAPACITY :: 65536
EXCHANGE_SELECTION_CAPACITY :: 256

Exchange_Task_Kind :: enum u8 {
    None,
    Export,
    Parse_Import,
    Commit_Import,
}

Exchange_Phase :: enum u8 {
    Idle,
    Draining_For_Export,
    Exporting,
    Parsing,
    Staged,
    Draining_For_Commit,
    Committing,
}

Exchange_Task_Result_Kind :: enum u8 {
    None,
    Succeeded,
    Cancelled,
    Read_Failed,
    Write_Failed,
    Invalid_Document,
    Persistence_Failed,
    Allocation_Failed,
}

Exchange_Request_Result :: enum u8 {
    Started,
    Busy,
    Invalid_Request,
    Failed,
}

// Exchange_Task_Result is the joined worker outcome copied by the display owner.
Exchange_Task_Result :: struct {
    kind: Exchange_Task_Result_Kind,
    store_error: userdata.Store_Error,
    sharing_rule: sharing.Sharing_Rule,
    bytes_processed: int,
}

// Exchange_Task_Payload is display-prepared, task-owned until the handle is joined.
Exchange_Task_Payload :: struct {
    kind: Exchange_Task_Kind,
    store: ^userdata.Store,
    path: [EXCHANGE_PATH_CAPACITY]u8,
    path_length: int,
    chunk: [EXCHANGE_CHUNK_CAPACITY]u8,
    persistence_row: userdata.Collection_Export_Row,
    writer_row: sharing.Export_Row,
    selected_ids: [EXCHANGE_SELECTION_CAPACITY]uuid.Identifier,
    selected_count: int,
    staged: ^sharing.Staged_Document,
    workspace: sharing.Staging_Workspace,
    plan: ^userdata.Collection_Import_Plan,
    cancel_requested: i32,
    result: Exchange_Task_Result,
}

// Exchange_Resolved_Collection records one eligible staged collection and its omissions.
Exchange_Resolved_Collection :: struct {
    source_index: int,
    resolved_entry_count: int,
    omitted_entry_count: int,
    importable: bool,
}

// Exchange_Resolved_Entry stores source and promoted-parent indices without allocation.
Exchange_Resolved_Entry :: struct {
    collection_index: int,
    source_entry_index: int,
    parent_entry_index: int,
    sibling_order: int,
}

// Exchange_Runtime owns task payload, staged arena data, and the admission lock.
Exchange_Runtime :: struct {
    phase: Exchange_Phase,
    arena: storage.Arena_Owner,
    payload: Exchange_Task_Payload,
    handle: taskpool.Task_Handle,
    task_active: bool,
    edit_admission_blocked: bool,
    collection_edit_locked: bool,
    restore_note_editing: bool,
    resolved_collections: []Exchange_Resolved_Collection,
    resolved_entries: []Exchange_Resolved_Entry,
    resolved_entry_to_plan: []int,
    resolved_collection_count: int,
    resolved_entry_count: int,
    left_out_entry_count: int,
    selected_import_collections: [EXCHANGE_SELECTION_CAPACITY]bool,
    selected_import_count: int,
    exported_collection_count: int,
    imported_collection_count: int,
}
