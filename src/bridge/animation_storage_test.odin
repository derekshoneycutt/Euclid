package bridge

import animation_model "../core/animation"
import dynviewmodel "../dynview/model"

import "core:testing"

//   Verify one owner transition resets all borrowers and the arena exactly once.
@(test)
bridge_test_animation_storage_advances_all_borrowers :: proc(t: ^testing.T) {
    memory: animation_model.Animation_Memory
    values: animation_model.Animation_Value_Store
    documents: dynviewmodel.Dynview_Document_Store
    testing.expect(t, animation_storage_init(&memory, &values, &documents))
    defer animation_storage_destroy(&memory, &values, &documents)
    testing.expect_value(t, animation_storage_begin_generation(
        &memory, &values, &documents, 3), animation_model.Animation_Memory_Status.Ok)
    testing.expect_value(t, animation_model.animation_value_store_set(
        &values, {3, 1, 1, 2}, []u8{4}), animation_model.Animation_Value_Status.Ok)
    before := animation_model.animation_memory_diagnostics(&memory)

    testing.expect_value(t, animation_storage_begin_generation(
        &memory, &values, &documents, 4), animation_model.Animation_Memory_Status.Ok)
    after := animation_model.animation_memory_diagnostics(&memory)
    value_diagnostics := animation_model.animation_value_store_diagnostics(&values)
    testing.expect_value(t, memory.generation, u64(4))
    testing.expect_value(t, values.generation, u64(4))
    testing.expect_value(t, documents.generation, u64(4))
    testing.expect_value(t, value_diagnostics.entry_count, 0)
    testing.expect_value(t, after.reset_count, before.reset_count + 1)
}