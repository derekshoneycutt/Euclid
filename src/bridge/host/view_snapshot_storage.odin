package julia_host

import bridgemodel "../model"
import dynviewmodel "../../dynview/model"
import storage "../../core/storage"
import "../../core"

//   Return canonical presentation text only when it belongs to the active animation.
// The returned string aliases service-owned published slot storage until replacement.
current_view_snapshot_text :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return ""
    }
    service := state^.julia_runtime_service
    slot_index := service^.published_view_snapshot_index
    if slot_index < 0 {
        return ""
    }
    slot := &service^.view_snapshots[slot_index]
    if !view_snapshot_matches_current(state, service, slot) {
        return ""
    }
    return string(slot^.presentation_bytes)
}

//   Return a free snapshot slot that is neither pending nor displayed.
// Published slots are intentionally unavailable even after their semantic data is copied,
// because presentation bytes still alias the slot.
reserve_view_snapshot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.view_snapshots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Reserve one snapshot slot for lazy preparation by request-owned Julia work.
reserve_view_candidate :: proc(service: ^Julia_Runtime_Service) -> int {
    slot_index := reserve_view_snapshot(service)
    if slot_index < 0 {
        return -1
    }
    slot := &service^.view_snapshots[slot_index]
    if !prepare_view_snapshot_slot(slot) {
        return -1
    }
    slot^.state = .Reserved
    return slot_index
}

//   Compare complete semantic payloads without relying on hashes or generations.
published_view_snapshot_equals :: proc(
    service: ^Julia_Runtime_Service, candidate: ^View_Snapshot) -> bool {

    published_index := service^.published_view_snapshot_index
    if published_index < 0 {
        return false
    }
    published := &service^.view_snapshots[published_index]
    if published == candidate || published^.state != .Published {
        return false
    }
    return view_snapshot_slice_equal(
        published^.presentation_bytes, candidate^.presentation_bytes) &&
        published^.presentation_mime == candidate^.presentation_mime &&
        view_snapshot_slice_equal(published^.command_text, candidate^.command_text) &&
        view_snapshot_slice_equal(published^.commands, candidate^.commands) &&
        view_snapshot_slice_equal(published^.math_programs, candidate^.math_programs) &&
        view_snapshot_slice_equal(published^.math_table_descriptors,
            candidate^.math_table_descriptors) &&
        view_snapshot_slice_equal(published^.math_commands, candidate^.math_commands) &&
        view_snapshot_slice_equal(published^.math_nodes, candidate^.math_nodes) &&
        view_snapshot_slice_equal(published^.document_text, candidate^.document_text) &&
        view_snapshot_slice_equal(published^.documents, candidate^.documents) &&
        view_snapshot_slice_equal(
            published^.document_blocks, candidate^.document_blocks) &&
        view_snapshot_slice_equal(
            published^.document_inlines, candidate^.document_inlines) &&
        view_snapshot_slice_equal(published^.document_display_rows,
            candidate^.document_display_rows)
}

//   Return true when two payload slices have identical values in identical order.
view_snapshot_slice_equal :: proc(left, right: []$Element) -> bool {
    if len(left) != len(right) {
        return false
    }
    for value, index in left {
        if value != right[index] {
            return false
        }
    }
    return true
}

//   Clear generation payload metadata without copying the slot-owned arena owner.
reset_view_snapshot_slot_payload :: proc(slot: ^View_Snapshot) {
    slot^.candidate_committed = false
    slot^.request_id = 0
    slot^.generation = 0
    slot^.runtime_generation = 0
    slot^.animation_generation = 0
    slot^.animation = nil
    slot^.presentation_mime = .Text_Plain
    slot^.presentation_bytes = nil
    slot^.command_text = nil
    slot^.command_revision = 0
    slot^.stream_has_error = false
    slot^.stream_open_block = false
    slot^.stream_open_block_id = 0
    slot^.commands = nil
    slot^.math_programs = nil
    slot^.math_table_descriptors = nil
    slot^.math_commands = nil
    slot^.math_nodes = nil
    slot^.document_text = nil
    slot^.documents = nil
    slot^.document_blocks = nil
    slot^.document_inlines = nil
    slot^.document_display_rows = nil
}

