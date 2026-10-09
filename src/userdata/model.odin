package userdata

import sqlite "../sqlite"
import settings "../settings"
import collections "../collections"
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
    Migration,
    Not_Writable,
    Closed,
    Unusable,
    Invalid_Batch,
    Read,
    Write,
    Finalize,
    Close,
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
    read_setting: sqlite.Statement,
    upsert_setting: sqlite.Statement,
    delete_setting: sqlite.Statement,
    read_collections: sqlite.Statement,
    read_collection_entries: sqlite.Statement,
    insert_collection: sqlite.Statement,
    insert_collection_entry: sqlite.Statement,
    delete_collection_entries: sqlite.Statement,
    delete_collections: sqlite.Statement,
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
