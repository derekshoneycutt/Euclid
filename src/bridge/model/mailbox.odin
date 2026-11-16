package bridgemodel

import vmem "core:mem/virtual"
import "core:sync"
import "core:time"
import presentation_model "../presentation"

// Mailbox_Node contains an immutable envelope and its FIFO successor.
Mailbox_Node :: struct($T: typeid) {
    value: T,
    next: ^Mailbox_Node(T),
}

// Consumer_Mailbox pauses admission while its sole consumer drains and resets the arena.
// The initialized arena stays at a stable address; dispatch never holds the mutex.
Consumer_Mailbox :: struct($T: typeid) {
    mutex: sync.Mutex,
    changed: sync.Cond,
    arena: vmem.Arena,
    first: ^Mailbox_Node(T),
    last: ^Mailbox_Node(T),
    borrowed: ^Mailbox_Node(T),
    accepted_bytes: int,
    byte_limit: int,
    outstanding: int,
    count_limit: int,
    peak_outstanding: int,
    peak_bytes: int,
    publication_count: u64,
    publication_time: time.Duration,
    lock_wait_time: time.Duration,
    copy_time: time.Duration,
    draining: bool,
    closed: bool,
    initialized: bool,
}

// Owned_View_Content retains exact presentation bytes outside any transport batch.
Owned_View_Content :: struct {
    message: Julia_Host_Egress,
    bytes: [presentation_model.PRESENTATION_MAX_SOURCE_BYTES]u8,
    present: bool,
}

// Consumer_Mailbox_Diagnostics reports logical admission pressure, not physical backing.
Consumer_Mailbox_Diagnostics :: struct {
    accepted_bytes: int,
    byte_limit: int,
    outstanding: int,
    peak_outstanding: int,
    peak_bytes: int,
    publication_count: u64,
    publication_time: time.Duration,
    lock_wait_time: time.Duration,
    copy_time: time.Duration,
}
