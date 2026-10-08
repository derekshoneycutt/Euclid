package ui

import native "../native"
import core "../../core"
import geometry "../../core/geometry"
import contentdata "../../core/content"
import worldmodel "../world/model"
import viewmodel "model"
import theme "theme"
import viewtext "text"
import viewmessages "../messages"
import uisemantics "semantics"
import uiwidgets "widgets"
import uiaccordion "layout/accordion"
import uisettings "settings"
import uigif "gif"
import uilibrary "library"
import uipresentation "presentation"
import uiterminal "terminal"

// draw_encoded_panel_geometry encodes visible composition backgrounds without text.
draw_encoded_panel_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: Ui_Control_Preparation) {
    regions := state^.ui_runtime.ui_regions
    window := state^.ui_runtime.window
    if state^.ui_runtime.current_layout_mode == .Portrait {
        _ = native.draw_encoder_rectangle(encoder, {0, regions.world_rect.height,
            f32(window.width), f32(window.height) - regions.world_rect.height},
            theme.UI_BACK_COLOR)
        draw_encoded_accordion_geometry(state, encoder, controls)
        return
    }
    _ = native.draw_encoder_rectangle(encoder, {
        regions.world_rect.x,
        regions.world_rect.y + regions.world_rect.height,
        regions.world_rect.width,
        f32(window.height) - regions.world_rect.height,
    }, theme.UI_BACK_COLOR)
    _ = native.draw_encoder_rectangle(encoder, {
        regions.world_rect.x + regions.world_rect.width, 0,
        f32(window.width) - regions.world_rect.width, f32(window.height),
    }, theme.UI_BACK_COLOR)
    uipresentation.draw_encoded_presentation_geometry(
        state, encoder, regions.text_rect)
    draw_encoded_accordion_geometry(state, encoder, controls)
}


// draw_encoded_accordion_content encodes the active section's geometry.
draw_encoded_accordion_content :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: uiaccordion.Accordion_Layout, controls: Ui_Control_Preparation) {
    for index in 0..<controls.accordion.sections.count {
        descriptor := controls.accordion.sections.items[index]
        section := descriptor.section
        content := layout.contents[int(section)]
        clip := layout.clips[int(section)]
        if clip.width <= 0 || clip.height <= 0 {
            continue
        }
        _ = native.draw_encoder_push_scissor(encoder, clip)
        draw_encoded_accordion_child(state, encoder, section, content, controls)
        _ = native.draw_encoder_pop_scissor(encoder)
    }
}

// draw_encoded_accordion_child draws one full-size child beneath its reveal clip.
draw_encoded_accordion_child :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    section: viewmodel.Ui_Accordion_Section, content: geometry.Rectangle,
    controls: Ui_Control_Preparation) {
    _ = native.draw_encoder_rectangle(
        encoder, content, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, content, 1, theme.UI_BORDER_COLOR)
    switch section {
    case .View:
        uipresentation.draw_encoded_presentation_geometry(
            state, encoder, content)
    case .Library:
        uilibrary.draw_encoded_tree_geometry(state, encoder, controls.tree)
    case .Save_Gif:
        uigif.draw_encoded_gif_geometry(encoder, controls.gif)
    case .Settings:
        uisettings.draw_encoded_settings_geometry(encoder, controls.settings)
    }
}

// draw_encoded_accordion_headers encodes all section headers and disclosures.
draw_encoded_accordion_headers :: proc(
    encoder: ^native.Draw_Encoder, sections: uiaccordion.Accordion_Section_Set,
    layout: uiaccordion.Accordion_Layout, active: viewmodel.Ui_Accordion_Section) {
    for index in 0..<sections.count {
        header := layout.headers[index]
        expanded := sections.items[index].section == active
        fill := worldmodel.BACKGROUND_COLOR
        if expanded {
            fill = theme.UI_COMPONENT_BACKGROUND_COLOR
        }
        _ = native.draw_encoder_rectangle(
            encoder, geometry.Rectangle(header), fill)
        _ = native.draw_encoder_rectangle_outline(
            encoder, geometry.Rectangle(header), 1, theme.UI_BORDER_COLOR)
        icon_size := min(theme.ACCORDION_DISCLOSURE_SIZE, header.height)
        icon := geometry.Rectangle{header.x + theme.ACCORDION_HEADER_PADDING,
            header.y + (header.height - icon_size) * 0.5, icon_size, icon_size}
        uiwidgets.draw_encoded_disclosure(encoder, geometry.Rectangle(icon), expanded)
    }
}

