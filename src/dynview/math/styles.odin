package dynview_math

// Math_Style_Level identifies one of TeX's four recursive math size levels.
Math_Style_Level :: enum u8 {
    Display,
    Text,
    Script,
    Script_Script,
}

// Math_Style combines a recursive size level with TeX's cramped-state bit.
Math_Style :: struct {
    level: Math_Style_Level,
    cramped: bool,
}

// Math_Child_Style_Role names the structural transition applied to a child program.
Math_Child_Style_Role :: enum u8 {
    Fraction_Numerator,
    Fraction_Denominator,
    Superscript,
    Subscript,
    Radical_Radicand,
    Radical_Degree,
}

//   Return the next smaller recursive level, saturating at script-script.
math_style_next_level :: #force_inline proc(
    level: Math_Style_Level) -> Math_Style_Level {

    switch level {
    case .Display:
        return .Text
    case .Text:
        return .Script
    case .Script, .Script_Script:
        return .Script_Script
    }
    return .Script_Script
}

//   Return the TeX size level used by a superscript or subscript child.
math_style_script_level :: #force_inline proc(
    level: Math_Style_Level) -> Math_Style_Level {

    switch level {
    case .Display, .Text:
        return .Script
    case .Script, .Script_Script:
        return .Script_Script
    }
    return .Script_Script
}

//   Resolve the TeX style inherited by one structural child math program.
math_child_style :: proc(
    parent: Math_Style,
    role: Math_Child_Style_Role) -> Math_Style {

    switch role {
    case .Fraction_Numerator:
        return {math_style_next_level(parent.level), parent.cramped}
    case .Fraction_Denominator:
        return {math_style_next_level(parent.level), true}
    case .Superscript:
        return {math_style_script_level(parent.level), parent.cramped}
    case .Subscript:
        return {math_style_script_level(parent.level), true}
    case .Radical_Radicand:
        return {parent.level, true}
    case .Radical_Degree:
        return {.Script_Script, false}
    }
    return parent
}