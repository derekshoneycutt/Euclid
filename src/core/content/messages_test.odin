#+test
package content_model

import "core:fmt"
import "core:math"
import "core:mem"
import "core:testing"
import storage_pkg "../storage"

// Frozen current-output fixtures with positional identity matching.
CONTENT_MESSAGE_TEST_TEMPLATES :: [CONTENT_SHIPPED_MESSAGE_COUNT]string{
    "Library", "Save GIF", "Settings", "Animation", "Presentation", "Animation library",
    "Context menu", "Copy", "Select All", "Paste", "Terminal",
    "History search: ", "?: help   Enter: recall   Esc: cancel",
    "Enlarge Terminal to explore history. Esc: cancel",
    "Searching history...", "No matching history",
    "Terminal history unavailable", "History search failed",
    "History capacity exceeded", "Loaded history",
    "History source preview", "Loading source...", "Source preview failed",
    "Source exceeds preview capacity", "now", "{count}s", "{count}m",
    "{count}h", "{count}d",
    "History search: words match source; spaces require all words. Semicolons separate conditions.",
    "Regexes use PCRE2, e.g. /(?i)Foo; no closing slash is needed. Inline flags can override regex case behavior.",
    "Up/Down or Ctrl+P/N: select. Enter recalls exact source into the draft; it never runs the entry.",
    "??: details   Up/Down: scroll   Esc: restore search",
    "History help: enlarge Terminal to read syntax. Esc: restore search. Enter does nothing.",
    "Malformed regex skipped; ?? explains syntax. No remaining conditions browses all history.",
    "Match emphasis unavailable (range/resource limit or stale source); recall is unchanged.",
    "Search resource or regex execution limit reached; simplify the query.",
    "History database search failed.",
    "History search cancelled.",
    "Invalid history query or query limit exceeded.",
    "History search help",
    "=text: exact substring   !text: exclude   /pattern: regex   `abbr: initialism   ~text: fuzzy",
    "julia>, help>, pkg>, shell>: modes. Multiple modes form a union, then combine with text conditions.",
    "Overlines mark positive matches without changing syntax faces. Exclusions and modes have no source emphasis.",
    "?: help   ??: details   Esc: restore search   Enter: no action in help. Edit the query to search again.",
    "Smart case: uppercase in an ordinary semicolon segment makes all its words case-sensitive; otherwise they ignore case.",
    "Escape semicolons with \\; e.g. =a\\;b. Other backslashes are preserved, including regex escapes such as /\\d+.",
    "Malformed regex conditions are skipped. No effective conditions browses all history. Memory/execution failures are errors.",
    "~fb matches with gaps (fuzzy); `fb follows word/camel boundaries (initialism), e.g. fooBar.",
    "PageUp/PageDown or Alt+V/Ctrl+V: adjacent page. Alt+Shift+< / >: oldest/newest.",
    "Alt+PageUp/PageDown or preview wheel: scroll source. In help, Up/Down, PageUp/PageDown and wheel scroll help.",
    "Limits: 1024 query UTF-8 bytes, 64 conditions, 256 ranges per page or preview. Source stays readable if emphasis cannot fit.",
    "Equal distinct submissions stay separate. Linked saved/session copies appear once. Recall preserves original source and mode.",
    "Search animations", "Clear search", "Library search status", "Did you mean...",
    "Use suggested search", "Use suggested search: {query}", "Search query is invalid",
    "Searching animations", "No matching animations", "Matching animations: {count}",
    "Matching animations: {count} or more", "Actions for {name}", "Move Up", "Move Down",
    "Unicode completion: {symbol}. Press Right Arrow to insert; Escape to dismiss.",
    "Library name", "Create collection", "New Collection",
    "Delete collection", "Confirm delete",
    "Display FPS", "Limit FPS",
    "Enable Drawing Sound", "Use SIMD Projection", "Use SIMD Projection (Unavailable)",
    "GPU Dust Instancing", "GPU Dust Instancing (Unavailable)", "Maximum Dust particles",
    "Dust particles Rendered: {count}", "Trail particles Rendered: {count}",
    "Flicker particles Rendered: {count}", "Julia animation entries added: {count}",
    "FPS {fps}", "User data saved", "User data not saved yet", "Saving user data...",
    "User-data storage unavailable", "User data could not be saved",
    "Reduce interface motion", "System requests reduced motion",
    "UI Dust particles: {count}",
    "Peaks per 5-second interval.",
    "Increased contrast", "System requests increased contrast",
    "Text size", "Accessibility", "Particles", "Other Settings",
    "History", "Persist Terminal History", "Delete Terminal History",
    "Confirm Delete",
    "Confirmation required; activate again to delete Terminal history.",
    "Deleting Terminal history...", "Terminal history deleted.",
    "Terminal history could not be deleted.",
    "Animation scale",
    "Scales animation ink after viewport fitting; 100% preserves authored sizing.",
    "100% (Default)", "Monochrome", "Focus follows mouse hover",
    "Move keyboard focus as the pointer moves. Hover does not activate controls or change input carets.",
    "Control size",
    "Scales interface controls and pointer targets without changing text or animation geometry.",
    "Show magnifier",
    "Magnifies a view of the completed frame near the pointer. It does not change hit targets.",
    "Lock magnifier to text input",
    "Shows the magnifier only at a visible focused text caret. It hides when no eligible input is focused.",
    "Enable particle effects", "Open animations at their completed figure",
    "Turning this off clears all particles and makes geometry and text immediately readable. Pause holds construction, not dust.",
    "Applies to the next animation you select. Play disperses its completed figure and starts construction at your remembered speed.",
    "Output scale", "Capture every", "Playback timing", "Animation",
    "Recorded", "Use animation timing", "Use recorded timing", "Downsample", "Path",
    "Saved GIF path", "100%", "50%", "33%", "25%", "frame", "{count} frames",
    "Cancel GIF", "Recording...", "Saving...", "Status: Idle", "Status: Armed",
    "Status: Recording ({count} frames)", "Status: Saving", "Status: Saved",
    "Status: Error", "GIF capture idle", "GIF capture armed", "GIF capture recording",
    "GIF capture saving", "GIF capture saved", "GIF capture error",
    "Error: failed to begin GIF capture session.", "Error: failed to finalize GIF file.",
    "Canceled: refresh during pause interrupts GIF capture.",
    "Error: failed to submit GIF frame.", "Window resized; GIF capture cancelled.",
    "Restart animation", "Pause animation", "Resume animation",
    "Add to Favorites", "Remove from Favorites", "Add to collections",
    "Hide animation controls", "Show animation controls",
    "Playback speed: 1x. Change to 2x", "Playback speed: 2x. Change to 4x",
    "Playback speed: 4x. Change to 1x", "Playback speed: 1x. Locked during GIF capture",
    "Show completed figure", "Completed figure", "Play animation from beginning",
    "Could not show completed figure",
    "Sharing", "Save PNG", "Save the current animation frame.",
    "Status: Idle", "Status: Saving", "Status: Saved",
    "Could not save PNG.", "Available after GIF saving finishes.", "Saved PNG path",
}