// draw_encoded_accordion_geometry encodes panel chrome while labels stay deferred.
draw_encoded_accordion_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: Ui_Control_Preparation) {
    runtime := &state^.ui_runtime
    panel := runtime^.ui_regions.accordion_rect
    _ = native.draw_encoder_rectangle(
        encoder, geometry.Rectangle(panel), worldmodel.BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, geometry.Rectangle(panel), 1, theme.UI_BORDER_COLOR)
    sections := controls.accordion.sections
    layout := controls.accordion.layout
    draw_encoded_accordion_content(state, encoder, layout, controls)
    draw_encoded_accordion_headers(
        encoder, sections, layout, runtime^.active_accordion_section)
}


// draw_encoded_panel_text emits non-presentation labels for the active UI layout.
draw_encoded_panel_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: Ui_Control_Preparation) {
    sections := controls.accordion.sections
    layout := controls.accordion.layout
    for index in 0..<sections.count {
        header := layout.headers[index]
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            sections.items[index].label,
            header.x + theme.ACCORDION_HEADER_PADDING + theme.ACCORDION_DISCLOSURE_SIZE +
                theme.ACCORDION_HEADER_PADDING,
            header.y + (header.height - theme.TREE_FONT_SIZE) * 0.5)
    }
    for index in 0..<sections.count {
        section := sections.items[index].section
        clip := layout.clips[int(section)]
        if clip.width <= 0 || clip.height <= 0 {
            continue
        }
        _ = native.draw_encoder_push_scissor(encoder, clip)
        draw_encoded_accordion_child_text(state, encoder, section,
            layout.contents[int(section)], controls)
        _ = native.draw_encoder_pop_scissor(encoder)
    }
    draw_encoded_overlay_text(state, encoder)
}

// draw_encoded_accordion_child_text shares the prepared full-size layout with geometry.
draw_encoded_accordion_child_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    section: viewmodel.Ui_Accordion_Section, content: geometry.Rectangle,
    controls: Ui_Control_Preparation) {
    switch section {
    case .Library:
        uilibrary.draw_encoded_library_search_geometry(
            state, encoder, controls.library_search)
        uilibrary.draw_encoded_library_search_text(
            state, encoder, controls.library_search)
        uilibrary.draw_encoded_tree_text(state, encoder, controls.tree)
    case .Save_Gif:
        uigif.draw_encoded_gif_text(state, encoder,
            content, controls.gif)
    case .Settings:
        uisettings.draw_encoded_settings_text(
            state, encoder, controls.settings)
    case .View:
    }
}

// draw_encoded_overlay_text emits transient overlay labels outside accordion panels.
draw_encoded_overlay_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    runtime := &state^.ui_runtime
    if !runtime^.display_fps {
        return
    }
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    fps := viewmessages.shell_format(state, .Fps_Overlay,
        []contentdata.Content_Format_Argument{{"fps", state^.telemetry.fps_avg_live}},
        storage[:])
    viewtext.draw_encoded_label(&state^.font_cache, encoder, fps, 8, 8)
}

// draw_encoded_focus_outline emits the current keyboard-visible focus bounds.
draw_encoded_focus_outline :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    encoder: ^native.Draw_Encoder) {
    semantic := runtime^.semantic_focus
    if semantic == nil || !semantic^.window_focused ||
        semantic^.focus_origin != .Keyboard {return}
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, semantic^.logical_focus)
    if index < 0 || .Focus_Visible not_in snapshot^.nodes[index].states {
        return
    }
    node := snapshot^.nodes[index]
    _ = native.draw_encoder_push_scissor(encoder, node.clip_bounds)
    _ = native.draw_encoder_rectangle_outline(
        encoder, node.bounds, 2, theme.UI_TEXT_COLOR)
    _ = native.draw_encoder_pop_scissor(encoder)
}


// draw_encoded_view_content separates a render-only portrait tail from logical visibility.
draw_encoded_view_content :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    terminal: uiterminal.Terminal_Prepared_Frame,
    presentation: uipresentation.Presentation_Preparation) {
    runtime := &state^.ui_runtime
    panel := geometry.Rectangle(runtime^.ui_regions.text_rect)
    clip := uiaccordion.ui_presentation_clip(runtime, panel)
    if clip.width <= 0 || clip.height <= 0 {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, clip)
    if uiterminal.is_terminal_selected(state) {
        prepared := terminal
        if !uipresentation.ui_presentation_is_visible(runtime) {
            prepared = uiterminal.terminal_prepare_visual(
                state, uiterminal.terminal_content_panel(panel))
        }
        uiterminal.terminal_draw_encoded(state, encoder, prepared)
    } else {
        prepared := presentation
        if !uipresentation.ui_presentation_is_visible(runtime) {
            prepared = uipresentation.prepare_presentation_visual(state, panel)
        }
        uipresentation.draw_encoded_presentation_text(state, encoder, prepared)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}
