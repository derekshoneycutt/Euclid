package gifmodel

import "base:runtime"
import vmem "core:mem/virtual"

// Return the contiguous encoded GIF bytes and their logical length.
Gif_Encode_Result :: struct {
    data: []u8,
    data_size: int,
}

// Store one encoder-owned indexed frame and its quantization metadata.
Gif_Encode_Frame :: struct {
    pixels: []u32,
    depth: int,
    count: int,
    r_bits: int,
    g_bits: int,
    b_bits: int,
    is_cooked: bool,
}

// Link one arena-owned output chunk in submission order.
Gif_Encode_Buffer :: struct {
    next: ^Gif_Encode_Buffer,
    size: int,
    data: []u8,
}

// Own one bounded GIF encoding session and its virtual-memory arena.
Gif_Encode_State :: struct {
    previous_frame: Gif_Encode_Frame,
    current_frame: Gif_Encode_Frame,

    lzw_mem: []i16,
    tlb_mem: []u8,
    used_mem: []u8,

    list_head: ^Gif_Encode_Buffer,
    list_tail: ^Gif_Encode_Buffer,

    width: int,
    height: int,
    alpha_threshold: int,
    use_bgra: bool,

    frames_submitted: int,

    arena: vmem.Arena,
    arena_allocator: runtime.Allocator,
    arena_initialized: bool,
}
