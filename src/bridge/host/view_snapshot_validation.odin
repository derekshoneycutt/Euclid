package julia_host

import dynviewmodel "../../dynview/model"
import storage "../../core/storage"
import dyncore "../../dynview/core"

//   Validate all semantic bounds and require a closed, error-free command stream.
// Sealed aliases are checked before any copy into display-owned storage.
view_snapshot_is_valid :: proc(slot: ^View_Snapshot) -> bool {
    if slot == nil || !view_snapshot_text_payload_is_valid(
        &slot^.presentation_builder, slot^.presentation_bytes,
        VIEW_SNAPSHOT_TEXT_CAPACITY) || !view_snapshot_text_payload_is_valid(
        &slot^.command_text_builder, slot^.command_text,
        dynviewmodel.DYNVIEW_MAX_TEXT_BYTES) || !view_snapshot_text_payload_is_valid(
        &slot^.document_text_builder, slot^.document_text,
        dynviewmodel.DYNVIEW_MAX_DOCUMENT_BYTES) {
        return false
    }
    if !view_snapshot_record_payloads_are_valid(slot) {
        return false
    }
    if slot^.stream_has_error || slot^.stream_open_block {
        return false
    }
    for command in slot^.commands {
        if !view_snapshot_command_text_spans_valid(command, len(slot^.command_text)) {
            return false
        }
    }
    for command in slot^.math_commands {
        if !view_snapshot_command_text_spans_valid(command, len(slot^.command_text)) ||
            !view_snapshot_math_command_semantics_are_valid(command) ||
            (command.kind == .Matrix && (command.table_descriptor_index < 0 ||
            int(command.table_descriptor_index) >= len(slot^.math_table_descriptors))) {
            return false
        }
    }
    for descriptor in slot^.math_table_descriptors {
        if !view_snapshot_math_table_descriptor_is_valid(descriptor) {
            return false
        }
    }
    return view_snapshot_math_records_are_valid(slot) &&
        view_snapshot_documents_are_valid(slot)
}

//   Validate one sealed native table descriptor at the publication boundary.
view_snapshot_math_table_descriptor_is_valid :: proc(
    descriptor: dynviewmodel.Dynview_Math_Table_Descriptor) -> bool {
    return dyncore.math_table_descriptor_is_valid(descriptor)
}

//   Validate atom and explicit-glue metadata before snapshot publication.
view_snapshot_math_command_semantics_are_valid :: proc(
    command: dynviewmodel.Dynview_Command) -> bool {

    atom := i32(command.math_atom_class)
    glue := i32(command.math_glue_kind)
    if atom < i32(dynviewmodel.Dynview_Math_Atom_Class.None) ||
        atom > i32(dynviewmodel.Dynview_Math_Atom_Class.Inner) ||
        glue < i32(dynviewmodel.Dynview_Math_Glue_Kind.None) ||
        glue > i32(dynviewmodel.Dynview_Math_Glue_Kind.Thin) {
        return false
    }
    if command.math_glue_kind != .None {
        return command.math_atom_class == .None
    }
    return command.math_atom_class != .None
}

//   Require every record slice to be the populated prefix of its sealed builder.
view_snapshot_record_payloads_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    return view_snapshot_record_payload_is_valid(
        &slot^.command_builder, slot^.commands, dynviewmodel.DYNVIEW_MAX_COMMANDS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_program_builder,
            slot^.math_programs, dynviewmodel.DYNVIEW_MAX_MATH_PROGRAMS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_table_descriptor_builder,
            slot^.math_table_descriptors,
            dynviewmodel.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_command_builder,
            slot^.math_commands, dynviewmodel.DYNVIEW_MAX_MATH_COMMANDS) &&
        view_snapshot_record_payload_is_valid(&slot^.math_node_builder,
            slot^.math_nodes, dynviewmodel.DYNVIEW_MAX_MATH_NODES) &&
        view_snapshot_record_payload_is_valid(&slot^.document_builder,
            slot^.documents, dynviewmodel.DYNVIEW_MAX_DOCUMENTS) &&
        view_snapshot_record_payload_is_valid(&slot^.document_block_builder,
            slot^.document_blocks, dynviewmodel.DYNVIEW_MAX_DOCUMENT_BLOCKS) &&
        view_snapshot_record_payload_is_valid(&slot^.document_inline_builder,
            slot^.document_inlines, dynviewmodel.DYNVIEW_MAX_DOCUMENT_INLINES) &&
        view_snapshot_record_payload_is_valid(&slot^.document_display_row_builder,
            slot^.document_display_rows, dynviewmodel.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS)
}

