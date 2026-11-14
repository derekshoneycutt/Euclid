package userdata

import sqlite "../../sqlite"
import settings "../../settings"
import collections "../../collections"
import uuid "core:encoding/uuid"

DATABASE_APPLICATION_ID :: 0x45554355
DATABASE_SCHEMA_VERSION :: 2
DATABASE_PATH_MAX_BYTES :: 4096
DATABASE_TEXT_MAX_BYTES :: 64
DATABASE_DIRECTORY_NAME :: "Euclid"
DATABASE_FILENAME :: "user.sqlite3"

Store_Status :: enum u8 {
    Closed,
    Ready,
    Read_Only,
    Unusable,
}

Store_Error_Kind :: enum u8 {
    None,
    Invalid_State,
    Invalid_Path,
    Path_Resolution,
    Directory,
    Open,
    Sqlite_Threading,
    Wrong_Application,
    Unsupported_Schema,
    Future_Schema,
    Invalid_Schema,
    Schema,
    Not_Writable,
    Closed,
    Unusable,
    Invalid_Batch,
    Read,
    Write,
    Finalize,
    Close,
    Allocation,
    Invalid_Exercise,
    Invalid_Reference,
    Reference_Collision,
    Reference_Retired,
    Identity_Retired,
    Not_Found,
    Identity_Collision,
}

Store_Error :: struct {
    kind: Store_Error_Kind,
    sqlite_error: sqlite.Error,
    cleanup_error: sqlite.Error,
    application_id: i64,
    schema_version: i64,
}

Store :: struct {
    connection: sqlite.Connection,
    collection_replay_workspace: collections.Set,
    read_setting: sqlite.Statement,
    upsert_setting: sqlite.Statement,
    delete_setting: sqlite.Statement,
    read_collections: sqlite.Statement,
    read_collection_entries: sqlite.Statement,
    read_collection_note: sqlite.Statement,
    insert_collection: sqlite.Statement,
    insert_collection_entry: sqlite.Statement,
    delete_collection_entries: sqlite.Statement,
    delete_collections: sqlite.Statement,
    upsert_collection_note: sqlite.Statement,
    delete_orphan_collection_notes: sqlite.Statement,
    exercise_by_identity: sqlite.Statement,
    exercise_by_alias: sqlite.Statement,
    exercise_list_count: sqlite.Statement,
    exercise_list_rows: sqlite.Statement,
    retired_exercise_alias: sqlite.Statement,
    exercise_alias_state: sqlite.Statement,
    exercise_identity_taken: sqlite.Statement,
    exercise_rows_for_admission: sqlite.Statement,
    retired_exercise_rows_for_admission: sqlite.Statement,
    exercise_insert: sqlite.Statement,
    exercise_update: sqlite.Statement,
    exercise_delete: sqlite.Statement,
    exercise_retire_alias: sqlite.Statement,
    exercise_retire_identity: sqlite.Statement,
    status: Store_Status,
    path: [DATABASE_PATH_MAX_BYTES]u8,
    path_length: int,
}

Store_Header :: struct {
    application_id: i64,
    schema_version: i64,
    user_object_count: i64,
    failure: Store_Error,
}

Invalid_Value_Reason :: enum u8 {
    None,
    Storage_Type,
    Null_Column,
    Column_Type,
    Value_Range,
    Unknown_Enum,
    Text_Capacity,
}

Invalid_Setting_Value :: struct {
    id: settings.Setting_Id,
    reason: Invalid_Value_Reason,
}

Setting_Read_Result :: struct {
    value: settings.Setting_Value,
    found: bool,
    reason: Invalid_Value_Reason,
    failure: sqlite.Error,
}

Setting_Value_Read_Result :: struct {
    value: settings.Setting_Value,
    reason: Invalid_Value_Reason,
    failure: sqlite.Error,
}

Setting_Storage_Type_Result :: struct {
    kind: settings.Setting_Storage_Kind,
    reason: Invalid_Value_Reason,
    failure: sqlite.Error,
}

Batch_Apply_Result :: struct {
    failure: sqlite.Error,
    failed_id: settings.Setting_Id,
    has_failed_id: bool,
}

Load_Result :: struct {
    failure: Store_Error,
    invalid_count: int,
    invalid_values: [settings.SETTING_COUNT]Invalid_Setting_Value,
}

Commit_Outcome :: enum u8 {
    Committed,
    Not_Committed,
    Store_Unusable,
}

Commit_Result :: struct {
    outcome: Commit_Outcome,
    failure: Store_Error,
    failed_id: settings.Setting_Id,
    has_failed_id: bool,
}

