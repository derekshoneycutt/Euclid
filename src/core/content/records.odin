package content_model

import "core:encoding/uuid"

CONTENT_LOCALE_CAPACITY :: 4
CONTENT_MESSAGE_CAPACITY :: 80
CONTENT_ARGUMENT_CAPACITY :: 32
CONTENT_TRANSLATION_CAPACITY :: 320
CONTENT_SUBJECT_CAPACITY :: 139
CONTENT_NAME_CAPACITY :: 552
CONTENT_EDITION_CAPACITY :: 8
CONTENT_AVAILABILITY_CAPACITY :: 2224

// Wire-compatible argument kinds; formatting is a later display-owned concern.
Content_Argument_Kind :: enum u8 {
    Text = 1,
    Uint32 = 2,
    Int64 = 3,
    Float32_One_Decimal = 4,
}

// Locale identity and authored default, independent of edition text language.
Content_Locale :: struct {
    tag: Content_Text_Ref,
    is_default: bool,
}

// Stable UI identity and its bounded, ordinal-preserving signature.
Content_Message :: struct {
    native_id: u16,
    key: Content_Text_Ref,
    developer_context: Content_Text_Ref,
    argument_count: u8,
    arguments: [2]Content_Argument,
}

// Named argument with an admitted wire kind and no borrowed string pointer.
Content_Argument :: struct {
    name: Content_Text_Ref,
    kind: Content_Argument_Kind,
}

// Locale-specific template resolved against one admitted message.
Content_Translation :: struct {
    locale_index: u16,
    message_index: u16,
    template: Content_Text_Ref,
}

// Locale-scoped catalogue name resolved against a stable topology row.
Content_Name :: struct {
    locale_index: u16,
    record_index: u16,
    display_name: Content_Text_Ref,
}

// Ordinary edition metadata for translated and original authored content alike.
Content_Edition :: struct {
    id: Content_Text_Ref,
    name: Content_Text_Ref,
    language: Content_Text_Ref,
    description: Content_Text_Ref,
}

// Available edition for an invocable subject, including the reserved null UUID.
Content_Availability :: struct {
    subject_index: u16,
    locale_index: u16,
    edition_index: u16,
    is_default: bool,
}

// Search-facing facts admitted with names and availability, not independently.
Content_Search_Projection :: struct {
    projection_id: u32,
    record_index: u16,
    locale_index: u16,
    edition_index: u16,
    display_name: Content_Text_Ref,
    hierarchy_path: Content_Text_Ref,
    semantic_text: Content_Text_Ref,
    aliases: Content_Text_Ref,
}

// Fixed-capacity native projections sharing the generation's packed text owner.
Content_Records :: struct {
    locale_count: u16,
    locales: [CONTENT_LOCALE_CAPACITY]Content_Locale,
    message_count: u16,
    messages: [CONTENT_MESSAGE_CAPACITY]Content_Message,
    argument_count: u16,
    translation_count: u16,
    translations: [CONTENT_TRANSLATION_CAPACITY]Content_Translation,
    subject_count: u16,
    subjects: [CONTENT_SUBJECT_CAPACITY]uuid.Identifier,
    name_count: u16,
    names: [CONTENT_NAME_CAPACITY]Content_Name,
    edition_count: u16,
    editions: [CONTENT_EDITION_CAPACITY]Content_Edition,
    availability_count: u16,
    availability: [CONTENT_AVAILABILITY_CAPACITY]Content_Availability,
    projection_count: u16,
    projections: [CATALOG_RECORD_CAPACITY]Content_Search_Projection,
    complete: bool,
}
