package particles

import particlemodel "model"

import "core:math"

import rl "vendor:raylib"

Dust_Field_State :: particlemodel.Dust_Field_State
Dust_Field_Stencil :: particlemodel.Dust_Field_Stencil
Dust_Field_Bounds :: particlemodel.Dust_Field_Bounds
Dust_Transfer :: particlemodel.Dust_Transfer

DUST_FIELD_DIM :: particlemodel.DUST_FIELD_DIM
DUST_FIELD_NODE_COUNT :: particlemodel.DUST_FIELD_NODE_COUNT
DUST_FIELD_INTERVAL_COUNT :: DUST_FIELD_DIM - 1
DUST_FIELD_SPACING :: f32(1.0 / f32(DUST_FIELD_INTERVAL_COUNT))
DUST_FIELD_INVERSE_SPACING_SQ :: f32(1.0 / (DUST_FIELD_SPACING * DUST_FIELD_SPACING))

Dust_Field_Neighbors :: struct {
    left, right, down, up: int,
}

DUST_DENSITY_EPSILON :: f32(1e-6)
DUST_PRESSURE_YIELD :: f32(1.05)
DUST_PRESSURE_STRENGTH :: f32(0.00008)
DUST_PRESSURE_ACCELERATION_MAX :: f32(0.03)
DUST_VISCOSITY :: f32(0.000048)
DUST_DRAG_RATE :: f32(1.5)

// Map a board-space position onto the fixed dust-field lattice.
dust_field_coordinates :: proc(position: rl.Vector2) -> rl.Vector2 {
    scale := f32(DUST_FIELD_INTERVAL_COUNT)
    return {
        math.clamp(position.x, f32(0), f32(1)) * scale,
        math.clamp(position.y, f32(0), f32(1)) * scale,
    }
}

