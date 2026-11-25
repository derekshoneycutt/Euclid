using LinearAlgebra

@testset "Shape query kinds match canonical geometry ABI" begin
    expected = (
        (:SHAPE_KIND_POINT, 0), (:SHAPE_KIND_LINE, 1),
        (:SHAPE_KIND_ARC, 2), (:SHAPE_KIND_FILLED_ARC, 3),
        (:SHAPE_KIND_CIRCLE_REGION, 4), (:SHAPE_KIND_TROCHOID, 5),
        (:SHAPE_KIND_CYCLOID, 7), (:SHAPE_KIND_PARABOLA, 9),
        (:SHAPE_KIND_HYPERBOLA, 10), (:SHAPE_KIND_POLYGON, 13))
    for (name, value) in expected
        @test getfield(OdinJuliaBridge, name) === Int32(value)
    end

end

"""Prepare one managed typed result with distinct, coplanar defining positions."""
function transform_test_fixture(shape)
    runtime = EuclidRepl.create_runtime()
    EuclidRepl.set_active_operation_context!(
        runtime, UInt64(2), UInt64(3), UInt64(4))
    definition = EuclidRepl.shape_motion_definition(shape)
    REPL_TEST_KINDS[definition.host] = first(definition.kinds)
    for (index, id) in pairs(definition.ids)
        REPL_TEST_POSITIONS[id] = (0.2f0 * index, 0.3f0, 0f0)
    end
    definition.oriented &&
        (REPL_TEST_ORIENTATIONS[definition.host] = (0f0, 0f0, 0f0, 1f0))
    EuclidRepl.track_managed_host!(runtime.session, definition.host)
    return runtime, definition
end

"""Evaluate an independent Float64 Rodrigues oracle for world-axis motion."""
function transform_test_oracle(point, first, second, angle)
    axis = normalize(Float64.(second .- first))
    relative = Float64.(point .- first)
    return first .+ relative .* cos(angle) .+
        cross(axis, relative) .* sin(angle) .+
        axis .* dot(axis, relative) .* (1 - cos(angle))
end

"""Exercise the retained Julia transform oracle across queued activation boundaries."""
function drain_transform_test!(runtime)
    for _ in 1:20
        session = runtime.session
        if session.active_job === nothing
            session.pending_count == 0 && return
            session.active_job = session.pending[session.pending_head]
            session.pending[session.pending_head] = nothing
            session.pending_head = mod1(
                session.pending_head + 1, EuclidRepl.ACTION_QUEUE_CAPACITY)
            session.pending_count -= 1
        end
        job = session.active_job
        if !job.activated
            EuclidRepl.activate_payload!(TEST_STATE_PTR, job.payload)
            job.activated = true
        end
        EuclidRepl.render_payload!(
            TEST_STATE_PTR, job.duration, job.duration, job.payload)
        session.completed_count += 1
        session.active_job = nothing
    end
    error("transformation test queue did not drain")
end

@testset "Terminal rigid dispatch copies snapshots instead of sampling Julia mechanics" begin
    empty!(REPL_TEST_NATIVE_REQUESTS)
    shape = OdinJuliaBridge.BridgeShapeCircle(0, 899)
    runtime, _ = transform_test_fixture(shape)
    EuclidRepl.rotate_x!(
        runtime, TEST_STATE_PTR, shape, -4pi; pivot=[0, 0, 0], duration=1)
    payload = runtime.session.active_job.payload
    EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
    EuclidRepl.render_payload!(TEST_STATE_PTR, 0.125f0, 1f0, payload)
    @test length(REPL_TEST_NATIVE_REQUESTS) == 2
    point, plane = REPL_TEST_NATIVE_REQUESTS
    @test point.kind == OdinJuliaBridge.NATIVE_MODIFIER_ROTATE_POINT
    @test plane.kind == OdinJuliaBridge.NATIVE_MODIFIER_ROTATE_SHAPE_ORIENTATION
    @test point.start == Tuple(only(payload.start_positions))
    @test point.elapsed == plane.elapsed == 0.125f0
    @test point.angle == plane.angle == Float32(-4pi)
    @test (plane.displacement..., plane.scalar) == payload.start_orientation
end

