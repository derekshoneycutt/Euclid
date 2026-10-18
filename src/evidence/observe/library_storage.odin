package observe

import storage "../../core/storage"

// Independent TLSF samples; retained free-list backing is not resettable arena usage.
Library_Storage :: struct {
    display: storage.Tlsf_Owner_Diagnostics,
    projection: storage.Tlsf_Owner_Diagnostics,
    search: storage.Tlsf_Owner_Diagnostics,
    semantic: [2]storage.Tlsf_Owner_Diagnostics,
    replay: storage.Tlsf_Owner_Diagnostics,
    native: storage.Tlsf_Owner_Diagnostics,
    collection_count: int,
    placement_count: int,
    projection_count: int,
    topology_build_count: u64,
    semantic_text_bytes: int,
    native_control_count: int,
    native_text_bytes: int,
    native_toolkit_updates: u64,
    native_toolkit_nodes: u64,
    replay_joined: bool,
}
