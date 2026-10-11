#+test
package termemulator

import "core:testing"
import termgrid "../grid"
import termmodel "../model"
import termpalette "../palette"

// Verify DECRQSS construction depends only on the explicit query snapshot.
@(test)
emulator_test_query_context_decrqss :: proc(t: ^testing.T) {
    producer := termmodel.Terminal_Producer{.Terminal_Session, 7, 2}
    query_context := Query_Context{
        style = {
            foreground = termpalette.terminal_color_indexed(3),
            background = termpalette.terminal_color_direct(0x010203ff),
            bold = true,
            italic = true,
            underline = true,
        },
        scroll_top = 2,
        scroll_bottom = 8,
        producer = producer,
    }
    sgr_selector := "m"
    response := query_prepare_decrqss_response(
        query_context, transmute([]u8)sgr_selector)
    testing.expect_value(t, response.kind, termmodel.Terminal_Response_Kind.Decrqss_Sgr)
    testing.expect_value(t,
        response.first, TERMINAL_SGR_BOLD | TERMINAL_SGR_ITALIC |
            TERMINAL_SGR_UNDERLINE)
    testing.expect_value(t, response.producer, producer)

    margin_selector := "r"
    margins := query_prepare_decrqss_response(
        query_context, transmute([]u8)margin_selector)
    testing.expect_value(t, margins.first, u32(3))
    testing.expect_value(t, margins.second, u32(9))
}

// Verify XTGETTCAP construction is transactional and producer-correlated.
@(test)
emulator_test_query_context_xtgetcap :: proc(t: ^testing.T) {
    producer := termmodel.Terminal_Producer{.Julia_Evaluation, 11, 4}
    responses: [3]termmodel.Terminal_Response
    candidate := "544e;436f;524742"
    count, valid := query_prepare_xtgetcap_responses(
        {producer = producer}, transmute([]u8)candidate, responses[:])
    testing.expect(t, valid)
    testing.expect_value(t, count, 3)
    for response in responses[:count] {
        testing.expect_value(t, response.producer, producer)
        testing.expect_value(t, response.kind, termmodel.Terminal_Response_Kind.Xtgetcap)
    }

    malformed := "544e;"
    rejected_count, rejected := query_prepare_xtgetcap_responses(
        {}, transmute([]u8)malformed, responses[:])
    testing.expect(t, !rejected)
    testing.expect_value(t, rejected_count, 0)
}

// Verify parser state is copied into the query context without retaining the parser.
@(test)
emulator_test_interpreter_query_context_snapshot :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    testing.expect(t, termgrid.grid_init(
        &grid, 8, 4, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    retained: Terminal_Title_State
    retained.query_geometry = {
        window_width = 640,
        window_height = 480,
        valid = true,
    }
    retained.modify_other_keys_level = 2
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained}))
    interpreter.input_mode.bracketed_paste = true
    interpreter.cursor_visible = false
    snapshot := interpreter_query_context(&interpreter)
    testing.expect_value(t, snapshot.geometry.window_width, 640)
    testing.expect_value(t, snapshot.geometry.window_height, 480)
    testing.expect_value(t, snapshot.modify_other_keys_level, u8(2))
    testing.expect(t, snapshot.input_mode.bracketed_paste)
    testing.expect(t, snapshot.palette == &retained.palette)
}
