package font

import "../../core"

import "core:os"
import "core:time"

// Minimum monotonic interval between font-source metadata scans.
FONT_SOURCE_POLL_INTERVAL_NS :: i64(100 * time.Millisecond)

// Quiet period required before one observed source change triggers reload.
FONT_SOURCE_DEBOUNCE_NS :: i64(150 * time.Millisecond)

// Comparable file identity used for polling without retaining OS metadata.
Font_Source_Signature :: core.Font_Source_Signature

// Per-font committed and debounce-pending source observation.
Font_Source_Monitor_Entry :: core.Font_Source_Monitor_Entry

// Display-owned polling/debounce state for every configured font source.
Font_Source_Monitor :: core.Font_Source_Monitor

//   Return monotonic nanoseconds for display-owned polling and debounce deadlines.
//
// Returns:
//   - Monotonic elapsed nanoseconds suitable only for interval comparison.
source_monitor_now_ns :: proc() -> i64 {
    return i64(time.tick_since({}))
}

//   Snapshot one source without retaining filesystem metadata past this frame.
//
// Returns:
//   - Present signature containing modification time and byte size, or zero/absent
//     when stat fails.
source_signature :: proc(path: string) -> Font_Source_Signature {
    info, stat_error := os.stat(path, context.temp_allocator)
    if stat_error != nil {
        return {}
    }
    return {
        modification_ns = time.to_unix_nanoseconds(info.modification_time),
        size = info.size,
        present = true,
    }
}

//   Establish source baselines without treating startup files as changes.
//
// Side effects:
//   - Snapshots every configured path, schedules the next poll, and marks initialized.
source_monitor_init :: proc(cache: ^Font_Cache, now_ns: i64) {
    for entry_index in 0..<FONT_KEY_COUNT {
        path := cache_source_path(cache, Font_Key(entry_index))
        cache.source_monitor.entries[entry_index].observed =
            source_signature(path)
    }
    cache.source_monitor.next_poll_ns = now_ns + FONT_SOURCE_POLL_INTERVAL_NS
    cache.source_monitor.initialized = true
}

//   Reset one quiet-period deadline whenever its source signature changes again.
//
// Notes:
//   - Reobserving the same pending signature does not extend its deadline; observing the
//     committed signature cancels pending change.
//
// Side effects:
//   - Records a distinct pending signature and schedules debounce maturity.
source_monitor_observe :: proc(
    cache: ^Font_Cache, key: Font_Key, signature: Font_Source_Signature,
    now_ns: i64) {

    monitored := &cache.source_monitor.entries[int(key)]
    if signature == monitored.observed {
        monitored.pending_change = false
        return
    }
    if !monitored.pending_change || signature != monitored.pending {
        monitored.pending = signature
        monitored.reload_due_ns = now_ns + FONT_SOURCE_DEBOUNCE_NS
        monitored.pending_change = true
    }
}

//   Commit quiet source changes and record replacement generations when relevant.
//
// Side effects:
//   - Promotes each mature pending signature, increments change telemetry, and requests
//     reload only for resident or previously demanded variants.
source_monitor_commit :: proc(cache: ^Font_Cache, now_ns: i64) {
    for entry_index in 0..<FONT_KEY_COUNT {
        monitored := &cache.source_monitor.entries[entry_index]
        if !monitored.pending_change || now_ns < monitored.reload_due_ns {
            continue
        }
        monitored.observed = monitored.pending
        monitored.pending_change = false
        cache.source_monitor.change_count += 1
        if cache_reload(cache, Font_Key(entry_index)) {
            cache.source_monitor.reload_count += 1
        }
    }
}

//   Poll font metadata at a bounded cadence and debounce changes across frames.
//
// Side effects:
//   - Commits mature changes every service call; scans source paths only after the poll
//     deadline and stops all monitoring once cache shutdown begins.
source_monitor_service :: proc(cache: ^Font_Cache, now_ns: i64) {
    if cache == nil || cache.shutting_down ||
        !cache.source_monitor.initialized {
        return
    }
    source_monitor_commit(cache, now_ns)
    if now_ns < cache.source_monitor.next_poll_ns {
        return
    }
    cache.source_monitor.next_poll_ns = now_ns + FONT_SOURCE_POLL_INTERVAL_NS
    for entry_index in 0..<FONT_KEY_COUNT {
        path := cache_source_path(cache, Font_Key(entry_index))
        source_monitor_observe(
            cache, Font_Key(entry_index),
            source_signature(path), now_ns)
    }
}