package ui

import native "../native"
import viewmodel "../model"
import view_core "../core"
import contentdata "../../core/content"

import "../../core"
import geometry "../../core/geometry"
import view_font "../font"

LIBRARY_SEARCH_INPUT_ID :: 6401
LIBRARY_SEARCH_CLEAR_ID :: 6402
LIBRARY_SEARCH_SUGGESTION_ID :: 6403
LIBRARY_SEARCH_STATUS_ID :: 6404
LIBRARY_SEARCH_TEXT_RUN_ID :: 6410
LIBRARY_SEARCH_INPUT_HEIGHT :: f32(30)
LIBRARY_SEARCH_PROMPT_HEIGHT :: f32(20)
LIBRARY_SEARCH_SUGGESTION_HEIGHT :: f32(24)
LIBRARY_SEARCH_INSET :: f32(6)
LIBRARY_SEARCH_ACTION_WIDTH :: f32(30)
LIBRARY_SEARCH_DEBOUNCE_SECONDS :: f32(0.175)

// Library_Search_Layout fixes search controls above the remaining tree viewport.
Library_Search_Layout :: struct {
    input: geometry.Rectangle,
    text_input: geometry.Rectangle,
    action: geometry.Rectangle,
    suggestion_prompt: geometry.Rectangle,
    suggestion: geometry.Rectangle,
    tree: geometry.Rectangle,
}

// Library_Search_Preparation retains one frame's search control geometry and state.
Library_Search_Preparation :: struct {
    layout: Library_Search_Layout,
    input: Input_Box_Result,
    clear: Icon_Button_Result,
    suggestion: Text_Button_Result,
}

// prepare_library_search_visual borrows current text without editing or publishing controls.
prepare_library_search_visual :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle) -> Library_Search_Preparation {
    result := Library_Search_Preparation{layout = library_search_layout(
        panel, state^.ui_runtime.library_search.suggestion_length > 0)}
    params := library_search_input_params(state, result.layout, {}, panel)
    params.focused = false
    result.input = input_box_draw_result(params, false)
    return result
}

// library_search_layout reserves correction rows only while a suggestion is visible.
library_search_layout :: proc(
    panel: geometry.Rectangle, show_suggestion: bool) -> Library_Search_Layout {
    inner := geometry.Rectangle{panel.x + LIBRARY_SEARCH_INSET,
        panel.y + LIBRARY_SEARCH_INSET,
        max(f32(0), panel.width - LIBRARY_SEARCH_INSET * 2),
        max(f32(0), panel.height - LIBRARY_SEARCH_INSET * 2)}
    input := geometry.Rectangle{inner.x, inner.y, inner.width,
        min(LIBRARY_SEARCH_INPUT_HEIGHT, inner.height)}
    action_width := min(LIBRARY_SEARCH_ACTION_WIDTH, input.width)
    prompt_y := input.y + input.height
    prompt_height := f32(0)
    suggestion_height := f32(0)
    if show_suggestion {
        prompt_height = min(LIBRARY_SEARCH_PROMPT_HEIGHT,
            max(f32(0), inner.y + inner.height - prompt_y))
        suggestion_height = min(LIBRARY_SEARCH_SUGGESTION_HEIGHT,
            max(f32(0), inner.y + inner.height - prompt_y - prompt_height))
    }
    suggestion_y := prompt_y + prompt_height
    suggestion_x := inner.x + INPUT_BOX_TEXT_INSET * 2
    suggestion := geometry.Rectangle{suggestion_x, suggestion_y,
        max(f32(0), inner.width - (suggestion_x - inner.x)), suggestion_height}
    tree_y := suggestion.y + suggestion.height
    return {input = input,
        text_input = {input.x, input.y, max(f32(0), input.width - action_width),
            input.height},
        action = {input.x + input.width - action_width, input.y,
            action_width, input.height},
        suggestion_prompt = {inner.x, prompt_y, inner.width, prompt_height},
        suggestion = suggestion,
        tree = {inner.x, tree_y, inner.width,
            max(f32(0), inner.y + inner.height - tree_y)}}
}

