package content

import contentdata "../../core/content"

import "core:encoding/uuid"
import "core:log"

// One parsed template placeholder and the scan position after it.
Content_Template_Placeholder :: struct {
    name: string,
    next: int,
    closed: bool,
}

// Admit a generation only after every normalized table and relation is complete.
content_admission_validate_complete :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    if !content_admission_loaded_counts_match(database, generation) ||
       !content_admission_validate_locales(generation) ||
       !content_admission_validate_messages(generation) ||
       !content_admission_validate_translations(generation) ||
       !content_admission_validate_catalogue(generation) ||
       !content_admission_validate_subjects(generation) ||
       !content_admission_validate_editions(generation) ||
       !content_admission_validate_availability(generation) ||
       !content_admission_validate_projections(generation) {
        return false
    }
    generation.data.complete = true
    return true
}

// Compare materialized rows against every declared normalized table cardinality.
content_admission_loaded_counts_match :: proc(
    database: ^Content_Database, generation: ^Content_Generation) -> bool {
    data := &generation.data
    counts := database.expected_table_counts
    return int(data.locale_count) == int(counts[2]) &&
        int(data.message_count) == int(counts[3]) &&
        int(data.argument_count) == int(counts[4]) &&
        int(data.translation_count) == int(counts[5]) &&
        int(data.subject_count) == int(counts[6]) &&
        int(generation.record_count) == int(counts[7]) &&
        int(data.name_count) == int(counts[8]) &&
        int(data.edition_count) == int(counts[9]) &&
        int(data.availability_count) == int(counts[10]) &&
        int(data.projection_count) == int(counts[11])
}

// Require the only shipped locale to be the default en-US locale.
content_admission_validate_locales :: proc(generation: ^Content_Generation) -> bool {
    if generation.data.locale_count != 1 {
        return false
    }
    locale := generation.data.locales[0]
    return locale.is_default &&
        content_admission_ref_equals(generation, locale.tag, "en-US")
}

// Validate exact required ID/key coverage, uniqueness, and signature consistency.
content_admission_validate_messages :: proc(generation: ^Content_Generation) -> bool {
    if generation.data.message_count != CONTENT_SHIPPED_MESSAGE_COUNT {
        return false
    }
    for index in 0..<int(generation.data.message_count) {
        message := &generation.data.messages[index]
        key := content_admission_builder_text(generation, message.key)
        if !content_admission_message_identity_is_shipped(message.native_id, key) ||
           !content_admission_message_signature_is_valid(generation, message) ||
           !content_admission_message_matches_native_signature(generation, message) {
            return false
        }
        for prior in 0..<index {
            previous := &generation.data.messages[prior]
            if previous.native_id == message.native_id ||
               content_admission_ref_equals(generation, previous.key, key) {
                return false
            }
        }
    }
    return true
}

// Native consumers require their frozen signatures, while translated prose remains authored.
content_admission_message_matches_native_signature :: proc(
    generation: ^Content_Generation, message: ^contentdata.Content_Message) -> bool {
    signature := contentdata.content_message_signature(
        contentdata.Content_Message_Id(message.native_id))
    expected := len(signature.name) > 0 ? 1 : 0
    if int(message.argument_count) != expected {
        log.errorf(
            "content_native_signature_rejected id=%d expected_count=%d actual_count=%d",
            message.native_id, expected, message.argument_count)
        return false
    }
    if expected == 0 {
        return true
    }
    argument := message.arguments[0]
    valid := argument.kind == signature.kind &&
        content_admission_ref_equals(generation, argument.name, signature.name)
    if !valid {
        log.errorf(
            "content_native_signature_rejected id=%d expected_name=%s expected_kind=%v",
            message.native_id, signature.name, signature.kind)
    }
    return valid
}

// Require a bounded, self-consistent declared signature with identifier names.
content_admission_message_signature_is_valid :: proc(
    generation: ^Content_Generation,
    message: ^contentdata.Content_Message) -> bool {
    if int(message.argument_count) > len(message.arguments) {
        return false
    }
    for index in 0..<int(message.argument_count) {
        name := content_admission_builder_text(generation, message.arguments[index].name)
        if !content_admission_argument_name_is_valid(name) {
            return false
        }
    }
    return content_admission_message_arguments_are_unique(generation, message)
}

