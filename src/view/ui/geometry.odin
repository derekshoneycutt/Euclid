package ui

import input "../input"
import capturemodel "../capture/model"
import dynview "../../dynview"
import dyncompile "../../dynview/compile"
import dyncore "../../dynview/core"
import core "../../core"
import geometry "../../core/geometry"
import fmt "core:fmt"
import viewmodel "model"
import theme "theme"
import projection "../world/projection"
import uiwidgets "widgets"
import uisplitter "layout/splitter"
import uiaccordion "layout/accordion"
import uiregions "layout/regions"

// Geometry-stage result carried into static routing and later frame preparation.
Ui_Geometry_Preparation :: struct {
    pointer_capture: viewmodel.Ui_Press_Owner_State,
    compile_dynview: bool,
    splitters: uisplitter.Splitter_Preparation,
}

// Save the active accordion section into the current layout's independent memory.
ui_save_layout_section :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if runtime^.layout.current_layout_mode == .Portrait {
        runtime^.layout.portrait.active_section =
            runtime^.layout.active_accordion_section
    } else {
        runtime^.layout.landscape.active_section =
            runtime^.layout.active_accordion_section
    }
}

// Restore one resolved layout and its independent accordion memory.
ui_transition_layout :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    destination: viewmodel.Ui_Layout_Mode) -> bool {
    if destination == runtime^.layout.current_layout_mode {
        return false
    }
    ui_save_layout_section(runtime)
    ui_release_geometry_capture(runtime)
    runtime^.layout.accordion_transition.initialized = false
    runtime^.layout.current_layout_mode = destination
    if destination == .Portrait {
        if !runtime^.layout.portrait.entered {
            runtime^.layout.portrait.active_section = .View
        }
        runtime^.layout.active_accordion_section =
            runtime^.layout.portrait.active_section
        runtime^.layout.portrait.entered = true
    } else {
        runtime^.layout.active_accordion_section =
            runtime^.layout.landscape.active_section
    }
    _ = ui_publish_presentation_visibility(
        &runtime^.layout, &runtime^.presentation,
        &runtime^.input, &runtime^.terminal)
    return true
}

// Apply one logical extent and derive active-layout split pixels from intent.
ui_apply_window_metrics :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    metrics: viewmodel.Ui_Window_Metrics) -> bool {
    changed := runtime^.layout.window != metrics
    if changed {
        ui_release_geometry_capture(runtime)
        runtime^.layout.window = metrics
    }
    resolved := uiregions.resolve_layout_mode(runtime^.layout.layout_preference,
        runtime^.layout.current_layout_mode, f32(metrics.width), f32(metrics.height))
    transitioned := ui_transition_layout(runtime, resolved)
    if resolved == .Portrait {
        runtime^.layout.vertical_split_x = f32(metrics.width)
        runtime^.layout.horizontal_split_y = uisplitter.splitter_clamp_horizontal(
            runtime^.layout.portrait.world_height_ratio *
                f32(metrics.height), metrics.height)
    } else {
        runtime^.layout.vertical_split_x = uisplitter.splitter_clamp_vertical(
            runtime^.layout.landscape.vertical_ratio *
                f32(metrics.width), metrics.width)
        runtime^.layout.horizontal_split_y = uisplitter.splitter_clamp_horizontal(
            runtime^.layout.landscape.horizontal_ratio *
                f32(metrics.height), metrics.height)
    }
    return changed || transitioned
}

// prepare_ui_accordion_geometry publishes full-size portrait content and reveal geometry.
prepare_ui_accordion_geometry :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, frame: input.Input_Frame) {
    sections := uiaccordion.accordion_section_descriptors(
        runtime^.layout.current_layout_mode, "")
    _ = uiaccordion.accordion_transition_layout({
        panel = geometry.Rectangle(runtime^.layout.ui_regions.accordion_rect),
        mouse_input = frame,
        transition = &runtime^.layout.accordion_transition,
        reduce_motion = uiaccordion.ui_reduced_motion(
            runtime^.preferences.values.interface.reduce_motion,
            runtime^.platform_reduce_motion),
    }, sections, runtime^.layout.active_accordion_section)
    if runtime^.layout.current_layout_mode == .Portrait {
        runtime^.layout.ui_regions.text_rect =
            geometry.Rectangle(uiaccordion.accordion_content_rect(
                &runtime^.layout, .View))
        runtime^.layout.ui_regions.terminal_rect =
            uiregions.layout_terminal_rect(runtime^.layout.ui_regions.text_rect)
    }
    _ = ui_publish_presentation_visibility(
        &runtime^.layout, &runtime^.presentation,
        &runtime^.input, &runtime^.terminal)
}

// Prepare panel geometry while preserving capture identity from frame start.
prepare_ui_geometry :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: input.Input_Frame,
    frame_dt: f32) -> Ui_Geometry_Preparation {
    ui_runtime := &state^.ui_runtime
    capture_for_frame := ui_runtime^.input.press_owner
    splitters := uisplitter.update_splitters(uisplitter.Splitter_Update_Context{
        layout = &ui_runtime^.layout,
        press_owner = &ui_runtime^.input.press_owner,
        semantic_focus = ui_runtime^.semantic_focus,
        mouse_input = mouse_input,
        dt = min(f32(0.05), max(f32(0), frame_dt)),
        capture_view = capturemodel.gif_capture_view(&state^.gif_capture_status),
    })
    uisplitter.apply_splitter_preparation(&ui_runtime^.layout, splitters)
    ui_runtime^.input.cursor = splitters.cursor
    regions := uiregions.compute_ui_regions(ui_runtime.layout.current_layout_mode,
        f32(ui_runtime^.layout.window.width), f32(ui_runtime^.layout.window.height),
        ui_runtime.layout.vertical_split_x, ui_runtime.layout.horizontal_split_y)
    if !uiregions.validate_ui_regions(regions) {
        fmt.println("[ui] Warning: invalid regions; using baseline fallback")
        regions = uiregions.compute_ui_regions(.Landscape,
            f32(ui_runtime^.layout.window.width), f32(ui_runtime^.layout.window.height),
            ui_runtime.layout.vertical_split_x, ui_runtime.layout.horizontal_split_y)
    }
    state^.ui_runtime.layout.ui_regions = regions
    prepare_ui_accordion_geometry(ui_runtime, mouse_input)
    regions = ui_runtime^.layout.ui_regions
    projection.fit_iso_scale_to_viewport(
        &state^.iso_scale, regions.world_rect.width, regions.world_rect.height)

    track_ui_dynview_geometry(state, regions)
    return {capture_for_frame, dyncompile.compile_is_needed(&state^.dynview),
        splitters}
}

// Track the text panel and typography inputs that invalidate Dynview layout.
track_ui_dynview_geometry :: proc(
    state: ^core.Euclid_General_State,
    regions: viewmodel.Ui_Regions) {
    text_panel := uiwidgets.text_content_panel(regions.text_rect)
    dynview.track_panel(&state^.dynview, geometry.Rectangle(text_panel))
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    dynview.track_font(&state^.dynview, theme.ui_font_size(text_percent),
        theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, text_percent),
        theme.ui_scaled_metric(theme.TEXT_ROW_HEIGHT, text_percent))
    dynview.track_style(&state^.dynview, dyncore.DYNVIEW_STYLE_REVISION_PLAIN_TEXT)
}