//   Initialize the byte-backed builders for one view snapshot generation.
prepare_view_snapshot_byte_builders :: proc(
    slot: ^View_Snapshot) -> [3]storage.Bounded_Builder_Status {
    return {
        storage.bounded_byte_builder_init(
            &slot^.presentation_builder, VIEW_SNAPSHOT_TEXT_CAPACITY, &slot^.arena),
        storage.bounded_byte_builder_init(
            &slot^.command_text_builder,
            dynviewmodel.DYNVIEW_MAX_TEXT_BYTES, &slot^.arena),
        storage.bounded_byte_builder_init(
            &slot^.document_text_builder,
            dynviewmodel.DYNVIEW_MAX_DOCUMENT_BYTES, &slot^.arena),
    }
}

//   Initialize every future arena-backed payload builder for one free slot generation.
prepare_view_snapshot_builders :: proc(slot: ^View_Snapshot) -> bool {
    byte_statuses := prepare_view_snapshot_byte_builders(slot)
    statuses: [12]storage.Bounded_Builder_Status = {
        byte_statuses[0], byte_statuses[1], byte_statuses[2],
        storage.bounded_element_builder_init(
            &slot^.command_builder, dynviewmodel.DYNVIEW_MAX_COMMANDS, &slot^.arena),
        storage.bounded_element_builder_init(
            &slot^.math_program_builder,
            dynviewmodel.DYNVIEW_MAX_MATH_PROGRAMS, &slot^.arena),
        storage.bounded_element_builder_init(&slot^.math_table_descriptor_builder,
            dynviewmodel.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS, &slot^.arena),
        storage.bounded_element_builder_init(
            &slot^.math_command_builder,
            dynviewmodel.DYNVIEW_MAX_MATH_COMMANDS, &slot^.arena),
        storage.bounded_element_builder_init(
            &slot^.math_node_builder, dynviewmodel.DYNVIEW_MAX_MATH_NODES, &slot^.arena),
        storage.bounded_element_builder_init(
            &slot^.document_builder, dynviewmodel.DYNVIEW_MAX_DOCUMENTS, &slot^.arena),
        storage.bounded_element_builder_init(&slot^.document_block_builder,
            dynviewmodel.DYNVIEW_MAX_DOCUMENT_BLOCKS, &slot^.arena),
        storage.bounded_element_builder_init(&slot^.document_inline_builder,
            dynviewmodel.DYNVIEW_MAX_DOCUMENT_INLINES, &slot^.arena),
        storage.bounded_element_builder_init(&slot^.document_display_row_builder,
            dynviewmodel.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS, &slot^.arena),
    }
    for status in statuses {
        if status != .Ok {
            return false
        }
    }
    return true
}

//   Reset and prepare arena storage only after the slot has returned to Free.
prepare_view_snapshot_slot :: proc(slot: ^View_Snapshot) -> bool {
    if slot == nil || slot^.state != .Free || !slot^.arena.initialized {
        return false
    }
    storage.arena_owner_reset(&slot^.arena)
    reset_view_snapshot_slot_payload(slot)
    if prepare_view_snapshot_builders(slot) {
        return true
    }
    storage.arena_owner_reset(&slot^.arena)
    slot^.presentation_builder = {}
    slot^.command_text_builder = {}
    slot^.command_builder = {}
    slot^.math_program_builder = {}
    slot^.math_table_descriptor_builder = {}
    slot^.math_command_builder = {}
    slot^.math_node_builder = {}
    slot^.document_text_builder = {}
    slot^.document_builder = {}
    slot^.document_block_builder = {}
    slot^.document_inline_builder = {}
    slot^.document_display_row_builder = {}
    return false
}

