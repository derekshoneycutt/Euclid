package content_model

import "core:fmt"
import "core:math"
import "core:unicode/utf8"

UI_FORMAT_OUTPUT_BYTE_CAPACITY :: 536
UI_FORMAT_TEXT_BYTE_CAPACITY :: 512

// Stable authored message IDs, deliberately independent of widgets and row order.
Content_Message_Id :: enum u16 {
    Invalid = 0,
    Navigation_Library = 1001,
    Gif_Save = 1002,
    Navigation_Settings = 1003,
    Animation_Default_Title = 1004,
    Presentation_Accessible_Label = 1005,
    Library_Tree_Accessible_Label = 1006,
    Context_Menu_Label = 1007,
    Context_Copy = 1008,
    Context_Select_All = 1009,
    Context_Paste = 1010,
    Terminal_Accessible_Label = 1011,
    Library_Search_Input = 1101,
    Library_Clear_Search = 1102,
    Library_Search_Status_Label = 1103,
    Library_Suggestion_Prompt = 1104,
    Library_Suggestion_Action_Fallback = 1105,
    Library_Suggestion_Action = 1106,
    Library_Status_Invalid = 1107,
    Library_Status_Searching = 1108,
    Library_Status_No_Matches = 1109,
    Library_Status_Match_Count = 1110,
    Library_Status_Match_Count_More = 1111,
    Settings_Display_Fps = 1201,
    Settings_Limit_Fps = 1202,
    Settings_Drawing_Sound = 1203,
    Settings_Simd_Available = 1204,
    Settings_Simd_Unavailable = 1205,
    Settings_Gpu_Dust_Available = 1206,
    Settings_Gpu_Dust_Unavailable = 1207,
    Settings_Maximum_Dust = 1208,
    Settings_Stats_Dust = 1209,
    Settings_Stats_Trail = 1210,
    Settings_Stats_Flicker = 1211,
    Settings_Stats_Animation_Entries = 1212,
    Fps_Overlay = 1213,
    Settings_Save_Saved = 1214,
    Settings_Save_Pending = 1215,
    Settings_Save_Saving = 1216,
    Settings_Save_Unavailable = 1217,
    Settings_Save_Failed = 1218,
    Settings_Reduce_Motion = 1219,
    Settings_System_Reduce_Motion = 1220,
    Gif_Output_Scale = 1301,
    Gif_Capture_Every = 1302,
    Gif_Playback_Timing = 1303,
    Gif_Timing_Animation = 1304,
    Gif_Timing_Recorded = 1305,
    Gif_Timing_Animation_Description = 1306,
    Gif_Timing_Recorded_Description = 1307,
    Gif_Downsample_Accessible = 1308,
    Gif_Saved_Path_Label = 1309,
    Gif_Saved_Path_Accessible = 1310,
    Gif_Output_Scale_Hundred = 1311,
    Gif_Output_Scale_Fifty = 1312,
    Gif_Output_Scale_Thirty_Three = 1313,
    Gif_Output_Scale_Twenty_Five = 1314,
    Gif_Cadence_Single = 1315,
    Gif_Cadence_Multiple = 1316,
    Gif_Action_Cancel = 1317,
    Gif_Action_Recording = 1318,
    Gif_Action_Saving = 1319,
    Gif_Status_Idle = 1320,
    Gif_Status_Armed = 1321,
    Gif_Status_Recording = 1322,
    Gif_Status_Saving = 1323,
    Gif_Status_Saved = 1324,
    Gif_Status_Error = 1325,
    Gif_Accessibility_Idle = 1326,
    Gif_Accessibility_Armed = 1327,
    Gif_Accessibility_Recording = 1328,
    Gif_Accessibility_Saving = 1329,
    Gif_Accessibility_Saved = 1330,
    Gif_Accessibility_Error = 1331,
    Gif_Error_Begin = 1332,
    Gif_Error_Finalize = 1333,
    Gif_Cancelled_During_Pause = 1334,
    Gif_Error_Submit_Frame = 1335,
    Gif_Cancelled_Window_Resize = 1336,
    Animation_Restart = 1401,
    Animation_Pause = 1402,
    Animation_Resume = 1403,
    Animation_Add_Favorite = 1404,
    Animation_Remove_Favorite = 1405,
}

