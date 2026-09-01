package dynview

import "../core"
import "base:runtime"

// Build bounded shaped runs and glyphs before atomic cache publication.
Dynview_Shaped_Builder :: struct {
    runs: core.Bounded_Element_Builder(core.Dynview_Shaped_Run),
    glyphs: core.Bounded_Element_Builder(core.Shaped_Glyph),
    font_generation: u64,
    initialized: bool,
}

Dynview_Shaped_Append :: struct {
    math_command_index: int,
    site: core.Dynview_Shaped_Site,
    text_offset, text_len: int,
    glyphs: []core.Shaped_Glyph,
    metrics: core.Dynview_Shaped_Run,
}

//   Initialize empty shaped-record builders in the display-cache arena.
shaped_builder_init :: proc(
    builder: ^Dynview_Shaped_Builder,
    arena: ^core.Arena_Owner,
    font_generation: u64) -> core.Bounded_Builder_Status {

    return shaped_builder_init_with_allocator(
        builder, core.arena_owner_allocator(arena), font_generation)
}

//   Initialize shaped-record builders through a supplied allocator for failure tests.
shaped_builder_init_with_allocator :: proc(
    builder: ^Dynview_Shaped_Builder,
    allocator: runtime.Allocator,
    font_generation: u64) -> core.Bounded_Builder_Status {

    if builder == nil || font_generation == 0 {
        return .Invalid_Argument
    }
    run_status := core.bounded_element_builder_init_with_allocator(
        &builder^.runs, core.DYNVIEW_MAX_SHAPED_RUNS, allocator)
    if run_status != .Ok {
        return run_status
    }
    glyph_status := core.bounded_element_builder_init_with_allocator(
        &builder^.glyphs, core.FONT_SHAPED_GLYPH_CAPACITY, allocator)
    if glyph_status != .Ok {
        builder^ = {}
        return glyph_status
    }
    builder^.font_generation = font_generation
    builder^.initialized = true
    return .Ok
}

//   Append one complete shaped run without publishing a partial span.
shaped_run_from_append :: proc(
    builder: ^Dynview_Shaped_Builder,
    append: Dynview_Shaped_Append,
    glyph_start: int) -> core.Dynview_Shaped_Run {
    return {
        math_command_index = append.math_command_index,
        site = append.site,
        text_offset = append.text_offset,
        text_len = append.text_len,
        glyph_start = glyph_start,
        glyph_count = len(append.glyphs),
        font_generation = builder^.font_generation,
        base_pixel_size = append.metrics.base_pixel_size,
        raster_ascent = append.metrics.raster_ascent,
        advance = append.metrics.advance,
        ink_left = append.metrics.ink_left,
        ink_right = append.metrics.ink_right,
        ascent = append.metrics.ascent,
        descent = append.metrics.descent,
        italic_correction = append.metrics.italic_correction,
        top_accent_attachment = append.metrics.top_accent_attachment,
    }
}

//   Append one complete shaped run without publishing a partial span.
shaped_builder_append :: proc(
    builder: ^Dynview_Shaped_Builder,
    append: Dynview_Shaped_Append) -> core.Bounded_Builder_Status {

    if builder == nil || !builder^.initialized || append.math_command_index < 0 ||
        append.text_offset < 0 || append.text_len <= 0 || len(append.glyphs) <= 0 {
        return .Invalid_Argument
    }
    glyph_status := core.bounded_element_builder_reserve(
        &builder^.glyphs, len(append.glyphs))
    if glyph_status != .Ok {
        return glyph_status
    }
    run_status := core.bounded_element_builder_reserve(&builder^.runs, 1)
    if run_status != .Ok {
        return run_status
    }
    glyph_start := builder^.glyphs.count
    copy(builder^.glyphs.storage[glyph_start:], append.glyphs)
    builder^.glyphs.count += len(append.glyphs)
    run := shaped_run_from_append(builder, append, glyph_start)
    builder^.runs.storage[builder^.runs.count] = run
    builder^.runs.count += 1
    return .Ok
}

//   Seal valid shaped spans and publish them to layout records atomically.
shaped_builder_seal :: proc(
    builder: ^Dynview_Shaped_Builder,
    cache: ^core.Dynview_Compile_Cache,
    text_bytes_len: int,
    math_command_count: int,
    current_font_generation: u64) -> core.Bounded_Builder_Status {

    if !shaped_builder_can_seal(
        builder, cache, text_bytes_len, math_command_count, current_font_generation) {
        clear_shaped_records(cache)
        return .Invalid_Argument
    }
    runs, run_status := core.bounded_element_builder_seal(&builder^.runs)
    if run_status != .Ok {
        clear_shaped_records(cache)
        return run_status
    }
    glyphs, glyph_status := core.bounded_element_builder_seal(&builder^.glyphs)
    if glyph_status != .Ok {
        clear_shaped_records(cache)
        return glyph_status
    }
    clear_shaped_records(cache)
    cache^.shaped_runs = runs
    cache^.shaped_glyphs = glyphs
    cache^.shaped_font_generation = current_font_generation
    for run, run_index in runs {
        command := &cache^.math_commands[run.math_command_index]
        command^.shaped_run_indices[int(run.site)] = i32(run_index)
    }
    return .Ok
}

//   Reject stale generations and malformed run, text, glyph, or layout spans.
shaped_builder_can_seal :: proc(
    builder: ^Dynview_Shaped_Builder,
    cache: ^core.Dynview_Compile_Cache,
    text_bytes_len: int,
    math_command_count: int,
    current_font_generation: u64) -> bool {

    if builder == nil || !builder^.initialized || cache == nil || text_bytes_len < 0 ||
        math_command_count < 0 ||
        current_font_generation == 0 ||
        builder^.font_generation != current_font_generation {
        return false
    }
    previous_key := -1
    for run in builder^.runs.storage[:builder^.runs.count] {
        key := run.math_command_index * 4 + int(run.site)
        if run.font_generation != current_font_generation ||
            run.math_command_index < 0 || run.math_command_index >= math_command_count ||
            run.text_offset < 0 ||
            run.text_len <= 0 || run.text_len > text_bytes_len-run.text_offset ||
            run.glyph_start < 0 || run.glyph_count <= 0 ||
            run.glyph_count > builder^.glyphs.count-run.glyph_start ||
            key <= previous_key {
            return false
        }
        previous_key = key
    }
    return true
}

//   Remove all shaped aliases and restore math commands to fallback behavior.
clear_shaped_records :: proc(cache: ^core.Dynview_Compile_Cache) {
    if cache == nil {
        return
    }
    for command_index in 0..<cache^.math_command_count {
        cache^.math_commands[command_index].shaped_run_indices = {-1, -1, -1, -1}
    }
    cache^.shaped_runs = nil
    cache^.shaped_glyphs = nil
    cache^.shaped_font_generation = 0
}