package ui

import viewmodel "../model"

import view_core "../core"
import view_font "../font"

import rl "vendor:raylib"

ACCORDION_SECTION_COUNT :: 3
ACCORDION_HEADER_ID_BASE :: 2201

// Geometry for all accordion headers and the one expanded content region.
Accordion_Layout :: struct {
    headers: [ACCORDION_SECTION_COUNT]rl.Rectangle,
    content: rl.Rectangle,
}

// Prepared header interactions paired with their final frame layout.
Accordion_Preparation :: struct {
    layout: Accordion_Layout,
    headers: [ACCORDION_SECTION_COUNT]Text_Button_Result,
}

// Shared dependencies for preparing and drawing accordion headers.
Accordion_Context :: struct {
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    active: viewmodel.Ui_Accordion_Section,
    font: rl.Font,
    font_resolver: view_font.Font_Resolver,
}

// Return the user-facing label for one accordion section.
accordion_section_label :: proc(section: viewmodel.Ui_Accordion_Section) -> string {
    switch section {
    case .Library:
        return "Library"
    case .Save_Gif:
        return "Save GIF"
    case .Settings:
        return "Settings"
    }
    return ""
}

// Place ordered headers around one flexible active content rectangle.
accordion_layout :: proc(
    panel: rl.Rectangle,
    active: viewmodel.Ui_Accordion_Section) -> Accordion_Layout {
    inner := container_geometry(panel, ACCORDION_PANEL_INSET).inner_rect
    content_height := max(
        inner.height - ACCORDION_HEADER_HEIGHT * ACCORDION_SECTION_COUNT, 0)
    result := Accordion_Layout{}
    cursor_y := inner.y
    for section_index in 0..<ACCORDION_SECTION_COUNT {
        section := viewmodel.Ui_Accordion_Section(section_index)
        result.headers[section_index] = {
            inner.x, cursor_y, inner.width, ACCORDION_HEADER_HEIGHT}
        cursor_y += ACCORDION_HEADER_HEIGHT
        if section == active {
            result.content = {inner.x, cursor_y, inner.width, content_height}
            cursor_y += content_height
        }
    }
    return result
}

// Build one full-width accordion header button.
accordion_header_params :: proc(
    ctx: Accordion_Context,
    section: viewmodel.Ui_Accordion_Section,
    rect: rl.Rectangle) -> Text_Button_Params {
    return {
        id = ACCORDION_HEADER_ID_BASE + int(section),
        rect = rect,
        label = accordion_section_label(section),
        enabled = true,
        mouse = ctx.mouse_input,
        interaction_space_rect = ctx.panel,
        interaction_enabled = true,
        font = ctx.font,
        font_resolver = ctx.font_resolver,
    }
}

// Resolve header interaction and publish exactly one expanded section.
prepare_accordion :: proc(
    ctx: Accordion_Context,
    active: ^viewmodel.Ui_Accordion_Section) -> Accordion_Preparation {
    result := Accordion_Preparation{layout = accordion_layout(ctx.panel, active^)}
    selected := active^
    for section_index in 0..<ACCORDION_SECTION_COUNT {
        section := viewmodel.Ui_Accordion_Section(section_index)
        result.headers[section_index] = update_text_button(
            accordion_header_params(ctx, section, result.layout.headers[section_index]),
            ctx.press_owner)
        if result.headers[section_index].clicked {
            selected = section
        }
    }
    if selected != active^ {
        active^ = selected
        result.layout = accordion_layout(ctx.panel, selected)
        for section_index in 0..<ACCORDION_SECTION_COUNT {
            result.headers[section_index].button_drawn_rect =
                result.layout.headers[section_index]
        }
    }
    return result
}

// Draw one accordion header with disclosure and selected-state treatment.
draw_accordion_header :: proc(
    ctx: Accordion_Context,
    section: viewmodel.Ui_Accordion_Section,
    result: Text_Button_Result) {
    params := accordion_header_params(ctx, section, result.button_drawn_rect)
    colors := text_button_colors(params, result.hovered, result.pressed)
    expanded := section == ctx.active
    if expanded {
        colors.background = UI_COMPONENT_BACKGROUND_COLOR
    }
    rl.DrawRectangleRec(result.button_drawn_rect, colors.background)
    rl.DrawRectangleLinesEx(result.button_drawn_rect, 1, colors.border)
    icon_size := min(ACCORDION_DISCLOSURE_SIZE, result.button_drawn_rect.height)
    icon_rect := rl.Rectangle{
        result.button_drawn_rect.x + ACCORDION_HEADER_PADDING,
        result.button_drawn_rect.y + (result.button_drawn_rect.height - icon_size) * 0.5,
        icon_size,
        icon_size,
    }
    view_core.draw_tree_disclosure_icon(icon_rect, expanded, colors.foreground)
    view_core.ui_text_shaped({
        resolver = ctx.font_resolver,
        key = .Regular,
        text = accordion_section_label(section),
        position = {
            icon_rect.x + icon_rect.width + ACCORDION_HEADER_LABEL_GAP,
            result.button_drawn_rect.y + ACCORDION_HEADER_TEXT_OFFSET_Y,
        },
        color = colors.foreground,
        font = view_core.ui_text_font(ctx.font),
    })
}

// Draw all accordion headers around the active child panel.
draw_accordion :: proc(
    ctx: Accordion_Context,
    prepared: Accordion_Preparation) {
    for section_index in 0..<ACCORDION_SECTION_COUNT {
        section := viewmodel.Ui_Accordion_Section(section_index)
        draw_accordion_header(ctx, section, prepared.headers[section_index])
    }
}