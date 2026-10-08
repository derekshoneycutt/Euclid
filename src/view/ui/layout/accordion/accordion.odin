package uiaccordion

import view_font "../../../font"
import geometry "../../../../core/geometry"
import viewmodel "../../model"
import uiwidgets "../../widgets"
import input "../../../input"
import uisemantics "../../semantics"
import theme "../../theme"

ACCORDION_MAX_SECTION_COUNT :: 4
ACCORDION_HEADER_ID_BASE :: 2201
INTERFACE_TRANSITION_SECONDS :: f64(0.180)
ACCORDION_TRANSITION_SECONDS :: INTERFACE_TRANSITION_SECONDS

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
    contents: [ACCORDION_MAX_SECTION_COUNT]geometry.Rectangle,
    clips: [ACCORDION_MAX_SECTION_COUNT]geometry.Rectangle,
}

// Prepared header interactions paired with their final frame layout.
Accordion_Preparation :: struct {
    sections: Accordion_Section_Set,
    layout: Accordion_Layout,
    headers: [ACCORDION_MAX_SECTION_COUNT]uiwidgets.Text_Button_Result,
}

// Shared dependencies for preparing and drawing accordion headers.
Accordion_Context :: struct {
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    semantic_focus: ^viewmodel.Ui_Semantic_Focus_State,
    active: viewmodel.Ui_Accordion_Section,
    font: view_font.Font_Face,
    font_resolver: view_font.Font_Resolver,
    transition: ^viewmodel.Ui_Accordion_Transition,
    reduce_motion: bool,
}

// accordion_semantic_id returns the stable identity for one section header.
accordion_semantic_id :: #force_inline proc(
    section: viewmodel.Ui_Accordion_Section) -> viewmodel.Ui_Node_Id {
    return {domain = .Accordion, local_id = u64(section) + 1}
}

// accordion_panel_semantic_id returns the stable identity for one section panel.
accordion_panel_semantic_id :: #force_inline proc(
    section: viewmodel.Ui_Accordion_Section) -> viewmodel.Ui_Node_Id {
    return {domain = .Accordion, local_id = u64(section) + 101}
}

// register_accordion_header publishes one operable header in visual order.
register_accordion_header :: proc(
    ctx: Accordion_Context,
    descriptor: Accordion_Section_Descriptor,
    rect: geometry.Rectangle,
    active: viewmodel.Ui_Accordion_Section,
    order: int) -> viewmodel.Ui_Node_Id {
    id := accordion_semantic_id(descriptor.section)
    controls: viewmodel.Ui_Node_Id
    states := viewmodel.Ui_Node_State{
        .Visible, .Enabled, .Focusable, .Tab_Stop}
    if descriptor.section == active {
        states += {.Selected, .Expanded}
        controls = accordion_panel_semantic_id(descriptor.section)
    }
    _ = uisemantics.semantic_register_control(ctx.semantic_focus, {
        id = id,
        controls = controls,
        role = .Accordion_Header,
        states = states,
        actions = {.Focus, .Activate, .Expand},
        region = .Accordion_Headers,
        traversal_order = u16(order),
        bounds = geometry.Rectangle(rect),
        clip_bounds = geometry.Rectangle(ctx.panel),
        label = descriptor.label,
    })
    return id
}

// register_accordion_panel publishes the active controlled content container.
register_accordion_panel :: proc(
    ctx: Accordion_Context, descriptor: Accordion_Section_Descriptor,
    rect: geometry.Rectangle) {
    id := accordion_panel_semantic_id(descriptor.section)
    clip := rect
    if ctx.transition != nil {
        clip = geometry.Rectangle(ctx.transition^.clips[int(descriptor.section)])
    }
    _ = uisemantics.semantic_register_control(ctx.semantic_focus, {
        id = id, role = .Panel, states = {.Visible, .Enabled},
        region = .Accordion_Content, bounds = geometry.Rectangle(rect),
        clip_bounds = geometry.Rectangle(clip), label = descriptor.label,
    })
    if ctx.semantic_focus != nil {
        ctx.semantic_focus^.staging_accordion_parent = id
        ctx.semantic_focus^.staging_accordion_clip = geometry.Rectangle(clip)
        ctx.semantic_focus^.staging_accordion_clip_set = true
    }
}

// Return landscape descriptors borrowing caller-resolved labels.
accordion_landscape_sections :: proc(
    labels: [3]string = {}) -> Accordion_Section_Set {
    return {
        items = {
            {section = .Library, label = labels[0]},
            {section = .Save_Gif, label = labels[1]},
            {section = .Settings, label = labels[2]},
            {},
        },
        count = 3,
    }
}

// Return portrait descriptors borrowing the caller-resolved title and labels.
accordion_portrait_sections :: proc(
    title: string, labels: [3]string = {}) -> Accordion_Section_Set {
    utilities := accordion_landscape_sections(labels)
    return {
        items = {
            {section = .View, label = title},
            utilities.items[0],
            utilities.items[1],
            utilities.items[2],
        },
        count = 4,
    }
}


