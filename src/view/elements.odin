package view

import "../surface"
import "../kine"
import ec "../core"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/linalg"

draw_drawing_surface :: proc(room : ^EuclidDrawingSurface, state: ^EuclidGeneralState) {
    surfaceZeros : Vector3 = room^.Zeros + { room^.EdgeSize, room^.EdgeSize, 0 }
    surfaceRightUp : Vector3 = room^.RightUp + { -room^.EdgeSize, room^.EdgeSize, 0 }
    surfaceLeftDown : Vector3 = room^.LeftDown + { room^.EdgeSize, -room^.EdgeSize, 0 }
    surfaceRightDown : Vector3 = room^.RightDown + { -room^.EdgeSize, -room^.EdgeSize, 0 }

    rl.DrawTriangle(iso_to_cartesian(room^.Zeros, state^.IsoScale^),
        iso_to_cartesian(room^.LeftDown, state^.IsoScale^),
        iso_to_cartesian(room^.RightUp, state^.IsoScale^), room^.EdgeColor)
    rl.DrawTriangle(iso_to_cartesian(room^.RightDown, state^.IsoScale^),
        iso_to_cartesian(room^.RightUp, state^.IsoScale^),
        iso_to_cartesian(room^.LeftDown, state^.IsoScale^), room^.EdgeColor)
    rl.DrawTriangle(iso_to_cartesian(surfaceZeros, state^.IsoScale^),
        iso_to_cartesian(surfaceLeftDown, state^.IsoScale^),
        iso_to_cartesian(surfaceRightUp, state^.IsoScale^), room^.Color)
    rl.DrawTriangle(iso_to_cartesian(surfaceRightDown, state^.IsoScale^),
        iso_to_cartesian(surfaceRightUp, state^.IsoScale^),
        iso_to_cartesian(surfaceLeftDown, state^.IsoScale^), room^.Color)
}

draw_kine_points :: proc(
    lastPoints: ^[dynamic]Maybe(Vector3),
    state: ^EuclidGeneralState, alpha: f32) {

    points := state^.KinePoints
    for index in 0..<len(points) {
        point := &points^[index]
        if point.DoDraw {
            /*lastPointPos, lastok := lastPoints^[index].?
            if !lastok { continue }
            pointPos, ok := points^[index].Position.?
            if !ok { continue }*/

            // TODO: Print the other things, too, clean this up, etc.
            if point^.Type == .Compass {
                draw_kine_compass(lastPoints, state, point, alpha)
            }
        }
    }
}

draw_kine_compass :: proc(
    lastPoints: ^[dynamic]Maybe(Vector3),
    state: ^EuclidGeneralState,
    point : ^KineShapePoint, alpha : f32) {

    points := state^.KinePoints
    if point^.ChildPointHead <= 0 && point^.ChildPointHead >= len(points) {
        return
    }
    usePoints : [3]Vector3
    convPoints : [3]Vector2
    lastPoint := lastPoints^[point^.ChildPointHead].? or_else {0, 0, 0}
    currPoint := points^[point^.ChildPointHead]
    usePoints[0] = currPoint.Position.? or_else {0, 0, 0}
    usePoints[0] = linalg.lerp(lastPoint, usePoints[0], alpha)
    convPoints[0] = iso_to_cartesian(usePoints[0], state^.IsoScale^)
    if currPoint.NextChildPoint <= 0 && currPoint.NextChildPoint >= len(points) {
        return
    }
    lastPoint = lastPoints^[currPoint.NextChildPoint].? or_else {0, 0, 0}
    currPoint = points^[currPoint.NextChildPoint]
    usePoints[1] = currPoint.Position.? or_else {0, 0, 0}
    usePoints[1] = linalg.lerp(lastPoint, usePoints[1], alpha)
    convPoints[1] = iso_to_cartesian(usePoints[1], state^.IsoScale^)
    if currPoint.NextChildPoint <= 0 && currPoint.NextChildPoint >= len(points) {
        return
    }
    lastPoint = lastPoints^[currPoint.NextChildPoint].? or_else {0, 0, 0}
    currPoint = points^[currPoint.NextChildPoint]
    usePoints[2] = currPoint.Position.? or_else {0, 0, 0}
    usePoints[2] = linalg.lerp(lastPoint, usePoints[2], alpha)
    convPoints[2] = iso_to_cartesian(usePoints[2], state^.IsoScale^)

    useColor := point^.Color.? or_else rl.Color{255, 255, 255, 255}

    if point^.ActiveChild == 1 {
        activeColor := point^.ActiveColor.? or_else useColor
        rl.DrawCircleV(Vector2{convPoints[0].x, convPoints[0].y}, point^.BrushSize, activeColor)
    }
    else if point^.ActiveChild == 3 {
        activeColor := point^.ActiveColor.? or_else useColor
        rl.DrawCircleV(Vector2{convPoints[2].x, convPoints[2].y}, point^.BrushSize, activeColor)        
    }

    rl.DrawSplineLinear(&convPoints[0], 3, point^.BrushSize, useColor)
    draw_outside_arc_compass(usePoints[0], usePoints[1], usePoints[2], state,
        point^.BrushSize, useColor)
}


// TODO : I'm not a big fan of this dynamic allocation here
build_outside_arc_points :: proc(
    p0, p1, p2: Vector3,
    segments: int,
    radiusScale: f32) -> [dynamic]Vector3 {

    points := make([dynamic]Vector3)

    a := p0 - p1
    b := p2 - p1

    aLen := linalg.length(a)
    bLen := linalg.length(b)
    if segments <= 0 {
        return points
    }

    an := a / aLen
    bn := b / bLen

    n := linalg.cross(an, bn)
    nLen := linalg.length(n)
    n /= nLen

    dotAB := math.clamp(linalg.dot(an, bn), -1, 1)
    crossAB := linalg.cross(an, bn)
    thetaShort := math.atan2(linalg.dot(n, crossAB), dotAB)

    sign := f32(1.0)
    if thetaShort < 0 {
        sign = -1.0
    }
    thetaOut := thetaShort - 2.0 * math.PI * sign

    u := an
    v := linalg.normalize(linalg.cross(n, u))

    radius := math.min(aLen, bLen) * radiusScale
    step := thetaOut / f32(segments)

    for i in 0..=segments {
        t := step * f32(i)
        dir := u * math.cos(t) + v * math.sin(t)
        append(&points, p1 + dir * radius)
    }

    return points
}

draw_outside_arc_compass :: proc(
    p0, p1, p2: Vector3,
    state: ^EuclidGeneralState,
    brushSize: f32,
    color: rl.Color) {

    arc3d := build_outside_arc_points(p0, p1, p2, 20, 0.25)
    defer delete(arc3d)

    if len(arc3d) < 2 {
        return
    }

    arc2d := make([dynamic]Vector2, len(arc3d))
    defer delete(arc2d)
    for i in 0..<len(arc3d) {
        arc2d[i] = iso_to_cartesian(arc3d[i], state^.IsoScale^)
    }

    rl.DrawSplineLinear(&arc2d[0], i32(len(arc2d)), brushSize, color)
}
