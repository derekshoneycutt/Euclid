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
import uisharing "sharing"
import uilibrary "library"
import uipresentation "presentation"
import uiterminal "terminal"
import font "../font"

// draw_encoded_panel_geometry encodes visible composition backgrounds without text.
draw_encoded_panel_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: ^Ui_Control_Preparation) {
    regions := state^.ui_runtime.layout.ui_regions
    window := state^.ui_runtime.layout.window
    if state^.ui_runtime.layout.current_layout_mode == .Portrait {
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
    if state^.julia_interface != nil {
        _ = uiwidgets.surface_shadow_draw(
            encoder, geometry.Rectangle(regions.text_rect), .Low)
    }
    uipresentation.draw_encoded_presentation_geometry(
        state, encoder, regions.text_rect)
    draw_encoded_accordion_geometry(state, encoder, controls)
}


// draw_encoded_accordion_content encodes the active section's geometry.
draw_encoded_accordion_content :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    layout: uiaccordion.Accordion_Layout, controls: ^Ui_Control_Preparation) {
    for index in 0..<controls^.accordion.sections.count {
        descriptor := controls^.accordion.sections.items[index]
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
    controls: ^Ui_Control_Preparation) {
    _ = native.draw_encoder_rectangle(
        encoder, content, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, content, 1, theme.UI_BORDER_COLOR)
    switch section {
    case .View:
        uipresentation.draw_encoded_presentation_geometry(
            state, encoder, content)
    case .Library:
        uilibrary.draw_encoded_tree_geometry(state, encoder, &controls^.tree)
    case .Save_Gif:
        uisharing.draw_encoded_sharing_geometry(encoder, controls.sharing)
    case .Settings:
        uisettings.draw_encoded_settings_geometry(encoder, controls.settings)
    }
}

// draw_encoded_accordion_headers encodes all section headers and disclosures.
draw_encoded_accordion_headers :: proc(
    encoder: ^native.Draw_Encoder, sections: uiaccordion.Accordion_Section_Set,
    layout: uiaccordion.Accordion_Layout, active: viewmodel.Ui_Accordion_Section,
    scale := f32(1)) {
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
            encoder, geometry.Rectangle(header), scale, theme.UI_BORDER_COLOR)
        icon_size := min(theme.ACCORDION_DISCLOSURE_SIZE * scale, header.height)
        icon: geometry.Rectangle = {header.x + theme.ACCORDION_HEADER_PADDING * scale,
            header.y + (header.height - icon_size) * 0.5, icon_size, icon_size}
        uiwidgets.draw_encoded_disclosure(encoder, geometry.Rectangle(icon), expanded)
    }
}

// draw_encoded_accordion_geometry encodes panel chrome while labels stay deferred.
draw_encoded_accordion_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: ^Ui_Control_Preparation) {
    runtime := &state^.ui_runtime
    panel := runtime^.layout.ui_regions.accordion_rect
    _ = uiwidgets.surface_shadow_draw(
        encoder, geometry.Rectangle(panel), .Low)
    _ = native.draw_encoder_rectangle(
        encoder, geometry.Rectangle(panel), worldmodel.BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, geometry.Rectangle(panel),
        theme.ui_control_size_scale(
            runtime^.preferences.values.interface.control_size_percent),
        theme.UI_BORDER_COLOR)
    sections := controls^.accordion.sections
    layout := controls^.accordion.layout
    draw_encoded_accordion_content(state, encoder, layout, controls)
    draw_encoded_accordion_headers(
        encoder, sections, layout, runtime^.layout.active_accordion_section,
        runtime^.layout.accordion_transition.scale)
}


