package ui

import native "../native"

import viewmodel "../model"

import view_core "../core"
import view_font "../font"

import rl "vendor:raylib"

ACCORDION_MAX_SECTION_COUNT :: 4
ACCORDION_HEADER_ID_BASE :: 2201

// One ordered accordion section and its frame-borrowed display label.
Accordion_Section_Descriptor :: struct {
    section: viewmodel.Ui_Accordion_Section,
    label: string,
}

// Bounded ordered section descriptors for one layout composition.
Accordion_Section_Set :: struct {
    items: [ACCORDION_MAX_SECTION_COUNT]Accordion_Section_Descriptor,
    count: int,
}

// Geometry for all accordion headers and the one expanded content region.
Accordion_Layout :: struct {
    headers: [ACCORDION_MAX_SECTION_COUNT]rl.Rectangle,
    content: rl.Rectangle,
}

// Prepared header interactions paired with their final frame layout.
Accordion_Preparation :: struct {
    sections: Accordion_Section_Set,
    layout: Accordion_Layout,
    headers: [ACCORDION_MAX_SECTION_COUNT]Text_Button_Result,
}

// Shared dependencies for preparing and drawing accordion headers.
Accordion_Context :: struct {
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    active: viewmodel.Ui_Accordion_Section,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
}

// Return the three utility sections used by landscape composition.
accordion_landscape_sections :: proc() -> Accordion_Section_Set {
    return {
        items = {
            {section = .Library, label = "Library"},
            {section = .Save_Gif, label = "Save GIF"},
            {section = .Settings, label = "Settings"},
            {},
        },
        count = 3,
    }
}

// Return the selected View followed by portrait's three utility sections.
accordion_portrait_sections :: proc(title: string) -> Accordion_Section_Set {
    view_title := title
    if len(view_title) == 0 { view_title = "Animation" }
    return {
        items = {
            {section = .View, label = view_title},
            {section = .Library, label = "Library"},
            {section = .Save_Gif, label = "Save GIF"},
            {section = .Settings, label = "Settings"},
        },
        count = 4,
    }
}

// Return ordered descriptors for the resolved layout without retaining title storage.
accordion_sections_for_layout :: proc(
    mode: viewmodel.Ui_Layout_Mode, title: string) -> Accordion_Section_Set {
    if mode == .Portrait { return accordion_portrait_sections(title) }
    return accordion_landscape_sections()
}

// Return the active descriptor index, falling back to the first supplied section.
accordion_section_index :: proc(
    sections: Accordion_Section_Set,
    active: viewmodel.Ui_Accordion_Section) -> int {
    for index in 0..<sections.count {
        if sections.items[index].section == active { return index }
    }
    return 0
}

// Place ordered headers around one flexible active content rectangle.
accordion_layout :: proc(
    panel: rl.Rectangle,
    sections: Accordion_Section_Set,
    active: viewmodel.Ui_Accordion_Section) -> Accordion_Layout {
    inner := container_geometry(panel, ACCORDION_PANEL_INSET).inner_rect
    content_height := max(
        inner.height - ACCORDION_HEADER_HEIGHT * f32(sections.count), 0)
    result := Accordion_Layout{}
    cursor_y := inner.y
    active_index := accordion_section_index(sections, active)
    for section_index in 0..<sections.count {
        result.headers[section_index] = {
            inner.x, cursor_y, inner.width, ACCORDION_HEADER_HEIGHT}
        cursor_y += ACCORDION_HEADER_HEIGHT
        if section_index == active_index {
            result.content = {inner.x, cursor_y, inner.width, content_height}
            cursor_y += content_height
        }
    }
    return result
}

// Build one full-width accordion header button.
accordion_header_params :: proc(
    ctx: Accordion_Context,
    descriptor: Accordion_Section_Descriptor,
    rect: rl.Rectangle) -> Text_Button_Params {
    return {
        id = ACCORDION_HEADER_ID_BASE + int(descriptor.section),
        rect = rect,
        label = descriptor.label,
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
    sections: Accordion_Section_Set,
    active: ^viewmodel.Ui_Accordion_Section) -> Accordion_Preparation {
    active_index := accordion_section_index(sections, active^)
    active^ = sections.items[active_index].section
    result := Accordion_Preparation{
        sections = sections,
        layout = accordion_layout(ctx.panel, sections, active^),
    }
    selected := active^
    for section_index in 0..<sections.count {
        descriptor := sections.items[section_index]
        result.headers[section_index] = update_text_button(
            accordion_header_params(
                ctx, descriptor, result.layout.headers[section_index]),
            ctx.press_owner)
        if result.headers[section_index].clicked {
            selected = descriptor.section
        }
    }
    if selected != active^ {
        active^ = selected
        result.layout = accordion_layout(ctx.panel, sections, selected)
        for section_index in 0..<sections.count {
            result.headers[section_index].button_drawn_rect =
                result.layout.headers[section_index]
        }
    }
    return result
}

// Draw one accordion header with disclosure and selected-state treatment.
draw_accordion_header :: proc(
    ctx: Accordion_Context,
    descriptor: Accordion_Section_Descriptor,
    result: Text_Button_Result) {
    params := accordion_header_params(ctx, descriptor, result.button_drawn_rect)
    colors := text_button_colors(params, result.hovered, result.pressed)
    expanded := descriptor.section == ctx.active
    if expanded {
        colors.background = native.to_raylib_color(UI_COMPONENT_BACKGROUND_COLOR)
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
        text = descriptor.label,
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
    for section_index in 0..<prepared.sections.count {
        draw_accordion_header(
            ctx, prepared.sections.items[section_index],
            prepared.headers[section_index])
    }
}