// library_search_visible reports whether the editable control belongs to composition.
library_search_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime != nil && runtime^.active_accordion_section == .Library
}

// library_search_input_rect resolves the routed text-control rectangle.
library_search_input_rect :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> geometry.Rectangle {
    return library_search_layout(
        accordion_content_rect(runtime, .Library), false).text_input
}

// library_search_input_params borrows bounded query storage for one editable frame.
library_search_input_params :: proc(
    state: ^core.Euclid_General_State, layout: Library_Search_Layout,
    frame: Input_Frame, clip_rect: geometry.Rectangle) -> Input_Box_Params {
    search := &state^.ui_runtime.library_search
    focus := state^.ui_runtime.interaction_frame.effective_focus
    target := state^.ui_runtime.interaction_frame.pointer_target
    query := string(search^.query[:search^.query_length])
    return {rect = layout.text_input,
        clip_rect = clip_rect,
        descriptor = {
            id = semantic_control_id(.Library_Control, LIBRARY_SEARCH_INPUT_ID),
            text_run_id = semantic_control_id(
                .Library_Control, LIBRARY_SEARCH_TEXT_RUN_ID),
            region = .Accordion_Content,
            label = view_core.shell_message(state, .Library_Search_Input),
            placeholder = view_core.shell_message(state, .Library_Search_Input),
            text = query, mode = .Editable,
            cursor_byte = search^.input.cursor_byte,
            anchor_byte = search^.input.anchor_byte,
            content_revision = search^.query_revision,
        },
        semantic_focus = state^.ui_runtime.semantic_focus, state = &search^.input,
        frame = frame, focused = focus.kind == .Input_Box &&
            focus.id == LIBRARY_SEARCH_INPUT_ID,
        pointer_routed = target.focus.kind == .Input_Box &&
            target.id == LIBRARY_SEARCH_INPUT_ID,
        column_advance = TEXT_WRAP_ADVANCE,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        edit_target = {search^.query[:], &search^.query_length}}
}

// library_search_apply_input commits edit and immediate-submit intent.
library_search_apply_input :: proc(
    search: ^viewmodel.Library_Search_State, result: Input_Box_Result) {
    if result.changed {
        viewmodel.library_search_query_changed(
            search, LIBRARY_SEARCH_DEBOUNCE_SECONDS)
    }
    if result.submit_requested && search^.query_length > 0 {
        search^.query_dirty = true
        search^.submit_requested = true
        search^.debounce_remaining_seconds = 0
    }
}

// library_search_clear_query invalidates work and restores ordinary tree behavior.
library_search_clear_query :: proc(search: ^viewmodel.Library_Search_State) {
    search^.query_length = 0
    search^.input.cursor_byte = 0
    search^.input.anchor_byte = 0
    viewmodel.library_search_query_changed(search, 0, true)
}

// library_search_apply_suggestion replaces the query and requests immediate search.
library_search_apply_suggestion :: proc(search: ^viewmodel.Library_Search_State) {
    if search^.suggestion_length <= 0 {
        return
    }
    copy(search^.query[:search^.suggestion_length],
        search^.suggestion[:search^.suggestion_length])
    search^.query_length = search^.suggestion_length
    viewmodel.library_search_query_changed(search, 0, true)
    search^.input.cursor_byte = search^.query_length
    search^.input.anchor_byte = search^.query_length
    search^.submit_requested = true
}

// library_search_suggestion_label builds the bounded spoken correction target.
library_search_suggestion_label :: proc(
    state: ^core.Euclid_General_State, suggestion: string, storage: []u8) -> string {
    if len(suggestion) == 0 {
        return view_core.shell_message(state, .Library_Suggestion_Action_Fallback)
    }
    return view_core.shell_format(state, .Library_Suggestion_Action,
        []contentdata.Content_Format_Argument{{"query", suggestion}}, storage)
}