// One native ID/key identity shared by admission and runtime lookup.
Content_Required_Message :: struct {
    native_id: u16,
    key: string,
}

CONTENT_SHIPPED_MESSAGE_COUNT :: 83
CONTENT_REQUIRED_MESSAGES :: [CONTENT_SHIPPED_MESSAGE_COUNT]Content_Required_Message{
    {1001, "ui.navigation.library"},
    {1002, "ui.gif.save"},
    {1003, "ui.navigation.settings"},
    {1004, "ui.animation.default_title"},
    {1005, "ui.presentation.accessible_label"},
    {1006, "ui.library.tree_accessible_label"},
    {1007, "ui.context_menu.label"},
    {1008, "ui.context_menu.copy"},
    {1009, "ui.context_menu.select_all"},
    {1010, "ui.context_menu.paste"},
    {1011, "ui.terminal.accessible_label"},
    {1101, "ui.library.search_input"},
    {1102, "ui.library.clear_search"},
    {1103, "ui.library.search_status_label"},
    {1104, "ui.library.suggestion_prompt"},
    {1105, "ui.library.suggestion_action_fallback"},
    {1106, "ui.library.suggestion_action"},
    {1107, "ui.library.status.invalid"},
    {1108, "ui.library.status.searching"},
    {1109, "ui.library.status.no_matches"},
    {1110, "ui.library.status.match_count"},
    {1111, "ui.library.status.match_count_more"},
    {1201, "ui.settings.display_fps"},
    {1202, "ui.settings.limit_fps"},
    {1203, "ui.settings.drawing_sound"},
    {1204, "ui.settings.simd_available"},
    {1205, "ui.settings.simd_unavailable"},
    {1206, "ui.settings.gpu_dust_available"},
    {1207, "ui.settings.gpu_dust_unavailable"},
    {1208, "ui.settings.maximum_dust"},
    {1209, "ui.settings.stats.dust"},
    {1210, "ui.settings.stats.trail"},
    {1211, "ui.settings.stats.flicker"},
    {1212, "ui.settings.stats.animation_entries"},
    {1213, "ui.fps.overlay"},
    {1214, "ui.settings.save.saved"},
    {1215, "ui.settings.save.pending"},
    {1216, "ui.settings.save.saving"},
    {1217, "ui.settings.save.unavailable"},
    {1218, "ui.settings.save.failed"},
    {1219, "ui.settings.reduce_motion"},
    {1220, "ui.settings.system_reduce_motion"},
    {1301, "ui.gif.output_scale"},
    {1302, "ui.gif.capture_every"},
    {1303, "ui.gif.playback_timing"},
    {1304, "ui.gif.timing.animation"},
    {1305, "ui.gif.timing.recorded"},
    {1306, "ui.gif.timing.animation_description"},
    {1307, "ui.gif.timing.recorded_description"},
    {1308, "ui.gif.downsample_accessible"},
    {1309, "ui.gif.saved_path.label"},
    {1310, "ui.gif.saved_path.accessible"},
    {1311, "ui.gif.output_scale.100"},
    {1312, "ui.gif.output_scale.50"},
    {1313, "ui.gif.output_scale.33"},
    {1314, "ui.gif.output_scale.25"},
    {1315, "ui.gif.cadence.single"},
    {1316, "ui.gif.cadence.multiple"},
    {1317, "ui.gif.action.cancel"},
    {1318, "ui.gif.action.recording"},
    {1319, "ui.gif.action.saving"},
    {1320, "ui.gif.status.idle"},
    {1321, "ui.gif.status.armed"},
    {1322, "ui.gif.status.recording"},
    {1323, "ui.gif.status.saving"},
    {1324, "ui.gif.status.saved"},
    {1325, "ui.gif.status.error"},
    {1326, "ui.gif.accessibility.idle"},
    {1327, "ui.gif.accessibility.armed"},
    {1328, "ui.gif.accessibility.recording"},
    {1329, "ui.gif.accessibility.saving"},
    {1330, "ui.gif.accessibility.saved"},
    {1331, "ui.gif.accessibility.error"},
    {1332, "ui.gif.error.begin"},
    {1333, "ui.gif.error.finalize"},
    {1334, "ui.gif.cancelled_during_pause"},
    {1335, "ui.gif.error.submit_frame"},
    {1336, "ui.gif.cancelled_window_resize"},
    {1401, "ui.animation.restart"},
    {1402, "ui.animation.pause"},
    {1403, "ui.animation.resume"},
    {1404, "ui.animation.add_favorite"},
    {1405, "ui.animation.remove_favorite"},
}