// Build a complete message fixture with a stable arena owner for consumer tests.
content_message_test_generation :: proc(t: ^testing.T) -> ^Content_Generation {
    generation := new(Content_Generation, context.allocator)
    testing.expect_value(t, content_generation_init(generation),
        Content_Generation_Status.Ok)
    _ = content_generation_test_build(t, generation, 17, true)
    content_generation_test_append_text(t, generation, "en-US", 35,
        &generation.data.locales[0].tag)
    generation.data.locales[0].is_default = true
    generation.data.locale_count = 1
    identities := CONTENT_REQUIRED_MESSAGES
    templates := CONTENT_MESSAGE_TEST_TEMPLATES
    for identity, index in identities {
        content_message_test_append(t, generation, identity, index, templates[index])
    }
    generation.data.message_count = CONTENT_SHIPPED_MESSAGE_COUNT
    generation.data.translation_count = CONTENT_SHIPPED_MESSAGE_COUNT
    generation.data.complete = true
    testing.expect_value(t, content_generation_seal(generation),
        Content_Generation_Status.Ok)
    return generation
}

// Append one independently frozen template and its current native argument signature.
content_message_test_append :: proc(
    t: ^testing.T, generation: ^Content_Generation,
    identity: Content_Required_Message, index: int, template: string) {
    message := &generation.data.messages[index]
    message.native_id = identity.native_id
    content_generation_test_append_text(t, generation, identity.key, 64, &message.key)
    name, kind := content_message_test_signature(Content_Message_Id(identity.native_id))
    if len(name) > 0 {
        message.argument_count = 1
        generation.data.argument_count += 1
        message.arguments[0].kind = kind
        content_generation_test_append_text(t, generation, name, 32,
            &message.arguments[0].name)
    }
    translation := &generation.data.translations[index]
    translation.message_index = u16(index)
    content_generation_test_append_text(t, generation, template, 128,
        &translation.template)
}