//   Initialize all fixed snapshot-slot arena owners in place.
view_snapshot_slots_init :: proc(service: ^Julia_Runtime_Service) -> bool {
    if service == nil {
        return false
    }
    for &slot, slot_index in service^.view_snapshots {
        if storage.arena_owner_init(
            &slot.arena, bridgemodel.VIEW_SNAPSHOT_ARENA_RESERVATION) {
            continue
        }
        for initialized_index in 0..<slot_index {
            storage.arena_owner_destroy(&service^.view_snapshots[initialized_index].arena)
        }
        return false
    }
    return true
}

//   Destroy every snapshot-slot arena after Julia worker ownership has ended.
view_snapshot_slots_destroy :: proc(service: ^Julia_Runtime_Service) {
    if service == nil {
        return
    }
    for &slot in service^.view_snapshots {
        storage.arena_owner_destroy(&slot.arena)
    }
}

//   Generate canonical presentation and semantic data into snapshot-owned storage.
// The completed slot contains self-owned copies of all populated spans and can be
// published without consulting Julia.
build_generated_view_snapshot_payloads :: proc(
    slot: ^View_Snapshot,
    staging: ^dynviewmodel.Dynview_System,
    presentation: string) -> bool {
    if !build_view_snapshot_text_payloads(slot, presentation,
        staging^.command_buffer.text_bytes[:staging^.command_buffer.text_bytes_len]) {
        return false
    }
    slot^.command_revision = staging^.command_buffer.revision
    slot^.stream_has_error = staging^.command_buffer.has_stream_error
    slot^.stream_open_block = staging^.command_buffer.stream_open_block
    slot^.stream_open_block_id = staging^.command_buffer.stream_open_block_id
    cache := &staging^.compile_cache
    return build_view_snapshot_record_payloads(slot, {
        commands = staging^.command_buffer.commands[
            :staging^.command_buffer.command_count],
        math_programs = cache^.math_programs[:cache^.math_program_count],
        math_commands = cache^.math_commands[:cache^.math_command_count],
        math_nodes = cache^.math_nodes[:cache^.math_node_count],
        math_table_descriptors = cache^.math_table_descriptors[
            :cache^.math_table_descriptor_count],
        document_text = cache^.document_text[:cache^.document_text_count],
        documents = cache^.documents[:cache^.document_count],
        document_blocks = cache^.document_blocks[:cache^.document_block_count],
        document_inlines = cache^.document_inlines[:cache^.document_inline_count],
        document_display_rows = cache^.document_display_rows[
            :cache^.document_display_row_count],
    })
}

//   Copy and seal canonical presentation and semantic text as one snapshot candidate.
build_view_snapshot_text_payloads :: proc(
    slot: ^View_Snapshot, presentation: string, command_text: []u8) -> bool {

    presentation_count := min(len(presentation), VIEW_SNAPSHOT_TEXT_CAPACITY)
    presentation_status := storage.bounded_byte_builder_append(
        &slot^.presentation_builder,
        transmute([]u8)presentation[:presentation_count])
    command_status := storage.bounded_byte_builder_append(
        &slot^.command_text_builder, command_text)
    if presentation_status != .Ok || command_status != .Ok {
        return false
    }
    presentation_payload, presentation_seal_status :=
        storage.bounded_byte_builder_seal(&slot^.presentation_builder)
    command_payload, command_seal_status :=
        storage.bounded_byte_builder_seal(&slot^.command_text_builder)
    if presentation_seal_status != .Ok || command_seal_status != .Ok {
        return false
    }
    slot^.presentation_bytes = presentation_payload
    slot^.command_text = command_payload
    return true
}