// Build compact transfer coordinates for one clamped board-space position.
dust_field_transfer :: proc(
    position: rl.Vector2, particle_index: int = -1) -> Dust_Transfer {
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
dust_field_transfer_stencil :: #force_inline proc(
    transfer: Dust_Transfer) -> Dust_Field_Stencil {
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
dust_field_stencil :: proc(position: rl.Vector2) -> Dust_Field_Stencil {
    return dust_field_transfer_stencil(dust_field_transfer(position))
}

// Clear all five fixed field planes before the next particle-to-grid transfer.
dust_field_clear :: proc(field: ^Dust_Field_State) {
    field^ = {}
}

// Clear deposition planes inside one previously visited inclusive rectangle.
dust_field_clear_bounds :: proc(
    field: ^Dust_Field_State, bounds: Dust_Field_Bounds) {
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
dust_field_prepare :: proc(field: ^Dust_Field_State) {
    dust_field_clear_bounds(field, field^.previous_solve_bounds)
    field^.support_bounds = {}
    field^.previous_solve_bounds = {}
}

// Include one bilinear stencil's two-by-two node footprint in current support.
dust_field_include_stencil :: proc(
    field: ^Dust_Field_State, stencil: Dust_Field_Stencil) {
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
dust_field_solve_bounds :: proc(
    support: Dust_Field_Bounds) -> Dust_Field_Bounds {
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
dust_field_deposit_transfer :: proc(field: ^Dust_Field_State,
    transfer: Dust_Transfer, velocity: rl.Vector2) {
    stencil := dust_field_transfer_stencil(transfer)
    dust_field_include_stencil(field, stencil)
    for stencil_index in 0..<particlemodel.DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        field^.density[node] += weight
        field^.momentum_x[node] += velocity.x * weight
        field^.momentum_y[node] += velocity.y * weight
    }
}

// Deposit one position's unit density and XY momentum.
dust_field_deposit :: proc(field: ^Dust_Field_State,
    position, velocity: rl.Vector2) {
    dust_field_deposit_transfer(
        field, dust_field_transfer(position), velocity)
}

// Intersect one tool sample's radius with occupied field support.
dust_field_tool_bounds :: proc(
    field: ^Dust_Field_State, position: rl.Vector2) -> Dust_Field_Bounds {
    radius := f32(DUST_CONTACT_PUSH_RADIUS)
    return {
        min_x = i32(max(int(math.ceil(f64((position.x - radius) /
            DUST_FIELD_SPACING))), int(field^.support_bounds.min_x))),
        min_y = i32(max(int(math.ceil(f64((position.y - radius) /
            DUST_FIELD_SPACING))), int(field^.support_bounds.min_y))),
        max_x = i32(min(int(math.floor(f64((position.x + radius) /
            DUST_FIELD_SPACING))), int(field^.support_bounds.max_x))),
        max_y = i32(min(int(math.floor(f64((position.y + radius) /
            DUST_FIELD_SPACING))), int(field^.support_bounds.max_y))),
        valid = true,
    }
}

// Add one radial or authored-direction impulse to occupied nodes near a tool sample.
dust_field_apply_tool_impulse :: proc(
    field: ^Dust_Field_State, position, direction: rl.Vector2,
    directional: bool) -> u64 {
    if !field^.support_bounds.valid {return 0}
    direction_length := f32(math.sqrt(f64(
        direction.x * direction.x + direction.y * direction.y)))
    if directional && direction_length <= DUST_DENSITY_EPSILON {return 0}
    radius := f32(DUST_CONTACT_PUSH_RADIUS)
    bounds := dust_field_tool_bounds(field, position)
    if bounds.min_x > bounds.max_x || bounds.min_y > bounds.max_y {return 0}
    visits: u64
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        for x in int(bounds.min_x)..=int(bounds.max_x) {
            visits += 1
            node := y * DUST_FIELD_DIM + x
            density := field^.density[node]
            delta_x := f32(x) * DUST_FIELD_SPACING - position.x
            delta_y := f32(y) * DUST_FIELD_SPACING - position.y
            distance_sq := delta_x * delta_x + delta_y * delta_y
            if density <= DUST_DENSITY_EPSILON || distance_sq > radius * radius {
                continue
            }
            distance := f32(math.sqrt(f64(distance_sq)))
            falloff := DUST_CONTACT_PUSH_SPEED * (1 - distance / radius)
            if directional {
                field^.momentum_x[node] +=
                    density * direction.x * falloff / direction_length
                field^.momentum_y[node] +=
                    density * direction.y * falloff / direction_length
            } else if distance > 0 {
                field^.momentum_x[node] += density * delta_x * falloff / distance
                field^.momentum_y[node] += density * delta_y * falloff / distance
            }
        }
    }
    return visits
}

// Add one radial tool-velocity impulse to occupied nodes inside current support.
dust_field_apply_tool_point :: proc(
    field: ^Dust_Field_State, position: rl.Vector2) -> u64 {
    return dust_field_apply_tool_impulse(field, position, {}, false)
}

// Add one motion-directed filled-sweep impulse to nearby occupied nodes.
dust_field_apply_tool_motion :: proc(
    field: ^Dust_Field_State, position, direction: rl.Vector2) -> u64 {
    return dust_field_apply_tool_impulse(field, position, direction, true)
}

// Convert deposited momentum to velocity inside one inclusive rectangle.
dust_field_normalize :: proc(
    field: ^Dust_Field_State, bounds: Dust_Field_Bounds) {
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        row := y * DUST_FIELD_DIM
        for x in int(bounds.min_x)..=int(bounds.max_x) {
            node := row + x
            density := field^.density[node]
            if density <= DUST_DENSITY_EPSILON {
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
dust_field_sample_transfer :: proc(
    field: ^Dust_Field_State, transfer: Dust_Transfer) -> rl.Vector2 {
    stencil := dust_field_transfer_stencil(transfer)
    result: rl.Vector2
    for stencil_index in 0..<particlemodel.DUST_FIELD_STENCIL_CAP {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        result.x += field^.solved_velocity_x[node] * weight
        result.y += field^.solved_velocity_y[node] * weight
    }
    return result
}

// Reconstruct one XY velocity at a board-space position.
dust_field_sample :: proc(
    field: ^Dust_Field_State,
    position: rl.Vector2) -> rl.Vector2 {
    return dust_field_sample_transfer(
        field, dust_field_transfer(position))
}

// Evaluate yielded pressure for one deposited density value.
dust_field_pressure :: #force_inline proc(density: f32) -> f32 {
    excess := max(density - DUST_PRESSURE_YIELD, f32(0))
    return DUST_PRESSURE_STRENGTH * excess * excess
}

// Evaluate bounded pressure acceleration from resolved cardinal neighbors.
dust_field_pressure_acceleration :: #force_inline proc(
    field: ^Dust_Field_State,
    density: f32, neighbors: Dust_Field_Neighbors) -> rl.Vector2 {
    scale := f32(0.5) / DUST_FIELD_SPACING
    gradient := rl.Vector2{
        (dust_field_pressure(field^.density[neighbors.right]) -
            dust_field_pressure(field^.density[neighbors.left])) * scale,
        (dust_field_pressure(field^.density[neighbors.up]) -
            dust_field_pressure(field^.density[neighbors.down])) * scale,
    }
    return {
        math.clamp(-gradient.x / density, -DUST_PRESSURE_ACCELERATION_MAX,
            DUST_PRESSURE_ACCELERATION_MAX),
        math.clamp(-gradient.y / density, -DUST_PRESSURE_ACCELERATION_MAX,
            DUST_PRESSURE_ACCELERATION_MAX),
    }
}

// Evaluate the cardinal velocity Laplacian from resolved neighbor indices.
dust_field_laplacian :: #force_inline proc(
    field: ^Dust_Field_State,
    node: int, neighbors: Dust_Field_Neighbors) -> rl.Vector2 {
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
dust_field_evolve_node :: #force_inline proc(
    field: ^Dust_Field_State,
    node: int, neighbors: Dust_Field_Neighbors, dt: f32) -> rl.Vector2 {
    density := field^.density[node]
    if density <= DUST_DENSITY_EPSILON {
        return {}
    }
    pressure := dust_field_pressure_acceleration(
        field, density, neighbors)
    laplacian := dust_field_laplacian(field, node, neighbors)
    drag := 1 + DUST_DRAG_RATE * dt
    return {
        (field^.momentum_x[node] +
            dt * (pressure.x + DUST_VISCOSITY * laplacian.x)) / drag,
        (field^.momentum_y[node] +
            dt * (pressure.y + DUST_VISCOSITY * laplacian.y)) / drag,
    }
}

// Evolve one row using direct horizontal and caller-resolved vertical neighbors.
dust_field_evolve_row :: proc(
    field: ^Dust_Field_State,
    bounds: Dust_Field_Bounds, y: int, dt: f32) {
    row := y * DUST_FIELD_DIM
    down_row := row - DUST_FIELD_DIM * int(y > 0)
    up_row := row + DUST_FIELD_DIM * int(y + 1 < DUST_FIELD_DIM)
    for x in int(bounds.min_x)..=int(bounds.max_x) {
        node := row + x
        neighbors := Dust_Field_Neighbors{
            node - int(x > 0), node + int(x + 1 < DUST_FIELD_DIM),
            down_row + x, up_row + x}
        next := dust_field_evolve_node(
            field, node, neighbors, dt)
        field^.solved_velocity_x[node] = next.x
        field^.solved_velocity_y[node] = next.y
    }
}

// Evolve every node through one fixed explicit solve and publish its velocity.
dust_field_evolve :: proc(field: ^Dust_Field_State, dt: f32) {
    bounds := dust_field_solve_bounds(field^.support_bounds)
    if !bounds.valid {
        return
    }
    dust_field_normalize(field, bounds)
    for y in int(bounds.min_y)..=int(bounds.max_y) {
        dust_field_evolve_row(field, bounds, y, dt)
    }
    field^.previous_solve_bounds = bounds
}

// Deposit every grounded particle into the field in stable slot order.
dust_field_begin_deposit :: proc(ps: ^Particle_System) {
    field := &ps^.dust_field
    dust_field_prepare(field)
    ps^.dust_transfer_count = 0
}

// Cache and deposit one grounded particle after its local transition update.
dust_field_deposit_grounded_index :: proc(
    ps: ^Particle_System, index: int) {
    position := Vector2{ps^.low_particles.pos_x[index],
        ps^.low_particles.pos_y[index]}
    velocity := Vector2{ps^.low_particles.vel_x[index],
        ps^.low_particles.vel_y[index]}
    transfer := dust_field_transfer(position, index)
    ps^.dust_transfers[ps^.dust_transfer_count] = transfer
    ps^.dust_transfer_count += 1
    dust_field_deposit_transfer(&ps^.dust_field, transfer, velocity)
}

// Deposit every grounded particle into the field in stable slot order.
dust_field_deposit_grounded :: proc(ps: ^Particle_System) {
    dust_field_begin_deposit(ps)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            continue
        }
        dust_field_deposit_grounded_index(ps, index)
    }
}