// Freeze dynamic consumers' named kinds separately from authored templates.
content_message_test_signature :: proc(
    id: Content_Message_Id) -> (string, Content_Argument_Kind) {
    #partial switch id {
    case .Library_Suggestion_Action:
        return "query", .Text
    case .Library_Actions_For:
        return "name", .Text
    case .Library_Unicode_Completion:
        return "symbol", .Text
    case .Library_Status_Match_Count, .Library_Status_Match_Count_More,
         .Gif_Cadence_Multiple:
        return "count", .Uint32
    case .Settings_Stats_Dust, .Settings_Stats_Trail, .Settings_Stats_Flicker,
         .Settings_Stats_Ui_Dust, .Settings_Stats_Animation_Entries,
         .Gif_Status_Recording, .Terminal_History_Age_Seconds,
         .Terminal_History_Age_Minutes, .Terminal_History_Age_Hours,
         .Terminal_History_Age_Days:
        return "count", .Int64
    case .Fps_Overlay:
        return "fps", .Float32_One_Decimal
    case:
        return "", .Text
    }
}

// Release the fixture only after all callers have stopped borrowing its messages.
content_message_test_destroy :: proc(generation: ^Content_Generation) {
    content_generation_destroy(generation)
    free(generation, context.allocator)
}

// Freeze baseline substituted bytes independently of the runtime formatter.
content_message_test_expected :: proc(
    template: string, kind: Content_Argument_Kind) -> string {
    switch kind {
    case .Text:
        if template ==
            "Unicode completion: {symbol}. Press Right Arrow to insert; Escape to dismiss." {
            return "Unicode completion: Elements. Press Right Arrow to insert; Escape to dismiss."
        }
        return "Actions for Elements" if template == "Actions for {name}" else
            "Use suggested search: Elements"
    case .Uint32, .Int64:
        // Baseline templates each contain one named count placeholder.
        for index in 0..<len(template) {
            if template[index] == '{' {
                return fmt.tprintf("%s42%s", template[:index], template[index + 7:])
            }
        }
    case .Float32_One_Decimal:
        return "FPS 59.2"
    }
    return template
}

// Exercise every ID, template, state label, signature, and exact baseline substitution.
@(test)
content_messages_preserve_every_shipped_output :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    templates := CONTENT_MESSAGE_TEST_TEMPLATES
    covered := 0
    for id in Content_Message_Id {
        if id == .Invalid {
            continue
        }
        identity, ordinal := content_message_identity(id)
        testing.expect(t, ordinal >= 0 && identity.native_id == u16(id))
        view, status := content_message_lookup(generation, id)
        testing.expect_value(t, status, Content_Message_Status.Ok)
        testing.expect_value(t, view.ordinal, ordinal)
        testing.expect_value(t, view.template, templates[ordinal])
        content_message_test_output(t, generation, id, templates[ordinal])
        covered += 1
    }
    testing.expect_value(t, covered, CONTENT_SHIPPED_MESSAGE_COUNT)
}

// Verify one no-argument or typed message using the independently frozen output.
content_message_test_output :: proc(
    t: ^testing.T, generation: ^Content_Generation, id: Content_Message_Id,
    template: string) {
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    name, kind := content_message_test_signature(id)
    arguments: [1]Content_Format_Argument
    count := 0
    if len(name) > 0 {
        arguments[0].name = name
        switch kind {
        case .Text:
            arguments[0].value = string("Elements")
        case .Uint32:
            arguments[0].value = u32(42)
        case .Int64:
            arguments[0].value = i64(42)
        case .Float32_One_Decimal:
            arguments[0].value = f32(59.25)
        }
        count = 1
    }
    text, status := content_message_format(generation, id, arguments[:count], storage[:])
    testing.expect_value(t, status, Content_Message_Status.Ok)
    expected := count == 0 ? template : content_message_test_expected(template, kind)
    testing.expect_value(t, text, expected)
}