//   Require one record slice to alias its sealed builder's populated prefix.
view_snapshot_record_payload_is_valid :: proc(
    builder: ^$Builder/storage.Bounded_Element_Builder($Element),
    payload: []Element, max_count: int) -> bool {

    if builder == nil || !builder.sealed || builder.count != len(payload) ||
        len(payload) > max_count {
        return false
    }
    return len(payload) == 0 || raw_data(payload) == raw_data(builder.storage)
}

//   Require one published byte slice to be the populated prefix of its sealed builder.
view_snapshot_text_payload_is_valid :: proc(
    builder: ^storage.Bounded_Byte_Builder, payload: []u8, max_count: int) -> bool {

    if builder == nil || !builder.sealed || builder.count != len(payload) ||
        len(payload) > max_count {
        return false
    }
    return len(payload) == 0 || raw_data(payload) == raw_data(builder.storage)
}

//   Validate every text-bearing span in one semantic command against the sealed blob.
view_snapshot_command_text_spans_valid :: proc(
    command: dynviewmodel.Dynview_Command, text_count: int) -> bool {

    spans: [5][2]int = {
        {command.text_offset, command.text_len},
        {command.script_base_text_offset, command.script_base_text_len},
        {command.script_sup_text_offset, command.script_sup_text_len},
        {command.script_sub_text_offset, command.script_sub_text_len},
        {command.radical_index_text_offset, command.radical_index_text_len},
    }
    for span in spans {
        if span[0] < 0 || span[1] < 0 || span[1] > text_count ||
            span[0] > text_count - span[1] {
            return false
        }
    }
    return true
}

//   Validate math program ranges and node-local text and child spans.
view_snapshot_math_records_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    for node in slot^.math_nodes {
        if !view_snapshot_span_is_valid(
            node.text_offset, node.text_len, len(slot^.command_text)) {
            return false
        }
    }
    for program in slot^.math_programs {
        if !view_snapshot_math_program_is_valid(slot, program) {
            return false
        }
        for node in slot^.math_nodes[
            program.node_start:program.node_start + program.node_count] {
            if !view_snapshot_math_node_is_valid(node, program) {
                return false
            }
        }
    }
    return true
}

//   Validate one math program and its root against populated snapshot records.
view_snapshot_math_program_is_valid :: proc(
    slot: ^View_Snapshot, program: dynviewmodel.Dynview_Math_Program) -> bool {

    if !program.valid || !view_snapshot_range_is_valid(
        program.command_start, program.command_count, len(slot^.math_commands)) ||
        !view_snapshot_range_is_valid(
            program.node_start, program.node_count, len(slot^.math_nodes)) ||
        !view_snapshot_span_is_valid(
            program.copy_text_offset, program.copy_text_len,
            len(slot^.command_text)) {
        return false
    }
    return program.node_count == 0 || view_snapshot_node_index_is_valid(
        program.root_node_index, program, false)
}

//   Validate one node's contiguous and kind-specific child references.
view_snapshot_math_node_is_valid :: proc(
    node: dynviewmodel.Dynview_Math_Node,
    program: dynviewmodel.Dynview_Math_Program) -> bool {

    if node.child_count < 0 || (node.child_count > 0 &&
        (!view_snapshot_node_index_is_valid(node.first_child, program, false) ||
        node.child_count > program.node_start + program.node_count -
            node.first_child)) {
        return false
    }
    switch node.kind {
    case .None, .Sequence, .Glyph_Run:
        return true
    case .Script:
        return view_snapshot_node_index_is_valid(node.base_child, program, false) &&
            view_snapshot_node_index_is_valid(
                node.superscript_child, program, true) &&
            view_snapshot_node_index_is_valid(node.subscript_child, program, true)
    case .Radical:
        return view_snapshot_node_index_is_valid(node.radicand_child, program, false) &&
            view_snapshot_node_index_is_valid(node.index_child, program, true)
    case .Fraction:
        return view_snapshot_node_index_is_valid(node.numerator_child, program, false) &&
            view_snapshot_node_index_is_valid(node.denominator_child, program, false)
    case .Stretch_Delimiter:
        return view_snapshot_node_index_is_valid(node.base_child, program, false)
    }
    return false
}