// Explicit formatting failure; no error is a successful English fallback.
Content_Message_Status :: enum {
    Ok,
    Missing_Key,
    Missing_Locale,
    Missing_Translation,
    Signature_Mismatch,
    Invalid_Template,
    Invalid_Argument,
    Output_Capacity,
    Invalid_State,
}

Content_Message_Value :: union {string, u32, i64, f32}

// Caller-owned named value; text is borrowed only for the duration of formatting.
Content_Format_Argument :: struct {
    name: string,
    value: Content_Message_Value,
}

// Generation-borrowed lookup result; never retain it past generation retirement.
Content_Message_View :: struct {
    message: ^Content_Message,
    template: string,
    ordinal: int,
}

// Bounded parser result shared by admission and defensive runtime formatting.
Content_Placeholder :: struct {
    name: string,
    next: int,
    closed: bool,
}

// Shared mutable state for one transactional template expansion pass.
Content_Message_Expand_State :: struct {
    arguments: []Content_Format_Argument,
    destination: []u8,
    count: ^int,
    seen: ^[2]bool,
}

// Current native consumer signature; an empty name denotes a static message.
Content_Message_Signature :: struct {
    name: string,
    kind: Content_Argument_Kind,
}

// Freeze native argument names and wire kinds independently of translated prose.
content_message_signature :: proc(id: Content_Message_Id) -> Content_Message_Signature {
    #partial switch id {
    case .Library_Suggestion_Action: return {"query", .Text}
    case .Library_Status_Match_Count, .Library_Status_Match_Count_More,
         .Gif_Cadence_Multiple:
        return {"count", .Uint32}
    case .Settings_Stats_Dust, .Settings_Stats_Trail, .Settings_Stats_Flicker,
         .Settings_Stats_Animation_Entries, .Gif_Status_Recording:
        return {"count", .Int64}
    case .Fps_Overlay: return {"fps", .Float32_One_Decimal}
    }
    return {}
}

// Resolve an ID to its required key and stable cache ordinal, not its database row.
content_message_identity :: proc(
    id: Content_Message_Id) -> (Content_Required_Message, int) {
    required := CONTENT_REQUIRED_MESSAGES
    for identity, ordinal in required {
        if identity.native_id == u16(id) {
            return identity, ordinal
        }
    }
    return {}, -1
}

// Borrow one exact ID/key translation from a complete sealed generation.
content_message_lookup :: proc(
    generation: ^Content_Generation, id: Content_Message_Id,
    locale := "en-US") -> (Content_Message_View, Content_Message_Status) {
    if generation == nil || !generation.initialized || !generation.sealed ||
       generation.generation == 0 || !generation.data.complete {
        return {}, .Invalid_State
    }
    identity, ordinal := content_message_identity(id)
    if ordinal < 0 {
        return {}, .Missing_Key
    }
    locale_index := content_message_locale_index(generation, locale)
    if locale_index < 0 {
        return {}, .Missing_Locale
    }
    for index in 0..<int(generation.data.message_count) {
        message := &generation.data.messages[index]
        key, status := content_generation_text(generation, message.key)
        if status != .Ok {
            return {}, .Invalid_State
        }
        if message.native_id == identity.native_id && key == identity.key {
            return content_message_translation(generation, message, index,
                locale_index, ordinal)
        }
    }
    return {}, .Missing_Key
}