// Assign exact field velocity to every grounded particle in stable slot order.
dust_field_assign_grounded :: proc(ps: ^Particle_System) {
    field := &ps^.dust_field
    ps^.dust_grounded_count = 0
    ps^.dust_peak_speed_sq = 0
    ps^.dust_kinetic_measure = 0
    for transfer in ps^.dust_transfers[:ps^.dust_transfer_count] {
        index := int(transfer.particle_index)
        velocity := dust_field_sample_transfer(field, transfer)
        ps^.low_particles.vel_x[index] = velocity.x
        ps^.low_particles.vel_y[index] = velocity.y
        speed_sq := velocity.x * velocity.x + velocity.y * velocity.y
        ps^.dust_peak_speed_sq = max(
            ps^.dust_peak_speed_sq, speed_sq)
        ps^.dust_kinetic_measure += speed_sq
    }
    ps^.dust_grounded_count = ps^.dust_transfer_count
}

// Run one field-only grounded XY update after ballistic and contact mutations.
dust_field_update_grounded :: proc(ps: ^Particle_System, dt: f32) {
    dust_field_deposit_grounded(ps)
    dust_field_evolve(&ps^.dust_field, dt)
    dust_field_assign_grounded(ps)
}

// Solve and assign a field whose grounded deposits were prepared by the caller.
dust_field_finish_grounded :: proc(ps: ^Particle_System, dt: f32) {
    dust_field_evolve(&ps^.dust_field, dt)
    dust_field_assign_grounded(ps)
}