//   Validate a required or optional node index within one program-owned range.
view_snapshot_node_index_is_valid :: proc(
    index: int, program: dynviewmodel.Dynview_Math_Program, optional: bool) -> bool {

    if optional && index == -1 {
        return true
    }
    return index >= program.node_start &&
        index < program.node_start + program.node_count
}

//   Validate one nonnegative offset/count pair without overflowing its upper bound.
view_snapshot_span_is_valid :: proc(offset, count, total: int) -> bool {
    return offset >= 0 && count >= 0 && count <= total && offset <= total - count
}

//   Validate one record range; empty ranges permit the canonical zero start.
view_snapshot_range_is_valid :: proc(start, count, total: int) -> bool {
    return view_snapshot_span_is_valid(start, count, total)
}

//   Validate all semantic document ownership ranges and inline references.
view_snapshot_documents_are_valid :: proc(slot: ^View_Snapshot) -> bool {
    for document in slot^.documents {
        if !view_snapshot_document_is_valid(slot, document) {
            return false
        }
        blocks := slot^.document_blocks[
            document.block_start:document.block_start + document.block_count]
        for block in blocks {
            if !view_snapshot_document_block_is_valid(document, block) {
                return false
            }
        }
        if !view_snapshot_document_list_sequence_is_valid(blocks) {
            return false
        }
        items := slot^.document_inlines[
            document.inline_start:document.inline_start + document.inline_count]
        for item in items {
            if !view_snapshot_document_inline_is_valid(slot, document, item) {
                return false
            }
        }
        rows := slot^.document_display_rows[document.display_row_start:
            document.display_row_start + document.display_row_count]
        for row in rows {
            if !view_snapshot_document_display_row_is_valid(slot, document, row) {
                return false
            }
        }
    }
    return true
}

// Validate flattened list labels, body ownership, and item-start adjacency.
view_snapshot_document_list_sequence_is_valid :: proc(
    blocks: []dynviewmodel.Dynview_Document_Block) -> bool {

    for block, index in blocks {
        if block.kind == .List_Item {
            if index+1 < len(blocks) {
                body := blocks[index+1]
                if body.item_first_block && (body.kind == .List_Item ||
                    body.list_id != block.list_id ||
                    body.item_ordinal != block.item_ordinal) {
                    return false
                }
            }
        } else if block.list_kind != .None &&
            (block.list_id == 0 || block.item_ordinal == 0) {
            return false
        }
    }
    return true
}

//   Validate one document descriptor before slicing any child records.
view_snapshot_document_is_valid :: proc(
    slot: ^View_Snapshot, document: dynviewmodel.Dynview_Document) -> bool {

    return view_snapshot_span_is_valid(
        document.source_offset, document.source_count, len(slot^.document_text)) &&
        view_snapshot_span_is_valid(
            document.text_offset, document.text_count, len(slot^.document_text)) &&
        view_snapshot_range_is_valid(document.block_start, document.block_count,
            len(slot^.document_blocks)) &&
        view_snapshot_range_is_valid(document.inline_start, document.inline_count,
            len(slot^.document_inlines)) &&
        view_snapshot_range_is_valid(document.display_row_start,
            document.display_row_count, len(slot^.document_display_rows))
}

//   Validate one block's kind, source, and child range within its document.
view_snapshot_document_block_is_valid :: proc(
    document: dynviewmodel.Dynview_Document,
    block: dynviewmodel.Dynview_Document_Block) -> bool {

    kind := int(block.kind)
    alignment := int(block.alignment)
    container_kind := int(block.container_kind)
    list_kind := int(block.list_kind)
    has_list := block.list_kind != .None
    list_container := block.container_kind == .Itemize ||
        block.container_kind == .Enumerate ||
        block.container_kind == .Description
    return kind >= int(dynviewmodel.Dynview_Document_Block_Kind.Paragraph) &&
        kind <= int(dynviewmodel.Dynview_Document_Block_Kind.List_Item) &&
        alignment >= int(dynviewmodel.Dynview_Document_Alignment.Left) &&
        alignment <= int(dynviewmodel.Dynview_Document_Alignment.Right) &&
        container_kind >= int(dynviewmodel.Dynview_Document_Container_Kind.None) &&
        container_kind <= int(dynviewmodel.Dynview_Document_Container_Kind.Description) &&
        list_kind >= int(dynviewmodel.Dynview_Document_List_Kind.None) &&
        list_kind <= int(dynviewmodel.Dynview_Document_List_Kind.Description) &&
        block.container_depth <= 4 && block.left_margin_levels <= 4 &&
        block.right_margin_levels <= 4 &&
        (!list_container || has_list) &&
        (has_list || block.list_id == 0 && block.item_ordinal == 0) &&
        (!has_list || block.list_id > 0 && block.item_ordinal > 0 &&
            block.left_margin_levels > 0) &&
        (block.kind != .List_Item || has_list && block.inline_count > 0 &&
            !block.item_first_block) &&
        (block.kind == .List_Item || !block.item_first_block || has_list) &&
        view_snapshot_subspan_is_valid(document.source_offset,
            document.source_count, block.source_offset, block.source_count) &&
        view_snapshot_subspan_is_valid(document.inline_start,
            document.inline_count, block.inline_start, block.inline_count) &&
        view_snapshot_subspan_is_valid(document.display_row_start,
            document.display_row_count, block.display_row_start,
            block.display_row_count)
}

