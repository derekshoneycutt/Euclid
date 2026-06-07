package kine

import "../core"
import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
MAX_KINECONSTRAINTS :: core.MAX_KINECONSTRAINTS

Vector3 :: core.Vector3
KineShapePointType :: core.KineShapePointType
KineShapePoint :: core.KineShapePoint

KineConstraintTrait :: core.KineConstraintTrait
KineConstraint :: core.KineConstraint
KinePointSystem :: core.KinePointSystem

KineShapeCompass :: core.KineShapeCompass
KineShapePen :: core.KineShapePen
KineShapeLine :: core.KineShapeLine
KineShapeCircle :: core.KineShapeCircle

KineDrawBase :: core.KineDrawBase
KinePointDraw :: core.KinePointDraw
KineLineDraw :: core.KineLineDraw
KineCircleDraw :: core.KineCircleDraw
KinePenDraw :: core.KinePenDraw
KineCompassDraw :: core.KineCompassDraw

kine_update_last_cache_vectors :: proc(
    pointSystem: ^KinePointSystem) {

    for i in 0..<MAX_KINEPOINTS {
        pointSystem^.PreviousVectors[i] = pointSystem^.Points[i].Position
    }
}

kine_freeze_system_indices :: proc(
    pointSystem: ^KinePointSystem) {

    pointSystem^.AnimPointsStart = pointSystem^.NextPointIndex
    pointSystem^.AnimConstraintsStart = pointSystem^.NextConstraintIndex
}

kine_clear_animation_data :: proc(
    pointSystem: ^KinePointSystem) {

    for i in pointSystem^.AnimPointsStart..<MAX_KINEPOINTS {
        pointSystem^.Points[i] = {}
        pointSystem^.Points[i].DoDraw = false
    }
    for i in pointSystem^.AnimConstraintsStart..<MAX_KINECONSTRAINTS {
        pointSystem^.Constraints[i] = {}
        pointSystem^.Constraints[i].DoApply = false
    }
}



kine_draw_cache_reset :: proc(
    pointSystem: ^KinePointSystem) {

    pointSystem^.DrawCache.PointCount = 0
    pointSystem^.DrawCache.LineCount = 0
    pointSystem^.DrawCache.CircleCount = 0
    pointSystem^.DrawCache.PenCount = 0
    pointSystem^.DrawCache.CompassCount = 0
}

build_kine_draw_cache :: proc(
    pointSystem: ^KinePointSystem,
    alpha: f32) {

    kine_draw_cache_reset(pointSystem)

    for index in 0..<len(pointSystem^.Points) {
        src := &pointSystem^.Points[index]
        if !src^.DoDraw {
            continue
        }

        switch src^.Type {
            case .Point:
                cache_push_point(pointSystem, index, src, alpha)
            case .Line:
                cache_push_line(pointSystem, index, src, alpha)
            case .Circle:
                cache_push_circle(pointSystem, index, src, alpha)
            case .Pen:
                cache_push_pen(pointSystem, index, src, alpha)
            case .Compass:
                cache_push_compass(pointSystem, index, src, alpha)
        }
    }
}

lerped_point_position :: proc(
    pointSystem: ^KinePointSystem,
    index: int,
    alpha: f32,
    out: ^Vector3) -> bool {

    if index < 0 || index >= MAX_KINEPOINTS {
        return false
    }

    curr := pointSystem^.Points[index]
    currPos, hasCurr := curr.Position.?
    if !hasCurr {
        return false
    }

    prev := pointSystem^.PreviousVectors[index].? or_else currPos
    out^ = linalg.lerp(prev, currPos, alpha)
    return true
}

make_draw_base :: #force_inline proc(
    sourceIndex: int,
    src: ^KineShapePoint) -> KineDrawBase {

    color := src^.Color.? or_else rl.WHITE
    activeColor, hasActiveColor := src^.ActiveColor.?

    return KineDrawBase{
        Type = src^.Type,
        SourceIndex = sourceIndex,
        BrushSize = src^.BrushSize,
        Color = color,
        ActiveColor = activeColor,
        HasActiveColor = hasActiveColor,
        ActiveChild = src^.ActiveChild,
    }
}


