#+test
package ui

import color "../../core/color"
import dyncore "../../dynview/core"
import math "core:math"
import testing "core:testing"
import theme "theme"
import uisplitter "layout/splitter"
import uiterminal "terminal"
import terminalview "../terminal"
import worldmodel "../world/model"
import native "../native"

// Verify additive preference policy and immutable draw-time role publication.
@(test)
increased_contrast_policy_and_standard_palette :: proc(t: ^testing.T) {
    modes := [?]bool{false, true}
    for manual in modes {
        for system in modes {
            testing.expect_value(t,
                theme.increased_contrast(manual, system), manual || system)
        }
    }
    encoder: native.Draw_Encoder
    for increased in modes {
        theme.prepare_draw_colors(&encoder, increased)
        for role in theme.Color_Role {
            testing.expect_value(t, theme.draw_color(&encoder, role),
                theme.appearance_color(increased, role))
        }
    }
    testing.expect_value(t, theme.appearance_color(false, .Text), theme.UI_TEXT_COLOR)
    testing.expect_value(t, theme.appearance_color(false, .Tree_Text),
        theme.UI_TREE_SELECTION_TEXT_COLOR)
    testing.expect_value(t, theme.appearance_color(false, .Text_Selection_Background),
        theme.UI_TEXT_SELECTION_BACKGROUND_COLOR)
}

// Verify enhanced text and essential boundary thresholds against composited UI states.
@(test)
increased_contrast_ui_state_pairs :: proc(t: ^testing.T) {
    backgrounds := [?]color.Color_RGBA8{theme.UI_BACK_COLOR,
        theme.UI_COMPONENT_BACKGROUND_COLOR, worldmodel.BACKGROUND_COLOR}
    for background in backgrounds {
        rgb := contrast_rgb(background)
        backings := [?][3]f64{rgb, contrast_composite(theme.UI_HOVER_COLOR, rgb)}
        for backing in backings {
            testing.expect(t,
                contrast_ratio(theme.appearance_color(true, .Text), backing) >= 7)
            testing.expect(t,
                contrast_ratio(
                    theme.appearance_color(true, .Control_Border), backing) >= 3)
        }
    }
    tree := contrast_rgb(theme.UI_TREE_SELECTION_BACKGROUND_COLOR)
    selected := contrast_rgb(theme.appearance_color(true, .Selection_Background))
    modes := [?]bool{false, true}
    for hover in modes {
        tree_back := contrast_composite(
            theme.UI_SELECTED_HOVER_COLOR, tree) if hover else tree
        selected_back := contrast_composite(
            theme.UI_SELECTED_HOVER_COLOR, selected) if hover else selected
        testing.expect(t,
            contrast_ratio(theme.appearance_color(true, .Tree_Text), tree_back) >= 7)
        testing.expect(t,contrast_ratio(
            theme.appearance_color(true, .Selection_Text), selected_back) >= 7)
    }
}

// Verify only application-owned Terminal and Dynview roles carry the enhanced text guarantee.
@(test)
increased_contrast_presentation_pairs :: proc(t: ^testing.T) {
    panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
    roles := [?]theme.Color_Role{
        .Text, .Error_Text, .Prompt_Text, .Inline_Text,
        .Terminal_Prompt, .Terminal_Help, .Terminal_Package,
        .Terminal_Shell, .Terminal_Preview}
    for role in roles {
        testing.expect(t,
            contrast_ratio(theme.appearance_color(true, role), panel) >= 7)
    }
    draw := uiterminal.terminal_draw_theme(true)
    testing.expect(t, contrast_ratio(draw.selection_foreground,
        contrast_rgb(draw.selection_background)) >= 7)
    testing.expect(t,
        contrast_ratio(
            draw.cursor_foreground, contrast_rgb(draw.default_foreground)) >= 7)
    testing.expect_value(t, draw.selection_background,
        theme.appearance_color(true, .Text_Selection_Background))
}

// Explorer-owned text stays readable on panel and navigation-selected surfaces.
@(test)
history_explorer_contrast_covers_selected_and_informational_text :: proc(t: ^testing.T) {
    modes := [?]bool{false, true}
    for increased in modes {
        target := f64(4.5) if !increased else f64(7)
        panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
        selected := contrast_rgb(theme.appearance_color(
            increased, .History_Explorer_Selection_Background))
        foreground := theme.appearance_color(increased, .Text)
        testing.expect(t, contrast_ratio(foreground, panel) >= target)
        testing.expect(t, contrast_ratio(foreground, selected) >= target)
        testing.expect(t,
            contrast_ratio(theme.appearance_color(increased, .Control_Border),
                panel) >= 3)
    }
}

