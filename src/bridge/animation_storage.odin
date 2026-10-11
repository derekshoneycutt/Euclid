package bridge

import animation_model "../core/animation"
import dynviewmodel "../dynview/model"

//   Initialize the shared owner and every generation-scoped borrower.
animation_storage_init :: proc(
    memory: ^animation_model.Animation_Memory,
    values: ^animation_model.Animation_Value_Store,
    documents: ^dynviewmodel.Dynview_Document_Store) -> bool {
    if !animation_model.animation_memory_init(memory) {
        return false
    }
    if !animation_model.animation_value_store_init(values, memory) {
        animation_model.animation_memory_destroy(memory)
        return false
    }
    if !dynviewmodel.dynview_document_store_init(documents, memory) {
        animation_model.animation_value_store_destroy(values)
        animation_model.animation_memory_destroy(memory)
        return false
    }
    return true
}

//   Clear borrowers, reset shared memory once, then publish one generation.
animation_storage_begin_generation :: proc(
    memory: ^animation_model.Animation_Memory,
    values: ^animation_model.Animation_Value_Store,
    documents: ^dynviewmodel.Dynview_Document_Store,
    generation: u64) -> animation_model.Animation_Memory_Status {
    if memory == nil || values == nil || documents == nil ||
        !memory.initialized || !values.initialized || !documents.initialized ||
        values.memory != memory {
        return .Illegal_State
    }
    if generation == 0 {
        return .Invalid_Argument
    }
    animation_model.animation_value_store_clear_generation(values)
    dynviewmodel.dynview_document_store_clear_generation(documents)
    status := animation_model.animation_memory_begin_generation(memory, generation)
    if status != .Ok {
        return status
    }
    animation_model.animation_value_store_publish_generation(values, generation)
    dynviewmodel.dynview_document_store_publish_generation(documents, memory, generation)
    return .Ok
}

//   Detach all borrowers before destroying their shared animation memory.
animation_storage_destroy :: proc(
    memory: ^animation_model.Animation_Memory,
    values: ^animation_model.Animation_Value_Store,
    documents: ^dynviewmodel.Dynview_Document_Store) {
    animation_model.animation_value_store_destroy(values)
    dynviewmodel.dynview_document_store_destroy(documents)
    animation_model.animation_memory_destroy(memory)
}