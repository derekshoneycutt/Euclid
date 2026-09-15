package particles

import particlemodel "model"

import "core:math"

import rl "vendor:raylib"

Vector_Dust_Field_State :: particlemodel.Vector_Dust_Field_State
Vector_Dust_Field_Stencil :: particlemodel.Vector_Dust_Field_Stencil

VECTOR_DUST_DENSITY_EPSILON :: f32(1e-6)
VECTOR_DUST_PRESSURE_YIELD :: f32(1.05)
VECTOR_DUST_PRESSURE_STRENGTH :: f32(0.00008)
VECTOR_DUST_PRESSURE_ACCELERATION_MAX :: f32(0.03)
VECTOR_DUST_VISCOSITY :: f32(0.000048)
VECTOR_DUST_DRAG_RATE :: f32(1.5)

// Build the four-node bilinear stencil for one clamped board-space position.
vector_dust_field_stencil :: proc(position: rl.Vector2) -> Vector_Dust_Field_Stencil {
    coordinates := dust_field_coordinates(position)
    base_x := min(int(math.floor(f64(coordinates.x))), DUST_FIELD_DIM - 2)
    base_y := min(int(math.floor(f64(coordinates.y))), DUST_FIELD_DIM - 2)
    fraction_x := coordinates.x - f32(base_x)
    fraction_y := coordinates.y - f32(base_y)
    return {
        indices = {
            i32(base_y * DUST_FIELD_DIM + base_x),
            i32(base_y * DUST_FIELD_DIM + base_x + 1),
            i32((base_y + 1) * DUST_FIELD_DIM + base_x),
            i32((base_y + 1) * DUST_FIELD_DIM + base_x + 1),
        },
        weights = {
            (1 - fraction_x) * (1 - fraction_y),
            fraction_x * (1 - fraction_y),
            (1 - fraction_x) * fraction_y,
            fraction_x * fraction_y,
        },
    }
}

// Clear all five fixed field planes before the next particle-to-grid transfer.
vector_dust_field_clear :: proc(field: ^Vector_Dust_Field_State) {
    field^ = {}
}

// Deposit one particle's unit density and XY momentum in one stencil traversal.
vector_dust_field_deposit :: proc(field: ^Vector_Dust_Field_State,
        position, velocity: rl.Vector2) {
    stencil := vector_dust_field_stencil(position)
    for stencil_index in 0..<particlemodel.VECTOR_DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        field^.density[node] += weight
        field^.velocity_x[node] += velocity.x * weight
        field^.velocity_y[node] += velocity.y * weight
    }
}

// Convert deposited momentum in the velocity planes to nodal velocity.
vector_dust_field_normalize :: proc(field: ^Vector_Dust_Field_State) {
    for node in 0..<DUST_FIELD_NODE_COUNT {
        density := field^.density[node]
        if density <= VECTOR_DUST_DENSITY_EPSILON {
            field^.velocity_x[node] = 0
            field^.velocity_y[node] = 0
            continue
        }
        field^.velocity_x[node] /= density
        field^.velocity_y[node] /= density
    }
}

// Reconstruct one XY velocity from the four surrounding field nodes.
vector_dust_field_sample :: proc(field: ^Vector_Dust_Field_State,
        position: rl.Vector2) -> rl.Vector2 {
    stencil := vector_dust_field_stencil(position)
    result: rl.Vector2
    for stencil_index in 0..<particlemodel.VECTOR_DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        result.x += field^.velocity_x[node] * weight
        result.y += field^.velocity_y[node] * weight
    }
    return result
}

// Return one clamped cardinal neighbor for the shared field topology.
vector_dust_field_neighbor :: #force_inline proc(node, offset_x, offset_y: int) -> int {
    x := clamp(node % DUST_FIELD_DIM + offset_x, 0, DUST_FIELD_DIM - 1)
    y := clamp(node / DUST_FIELD_DIM + offset_y, 0, DUST_FIELD_DIM - 1)
    return y * DUST_FIELD_DIM + x
}

// Evaluate yielded pressure for one deposited density value.
vector_dust_field_pressure :: #force_inline proc(density: f32) -> f32 {
    excess := max(density - VECTOR_DUST_PRESSURE_YIELD, f32(0))
    return VECTOR_DUST_PRESSURE_STRENGTH * excess * excess
}

