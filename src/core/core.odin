package core

// Defines the core structures used in the Euclid Application.
// The general bias is to just allocate memory upfront inside EuclidGeneralState and
// stick to that memory, except for a few UI helpers using temp_allocator and Julia's GC.
// This creates some hard caps on e.g. the particle system, but it also prevents wildness.

import "../julialib"
import "base:runtime"
import rl "vendor:raylib"

MAX_LOW_PARTICLES :: 4096
MAX_PARTICLES :: 2048
MAX_METAVALUES :: 256
MAX_KINEPOINTS :: 256
MAX_KINECONSTRAINTS :: 256
MAX_JULIA_INTERFACES :: 512

TOOL_LENGTH :: 0.35

Vector2 :: rl.Vector2
Vector3 :: rl.Vector3

EuclidJuliaAnimationInterface :: struct {
    GetViewText : ^julialib.jl_value_t,
    Initiate : ^julialib.jl_value_t, // initiate the animation type
    Loop : ^julialib.jl_value_t, // ran each dt in the main window loop
    Clean : ^julialib.jl_value_t, // stop and clear animations

    Name : string,
    IsExpanded : bool,
    IsSelected : bool,

    FirstChildId : int,
    ParentId : int,
    NextSibling : int,
}

EuclidJuliaInterface :: struct {
    InitScripts : ^julialib.jl_value_t,
    GlobalLoop : ^julialib.jl_value_t,

    NullAnimation : EuclidJuliaAnimationInterface,

    CurrentAnimation : ^EuclidJuliaAnimationInterface,
    CurrentAnimationIndex : int,
    SelectedAnimationIndex : int,
    PendingAnimationReset : bool,
    AnimationResetCooldownRemaining : f32,

    Animations : [MAX_JULIA_INTERFACES]EuclidJuliaAnimationInterface,
    NextAnimationIndex : int,
}

IsoScale :: struct {
    Scale : f32,
    XOffset : f32,
    YOffset : f32,

    MainLightDir : Vector3,
    UseDirectionalShadow : bool,
}

KineShapePointType :: enum {
    Point,
    Line,
    Circle,
    FilledCircle,
    Triangle,
    Square,
    Pentagon,
    Pen,
    Compass,
}

KineShapePoint :: struct {
    Type : KineShapePointType,

    Position : Maybe(Vector3),
    Color : Maybe(rl.Color),
    ActiveColor : Maybe(rl.Color),
    BrushSize : f32,
    Offset : f32,

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
    MinAngle = (1 << 5),
    CenterPivot = (1 << 6)
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
    PivotFloorId : int,
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

KineShapeFilledCircle :: struct {
    HostId : int,
    StartId : int,
    EndId : int,
}

KineShapeTriangle :: struct {
    HostId : int,
    Joint1Id : int,
    Joint2Id : int,
    Joint3Id : int,
}

KineShapeSquare :: struct {
    HostId : int,
    Joint1Id : int,
    Joint2Id : int,
    Joint3Id : int,
    Joint4Id : int,
}

KineShapePentagon :: struct {
    HostId : int,
    Joint1Id : int,
    Joint2Id : int,
    Joint3Id : int,
    Joint4Id : int,
    Joint5Id : int,
}

KineDrawBase :: struct {
    Type: KineShapePointType,
    SourceIndex: int,
    BrushSize: f32,
    Color: rl.Color,
    ActiveColor: rl.Color,
    HasActiveColor: bool,
    ActiveChild: int,
}

KinePointDraw :: struct {
    using Base: KineDrawBase,
    Point1: Vector3,
}

KineLineDraw :: struct {
    using Base: KineDrawBase,
    Point1: Vector3,
    Point2: Vector3,
}

KineCircleDraw :: struct {
    using Base: KineDrawBase,
    Center: Vector3,
    Start: Vector3,
    End: Vector3,
    Offset: f32,
}

KineFilledCircleDraw :: struct {
    using Base: KineDrawBase,
    Center: Vector3,
    Start: Vector3,
    End: Vector3,
}

KineTriangleDraw :: struct {
    using Base: KineDrawBase,
    Point1: Vector3,
    Point2: Vector3,
    Point3: Vector3,
}

KineSquareDraw :: struct {
    using Base: KineDrawBase,
    Point1: Vector3,
    Point2: Vector3,
    Point3: Vector3,
    Point4: Vector3,
}

KinePentagonDraw :: struct {
    using Base: KineDrawBase,
    Point1: Vector3,
    Point2: Vector3,
    Point3: Vector3,
    Point4: Vector3,
    Point5: Vector3,
}

KinePenDraw :: struct {
    using Base: KineDrawBase,
    Joint1: Vector3,
    Joint2: Vector3,
}

KineCompassDraw :: struct {
    using Base: KineDrawBase,
    Joint1: Vector3,
    Pivot: Vector3,
    Joint2: Vector3,
}

KineDrawCacheItem :: union {
    KinePointDraw,
    KineLineDraw,
    KineCircleDraw,
    KineFilledCircleDraw,
    KineTriangleDraw,
    KineSquareDraw,
    KinePentagonDraw
}

KineDrawCache :: struct {
    Items: [MAX_KINEPOINTS]KineDrawCacheItem,
    ItemCount: int,

    Pen: KinePenDraw,
    DrawPen: bool,
    Compass: KineCompassDraw,
    DrawCompass: bool,
}

KinePointSystem :: struct {
    DrawCache : KineDrawCache,

    PreviousVectors : [MAX_KINEPOINTS]Maybe(Vector3),
    Points : [MAX_KINEPOINTS]KineShapePoint,
    Constraints : [MAX_KINECONSTRAINTS]KineConstraint,
    NextPointIndex : int,
    NextConstraintIndex : int,

    AnimPointsStart : int,
    AnimConstraintsStart : int,
}





ParticleType :: enum u8 {
    Trail,
    Flicker,
    BurnOut,
    Dust,
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
    LowParticles : [MAX_LOW_PARTICLES]Particle,
    Particles : [MAX_PARTICLES]Particle,
    HighParticles : [MAX_PARTICLES]Particle,
    NextIndex : int,
    SpawnTimer : f32,

    LastRenderLow : int,
    LastRenderMid : int,
    LastRenderHigh : int,
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

Stroke3DRenderState :: struct {
    Shader: rl.Shader,
    Ready: bool,
    LocLightDir: i32,
    LocAmbient: i32,
    LocDiffuse: i32,
    LocSpecularStrength: i32,
    LocSpecularPower: i32,
    LocP0: i32,
    LocP1: i32,
    LocRadius: i32,
    LocViewportHeight: i32,
}

EuclidUIRuntimeState :: struct {
    TreeScrollDragging: bool,
    TreeScrollDragOff: f32,
    TextScrollDragging: bool,
    TextScrollDragOff: f32,
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

    Stroke3D: Stroke3DRenderState,
    UIRuntime: EuclidUIRuntimeState,

    CurrentDeltaTime : f32,

    AnimMetadata : [MAX_METAVALUES]f32,
}
