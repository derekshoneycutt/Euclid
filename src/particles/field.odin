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
DUST_FIELD_SPACING :: f32(1.0 / f32(DUST_FIELD_INTERVAL_COUNT))
DUST_FIELD_INVERSE_SPACING_SQ :: f32(1.0 / (DUST_FIELD_SPACING * DUST_FIELD_SPACING))
DUST_FIELD_DENSITY_EPSILON :: f32(1e-6)
DUST_FIELD_DENSITY_ENTER :: f32(0.80)
DUST_FIELD_DENSITY_EXIT :: f32(0.60)
DUST_FIELD_PRESSURE_YIELD :: f32(1.05)
DUST_FIELD_PRESSURE_STRENGTH :: f32(0.00008)
DUST_FIELD_PRESSURE_ACCELERATION_MAX :: f32(0.03)
DUST_FIELD_VISCOSITY_MIN :: f32(0.000048)
DUST_FIELD_VISCOSITY_MAX :: f32(0.000144)
DUST_FIELD_DRAG_RATE_MIN :: f32(1.5)
DUST_FIELD_DRAG_RATE_MAX :: f32(5.5)
DUST_FIELD_WAKE_SPEED_SQ :: f32(2.5e-8)
DUST_FIELD_SLEEP_SPEED_SQ :: f32(1e-8)
DUST_FIELD_QUIET_FRAMES :: u16(45)

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

// Build candidate density from every live grounded low-layer particle.
dust_field_build_candidate_density :: proc(ps: ^Particle_System) {
    dust_field_reset_active(&ps^.dust_field)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        dust_field_deposit_scalar(&ps^.dust_field,
            &ps^.dust_field.candidate_density, position, 1)
    }
}

// Apply grounded density hysteresis to authoritative aggregate membership.
dust_field_classify_particles :: proc(ps: ^Particle_System) {
    ps^.dust_aggregate_count = 0
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.low_particles.alive[index] ||
            ps^.low_particles.pos_z[index] > DUST_FLOOR_Z {
            ps^.dust_aggregate[index] = false
            ps^.dust_field_quiet_frames[index] = 0
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        density := dust_field_sample_scalar(
            &ps^.dust_field.candidate_density, position)
        threshold := DUST_FIELD_DENSITY_EXIT if ps^.dust_aggregate[index] else
            DUST_FIELD_DENSITY_ENTER
        ps^.dust_aggregate[index] = density >= threshold
        if ps^.dust_aggregate[index] {
            ps^.dust_aggregate_count += 1
        } else {
            ps^.dust_field_quiet_frames[index] = 0
        }
    }
}

// Rebuild candidate density and classify current aggregate membership.
dust_field_prepare_membership :: proc(ps: ^Particle_System) {
    dust_field_build_candidate_density(ps)
    dust_field_classify_particles(ps)
}

// Rebuild current aggregate density, momentum, color, and visual coverage.
dust_field_deposit_aggregate :: proc(ps: ^Particle_System) {
    dust_field_reset_active(&ps^.dust_field)
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.dust_aggregate[index] {
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        velocity := Vector2{ps^.low_particles.vel_x[index],
            ps^.low_particles.vel_y[index]}
        dust_field_deposit_particle(ps, index, position, velocity)
    }
}

// Deposit one aggregate particle's physical and visual field contribution.
dust_field_deposit_particle :: proc(ps: ^Particle_System, particle_index: int,
        position, velocity: Vector2) {
    particle := ps^.low_particles[particle_index]
    alpha := f32(1)
    if particle.life > 0 {
        alpha = math.clamp(1 - particle.age / particle.life, f32(0), f32(1))
    }
    color_scale := alpha / 255
    stencil := dust_field_stencil(position)
    for stencil_index in 0..<stencil.count {
        node := int(stencil.indices[stencil_index])
        weight := stencil.weights[stencil_index]
        dust_field_mark_active(&ps^.dust_field, node)
        ps^.dust_field.density[node] += weight
        ps^.dust_field.momentum_x[node] += velocity.x * weight
        ps^.dust_field.momentum_y[node] += velocity.y * weight
        ps^.dust_field.color_r[node] += f32(particle.color.r) * color_scale * weight
        ps^.dust_field.color_g[node] += f32(particle.color.g) * color_scale * weight
        ps^.dust_field.color_b[node] += f32(particle.color.b) * color_scale * weight
        ps^.dust_field.coverage[node] += alpha * weight
    }
}

// Convert deposited momentum to nodal velocity before field evolution.
dust_field_initialize_velocity :: proc(field: ^Dust_Field_State) {
    for active_index in 0..<field^.active_count {
        node := int(field^.active_nodes[active_index])
        density := field^.density[node]
        if density <= DUST_FIELD_DENSITY_EPSILON {
            continue
        }
        field^.velocity_x[node] = field^.momentum_x[node] / density
        field^.velocity_y[node] = field^.momentum_y[node] / density
    }
}

