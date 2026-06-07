package kine

import "../core"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Vector3 :: core.Vector3
KineShapePointType :: core.KineShapePointType
KineShapePoint :: core.KineShapePoint

KineShapeCompass :: core.KineShapeCompass
KineShapePen :: core.KineShapePen
KineShapeLine :: core.KineShapeLine
KineShapeCircle :: core.KineShapeCircle

init_kineshape_point :: proc(
    system: ^KinePointSystem,
    pos : core.Vector3,
    color: rl.Color,
    brushSize: f32) -> (^KineShapePoint, int) {

    pointId := system^.NextPointIndex
    system^.Points[pointId] =
        KineShapePoint{ .Point, pos, color, nil, brushSize, 0, 0, 0, 0, false }
    system^.NextPointIndex += 1

    return &system^.Points[pointId], pointId
}

init_kineshape_line :: proc(
    system: ^KinePointSystem,
    point1pos, point2pos : core.Vector3,
    color: rl.Color,
    brushSize: f32) -> KineShapeLine {

    hostPoint := KineShapePoint{ .Line, nil, color, nil, brushSize, 0, 2, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1pos, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2pos, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system^.NextPointIndex
    point1Id := hostId + 1
    point2Id := hostId + 2
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id
    system^.NextPointIndex = point2Id + 1

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[point2Id] = point2

    return KineShapeLine{ hostId, point1Id, point2Id }
}

init_kineshape_circle :: proc(
    system: ^KinePointSystem,
    center_pos: core.Vector3,
    radius: f32,
    startTheta, endTheta: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeCircle {

    start_pos := core.Vector3{
        center_pos.x + radius * f32(math.cos(startTheta)),
        center_pos.y + radius * f32(math.sin(startTheta)),
        center_pos.z,
    }

    end_pos := core.Vector3{
        center_pos.x + radius * f32(math.cos(endTheta)),
        center_pos.y + radius * f32(math.sin(endTheta)),
        center_pos.z,
    }

    hostPoint := KineShapePoint{ .Circle, center_pos, color, nil, brushSize, 1, 2, 0, 0, false }
    startPoint := KineShapePoint{ .Point, start_pos, nil, nil, 0, 0, 0, 0, 0, false }
    endPoint := KineShapePoint{ .Point, end_pos, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system^.NextPointIndex
    startId := hostId + 1
    endId := hostId + 2
    system^.NextPointIndex = endId + 1

    hostPoint.ChildPointHead = startId
    startPoint.NextChildPoint = endId

    system^.Points[hostId] = hostPoint
    system^.Points[startId] = startPoint
    system^.Points[endId] = endPoint

    return KineShapeCircle{
        hostId, startId, endId }
}

init_kineshape_pen :: proc(
    system: ^KinePointSystem,
    length: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapePen {

    hostPoint := KineShapePoint{ .Pen, nil, color, nil, brushSize, 0, 2, 0, 0, false }
    point1 := KineShapePoint{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system.NextPointIndex
    point1Id := hostId + 1
    point2Id := hostId + 2
    system^.NextPointIndex = point2Id + 1
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id

    length := KineConstraint{ .Distance, hostId, { length, 0, 0 }, 0, 0, 0, 0, true }

    point1Floor := KineConstraint{ .Floor, point1Id, { 0, 0, 0 }, 0, 0, 0, 0, true }
    point2Floor := KineConstraint{ .Floor, point2Id, { 0, 0, 0 }, 0, 0, 0, 0, true }

    lockPoint1 := KineConstraint{ .SnapPoint, point1Id, { 0, 0, 0 }, 0, 0, 0, nil, false }
    lockPoint2 := KineConstraint{ .SnapPoint, point2Id, { 0, 0, 0 }, 0, 0, 0, nil, false }

    lengthId := system^.NextConstraintIndex
    system^.NextConstraintIndex += 5

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[point2Id] = point2

    system^.Constraints[lengthId] = length
    system^.Constraints[lengthId + 1] = point1Floor
    system^.Constraints[lengthId + 2] = point2Floor
    system^.Constraints[lengthId + 3] = lockPoint1
    system^.Constraints[lengthId + 4] = lockPoint2

    return KineShapePen{ hostId, point1Id, point2Id,
        lengthId, lengthId + 1, lengthId + 2, lengthId + 3, lengthId + 4 }
}

init_kineshape_compass :: proc(
    system: ^KinePointSystem,
    limbLength: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeCompass {

    hostPoint := KineShapePoint{ .Compass, nil, color, nil, brushSize, 0, 3, 0, 0, false }
    point1 := KineShapePoint{ .Point, Vector3{0, 0, 0}, nil, nil, 0, 0, 0, 0, 0, false }
    pivot := KineShapePoint{ .Point, Vector3{0.01, 0.01, 0.01}, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, Vector3{0.02, 0.02, 0}, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system.NextPointIndex
    point1Id := hostId + 1
    pivotId := hostId + 2
    point2Id := hostId + 3
    system^.NextPointIndex = point2Id + 1
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

    centerPivotId := system^.NextConstraintIndex
    system^.NextConstraintIndex += 8

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[pivotId] = pivot
    system^.Points[point2Id] = point2

    system^.Constraints[centerPivotId] = centerpivot
    system^.Constraints[centerPivotId + 1] = limb1Length
    system^.Constraints[centerPivotId + 2] = limb2Length
    system^.Constraints[centerPivotId + 3] = point1Floor
    system^.Constraints[centerPivotId + 4] = pivotFloor
    system^.Constraints[centerPivotId + 5] = point2Floor
    system^.Constraints[centerPivotId + 6] = lockPoint1
    system^.Constraints[centerPivotId + 7] = lockPoint2

    return KineShapeCompass{ hostId, point1Id, pivotId, point2Id,
        centerPivotId, centerPivotId + 1, centerPivotId + 2, centerPivotId + 3,
        centerPivotId + 4, centerPivotId + 5, centerPivotId + 6, centerPivotId + 7 }
}
