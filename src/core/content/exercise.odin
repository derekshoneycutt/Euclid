package content_model

import "core:encoding/uuid"

// Bounded result window validated with the operation's identity.
Exercise_Query_Page :: struct {
    offset: u32,
    limit: u16,
}

// Accept the stable lowercase ASCII spelling used for friendly exercise references.
exercise_reference_is_valid :: proc(reference: string) -> bool {
    if len(reference) < 1 || len(reference) > EXERCISE_REFERENCE_BYTE_CAPACITY {
        return false
    }
    for byte in transmute([]u8)reference {
        if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') &&
           byte != '-' && byte != '_' {
            return false
        }
    }
    return true
}

// Require one canonical nonzero lowercase UUID.
exercise_uuid_is_valid :: proc(value: string) -> bool {
    if len(value) != EXERCISE_UUID_BYTE_COUNT {
        return false
    }
    identifier, failure := uuid.read(value)
    if failure != .None || identifier == (uuid.Identifier{}) {
        return false
    }
    for byte, index in transmute([]u8)value {
        if index == 8 || index == 13 || index == 18 || index == 23 {
            if byte != '-' {
                return false
            }
        } else if !(byte >= '0' && byte <= '9') &&
           !(byte >= 'a' && byte <= 'f') {
            return false
        }
    }
    return true
}

// Build one operation-specific request with validated bounded text and paging.
exercise_query_request_make :: proc(
    generation: u64, kind: Exercise_Query_Kind, animation_id, reference: string,
    page: Exercise_Query_Page) -> (Exercise_Query_Request, bool) {
    request: Exercise_Query_Request = {
        generation = generation,
        kind = kind,
        result_offset = page.offset,
        page_limit = page.limit,
    }
    if kind == .List || kind == .Children {
        root := kind == .Children && len(animation_id) == 0
        if (!root && !exercise_uuid_is_valid(animation_id)) || len(reference) != 0 ||
           page.limit == 0 || page.limit > EXERCISE_LIST_PAGE_CAPACITY ||
           page.offset > u32(max(i32)) {
            return {}, false
        }

        request.animation_id_length = u16(len(animation_id))
        copy(request.animation_id[:], transmute([]u8)animation_id)
        return request, true
    }
    if len(animation_id) != 0 || page.offset != 0 || page.limit != 0 {
        return {}, false
    }
    if kind == .Resolve_Alias {
        if !exercise_reference_is_valid(reference) {
            return {}, false
        }
    } else if kind == .Resolve_Uuid || kind == .Read_Uuid {
        if !exercise_uuid_is_valid(reference) {
            return {}, false
        }
    } else {
        return {}, false
    }
    request.reference_length = u16(len(reference))
    copy(request.reference[:], transmute([]u8)reference)
    return request, true
}

// Find an exact catalogue identity in the current immutable generation.
exercise_animation_exists :: proc(
    generation: ^Content_Generation, identity: string) -> bool {
    if generation == nil || !generation.sealed || !generation.data.complete {
        return false
    }
    id, failure := uuid.read(identity)
    if failure != .None {
        return false
    }
    for record in generation.records[:generation.record_count] {
        if record.stable_id == id {
            return record.node_kind == .Animation
        }
    }
    return false
}

// Copy only the requested catalogue page from the worker's admitted snapshot.
exercise_catalogue_children :: proc(
    generation: ^Content_Generation,
    request: Exercise_Query_Request) -> Exercise_Query_Result {
    value := request
    result: Exercise_Query_Result = {
        generation = value.generation,
        kind = value.kind,
        result_offset = value.result_offset,
        status = .Invalid_Request,
    }
    if value.animation_id_length > len(value.animation_id) ||
       value.reference_length != 0 {
        return result
    }
    _, valid := exercise_query_request_make(value.generation, value.kind,
        string(value.animation_id[:value.animation_id_length]),
        "", {value.result_offset, value.page_limit})
    if !valid || value.kind != .Children {
        return result
    }
    if generation == nil || !generation.sealed || !generation.data.complete {
        result.status = .Unavailable
        return result
    }
    result.index_generation = generation.generation
    parent: uuid.Identifier
    if value.animation_id_length > 0 {
        identity := string(value.animation_id[:value.animation_id_length])
        if !exercise_animation_exists(generation, identity) {
            result.status = .Missing_Animation
            return result
        }
        parent, _ = uuid.read(identity)
    }
    exercise_catalogue_copy_children(generation, parent, value, &result)
    result.status = .Ready
    result.more_available = u64(value.result_offset) + u64(result.returned_count) <
        u64(result.total_count)
    return result
}

// Preserve catalogue order while skipping rows outside the bounded result window.
exercise_catalogue_copy_children :: proc(
    generation: ^Content_Generation, parent: uuid.Identifier,
    request: Exercise_Query_Request, result: ^Exercise_Query_Result) {
    for record in generation.records[:generation.record_count] {
        if record.parent_stable_id != parent || record.node_kind != .Animation {
            continue
        }
        ordinal := result.total_count
        result.total_count += 1
        if ordinal < request.result_offset ||
           result.returned_count >= request.page_limit {
            continue
        }
        child := &result.children[result.returned_count]
        _ = uuid.to_string(record.stable_id, child.animation_id[:])
        name, _ := content_generation_text(generation, record.display_name)
        child.name_length = u16(copy(child.name[:], transmute([]u8)name))
        child.kind = record.node_kind
        result.returned_count += 1
    }
}
