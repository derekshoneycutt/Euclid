package view

import "../kine"
import "../core"
import "../files"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

CIRCLE_ARC_SEGMENTS :: 96

COMPASS_TOPCIRCLE_SEGMENTS :: 30
COMPASS_TOPCIRCLE_VECTORS :: COMPASS_TOPCIRCLE_SEGMENTS + 1
COMPASS_TOPCIRCLE_RADIUS :: 0.25

SHADOW_MIN_THICKNESS :: 0.5
SHADOW_ALPHA_BASE :: 90
SHADOW_ALPHA_MIN :: 35
SHADOW_ALPHA_HEIGHT_SCALE :: 35.0
SHADOW_EPSILON_LZ :: 0.0001

STROKE3D_AMBIENT :: 0.28
STROKE3D_DIFFUSE :: 1.05
STROKE3D_SPECULAR_STRENGTH :: 0.26
STROKE3D_SPECULAR_POWER :: 18.0


init_stroke3d_shader :: proc(state: ^EuclidGeneralState) {
    s := &state^.Stroke3D

    vertex_path := files.packaged_asset_path("shaders/stroke3d.vs", context.temp_allocator)
    fragment_path := files.packaged_asset_path("shaders/stroke3d.fs", context.temp_allocator)
    if len(vertex_path) == 0 || len(fragment_path) == 0 {
        fmt.println("stroke3d shader paths could not be resolved from assets.pkg; pen/compass 3D shading disabled")
        s^.Ready = false
        return
    }

    vertex_cstr := strings.clone_to_cstring(vertex_path, context.temp_allocator)
    fragment_cstr := strings.clone_to_cstring(fragment_path, context.temp_allocator)

    if !rl.FileExists(vertex_cstr) || !rl.FileExists(fragment_cstr) {
        fmt.println("stroke3d shader files not found; pen/compass 3D shading disabled")
        fmt.println("stroke3d expected paths: vs=", vertex_path, " fs=", fragment_path)
        s^.Ready = false
        return
    }

    s^.Shader = rl.LoadShader(vertex_cstr, fragment_cstr)
    if s^.Shader.id == 0 {
        fmt.println("stroke3d shader failed to load; pen/compass 3D shading disabled")
        s^.Ready = false
        return
    }

    s^.LocLightDir = rl.GetShaderLocation(s^.Shader, "uLightDirView")
    s^.LocAmbient = rl.GetShaderLocation(s^.Shader, "uAmbient")
    s^.LocDiffuse = rl.GetShaderLocation(s^.Shader, "uDiffuse")
    s^.LocSpecularStrength = rl.GetShaderLocation(s^.Shader, "uSpecularStrength")
    s^.LocSpecularPower = rl.GetShaderLocation(s^.Shader, "uSpecularPower")
    s^.LocP0 = rl.GetShaderLocation(s^.Shader, "uP0")
    s^.LocP1 = rl.GetShaderLocation(s^.Shader, "uP1")
    s^.LocRadius = rl.GetShaderLocation(s^.Shader, "uRadius")
    s^.LocViewportHeight = rl.GetShaderLocation(s^.Shader, "uViewportHeight")

    if s^.LocP0 < 0 || s^.LocP1 < 0 || s^.LocRadius < 0 || s^.LocViewportHeight < 0 {
        fmt.println("stroke3d shader missing required uniforms; pen/compass 3D shading disabled")
        fmt.println("stroke3d uniform locations p0=", s^.LocP0, " p1=", s^.LocP1,
            " radius=", s^.LocRadius, " viewportHeight=", s^.LocViewportHeight)
        rl.UnloadShader(s^.Shader)
        s^.Ready = false
        return
    }

    s^.Ready = true
}


shutdown_stroke3d_shader :: proc(state: ^EuclidGeneralState) {
    s := &state^.Stroke3D

    if !s^.Ready {
        return
    }

    rl.UnloadShader(s^.Shader)
    s^.Ready = false
}


set_stroke3d_uniform_float :: #force_inline proc(state: ^EuclidGeneralState, location: i32, value: f32) {
    if location < 0 {
        return
    }
    localValue := value
    rl.SetShaderValue(state^.Stroke3D.Shader, location, &localValue, .FLOAT)
}


set_stroke3d_uniform_vec2 :: #force_inline proc(state: ^EuclidGeneralState, location: i32, value: Vector2) {
    if location < 0 {
        return
    }
    vecData := [2]f32{value.x, value.y}
    rl.SetShaderValue(state^.Stroke3D.Shader, location, &vecData[0], .VEC2)
}


