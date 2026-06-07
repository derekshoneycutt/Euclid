package view

import "../surface"
import "../kine"
import "../core"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/linalg"

CIRCLE_ARC_SEGMENTS :: 60

COMPASS_TOPCIRCLE_SEGMENTS :: 30
COMPASS_TOPCIRCLE_VECTORS :: COMPASS_TOPCIRCLE_SEGMENTS + 1
COMPASS_TOPCIRCLE_RADIUS :: 0.25

SHADOW_MIN_THICKNESS :: 0.5
SHADOW_ALPHA_BASE :: 90
SHADOW_ALPHA_MIN :: 35
SHADOW_ALPHA_HEIGHT_SCALE :: 35.0
SHADOW_EPSILON_LZ :: 0.0001

compute_sweep_delta :: proc(startTheta, endTheta: f32) -> f32 {
    startN := startTheta
    if startN < 0 {
        startN += 2.0 * math.PI
    }
    endN := endTheta
    if endN < 0 {
        endN += 2.0 * math.PI
    }

    delta := endN - startN
    if delta < 0 {
        delta += 2.0 * math.PI
    }
    return delta
}


shadow_alpha_from_height :: proc(avgHeight: f32) -> u8 {
    atten := f32(SHADOW_ALPHA_BASE) - avgHeight * SHADOW_ALPHA_HEIGHT_SCALE
    atten = math.clamp(atten, f32(SHADOW_ALPHA_MIN), f32(SHADOW_ALPHA_BASE))
    return u8(atten)
}

make_shadow_color :: proc(source: rl.Color, avgHeight: f32) -> rl.Color {
    _ = source
    a := shadow_alpha_from_height(avgHeight)
    return rl.Color{0, 0, 0, a}
}

project_to_floor_shadow :: proc(p: Vector3, scale: IsoScale) -> Vector3 {
    if !scale.UseDirectionalShadow {
        return {p.x, p.y, 0}
    }

    l := scale.MainLightDir
    if math.abs(l.z) < SHADOW_EPSILON_LZ {
        return {p.x, p.y, 0}
    }

    t := -p.z / l.z
    return p + l * t
}

shadow_to_screen :: proc(p: Vector3, state: ^EuclidGeneralState) -> Vector2 {
    pShadow := project_to_floor_shadow(p, state^.IsoScale^)
    return iso_to_cartesian(pShadow, state^.IsoScale^)
}



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

draw_kine_points_low_cached :: proc(state: ^EuclidGeneralState) {
    for i in 0..<state^.PointSystem^.DrawCache.PointCount {
        draw_cached_point(state, &state^.PointSystem^.DrawCache.Points[i])
    }

    for i in 0..<state^.PointSystem^.DrawCache.LineCount {
        draw_cached_line(state, &state^.PointSystem^.DrawCache.Lines[i])
    }

    for i in 0..<state^.PointSystem^.DrawCache.CircleCount {
        draw_cached_circle(state, &state^.PointSystem^.DrawCache.Circles[i])
    }
}


draw_kine_points_high_cached :: proc(state: ^EuclidGeneralState) {
    for i in 0..<state^.PointSystem^.DrawCache.PenCount {
        draw_cached_pen(state, &state^.PointSystem^.DrawCache.Pens[i])
    }

    for i in 0..<state^.PointSystem^.DrawCache.CompassCount {
        draw_cached_compass(state, &state^.PointSystem^.DrawCache.Compasses[i])
    }
}


draw_kine_points_shadows_cached :: proc(state: ^EuclidGeneralState) {
    for i in 0..<state^.PointSystem^.DrawCache.PenCount {
        draw_cached_pen_shadow(state, &state^.PointSystem^.DrawCache.Pens[i])
    }

    for i in 0..<state^.PointSystem^.DrawCache.CompassCount {
        draw_cached_compass_shadow(state, &state^.PointSystem^.DrawCache.Compasses[i])
    }
}


draw_cached_point :: proc(state: ^EuclidGeneralState, p: ^kine.KinePointDraw) {
    c := iso_to_cartesian(p^.Point1, state^.IsoScale^)
    rl.DrawCircleV(c, p^.Base.BrushSize, p^.Base.Color)
}


