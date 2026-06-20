package kine

import rl "vendor:raylib"
import "core:math"

init_kineshape_point :: proc(
    system: ^KinePointSystem,
    pos : Vector3,
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
    point1pos, point2pos : Vector3,
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
    center_pos: Vector3,
    radius: f32,
    startTheta, endTheta: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeCircle {

    start_pos := Vector3{
        center_pos.x + radius * f32(math.cos(startTheta)),
        center_pos.y + radius * f32(math.sin(startTheta)),
        center_pos.z,
    }

    end_pos := Vector3{
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

init_kineshape_filledcircle :: proc(
    system: ^KinePointSystem,
    center_pos: Vector3,
    radius: f32,
    startTheta, endTheta: f32,
    color: rl.Color,
    brushSize: f32) -> KineShapeFilledCircle {

    start_pos := Vector3{
        center_pos.x + radius * f32(math.cos(startTheta)),
        center_pos.y + radius * f32(math.sin(startTheta)),
        center_pos.z,
    }

    end_pos := Vector3{
        center_pos.x + radius * f32(math.cos(endTheta)),
        center_pos.y + radius * f32(math.sin(endTheta)),
        center_pos.z,
    }

    hostPoint := KineShapePoint{ .FilledCircle, center_pos, color, nil, brushSize, 1, 2, 0, 0, false }
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

    return KineShapeFilledCircle{
        hostId, startId, endId }
}

init_kineshape_triangle :: proc(
    system: ^KinePointSystem,
    point1, point2, point3: Vector3,
    color: rl.Color) -> KineShapeTriangle {

    hostPoint := KineShapePoint{ .Triangle, nil, color, nil, 0, 0, 3, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2, nil, nil, 0, 0, 0, 0, 0, false }
    point3 := KineShapePoint{ .Point, point3, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system^.NextPointIndex
    point1Id := hostId + 1
    point2Id := hostId + 2
    point3Id := hostId + 3
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id
    point2.NextChildPoint = point3Id
    system^.NextPointIndex = point3Id + 1

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[point2Id] = point2
    system^.Points[point3Id] = point3

    return KineShapeTriangle{ hostId, point1Id, point2Id, point3Id }
}

init_kineshape_square :: proc(
    system: ^KinePointSystem,
    point1, point2, point3, point4: Vector3,
    color: rl.Color) -> KineShapeSquare {

    hostPoint := KineShapePoint{ .Square, nil, color, nil, 0, 0, 4, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2, nil, nil, 0, 0, 0, 0, 0, false }
    point3 := KineShapePoint{ .Point, point3, nil, nil, 0, 0, 0, 0, 0, false }
    point4 := KineShapePoint{ .Point, point4, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system^.NextPointIndex
    point1Id := hostId + 1
    point2Id := hostId + 2
    point3Id := hostId + 3
    point4Id := hostId + 4
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id
    point2.NextChildPoint = point3Id
    point3.NextChildPoint = point4Id
    system^.NextPointIndex = point4Id + 1

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[point2Id] = point2
    system^.Points[point3Id] = point3
    system^.Points[point4Id] = point4

    return KineShapeSquare{ hostId, point1Id, point2Id, point3Id, point4Id }
}

init_kineshape_pentagon :: proc(
    system: ^KinePointSystem,
    point1, point2, point3, point4, point5: Vector3,
    color: rl.Color) -> KineShapePentagon {

    hostPoint := KineShapePoint{ .Pentagon, nil, color, nil, 0, 0, 5, 0, 0, false }
    point1 := KineShapePoint{ .Point, point1, nil, nil, 0, 0, 0, 0, 0, false }
    point2 := KineShapePoint{ .Point, point2, nil, nil, 0, 0, 0, 0, 0, false }
    point3 := KineShapePoint{ .Point, point3, nil, nil, 0, 0, 0, 0, 0, false }
    point4 := KineShapePoint{ .Point, point4, nil, nil, 0, 0, 0, 0, 0, false }
    point5 := KineShapePoint{ .Point, point5, nil, nil, 0, 0, 0, 0, 0, false }

    hostId := system^.NextPointIndex
    point1Id := hostId + 1
    point2Id := hostId + 2
    point3Id := hostId + 3
    point4Id := hostId + 4
    point5Id := hostId + 5
    hostPoint.ChildPointHead = point1Id
    point1.NextChildPoint = point2Id
    point2.NextChildPoint = point3Id
    point3.NextChildPoint = point4Id
    point4.NextChildPoint = point5Id
    system^.NextPointIndex = point5Id + 1

    system^.Points[hostId] = hostPoint
    system^.Points[point1Id] = point1
    system^.Points[point2Id] = point2
    system^.Points[point3Id] = point3
    system^.Points[point4Id] = point4
    system^.Points[point5Id] = point5

    return KineShapePentagon{ hostId, point1Id, point2Id, point3Id, point4Id, point5Id }
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