get_stroke3d_render_scale :: #force_inline proc() -> Vector2 {
    screenW := f32(rl.GetScreenWidth())
    screenH := f32(rl.GetScreenHeight())
    renderW := f32(rl.GetRenderWidth())
    renderH := f32(rl.GetRenderHeight())

    sx := f32(1.0)
    sy := f32(1.0)

    if screenW > 0 && renderW > 0 {
        sx = renderW / screenW
    }
    if screenH > 0 && renderH > 0 {
        sy = renderH / screenH
    }

    return Vector2{sx, sy}
}


set_stroke3d_segment :: #force_inline proc(state: ^EuclidGeneralState, p0, p1: Vector2, thickness: f32) {
    s := &state^.Stroke3D
    scale := get_stroke3d_render_scale()
    p0Scaled := Vector2{p0.x * scale.x, p0.y * scale.y}
    p1Scaled := Vector2{p1.x * scale.x, p1.y * scale.y}
    avgScale := (scale.x + scale.y) * 0.5

    set_stroke3d_uniform_vec2(state, s^.LocP0, p0Scaled)
    set_stroke3d_uniform_vec2(state, s^.LocP1, p1Scaled)
    set_stroke3d_uniform_float(state, s^.LocRadius, thickness * 0.5 * avgScale)
}


draw_stroke3d_segment :: #force_inline proc(state: ^EuclidGeneralState, p0, p1: Vector2, thickness: f32, color: rl.Color) {
    s := &state^.Stroke3D
    if s^.Ready {
        rlgl.DrawRenderBatchActive()
        set_stroke3d_segment(state, p0, p1, thickness)
    }
    rl.DrawLineEx(p0, p1, thickness, color)
}


begin_stroke3d_mode :: proc(state: ^EuclidGeneralState) {
    s := &state^.Stroke3D

    if !s^.Ready {
        return
    }

    light := -state^.IsoScale^.MainLightDir
    light = linalg.normalize(light)

    lightDirData := [3]f32{light.x, light.y, light.z}
    if s^.LocLightDir >= 0 {
        rl.SetShaderValue(s^.Shader, s^.LocLightDir, &lightDirData[0], .VEC3)
    }

    set_stroke3d_uniform_float(state, s^.LocAmbient, STROKE3D_AMBIENT)
    set_stroke3d_uniform_float(state, s^.LocDiffuse, STROKE3D_DIFFUSE)
    set_stroke3d_uniform_float(state, s^.LocSpecularStrength, STROKE3D_SPECULAR_STRENGTH)
    set_stroke3d_uniform_float(state, s^.LocSpecularPower, STROKE3D_SPECULAR_POWER)
    set_stroke3d_uniform_float(state, s^.LocViewportHeight, f32(rl.GetRenderHeight()))

    rl.BeginShaderMode(s^.Shader)
}


end_stroke3d_mode :: proc(state: ^EuclidGeneralState) {
    if !state^.Stroke3D.Ready {
        return
    }
    rlgl.DrawRenderBatchActive()
    rl.EndShaderMode()
}

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



draw_drawing_surface :: proc(state: ^EuclidGeneralState) {
    room := state^.DrawSurface

    surfaceZeros : Vector3 = room^.Zeros + { room.EdgeSize, room.EdgeSize, 0 }
    surfaceRightUp : Vector3 = room^.RightUp + { -room.EdgeSize, room.EdgeSize, 0 }
    surfaceLeftDown : Vector3 = room^.LeftDown + { room.EdgeSize, -room.EdgeSize, 0 }
    surfaceRightDown : Vector3 = room^.RightDown + { -room.EdgeSize, -room.EdgeSize, 0 }

    rl.DrawTriangle(iso_to_cartesian(room.Zeros, state^.IsoScale^),
        iso_to_cartesian(room.RightUp, state^.IsoScale^),
        iso_to_cartesian(room.LeftDown, state^.IsoScale^), room.EdgeColor)
    rl.DrawTriangle(iso_to_cartesian(room^.RightDown, state^.IsoScale^),
        iso_to_cartesian(room.LeftDown, state^.IsoScale^),
        iso_to_cartesian(room.RightUp, state^.IsoScale^), room.EdgeColor)
    rl.DrawTriangle(iso_to_cartesian(surfaceZeros, state^.IsoScale^),
        iso_to_cartesian(surfaceRightUp, state^.IsoScale^),
        iso_to_cartesian(surfaceLeftDown, state^.IsoScale^), room.Color)
    rl.DrawTriangle(iso_to_cartesian(surfaceRightDown, state^.IsoScale^),
        iso_to_cartesian(surfaceLeftDown, state^.IsoScale^),
        iso_to_cartesian(surfaceRightUp, state^.IsoScale^), room.Color)
}

