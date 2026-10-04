package main

import app "app"
import evidence_allocation "evidence/allocation"

import "core:fmt"
import "core:log"
import "core:os"

// Run with allocation evidence enabled for debug process builds.
run_debug_application :: proc() -> int {
    fmt.println("Initiating debug allocation evidence...")
    original_allocator := context.allocator
    process_allocations: evidence_allocation.Domain
    if !evidence_allocation.domain_init(
        &process_allocations, original_allocator, original_allocator) {
        fmt.eprintln("Unable to initialize debug allocation evidence.")
        return 1
    }
    context.allocator = evidence_allocation.domain_allocator(&process_allocations)
    exit_code := app.run_application(log.Level.Debug, &process_allocations)
    context.allocator = original_allocator
    evidence_allocation.domain_report(&process_allocations)
    evidence_allocation.domain_destroy(&process_allocations)
    fmt.println("Debug allocation evidence destroyed.")
    return exit_code
}

// Run the process allocation envelope and return its result to the OS.
main :: proc() {
    exit_code := 0
    when ODIN_DEBUG {
        exit_code = run_debug_application()
    } else {
        exit_code = app.run_application(log.Level.Info)
    }
    if exit_code != 0 {
        os.exit(exit_code)
    }
}
