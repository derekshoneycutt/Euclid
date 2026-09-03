package bridge

import "../core"

import "core:testing"

//   Verify valid bridge table metadata copies into bounded native storage.
@(test)
dynview_table_descriptor_import_preserves_typed_metadata :: proc(t: ^testing.T) {
    cache := new(core.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    descriptors := [1]Bridge_Dynview_Math_Table_Descriptor{{
        rows = 2,
        columns = 3,
        cell_style = i32(core.Dynview_Math_Style_Level.Text),
    }}
    descriptors[0].column_alignments[0] =
        i32(core.Dynview_Matrix_Column_Alignment.Left)
    descriptors[0].column_alignments[1] =
        i32(core.Dynview_Matrix_Column_Alignment.Center)
    descriptors[0].column_alignments[2] =
        i32(core.Dynview_Matrix_Column_Alignment.Right)

    status := dynview_import_math_table_descriptors(cache, raw_data(descriptors[:]), 1)

    testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, cache^.math_table_descriptor_count, 1)
    testing.expect_value(t, cache^.math_table_descriptors[0].rows, 2)
    testing.expect_value(t, cache^.math_table_descriptors[0].columns, 3)
    testing.expect_value(t, cache^.math_table_descriptors[0].cell_style,
        core.Dynview_Math_Style_Level.Text)
    testing.expect_value(t, cache^.math_table_descriptors[0].column_alignments[2],
        core.Dynview_Matrix_Column_Alignment.Right)
}

//   Verify invalid descriptor enums reject without publishing a native count.
@(test)
dynview_table_descriptor_import_rejects_invalid_alignment :: proc(t: ^testing.T) {
    cache := new(core.Dynview_Compile_Cache, context.allocator)
    defer free(cache)
    descriptors := [1]Bridge_Dynview_Math_Table_Descriptor{{
        rows = 1,
        columns = 1,
        cell_style = i32(core.Dynview_Math_Style_Level.Text),
    }}
    descriptors[0].column_alignments[0] = 9

    status := dynview_import_math_table_descriptors(cache, raw_data(descriptors[:]), 1)

    testing.expect_value(t, status, i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, cache^.math_table_descriptor_count, 0)
}

//   Verify descriptor identities are required on matrices and forbidden elsewhere.
@(test)
dynview_table_descriptor_references_are_matrix_local :: proc(t: ^testing.T) {
    matrix_op := Bridge_Dynview_Math_Op{table_descriptor_index = 1}
    text := Bridge_Dynview_Math_Op{table_descriptor_index = -1}

    testing.expect(t, dynview_math_op_table_reference_valid(matrix_op, .Matrix, 2))
    testing.expect(t, !dynview_math_op_table_reference_valid(matrix_op, .Matrix, 1))
    testing.expect(t, dynview_math_op_table_reference_valid(text, .Text_Run, 2))
    text.table_descriptor_index = 0
    testing.expect(t, !dynview_math_op_table_reference_valid(text, .Text_Run, 2))
}