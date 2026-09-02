package dynview

import "../core"

import "core:testing"

//   Verify sealed layout records preserve order, indexes, and grid placement.
@(test)
layout_storage_publishes_ordered_records :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    cache := new(core.Dynview_Compile_Cache, allocator)
    testing.expect_value(t, layout_builders_init(cache, &arena), DYNVIEW_STATUS_OK)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 20
    state := Dynview_Layout_State{active_block_id = 7, line_index = 0, col = 1}
    acc := Dynview_Layout_Line_Accumulator{}
    layout_seed_line_accumulator(&acc, 0, 12, 4)

    first_status := layout_push_item(cache, &state, &acc, {
        kind = .Text_Run, col_span = 2, draw_height = 16, ascent = 12, descent = 4,
    })
    second_status := layout_push_item(cache, &state, &acc, {
        kind = .Inline_Box, col_span = 1, draw_height = 20,
    })
    line_status := layout_finalize_line(cache, &state, &acc, 12, 4)
    seal_status := layout_builders_seal(cache)

    testing.expect_value(t, first_status, DYNVIEW_STATUS_OK)
    testing.expect_value(t, second_status, DYNVIEW_STATUS_OK)
    testing.expect_value(t, line_status, DYNVIEW_STATUS_OK)
    testing.expect_value(t, seal_status, DYNVIEW_STATUS_OK)
    testing.expect_value(t, len(cache^.layout_items), 2)
    testing.expect_value(t, len(cache^.layout_lines), 1)
    testing.expect_value(t, cache^.layout_items[0].block_id, i32(7))
    testing.expect_value(t, cache^.layout_items[0].col_start, 1)
    testing.expect_value(t, cache^.layout_items[1].col_start, 3)
    testing.expect_value(t, cache^.layout_lines[0].item_start, 0)
    testing.expect_value(t, cache^.layout_lines[0].item_count, 2)
    testing.expect(t, cache^.layout_is_valid)
}

//   Verify both layout record families reject one record beyond their maxima.
@(test)
layout_storage_rejects_exact_limit_overflow :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    cache := new(core.Dynview_Compile_Cache, allocator)
    testing.expect_value(t, layout_builders_init(cache, &arena), DYNVIEW_STATUS_OK)
    cache^.layout_item_builder.count = core.DYNVIEW_MAX_LAYOUT_ITEMS
    item_status := layout_push_item(
        cache, &Dynview_Layout_State{}, &Dynview_Layout_Line_Accumulator{}, {})

    cache^.layout_line_builder.count = core.DYNVIEW_MAX_LAYOUT_LINES
    line_status := layout_finalize_line(
        cache, &Dynview_Layout_State{}, &Dynview_Layout_Line_Accumulator{}, 12, 4)

    testing.expect_value(t, item_status, DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, line_status, DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, len(cache^.layout_items), 0)
    testing.expect_value(t, len(cache^.layout_lines), 0)
}

//   Verify resetting a partial layout clears all arena-backed record aliases.
@(test)
layout_storage_reset_clears_partial_aliases :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    cache := new(core.Dynview_Compile_Cache, allocator)
    testing.expect_value(t, layout_builders_init(cache, &arena), DYNVIEW_STATUS_OK)
    state := Dynview_Layout_State{}
    acc := Dynview_Layout_Line_Accumulator{}
    testing.expect_value(t, layout_push_item(cache, &state, &acc, {}),
        DYNVIEW_STATUS_OK)

    layout_reset_cache(cache)

    testing.expect_value(t, len(cache^.layout_items), 0)
    testing.expect_value(t, len(cache^.layout_lines), 0)
    testing.expect_value(t, cache^.layout_item_builder.max_count, 0)
    testing.expect_value(t, cache^.layout_line_builder.max_count, 0)
}

//   Verify the display-style TeX table resolves thin, medium, and thick atom spacing.
@(test)
math_atom_spacing_uses_tex_display_table :: proc(t: ^testing.T) {
    testing.expect_value(t, math_atom_spacing_mu(.Ord, .Op), f32(3))
    testing.expect_value(t, math_atom_spacing_mu(.Ord, .Bin), f32(4))
    testing.expect_value(t, math_atom_spacing_mu(.Ord, .Rel), f32(5))
    testing.expect_value(t, math_atom_spacing_mu(.Open, .Ord), f32(0))
    testing.expect_value(t, math_atom_spacing_mu(.Close, .Bin), f32(4))
    testing.expect_value(t, math_atom_spacing_mu(.Punct, .Open), f32(3))
    testing.expect_value(t, math_atom_spacing_mu(.Inner, .Close), f32(0))
}

//   Verify binary atoms retain binary spacing only between compatible neighbors.
@(test)
math_binary_atom_cancellation_matches_tex_neighbors :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    cache := new(core.Dynview_Compile_Cache, allocator)
    program := core.Dynview_Math_Program{command_count = 3}
    cache^.math_commands[0].math_atom_class = .Ord
    cache^.math_commands[1].math_atom_class = .Bin
    cache^.math_commands[2].math_atom_class = .Ord

    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        core.Dynview_Math_Atom_Class.Bin)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(4))

    cache^.math_commands[0].math_atom_class = .Open
    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        core.Dynview_Math_Atom_Class.Ord)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(0))

    cache^.math_commands[0].math_atom_class = .Ord
    cache^.math_commands[2].math_atom_class = .Rel
    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        core.Dynview_Math_Atom_Class.Ord)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 2, 18), f32(5))
}

//   Verify explicit math glue contributes its own fixed mu width between atoms.
@(test)
math_explicit_glue_uses_semantic_width :: proc(t: ^testing.T) {
    arena: core.Arena_Owner
    testing.expect(t, core.arena_owner_init(&arena))
    defer core.arena_owner_destroy(&arena)
    allocator := core.arena_owner_allocator(&arena)
    cache := new(core.Dynview_Compile_Cache, allocator)
    program := core.Dynview_Math_Program{command_count = 3}
    cache^.math_commands[0].math_atom_class = .Ord
    cache^.math_commands[1].math_glue_kind = .Thick
    cache^.math_commands[2].math_atom_class = .Ord

    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(5))
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 2, 18), f32(0))

    cache^.math_commands[1].math_glue_kind = .Space
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(6))

    cache^.math_commands[1].math_glue_kind = .Negative_Thin
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(-3))

    cache^.math_commands[1].math_glue_kind = .Quad
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(18))

    cache^.math_commands[1].math_glue_kind = .Thin
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(3))
}