draw_cached_line :: proc(state: ^EuclidGeneralState, l: ^kine.KineLineDraw) {
    c0 := iso_to_cartesian(l^.Point1, state^.IsoScale^)
    c1 := iso_to_cartesian(l^.Point2, state^.IsoScale^)
    rl.DrawLineEx(c0, c1, l^.Base.BrushSize, l^.Base.Color)
}


draw_cached_circle :: proc(state: ^EuclidGeneralState, c: ^kine.KineCircleDraw) {
    start := c^.Start
    finish := c^.End
    center := c^.Center

    startVec := start - center
    endVec := finish - center

    startRadius := f32(math.sqrt(startVec.x * startVec.x + startVec.y * startVec.y))
    endRadius := f32(math.sqrt(endVec.x * endVec.x + endVec.y * endVec.y))

    startTheta := f32(math.atan2(startVec.y, startVec.x))
    endTheta := f32(math.atan2(endVec.y, endVec.x))
    sweepDelta := compute_sweep_delta(startTheta, endTheta)

    prevWorld := start
    prevScreen := iso_to_cartesian(prevWorld, state^.IsoScale^)
    segCount := f32(CIRCLE_ARC_SEGMENTS)

    for i in 1..=CIRCLE_ARC_SEGMENTS {
        t := f32(i) / segCount
        theta := startTheta + sweepDelta * t
        radius := math.lerp(startRadius, endRadius, t)

        currWorld := Vector3{
            center.x + f32(math.cos(theta)) * radius,
            center.y + f32(math.sin(theta)) * radius,
            center.z,
        }

        currScreen := iso_to_cartesian(currWorld, state^.IsoScale^)
        rl.DrawLineEx(prevScreen, currScreen, c^.Base.BrushSize, c^.Base.Color)
        prevScreen = currScreen
    }
}


draw_cached_pen :: proc(state: ^EuclidGeneralState, pen: ^kine.KinePenDraw) {
    c0 := iso_to_cartesian(pen^.Joint1, state^.IsoScale^)
    c1 := iso_to_cartesian(pen^.Joint2, state^.IsoScale^)

    if pen^.Base.ActiveChild == 1 {
        active := pen^.Base.Color
        if pen^.Base.HasActiveColor {
            active = pen^.Base.ActiveColor
        }
        rl.DrawCircleV(c0, pen^.Base.BrushSize, active)
    } else if pen^.Base.ActiveChild == 2 {
        active := pen^.Base.Color
        if pen^.Base.HasActiveColor {
            active = pen^.Base.ActiveColor
        }
        rl.DrawCircleV(c1, pen^.Base.BrushSize, active)
    }

    rl.DrawLineEx(c0, c1, pen^.Base.BrushSize, pen^.Base.Color)
}


draw_outside_arc_compass_cached :: proc(
    p0, p1, p2: Vector3,
    state: ^EuclidGeneralState,
    brushSize: f32,
    color: rl.Color,
) {
    a := p0 - p1
    b := p2 - p1

    aLen := linalg.length(a)
    bLen := linalg.length(b)
    if aLen <= 0.00001 || bLen <= 0.00001 {
        return
    }

    an := a / aLen
    bn := b / bLen

    n := linalg.cross(an, bn)
    nLen := linalg.length(n)
    if nLen <= 0.00001 {
        return
    }
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

    radius := math.min(aLen, bLen) * COMPASS_TOPCIRCLE_RADIUS
    if radius <= 0 {
        return
    }

    step := thetaOut / f32(COMPASS_TOPCIRCLE_SEGMENTS)

    prev3d := p1 + u * radius
    prev := iso_to_cartesian(prev3d, state^.IsoScale^)

    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := u * math.cos(t) + v * math.sin(t)
        curr3d := p1 + dir * radius
        curr := iso_to_cartesian(curr3d, state^.IsoScale^)

        rl.DrawLineEx(prev, curr, brushSize, color)
        prev = curr
    }
}


