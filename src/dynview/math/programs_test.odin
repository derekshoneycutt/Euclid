package dynview_math

import app_core "../../core"

import "core:testing"

//   Verify table lengths and rule records resolve once into boundary spans.
@(test)
math_table_boundaries_resolve_typed_lengths_and_rules :: proc(t: ^testing.T) {
    descriptor := app_core.Dynview_Math_Table_Descriptor{rows = 2, columns = 2}
    descriptor.column_boundary_gaps[0] = {0, .Zero}
    descriptor.column_boundary_gaps[1] = {0.5, .Em}
    descriptor.vertical_rule_counts[0] = 2
    descriptor.vertical_rule_counts[1] = 2
    descriptor.row_extra_gaps[0] = {0.5, .Ex}
    descriptor.horizontal_rule_counts[1] = 1

    thickness := math_table_rule_thickness(20)
    separation := math_table_rule_separation(20)
    occupied := thickness * 2 + separation
    clearance := vertical_math_content_clearance(20, 10)
    outer_width := math_table_column_boundary_width(&descriptor, 0, 20, 10)
    column_width := math_table_column_boundary_width(&descriptor, 1, 20, 10)
    row_height := math_table_row_boundary_height(&descriptor, 1, 20)

    testing.expect(t, clearance > 6)
    testing.expect_value(t, outer_width - occupied, clearance)
    testing.expect_value(t, column_width - occupied, clearance * 2)
    testing.expect_value(t, row_height,
        matrix_row_gap(20) + f32(5) + thickness)
    testing.expect_value(t,
        math_table_length_px({3, .Point}, 20, 0), f32(4))
    tight_ascent, tight_descent := math_table_row_strut(.Tight, 20)
    testing.expect_value(t, tight_ascent, f32(12))
    testing.expect_value(t, tight_descent, f32(4))
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
    arena: app_core.Arena_Owner
    testing.expect(t, app_core.arena_owner_init(&arena))
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    program := app_core.Dynview_Math_Program{command_count = 3}
    cache^.math_commands[0].math_atom_class = .Ord
    cache^.math_commands[1].math_atom_class = .Bin
    cache^.math_commands[2].math_atom_class = .Ord

    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        app_core.Dynview_Math_Atom_Class.Bin)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(4))

    cache^.math_commands[0].math_atom_class = .Open
    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        app_core.Dynview_Math_Atom_Class.Ord)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 1, 18), f32(0))

    cache^.math_commands[0].math_atom_class = .Ord
    cache^.math_commands[2].math_atom_class = .Rel
    testing.expect_value(t,
        math_program_effective_atom_class(cache, program, 1),
        app_core.Dynview_Math_Atom_Class.Ord)
    testing.expect_value(t,
        math_program_command_leading_space(cache, program, 2, 18), f32(5))
}

//   Verify explicit math glue contributes its own fixed mu width between atoms.
@(test)
math_explicit_glue_uses_semantic_width :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    testing.expect(t, app_core.arena_owner_init(&arena))
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    program := app_core.Dynview_Math_Program{command_count = 3}
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