// Locate an exact admitted locale without language detection or fallback.
content_message_locale_index :: proc(
    generation: ^Content_Generation, locale: string) -> int {
    for entry, index in generation.data.locales[:generation.data.locale_count] {
        tag, status := content_generation_text(generation, entry.tag)
        if status == .Ok && tag == locale {
            return index
        }
    }
    return -1
}

// Resolve a translation by admitted row references and preserve the native ordinal.
content_message_translation :: proc(
    generation: ^Content_Generation, message: ^Content_Message,
    index, locale_index: int,
    ordinal: int) -> (Content_Message_View, Content_Message_Status) {
    for translation in generation.data.translations[:generation.data.translation_count] {
        if int(translation.message_index) != index ||
           int(translation.locale_index) != locale_index {
            continue
        }
        template, status := content_generation_text(generation, translation.template)
        if status != .Ok {
            return {}, .Invalid_State
        }
        return {message, template, ordinal}, .Ok
    }
    return {}, .Missing_Translation
}

// Recognize the frozen ASCII identifier grammar used in named substitutions.
content_message_argument_name_valid :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > 32 || name[0] < 'a' || name[0] > 'z' {
        return false
    }
    for byte in transmute([]u8)name {
        if !(byte >= 'a' && byte <= 'z') && !(byte >= '0' && byte <= '9') &&
           byte != '_' {
            return false
        }
    }
    return true
}

// Parse one simple placeholder; escaped and nested braces are intentionally invalid.
content_message_placeholder :: proc(
    template: string, opening: int) -> Content_Placeholder {
    closing := opening + 1
    for closing < len(template) && template[closing] != '}' {
        if template[closing] == '{' {
            return {next = closing}
        }
        closing += 1
    }
    if closing == len(template) {
        return {next = closing}
    }
    name := template[opening + 1:closing]
    return {name, closing + 1, content_message_argument_name_valid(name)}
}

// Check caller names and types against the generation-owned declared signature.
content_message_validate_arguments :: proc(
    generation: ^Content_Generation, message: ^Content_Message,
    arguments: []Content_Format_Argument) -> Content_Message_Status {
    if len(arguments) != int(message.argument_count) || len(arguments) > 2 {
        return .Signature_Mismatch
    }
    for declared in message.arguments[:message.argument_count] {
        name, status := content_generation_text(generation, declared.name)
        if status != .Ok {
            return .Invalid_State
        }
        matches := 0
        for argument in arguments {
            if argument.name != name {
                continue
            }
            matches += 1
            validation := content_message_validate_value(declared.kind, argument.value)
            if validation != .Ok {
                return validation
            }
        }
        if matches != 1 {
            return .Signature_Mismatch
        }
    }
    return .Ok
}

// Enforce wire widths, bounded UTF-8 text, nonnegative counts, and finite FPS.
content_message_validate_value :: proc(
    kind: Content_Argument_Kind,
    value: Content_Message_Value) -> Content_Message_Status {
    if !content_message_kind_matches_value(kind, value) {
        return .Signature_Mismatch
    }
    switch item in value {
    case string:
        if len(item) > UI_FORMAT_TEXT_BYTE_CAPACITY || !utf8.valid_string(item) {
            return .Invalid_Argument
        }
    case i64:
        if item < 0 { return .Invalid_Argument }
    case f32:
        if math.is_nan(item) || math.is_inf(item) { return .Invalid_Argument }
    case u32:
    case:
        return .Invalid_Argument
    }
    return .Ok
}

// Enforce exact wire-kind compatibility before deeper value-specific checks.
content_message_kind_matches_value :: proc(
    kind: Content_Argument_Kind, value: Content_Message_Value) -> bool {
    switch item in value {
    case string: return kind == .Text
    case u32: return kind == .Uint32
    case i64: return kind == .Int64
    case f32: return kind == .Float32_One_Decimal
    }
    return false
}

