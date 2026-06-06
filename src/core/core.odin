package core

import "base:runtime"
import rl "vendor:raylib"

MAX_PARTICLES :: 8192

Vector2 :: [2]f32
Vector3 :: [3]f32

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

    DoDraw : bool
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

    Host : ^KineShapePoint,
    Joint1 : ^KineShapePoint,
    Pivot : ^KineShapePoint,
    Joint2 : ^KineShapePoint,

    CenterPivot : ^KineConstraint,
    Limb1Length : ^KineConstraint,
    Limb2Length : ^KineConstraint,
    Point1Floor : ^KineConstraint,
    PivotFloor : ^KineConstraint,
    Point2Floor : ^KineConstraint,
    LockPoint1 : ^KineConstraint,
    LockPoint2 : ^KineConstraint,
}


ParticleType :: enum u8 {
    Trail,
    Flicker,
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

    DrawSurface: ^EuclidDrawingSurface,

    KinePoints: ^[dynamic]KineShapePoint,
    KineConstraints: ^[dynamic]KineConstraint,

    ParticleSystem: ^ParticleSystem,

    Compass: ^KineShapeCompass,

    CurrentDeltaTime: f32,

    AnimMetaFloat1 : f32,
    AnimMetaFloat2 : f32,
    AnimMetaFloat3 : f32,
    AnimMetaFloat4 : f32,
    AnimMetaFloat5 : f32,
    AnimMetaFloat6 : f32,
    AnimMetaFloat7 : f32,
    AnimMetaFloat8 : f32,
    AnimMetaFloat9 : f32,
}