// library_search_status_text formats one bounded meaningful search milestone.
library_search_status_text :: proc(
    state: ^core.Euclid_General_State,
    search: ^viewmodel.Library_Search_State, storage: []u8) -> string {
    if search == nil || search^.query_length == 0 {
        return ""
    }
    if search^.invalid_query {
        return view_core.shell_format(state, .Library_Status_Invalid, nil, storage)
    }
    if !search^.active {
        return view_core.shell_format(state, .Library_Status_Searching, nil, storage)
    }
    if search^.total_match_count == 0 {
        return view_core.shell_format(state, .Library_Status_No_Matches, nil, storage)
    }
    id := contentdata.Content_Message_Id.Library_Status_Match_Count
    if search^.more_available {
        id = .Library_Status_Match_Count_More
    }
    return view_core.shell_format(state, id,
        []contentdata.Content_Format_Argument{{"count", search.total_match_count}},
        storage)
}

// prepare_library_search_status publishes bounded result and error feedback.
prepare_library_search_status :: proc(state: ^core.Euclid_General_State) {
    storage: [64]u8
    value := library_search_status_text(
        state, &state^.ui_runtime.library_search, storage[:])
    if len(value) == 0 {
        return
    }
    _ = semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = semantic_control_id(.Library_Control, LIBRARY_SEARCH_STATUS_ID),
        role = .Status, states = {.Visible, .Enabled},
        region = .Accordion_Content, traversal_order = 4,
        bounds = {}, clip_bounds = {},
        label = view_core.shell_message(state, .Library_Search_Status_Label),
        value = value,
    })
}

// library_search_accept_suggestion_key admits Right only at a collapsed end caret.
library_search_accept_suggestion_key :: proc(
    search: ^viewmodel.Library_Search_State, frame: Input_Frame) -> bool {
    if search == nil || search^.suggestion_length <= 0 ||
        search^.input.cursor_byte != search^.query_length ||
        search^.input.anchor_byte != search^.query_length {
        return false
    }
    for event in frame.events {
        if (event.kind == .Press || event.kind == .Repeat) &&
            event.key == .Right && event.modifiers == {} {
            return true
        }
    }
    return false
}

// prepare_library_clear resolves, registers, and applies the Clear action.
prepare_library_clear :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: Input_Frame, layout: Library_Search_Layout) -> Icon_Button_Result {
    search := &state^.ui_runtime.library_search
    result := update_icon_button({id = LIBRARY_SEARCH_CLEAR_ID,
        rect = layout.action, icon_id = .None, mouse = frame,
        interaction_space_rect = panel,
        interaction_enabled = search^.query_length > 0,
        inset_scale = 0.55,
        semantics = {
            publish = true,
            focus = state^.ui_runtime.semantic_focus,
            id = semantic_control_id(.Library_Control, LIBRARY_SEARCH_CLEAR_ID),
            role = .Button,
            states = button_semantic_states(search^.query_length > 0),
            region = .Accordion_Content,
            traversal_order = 1,
            clip_bounds = viewmodel.Rectangle(panel),
            label = view_core.shell_message(state, .Library_Clear_Search),
        }}, &state^.ui_runtime.ui_press_owner)
    if result.action.activated {
        library_search_clear_query(search)
    }
    return result
}

// prepare_library_suggestion resolves one visible correction action.
prepare_library_suggestion :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: Input_Frame, layout: Library_Search_Layout) -> Text_Button_Result {
    search := &state^.ui_runtime.library_search
    if search^.suggestion_length <= 0 {
        return {}
    }
    suggestion := string(search^.suggestion[:search^.suggestion_length])
    label_storage: [viewmodel.LIBRARY_SEARCH_QUERY_BYTE_CAPACITY + 24]u8
    action_label := library_search_suggestion_label(state, suggestion, label_storage[:])
    result := update_text_button({id = LIBRARY_SEARCH_SUGGESTION_ID,
        rect = layout.suggestion, label = suggestion, enabled = true,
        mouse = frame, interaction_space_rect = panel,
        interaction_enabled = true,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        semantics = {
            publish = true,
            focus = state^.ui_runtime.semantic_focus,
            id = semantic_control_id(
                .Library_Control, LIBRARY_SEARCH_SUGGESTION_ID),
            role = .Button,
            states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
            region = .Accordion_Content,
            traversal_order = 2,
            clip_bounds = viewmodel.Rectangle(panel),
            label = action_label,
            value = suggestion,
        }},
        &state^.ui_runtime.ui_press_owner)
    if result.action.activated {
        library_search_apply_suggestion(search)
    }
    return result
}