//   Copy and seal all semantic record families as one complete snapshot candidate.
build_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Payloads) -> bool {

    if !append_view_snapshot_record_payloads(slot, payloads) {
        return false
    }
    sealed, ok := seal_view_snapshot_record_payloads(slot)
    if !ok {
        return false
    }
    slot^.commands = sealed.commands
    slot^.math_programs = sealed.programs
    slot^.math_table_descriptors = sealed.descriptors
    slot^.math_commands = sealed.math_commands
    slot^.math_nodes = sealed.nodes
    slot^.document_text = sealed.document_text
    slot^.documents = sealed.documents
    slot^.document_blocks = sealed.document_blocks
    slot^.document_inlines = sealed.document_inlines
    slot^.document_display_rows = sealed.document_display_rows
    return true
}

//   Append every semantic payload family before any builder is sealed.
append_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Payloads) -> bool {

    statuses: [10]storage.Bounded_Builder_Status = {
        storage.bounded_byte_builder_append(
            &slot^.document_text_builder, payloads.document_text),
        storage.bounded_element_builder_append(
            &slot^.command_builder, payloads.commands),
        storage.bounded_element_builder_append(
            &slot^.math_program_builder, payloads.math_programs),
        storage.bounded_element_builder_append(
            &slot^.math_table_descriptor_builder, payloads.math_table_descriptors),
        storage.bounded_element_builder_append(
            &slot^.math_command_builder, payloads.math_commands),
        storage.bounded_element_builder_append(
            &slot^.math_node_builder, payloads.math_nodes),
        storage.bounded_element_builder_append(
            &slot^.document_builder, payloads.documents),
        storage.bounded_element_builder_append(
            &slot^.document_block_builder, payloads.document_blocks),
        storage.bounded_element_builder_append(
            &slot^.document_inline_builder, payloads.document_inlines),
        storage.bounded_element_builder_append(&slot^.document_display_row_builder,
            payloads.document_display_rows),
    }
    for status in statuses {
        if status != .Ok {
            return false
        }
    }
    return true
}

//   Seal every appended semantic record family as one immutable payload set.
seal_view_snapshot_record_payloads :: proc(
    slot: ^View_Snapshot) -> (View_Snapshot_Sealed_Records, bool) {

    commands, command_status :=
        storage.bounded_element_builder_seal(&slot^.command_builder)
    programs, program_status :=
        storage.bounded_element_builder_seal(&slot^.math_program_builder)
    descriptors, descriptor_status :=
        storage.bounded_element_builder_seal(&slot^.math_table_descriptor_builder)
    math_commands, math_command_status :=
        storage.bounded_element_builder_seal(&slot^.math_command_builder)
    nodes, node_status :=
        storage.bounded_element_builder_seal(&slot^.math_node_builder)
    document_text, document_text_status :=
        storage.bounded_byte_builder_seal(&slot^.document_text_builder)
    documents, document_status :=
        storage.bounded_element_builder_seal(&slot^.document_builder)
    document_blocks, block_status :=
        storage.bounded_element_builder_seal(&slot^.document_block_builder)
    document_inlines, inline_status :=
        storage.bounded_element_builder_seal(&slot^.document_inline_builder)
    document_display_rows, row_status :=
        storage.bounded_element_builder_seal(&slot^.document_display_row_builder)
    if command_status != .Ok || program_status != .Ok || descriptor_status != .Ok ||
        math_command_status != .Ok || node_status != .Ok ||
        document_text_status != .Ok || document_status != .Ok ||
        block_status != .Ok || inline_status != .Ok || row_status != .Ok {
        return {}, false
    }
    return {commands, programs, descriptors, math_commands, nodes,
        document_text, documents, document_blocks, document_inlines,
        document_display_rows}, true
}

