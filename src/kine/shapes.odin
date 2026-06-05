package kine

import ec "../core"
import rl "vendor:raylib"

KineShapePointType :: enum {
    Point,
    Line,
    Circle,
    Pen,
    Compass,
}

KineShapePoint :: struct {
    Type : KineShapePointType,

    Position : Maybe(ec.Vector3),
    Color : Maybe(rl.Color),
    ActiveColor : Maybe(rl.Color),
    BrushSize : f32,

    ActiveChild: int,
    ChildCount : int,
    ChildPointHead : int,
    NextChildPoint : int,

    DoDraw : bool
}

KineShapeLine :: struct {
    HostId : int,
    Join1Id : int,
    Join2Id : int,
    Host : ^KineShapePoint,
    Joint1 : ^KineShapePoint,
    Joint2 : ^KineShapePoint,

    LengthConstraintId : int,
    LengthConstraint : ^KineConstraint,
}

KineShapeCompass :: struct {
    HostId : int,
    Joint1Id : int,
    PivotId : int,
    Joint2Id : int,
    Host : ^KineShapePoint,
    Joint1 : ^KineShapePoint,
    Pivot : ^KineShapePoint,
    Joint2 : ^KineShapePoint,

    Limb1LengthId : int,
    Limb2LengthId : int,
    Limb1Length : ^KineConstraint,
    Limb2Length : ^KineConstraint,
}

init_kineshape_line :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    point1pos, point2pos : ec.Vector3,
    length: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeLine {

    hostPoint := KineShapePoint{ .Line, nil, color, nil, brushSize, 0, 2, 0, 0, true }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := len(points)
    point1Id := hostId + 1
    point2Id := hostId + 2
    hostPoint.ChildPointHead = hostId + 1
    point1.NextChildPoint = hostId + 2

    length := KineConstraint{ .Distance, hostId, { length, 0, 0 }, 0, 0, 0, 0, true }
    lengthId := len(constraints)

    append(points, hostPoint, point1, point2)
    append(constraints, length)

    return KineShapeLine{ hostId, hostId + 1, hostId + 2,
        &points^[hostId], &points^[hostId + 1], &points^[hostId + 2],
        lengthId, &constraints^[lengthId]}
}

init_kineshape_compass :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    point1pos, pivotpos, point2pos : ec.Vector3,
    limbLength: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeCompass {

    hostPoint := KineShapePoint{ .Compass, nil, color, nil, brushSize, 0, 3, 0, 0, true }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, 0, 0, 0, 0, 0, false }
    pivot := KineShapePoint{ .Point, pivotpos, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := len(points)
    point1Id := hostId + 1
    point2Id := hostId + 3
    hostPoint.ChildPointHead = hostId + 1
    point1.NextChildPoint = hostId + 2
    pivot.NextChildPoint = hostId + 3

    centerpivot := KineConstraint{ .CenterPivot, hostId, { 0, 0, 0 }, 0.01, 0, 0, 0, true }
    limb1Length := KineConstraint{ .Distance, hostId, { limbLength, 0, 0 }, 0, 0, 0, 0, true }
    limb2Length := KineConstraint{ .Distance, hostId, { limbLength, 0, 0 }, 0, 0, 0, 1, true }
    point1Floor := KineConstraint{ .Floor, hostId + 1, { 0, 0, 0 }, 0, 0, 0, 0, true }
    pivotFloor := KineConstraint{ .Floor, hostId + 2, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2Floor := KineConstraint{ .Floor, hostId + 3, { 0, 0, 0 }, 0, 0, 0, 0, true }

    limb1LengthId := len(constraints) + 1

    append(points, hostPoint, point1, pivot, point2)
    append(constraints, centerpivot, limb1Length, limb2Length, point1Floor, pivotFloor, point2Floor)

    return KineShapeCompass{ hostId, hostId + 1, hostId + 2, hostId + 3,
        &points^[hostId], &points^[hostId + 1], &points^[hostId + 2], &points^[hostId + 3],
        limb1LengthId, limb1LengthId + 1,
        &constraints^[limb1LengthId], &constraints^[limb1LengthId + 1] }
}
