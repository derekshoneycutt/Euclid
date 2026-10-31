#+test
package view

import user_data "../persistence/userdata"
import historyruntime "../terminal/history/runtime"
import terminalview "terminal"
import taskpool "../taskpool"
import "core:testing"

// Window teardown must close history before font shutdown can stop its shared pool.
@(test)
terminal_explorer_shutdown_finalizes_history_before_pool_stop :: proc(t: ^testing.T) {
    path := settings_save_test_path(t)
    defer settings_save_test_path_destroy(path)
    store: user_data.Store
    testing.expect_value(t, user_data.store_open(&store, path.filename).kind,
        user_data.Store_Error_Kind.None)
    defer user_data.store_close(&store)
    state, executor := settings_save_test_prepare_named_shutdown(t, &store)
    defer settings_save_test_destroy_state(state)
    defer free(executor, context.allocator)
    defer taskpool.task_pool_destroy(&executor^.pool)
    history := &state^.terminal_history_runtime
    terminalview.history_runtime_start(history, &store.connection)
    terminalview.history_runtime_service(
        history, &state^.user_data_admission, &executor^.pool, false, false)
    testing.expect(t, history^.task_active)
    testing.expect_value(t, shutdown_window_runtime({
        state = state,
    }), 0)
    testing.expect_value(t, history^.status, historyruntime.History_Runtime_Status.Closed)
    testing.expect(t, !history^.store.initialized && !history^.task_active)
    taskpool.task_pool_shutdown(&executor^.pool)
    shutdown_shared_user_data(state, &executor^.pool, true)
    testing.expect(t, !history^.shutdown_failed)
}
