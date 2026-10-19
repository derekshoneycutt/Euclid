package theme

import color "../../../core/color"
import native "../../native"
import "core:slice"

// Color_Role identifies application-owned paint, never authored content or syntax faces.
Color_Role :: enum {
    Text,
    Tree_Text,
    Selection_Background,
    Selection_Text,
    Text_Selection_Background,
    Text_Selection_Foreground,
    Control_Border,
    Disabled_Text,
    Error_Text,
    Prompt_Text,
    Inline_Text,
    Terminal_Prompt,
    Terminal_Help,
    Terminal_Package,
    Terminal_Shell,
    Terminal_Preview,
}

@(rodata)
standard_colors := [Color_Role]color.Color_RGBA8{
    .Text = UI_TEXT_COLOR,
    .Tree_Text = UI_TREE_SELECTION_TEXT_COLOR,
    .Selection_Background = UI_SELECTION_BACKGROUND_COLOR,
    .Selection_Text = UI_SELECTION_TEXT_COLOR,
    .Text_Selection_Background = UI_TEXT_SELECTION_BACKGROUND_COLOR,
    .Text_Selection_Foreground = UI_TEXT_SELECTION_FOREGROUND_COLOR,
    .Control_Border = UI_CONTROL_BORDER_COLOR,
    .Disabled_Text = UI_DISABLED_TEXT_COLOR,
    .Error_Text = {221, 128, 122, 255},
    .Prompt_Text = {186, 198, 228, 255},
    .Inline_Text = {170, 190, 218, 255},
    .Terminal_Prompt = {0x38, 0x98, 0x26, 255},
    .Terminal_Help = {0xD4, 0xB0, 0x06, 255},
    .Terminal_Package = {0x83, 0x9A, 0xE6, 255},
    .Terminal_Shell = {0xDD, 0x80, 0x7A, 255},
    .Terminal_Preview = {0x84, 0x84, 0x84, 255},
}

@(rodata)
increased_colors := [Color_Role]color.Color_RGBA8{
    .Text = {214, 191, 195, 255},
    .Tree_Text = {232, 210, 214, 255},
    .Selection_Background = {194, 169, 173, 255},
    .Selection_Text = UI_SELECTION_TEXT_COLOR,
    .Text_Selection_Background = {74, 88, 104, 255},
    .Text_Selection_Foreground = UI_TEXT_SELECTION_FOREGROUND_COLOR,
    .Control_Border = {175, 145, 155, 255},
    .Disabled_Text = {160, 140, 148, 255},
    .Error_Text = {242, 162, 155, 255},
    .Prompt_Text = {204, 214, 240, 255},
    .Inline_Text = {194, 210, 235, 255},
    .Terminal_Prompt = {126, 192, 112, 255},
    .Terminal_Help = {0xD4, 0xB0, 0x06, 255},
    .Terminal_Package = {165, 185, 245, 255},
    .Terminal_Shell = {242, 162, 155, 255},
    .Terminal_Preview = {165, 165, 165, 255},
}

// increased_contrast combines saved application intent with independent platform intent.
increased_contrast :: proc(requested, system_requested: bool) -> bool {
    return requested || system_requested
}

// appearance_color resolves one role from an immutable Standard/Increased table.
appearance_color :: proc(increased: bool, role: Color_Role) -> color.Color_RGBA8 {
    return increased_colors[role] if increased else standard_colors[role]
}

// prepare_draw_colors borrows process-lifetime immutable colors for one consistent frame.
prepare_draw_colors :: proc(encoder: ^native.Draw_Encoder, increased: bool) {
    encoder^.semantic_colors =
        slice.enumerated_array(&increased_colors) if increased else
            slice.enumerated_array(&standard_colors)
}

// draw_color resolves explicit application paint without inspecting source RGB values.
draw_color :: proc(
    encoder: ^native.Draw_Encoder, role: Color_Role) -> color.Color_RGBA8 {
    if encoder != nil && len(encoder^.semantic_colors) == len(standard_colors) {
        return encoder^.semantic_colors[int(role)]
    }
    return standard_colors[role]
}
