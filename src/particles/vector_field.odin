package particles

import particlemodel "model"

import "core:math"

import rl "vendor:raylib"

Vector_Dust_Field_State :: particlemodel.Vector_Dust_Field_State
Vector_Dust_Field_Stencil :: particlemodel.Vector_Dust_Field_Stencil
Vector_Dust_Field_Bounds :: particlemodel.Vector_Dust_Field_Bounds
Vector_Dust_Transfer :: particlemodel.Vector_Dust_Transfer

Vector_Dust_Field_Neighbors :: struct {
    left, right, down, up: int,
}

VECTOR_DUST_DENSITY_EPSILON :: f32(1e-6)
VECTOR_DUST_PRESSURE_YIELD :: f32(1.05)
VECTOR_DUST_PRESSURE_STRENGTH :: f32(0.00008)
VECTOR_DUST_PRESSURE_ACCELERATION_MAX :: f32(0.03)
VECTOR_DUST_VISCOSITY :: f32(0.000048)
VECTOR_DUST_DRAG_RATE :: f32(1.5)

// Build compact transfer coordinates for one clamped board-space position.
vector_dust_field_transfer :: proc(
        position: rl.Vector2, particle_index: int = -1) -> Vector_Dust_Transfer {
    coordinates := dust_field_coordinates(position)
    base_x := min(int(math.floor(f64(coordinates.x))), DUST_FIELD_DIM - 2)
    base_y := min(int(math.floor(f64(coordinates.y))), DUST_FIELD_DIM - 2)
    return {
        particle_index = i32(particle_index),
        base_node = i32(base_y * DUST_FIELD_DIM + base_x),
        fraction_x = coordinates.x - f32(base_x),
        fraction_y = coordinates.y - f32(base_y),
    }
}

// Expand compact transfer coordinates into their four-node bilinear stencil.
vector_dust_field_transfer_stencil :: #force_inline proc(
        transfer: Vector_Dust_Transfer) -> Vector_Dust_Field_Stencil {
    base := transfer.base_node
    fraction_x := transfer.fraction_x
    fraction_y := transfer.fraction_y
    return {
        indices = {
            base,
            base + 1,
            base + DUST_FIELD_DIM,
            base + DUST_FIELD_DIM + 1,
        },
        weights = {
            (1 - fraction_x) * (1 - fraction_y),
            fraction_x * (1 - fraction_y),
            (1 - fraction_x) * fraction_y,
            fraction_x * fraction_y,
        },
    }
}

// Build the four-node bilinear stencil for one clamped board-space position.
vector_dust_field_stencil :: proc(position: rl.Vector2) -> Vector_Dust_Field_Stencil {
    return vector_dust_field_transfer_stencil(vector_dust_field_transfer(position))
}

// Clear all five fixed field planes before the next particle-to-grid transfer.
vector_dust_field_clear :: proc(field: ^Vector_Dust_Field_State) {
    field^ = {}
}

// Clear deposition planes inside one previously visited inclusive rectangle.
vector_dust_field_clear_bounds :: proc(
    field: ^Vector_Dust_Field_State, bounds: Vector_Dust_Field_Bounds) {
    if !bounds.valid {
        return
    }
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        for x in int(bounds.min_x)..=int(bounds.max_x) {
            node := y * DUST_FIELD_DIM + x
            field^.density[node] = 0
            field^.momentum_x[node] = 0
            field^.momentum_y[node] = 0
        }
    }
}

// Prepare deposition by clearing the prior solve region and resetting support.
vector_dust_field_prepare :: proc(field: ^Vector_Dust_Field_State) {
    vector_dust_field_clear_bounds(field, field^.previous_solve_bounds)
    field^.support_bounds = {}
    field^.previous_solve_bounds = {}
}

// Include one bilinear stencil's two-by-two node footprint in current support.
vector_dust_field_include_stencil :: proc(
    field: ^Vector_Dust_Field_State, stencil: Vector_Dust_Field_Stencil) {
    base := int(stencil.indices[0])
    x := i32(base % DUST_FIELD_DIM)
    y := i32(base / DUST_FIELD_DIM)
    if !field^.support_bounds.valid {
        field^.support_bounds = {x, y, x + 1, y + 1, true}
        return
    }
    bounds := &field^.support_bounds
    bounds^.min_x = min(bounds^.min_x, x)
    bounds^.min_y = min(bounds^.min_y, y)
    bounds^.max_x = max(bounds^.max_x, x + 1)
    bounds^.max_y = max(bounds^.max_y, y + 1)
}

// Expand current support by one node and clamp it to the global topology.
vector_dust_field_solve_bounds :: proc(
    support: Vector_Dust_Field_Bounds) -> Vector_Dust_Field_Bounds {
    if !support.valid {
        return {}
    }
    return {
        max(support.min_x - 1, i32(0)),
        max(support.min_y - 1, i32(0)),
        min(support.max_x + 1, i32(DUST_FIELD_DIM - 1)),
        min(support.max_y + 1, i32(DUST_FIELD_DIM - 1)),
        true,
    }
}