// Lookup must use exact identity and references rather than database or enum ordinals.
@(test)
content_messages_reject_missing_identity_and_locale :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    _, missing := content_message_lookup(generation, .Invalid)
    testing.expect_value(t, missing, Content_Message_Status.Missing_Key)
    _, locale := content_message_lookup(generation, .Navigation_Library, "fr")
    testing.expect_value(t, locale, Content_Message_Status.Missing_Locale)
    generation.data.translations[0].locale_index = 1
    _, translation := content_message_lookup(generation, .Navigation_Library)
    testing.expect_value(t, translation, Content_Message_Status.Missing_Translation)
    generation.data.translations[0].locale_index = 0
    generation.data.messages[0].key = generation.data.messages[1].key
    _, key := content_message_lookup(generation, .Navigation_Library)
    testing.expect_value(t, key, Content_Message_Status.Missing_Key)
    generation.data.messages[0], generation.data.messages[1] =
        generation.data.messages[1], generation.data.messages[0]
    generation.data.translations[0].message_index = 1
    generation.data.translations[1].message_index = 0
    view, found := content_message_lookup(generation, .Gif_Save)
    testing.expect_value(t, found, Content_Message_Status.Ok)
    testing.expect_value(t, view.ordinal, 1)
    testing.expect_value(t, view.template, "Save GIF")
}

// A rejected call returns a precise status and leaves caller storage untouched.
content_message_test_reject :: proc(
    t: ^testing.T, generation: ^Content_Generation, id: Content_Message_Id,
    arguments: []Content_Format_Argument, expected: Content_Message_Status) {
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for &byte in storage[:] {
        byte = 0xa5
    }
    baseline := storage
    text, status := content_message_format(generation, id, arguments, storage[:])
    testing.expect_value(t, status, expected)
    testing.expect_value(t, text, "")
    testing.expect_value(t, storage, baseline)
}

// Wrong names, duplicate/missing values, wire kinds, and invalid text cannot format.
@(test)
content_messages_validate_named_argument_values :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    content_message_test_reject(t, generation, .Library_Status_Match_Count, nil,
        .Signature_Mismatch)
    content_message_test_reject(t, generation, .Library_Status_Match_Count,
        []Content_Format_Argument{{"other", u32(1)}}, .Signature_Mismatch)
    content_message_test_reject(t, generation, .Library_Status_Match_Count,
        []Content_Format_Argument{{"count", i64(1)}}, .Signature_Mismatch)
    content_message_test_reject(t, generation, .Library_Status_Match_Count,
        []Content_Format_Argument{{"count", u32(1)}, {"count", u32(2)}},
        .Signature_Mismatch)
    content_message_test_reject(t, generation, .Settings_Stats_Dust,
        []Content_Format_Argument{{"count", i64(-1)}}, .Invalid_Argument)
    content_message_test_reject(t, generation, .Fps_Overlay,
        []Content_Format_Argument{{"fps", f32(math.nan_f64())}}, .Invalid_Argument)
    content_message_test_reject(t, generation, .Fps_Overlay,
        []Content_Format_Argument{{"fps", f32(math.inf_f64(1))}}, .Invalid_Argument)
    content_message_test_reject(t, generation, .Library_Suggestion_Action,
        []Content_Format_Argument{{"query", string("\x80")}}, .Invalid_Argument)
    oversized: [UI_FORMAT_TEXT_BYTE_CAPACITY + 1]u8
    content_message_test_reject(t, generation, .Library_Suggestion_Action,
        []Content_Format_Argument{{"query", string(oversized[:])}}, .Invalid_Argument)
}

// Defensive grammar validation rejects corruption instead of interpreting more syntax.
@(test)
content_messages_reject_malformed_and_unknown_placeholders :: proc(t: ^testing.T) {
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    cases := [?]string{"{", "}", "{}", "{{count}}", "{Count}", "{count:2}",
        "{unknown}", "{count", "count}", "No substitutions"}
    for template in cases {
        _, status := content_message_expand(template,
            []Content_Format_Argument{{"count", u32(1)}}, storage[:])
        testing.expect_value(t, status, Content_Message_Status.Invalid_Template)
    }
    text_count, valid := content_message_expand("{count} again {count}",
        []Content_Format_Argument{{"count", u32(7)}}, storage[:])
    testing.expect_value(t, valid, Content_Message_Status.Ok)
    testing.expect_value(t, string(storage[:text_count]), "7 again 7")
}

