package core

import "base:runtime"
import rl "vendor:raylib"

MAX_PARTICLES :: 1024
MAX_METAVALUES :: 256
MAX_KINEPOINTS :: 256
MAX_KINECONSTRAINTS :: 256
MAX_JULIA_INTERFACES :: 64

Vector2 :: [2]f32
Vector3 :: [3]f32

Jl_Value_T  :: struct {}
Jl_Function_T  :: struct {}
Jl_Symbol_T  :: struct {}
Jl_Module_T :: struct {}

EuclidJuliaAnimationInterface :: struct {
    Initiate : ^Jl_Function_T,
    Loop : ^Jl_Function_T,
    Clean : ^Jl_Function_T,
}

EuclidJuliaInterface :: struct {
    InitScripts : ^Jl_Function_T,
    GlobalLoop : ^Jl_Function_T,

    NullAnimation : EuclidJuliaAnimationInterface,

    CurrentAnimation : ^EuclidJuliaAnimationInterface,

    Animations : [MAX_JULIA_INTERFACES]EuclidJuliaAnimationInterface,
    NextAnimationIndex : int,
}

IsoScale :: struct {
    Scale : f32,
    XOffset : f32,
    YOffset : f32
}

KineShapePointType :: enum {
    Point,
    Line,
    Circle,
    Pen,
    Compass,
}

KineShapePoint :: struct {
    Type : KineShapePointType,

    Position : Maybe(Vector3),
    Color : Maybe(rl.Color),
    ActiveColor : Maybe(rl.Color),
    BrushSize : f32,

    ActiveChild: int,
    ChildCount : int,
    ChildPointHead : int,
    NextChildPoint : int,

    DoDraw : bool,
}

KineConstraintTrait :: enum {
    Distance = 1,
    Floor = (1 << 1),
    SnapToFloor = (1 << 2),
    SnapPoint = (1 << 3),
    MaxAngle = (1 << 4),
    CenterPivot = (1 << 5)
}

KineConstraint :: struct {
    Traits : KineConstraintTrait,

    OnPoint : int,
    Restriction : Vector3,
    Bounce : f32,
    Allowance : f32,
    DependOn : i32,
    ChildOffset : Maybe(i32),

    DoApply : bool
}



KineShapeCompass :: struct {
    HostId : int,
    Joint1Id : int,
    PivotId : int,
    Joint2Id : int,

    CenterPivotId : int,
    Limb1LengthId : int,
    Limb2LengthId : int,
    Point1FloorId : int,
    PivotFLoorId : int,
    Point2FloorId : int,
    LockPoint1Id : int,
    LockPoint2Id : int,
}

KineShapePen :: struct {
    HostId : int,
    Joint1Id : int,
    Joint2Id : int,

    LengthConstraintId : int,
    Point1FloorId : int,
    Point2FloorId : int,
    LockPoint1Id : int,
    LockPoint2Id : int,
}

KineShapeLine :: struct {
    HostId : int,
    Joint1Id : int,
    Joint2Id : int,
}

KineShapeCircle :: struct {
    HostId : int,
    StartId : int,
    EndId : int,
}


ParticleType :: enum u8 {
    Trail,
    Flicker,
    BurnOut,
}

Particle :: struct {
    Type : ParticleType,

    Position : Vector3,
    Velocities : Vector3,

    Age : f32,
    Life : f32,
    Size : f32,
    Color : rl.Color,
    Alive : bool,
    LitFrames : i16,
}

ParticleSystem :: struct {
    Particles : [MAX_PARTICLES]Particle,
    NextIndex : int,
    SpawnTimer : f32,
}



KinePointSystem :: struct {
    PreviousVectors : [MAX_KINEPOINTS]Maybe(Vector3),
    Points : [MAX_KINEPOINTS]KineShapePoint,
    Constraints : [MAX_KINECONSTRAINTS]KineConstraint,
    NextPointIndex : int,
    NextConstraintIndex : int,

    AnimPointsStart : int,
    AnimConstraintsStart : int,
}


EuclidDrawingSurface :: struct {
    Zeros : Vector3,
    RightUp : Vector3,
    LeftDown : Vector3,
    RightDown : Vector3,

    Color : rl.Color,
    EdgeColor : rl.Color,

    EdgeSize : f32
}

EuclidGeneralState :: struct {
    SavedContext : runtime.Context,

    IsoScale : ^IsoScale,

    DrawSurface : ^EuclidDrawingSurface,

    JuliaInterface : ^EuclidJuliaInterface,
    PointSystem : ^KinePointSystem,
    ParticleSystem : ^ParticleSystem,
    Compass : KineShapeCompass,
    Pen : KineShapePen,

    CurrentDeltaTime : f32,

    AnimMetadata : [MAX_METAVALUES]f32,
}