draw_kine_points_low_cached :: proc(state: ^EuclidGeneralState) {
    for i in 0..<state^.PointSystem^.DrawCache.ItemCount {
        item := &state^.PointSystem^.DrawCache.Items[i]
        switch &itemTyped in item {
            case core.KineLabelDraw:
                draw_cached_label(state, &itemTyped)
            case core.KinePointDraw:
                draw_cached_point(state, &itemTyped)
            case core.KineLineDraw:
                draw_cached_line(state, &itemTyped)
            case core.KineCircleDraw:
                draw_cached_circle(state, &itemTyped)
            case core.KineFilledCircleDraw:
                draw_cached_filledcircle(state, &itemTyped)
            case core.KineTriangleDraw:
                draw_cached_triangle(state, &itemTyped)
            case core.KineSquareDraw:
                draw_cached_square(state, &itemTyped)
            case core.KinePentagonDraw:
                draw_cached_pentagon(state, &itemTyped)
            case:
                continue
        }
    }
}


draw_kine_points_high_cached :: proc(state: ^EuclidGeneralState) {
    if state^.PointSystem^.DrawCache.DrawPen {
        draw_cached_pen_active_dot(state, &state^.PointSystem^.DrawCache.Pen)
    }
    if state^.PointSystem^.DrawCache.DrawCompass {
        draw_cached_compass_active_dot(state, &state^.PointSystem^.DrawCache.Compass)
    }

    begin_stroke3d_mode(state)

    if state^.PointSystem^.DrawCache.DrawPen {
        draw_cached_pen(state, &state^.PointSystem^.DrawCache.Pen)
    }
    if state^.PointSystem^.DrawCache.DrawCompass {
        draw_cached_compass(state, &state^.PointSystem^.DrawCache.Compass)
    }

    end_stroke3d_mode(state)
}


draw_kine_points_shadows_cached :: proc(state: ^EuclidGeneralState) {
    if state^.PointSystem^.DrawCache.DrawPen {
        draw_cached_pen_shadow(state, &state^.PointSystem^.DrawCache.Pen)
    }
    if state^.PointSystem^.DrawCache.DrawCompass {
        draw_cached_compass_shadow(state, &state^.PointSystem^.DrawCache.Compass)
    }
}


draw_cached_label :: proc(state: ^EuclidGeneralState, p: ^kine.KineLabelDraw) {
    c := iso_to_cartesian(p^.Point1, state^.IsoScale^)
    font := rl.GetFontDefault()
    rl.DrawTextCodepoint(font, p^.Label, c, p^.BrushSize, p^.Color)
}


draw_cached_point :: proc(state: ^EuclidGeneralState, p: ^kine.KinePointDraw) {
    c := iso_to_cartesian(p^.Point1, state^.IsoScale^)
    rl.DrawCircleV(c, p^.BrushSize, p^.Color)
}


draw_cached_line :: proc(state: ^EuclidGeneralState, l: ^kine.KineLineDraw) {
    c0 := iso_to_cartesian(l^.Point1, state^.IsoScale^)
    c1 := iso_to_cartesian(l^.Point2, state^.IsoScale^)
    rl.DrawLineEx(c0, c1, l^.BrushSize, l^.Color)
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
    sweepDelta := compute_sweep_delta(startTheta, endTheta) + c^.Offset

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
        rl.DrawLineEx(prevScreen, currScreen, c^.BrushSize, c^.Color)
        prevScreen = currScreen
    }
}

draw_cached_filledcircle :: proc(state: ^EuclidGeneralState, c: ^kine.KineFilledCircleDraw) {
    start := c^.Start
    finish := c^.End
    center := c^.Center
    isocenter := iso_to_cartesian(center, state^.IsoScale^)

    startVec := start - center
    endVec := finish - center

    startRadius := f32(math.sqrt(startVec.x * startVec.x + startVec.y * startVec.y))
    endRadius := f32(math.sqrt(endVec.x * endVec.x + endVec.y * endVec.y))

    startTheta := f32(math.atan2(startVec.y, startVec.x))
    endTheta := f32(math.atan2(endVec.y, endVec.x))
    sweepDelta := compute_sweep_delta(startTheta, endTheta)

    points: [CIRCLE_ARC_SEGMENTS + 2]rl.Vector2
    points[0] = isocenter
    points[1] = iso_to_cartesian(start, state^.IsoScale^)

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

        points[i + 1] = iso_to_cartesian(currWorld, state^.IsoScale^)
    }

    rl.DrawTriangleFan(&points[0], len(points), c^.Color)
}


draw_cached_triangle :: proc(state: ^EuclidGeneralState, l: ^kine.KineTriangleDraw) {
    c0 := iso_to_cartesian(l^.Point1, state^.IsoScale^)
    c1 := iso_to_cartesian(l^.Point2, state^.IsoScale^)
    c2 := iso_to_cartesian(l^.Point3, state^.IsoScale^)
    rl.DrawTriangle(c0, c1, c2, l^.Color)
}


