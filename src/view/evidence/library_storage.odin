package viewevidence

import observe "../../evidence/observe"
import storage "../../core/storage"
import core "../../core"

// Sample display domains and a joined replay owner without retaining mutable storage.
observe_library_storage :: proc(
    state: ^core.Euclid_General_State,
    native: storage.Tlsf_Owner_Diagnostics = {}) -> observe.Library_Storage {
    preferences := &state^.preferences_runtime
    projection := &state^.ui_runtime.library.tree.projection
    semantic_text_bytes_index := state^.semantic_focus.committed_index
    result: observe.Library_Storage = {
        display = storage.tlsf_owner_diagnostics(
            &preferences.collections_state.allocator),
        projection = storage.tlsf_owner_diagnostics(&projection.allocator),
        search = storage.tlsf_owner_diagnostics(
            &state^.ui_runtime.library.search.visible_id_allocator),
        native = native,
        collection_count = preferences.collections_state.collection_count,
        placement_count = preferences.collections_state.entry_count,
        projection_count = projection.count,
        topology_build_count = projection.build_count,
        semantic_text_bytes =
            state^.semantic_focus.snapshots[semantic_text_bytes_index].text_count,
        replay_joined = !preferences.settings_save_active,
    }
    for &sample, index in result.semantic {
        sample = storage.tlsf_owner_diagnostics(
            &state^.semantic_focus.snapshots[index].allocator)
    }
    if result.replay_joined && preferences.settings_store != nil {
        result.replay = storage.tlsf_owner_diagnostics(
            &preferences.settings_store.collection_replay_workspace.allocator)
    }
    return result
}