//   Reset worker-only semantic emission storage for one generation.
// Capacity remains allocated; only populated lengths, errors, and cache validity are reset.
reset_view_snapshot_staging :: proc(staging: ^dynviewmodel.Dynview_System) {
    staging^.content = {}
    staging^.command_buffer.command_count = 0
    staging^.command_buffer.text_bytes_len = 0
    staging^.command_buffer.command_view = nil
    staging^.command_buffer.text_view = nil
    staging^.command_buffer.has_stream_error = false
    staging^.command_buffer.stream_open_block = false
    staging^.command_buffer.stream_open_block_id = -1
    staging^.command_buffer.revision += 1
    staging^.compile_cache.math_program_count = 0
    staging^.compile_cache.math_table_descriptor_count = 0
    staging^.compile_cache.math_command_count = 0
    staging^.compile_cache.math_node_count = 0
    staging^.compile_cache.document_text_count = 0
    staging^.compile_cache.document_count = 0
    staging^.compile_cache.document_block_count = 0
    staging^.compile_cache.document_inline_count = 0
    staging^.compile_cache.document_display_row_count = 0
    staging^.compile_cache.last_error_code = 0
    staging^.compile_cache.is_valid = false
}

//   Install immutable snapshot aliases before invalidating display compilation caches.
// The display thread retains the published slot until replacement or invalidation.
install_view_snapshot_content :: proc(
    slot: ^View_Snapshot, runtime: ^dynviewmodel.Dynview_System) {

    install_view_snapshot_aliases(slot, runtime)
    install_view_snapshot_buffer(slot, &runtime^.command_buffer)
    install_view_snapshot_cache_counts(slot, &runtime^.compile_cache)
    runtime^.pending_invalidation_mask |= 1
}

// Install immutable semantic aliases from one published snapshot.
install_view_snapshot_aliases :: proc(
    slot: ^View_Snapshot, runtime: ^dynviewmodel.Dynview_System) {

    runtime^.content = {
        revision = slot^.command_revision,
        presentation_mime = slot^.presentation_mime,
        presentation_bytes = slot^.presentation_bytes,
        has_stream_error = slot^.stream_has_error,
        stream_open_block = slot^.stream_open_block,
        stream_open_block_id = slot^.stream_open_block_id,
        commands = slot^.commands,
        text_bytes = slot^.command_text,
        math_programs = slot^.math_programs,
        math_table_descriptors = slot^.math_table_descriptors,
        math_commands = slot^.math_commands,
        math_nodes = slot^.math_nodes,
        document_text = slot^.document_text,
        documents = slot^.documents,
        document_blocks = slot^.document_blocks,
        document_inlines = slot^.document_inlines,
        document_display_rows = slot^.document_display_rows,
    }
}

// Install immutable command aliases from one published snapshot.
install_view_snapshot_buffer :: proc(
    slot: ^View_Snapshot, buffer: ^dynviewmodel.Dynview_Command_Buffer) {

    buffer^.revision = slot^.command_revision
    buffer^.command_count = len(slot^.commands)
    buffer^.text_bytes_len = len(slot^.command_text)
    buffer^.has_stream_error = slot^.stream_has_error
    buffer^.stream_open_block = slot^.stream_open_block
    buffer^.stream_open_block_id = slot^.stream_open_block_id
    buffer^.command_view = slot^.commands
    buffer^.text_view = slot^.command_text
}

// Install semantic family counts and invalidate derived cache state.
install_view_snapshot_cache_counts :: proc(
    slot: ^View_Snapshot, cache: ^dynviewmodel.Dynview_Compile_Cache) {

    cache^.math_program_count = len(slot^.math_programs)
    cache^.math_table_descriptor_count = len(slot^.math_table_descriptors)
    cache^.math_command_count = len(slot^.math_commands)
    cache^.math_node_count = len(slot^.math_nodes)
    cache^.document_text_count = len(slot^.document_text)
    cache^.document_count = len(slot^.documents)
    cache^.document_block_count = len(slot^.document_blocks)
    cache^.document_inline_count = len(slot^.document_inlines)
    cache^.document_display_row_count = len(slot^.document_display_rows)
    cache^.is_valid = false
    cache^.layout_is_valid = false
}