// The frozen output limit permits exactly 536 bytes but rejects 537 without truncation.
@(test)
content_messages_enforce_exact_output_capacity :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    query: [UI_FORMAT_TEXT_BYTE_CAPACITY]u8
    for &byte in query[:] {
        byte = 'q'
    }
    arguments: []Content_Format_Argument = {{"query", string(query[:])}}
    exact: [534]u8
    text, status := content_message_format(
        generation, .Library_Suggestion_Action, arguments, exact[:])
    testing.expect_value(t, status, Content_Message_Status.Ok)
    testing.expect_value(t, len(text), 534)
    short: [533]u8
    _, too_short := content_message_format(
        generation, .Library_Suggestion_Action, arguments, short[:])
    testing.expect_value(t, too_short, Content_Message_Status.Output_Capacity)
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    count, at_bound := content_message_expand(
        "123456789012345678901234{query}", arguments, storage[:])
    testing.expect_value(t, at_bound, Content_Message_Status.Ok)
    testing.expect_value(t, count, UI_FORMAT_OUTPUT_BYTE_CAPACITY)
    _, over_bound := content_message_expand(
        "1234567890123456789012345{query}", arguments, storage[:])
    testing.expect_value(t, over_bound, Content_Message_Status.Output_Capacity)
}

// Repeated formatting does not allocate, mutate packed content, or grow owner pressure.
@(test)
content_messages_preserve_numeric_precision_and_owner_pressure :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    before := storage_pkg.arena_owner_diagnostics(&generation.arena_owner)
    text_count := generation.text_builder.count
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for _ in 0..<1000 {
        text, status := content_message_format(generation, .Library_Status_Match_Count,
            []Content_Format_Argument{{"count", max(u32)}}, storage[:])
        testing.expect_value(t, status, Content_Message_Status.Ok)
        testing.expect_value(t, text, "Matching animations: 4294967295")
    }
    values := [?]f32{0, -0.0, 59.25, 59.75, 1000.125, -1.25, max(f32)}
    for value in values {
        text, status := content_message_format(generation, .Fps_Overlay,
            []Content_Format_Argument{{"fps", value}}, storage[:])
        testing.expect_value(t, status, Content_Message_Status.Ok)
        testing.expect_value(t, text, fmt.tprintf("FPS %.1f", value))
    }
    text, status := content_message_format(generation, .Settings_Stats_Dust,
        []Content_Format_Argument{{"count", max(i64)}}, storage[:])
    testing.expect_value(t, status, Content_Message_Status.Ok)
    testing.expect_value(t, text, "Dust particles Rendered: 9223372036854775807")
    testing.expect_value(t, generation.text_builder.count, text_count)
    diagnostics := storage_pkg.arena_owner_diagnostics(&generation.arena_owner)
    testing.expect_value(t, diagnostics, before)
}

// Named arguments may be reordered and repeated, but neither omitted nor duplicated.
@(test)
content_messages_support_two_named_values_without_ordinal_assumptions ::
proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    count_view, _ := content_message_lookup(generation, .Library_Status_Match_Count)
    query_view, _ := content_message_lookup(generation, .Library_Suggestion_Action)
    message: Content_Message = {
        argument_count = 2,
        arguments = {
            count_view.message.arguments[0],
            query_view.message.arguments[0],
        },
    }
    arguments: []Content_Format_Argument = {
        {"query", string("Elements")},
        {"count", u32(42)},
    }
    testing.expect_value(t,
        content_message_validate_arguments(generation, &message, arguments),
        Content_Message_Status.Ok)
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    count, status := content_message_expand(
        "{query}: {count} again {query}", arguments, storage[:])
    testing.expect_value(t, status, Content_Message_Status.Ok)
    testing.expect_value(t, string(storage[:count]), "Elements: 42 again Elements")
    arguments[1] = {"query", string("duplicate")}
    testing.expect_value(t,
        content_message_validate_arguments(generation, &message, arguments),
        Content_Message_Status.Signature_Mismatch)
}

// Formatting and lookup allocate neither caller nor temporary persistent storage.
@(test)
content_messages_hot_path_allocates_nothing :: proc(t: ^testing.T) {
    generation := content_message_test_generation(t)
    defer content_message_test_destroy(generation)
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    previous_allocator := context.allocator
    context.allocator = mem.tracking_allocator(&tracker)
    storage: [UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    for _ in 0..<1000 {
        _, static_status := content_message_lookup(
            generation, .Navigation_Library)
        _, text_status := content_message_format(
            generation, .Library_Suggestion_Action,
            []Content_Format_Argument{{"query", string("Elements")}}, storage[:])
        _, number_status := content_message_format(
            generation, .Fps_Overlay,
            []Content_Format_Argument{{"fps", f32(59.75)}}, storage[:])
        testing.expect(t, static_status == .Ok && text_status == .Ok &&
            number_status == .Ok)
    }
    context.allocator = previous_allocator
    testing.expect_value(t, tracker.total_allocation_count, i64(0))
}