// Deposit one particle's unit density and XY momentum in one stencil traversal.
vector_dust_field_deposit_transfer :: proc(field: ^Vector_Dust_Field_State,
        transfer: Vector_Dust_Transfer, velocity: rl.Vector2) {
    stencil := vector_dust_field_transfer_stencil(transfer)
    vector_dust_field_include_stencil(field, stencil)
    for stencil_index in 0..<particlemodel.VECTOR_DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        field^.density[node] += weight
        field^.momentum_x[node] += velocity.x * weight
        field^.momentum_y[node] += velocity.y * weight
    }
}

// Deposit one position's unit density and XY momentum.
vector_dust_field_deposit :: proc(field: ^Vector_Dust_Field_State,
        position, velocity: rl.Vector2) {
    vector_dust_field_deposit_transfer(
        field, vector_dust_field_transfer(position), velocity)
}

// Convert deposited momentum to velocity inside one inclusive rectangle.
vector_dust_field_normalize :: proc(
    field: ^Vector_Dust_Field_State, bounds: Vector_Dust_Field_Bounds) {
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        row := y * DUST_FIELD_DIM
        for x in int(bounds.min_x)..=int(bounds.max_x) {
            node := row + x
            density := field^.density[node]
            if density <= VECTOR_DUST_DENSITY_EPSILON {
                field^.momentum_x[node] = 0
                field^.momentum_y[node] = 0
                continue
            }
            field^.momentum_x[node] /= density
            field^.momentum_y[node] /= density
        }
    }
}

// Reconstruct one XY velocity from the four surrounding field nodes.
vector_dust_field_sample_transfer :: proc(
        field: ^Vector_Dust_Field_State, transfer: Vector_Dust_Transfer) -> rl.Vector2 {
    stencil := vector_dust_field_transfer_stencil(transfer)
    result: rl.Vector2
    for stencil_index in 0..<particlemodel.VECTOR_DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        result.x += field^.solved_velocity_x[node] * weight
        result.y += field^.solved_velocity_y[node] * weight
    }
    return result
}

// Reconstruct one XY velocity at a board-space position.
vector_dust_field_sample :: proc(field: ^Vector_Dust_Field_State,
        position: rl.Vector2) -> rl.Vector2 {
    return vector_dust_field_sample_transfer(
        field, vector_dust_field_transfer(position))
}

// Evaluate yielded pressure for one deposited density value.
vector_dust_field_pressure :: #force_inline proc(density: f32) -> f32 {
    excess := max(density - VECTOR_DUST_PRESSURE_YIELD, f32(0))
    return VECTOR_DUST_PRESSURE_STRENGTH * excess * excess
}

// Evaluate bounded pressure acceleration from resolved cardinal neighbors.
vector_dust_field_pressure_acceleration :: #force_inline proc(
    field: ^Vector_Dust_Field_State,
        density: f32, neighbors: Vector_Dust_Field_Neighbors) -> rl.Vector2 {
    scale := f32(0.5) / DUST_FIELD_SPACING
    gradient := rl.Vector2{
        (vector_dust_field_pressure(field^.density[neighbors.right]) -
            vector_dust_field_pressure(field^.density[neighbors.left])) * scale,
        (vector_dust_field_pressure(field^.density[neighbors.up]) -
            vector_dust_field_pressure(field^.density[neighbors.down])) * scale,
    }
    return {
        math.clamp(-gradient.x / density, -VECTOR_DUST_PRESSURE_ACCELERATION_MAX,
            VECTOR_DUST_PRESSURE_ACCELERATION_MAX),
        math.clamp(-gradient.y / density, -VECTOR_DUST_PRESSURE_ACCELERATION_MAX,
            VECTOR_DUST_PRESSURE_ACCELERATION_MAX),
    }
}

