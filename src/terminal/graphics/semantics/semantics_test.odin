#+test
package termgraphicssemantics

import "core:testing"
import termattachment "../../attachment"
import gfxprotocol "../protocol"

GRAPHICS_SEMANTICS_TEST_ANIMATED_GIF :: [109]u8{
    71, 73, 70, 56, 57, 97, 2, 0, 1, 0, 129, 0, 0, 255, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 255, 11, 78, 69, 84, 83,
    67, 65, 80, 69, 50, 46, 48, 3, 1, 2, 0, 0, 33, 249, 4, 8,
    2, 0, 0, 0, 44, 0, 0, 0, 0, 2, 0, 1, 0, 0, 8, 5,
    0, 1, 0, 8, 8, 0, 33, 249, 4, 8, 3, 0, 0, 0, 44, 0,
    0, 0, 0, 2, 0, 1, 0, 129, 0, 255, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 8, 5, 0, 1, 0, 8, 8, 0, 59,
}

GRAPHICS_SEMANTICS_TEST_STATIC_GIF :: [34]u8{
    71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0,
    255, 255, 255, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 1, 76,
    0, 59,
}

// Mutable capability fixture used by direct graphics semantics tests.
Graphics_Semantics_Test_Context :: struct {
    anchor: Anchor,
    cell_height: int,
    advanced_rows: int,
}

// Return the fixture's current stable terminal anchor.
graphics_semantics_test_anchor :: proc(user_data: rawptr) -> (Anchor, bool) {
    fixture := cast(^Graphics_Semantics_Test_Context)user_data
    if fixture == nil { return {}, false }
    return fixture.anchor, true
}

// Record synchronous row advancement requested by semantic placement.
graphics_semantics_test_advance :: proc(user_data: rawptr, rows: int) {
    fixture := cast(^Graphics_Semantics_Test_Context)user_data
    if fixture != nil { fixture.advanced_rows += rows }
}

// Return the fixture's configured terminal cell height.
graphics_semantics_test_cell_height :: proc(user_data: rawptr) -> (int, bool) {
    fixture := cast(^Graphics_Semantics_Test_Context)user_data
    if fixture == nil || fixture.cell_height <= 0 { return 0, false }
    return fixture.cell_height, true
}

// Verify Kitty controls parse bounded identity, geometry, crop, and cursor values.
@(test)
graphics_semantics_test_kitty_controls :: proc(t: ^testing.T) {
    source := "a=T,f=32,s=2,v=3,i=7,p=9,c=4,r=5,x=1,y=2,w=3,h=4,X=5,Y=6,z=-2,C=1"
    controls := graphics_parse_kitty_raw_controls(
        transmute([]u8)source)
    testing.expect(t, controls.valid)
    testing.expect_value(t, controls.image_id, u32(7))
    testing.expect_value(t, controls.placement_id, u32(9))
    testing.expect_value(t, controls.columns, 4)
    testing.expect_value(t, controls.rows, 5)
    testing.expect_value(t, controls.z_index, i32(-2))
    testing.expect(t, controls.preserve_cursor)
    invalid_source := "a=T,q=3"
    testing.expect(t, !graphics_parse_kitty_raw_controls(
        transmute([]u8)invalid_source).valid)
}

// Verify animation actions map overloaded controls independent of key order.
@(test)
graphics_semantics_test_kitty_animation_controls :: proc(t: ^testing.T) {
    frame_source := "Y=255,z=-1,r=2,c=1,X=1,a=f,i=7,s=3,v=4,x=1,y=2"
    frame := graphics_parse_kitty_raw_controls(transmute([]u8)frame_source)
    testing.expect(t, frame.valid)
    testing.expect_value(t, frame.action, gfxprotocol.Kitty_Graphics_Action.Frame)
    testing.expect_value(t, frame.base_frame, 1)
    testing.expect_value(t, frame.edit_frame, 2)
    testing.expect_value(t, frame.gap_ms, i32(-1))
    testing.expect_value(t, frame.background_rgba, u32(255))
    testing.expect_value(t, frame.composition_mode, 1)

    animate_source := "v=4,s=3,c=2,r=1,z=48,a=a,i=7"
    animate := graphics_parse_kitty_raw_controls(transmute([]u8)animate_source)
    testing.expect(t, animate.valid)
    testing.expect_value(t, animate.current_frame, 2)
    testing.expect_value(t, animate.edit_frame, 1)
    testing.expect_value(t, animate.animation_state, 3)
    testing.expect_value(t, animate.loop_count, u32(4))

    compose_source := "C=1,Y=8,X=4,h=2,w=3,y=1,x=2,c=3,r=2,a=c,i=7"
    compose := graphics_parse_kitty_raw_controls(transmute([]u8)compose_source)
    testing.expect(t, compose.valid)
    testing.expect_value(t, compose.base_frame, 3)
    testing.expect_value(t, compose.edit_frame, 2)
    testing.expect_value(t, compose.composition_mode, 1)
}