// Construct geometry-only or caller-labelled sections without retaining their bytes.
accordion_section_descriptors :: proc(
    mode: viewmodel.Ui_Layout_Mode, title: string,
    labels: [3]string = {}) -> Accordion_Section_Set {
    if mode == .Portrait {
        return accordion_portrait_sections(title, labels)
    }
    return accordion_landscape_sections(labels)
}

// Return the active descriptor index, falling back to the first supplied section.
accordion_section_index :: proc(
    sections: Accordion_Section_Set,
    active: viewmodel.Ui_Accordion_Section) -> int {
    for index in 0..<sections.count {
        if sections.items[index].section == active {
            return index
        }
    }
    return 0
}

// Place ordered headers around one flexible active content rectangle.
accordion_layout :: proc(
    panel: geometry.Rectangle,
    sections: Accordion_Section_Set,
    active: viewmodel.Ui_Accordion_Section) -> Accordion_Layout {
    inner := panel
    inner.x += theme.ACCORDION_PANEL_INSET
    inner.y += theme.ACCORDION_PANEL_INSET
    inner.width = max(f32(0), inner.width - theme.ACCORDION_PANEL_INSET * 2)
    inner.height = max(f32(0), inner.height - theme.ACCORDION_PANEL_INSET * 2)
    content_height := max(
        inner.height - theme.ACCORDION_HEADER_HEIGHT * f32(sections.count), 0)
    result := Accordion_Layout{}
    cursor_y := inner.y
    active_index := accordion_section_index(sections, active)
    for section_index in 0..<sections.count {
        result.headers[section_index] = {
            inner.x, cursor_y, inner.width, theme.ACCORDION_HEADER_HEIGHT}
        cursor_y += theme.ACCORDION_HEADER_HEIGHT
        if section_index == active_index {
            result.content = {inner.x, cursor_y, inner.width, content_height}
            result.contents[int(active)] = result.content
            result.clips[int(active)] = result.content
            cursor_y += content_height
        }
    }
    return result
}

// accordion_transition_sample advances all reveal heights with one shared ease-out.
accordion_transition_sample :: proc(
    transition: ^viewmodel.Ui_Accordion_Transition, now_seconds: f64) {
    if !transition^.running {
        return
    }
    progress := clamp((now_seconds - transition^.start_seconds) /
        ACCORDION_TRANSITION_SECONDS, 0, 1)
    if now_seconds >= transition^.start_seconds + ACCORDION_TRANSITION_SECONDS {
        progress = 1
    }
    remaining := 1 - interface_motion_ease(transition^.start_seconds, now_seconds)
    height := max(f32(0), transition^.panel.height - theme.ACCORDION_PANEL_INSET * 2 -
        theme.ACCORDION_HEADER_HEIGHT * f32(transition^.section_count))
    transition^.heights = {}
    transferred: f32
    for start_height, index in transition^.start_heights {
        if index != int(transition^.selected) {
            transition^.heights[index] = start_height * remaining
            transferred += transition^.heights[index]
        }
    }
    transition^.heights[int(transition^.selected)] = max(f32(0), height - transferred)
    transition^.running = progress < 1
}

// interface_motion_ease gives bounded cubic ease-out independent of simulation time.
interface_motion_ease :: proc(start_seconds, now_seconds: f64) -> f32 {
    if now_seconds >= start_seconds + INTERFACE_TRANSITION_SECONDS {
        return 1
    }
    progress := clamp((now_seconds - start_seconds) / INTERFACE_TRANSITION_SECONDS, 0, 1)
    return f32(1 - (1 - progress) * (1 - progress) * (1 - progress))
}

// ui_reduced_motion combines explicit interface intent with independent platform policy.
ui_reduced_motion :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime^.settings_preferences.interface.reduce_motion ||
        runtime^.platform_reduce_motion
}

// accordion_transition_settle assigns the entire available height without animation.
accordion_transition_settle :: proc(
    transition: ^viewmodel.Ui_Accordion_Transition, panel: geometry.Rectangle,
    sections: Accordion_Section_Set, selected: viewmodel.Ui_Accordion_Section) {
    transition^ = {
        initialized = true, panel = geometry.Rectangle(panel),
        section_count = sections.count, selected = selected,
    }
    transition^.heights[int(selected)] = max(f32(0),
        panel.height - theme.ACCORDION_PANEL_INSET * 2 -
        theme.ACCORDION_HEADER_HEIGHT * f32(sections.count))
}

