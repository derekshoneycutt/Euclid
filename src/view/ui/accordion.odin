package ui

import viewmodel "../model"

import view_font "../font"
import geometry "../../core/geometry"

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
    headers: [ACCORDION_MAX_SECTION_COUNT]geometry.Rectangle,
    content: geometry.Rectangle,
}

// Prepared header interactions paired with their final frame layout.
Accordion_Preparation :: struct {
    sections: Accordion_Section_Set,
    layout: Accordion_Layout,
    headers: [ACCORDION_MAX_SECTION_COUNT]Text_Button_Result,
}

// Shared dependencies for preparing and drawing accordion headers.
Accordion_Context :: struct {
    panel: geometry.Rectangle,
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
    panel: geometry.Rectangle,
    sections: Accordion_Section_Set,
    active: viewmodel.Ui_Accordion_Section) -> Accordion_Layout {
    inner := panel
    inner.x += ACCORDION_PANEL_INSET
    inner.y += ACCORDION_PANEL_INSET
    inner.width = max(f32(0), inner.width - ACCORDION_PANEL_INSET * 2)
    inner.height = max(f32(0), inner.height - ACCORDION_PANEL_INSET * 2)
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
    rect: geometry.Rectangle) -> Text_Button_Params {
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
        layout = accordion_layout(
            ctx.panel, sections, active^),
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
        result.layout = accordion_layout(
            ctx.panel, sections, selected)
        for section_index in 0..<sections.count {
            result.headers[section_index].button_drawn_rect =
                result.layout.headers[section_index]
        }
    }
    return result
}