draw_cached_square :: proc(state: ^EuclidGeneralState, l: ^kine.KineSquareDraw) {
    c0 := iso_to_cartesian(l^.Point1, state^.IsoScale^)
    c1 := iso_to_cartesian(l^.Point2, state^.IsoScale^)
    c2 := iso_to_cartesian(l^.Point3, state^.IsoScale^)
    c3 := iso_to_cartesian(l^.Point4, state^.IsoScale^)
    rl.DrawTriangle(c0, c1, c2, l^.Color)
    rl.DrawTriangle(c0, c2, c3, l^.Color)
}


draw_cached_pentagon :: proc(state: ^EuclidGeneralState, l: ^kine.KinePentagonDraw) {
    c0 := iso_to_cartesian(l^.Point1, state^.IsoScale^)
    c1 := iso_to_cartesian(l^.Point2, state^.IsoScale^)
    c2 := iso_to_cartesian(l^.Point3, state^.IsoScale^)
    c3 := iso_to_cartesian(l^.Point4, state^.IsoScale^)
    c4 := iso_to_cartesian(l^.Point5, state^.IsoScale^)
    rl.DrawTriangle(c0, c1, c2, l^.Color)
    rl.DrawTriangle(c0, c2, c3, l^.Color)
    rl.DrawTriangle(c0, c3, c4, l^.Color)
}


draw_cached_pen :: proc(state: ^EuclidGeneralState, pen: ^kine.KinePenDraw) {
    c0 := iso_to_cartesian(pen^.Joint1, state^.IsoScale^)
    c1 := iso_to_cartesian(pen^.Joint2, state^.IsoScale^)

    draw_stroke3d_segment(state, c0, c1, pen^.BrushSize, pen^.Color)
}


draw_cached_pen_active_dot :: proc(state: ^EuclidGeneralState, pen: ^kine.KinePenDraw) {
    c0 := iso_to_cartesian(pen^.Joint1, state^.IsoScale^)
    c1 := iso_to_cartesian(pen^.Joint2, state^.IsoScale^)

    if pen^.ActiveChild == 1 {
        active := pen^.Color
        if pen^.HasActiveColor {
            active = pen^.ActiveColor
        }
        rl.DrawCircleV(c0, pen^.BrushSize, active)
    } else if pen^.ActiveChild == 2 {
        active := pen^.Color
        if pen^.HasActiveColor {
            active = pen^.ActiveColor
        }
        rl.DrawCircleV(c1, pen^.BrushSize, active)
    }
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

        draw_stroke3d_segment(state, prev, curr, brushSize, color)
        prev = curr
    }
}


draw_cached_compass :: proc(state: ^EuclidGeneralState, comp: ^kine.KineCompassDraw) {
    c0 := iso_to_cartesian(comp^.Joint1, state^.IsoScale^)
    c1 := iso_to_cartesian(comp^.Pivot, state^.IsoScale^)
    c2 := iso_to_cartesian(comp^.Joint2, state^.IsoScale^)

    draw_stroke3d_segment(state, c0, c1, comp^.BrushSize, comp^.Color)
    draw_stroke3d_segment(state, c1, c2, comp^.BrushSize, comp^.Color)

    draw_outside_arc_compass_cached(
        comp^.Joint1,
        comp^.Pivot,
        comp^.Joint2,
        state,
        comp^.BrushSize,
        comp^.Color,
    )
}


draw_cached_compass_active_dot :: proc(state: ^EuclidGeneralState, comp: ^kine.KineCompassDraw) {
    c0 := iso_to_cartesian(comp^.Joint1, state^.IsoScale^)
    c2 := iso_to_cartesian(comp^.Joint2, state^.IsoScale^)

    if comp^.ActiveChild == 1 {
        active := comp^.Color
        if comp^.HasActiveColor {
            active = comp^.ActiveColor
        }
        rl.DrawCircleV(c0, comp^.BrushSize, active)
    } else if comp^.ActiveChild == 3 {
        active := comp^.Color
        if comp^.HasActiveColor {
            active = comp^.ActiveColor
        }
        rl.DrawCircleV(c2, comp^.BrushSize, active)
    }
}


draw_cached_pen_shadow :: proc(state: ^EuclidGeneralState, pen: ^kine.KinePenDraw) {
    s0 := shadow_to_screen(pen^.Joint1, state)
    s1 := shadow_to_screen(pen^.Joint2, state)

    avgHeight := (pen^.Joint1.z + pen^.Joint2.z) * 0.5
    shadowColor := make_shadow_color(pen^.Color, avgHeight)
    thickness := math.max(pen^.BrushSize * 0.8, SHADOW_MIN_THICKNESS)

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
    shadowColor := make_shadow_color(comp^.Color, avgHeight)
    thickness := math.max(comp^.BrushSize * 0.8, SHADOW_MIN_THICKNESS)

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
