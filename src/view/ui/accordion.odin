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
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    active: viewmodel.Ui_Accordion_Section,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
}

// accordion_semantic_id returns the stable identity for one section header.
accordion_semantic_id :: #force_inline proc(
    section: viewmodel.Ui_Accordion_Section) -> viewmodel.Ui_Node_Id {
    return {domain = .Accordion, local_id = u64(section) + 1}
}

// register_accordion_header publishes one operable header in visual order.
register_accordion_header :: proc(
    ctx: Accordion_Context,
    descriptor: Accordion_Section_Descriptor,
    rect: geometry.Rectangle,
    active: viewmodel.Ui_Accordion_Section,
    order: int) -> viewmodel.Ui_Node_Id {
    id := accordion_semantic_id(descriptor.section)
    states := viewmodel.Ui_Node_State{
        .Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.section == active {states += {.Selected, .Expanded}}
    _ = semantic_register_control(ctx.semantic_focus, {
        id = id,
        role = .Accordion_Header,
        states = states,
        actions = {.Focus, .Activate},
        region = .Accordion_Headers,
        traversal_order = u16(order),
        bounds = viewmodel.Rectangle(rect),
        clip_bounds = viewmodel.Rectangle(ctx.panel),
        label = descriptor.label,
    })
    return id
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
    rect: geometry.Rectangle,
    order: u16) -> Text_Button_Params {
    id := accordion_semantic_id(descriptor.section)
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
        semantics = {
            focus = ctx.semantic_focus,
            id = id,
            role = .Accordion_Header,
            states = button_semantic_states(true),
            region = .Accordion_Headers,
            traversal_order = order,
            clip_bounds = viewmodel.Rectangle(ctx.panel),
            label = descriptor.label,
        },
    }
}

// prepare_accordion_header_interactions resolves pointer and keyboard selection.
prepare_accordion_header_interactions :: proc(
    ctx: Accordion_Context, sections: Accordion_Section_Set,
    result: ^Accordion_Preparation,
    selected: viewmodel.Ui_Accordion_Section) -> viewmodel.Ui_Accordion_Section {
    resolved := selected
    for section_index in 0..<sections.count {
        descriptor := sections.items[section_index]
        result^.headers[section_index] = update_text_button(
            accordion_header_params(
                ctx, descriptor, result^.layout.headers[section_index],
                u16(section_index)),
            ctx.press_owner)
        if result^.headers[section_index].action.activated {
            resolved = descriptor.section
        }
    }
    return resolved
}

// register_accordion_headers publishes final geometry and pointer focus.
register_accordion_headers :: proc(
    ctx: Accordion_Context, sections: Accordion_Section_Set,
    result: ^Accordion_Preparation,
    selected: viewmodel.Ui_Accordion_Section) {
    for section_index in 0..<sections.count {
        descriptor := sections.items[section_index]
        id := register_accordion_header(ctx, descriptor,
            result^.layout.headers[section_index], selected, section_index)
        press_id := ACCORDION_HEADER_ID_BASE + int(descriptor.section)
        _ = semantic_focus_for_press(ctx.semantic_focus, ctx.press_owner,
            .Text_Button, press_id, id)
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
    selected := prepare_accordion_header_interactions(
        ctx, sections, &result, active^)
    if selected != active^ {
        active^ = selected
        result.layout = accordion_layout(
            ctx.panel, sections, selected)
        for section_index in 0..<sections.count {
            result.headers[section_index].button_drawn_rect =
                result.layout.headers[section_index]
        }
    }
    register_accordion_headers(ctx, sections, &result, selected)
    return result
}
