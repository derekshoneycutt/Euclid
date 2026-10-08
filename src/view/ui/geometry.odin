package ui

import input "../input"
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
import uipresentation "presentation"
import uilayout "layout"
import uiregions "layout/regions"

// Geometry-stage result carried into static routing and later frame preparation.
Ui_Geometry_Preparation :: struct {
    pointer_capture: viewmodel.Ui_Press_Owner_State,
    compile_dynview: bool,
    splitters: uisplitter.Splitter_Preparation,
}

// Save the active accordion section into the current layout's independent memory.
ui_save_layout_section :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if runtime^.current_layout_mode == .Portrait {
        runtime^.portrait.active_section = runtime^.active_accordion_section
    } else {
        runtime^.landscape.active_section = runtime^.active_accordion_section
    }
}

// Restore one resolved layout and its independent accordion memory.
ui_transition_layout :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    destination: viewmodel.Ui_Layout_Mode) -> bool {
    if destination == runtime^.current_layout_mode {
        return false
    }
    ui_save_layout_section(runtime)
    uilayout.ui_release_geometry_capture(runtime)
    runtime^.accordion_transition.initialized = false
    runtime^.current_layout_mode = destination
    if destination == .Portrait {
        if !runtime^.portrait.entered {
            runtime^.portrait.active_section = .View
        }
        runtime^.active_accordion_section = runtime^.portrait.active_section
        runtime^.portrait.entered = true
    } else {
        runtime^.active_accordion_section = runtime^.landscape.active_section
    }
    _ = uipresentation.ui_publish_presentation_visibility(runtime)
    return true
}

// Apply one logical extent and derive active-layout split pixels from intent.
ui_apply_window_metrics :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    metrics: viewmodel.Ui_Window_Metrics) -> bool {
    changed := runtime^.window != metrics
    if changed {
        uilayout.ui_release_geometry_capture(runtime)
        runtime^.window = metrics
    }
    resolved := uiregions.resolve_layout_mode(runtime^.layout_preference,
        runtime^.current_layout_mode, f32(metrics.width), f32(metrics.height))
    transitioned := ui_transition_layout(runtime, resolved)
    if resolved == .Portrait {
        runtime^.vertical_split_x = f32(metrics.width)
        runtime^.horizontal_split_y = uisplitter.splitter_clamp_horizontal(
            runtime^.portrait.world_height_ratio * f32(metrics.height), metrics.height)
    } else {
        runtime^.vertical_split_x = uisplitter.splitter_clamp_vertical(
            runtime^.landscape.vertical_ratio * f32(metrics.width), metrics.width)
        runtime^.horizontal_split_y = uisplitter.splitter_clamp_horizontal(
            runtime^.landscape.horizontal_ratio * f32(metrics.height), metrics.height)
    }
    return changed || transitioned
}

// prepare_ui_accordion_geometry publishes full-size portrait content and reveal geometry.
prepare_ui_accordion_geometry :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State, frame: input.Input_Frame) {
    sections := accordion_sections_for_layout(runtime^.current_layout_mode, "")
    _ = uiaccordion.accordion_transition_layout({
        panel = geometry.Rectangle(runtime^.ui_regions.accordion_rect),
        mouse_input = frame, transition = &runtime^.accordion_transition,
        reduce_motion = uiaccordion.ui_reduced_motion(runtime),
    }, sections, runtime^.active_accordion_section)
    if runtime^.current_layout_mode == .Portrait {
        runtime^.ui_regions.text_rect =
            geometry.Rectangle(uiaccordion.accordion_content_rect(runtime, .View))
        runtime^.ui_regions.terminal_rect =
            uiregions.layout_terminal_rect(runtime^.ui_regions.text_rect)
    }
    _ = uipresentation.ui_publish_presentation_visibility(runtime)
}

// Prepare panel geometry while preserving capture identity from frame start.
prepare_ui_geometry :: proc(
    state: ^core.Euclid_General_State,
    mouse_input: input.Input_Frame,
    frame_dt: f32) -> Ui_Geometry_Preparation {
    ui_runtime := &state^.ui_runtime
    capture_for_frame := ui_runtime^.ui_press_owner
    splitters := uisplitter.update_splitters(
        ui_runtime, mouse_input, min(f32(0.05), max(f32(0), frame_dt)),
        state^.gif_capture_status.gif_capture_phase)
    uisplitter.apply_splitter_preparation(ui_runtime, splitters)
    regions := uiregions.compute_ui_regions(ui_runtime.current_layout_mode,
        f32(ui_runtime^.window.width), f32(ui_runtime^.window.height),
        ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    if !uiregions.validate_ui_regions(regions) {
        fmt.println("[ui] Warning: invalid regions; using baseline fallback")
        regions = uiregions.compute_ui_regions(.Landscape,
            f32(ui_runtime^.window.width), f32(ui_runtime^.window.height),
            ui_runtime.vertical_split_x, ui_runtime.horizontal_split_y)
    }
    state^.ui_runtime.ui_regions = regions
    prepare_ui_accordion_geometry(ui_runtime, mouse_input)
    regions = ui_runtime^.ui_regions
    projection.fit_iso_scale_to_viewport(
        state^.iso_scale, regions.world_rect.width, regions.world_rect.height)

    text_panel := uiwidgets.text_content_panel(regions.text_rect)
    dynview.track_panel(&state^.dynview, geometry.Rectangle(text_panel))
    dynview.track_font(&state^.dynview, theme.TREE_FONT_SIZE,
        theme.TEXT_WRAP_ADVANCE, theme.TEXT_ROW_HEIGHT)
    dynview.track_style(&state^.dynview, dyncore.DYNVIEW_STYLE_REVISION_PLAIN_TEXT)
    return {capture_for_frame, dyncompile.compile_is_needed(&state^.dynview),
        splitters}
}