// accordion_visual_layout separates full-size child layout from bounded reveal clips.
accordion_visual_layout :: proc(
    panel: geometry.Rectangle, sections: Accordion_Section_Set,
    transition: ^viewmodel.Ui_Accordion_Transition) -> Accordion_Layout {
    inner := geometry.Rectangle{panel.x + theme.ACCORDION_PANEL_INSET,
        panel.y + theme.ACCORDION_PANEL_INSET,
        max(f32(0), panel.width - theme.ACCORDION_PANEL_INSET * 2),
        max(f32(0), panel.height - theme.ACCORDION_PANEL_INSET * 2)}
    content_height := max(f32(0),
        inner.height - theme.ACCORDION_HEADER_HEIGHT * f32(sections.count))
    result: Accordion_Layout
    cursor_y := inner.y
    for index in 0..<sections.count {
        descriptor := sections.items[index]
        section := int(descriptor.section)
        result.headers[index] = {
            inner.x, cursor_y, inner.width, theme.ACCORDION_HEADER_HEIGHT}
        cursor_y += theme.ACCORDION_HEADER_HEIGHT
        result.contents[section] = {inner.x, cursor_y, inner.width, content_height}
        result.clips[section] = {
            inner.x, cursor_y, inner.width, transition^.heights[section]}
        cursor_y += transition^.heights[section]
    }
    result.content = result.contents[int(transition^.selected)]
    for index in 0..<ACCORDION_MAX_SECTION_COUNT {
        transition^.contents[index] = geometry.Rectangle(result.contents[index])
        transition^.clips[index] = geometry.Rectangle(result.clips[index])
    }
    return result
}

// accordion_transition_layout samples before retargeting so interruptions stay continuous.
accordion_transition_layout :: proc(
    ctx: Accordion_Context, sections: Accordion_Section_Set,
    selected: viewmodel.Ui_Accordion_Section) -> Accordion_Layout {
    transition := ctx.transition
    if transition == nil {
        return accordion_layout(ctx.panel, sections, selected)
    }
    if !transition^.initialized || transition^.panel != geometry.Rectangle(ctx.panel) ||
        transition^.section_count != sections.count || ctx.reduce_motion {
        accordion_transition_settle(transition, ctx.panel, sections, selected)
    } else {
        accordion_transition_sample(transition, ctx.mouse_input.sample_time_seconds)
        if transition^.selected != selected {
            transition^.start_heights = transition^.heights
            transition^.selected = selected
            transition^.start_seconds = ctx.mouse_input.sample_time_seconds
            transition^.running = true
        }
    }
    return accordion_visual_layout(ctx.panel, sections, transition)
}

// accordion_content_rect returns prepared child geometry, falling back before first frame.
accordion_content_rect :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    section: viewmodel.Ui_Accordion_Section) -> geometry.Rectangle {
    if runtime^.accordion_transition.initialized {
        return geometry.Rectangle(runtime^.accordion_transition.contents[int(section)])
    }
    sections := accordion_section_descriptors(runtime^.current_layout_mode, "")
    return accordion_layout(
        geometry.Rectangle(runtime^.ui_regions.accordion_rect), sections, section).content
}

// accordion_content_clip exposes only the visible part of a selected child's layout.
accordion_content_clip :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    section: viewmodel.Ui_Accordion_Section) -> geometry.Rectangle {
    if runtime^.accordion_transition.initialized {
        return geometry.Rectangle(runtime^.accordion_transition.clips[int(section)])
    }
    return accordion_content_rect(runtime, section)
}

// Build one full-width accordion header button.
accordion_header_params :: proc(
    ctx: Accordion_Context,
    descriptor: Accordion_Section_Descriptor,
    rect: geometry.Rectangle,
    order: u16) -> uiwidgets.Text_Button_Params {
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
            states = uiwidgets.button_semantic_states(true),
            region = .Accordion_Headers,
            traversal_order = order,
            clip_bounds = geometry.Rectangle(ctx.panel),
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
        result^.headers[section_index] = uiwidgets.update_text_button(
            accordion_header_params(
                ctx, descriptor, result^.layout.headers[section_index],
                u16(section_index)),
            ctx.press_owner)
        id := accordion_semantic_id(descriptor.section)
        if result^.headers[section_index].action.activated ||
           uisemantics.semantic_command_requested(ctx.semantic_focus, id, .Expand) {
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
        _ = uisemantics.semantic_focus_for_press(ctx.semantic_focus, ctx.press_owner,
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
        layout = accordion_transition_layout(ctx, sections, active^),
    }
    selected := prepare_accordion_header_interactions(
        ctx, sections, &result, active^)
    if selected != active^ {
        active^ = selected
        result.layout = accordion_transition_layout(ctx, sections, selected)
        for section_index in 0..<sections.count {
            result.headers[section_index].button_drawn_rect =
                result.layout.headers[section_index]
        }
    }
    selected_index := accordion_section_index(sections, selected)
    register_accordion_panel(
        ctx, sections.items[selected_index], result.layout.content)
    register_accordion_headers(ctx, sections, &result, selected)
    return result
}
