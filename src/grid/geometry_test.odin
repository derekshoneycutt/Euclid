#+test
package grid

import "core:testing"

import test_helpers "../test_helpers"

// Verify exact cell multiples produce no centering remainder.
@(test)
grid_geometry_exact_multiples_have_zero_offsets :: proc(t: ^testing.T) {
    placement, ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 16, height = 44})

    testing.expect(t, ok)
    testing.expect_value(t, placement.column_span, 2)
    testing.expect_value(t, placement.row_span, 2)
    test_helpers.expect_close(t, placement.content_offset_x, 0, "exact width offset")
    test_helpers.expect_close(t, placement.content_offset_y, 0, "exact height offset")
}

// Verify fractional dimensions round outward and center within the allocation.
@(test)
grid_geometry_fractional_content_rounds_outward :: proc(t: ^testing.T) {
    placement, ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 17, height = 23})

    testing.expect(t, ok)
    testing.expect_value(t, placement.column_span, 3)
    testing.expect_value(t, placement.row_span, 2)
    test_helpers.expect_close(t, placement.allocated_width, 24, "allocated width")
    test_helpers.expect_close(t, placement.allocated_height, 44, "allocated height")
    test_helpers.expect_close(t, placement.content_offset_x, 3.5, "centered x offset")
    test_helpers.expect_close(t, placement.content_offset_y, 10.5, "centered y offset")
}

// Verify invalid cell and content dimensions are rejected without placement.
@(test)
grid_geometry_invalid_metrics_are_rejected :: proc(t: ^testing.T) {
    zero: f32 = 0
    not_a_number := zero / zero
    infinity := 1 / zero
    _, zero_cell_ok := place_embedded_content(
        Cell_Metrics{cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 8, height = 22})
    _, invalid_cell_baseline_ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 23},
        Embedded_Content_Metrics{width = 8, height = 22})
    _, zero_content_ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 8})
    _, invalid_content_baseline_ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{
            width = 8, height = 22, has_baseline = true, baseline_from_top = 23})
    _, nan_content_ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = not_a_number, height = 22})
    _, infinite_content_ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 8, height = infinity})

    testing.expect(t, !zero_cell_ok)
    testing.expect(t, !invalid_cell_baseline_ok)
    testing.expect(t, !zero_content_ok)
    testing.expect(t, !invalid_content_baseline_ok)
    testing.expect(t, !nan_content_ok)
    testing.expect(t, !infinite_content_ok)
}

// Verify baseline content remains contained and aligned to the canonical lattice.
@(test)
grid_geometry_baseline_content_is_aligned_and_contained :: proc(t: ^testing.T) {
    cells := Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16}
    content := Embedded_Content_Metrics{
        width = 19,
        height = 50,
        has_baseline = true,
        baseline_from_top = 34,
    }
    placement, ok := place_embedded_content(cells, content)

    testing.expect(t, ok)
    testing.expect_value(t, placement.column_span, 3)
    testing.expect_value(t, placement.row_span, 3)
    testing.expect_value(t, placement.baseline_row, 1)
    baseline_y := placement.content_offset_y + content.baseline_from_top
    expected_baseline_y := f32(placement.baseline_row) * cells.cell_height +
        cells.baseline_from_top
    test_helpers.expect_close(t, baseline_y, expected_baseline_y,
        "content baseline should match the grid lattice")
    testing.expect(t, placement.content_offset_y >= 0)
    testing.expect(t,
        placement.content_offset_y + content.height <= placement.allocated_height)
}

// Verify an exact top-boundary match selects the earliest containing baseline row.
@(test)
grid_geometry_baseline_boundary_is_deterministic :: proc(t: ^testing.T) {
    placement, ok := place_embedded_content(
        Cell_Metrics{cell_width = 10, cell_height = 20, baseline_from_top = 14},
        Embedded_Content_Metrics{
            width = 10, height = 40, has_baseline = true, baseline_from_top = 34})

    testing.expect(t, ok)
    testing.expect_value(t, placement.baseline_row, 1)
    testing.expect_value(t, placement.row_span, 2)
    test_helpers.expect_close(t, placement.content_offset_y, 0,
        "exact top-boundary placement")
}

// Verify the first valid baseline row gives the minimum containing row span.
@(test)
grid_geometry_asymmetric_baseline_uses_minimum_rows :: proc(t: ^testing.T) {
    cells := Cell_Metrics{cell_width = 10, cell_height = 20, baseline_from_top = 14}
    placement, ok := place_embedded_content(cells, Embedded_Content_Metrics{
        width = 10,
        height = 66,
        has_baseline = true,
        baseline_from_top = 47,
    })

    testing.expect(t, ok)
    testing.expect_value(t, placement.baseline_row, 2)
    testing.expect_value(t, placement.row_span, 4)
    test_helpers.expect_close(t, placement.content_offset_y, 7,
        "baseline-constrained top remainder")
    test_helpers.expect_close(t, placement.allocated_height, 80,
        "minimum baseline-constrained height")
}

// Verify large finite dimensions remain allocation-free and preserve containment.
@(test)
grid_geometry_large_content_preserves_containment :: proc(t: ^testing.T) {
    placement, ok := place_embedded_content(
        Cell_Metrics{cell_width = 8, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = 8000.5, height = 22000.25})

    testing.expect(t, ok)
    testing.expect_value(t, placement.column_span, 1001)
    testing.expect_value(t, placement.row_span, 1001)
    testing.expect(t, placement.allocated_width >= 8000.5)
    testing.expect(t, placement.allocated_height >= 22000.25)
}

// Verify finite dimensions that exceed the result integer range are rejected.
@(test)
grid_geometry_unrepresentable_span_is_rejected :: proc(t: ^testing.T) {
    _, ok := place_embedded_content(
        Cell_Metrics{cell_width = 1, cell_height = 22, baseline_from_top = 16},
        Embedded_Content_Metrics{width = max(f32), height = 22})

    testing.expect(t, !ok)
}