// Accept lowercase ASCII identifier names matching the placeholder grammar.
content_admission_argument_name_is_valid :: proc(name: string) -> bool {
    return contentdata.content_message_argument_name_valid(name)
}

// Reject duplicate names in one bounded message signature.
content_admission_message_arguments_are_unique :: proc(
    generation: ^Content_Generation, message: ^contentdata.Content_Message) -> bool {
    for index in 0..<int(message.argument_count) {
        for prior in 0..<index {
            if content_admission_builder_text(
                generation, message.arguments[index].name) ==
               content_admission_builder_text(
                   generation, message.arguments[prior].name) {
                return false
            }
        }
    }
    return true
}

// Require one signature-exact translation for every shipped message and locale.
content_admission_validate_translations :: proc(
    generation: ^Content_Generation) -> bool {
    data := &generation.data
    if data.translation_count != data.message_count * data.locale_count {
        return false
    }
    for translation_index in 0..<int(data.translation_count) {
        translation := &data.translations[translation_index]
        message := &data.messages[translation.message_index]
        template := content_admission_builder_text(generation, translation.template)
        if !content_admission_template_matches_signature(
            generation, template, message) {
            log.errorf("content_template_rejected id=%d template=%s",
                message.native_id, template)
            return false
        }
        for prior in 0..<translation_index {
            previous := &data.translations[prior]
            if previous.locale_index == translation.locale_index &&
               previous.message_index == translation.message_index {
                return false
            }
        }
    }
    return true
}

// Match simple named placeholders exactly to one admitted message signature.
content_admission_template_matches_signature :: proc(
    generation: ^Content_Generation, template: string,
    message: ^contentdata.Content_Message) -> bool {
    seen: [2]bool
    index := 0
    for index < len(template) {
        if template[index] == '}' {
            return false
        }
        if template[index] != '{' {
            index += 1
            continue
        }
        placeholder := content_admission_template_placeholder(template, index)
        match := content_admission_argument_index(generation, message, placeholder.name)
        if !placeholder.closed || match < 0 {
            return false
        }
        seen[match] = true
        index = placeholder.next
    }
    for argument_index in 0..<int(message.argument_count) {
        if !seen[argument_index] {
            return false
        }
    }
    return true
}

// Return one brace-delimited placeholder name and the index after its closing brace.
content_admission_template_placeholder :: proc(
    template: string, opening: int) -> Content_Template_Placeholder {
    placeholder := contentdata.content_message_placeholder(template, opening)
    return {placeholder.name, placeholder.next, placeholder.closed}
}

// Return the signature position matching one exact placeholder name.
content_admission_argument_index :: proc(
    generation: ^Content_Generation, message: ^contentdata.Content_Message,
    name: string) -> int {
    if !content_admission_argument_name_is_valid(name) {
        return -1
    }
    for index in 0..<int(message.argument_count) {
        if content_admission_ref_equals(
            generation, message.arguments[index].name, name) {
            return index
        }
    }
    return -1
}

// Validate exact subject topology and install each locale's default tree label.
content_admission_validate_catalogue :: proc(
    generation: ^Content_Generation) -> bool {
    if generation.record_count != CATALOG_EXPECTED_RECORD_COUNT ||
       generation.data.name_count !=
           generation.record_count * generation.data.locale_count ||
       !content_admission_validate_name_coverage(generation) ||
       !content_admission_validate_sibling_names(generation) {
        return false
    }
    return content_admission_install_default_names(generation)
}

// Require one and only one localized label for every node and locale.
content_admission_validate_name_coverage :: proc(
    generation: ^Content_Generation) -> bool {
    for name_index in 0..<int(generation.data.name_count) {
        name := &generation.data.names[name_index]
        for prior in 0..<name_index {
            previous := &generation.data.names[prior]
            if previous.record_index == name.record_index &&
               previous.locale_index == name.locale_index {
                return false
            }
        }
    }
    for record_index in 0..<int(generation.record_count) {
        for locale_index in 0..<int(generation.data.locale_count) {
            if content_admission_find_name(
                generation, record_index, locale_index) < 0 {
                return false
            }
        }
    }
    return true
}

