package content_model

import "core:encoding/uuid"

// Fixed copy-out ABI; lengths count UTF-8 bytes without terminators.
Animation_Content_Specification :: struct {
    application_locale: [35]u8,
    application_locale_length: u16,
    edition_id: [64]u8,
    edition_id_length: u16,
    edition_name: [256]u8,
    edition_name_length: u16,
    edition_text_language: [35]u8,
    edition_text_language_length: u16,
    selection_revision: u64,
    animation_identity: uuid.Identifier,
    content_generation_identity: u64,
    runtime_generation_identity: u64,
}

#assert(size_of(Animation_Content_Specification) == 440)
#assert(offset_of(Animation_Content_Specification, selection_revision) == 400)
#assert(offset_of(Animation_Content_Specification, animation_identity) == 408)
#assert(offset_of(Animation_Content_Specification, content_generation_identity) == 424)
#assert(offset_of(Animation_Content_Specification, runtime_generation_identity) == 432)

// Stable query outcomes, independent of the general bridge status namespace.
Animation_Content_Status :: enum u32 {
    Ok = 0,
    Missing_Invocation_Context = 1,
    Identity_Mismatch = 2,
    Missing_Default = 3,
    Stale_Generation = 4,
    Invalid_Output = 5,
}

// Find the admitted default edition for the declared default locale and subject.
animation_content_default :: proc(
    generation: ^Content_Generation, subject: uuid.Identifier) ->
        (Content_Availability, bool) {
    for binding in generation^.data.availability[:generation^.data.availability_count] {
        if binding.is_default &&
            generation^.data.subjects[binding.subject_index] == subject &&
            generation^.data.locales[binding.locale_index].is_default {
            return binding, true
        }
    }
    return {}, false
}

// Copy admitted packed text into fixed storage, rejecting malformed references or bounds.
animation_content_copy_text :: proc(
    generation: ^Content_Generation, reference: Content_Text_Ref,
    destination: []u8, length: ^u16) -> bool {
    text, status := content_generation_text(generation, reference)
    if status != .Ok || len(text) == 0 || len(text) > len(destination) {
        return false
    }
    copy(destination, transmute([]u8)text)
    length^ = u16(len(text))
    return true
}

// Fill the four owned text fields from one validated availability row.
animation_content_copy_binding :: proc(
    generation: ^Content_Generation, binding: Content_Availability,
    result: ^Animation_Content_Specification) -> bool {
    edition := generation^.data.editions[binding.edition_index]
    return animation_content_copy_text(generation,
        generation^.data.locales[binding.locale_index].tag,
        result^.application_locale[:], &result^.application_locale_length) &&
        animation_content_copy_text(generation, edition.id,
            result^.edition_id[:], &result^.edition_id_length) &&
        animation_content_copy_text(generation, edition.name,
            result^.edition_name[:], &result^.edition_name_length) &&
        animation_content_copy_text(generation, edition.language,
            result^.edition_text_language[:], &result^.edition_text_language_length)
}

// Compare effective selection only; storage, runtime, and animation identity are orthogonal.
animation_content_same_selection :: proc(
    first, second: ^Animation_Content_Specification) -> bool {
    return first^.application_locale == second^.application_locale &&
        first^.application_locale_length == second^.application_locale_length &&
        first^.edition_id == second^.edition_id &&
        first^.edition_id_length == second^.edition_id_length
}

// Resolve one initial specification without retaining any generation-owned pointer.
resolve_animation_content_specification :: proc(
    generation: ^Content_Generation, subject: uuid.Identifier,
    runtime_generation: u64, previous: ^Animation_Content_Specification,
    output: ^Animation_Content_Specification) -> Animation_Content_Status {
    if output == nil {
        return .Invalid_Output
    }
    if generation == nil || !generation^.sealed || !generation^.data.complete ||
        generation^.generation == 0 {
        return .Stale_Generation
    }
    binding, found := animation_content_default(generation, subject)
    if !found {
        return .Missing_Default
    }
    result := Animation_Content_Specification{
        selection_revision = 1,
        animation_identity = subject,
        content_generation_identity = generation^.generation,
        runtime_generation_identity = runtime_generation,
    }
    if !animation_content_copy_binding(generation, binding, &result) {
        return .Missing_Default
    }
    if previous != nil && previous^.selection_revision > 0 {
        result.selection_revision = previous^.selection_revision
        if !animation_content_same_selection(previous, &result) {
            if result.selection_revision == max(u64) {
                return .Stale_Generation
            }
            result.selection_revision += 1
        }
    }
    output^ = result
    return .Ok
}