@testset "Rigid transforms submit one bounded native group recipe" begin
    empty!(REPL_TEST_GROUP_SUBMISSIONS)
    shape = OdinJuliaBridge.BridgeShapeCircle(0, 899)
    runtime, definition = transform_test_fixture(shape)
    EuclidRepl.set_active_operation_context!(
        runtime, UInt64(2), UInt64(3), UInt64(4))
    EuclidRepl.rotate_z!(
        runtime, TEST_STATE_PTR, shape, -1.25f0;
        pivot=Float32[0.1, 0.2, 0], duration=2f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)

    job = runtime.session.active_job
    request_id, request = only(REPL_TEST_GROUP_SUBMISSIONS)
    @test job.native_submitted
    @test request_id == job.native_request_id
    @test request.target_count == 1
    @test request.targets[1].entity == only(definition.ids)
    @test request.targets[1].start == Tuple(REPL_TEST_POSITIONS[only(definition.ids)])
    @test request.modifier.kind == OdinJuliaBridge.NATIVE_MODIFIER_ROTATE_POINT
    @test request.modifier.angle == -1.25f0
    @test request.oriented
    @test request.orientation_entity == definition.host
    @test request.orientation == (0f0, 0f0, 0f0, 1f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test length(REPL_TEST_GROUP_SUBMISSIONS) == 1
end

@testset "Unified typed world transformations" begin
    shapes = (
        OdinJuliaBridge.BridgeShapeEntityResult(0, 900),
        OdinJuliaBridge.BridgeShapeLine(0, 901, 902, 903),
        OdinJuliaBridge.BridgeShapeTriangle(0, 904, 905, 906, 907),
        OdinJuliaBridge.BridgeShapeSquare(0, 908, 909, 910, 911, 912),
        OdinJuliaBridge.BridgeShapePentagon(0, 913, 914, 915, 916, 917, 918),
        OdinJuliaBridge.BridgeShapeCircle(0, 919),
        OdinJuliaBridge.BridgeShapeCircleRegion(0, 920, 921, 922),
        OdinJuliaBridge.BridgeShapeCycloidResult(0, 923, 924, 925),
        OdinJuliaBridge.BridgeShapeTrochoidResult(0, 926),
        OdinJuliaBridge.BridgeShapeConicResult(0, 927))
    pivot = Float32[0.4, -0.2, 0.1]
    for shape in shapes, axis in (
        Float32[1, 0, 0], Float32[0, 1, 0],
        Float32[0, 0, 1], Float32[1, 2, -3])
        runtime, definition = transform_test_fixture(shape)
        ids, oriented = definition.ids, definition.oriented
        starts = [collect(REPL_TEST_POSITIONS[id]) for id in ids]
        returned = EuclidRepl.rotate!(
            runtime, TEST_STATE_PTR, shape, pivot, pivot + axis, -2.7;
            duration=1)
        @test returned === shape
        payload = runtime.session.active_job.payload
        EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
        runtime.session.active_job.activated = true
        for progress in (0f0, 0.25f0, 0.5f0, 1f0)
            EuclidRepl.render_payload!(TEST_STATE_PTR, progress, 1f0, payload)
            progress == 1f0 && EuclidRepl.finalize_payload!(TEST_STATE_PTR, payload)
            for (id, start) in zip(ids, starts)
                expected = transform_test_oracle(start, pivot, pivot + axis, -2.7progress)
                @test collect(REPL_TEST_POSITIONS[id]) ≈ expected atol=2f-6
            end
            if oriented
                normal = EuclidRepl.motion_rotate(
                    REPL_TEST_ORIENTATIONS[payload.host_id], (0f0, 0f0, 1f0))
                expected = transform_test_oracle(
                    Float32[0, 0, 1], zeros(Float32, 3), axis, -2.7progress)
                @test collect(normal) ≈ expected atol=2f-6
            end
        end
        @test EuclidRepl.shape_motion_definition(shape).ids == ids
        runtime, definition = transform_test_fixture(shape)
        ids, oriented = definition.ids, definition.oriented
        starts = [collect(REPL_TEST_POSITIONS[id]) for id in ids]
        @test EuclidRepl.translate!(
            runtime, TEST_STATE_PTR, shape, [2, -3, 4]; duration=1) === shape
        payload = runtime.session.active_job.payload
        EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
        EuclidRepl.render_payload!(TEST_STATE_PTR, 1f0, 1f0, payload)
        for (id, start) in zip(ids, starts)
            @test collect(REPL_TEST_POSITIONS[id]) ≈ start + [2, -3, 4]
        end
        oriented && @test REPL_TEST_ORIENTATIONS[
            runtime.session.managed_host_ids[1]] == (0f0, 0f0, 0f0, 1f0)
    end
end

@testset "Signed paths, queue composition and reflection" begin
    shape = OdinJuliaBridge.BridgeShapeCircle(0, 950)
    runtime, definition = transform_test_fixture(shape)
    ids = definition.ids
    EuclidRepl.rotate_x!(runtime, TEST_STATE_PTR, shape, 4pi;
        pivot=[0, 0, 0], duration=1)
    payload = runtime.session.active_job.payload
    EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
    runtime.session.active_job.activated = true
    EuclidRepl.render_payload!(TEST_STATE_PTR, 0.125f0, 1f0, payload)
    @test REPL_TEST_POSITIONS[ids[1]][3] ≈ 0.3f0 atol=1f-6
    drain_transform_test!(runtime)
    @test collect(REPL_TEST_POSITIONS[ids[1]]) ≈ [0.2, 0.3, 0] atol=1f-6
    results = Vector{Float32}[]
    for operations in ((EuclidRepl.rotate_x!, EuclidRepl.rotate_y!),
        (EuclidRepl.rotate_y!, EuclidRepl.rotate_x!))
        runtime, definition = transform_test_fixture(shape)
        ids = definition.ids
        for operation in operations
            operation(runtime, TEST_STATE_PTR, shape, pi/2; pivot=[0, 0, 0])
        end
        drain_transform_test!(runtime)
        push!(results, collect(REPL_TEST_POSITIONS[ids[1]]))
    end
    @test !isapprox(results[1], results[2])
    for direction in (1f0, -1f0)
        runtime, definition = transform_test_fixture(shape)
        ids = definition.ids
        @test EuclidRepl.reflect!(runtime, TEST_STATE_PTR, shape,
            [0, 0, 0], [direction, 0, 0]; duration=1) === shape
        payload = runtime.session.active_job.payload
        EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
        runtime.session.active_job.activated = true
        EuclidRepl.render_payload!(TEST_STATE_PTR, 0.5f0, 1f0, payload)
        @test REPL_TEST_POSITIONS[ids[1]][3] ≈ 0.3f0 * direction atol=1f-6
        drain_transform_test!(runtime)
        @test collect(REPL_TEST_POSITIONS[ids[1]]) ≈ [0.2, -0.3, 0] atol=1f-6
    end
    runtime, _ = transform_test_fixture(shape)
    EuclidRepl.reflect!(runtime, TEST_STATE_PTR, shape, [0, 0, 1], [1, 0, 1])
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test_throws ArgumentError EuclidRepl.run_active_job_frame!(
        runtime, TEST_STATE_PTR, 1f0)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).failed
