package userdata

import settings "../../settings"
import collections "../../collections"

// Commit a coalesced settings batch in one transaction.
store_commit_batch :: proc(store: ^Store, changes: settings.Change_Set) -> Commit_Result {
    return store_commit_batch_internal(store, changes, -1)
}

// Commit a batch with a deterministic write failure point available to tests.
store_commit_batch_internal :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    fail_after_changes: int) -> Commit_Result {
    return store_commit_user_data_internal(
        store, changes, []collections.Mutation{}, fail_after_changes)
}

// Commit settings and ordered collection mutations on the same store transaction.
store_commit_user_data :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation) -> Commit_Result {
    return store_commit_user_data_internal(store, changes, mutations, -1)
}

// Validate and commit one bounded immutable user-data task payload.
store_commit_user_data_internal :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation,
    fail_after_changes: int) -> Commit_Result {
    if store == nil || store^.status == .Closed {
        return {
            outcome = .Not_Committed,
            failure = {
                kind = .Closed,
            },
        }
    }
    if store^.status == .Unusable {
        return {
            outcome = .Store_Unusable,
            failure = {
                kind = .Unusable,
            },
        }
    }
    if !settings.valid_change_set(changes) {
        return {
            outcome = .Not_Committed,
            failure = {
                kind = .Invalid_Batch,
            },
        }
    }
    if len(mutations) > collections.MUTATION_CAPACITY {
        return {
            outcome = .Not_Committed,
            failure = {
                kind = .Invalid_Batch,
            },
        }
    }
    if store^.status == .Read_Only {
        return {
            outcome = .Not_Committed,
            failure = {
                kind = .Not_Writable,
            },
        }
    }
    if changes.count == 0 && len(mutations) == 0 {
        return {
            outcome = .Committed,
        }
    }
    return store_commit_transaction(store, changes, mutations, fail_after_changes)
}

// Apply and commit one nonempty transaction, rolling back every failed outcome.
store_commit_transaction :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation,
    fail_after_changes: int) -> Commit_Result {
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            outcome = .Not_Committed,
            failure = {
                kind = .Write,
                sqlite_error = begin_error,
            },
        }
    }
    applied := store_apply_batch_changes(
        store, changes, fail_after_changes)
    if !store_sqlite_error_is_clear(applied.failure) {
        return store_commit_rollback_result(
            store, {
                kind = .Write,
                sqlite_error = applied.failure,
            },
            applied.failed_id, applied.has_failed_id)
    }
    collection_error := store_apply_collection_mutations(store, mutations)
    if !store_error_is_clear(collection_error) {
        return store_commit_rollback_result(store, collection_error, {}, false)
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return store_commit_rollback_result(
            store, {
                kind = .Write,
                sqlite_error = commit_error,
            }, {}, false)
    }
    return {
        outcome = .Committed,
    }
}

// Preserve the failed write result and report a rollback failure as unusable.
store_commit_rollback_result :: proc(
    store: ^Store,
    failure: Store_Error,
    id: settings.Setting_Id,
    has_id: bool) -> Commit_Result {
    store_failure := store_rollback_failure(store, failure.kind, failure.sqlite_error)
    outcome := Commit_Outcome.Not_Committed
    if store^.status == .Unusable {
        outcome = .Store_Unusable
    }
    return {
        outcome = outcome,
        failure = store_failure,
        failed_id = id,
        has_failed_id = has_id,
    }
}