// Evaluate the cardinal velocity Laplacian from resolved neighbor indices.
vector_dust_field_laplacian :: #force_inline proc(
        field: ^Vector_Dust_Field_State,
        node: int, neighbors: Vector_Dust_Field_Neighbors) -> rl.Vector2 {
    return {
        (field^.momentum_x[neighbors.left] + field^.momentum_x[neighbors.right] +
            field^.momentum_x[neighbors.down] + field^.momentum_x[neighbors.up] -
            4 * field^.momentum_x[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
        (field^.momentum_y[neighbors.left] + field^.momentum_y[neighbors.right] +
            field^.momentum_y[neighbors.down] + field^.momentum_y[neighbors.up] -
            4 * field^.momentum_y[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
    }
}

// Evolve one occupied node through pressure, smoothing, and rational drag.
vector_dust_field_evolve_node :: #force_inline proc(
    field: ^Vector_Dust_Field_State,
    node: int, neighbors: Vector_Dust_Field_Neighbors, dt: f32) -> rl.Vector2 {
    density := field^.density[node]
    if density <= VECTOR_DUST_DENSITY_EPSILON {
        return {}
    }
    pressure := vector_dust_field_pressure_acceleration(
        field, density, neighbors)
    laplacian := vector_dust_field_laplacian(field, node, neighbors)
    drag := 1 + VECTOR_DUST_DRAG_RATE * dt
    return {
        (field^.momentum_x[node] +
            dt * (pressure.x + VECTOR_DUST_VISCOSITY * laplacian.x)) / drag,
        (field^.momentum_y[node] +
            dt * (pressure.y + VECTOR_DUST_VISCOSITY * laplacian.y)) / drag,
    }
}

// Evolve one row using direct horizontal and caller-resolved vertical neighbors.
vector_dust_field_evolve_row :: proc(
        field: ^Vector_Dust_Field_State,
        bounds: Vector_Dust_Field_Bounds, y: int, dt: f32) {
    row := y * DUST_FIELD_DIM
    down_row := row - DUST_FIELD_DIM * int(y > 0)
    up_row := row + DUST_FIELD_DIM * int(y + 1 < DUST_FIELD_DIM)
    for x in int(bounds.min_x)..=int(bounds.max_x) {
        node := row + x
        neighbors := Vector_Dust_Field_Neighbors{
            node - int(x > 0), node + int(x + 1 < DUST_FIELD_DIM),
            down_row + x, up_row + x}
        next := vector_dust_field_evolve_node(
            field, node, neighbors, dt)
        field^.solved_velocity_x[node] = next.x
        field^.solved_velocity_y[node] = next.y
    }
}

// Evolve every node through one fixed explicit solve and publish its velocity.
vector_dust_field_evolve :: proc(field: ^Vector_Dust_Field_State, dt: f32) {
    bounds := vector_dust_field_solve_bounds(field^.support_bounds)
    if !bounds.valid {
        return
    }
    vector_dust_field_normalize(field, bounds)
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        vector_dust_field_evolve_row(field, bounds, y, dt)
    }
    field^.previous_solve_bounds = bounds
}

// Deposit every grounded particle into the field in stable slot order.
vector_dust_field_begin_deposit :: proc(ps: ^Particle_System) {
    field := &ps^.vector_dust_field
    vector_dust_field_prepare(field)
    ps^.vector_dust_transfer_count = 0
}

// Cache and deposit one grounded particle after its local transition update.
vector_dust_field_deposit_grounded_index :: proc(
        ps: ^Particle_System, index: int) {
    position := Vector2{ps^.low_particles.pos_x[index],
        ps^.low_particles.pos_y[index]}
    velocity := Vector2{ps^.low_particles.vel_x[index],
        ps^.low_particles.vel_y[index]}
    transfer := vector_dust_field_transfer(position, index)
    ps^.vector_dust_transfers[ps^.vector_dust_transfer_count] = transfer
    ps^.vector_dust_transfer_count += 1
    vector_dust_field_deposit_transfer(&ps^.vector_dust_field, transfer, velocity)
}

// Deposit every grounded particle into the field in stable slot order.
vector_dust_field_deposit_grounded :: proc(ps: ^Particle_System) {
    vector_dust_field_begin_deposit(ps)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            continue
        }
        vector_dust_field_deposit_grounded_index(ps, index)
    }
}

// Assign exact field velocity to every grounded particle in stable slot order.
vector_dust_field_assign_grounded :: proc(ps: ^Particle_System) {
    field := &ps^.vector_dust_field
    ps^.vector_dust_grounded_count = 0
    ps^.vector_dust_peak_speed_sq = 0
    ps^.vector_dust_kinetic_measure = 0
    for transfer in ps^.vector_dust_transfers[:ps^.vector_dust_transfer_count] {
        index := int(transfer.particle_index)
        velocity := vector_dust_field_sample_transfer(field, transfer)
        ps^.low_particles.vel_x[index] = velocity.x
        ps^.low_particles.vel_y[index] = velocity.y
        speed_sq := velocity.x * velocity.x + velocity.y * velocity.y
        ps^.vector_dust_peak_speed_sq = max(
            ps^.vector_dust_peak_speed_sq, speed_sq)
        ps^.vector_dust_kinetic_measure += speed_sq
    }
    ps^.vector_dust_grounded_count = ps^.vector_dust_transfer_count
}

// Run one field-only grounded XY update after ballistic and contact mutations.
vector_dust_field_update_grounded :: proc(ps: ^Particle_System, dt: f32) {
    vector_dust_field_deposit_grounded(ps)
    vector_dust_field_evolve(&ps^.vector_dust_field, dt)
    vector_dust_field_assign_grounded(ps)
}

// Solve and assign a field whose grounded deposits were prepared by the caller.
vector_dust_field_finish_grounded :: proc(ps: ^Particle_System, dt: f32) {
    vector_dust_field_evolve(&ps^.vector_dust_field, dt)
    vector_dust_field_assign_grounded(ps)
}