// Reject duplicate display labels among siblings for each locale.
content_admission_validate_sibling_names :: proc(
    generation: ^Content_Generation) -> bool {
    for left_index in 0..<int(generation.data.name_count) {
        left := &generation.data.names[left_index]
        left_record := &generation.records[left.record_index]
        for right_index in left_index + 1..<int(generation.data.name_count) {
            right := &generation.data.names[right_index]
            right_record := &generation.records[right.record_index]
            if left.locale_index == right.locale_index &&
               content_admission_records_share_parent(left_record, right_record) &&
               content_admission_builder_text(
                   generation, left.display_name) ==
               content_admission_builder_text(
                   generation, right.display_name) {
                return false
            }
        }
    }
    return true
}

// Compare nullable parent identities without conflating root nodes.
content_admission_records_share_parent :: proc(
    left, right: ^Catalog_Record) -> bool {
    return left.has_parent == right.has_parent &&
        (!left.has_parent || left.parent_stable_id == right.parent_stable_id)
}

// Bind each catalog record's runtime display name to the default locale row.
content_admission_install_default_names :: proc(
    generation: ^Content_Generation) -> bool {
    default_locale := content_admission_default_locale_index(generation)
    if default_locale < 0 {
        return false
    }
    for record_index in 0..<int(generation.record_count) {
        name_index := content_admission_find_name(
            generation, record_index, default_locale)
        if name_index < 0 {
            return false
        }
        generation.records[record_index].display_name =
            generation.data.names[name_index].display_name
    }
    return true
}

// Validate exact catalogue-node coverage plus the reserved null adapter.
content_admission_validate_subjects :: proc(
    generation: ^Content_Generation) -> bool {
    if generation.data.subject_count != contentdata.CONTENT_SUBJECT_CAPACITY {
        return false
    }
    zero_id: uuid.Identifier
    if content_admission_find_subject(generation, zero_id) < 0 {
        return false
    }
    for index in 0..<int(generation.data.subject_count) {
        subject := generation.data.subjects[index]
        if content_admission_find_subject_before(generation, subject, index) {
            return false
        }
        if subject != zero_id && content_admission_find_catalog(generation, subject) < 0 {
            return false
        }
    }
    for index in 0..<int(generation.record_count) {
        if content_admission_find_subject(
            generation, generation.records[index].stable_id) < 0 {
            return false
        }
    }
    return true
}

// Detect a subject UUID repeated earlier in the bounded declaration table.
content_admission_find_subject_before :: proc(
    generation: ^Content_Generation, identifier: uuid.Identifier,
    end_index: int) -> bool {
    for index in 0..<end_index {
        if generation.data.subjects[index] == identifier {
            return true
        }
    }
    return false
}

// Validate unique edition IDs and unique display names.
content_admission_validate_editions :: proc(
    generation: ^Content_Generation) -> bool {
    if generation.data.edition_count == 0 {
        return false
    }
    for index in 0..<int(generation.data.edition_count) {
        edition := &generation.data.editions[index]
        for prior in 0..<index {
            previous := &generation.data.editions[prior]
            if content_admission_builder_text(generation, previous.id) ==
                   content_admission_builder_text(generation, edition.id) ||
               content_admission_builder_text(generation, previous.name) ==
                   content_admission_builder_text(generation, edition.name) {
                return false
            }
        }
    }
    return true
}

// Require available editions and exactly one default for each subject/locale.
content_admission_validate_availability :: proc(
    generation: ^Content_Generation) -> bool {
    for subject_index in 0..<int(generation.data.subject_count) {
        for locale_index in 0..<int(generation.data.locale_count) {
            available, defaults := content_admission_availability_counts(
                generation, subject_index, locale_index)
            if available == 0 || defaults != 1 {
                return false
            }
        }
    }
    return content_admission_availability_is_unique(generation)
}