draw_cached_compass :: proc(state: ^EuclidGeneralState, comp: ^kine.KineCompassDraw) {
    c0 := iso_to_cartesian(comp^.Joint1, state^.IsoScale^)
    c1 := iso_to_cartesian(comp^.Pivot, state^.IsoScale^)
    c2 := iso_to_cartesian(comp^.Joint2, state^.IsoScale^)

    if comp^.Base.ActiveChild == 1 {
        active := comp^.Base.Color
        if comp^.Base.HasActiveColor {
            active = comp^.Base.ActiveColor
        }
        rl.DrawCircleV(c0, comp^.Base.BrushSize, active)
    } else if comp^.Base.ActiveChild == 3 {
        active := comp^.Base.Color
        if comp^.Base.HasActiveColor {
            active = comp^.Base.ActiveColor
        }
        rl.DrawCircleV(c2, comp^.Base.BrushSize, active)
    }

    rl.DrawLineEx(c0, c1, comp^.Base.BrushSize, comp^.Base.Color)
    rl.DrawLineEx(c1, c2, comp^.Base.BrushSize, comp^.Base.Color)

    draw_outside_arc_compass_cached(
        comp^.Joint1,
        comp^.Pivot,
        comp^.Joint2,
        state,
        comp^.Base.BrushSize,
        comp^.Base.Color,
    )
}


draw_cached_pen_shadow :: proc(state: ^EuclidGeneralState, pen: ^kine.KinePenDraw) {
    s0 := shadow_to_screen(pen^.Joint1, state)
    s1 := shadow_to_screen(pen^.Joint2, state)

    avgHeight := (pen^.Joint1.z + pen^.Joint2.z) * 0.5
    shadowColor := make_shadow_color(pen^.Base.Color, avgHeight)
    thickness := math.max(pen^.Base.BrushSize * 0.8, SHADOW_MIN_THICKNESS)

    rl.DrawLineEx(s0, s1, thickness, shadowColor)
}


draw_outside_arc_compass_shadow_cached :: proc(
    p0, p1, p2: Vector3,
    state: ^EuclidGeneralState,
    brushSize: f32,
    color: rl.Color,
) {
    if brushSize <= 0 {
        return
    }

    a := p0 - p1
    b := p2 - p1

    aLen := linalg.length(a)
    bLen := linalg.length(b)
    if aLen <= 0.00001 || bLen <= 0.00001 {
        return
    }

    an := a / aLen
    bn := b / bLen

    n := linalg.cross(an, bn)
    nLen := linalg.length(n)
    if nLen <= 0.00001 {
        return
    }
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

    radius := math.min(aLen, bLen) * COMPASS_TOPCIRCLE_RADIUS
    if radius <= 0 {
        return
    }

    step := thetaOut / f32(COMPASS_TOPCIRCLE_SEGMENTS)

    prev3d := p1 + u * radius
    prev := shadow_to_screen(prev3d, state)

    for i in 1..=COMPASS_TOPCIRCLE_SEGMENTS {
        t := step * f32(i)
        dir := u * math.cos(t) + v * math.sin(t)
        curr3d := p1 + dir * radius
        curr := shadow_to_screen(curr3d, state)

        rl.DrawLineEx(prev, curr, brushSize, color)
        prev = curr
    }
}


draw_cached_compass_shadow :: proc(state: ^EuclidGeneralState, comp: ^kine.KineCompassDraw) {
    s0 := shadow_to_screen(comp^.Joint1, state)
    s1 := shadow_to_screen(comp^.Pivot, state)
    s2 := shadow_to_screen(comp^.Joint2, state)

    avgHeight := (comp^.Joint1.z + comp^.Pivot.z + comp^.Joint2.z) / 3.0
    shadowColor := make_shadow_color(comp^.Base.Color, avgHeight)
    thickness := math.max(comp^.Base.BrushSize * 0.8, SHADOW_MIN_THICKNESS)

    rl.DrawLineEx(s0, s1, thickness, shadowColor)
    rl.DrawLineEx(s1, s2, thickness, shadowColor)

    draw_outside_arc_compass_shadow_cached(
        comp^.Joint1,
        comp^.Pivot,
        comp^.Joint2,
        state,
        thickness,
        shadowColor,
    )
}