// draw_encoded_panel_text emits non-presentation labels for the active UI layout.
draw_encoded_panel_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    controls: ^Ui_Control_Preparation) {
    sections := controls^.accordion.sections
    layout := controls^.accordion.layout
    scale := theme.ui_control_size_scale(
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    for index in 0..<sections.count {
        header := layout.headers[index]
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            sections.items[index].label,
            header.x + scale * (theme.ACCORDION_HEADER_PADDING +
                theme.ACCORDION_DISCLOSURE_SIZE +
                theme.ACCORDION_HEADER_PADDING),
            header.y + (header.height - theme.ui_font_size(
                state^.ui_runtime.preferences.values.interface.text_size_percent)) * 0.5)
        if sections.items[index].error_indicator {
            center, radius := uiaccordion.accordion_error_indicator_geometry(header)
            _ = native.draw_encoder_circle(encoder, center, radius, theme.UI_ERROR_COLOR)
        }
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
    controls: ^Ui_Control_Preparation) {
    switch section {
    case .Library:
        uilibrary.draw_encoded_library_search_geometry(
            state, encoder, controls^.library_search)
        uilibrary.draw_encoded_library_search_text(
            state, encoder, controls^.library_search)
        uilibrary.draw_encoded_tree_text(state, encoder, &controls^.tree)
    case .Save_Gif:
        uisharing.draw_encoded_sharing_text(state, encoder,
            content, controls.sharing)
    case .Settings:
        uisettings.draw_encoded_settings_text(
            state, encoder, controls^.settings)
    case .View:
    }
}

// draw_encoded_overlay_text emits transient overlay labels outside accordion panels.
draw_encoded_overlay_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder) {
    runtime := &state^.ui_runtime
    if !runtime^.rendering.display_fps {
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
        semantic^.focus_origin != .Keyboard {
        return
    }
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, semantic^.logical_focus)
    if index < 0 || .Focus_Visible not_in snapshot^.nodes[index].states {
        return
    }
    node := snapshot^.nodes[index]
    _ = native.draw_encoder_push_scissor(encoder, node.clip_bounds)
    uiwidgets.draw_encoded_focus_ring(encoder, node.bounds,
        theme.ui_control_size_scale(
            runtime^.preferences.values.interface.control_size_percent))
    _ = native.draw_encoder_pop_scissor(encoder)
}


// draw_encoded_view_content separates a render-only portrait tail from logical visibility.
draw_encoded_view_content :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    terminal: uiterminal.Terminal_Prepared_Frame,
    presentation: uipresentation.Presentation_Preparation,
    effects: uipresentation.Presentation_Effects_Draw_Params) {
    runtime := &state^.ui_runtime
    panel := geometry.Rectangle(runtime^.layout.ui_regions.text_rect)
    clip := uiaccordion.ui_presentation_clip(&runtime^.layout, panel)
    if clip.width <= 0 || clip.height <= 0 {
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, clip)
    if uiterminal.is_terminal_selected(state) {
        draw_encoded_terminal_content(state, encoder, terminal, panel, effects)
    } else {
        prepared := presentation
        if !prepared.active ||
            !uipresentation.ui_presentation_is_visible(&runtime^.presentation) {
            prepared = uipresentation.prepare_presentation_visual(state, panel)
        }
        uipresentation.draw_encoded_presentation_text(state, encoder, prepared)
        if uipresentation.ui_presentation_is_visible(&runtime^.presentation) {
            uipresentation.presentation_draw_effects(
                encoder, prepared.scroll.view_rect, effects)
        }
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

// draw_encoded_terminal_content reveals sampled glyphs while keeping non-ink Terminal content immediate.
draw_encoded_terminal_content :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    terminal: uiterminal.Terminal_Prepared_Frame, panel: geometry.Rectangle,
    effects: uipresentation.Presentation_Effects_Draw_Params) {
    visible := uipresentation.ui_presentation_is_visible(&state^.ui_runtime.presentation)
    prepared := terminal
    if !visible {
        prepared = uiterminal.terminal_prepare_visual(
            state, uiterminal.terminal_content_panel(panel))
    }
    previous := encoder^.ink_sink
    sink: native.Draw_Ink_Sink = {
        user_data = &state^.font_cache,
        record = font.cache_ink_capture_sample,
        glyphs_only = true,
    }
    if effects.dust != nil && visible {
        sink.visibility_data = effects.dust
        sink.alpha = uipresentation.presentation_ink_alpha
    }
    native.draw_encoder_set_ink_sink(encoder, sink)
    uiterminal.terminal_draw_encoded(state, encoder, prepared)
    native.draw_encoder_set_ink_sink(encoder, previous)
    if visible {
        viewport := geometry.Rectangle(prepared.scroll.view_rect)
        if prepared.explorer_active {
            viewport = prepared.explorer.bounds
        } else if !prepared.available && effects.dust != nil {
            viewport = effects.dust^.viewport
        }
        uipresentation.presentation_draw_dust_clipped(encoder, viewport, effects)
    }
}
