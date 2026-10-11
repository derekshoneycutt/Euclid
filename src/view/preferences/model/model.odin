package preferencesmodel

import settings "../../../settings"
import user_data "../../../userdata"
import taskpool "../../../taskpool"
import collections "../../../collections"

// Settings_Save_Status is the shared user-data durability state of local edits.
Settings_Save_Status :: enum u8 {
    Saved,
    Pending,
    Saving,
    Unavailable,
    Failed,
}

// Settings_Save_Task_Payload is immutable from submit until its handle is joined.
Settings_Save_Task_Payload :: struct {
    store: ^user_data.Store,
    changes: settings.Change_Set,
    mutations: [collections.MUTATION_CAPACITY]collections.Mutation,
    mutation_count: int,
    user_data_revision: u64,
    result: user_data.Commit_Result,
    owner_thread_id: int,
    worker_thread_id: int,
}

// Settings_Save_Runtime owns bounded persistence work until its worker is joined.
Settings_Save_Runtime :: struct {
    settings_pending: settings.Change_Set,
    collections_state: collections.Set,
    collection_mutations: [collections.MUTATION_CAPACITY]collections.Mutation,
    collection_mutation_count: int,
    collection_revision: u64,
    user_data_revision: u64,
    user_data_failure_revision: u64,
    user_data_failure: user_data.Store_Error,
    user_data_failure_unresolved: bool,
    settings_store: ^user_data.Store,
    settings_failure_count: int,
    settings_retry_frames: int,
    settings_save_payload: Settings_Save_Task_Payload,
    settings_save_handle: taskpool.Task_Handle,
    settings_save_active: bool,
    settings_save_commit_count: u64,
    settings_save_failure_count: u64,
    settings_save_owner_execution_count: u64,
}