// Add one cardinal derivative halo around deposited field support.
dust_field_expand_active_halo :: proc(field: ^Dust_Field_State) {
    deposited_count := field^.active_count
    for active_index in 0..<deposited_count {
        node := int(field^.active_nodes[active_index])
        x := node % DUST_FIELD_DIM
        y := node / DUST_FIELD_DIM
        if x > 0 {dust_field_mark_active(field, node - 1)}
        if x + 1 < DUST_FIELD_DIM {dust_field_mark_active(field, node + 1)}
        if y > 0 {dust_field_mark_active(field, node - DUST_FIELD_DIM)}
        if y + 1 < DUST_FIELD_DIM {
            dust_field_mark_active(field, node + DUST_FIELD_DIM)
        }
    }
}

// Return one clamped cardinal neighbor index for a field node.
dust_field_neighbor :: #force_inline proc(node, offset_x, offset_y: int) -> int {
    x := clamp(node % DUST_FIELD_DIM + offset_x, 0, DUST_FIELD_DIM - 1)
    y := clamp(node / DUST_FIELD_DIM + offset_y, 0, DUST_FIELD_DIM - 1)
    return y * DUST_FIELD_DIM + x
}

// Evaluate pressure from density above the accepted packed-state yield.
dust_field_pressure :: #force_inline proc(density: f32) -> f32 {
    excess := max(density - DUST_FIELD_PRESSURE_YIELD, f32(0))
    return DUST_FIELD_PRESSURE_STRENGTH * excess * excess
}

// Map density to a clamped aggregate response fraction.
dust_field_density_response :: #force_inline proc(density: f32) -> f32 {
    return math.clamp((density - DUST_FIELD_DENSITY_EXIT) /
        (2 - DUST_FIELD_DENSITY_EXIT), f32(0), f32(1))
}

// Evaluate the centered pressure gradient at one field node.
dust_field_pressure_gradient :: proc(field: ^Dust_Field_State, node: int) -> Vector2 {
    left := dust_field_neighbor(node, -1, 0)
    right := dust_field_neighbor(node, 1, 0)
    down := dust_field_neighbor(node, 0, -1)
    up := dust_field_neighbor(node, 0, 1)
    scale := f32(0.5) / DUST_FIELD_SPACING
    return {
        (dust_field_pressure(field^.density[right]) -
            dust_field_pressure(field^.density[left])) * scale,
        (dust_field_pressure(field^.density[up]) -
            dust_field_pressure(field^.density[down])) * scale,
    }
}