// Validate one display row's source range, programs, alignment, and number.
view_snapshot_document_display_row_is_valid :: proc(
    slot: ^View_Snapshot, document: dynviewmodel.Dynview_Document,
    row: dynviewmodel.Dynview_Document_Display_Row) -> bool {

    alignment := int(row.alignment)
    return view_snapshot_subspan_is_valid(document.source_offset,
        document.source_count, row.source_offset, row.source_count) &&
        row.primary_program_id >= 0 &&
        row.primary_program_id < len(slot^.math_programs) &&
        (row.secondary_program_id == -1 ||
            row.secondary_program_id >= 0 &&
            row.secondary_program_id < len(slot^.math_programs)) &&
        alignment >= int(dynviewmodel.Dynview_Document_Alignment.Left) &&
        alignment <= int(dynviewmodel.Dynview_Document_Alignment.Right) &&
        row.number >= 0
}

//   Validate one inline's semantic kind, byte spans, and optional math program.
view_snapshot_document_inline_is_valid :: proc(
    slot: ^View_Snapshot,
    document: dynviewmodel.Dynview_Document,
    item: dynviewmodel.Dynview_Document_Inline) -> bool {

    kind := int(item.kind)
    if kind < int(dynviewmodel.Dynview_Document_Inline_Kind.Text) ||
        kind > int(dynviewmodel.Dynview_Document_Inline_Kind.Forced_Break) ||
        !view_snapshot_subspan_is_valid(document.source_offset,
            document.source_count, item.source_offset, item.source_count) ||
        !view_snapshot_subspan_is_valid(document.text_offset,
            document.text_count, item.text_offset, item.text_count) ||
        !view_snapshot_document_inline_link_is_valid(document, item) {
        return false
    }
    if item.kind == .Math {
        root_style := int(item.root_style)
        return item.math_program_id >= 0 &&
            item.math_program_id < len(slot^.math_programs) &&
            root_style >= int(dynviewmodel.Dynview_Math_Style_Level.Display) &&
            root_style <= int(dynviewmodel.Dynview_Math_Style_Level.Text)
    }
    if item.math_program_id != -1 {
        return false
    }
    if item.kind == .Space {
        space_kind := int(item.space_kind)
        return space_kind >= int(dynviewmodel.Dynview_Document_Space_Kind.Breakable) &&
            space_kind <= int(dynviewmodel.Dynview_Document_Space_Kind.Controlled)
    }
    return item.kind != .Shape || item.shape.present
}

// Validate one optional link target against its owning document text span.
view_snapshot_document_inline_link_is_valid :: proc(
    document: dynviewmodel.Dynview_Document,
    item: dynviewmodel.Dynview_Document_Inline) -> bool {
    return item.link_id <= u16(dynviewmodel.DYNVIEW_MAX_DOCUMENT_LINKS) &&
        (item.link_id != 0 ||
            item.link_target_offset == 0 && item.link_target_count == 0) &&
        (item.link_id == 0 ||
            item.link_target_count > 0 &&
            view_snapshot_subspan_is_valid(document.text_offset,
                document.text_count, item.link_target_offset,
                item.link_target_count))
}

//   Require one child range to be fully contained by its owner range.
view_snapshot_subspan_is_valid :: proc(
    owner_start, owner_count, child_start, child_count: int) -> bool {

    if owner_start < 0 || owner_count < 0 || child_start < owner_start ||
        child_count < 0 {
        return false
    }
    relative_start := child_start-owner_start
    return child_count <= owner_count && relative_start <= owner_count-child_count
}