// Colored mode icons, inverse name badges, and the current-row circle meet their targets.
@(test)
history_explorer_contrast_covers_mode_badges_and_marker :: proc(t: ^testing.T) {
    modes := [?]bool{false, true}
    roles := [?]theme.Color_Role{.Terminal_Help, .Terminal_Package, .Terminal_Shell}
    for increased in modes {
        target := f64(7) if increased else f64(4.5)
        panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
        selected := contrast_rgb(theme.appearance_color(
            increased, .History_Explorer_Selection_Background))
        for role in roles {
            paint := theme.appearance_color(increased, role)
            testing.expect(t, contrast_ratio(paint, panel) >= 3)
            testing.expect(t, contrast_ratio(theme.UI_COMPONENT_BACKGROUND_COLOR,
                contrast_rgb(paint)) >= target)
        }
        testing.expect(t, contrast_ratio(
            theme.appearance_color(increased, .Terminal_Package), selected) >= 3)
    }
}

// contrast_rgb converts opaque sRGB bytes to normalized channels without linearizing.
contrast_rgb :: proc(value: color.Color_RGBA8) -> [3]f64 {
    return {f64(value.r) / 255, f64(value.g) / 255, f64(value.b) / 255}
}

// contrast_composite matches straight-alpha blending on the UNORM scene target.
contrast_composite :: proc(
    foreground: color.Color_RGBA8, background: [3]f64) -> [3]f64 {
    alpha := f64(foreground.a) / 255
    return contrast_rgb(foreground) * alpha + background * (1 - alpha)
}

// contrast_luminance applies the WCAG sRGB transfer and relative-luminance weights.
contrast_luminance :: proc(rgb: [3]f64) -> f64 {
    linear := rgb
    for &channel in linear {
        channel = channel / 12.92 if channel <= 0.04045 else
            math.pow((channel + 0.055) / 1.055, 2.4)
    }
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
}

// contrast_ratio measures the composited foreground, never rounded display ratios.
contrast_ratio :: proc(foreground: color.Color_RGBA8, background: [3]f64) -> f64 {
    first := contrast_luminance(contrast_composite(foreground, background))
    second := contrast_luminance(background)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
}

// Verify reference pairs and byte-space alpha blending before testing production colors.
@(test)
normal_contrast_measurement_reference_pairs :: proc(t: ^testing.T) {
    testing.expect_value(t,
        contrast_ratio(color.WHITE, contrast_rgb(color.BLACK)), f64(21))
    testing.expect_value(t,
        contrast_ratio(color.BLACK, contrast_rgb(color.WHITE)), f64(21))
    testing.expect_value(t,
        contrast_ratio(color.WHITE, contrast_rgb(color.WHITE)), f64(1))
    testing.expect_value(t, contrast_composite({255, 255, 255, 128},
        contrast_rgb(color.BLACK)), [3]f64{128.0 / 255, 128.0 / 255, 128.0 / 255})
    testing.expect(t, contrast_ratio(theme.UI_TEXT_COLOR,
        contrast_rgb(theme.UI_BORDER_COLOR)) < 4.5)
}

