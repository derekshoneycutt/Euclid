#+test
package ui_dust

import "core:fmt"
import "core:testing"
import "core:time"

UI_DUST_BENCHMARK :: #config(UI_DUST_BENCHMARK, false)

// Measure full-capacity matching separately from setup in an optimized test build.
@(test)
ui_dust_reclaim_benchmark :: proc(t: ^testing.T) {
    when UI_DUST_BENCHMARK {
        system := ui_dust_test_system({0, 0, 400, 400})
        defer free(system, context.allocator)
        total, worst := f64(0), f64(0)
        for iteration in 0..<110 {
            ui_dust_settle(system)
            ui_dust_validate_context(system, {
                visible = true,
                viewport = {0, 0, 400, 400},
            })
            ui_dust_test_fill_reclaim_capacity(system)
            start := time.tick_now()
            ui_dust_form_targets(system)
            elapsed := time.duration_seconds(time.tick_since(start)) * 1000
            testing.expect_value(t, system^.formation_reclaimed, 2048)
            if iteration >= 10 {
                total += elapsed
                worst = max(worst, elapsed)
            }
        }
        fmt.printfln("Reclaim 4096 sources / 2048 targets: mean %.3f ms, max %.3f ms",
            total / 100, worst)
    }
}