// Evaluate the cardinal velocity Laplacian at one field node.
dust_field_velocity_laplacian :: proc(field: ^Dust_Field_State,
        node: int) -> Vector2 {
    left := dust_field_neighbor(node, -1, 0)
    right := dust_field_neighbor(node, 1, 0)
    down := dust_field_neighbor(node, 0, -1)
    up := dust_field_neighbor(node, 0, 1)
    return {
        (field^.velocity_x[left] + field^.velocity_x[right] +
            field^.velocity_x[down] + field^.velocity_x[up] -
            4 * field^.velocity_x[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
        (field^.velocity_y[left] + field^.velocity_y[right] +
            field^.velocity_y[down] + field^.velocity_y[up] -
            4 * field^.velocity_y[node]) * DUST_FIELD_INVERSE_SPACING_SQ,
    }
}

// Evolve one occupied node through pressure, smoothing, and ground drag.
dust_field_evolve_node :: proc(field: ^Dust_Field_State, node: int,
        dt: f32) -> Vector2 {
    density := field^.density[node]
    if density <= DUST_FIELD_DENSITY_EPSILON {
        return {}
    }
    gradient := dust_field_pressure_gradient(field, node)
    pressure_x := math.clamp(-gradient.x / density,
        -DUST_FIELD_PRESSURE_ACCELERATION_MAX, DUST_FIELD_PRESSURE_ACCELERATION_MAX)
    pressure_y := math.clamp(-gradient.y / density,
        -DUST_FIELD_PRESSURE_ACCELERATION_MAX, DUST_FIELD_PRESSURE_ACCELERATION_MAX)
    response := dust_field_density_response(density)
    viscosity := math.lerp(
        DUST_FIELD_VISCOSITY_MIN, DUST_FIELD_VISCOSITY_MAX, response)
    laplacian := dust_field_velocity_laplacian(field, node)
    drag_rate := math.lerp(DUST_FIELD_DRAG_RATE_MIN, DUST_FIELD_DRAG_RATE_MAX, response)
    drag := f32(math.exp(f64(-drag_rate * dt)))
    return {
        (field^.velocity_x[node] + dt * (pressure_x + viscosity * laplacian.x)) * drag,
        (field^.velocity_y[node] + dt * (pressure_y + viscosity * laplacian.y)) * drag,
    }
}

// Evolve active aggregate support into ping-pong velocity storage.
dust_field_evolve :: proc(ps: ^Particle_System, dt: f32) {
    field := &ps^.dust_field
    dust_field_initialize_velocity(field)
    dust_field_expand_active_halo(field)
    ps^.dust_field_pressure_node_count = 0
    ps^.dust_field_peak_density = 0
    ps^.dust_field_peak_speed = 0
    ps^.dust_field_kinetic_measure = 0
    for active_index in 0..<field^.active_count {
        node := int(field^.active_nodes[active_index])
        next := dust_field_evolve_node(field, node, dt)
        field^.next_velocity_x[node] = next.x
        field^.next_velocity_y[node] = next.y
        dust_field_observe_node(ps, node, next)
    }
    for active_index in 0..<field^.active_count {
        node := int(field^.active_nodes[active_index])
        field^.velocity_x[node] = field^.next_velocity_x[node]
        field^.velocity_y[node] = field^.next_velocity_y[node]
        field^.next_velocity_x[node] = 0
        field^.next_velocity_y[node] = 0
    }
}

// Accumulate bounded aggregate field summaries for evidence and sleep policy.
dust_field_observe_node :: proc(ps: ^Particle_System, node: int, velocity: Vector2) {
    density := ps^.dust_field.density[node]
    speed_sq := velocity.x * velocity.x + velocity.y * velocity.y
    ps^.dust_field_peak_density = max(ps^.dust_field_peak_density, density)
    ps^.dust_field_peak_speed = max(
        ps^.dust_field_peak_speed, f32(math.sqrt(f64(speed_sq))))
    ps^.dust_field_kinetic_measure += density * speed_sq
    if density > DUST_FIELD_PRESSURE_YIELD {
        ps^.dust_field_pressure_node_count += 1
    }
}

// Assign exact reconstructed field velocity to every aggregate particle.
dust_field_assign_particle_velocities :: proc(ps: ^Particle_System) {
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.dust_aggregate[index] {
            continue
        }
        position := Vector2{ps^.low_particles.pos_x[index],
            ps^.low_particles.pos_y[index]}
        velocity := dust_field_sample_vector(&ps^.dust_field.velocity_x,
            &ps^.dust_field.velocity_y, position)
        ps^.low_particles.vel_x[index] = velocity.x
        ps^.low_particles.vel_y[index] = velocity.y
    }
}

// Update aggregate sleep state from local reconstructed field activity.
dust_field_update_sleeping :: proc(ps: ^Particle_System) {
    for index in 0..<ps^.use_max_dust_particles {
        if !ps^.dust_aggregate[index] {
            continue
        }
        speed_sq := ps^.low_particles.vel_x[index] * ps^.low_particles.vel_x[index] +
            ps^.low_particles.vel_y[index] * ps^.low_particles.vel_y[index]
        if speed_sq > DUST_FIELD_WAKE_SPEED_SQ {
            ps^.dust_field_quiet_frames[index] = 0
            if ps^.dust_sleeping[index] {
                wake_dust_particle(ps, index)
            }
            continue
        }
        if speed_sq > DUST_FIELD_SLEEP_SPEED_SQ || ps^.dust_activity_frames[index] > 0 {
            ps^.dust_field_quiet_frames[index] = 0
            continue
        }
        ps^.dust_field_quiet_frames[index] = min(
            ps^.dust_field_quiet_frames[index] + 1, DUST_FIELD_QUIET_FRAMES)
        if ps^.dust_field_quiet_frames[index] < DUST_FIELD_QUIET_FRAMES ||
            ps^.dust_sleeping[index] {
            continue
        }
        ps^.dust_sleeping[index] = true
        ps^.dust_sleeping_count += 1
        ps^.dust_sleep_transition_count += 1
        ps^.dust_field_sleep_transition_count += 1
    }
}

// Run one complete aggregate field update after membership classification.
dust_field_update_aggregate :: proc(ps: ^Particle_System, dt: f32) {
    dust_field_deposit_aggregate(ps)
    dust_field_evolve(ps, dt)
    dust_field_assign_particle_velocities(ps)
    dust_field_update_sleeping(ps)
}

// Reset aggregate field storage, membership, and bounded summary evidence.
dust_field_reset_state :: proc(ps: ^Particle_System) {
    dust_field_reset_active(&ps^.dust_field)
    ps^.dust_aggregate_count = 0
    ps^.dust_field_pressure_node_count = 0
    ps^.dust_field_suppressed_pair_count = 0
    ps^.dust_field_peak_density = 0
    ps^.dust_field_peak_speed = 0
    ps^.dust_field_kinetic_measure = 0
    ps^.dust_field_sleep_transition_count = 0
    ps^.dust_field_wake_transition_count = 0
    for index in 0..<ps^.use_max_dust_particles {
        ps^.dust_aggregate[index] = false
        ps^.dust_field_quiet_frames[index] = 0
    }
}