// Evaluate the centered pressure gradient at one field node.
vector_dust_field_pressure_gradient :: proc(field: ^Vector_Dust_Field_State,
        node: int) -> rl.Vector2 {
    left := vector_dust_field_neighbor(node, -1, 0)
    right := vector_dust_field_neighbor(node, 1, 0)
    down := vector_dust_field_neighbor(node, 0, -1)
    up := vector_dust_field_neighbor(node, 0, 1)
    scale := f32(0.5) / DUST_FIELD_SPACING
    return {
        (vector_dust_field_pressure(field^.density[right]) -
            vector_dust_field_pressure(field^.density[left])) * scale,
        (vector_dust_field_pressure(field^.density[up]) -
            vector_dust_field_pressure(field^.density[down])) * scale,
    }
}

// Evaluate the cardinal velocity Laplacian at one field node.
vector_dust_field_laplacian :: proc(field: ^Vector_Dust_Field_State,
        node: int) -> rl.Vector2 {
    left := vector_dust_field_neighbor(node, -1, 0)
    right := vector_dust_field_neighbor(node, 1, 0)
    down := vector_dust_field_neighbor(node, 0, -1)
    up := vector_dust_field_neighbor(node, 0, 1)
    return {
        (field^.velocity_x[left] + field^.velocity_x[right] +
            field^.velocity_x[down] + field^.velocity_x[up] -
            4 * field^.velocity_x[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
        (field^.velocity_y[left] + field^.velocity_y[right] +
            field^.velocity_y[down] + field^.velocity_y[up] -
            4 * field^.velocity_y[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
    }
}

// Evolve one occupied node through pressure, smoothing, and rational drag.
vector_dust_field_evolve_node :: proc(field: ^Vector_Dust_Field_State,
        node: int, dt: f32) -> rl.Vector2 {
    density := field^.density[node]
    if density <= VECTOR_DUST_DENSITY_EPSILON {
        return {}
    }
    gradient := vector_dust_field_pressure_gradient(field, node)
    pressure_x := math.clamp(-gradient.x / density,
        -VECTOR_DUST_PRESSURE_ACCELERATION_MAX,
        VECTOR_DUST_PRESSURE_ACCELERATION_MAX)
    pressure_y := math.clamp(-gradient.y / density,
        -VECTOR_DUST_PRESSURE_ACCELERATION_MAX,
        VECTOR_DUST_PRESSURE_ACCELERATION_MAX)
    laplacian := vector_dust_field_laplacian(field, node)
    drag := 1 + VECTOR_DUST_DRAG_RATE * dt
    return {
        (field^.velocity_x[node] +
            dt * (pressure_x + VECTOR_DUST_VISCOSITY * laplacian.x)) / drag,
        (field^.velocity_y[node] +
            dt * (pressure_y + VECTOR_DUST_VISCOSITY * laplacian.y)) / drag,
    }
}

// Evolve every node through one fixed explicit solve and publish its velocity.
vector_dust_field_evolve :: proc(field: ^Vector_Dust_Field_State, dt: f32) {
    vector_dust_field_normalize(field)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        next := vector_dust_field_evolve_node(field, node, dt)
        field^.next_velocity_x[node] = next.x
        field^.next_velocity_y[node] = next.y
    }
    for node in 0..<DUST_FIELD_NODE_COUNT {
        field^.velocity_x[node] = field^.next_velocity_x[node]
        field^.velocity_y[node] = field^.next_velocity_y[node]
    }
}

// Deposit every grounded particle into the field in stable slot order.
vector_dust_field_deposit_grounded :: proc(ps: ^Particle_System) {
    field := &ps^.vector_dust_field
    vector_dust_field_clear(field)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        velocity := Vector2{ps^.low_particles.vel_x[index],
            ps^.low_particles.vel_y[index]}
        vector_dust_field_deposit(field, position, velocity)
    }
}

// Assign exact field velocity to every grounded particle in stable slot order.
vector_dust_field_assign_grounded :: proc(ps: ^Particle_System) {
    field := &ps^.vector_dust_field
    ps^.vector_dust_grounded_count = 0
    ps^.vector_dust_peak_speed_sq = 0
    ps^.vector_dust_kinetic_measure = 0
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        velocity := vector_dust_field_sample(field, position)
        ps^.low_particles.vel_x[index] = velocity.x
        ps^.low_particles.vel_y[index] = velocity.y
        speed_sq := velocity.x * velocity.x + velocity.y * velocity.y
        ps^.vector_dust_grounded_count += 1
        ps^.vector_dust_peak_speed_sq = max(
            ps^.vector_dust_peak_speed_sq, speed_sq)
        ps^.vector_dust_kinetic_measure += speed_sq
    }
}

// Run one field-only grounded XY update after ballistic and contact mutations.
vector_dust_field_update_grounded :: proc(ps: ^Particle_System, dt: f32) {
    vector_dust_field_deposit_grounded(ps)
    vector_dust_field_evolve(&ps^.vector_dust_field, dt)
    vector_dust_field_assign_grounded(ps)
}