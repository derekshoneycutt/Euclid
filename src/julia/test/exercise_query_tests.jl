using .OdinJuliaBridge
using Test
using UUIDs

@testset "exercise references and bounded copy-out" begin
    bridge = OdinJuliaBridge
    identity = "10000000-0000-0000-0000-000000000001"
    @test bridge.parse_exercise_reference("builtin:elements-i-1") ==
        (UInt32(1), "elements-i-1")
    @test bridge.parse_exercise_reference("builtin:" * identity) == (UInt32(2), identity)
    for invalid in ("elements-i-1", "other:elements-i-1", "builtin:",
        "builtin:Elements-i-1", "builtin:" * "a"^17,
        "builtin:00000000-0000-0000-0000-000000000000")
        @test_throws ArgumentError bridge.parse_exercise_reference(invalid)
    end

    @testset "user exercise namespaces, draft bounds, and operation ABI" begin
        bridge = OdinJuliaBridge
        identity = "10000000-0000-0000-0000-000000000001"
        @test bridge.exercise_reference_namespace("builtin:elements-i-1") == :builtin
        @test bridge.exercise_reference_namespace("user:triangle") == :user
        @test bridge.parse_user_exercise_reference("user:triangle") ==
            (bridge.USER_EXERCISE_READ_REFERENCE, "triangle")
        @test bridge.parse_user_exercise_reference("user:" * identity) ==
            (bridge.USER_EXERCISE_READ_IDENTITY, identity)
        for invalid in ("triangle", "builtin:triangle", "user:", "user:Uppercase",
            "user:" * "a"^17, "user:" * "00000000-0000-0000-0000-000000000000")
            @test_throws ArgumentError bridge.parse_user_exercise_reference(invalid)
        end
        @test bridge.validate_user_exercise_draft(
            "triangle", "Triangle", "Instructions") == "triangle"
        @test_throws ArgumentError bridge.validate_user_exercise_draft(
            "Uppercase", "Triangle", "Instructions")
        @test_throws ArgumentError bridge.validate_user_exercise_draft(
            "triangle", " ", "Instructions")
        @test_throws ArgumentError bridge.validate_user_exercise_draft(
            "triangle", "x"^257, "Instructions")
        @test_throws ArgumentError bridge.validate_user_exercise_draft(
            "triangle", "Triangle", "x"^(bridge.EXERCISE_HEADER_MAX_TEXT_BYTES + 1))

        @test sizeof(bridge.UserExerciseInputABI) == 96
        @test fieldoffset(bridge.UserExerciseInputABI, 2) == 8
        @test fieldoffset(bridge.UserExerciseInputABI, 10) == 72
        @test fieldoffset(bridge.UserExerciseInputABI, 12) == 84
        @test fieldoffset(bridge.UserExerciseInputABI, 14) == 90
        @test bridge.check_user_exercise_status(UInt32(1)) === nothing
        for (status, reason) in ((0, :unavailable), (2, :invalid_request),
            (3, :not_found), (4, :retired), (5, :database_failed),
            (6, :missing_animation), (7, :busy), (8, :reference_collision),
            (9, :identity_collision), (10, :read_only), (11, :superseded))
            failure = try
                bridge.check_user_exercise_status(UInt32(status))
            catch error
                error
            end
            @test failure isa UserExerciseError
            @test failure.reason == reason
        end
    end
    @test bridge.canonical_exercise_uuid(UUID(identity)) == identity
    @test bridge.validate_exercise_page(0, 16) == (UInt32(0), UInt16(16))
    for (offset, limit) in ((-1, 1), (0, 0), (0, 17), (typemax(UInt32), 16))
        @test_throws ArgumentError bridge.validate_exercise_page(offset, limit)
    end
    @test sizeof(bridge.ExerciseQueryRowABI) == 348
    @test sizeof(bridge.ExerciseQueryMetadataABI) == 20
    @test sizeof(bridge.ExerciseQueryInputABI) == 24
    @test fieldoffset(bridge.ExerciseQueryInputABI, 6) == 22
    @test sizeof(bridge.ExerciseQueryBuffersABI) == 24
    @test fieldoffset(bridge.ExerciseQueryBuffersABI, 3) == 16
    @test bridge.exercise_query_text((0x61, 0x62, 0x00, 0x00)) == "ab"
    @test bridge.check_exercise_query_status(UInt32(1)) === nothing
    for (status, reason) in ((0, :unavailable), (2, :invalid_request), (3, :not_found),
        (4, :retired), (5, :database_failed), (6, :missing_animation), (7, :superseded))
        failure = try
            bridge.check_exercise_query_status(UInt32(status))
        catch error
            error
        end
        @test failure isa ExerciseQueryError
        @test failure.reason == reason
    end
end
