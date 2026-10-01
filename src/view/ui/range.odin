package ui

import viewmodel "../model"

import "core:math"

// Integer_Range_Spec describes one bounded integral control domain.
Integer_Range_Spec :: struct {
    minimum: int,
    maximum: int,
    step: int,
    page_step: int,
}

// Float_Range_Spec describes one bounded finite control domain.
Float_Range_Spec :: struct {
    minimum: f32,
    maximum: f32,
    step: f32,
    page_step: f32,
}

// range_integer_spec normalizes an integer range and positive step sizes.
range_integer_spec :: proc(
    minimum, maximum, step, page_step: int) -> Integer_Range_Spec {
    low := min(minimum, maximum)
    high := max(minimum, maximum)
    return {low, high, max(1, abs(step)), max(1, abs(page_step))}
}

// range_integer_clamp confines one value to a normalized integer range.
range_integer_clamp :: #force_inline proc(
    value: int, spec: Integer_Range_Spec) -> int {
    return clamp(value, spec.minimum, spec.maximum)
}

// range_integer_step applies a signed number of ordinary or page steps.
range_integer_step :: proc(
    value: int, amount: int, spec: Integer_Range_Spec,
    page: bool = false) -> int {
    increment := spec.step
    if page {
        increment = spec.page_step
    }
    return range_integer_clamp(value + amount * increment, spec)
}

// range_integer_normalized maps one integer value into the unit interval.
range_integer_normalized :: proc(value: int, spec: Integer_Range_Spec) -> f32 {
    extent := spec.maximum - spec.minimum
    if extent <= 0 {
        return 0
    }
    return f32(range_integer_clamp(value, spec) - spec.minimum) / f32(extent)
}

// range_integer_from_normalized maps a unit position to the nearest integer value.
range_integer_from_normalized :: proc(
    position: f32, spec: Integer_Range_Spec) -> int {
    extent := spec.maximum - spec.minimum
    return range_integer_clamp(
        spec.minimum + int(clamp(position, f32(0), f32(1)) * f32(extent) + 0.5),
        spec)
}

// range_float_spec validates finite float bounds and positive step sizes.
range_float_spec :: proc(
    minimum, maximum, step, page_step: f32) -> (Float_Range_Spec, bool) {
    if math.is_nan(minimum) || math.is_inf(minimum) || math.is_nan(maximum) ||
        math.is_inf(maximum) || math.is_nan(step) || math.is_inf(step) ||
        math.is_nan(page_step) || math.is_inf(page_step) {
        return {}, false
    }
    low := min(minimum, maximum)
    high := max(minimum, maximum)
    return {low, high, max(f32(0), abs(step)), max(f32(0), abs(page_step))}, true
}

// range_float_clamp confines one finite value to a validated float range.
range_float_clamp :: proc(value: f32, spec: Float_Range_Spec) -> f32 {
    if math.is_nan(value) || math.is_inf(value) {
        return spec.minimum
    }
    return clamp(value, spec.minimum, spec.maximum)
}

// range_float_step applies a signed number of ordinary or page steps.
range_float_step :: proc(
    value, amount: f32, spec: Float_Range_Spec,
    page: bool = false) -> f32 {
    increment := spec.step
    if page {
        increment = spec.page_step
    }
    return range_float_clamp(value + amount * increment, spec)
}

// range_action_source records one changed ranged-control input route.
range_action_source :: #force_inline proc(
    changed: bool, source: viewmodel.Ui_Control_Action_Source_Flag) ->
    viewmodel.Ui_Control_Action_Source {
    if changed {
        return {source}
    }
    return {}
}