end

@testset "Point batches share directed reflection and activation starts" begin
    shape = OdinJuliaBridge.BridgeShapeLine(0, 970, 971, 972)
    runtime, definition = transform_test_fixture(shape)
    ids = definition.ids
    @test EuclidRepl.reflect2d_points_x_axis!(
        runtime, TEST_STATE_PTR, ids; duration=1) == ids
    REPL_TEST_POSITIONS[ids[2]] = (0.4f0, -0.3f0, 0f0)
    payload = runtime.session.active_job.payload
    EuclidRepl.activate_payload!(TEST_STATE_PTR, payload)
    runtime.session.active_job.activated = true
    EuclidRepl.render_payload!(TEST_STATE_PTR, 0.5f0, 1f0, payload)
    @test REPL_TEST_POSITIONS[ids[1]][3] ≈ 0.3f0 atol=1f-6
    @test REPL_TEST_POSITIONS[ids[2]][3] ≈ -0.3f0 atol=1f-6
    drain_transform_test!(runtime)
    @test collect(REPL_TEST_POSITIONS[ids[1]]) ≈ [0.2, -0.3, 0] atol=1f-6
    @test collect(REPL_TEST_POSITIONS[ids[2]]) ≈ [0.4, 0.3, 0] atol=1f-6
end

@testset "Unified transform admission failures" begin
    shape = OdinJuliaBridge.BridgeShapeCircle(0, 960)
    runtime, _ = transform_test_fixture(shape)
    @test_throws ArgumentError EuclidRepl.translate!(
        runtime, TEST_STATE_PTR, shape, [NaN, 0, 0])
    @test_throws ArgumentError EuclidRepl.rotate!(
        runtime, TEST_STATE_PTR, shape, [0, 0, 0], [0, 0, 0], 1)
    @test_throws ArgumentError EuclidRepl.rotate_z!(
        runtime, TEST_STATE_PTR, shape, Inf; pivot=[0, 0, 0])
    REPL_TEST_KINDS[shape.host_id] = 0
    @test_throws ArgumentError EuclidRepl.translate!(
        runtime, TEST_STATE_PTR, shape, [0, 0, 0])
    empty!(runtime.session.managed_host_ids)
    @test_throws ArgumentError EuclidRepl.translate!(
        runtime, TEST_STATE_PTR, shape, [0, 0, 0])
end
