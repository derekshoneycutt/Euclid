package particles

import particlemodel "model"

import "core:math"

import rl "vendor:raylib"

Dust_Field_Scalar :: particlemodel.Dust_Field_Scalar
Dust_Field_State :: particlemodel.Dust_Field_State
Dust_Field_Stencil :: particlemodel.Dust_Field_Stencil

DUST_FIELD_DIM :: particlemodel.DUST_FIELD_DIM
DUST_FIELD_NODE_COUNT :: particlemodel.DUST_FIELD_NODE_COUNT
DUST_FIELD_INTERVAL_COUNT :: DUST_FIELD_DIM - 1

// Map a board-space position onto the fixed dust-field lattice.
dust_field_coordinates :: proc(position: rl.Vector2) -> rl.Vector2 {
    scale := f32(DUST_FIELD_INTERVAL_COUNT)
    return {
        math.clamp(position.x, f32(0), f32(1)) * scale,
        math.clamp(position.y, f32(0), f32(1)) * scale,
    }
}

// Evaluate the centered quadratic B-spline weight at one lattice offset.
dust_field_kernel_weight :: proc(offset: f32) -> f32 {
    distance := math.abs(offset)
    if distance < 0.5 {
        return 0.75 - distance * distance
    }
    if distance < 1.5 {
        remainder := 1.5 - distance
        return 0.5 * remainder * remainder
    }
    return 0
}

// Build a normalized compact stencil for one clamped board-space position.
dust_field_stencil :: proc(position: rl.Vector2) -> Dust_Field_Stencil {
    coordinates := dust_field_coordinates(position)
    first_x := int(math.floor(f64(coordinates.x - 0.5)))
    first_y := int(math.floor(f64(coordinates.y - 0.5)))
    stencil: Dust_Field_Stencil
    weight_sum: f32
    for y in first_y..=first_y + 2 {
        for x in first_x..=first_x + 2 {
            if x < 0 || x >= DUST_FIELD_DIM || y < 0 || y >= DUST_FIELD_DIM {
                continue
            }
            weight := dust_field_kernel_weight(coordinates.x - f32(x)) *
                dust_field_kernel_weight(coordinates.y - f32(y))
            stencil.indices[stencil.count] = i32(y * DUST_FIELD_DIM + x)
            stencil.weights[stencil.count] = weight
            stencil.count += 1
            weight_sum += weight
        }
    }
    for index in 0..<stencil.count {
        stencil.weights[index] /= weight_sum
    }
    return stencil
}

// Record a first-time active node for bounded sparse reset and evolution.
dust_field_mark_active :: proc(field: ^Dust_Field_State, node_index: int) {
    word_index := node_index / 64
    mask := u64(1) << u64(node_index % 64)
    if field^.active_bits[word_index] & mask != 0 {
        return
    }
    field^.active_bits[word_index] |= mask
    field^.active_nodes[field^.active_count] = i32(node_index)
    field^.active_count += 1
}

// Clear every CPU field plane at one previously active node.
dust_field_clear_node :: proc(field: ^Dust_Field_State, node_index: int) {
    field^.candidate_density[node_index] = 0
    field^.density[node_index] = 0
    field^.momentum_x[node_index] = 0
    field^.momentum_y[node_index] = 0
    field^.velocity_x[node_index] = 0
    field^.velocity_y[node_index] = 0
    field^.next_velocity_x[node_index] = 0
    field^.next_velocity_y[node_index] = 0
    field^.color_r[node_index] = 0
    field^.color_g[node_index] = 0
    field^.color_b[node_index] = 0
    field^.coverage[node_index] = 0
}

// Clear prior active support while leaving untouched empty nodes unvisited.
dust_field_reset_active :: proc(field: ^Dust_Field_State) {
    for active_index in 0..<field^.active_count {
        node_index := int(field^.active_nodes[active_index])
        dust_field_clear_node(field, node_index)
        word_index := node_index / 64
        field^.active_bits[word_index] = 0
        field^.active_nodes[active_index] = 0
    }
    field^.active_count = 0
}

// Deposit one scalar contribution through the normalized field stencil.
dust_field_deposit_scalar :: proc(field: ^Dust_Field_State,
        plane: ^Dust_Field_Scalar, position: rl.Vector2, amount: f32) {
    stencil := dust_field_stencil(position)
    for stencil_index in 0..<stencil.count {
        node_index := int(stencil.indices[stencil_index])
        dust_field_mark_active(field, node_index)
        plane^[node_index] += amount * stencil.weights[stencil_index]
    }
}

// Deposit one vector contribution through the normalized field stencil.
dust_field_deposit_vector :: proc(field: ^Dust_Field_State,
        plane_x, plane_y: ^Dust_Field_Scalar, position, amount: rl.Vector2) {
    stencil := dust_field_stencil(position)
    for stencil_index in 0..<stencil.count {
        node_index := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        dust_field_mark_active(field, node_index)
        plane_x^[node_index] += amount.x * weight
        plane_y^[node_index] += amount.y * weight
    }
}

// Reconstruct one scalar value from a normalized field stencil.
dust_field_sample_scalar :: proc(plane: ^Dust_Field_Scalar,
        position: rl.Vector2) -> f32 {
    stencil := dust_field_stencil(position)
    result: f32
    for stencil_index in 0..<stencil.count {
        node_index := int(stencil.indices[stencil_index])
        result += plane^[node_index] * stencil.weights[stencil_index]
    }
    return result
}

// Reconstruct one vector value from a normalized field stencil.
dust_field_sample_vector :: proc(plane_x, plane_y: ^Dust_Field_Scalar,
        position: rl.Vector2) -> rl.Vector2 {
    stencil := dust_field_stencil(position)
    result: rl.Vector2
    for stencil_index in 0..<stencil.count {
        node_index := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        result.x += plane_x^[node_index] * weight
        result.y += plane_y^[node_index] * weight
    }
    return result
}