cache_push_point :: proc(
    pointSystem: ^KinePointSystem,
    sourceIndex: int,
    src: ^KineShapePoint,
    alpha: f32) {

    if pointSystem^.DrawCache.PointCount >= len(pointSystem^.DrawCache.Points) {
        return
    }

    child := src^.ChildPointHead
    p0: Vector3
    if !lerped_point_position(pointSystem, child, alpha, &p0) {
        return
    }

    slot := &pointSystem^.DrawCache.Points[pointSystem^.DrawCache.PointCount]
    slot^.Base = make_draw_base(sourceIndex, src)
    slot^.Point1 = p0
    pointSystem^.DrawCache.PointCount += 1
}

cache_push_line :: proc(
    pointSystem: ^KinePointSystem,
    sourceIndex: int,
    src: ^KineShapePoint,
    alpha: f32) {

    if pointSystem^.DrawCache.LineCount >= len(pointSystem^.DrawCache.Lines) {
        return
    }

    child0 := src^.ChildPointHead
    point1: Vector3
    if !lerped_point_position(pointSystem, child0, alpha, &point1) {
        return
    }

    next := pointSystem.Points[child0].NextChildPoint
    point2: Vector3
    if !lerped_point_position(pointSystem, next, alpha, &point2) {
        return
    }

    slot := &pointSystem^.DrawCache.Lines[pointSystem^.DrawCache.LineCount]
    slot^.Base = make_draw_base(sourceIndex, src)
    slot^.Point1 = point1
    slot^.Point2 = point2
    pointSystem^.DrawCache.LineCount += 1
}

cache_push_circle :: proc(
    pointSystem: ^KinePointSystem,
    sourceIndex: int,
    src: ^KineShapePoint,
    alpha: f32) {

    if pointSystem^.DrawCache.CircleCount >= len(pointSystem^.DrawCache.Circles) {
        return
    }

    center, hasCenter := src^.Position.?
    if !hasCenter {
        return
    }

    child0 := src^.ChildPointHead
    start: Vector3
    if !lerped_point_position(pointSystem, child0, alpha, &start) {
        return
    }

    next := pointSystem.Points[child0].NextChildPoint
    end: Vector3
    if !lerped_point_position(pointSystem, next, alpha, &end) {
        return
    }

    if src^.ActiveChild > 1 {
        start, end = end, start
    }

    slot := &pointSystem^.DrawCache.Circles[pointSystem^.DrawCache.CircleCount]
    slot^.Base = make_draw_base(sourceIndex, src)
    slot^.Center = center
    slot^.Start = start
    slot^.End = end
    pointSystem^.DrawCache.CircleCount += 1
}

cache_push_pen :: proc(
    pointSystem: ^KinePointSystem,
    sourceIndex: int,
    src: ^KineShapePoint,
    alpha: f32) {

    if pointSystem^.DrawCache.PenCount >= len(pointSystem^.DrawCache.Pens) {
        return
    }

    child0 := src^.ChildPointHead
    j1: Vector3
    if !lerped_point_position(pointSystem, child0, alpha, &j1) {
        return
    }

    next := pointSystem.Points[child0].NextChildPoint
    j2: Vector3
    if !lerped_point_position(pointSystem, next, alpha, &j2) {
        return
    }

    slot := &pointSystem^.DrawCache.Pens[pointSystem^.DrawCache.PenCount]
    slot^.Base = make_draw_base(sourceIndex, src)
    slot^.Joint1 = j1
    slot^.Joint2 = j2
    pointSystem^.DrawCache.PenCount += 1
}

cache_push_compass :: proc(
    pointSystem: ^KinePointSystem,
    sourceIndex: int,
    src: ^KineShapePoint,
    alpha: f32) {

    if pointSystem^.DrawCache.CompassCount >= len(pointSystem^.DrawCache.Compasses) {
        return
    }

    child0 := src^.ChildPointHead
    p0: Vector3
    if !lerped_point_position(pointSystem, child0, alpha, &p0) {
        return
    }

    child1 := pointSystem.Points[child0].NextChildPoint
    p1: Vector3
    if !lerped_point_position(pointSystem, child1, alpha, &p1) {
        return
    }

    child2 := pointSystem.Points[child1].NextChildPoint
    p2: Vector3
    if !lerped_point_position(pointSystem, child2, alpha, &p2) {
        return
    }

    slot := &pointSystem^.DrawCache.Compasses[pointSystem^.DrawCache.CompassCount]
    slot^.Base = make_draw_base(sourceIndex, src)
    slot^.Joint1 = p0
    slot^.Pivot = p1
    slot^.Joint2 = p2
    pointSystem^.DrawCache.CompassCount += 1
}
