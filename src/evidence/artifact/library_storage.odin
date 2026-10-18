package artifact

import "../observe"
import storage "../../core/storage"
import "core:fmt"

// Serialize typed TLSF pressure without presenting retained backing as arena reservation.
artifact_tlsf_json :: proc(sample: storage.Tlsf_Owner_Diagnostics) -> string {
    return fmt.tprintf(
        "{{\"initialized\":%v,\"current_live_bytes\":%d,\"retained_bytes\":%d," +
        "\"live_allocation_count\":%d,\"pool_count\":%d,\"peak_live_bytes\":%d," +
        "\"peak_allocation_count\":%d,\"growth_failure_count\":%d}}",
        sample.initialized, sample.current_live_bytes, sample.retained_bytes,
        sample.live_allocation_count, sample.pool_count, sample.peak_live_bytes,
        sample.peak_allocation_count, sample.growth_failure_count)
}

// Keep display, replay, preparation, semantic, and native lifetimes distinguishable.
artifact_library_storage_json :: proc(sample: observe.Library_Storage) -> string {
    return fmt.tprintf(
        "{{\"display\":%s,\"projection\":%s,\"search\":%s,\"semantic\":[%s,%s]," +
        "\"replay\":%s,\"native\":%s,\"collection_count\":%d," +
        "\"placement_count\":%d,\"projection_count\":%d," +
        "\"topology_build_count\":%d,\"semantic_text_bytes\":%d," +
        "\"native_control_count\":%d,\"native_text_bytes\":%d," +
        "\"native_toolkit_updates\":%d,\"native_toolkit_nodes\":%d,\"replay_joined\":%v}}",
        artifact_tlsf_json(sample.display), artifact_tlsf_json(sample.projection),
        artifact_tlsf_json(sample.search), artifact_tlsf_json(sample.semantic[0]),
        artifact_tlsf_json(sample.semantic[1]), artifact_tlsf_json(sample.replay),
        artifact_tlsf_json(sample.native), sample.collection_count,
        sample.placement_count, sample.projection_count,
        sample.topology_build_count, sample.semantic_text_bytes,
        sample.native_control_count, sample.native_text_bytes,
        sample.native_toolkit_updates, sample.native_toolkit_nodes, sample.replay_joined)
}