Collection_Decode_Result :: struct {
    value: collections.Collection,
    valid: bool,
    failure: sqlite.Error,
}

Collection_Entry_Decode_Result :: struct {
    value: collections.Entry,
    valid: bool,
    failure: sqlite.Error,
}

Collection_Note_Read_Result :: struct {
    found: bool,
    text_length: int,
    notes_on_top: bool,
}

USER_EXERCISE_REFERENCE_MAX_BYTES :: 16
USER_EXERCISE_TITLE_MAX_BYTES :: 256
USER_EXERCISE_INSTRUCTIONS_MAX_BYTES :: 32 * 1024
USER_EXERCISE_LIST_PAGE_CAPACITY :: 16
USER_EXERCISE_ID_GENERATION_ATTEMPTS :: 8

// User_Exercise_Draft contains caller-owned text for one validated write.
User_Exercise_Draft :: struct {
    animation_id: uuid.Identifier,
    reference: string,
    title: string,
    instructions: string,
}

// User_Exercise_Record owns bounded copies of every persisted field.
User_Exercise_Record :: struct {
    id: uuid.Identifier,
    animation_id: uuid.Identifier,
    reference: [USER_EXERCISE_REFERENCE_MAX_BYTES]u8,
    reference_length: u8,
    title: [USER_EXERCISE_TITLE_MAX_BYTES]u8,
    title_length: u16,
    instructions: [USER_EXERCISE_INSTRUCTIONS_MAX_BYTES]u8,
    instructions_length: u32,
}

// User_Exercise_Summary omits instructions from bounded browsing results.
User_Exercise_Summary :: struct {
    id: uuid.Identifier,
    animation_id: uuid.Identifier,
    reference: [USER_EXERCISE_REFERENCE_MAX_BYTES]u8,
    reference_length: u8,
    title: [USER_EXERCISE_TITLE_MAX_BYTES]u8,
    title_length: u16,
}

// User_Exercise_Page owns one ordered, animation-scoped result window.
User_Exercise_Page :: struct {
    result_offset: u32,
    total_count: u32,
    returned_count: u16,
    more_available: bool,
    exercises: [USER_EXERCISE_LIST_PAGE_CAPACITY]User_Exercise_Summary,
}

// User_Exercise_Read_Result owns one decoded row and its SQLite read status.
User_Exercise_Read_Result :: struct {
    record: User_Exercise_Record,
    found: bool,
    failure: sqlite.Error,
}

// User_Exercise_Decode_Result reports row validity without a long return tuple.
User_Exercise_Decode_Result :: struct {
    record: User_Exercise_Record,
    valid: bool,
    failure: sqlite.Error,
}

// User_Exercise_Uuid_Result owns one copied UUID and its validation status.
User_Exercise_Uuid_Result :: struct {
    identity: uuid.Identifier,
    valid: bool,
    failure: sqlite.Error,
}

// User_Exercise_Operation identifies one worker-owned store operation.
User_Exercise_Operation :: enum u8 {
    None,
    Create,
    List,
    Read_Identity,
    Read_Reference,
    Update,
    Delete,
}

// User_Exercise_Task owns inputs and the joined result for one SQLite task.
User_Exercise_Task :: struct {
    request_id: u64,
    operation: User_Exercise_Operation,
    identity: uuid.Identifier,
    reference: [USER_EXERCISE_REFERENCE_MAX_BYTES]u8,
    reference_length: u8,
    draft_animation_id: uuid.Identifier,
    draft_reference: [USER_EXERCISE_REFERENCE_MAX_BYTES]u8,
    draft_reference_length: u8,
    draft_title: [USER_EXERCISE_TITLE_MAX_BYTES]u8,
    draft_title_length: u16,
    draft_instructions: [USER_EXERCISE_INSTRUCTIONS_MAX_BYTES]u8,
    draft_instructions_length: u32,
    result_offset: u32,
    page_limit: u16,
    result: User_Exercise_Record,
    page: User_Exercise_Page,
    failure: Store_Error,
}

// User_Exercise_Request_State keeps one operation in the existing save lane.
User_Exercise_Request_State :: enum u8 {
    None,
    Pending,
    In_Flight,
    Complete,
}

Collection_Kind_Decode_Result :: struct {
    value: collections.Entry_Kind,
    valid: bool,
    failure: sqlite.Error,
}

Collection_Uuid_Decode_Result :: struct {
    value: uuid.Identifier,
    valid: bool,
    failure: sqlite.Error,
}

Path_Error :: enum u8 {
    None,
    Invalid,
    Operating_System,
    Too_Long,
}