// prepare_library_search resolves input, clear, and suggestion interactions.
prepare_library_search :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: Input_Frame) -> Library_Search_Preparation {
    search := &state^.ui_runtime.library_search
    result := Library_Search_Preparation{layout = library_search_layout(
        panel, search^.suggestion_length > 0)}
    accept_suggestion := library_search_accept_suggestion_key(search, frame)
    params := library_search_input_params(state, result.layout, frame, panel)
    result.input = input_box_prepare(params, &state^.ui_runtime.ui_press_owner)
    library_search_apply_input(search, result.input)
    if accept_suggestion {
        library_search_apply_suggestion(search)
    }
    result.clear = prepare_library_clear(state, panel, frame, result.layout)
    result.layout = library_search_layout(panel, search^.suggestion_length > 0)
    result.suggestion = prepare_library_suggestion(
        state, panel, frame, result.layout)
    prepare_library_search_status(state)
    if result.input.hovered {
        state^.ui_runtime.cursor = .Text
    }
    return result
}

// draw_encoded_search_action draws the passive magnifier or active clear icon.
draw_encoded_search_action :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle, clear: bool) {
    center := geometry.Vector2{rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5}
    radius := min(rectangle.width, rectangle.height) * 0.18
    if clear {
        _ = native.draw_encoder_line(encoder, center - {radius, radius},
            center + {radius, radius}, 1.6, UI_TEXT_COLOR)
        _ = native.draw_encoder_line(encoder, center + {-radius, radius},
            center + {radius, -radius}, 1.6, UI_TEXT_COLOR)
        return
    }
    lens := center + geometry.Vector2{-radius * 0.25, -radius * 0.25}
    _ = native.draw_encoder_ring(
        encoder, lens, radius * 0.72, radius, UI_TEXT_COLOR)
    _ = native.draw_encoder_line(encoder, lens + {radius * 0.65, radius * 0.65},
        center + {radius, radius}, 1.6, UI_TEXT_COLOR)
}

// draw_encoded_library_search_geometry renders the fixed search-control chrome.
draw_encoded_library_search_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Library_Search_Preparation) {
    params := library_search_input_params(state, prepared.layout, {},
        geometry.Rectangle(prepared.input.control_geometry.clip_bounds))
    draw_encoded_input_box(encoder, params, prepared.input)
    clear := state^.ui_runtime.library_search.query_length > 0
    if clear || !prepared.input.focused {
        draw_encoded_search_action(encoder, prepared.layout.action, clear)
    }
}

// draw_encoded_library_search_text renders placeholder and verified correction text.
draw_encoded_library_search_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Library_Search_Preparation) {
    search := &state^.ui_runtime.library_search
    focus := state^.ui_runtime.interaction_frame.effective_focus
    if search^.query_length == 0 &&
        !(focus.kind == .Input_Box && focus.id == LIBRARY_SEARCH_INPUT_ID) {
        draw_encoded_label(state, encoder,
            view_core.shell_message(state, .Library_Search_Input),
            prepared.layout.text_input.x + INPUT_BOX_TEXT_INSET,
            prepared.layout.text_input.y + 7)
    }
    if search^.suggestion_length > 0 {
        draw_encoded_label(state, encoder,
            view_core.shell_message(state, .Library_Suggestion_Prompt),
            prepared.layout.suggestion_prompt.x + INPUT_BOX_TEXT_INSET,
            prepared.layout.suggestion_prompt.y + 3)
        draw_encoded_label(state, encoder,
            string(search^.suggestion[:search^.suggestion_length]),
            prepared.layout.suggestion.x,
            prepared.layout.suggestion.y + 3)
    }
}