package kine

import "../core"
import rl "vendor:raylib"

KineShapePointType :: core.KineShapePointType
KineShapePoint :: core.KineShapePoint

KineShapeCompass :: core.KineShapeCompass
KineShapePen :: core.KineShapePen
KineShapeLine :: core.KineShapeLine

init_kineshape_point :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    pos : core.Vector3,
    color: rl.Color,
    brushSize: f32) -> (^KineShapePoint, int) {

    point := KineShapePoint{ .Point, pos, nil, color, nil, brushSize, 0, 0, 0, 0, false }

    pointId := len(points)

    append(points, point)

    return &points[pointId], pointId
}

init_kineshape_line :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    point1pos, point2pos : core.Vector3,
    length: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeLine {

    hostPoint := KineShapePoint{ .Line, nil, nil, color, nil, brushSize, 0, 2, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := len(points)
    point1Id := hostId + 1
    point2Id := hostId + 2
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id

    append(points, hostPoint, point1, point2)

    return KineShapeLine{ hostId, point1Id, point2Id,
        &points^[hostId], &points^[point1Id], &points^[point2Id] }
}

init_kineshape_pen :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    point1pos, point2pos : core.Vector3,
    length: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapePen {

    hostPoint := KineShapePoint{ .Pen, nil, nil, color, nil, brushSize, 0, 2, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := len(points)
    point1Id := hostId + 1
    point2Id := hostId + 2
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id

    length := KineConstraint{ .Distance, hostId, { length, 0, 0 }, 0, 0, 0, 0, true }

    point1Floor := KineConstraint{ .Floor, point1Id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2Floor := KineConstraint{ .Floor, point2Id, { 0, 0, 0 }, 0, 0, 0, 0, true }

    lockPoint1 := KineConstraint{ .SnapPoint, point1Id, { 0, 0, 0 }, 0, 0, 0, nil, false }
    lockPoint2 := KineConstraint{ .SnapPoint, point2Id, { 0, 0, 0 }, 0, 0, 0, nil, false }

    lengthId := len(constraints)

    append(points, hostPoint, point1, point2)
    append(constraints, length, point1Floor, point2Floor, lockPoint1, lockPoint2)

    return KineShapePen{ hostId, point1Id, point2Id,
        lengthId, lengthId + 1, lengthId + 2, lengthId + 3, lengthId + 4,
        &points^[hostId], &points^[point1Id], &points^[point2Id],
        &constraints^[lengthId], &constraints^[lengthId + 1], &constraints^[lengthId + 2],
        &constraints^[lengthId + 3], &constraints^[lengthId + 4]}
}

init_kineshape_compass :: proc(
    points: ^[dynamic]KineShapePoint,
    constraints: ^[dynamic]KineConstraint,
    point1pos, pivotpos, point2pos : core.Vector3,
    limbLength: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeCompass {

    hostPoint := KineShapePoint{ .Compass, nil, nil, color, nil, brushSize, 0, 3, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, nil, 0, 0, 0, 0, 0, false }
    pivot := KineShapePoint{ .Point, pivotpos, nil, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := len(points)
    point1Id := hostId + 1
    pivotId := hostId + 2
    point2Id := hostId + 3
    hostPoint.ChildPointHead = hostId + 1
    point1.NextChildPoint = hostId + 2
    pivot.NextChildPoint = hostId + 3

    centerpivot := KineConstraint{ .CenterPivot, hostId, { 0, 0, 0 }, 0.01, 0, 0, 0, true }

    limb1Length := KineConstraint{ .Distance, hostId, { limbLength, 0, 0 }, 0, 0, 0, 0, true }
    limb2Length := KineConstraint{ .Distance, hostId, { limbLength, 0, 0 }, 0, 0, 0, 1, true }

    point1Floor := KineConstraint{ .Floor, point1Id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    pivotFloor := KineConstraint{ .Floor, pivotId, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2Floor := KineConstraint{ .Floor, point2Id, { 0, 0, 0 }, 0, 0, 0, 0, true }

    lockPoint1 := KineConstraint{ .SnapPoint, point1Id, { 0, 0, 0 }, 0, 0, 0, nil, false }
    lockPoint2 := KineConstraint{ .SnapPoint, point2Id, { 0, 0, 0 }, 0, 0, 0, nil, false }

    centerPivotId := len(constraints)

    append(points, hostPoint, point1, pivot, point2)
    append(constraints,
        centerpivot,
        limb1Length, limb2Length,
        point1Floor, pivotFloor, point2Floor,
        lockPoint1, lockPoint2
    )

    return KineShapeCompass{ hostId, point1Id, pivotId, point2Id,
        centerPivotId, centerPivotId + 1, centerPivotId + 2, centerPivotId + 3,
        centerPivotId + 4, centerPivotId + 5, centerPivotId + 6, centerPivotId + 7,
        &points^[hostId], &points^[point1Id], &points^[pivotId], &points^[point2Id],
        &constraints^[centerPivotId], &constraints^[centerPivotId + 1],
        &constraints^[centerPivotId + 2], &constraints^[centerPivotId + 3],
        &constraints^[centerPivotId + 4], &constraints^[centerPivotId + 5],
        &constraints^[centerPivotId + 6], &constraints^[centerPivotId + 7] }
}