// Render one already validated value into bounded scratch without an allocator.
content_message_value_text :: proc(
    value: Content_Message_Value, storage: []u8) -> string {
    switch item in value {
    case string: return item
    case u32: return fmt.bprintf(storage, "%d", item)
    case i64: return fmt.bprintf(storage, "%d", item)
    case f32: return fmt.bprintf(storage, "%.1f", item)
    }
    return ""
}

// Resolve a named caller value; absent or unknown substitutions remain errors.
content_message_substitution :: proc(
    name: string, arguments: []Content_Format_Argument,
    storage: []u8) -> (string, int) {
    for argument, index in arguments {
        if argument.name == name {
            return content_message_value_text(argument.value, storage), index
        }
    }
    return "", -1
}

// Append a whole literal/value or reject it without truncating the fixed scratch.
content_message_append :: proc(
    destination: []u8, count: ^int, text: string) -> bool {
    if len(text) > len(destination) - count^ {
        return false
    }
    copy(destination[count^:], text)
    count^ += len(text)
    return true
}

// Expand the frozen grammar transactionally, requiring every declared argument.
content_message_expand :: proc(
    template: string, arguments: []Content_Format_Argument,
    destination: []u8) -> (int, Content_Message_Status) {
    seen: [2]bool
    count, index := 0, 0
    state := Content_Message_Expand_State{
        arguments = arguments,
        destination = destination,
        count = &count,
        seen = &seen,
    }
    for index < len(template) {
        status, next := content_message_expand_segment(template, index, &state)
        if status != .Ok {
            return 0, status
        }
        index = next
        if index == len(template) {
            break
        }
    }
    for used in seen[:len(arguments)] {
        if !used { return 0, .Invalid_Template }
    }
    return count, .Ok
}

// Expand one template segment and optional following placeholder from the current index.
content_message_expand_segment :: proc(
    template: string, cursor: int,
    state: ^Content_Message_Expand_State) -> (Content_Message_Status, int) {
    index := cursor
    if template[index] == '}' {
        return .Invalid_Template, index
    }
    start := index
    for index < len(template) && template[index] != '{' && template[index] != '}' {
        index += 1
    }
    if !content_message_append(
        state.destination, state.count, template[start:index]) {
        return .Output_Capacity, index
    }
    if index == len(template) {
        return .Ok, index
    }
    if template[index] == '}' {
        return .Invalid_Template, index
    }
    return content_message_expand_placeholder(template, index, state)
}

// Expand one validated placeholder and record the matched named argument.
content_message_expand_placeholder :: proc(
    template: string, opening: int,
    state: ^Content_Message_Expand_State) -> (Content_Message_Status, int) {
    placeholder := content_message_placeholder(template, opening)
    numeric_storage: [64]u8
    value, argument_index := content_message_substitution(
        placeholder.name, state.arguments, numeric_storage[:])
    if !placeholder.closed || argument_index < 0 {
        return .Invalid_Template, opening
    }
    if !content_message_append(state.destination, state.count, value) {
        return .Output_Capacity, opening
    }
    state.seen[argument_index] = true
    return .Ok, placeholder.next
}

// Format into caller-owned storage only on success; failed calls preserve its bytes.
content_message_format :: proc(
    generation: ^Content_Generation, id: Content_Message_Id,
    arguments: []Content_Format_Argument, destination: []u8,
    locale := "en-US") -> (string, Content_Message_Status) {
    view, status := content_message_lookup(generation, id, locale)
    if status != .Ok { return "", status }
    status = content_message_validate_arguments(generation, view.message, arguments)
    if status != .Ok { return "", status }
    scratch: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    count, expanded := content_message_expand(view.template, arguments, scratch[:])
    if expanded != .Ok { return "", expanded }
    if count > len(destination) { return "", .Output_Capacity }
    copy(destination, scratch[:count])
    return string(destination[:count]), .Ok
}
