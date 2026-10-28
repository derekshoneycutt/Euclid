package main

import raw "../../libs/sqlite3"
import sqlite "../../src/sqlite"

import "base:runtime"
import "core:c"
import "core:strings"

Guard :: struct {
    fts5: bool,
    spellfix1: bool,
}

// Authorize only disposable-memory actions and explicitly requested built-in modules.
authorize :: proc "c" (
    user_data: rawptr, action: c.int,
    first, second, database, trigger: cstring) -> c.int {
    context = runtime.default_context()
    guard := (^Guard)(user_data)
    switch action {
    case 24, 25:
        return 1
    case 29:
        module := string(second)
        fts5_module := strings.equal_fold(module, "fts5") ||
            strings.equal_fold(module, "fts5vocab")
        if (!fts5_module || !guard.fts5) &&
            (!strings.equal_fold(module, "spellfix1") || !guard.spellfix1) {
            return 1
        }
    case 31:
        function := string(second)
        if strings.equal_fold(function, "load_extension") ||
            strings.equal_fold(function, "readfile") ||
            strings.equal_fold(function, "writefile") {
            return 1
        }
    case 19:
        pragma := string(first)
        if strings.equal_fold(pragma, "temp_store_directory") ||
            strings.equal_fold(pragma, "data_store_directory") ||
            strings.equal_fold(pragma, "writable_schema") {
            return 1
        }
        if strings.equal_fold(pragma, "temp_store") && second != nil &&
            !strings.equal_fold(string(second), "memory") && string(second) != "2" {
            return 1
        }
    }
    return 0
}

// Apply native connection guards before authorizing any request-owned SQL.
configure_connection :: proc(
    connection: ^sqlite.Connection, guard: ^Guard) -> raw.Result {
    db := connection.handle
    options := [?]c.int{1005, 1020, 1021}
    for option in options {
        result := raw.sqlite3_db_config(db, option, c.int(0), rawptr(nil))
        if result != .Ok {
            return result
        }
    }
    if result := raw.sqlite3_db_config(db, 1010, c.int(1), rawptr(nil)); result != .Ok {
        return result
    }
    raw.sqlite3_limit(db, 0, 8 * 1024 * 1024)
    raw.sqlite3_limit(db, 1, MAX_SOURCE_BYTES)
    raw.sqlite3_limit(db, 7, 0)
    raw.sqlite3_limit(db, 9, MAX_BINDS)
    raw.sqlite3_limit(db, 11, 0)
    failure := sqlite.connection_exec(connection, "PRAGMA temp_store=MEMORY")
    if failure.result != .Ok {
        return failure.result
    }
    return raw.sqlite3_set_authorizer(db, authorize, guard)
}

// Register only explicitly requested compiled-in capabilities, reporting unsupported names.
register_requirements :: proc(
    execution: ^Case_Execution, connection: ^sqlite.Connection,
    requirements: []string, guard: ^Guard) -> ^Failure {
    for name in requirements {
        switch name {
        case "fts5":
            if raw.sqlite3_compileoption_used("ENABLE_FTS5") == 0 {
                return make_failure(execution, "capability", .Error, "provider lacks fts5")
            }
            guard.fts5 = true
        case "spellfix1":
            if !guard.spellfix1 {
                failure := sqlite.connection_register_spellfix(connection)
                if failure.result != .Ok {
                    return native_failure(
                        execution, "capability", failure.result, -1)
                }
                guard.spellfix1 = true
            }
        case:
            return make_failure(
                execution, "capability", .Error, "unsupported provider capability")
        }
    }
    return nil
}
