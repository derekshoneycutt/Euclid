package dynview_core

import app_core "../../core"

import "core:math"

//   Return whether one typed table length is finite, bounded, and canonical.
math_length_is_valid :: proc(
    length: app_core.Dynview_Math_Length, allow_negative: bool) -> bool {

    value := length.value
    if math.is_nan(value) || math.is_inf(value) || abs(value) > 1024 {
        return false
    }
    switch length.unit {
    case .Default, .Zero:
        return value == 0
    case .Em, .Ex, .Point:
        return allow_negative || value >= 0
    }
    return false
}

//   Return whether one native table descriptor is canonical and bounded.
math_table_descriptor_is_valid :: proc(
    descriptor: app_core.Dynview_Math_Table_Descriptor) -> bool {

    if descriptor.rows <= 0 || descriptor.rows > 16 ||
        descriptor.columns <= 0 || descriptor.columns > 16 ||
        descriptor.cell_style < .Display || descriptor.cell_style > .Script_Script ||
        descriptor.row_spacing < .Matrix || descriptor.row_spacing > .Alignment {
        return false
    }
    for alignment in descriptor.column_alignments {
        if alignment < .Left || alignment > .Right {
            return false
        }
    }
    for gap, index in descriptor.column_boundary_gaps {
        live := index <= descriptor.columns
        if !math_length_is_valid(gap, false) ||
            descriptor.vertical_rule_counts[index] > 2 ||
            (!live && (gap != {} || descriptor.vertical_rule_counts[index] != 0)) {
            return false
        }
    }
    for gap, index in descriptor.row_extra_gaps {
        if !math_length_is_valid(gap, true) ||
            (index >= descriptor.rows && gap != {}) {
            return false
        }
    }
    for count, index in descriptor.horizontal_rule_counts {
        if count > 2 || (index > descriptor.rows && count != 0) {
            return false
        }
    }
    return true
}