// Verify iTerm2 and Sixel parsing retain exact bounded semantic values.
@(test)
graphics_semantics_test_iterm2_and_sixel_controls :: proc(t: ^testing.T) {
    iterm2_source := "inline=1;width=4;height=50%;preserveAspectRatio=0"
    controls := graphics_iterm2_parse_controls(
        transmute([]u8)iterm2_source)
    testing.expect(t, controls.valid && controls.inline_image)
    testing.expect_value(t, controls.column_span, 4)
    testing.expect_value(t, controls.height_percent, 50)
    testing.expect(t, !controls.preserve_aspect_ratio)

    sixel_source := "#1;2;100;0;0~"
    semantics := graphics_parse_sixel(
        transmute([]u8)sixel_source, {}, {
            dimension_limit = 16,
            image_pixel_limit = 256,
        })
    testing.expect(t, semantics.valid)
    testing.expect_value(t, semantics.width, 1)
    testing.expect_value(t, semantics.height, 6)
    testing.expect_value(t, semantics.palette_count, 2)
    testing.expect_value(t, semantics.palette[1], u32(0xff0000ff))
}

// Verify geometry snapshots and cursor effects use only explicit capabilities.
@(test)
graphics_semantics_test_context_capabilities :: proc(t: ^testing.T) {
    fixture := Graphics_Semantics_Test_Context{cell_height = 16, anchor = {
        screen = termattachment.Screen_Identity.Alternate,
        logical_row = 42,
        column = 3,
        sixel_scrolling_mode = true,
    }}
    semantics_context := Context{
        user_data = &fixture,
        anchor = graphics_semantics_test_anchor,
        cell_height = graphics_semantics_test_cell_height,
        advance_rows = graphics_semantics_test_advance,
    }
    geometry := graphics_kitty_geometry(&semantics_context, {
        columns = 2,
        rows = 4,
        z_index = -3,
    })
    testing.expect_value(t, geometry.screen, fixture.anchor.screen)
    testing.expect_value(t, geometry.logical_row, i64(42))
    testing.expect_value(t, geometry.column, 3)
    testing.expect_value(t, geometry.column_span, 2)
    testing.expect_value(t, geometry.row_span, 4)
    testing.expect_value(t, geometry.z_index, i32(-3))
    graphics_kitty_advance_cursor(&semantics_context, 4)
    testing.expect_value(t, fixture.advanced_rows, 4)
    testing.expect_value(t, graphics_placement_rows(
        &semantics_context, {pixel_height = 33}, {height = 64}), 3)
    testing.expect_value(t, graphics_placement_rows(
        &semantics_context, {row_span = 5, pixel_height = 33}, {height = 64}), 5)
}

// Queue one GIF for asynchronous preflight without reserving an attachment.
graphics_semantics_test_expect_gif_preflight :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State, bytes: []u8) {
    animated_transfer, animated_outcome := termattachment.transfer_begin(
        store, .Iterm2, len(bytes))
    testing.expect_value(
        t, animated_outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.transfer_append(
        store, animated_transfer, bytes),
        termattachment.Admission_Outcome.Admitted)
    animated, queued := graphics_iterm2_queue_request(parser, {
        kind = .Iterm2_Image,
        transfer_id = animated_transfer,
    })
    testing.expect(t, queued)
    testing.expect_value(t, animated.kind,
        gfxprotocol.Graphics_Decode_Kind.Iterm2_Gif_Preflight)
    testing.expect_value(t, animated.attachment_id, termattachment.Attachment_Id{})

    queued_animated, available := gfxprotocol.graphics_parser_take_decode_request(parser)
    testing.expect(t, available)
    termattachment.transfer_remove(store, queued_animated.transfer_id)
}

// Verify iTerm2 defers complete GIF inspection and target reservation.
@(test)
graphics_semantics_test_iterm2_animated_gif_admission :: proc(t: ^testing.T) {
    limits := termattachment.limits_default()
    limits.attachment_capacity = 2
    limits.placement_capacity = 2
    limits.transfer_capacity = 2
    limits.transfer_byte_limit = 1024
    limits.dimension_limit = 16
    limits.image_pixel_limit = 256
    limits.cpu_byte_limit = 4096
    limits.gpu_byte_limit = 4096
    limits.animation_decode_byte_limit = 4096
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(&store, limits, context.allocator))
    defer termattachment.store_destroy(&store)
    parser: gfxprotocol.Graphics_Parser_State
    testing.expect(t, gfxprotocol.graphics_parser_init(&parser, &store))
    defer gfxprotocol.graphics_parser_destroy(&parser)

    animated_bytes := GRAPHICS_SEMANTICS_TEST_ANIMATED_GIF
    graphics_semantics_test_expect_gif_preflight(
        t, &store, &parser, animated_bytes[:])
    static_bytes := GRAPHICS_SEMANTICS_TEST_STATIC_GIF
    graphics_semantics_test_expect_gif_preflight(
        t, &store, &parser, static_bytes[:])
    testing.expect_value(t, parser.gif_preflight_acceptance_count, u64(0))
    testing.expect_value(t, parser.gif_preflight_rejection_count, u64(0))
}