// Verify normal labels, interaction overlays, and essential boundaries on their real fills.
@(test)
normal_ui_contrast_covers_composited_states :: proc(t: ^testing.T) {
    backgrounds := [?]color.Color_RGBA8{
        theme.UI_BACK_COLOR,
        theme.UI_COMPONENT_BACKGROUND_COLOR,
        worldmodel.BACKGROUND_COLOR,
    }
    for background in backgrounds {
        rgb := contrast_rgb(background)
        testing.expect(t, contrast_ratio(theme.UI_TEXT_COLOR, rgb) >= 4.5)
        testing.expect(t, contrast_ratio(theme.UI_TEXT_COLOR,
            contrast_composite(theme.UI_HOVER_COLOR, rgb)) >= 4.5)
        testing.expect(t, contrast_ratio(theme.UI_CONTROL_BORDER_COLOR, rgb) >= 3)
        testing.expect(t, contrast_ratio(uisplitter.SPLITTER_ACTIVE_COLOR, rgb) >= 3)
    }
    selected := contrast_rgb(theme.UI_SELECTION_BACKGROUND_COLOR)
    testing.expect(t, contrast_ratio(theme.UI_SELECTION_TEXT_COLOR, selected) >= 4.5)
    testing.expect(t, contrast_ratio(theme.UI_SELECTION_TEXT_COLOR,
        contrast_composite(theme.UI_SELECTED_HOVER_COLOR, selected)) >= 4.5)
    tree_selected := contrast_rgb(theme.UI_TREE_SELECTION_BACKGROUND_COLOR)
    testing.expect_value(t,
        theme.UI_TREE_SELECTION_BACKGROUND_COLOR, theme.UI_BORDER_COLOR)
    testing.expect(t,
        contrast_ratio(theme.UI_TREE_SELECTION_TEXT_COLOR, tree_selected) >= 4.5)
    testing.expect(t, contrast_ratio(theme.UI_TREE_SELECTION_TEXT_COLOR,
        contrast_composite(theme.UI_SELECTED_HOVER_COLOR, tree_selected)) >= 4.5)
    panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
    hovered := contrast_composite(theme.UI_HOVER_COLOR, panel)
    testing.expect(t, contrast_ratio(theme.UI_TEXT_COLOR, hovered) >= 4.5)
    testing.expect(t, contrast_ratio(theme.ANIMATION_FAVORITE_COLOR, panel) >= 3)
    testing.expect(t, contrast_ratio(theme.UI_ERROR_COLOR, panel) >= 3)
}

// Verify stock Dynview text and the shared Terminal/presentation selection pair.
@(test)
normal_presentation_contrast_covers_stock_styles :: proc(t: ^testing.T) {
    panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
    selected := contrast_composite(theme.UI_PRESENTATION_SELECTION_COLOR, panel)
    testing.expect(t, contrast_ratio(dyncore.STYLE_DEFAULT.color, panel) >= 4.5)
    for entry in dyncore.STYLE_TABLE {
        testing.expect(t, contrast_ratio(entry.style.color, panel) >= 4.5)
    }
    terminal := uiterminal.terminal_draw_theme()
    testing.expect_value(t, theme.UI_PRESENTATION_SELECTION_COLOR,
        color.Color_RGBA8(terminal.selection_background))
    testing.expect_value(t, theme.UI_TEXT_SELECTION_FOREGROUND_COLOR,
        color.Color_RGBA8(terminal.selection_foreground))
    testing.expect(t,
        contrast_ratio(theme.UI_TEXT_SELECTION_FOREGROUND_COLOR, selected) >= 4.5)
    testing.expect(t, contrast_ratio(theme.UI_PRESENTATION_SELECTION_COLOR, panel) >= 3)
}

// Verify application-owned Terminal defaults, prompts, preview, selection, and block cursor.
@(test)
normal_terminal_contrast_covers_owned_colors :: proc(t: ^testing.T) {
    panel := contrast_rgb(theme.UI_COMPONENT_BACKGROUND_COLOR)
    prompts := [?]color.Color_RGBA8{
        terminalview.TERMINAL_PROMPT_COLOR, terminalview.TERMINAL_HELP_PROMPT_COLOR,
        terminalview.TERMINAL_PKG_PROMPT_COLOR, terminalview.TERMINAL_SHELL_PROMPT_COLOR,
        terminalview.TERMINAL_COMPLETION_PREVIEW_COLOR, terminalview.TERMINAL_TEXT_COLOR}
    for foreground in prompts {
        testing.expect(t, contrast_ratio(foreground, panel) >= 4.5)
    }
    draw := uiterminal.terminal_draw_theme()
    testing.expect(t,
        contrast_ratio(color.Color_RGBA8(draw.default_foreground), panel) >= 4.5)
    testing.expect(t, contrast_ratio(color.Color_RGBA8(draw.selection_foreground),
        contrast_rgb(color.Color_RGBA8(draw.selection_background))) >= 4.5)
    testing.expect(t,
        contrast_ratio(color.Color_RGBA8(draw.selection_background), panel) >= 3)
    testing.expect(t, contrast_ratio(terminalview.TERMINAL_CURSOR_TEXT_COLOR,
        contrast_rgb(color.Color_RGBA8(draw.default_foreground))) >= 4.5)
}