// Count available editions and default selections for one subject/locale.
content_admission_availability_counts :: proc(
    generation: ^Content_Generation,
    subject_index, locale_index: int) -> (int, int) {
    available, defaults := 0, 0
    for index in 0..<int(generation.data.availability_count) {
        row := generation.data.availability[index]
        if row.subject_index == u16(subject_index) &&
           row.locale_index == u16(locale_index) {
            available += 1
            defaults += int(row.is_default)
        }
    }
    return available, defaults
}

// Reject duplicate subject/locale/edition tuples.
content_admission_availability_is_unique :: proc(
    generation: ^Content_Generation) -> bool {
    for index in 0..<int(generation.data.availability_count) {
        row := generation.data.availability[index]
        for prior in 0..<index {
            previous := generation.data.availability[prior]
            if row.subject_index == previous.subject_index &&
               row.locale_index == previous.locale_index &&
               row.edition_index == previous.edition_index {
                return false
            }
        }
    }
    return true
}

// Require each search row to project the default name and available edition.
content_admission_validate_projections :: proc(
    generation: ^Content_Generation) -> bool {
    if generation.data.projection_count != generation.record_count {
        return false
    }
    default_locale := content_admission_default_locale_index(generation)
    for index in 0..<int(generation.data.projection_count) {
        projection := &generation.data.projections[index]
        if projection.projection_id != u32(index + 1) ||
           projection.record_index >= generation.record_count ||
           int(projection.locale_index) != default_locale ||
           !content_admission_projection_matches_default(generation, projection) {
            return false
        }
        if !content_admission_projection_is_unique(generation, projection, index) {
            return false
        }
    }
    return true
}

// Validate projection's localized label and default availability correspondence.
content_admission_projection_matches_default :: proc(
    generation: ^Content_Generation,
    projection: ^contentdata.Content_Search_Projection) -> bool {
    record := &generation.records[projection.record_index]
    subject_index := content_admission_find_subject(generation, record.stable_id)
    name_index := content_admission_find_name(
        generation, int(projection.record_index), int(projection.locale_index))
    if subject_index < 0 || name_index < 0 ||
       content_admission_builder_text(generation, projection.display_name) !=
           content_admission_builder_text(
               generation, generation.data.names[name_index].display_name) {
        return false
    }
    return content_admission_has_default_availability(
        generation, subject_index, int(projection.locale_index),
        int(projection.edition_index))
}

// Match one projection edition to the single default availability row.
content_admission_has_default_availability :: proc(
    generation: ^Content_Generation, subject_index, locale_index,
    edition_index: int) -> bool {
    for index in 0..<int(generation.data.availability_count) {
        row := generation.data.availability[index]
        if int(row.subject_index) == subject_index &&
           int(row.locale_index) == locale_index && row.is_default &&
           int(row.edition_index) == edition_index {
            return true
        }
    }
    return false
}

// Prevent two default-locale search documents for the same catalogue node.
content_admission_projection_is_unique :: proc(
    generation: ^Content_Generation,
    projection: ^contentdata.Content_Search_Projection, end_index: int) -> bool {
    for index in 0..<end_index {
        if generation.data.projections[index].record_index == projection.record_index {
            return false
        }
    }
    return true
}

// Locate one localized label by its compact topology and locale indexes.
content_admission_find_name :: proc(
    generation: ^Content_Generation, record_index, locale_index: int) -> int {
    for index in 0..<int(generation.data.name_count) {
        row := generation.data.names[index]
        if int(row.record_index) == record_index &&
           int(row.locale_index) == locale_index {
            return index
        }
    }
    return -1
}

// Return the authored default locale index or reject ambiguous metadata.
content_admission_default_locale_index :: proc(
    generation: ^Content_Generation) -> int {
    result := -1
    for index in 0..<int(generation.data.locale_count) {
        if generation.data.locales[index].is_default {
            if result >= 0 {
                return -1
            }
            result = index
        }
    }
    return result
}
